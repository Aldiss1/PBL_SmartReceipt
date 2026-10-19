import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/models/receipt_model.dart';
import 'package:smart_receipt/services/spending_analytics.dart';
import 'package:smart_receipt/services/spending_forecaster.dart';

Receipt _receipt({
  required int id,
  required DateTime date,
  required double total,
  Map<int, double> items = const <int, double>{1: 1000},
  DateTime? createdAt,
}) {
  return Receipt(
    id: id,
    storeName: 'Toko $id',
    transactionDate: date,
    totalAmount: total,
    taxAmount: 0,
    subtotal: total,
    createdAt: createdAt ?? date,
    transactions: <Transaction>[
      for (final MapEntry<int, double> item in items.entries)
        Transaction(
          receiptId: id,
          categoryId: item.key,
          itemName: 'Item',
          quantity: 1,
          unitPrice: item.value,
          totalPrice: item.value,
          discount: 0,
          createdAt: date,
        ),
    ],
  );
}

void main() {
  group('SpendingAnalytics', () {
    test('monthlyTotals uses transactionDate and zero-fills empty months', () {
      final DateTime now = DateTime(2026, 10, 19);
      final List<Receipt> receipts = <Receipt>[
        // Entered late (createdAt in October) but belongs to August.
        _receipt(
          id: 1,
          date: DateTime(2026, 8, 31, 23, 30),
          total: 100000,
          createdAt: DateTime(2026, 10, 1),
        ),
        _receipt(id: 2, date: DateTime(2026, 10, 2), total: 50000),
      ];

      final List<MonthlyTotal> series =
          SpendingAnalytics.monthlyTotals(receipts, months: 6, now: now);

      expect(series.length, 6);
      expect(series.first.month, DateTime(2026, 5));
      expect(series.last.month, DateTime(2026, 10));
      // May, June, July empty; August has the late-entered receipt.
      expect(series[0].total, 0);
      expect(series[3].total, 100000);
      expect(series[4].total, 0);
      expect(series[5].total, 50000);
    });

    test('totalBetween includes the first instant and excludes the boundary', () {
      final List<Receipt> receipts = <Receipt>[
        _receipt(id: 1, date: DateTime(2026, 10, 1), total: 1000),
        _receipt(id: 2, date: DateTime(2026, 10, 31, 23, 59), total: 2000),
        _receipt(id: 3, date: DateTime(2026, 11, 1), total: 4000),
      ];

      expect(
        SpendingAnalytics.totalBetween(
          receipts,
          from: DateTime(2026, 10, 1),
          toExclusive: DateTime(2026, 11, 1),
        ),
        3000,
      );
    });

    test('byCategory sums item totals and falls back to Lainnya', () {
      final List<Receipt> receipts = <Receipt>[
        _receipt(
          id: 1,
          date: DateTime(2026, 10, 5),
          total: 30000,
          items: <int, double>{1: 20000, 3: 10000},
        ),
        _receipt(
          id: 2,
          date: DateTime(2026, 10, 6),
          total: 5000,
          items: <int, double>{99: 5000},
        ),
      ];

      final Map<String, double> byCategory = SpendingAnalytics.byCategory(
        receipts,
        <int, String>{1: 'Makanan', 3: 'Rumah Tangga'},
        from: DateTime(2026, 10, 1),
        toExclusive: DateTime(2026, 11, 1),
      );

      expect(byCategory['Makanan'], 20000);
      expect(byCategory['Rumah Tangga'], 10000);
      expect(byCategory['Lainnya'], 5000);
    });

    test('trimLeadingEmpty drops months before the first receipt', () {
      final List<MonthlyTotal> trimmed = SpendingAnalytics.trimLeadingEmpty(
        <MonthlyTotal>[
          MonthlyTotal(month: DateTime(2026, 5), total: 0),
          MonthlyTotal(month: DateTime(2026, 6), total: 0),
          MonthlyTotal(month: DateTime(2026, 7), total: 120000),
          MonthlyTotal(month: DateTime(2026, 8), total: 130000),
        ],
      );

      expect(trimmed.length, 2);
      expect(trimmed.first.month, DateTime(2026, 7));
    });

    test('trimLeadingEmpty returns nothing when all months are empty', () {
      expect(
        SpendingAnalytics.trimLeadingEmpty(<MonthlyTotal>[
          MonthlyTotal(month: DateTime(2026, 9), total: 0),
        ]),
        isEmpty,
      );
    });
  });

  group('SpendingForecaster', () {
    List<MonthlyTotal> series(List<double> totals) => <MonthlyTotal>[
          for (int i = 0; i < totals.length; i++)
            MonthlyTotal(month: DateTime(2026, 5 + i), total: totals[i]),
        ];

    test('recovers a perfect linear trend and predicts the next month', () {
      final ForecastResult result = SpendingForecaster.forecast(
        series(<double>[100000, 150000, 200000, 250000]),
      );

      expect(result.hasEnoughData, isTrue);
      expect(result.sampleCount, 4);
      expect(result.slope, closeTo(50000, 1e-6));
      expect(result.predicted, closeTo(300000, 1e-6));
      expect(result.mae, closeTo(0, 1e-6));
      expect(result.rmse, closeTo(0, 1e-6));
      expect(result.rSquared, closeTo(1, 1e-9));
      expect(result.changeFromLastMonth, closeTo(0.2, 1e-9));
    });

    test('reports real errors for noisy data', () {
      final ForecastResult result = SpendingForecaster.forecast(
        series(<double>[100000, 300000, 200000, 400000]),
      );

      expect(result.hasEnoughData, isTrue);
      expect(result.mae, greaterThan(0));
      expect(result.rmse, greaterThanOrEqualTo(result.mae));
      expect(result.rSquared, inInclusiveRange(0, 1));
    });

    test('requires at least three months of data', () {
      final ForecastResult result = SpendingForecaster.forecast(
        series(<double>[100000, 200000]),
      );

      expect(result.hasEnoughData, isFalse);
      expect(result.sampleCount, 2);
      expect(result.predicted, 0);
    });

    test('never predicts a negative amount', () {
      final ForecastResult result = SpendingForecaster.forecast(
        series(<double>[900000, 500000, 100000]),
      );

      expect(result.predicted, greaterThanOrEqualTo(0));
    });

    test('flat history yields a flat forecast and full R²', () {
      final ForecastResult result = SpendingForecaster.forecast(
        series(<double>[200000, 200000, 200000]),
      );

      expect(result.slope, closeTo(0, 1e-9));
      expect(result.predicted, closeTo(200000, 1e-6));
      expect(result.rSquared, 1);
      expect(result.changeFromLastMonth, 0);
    });

    test('changeFromLastMonth is null when the last month is zero', () {
      final ForecastResult result = SpendingForecaster.forecast(
        series(<double>[100000, 100000, 0]),
      );

      expect(result.changeFromLastMonth, isNull);
    });
  });
}
