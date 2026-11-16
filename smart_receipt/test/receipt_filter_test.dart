import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/models/receipt_filter.dart';
import 'package:smart_receipt/models/receipt_model.dart';

String _categoryName(int id) => switch (id) {
      1 => 'Makanan',
      2 => 'Minuman',
      _ => 'Lainnya',
    };

Receipt _receipt({
  int? id = 1,
  String store = 'Indomaret',
  DateTime? date,
  double? total,
  int categoryId = 1,
  String itemName = 'Indomie Goreng',
}) {
  final DateTime stamp = date ?? DateTime(2026, 11, 10, 19, 14);
  final double amount = total ?? 7000;
  return Receipt(
    id: id,
    storeName: store,
    transactionDate: stamp,
    totalAmount: amount,
    taxAmount: 0,
    subtotal: amount,
    paymentMethod: 'Tunai',
    status: 'saved',
    createdAt: stamp,
    transactions: <Transaction>[
      Transaction(
        receiptId: id ?? 0,
        categoryId: categoryId,
        itemName: itemName,
        quantity: 1,
        unitPrice: amount,
        totalPrice: amount,
        discount: 0,
        createdAt: stamp,
      ),
    ],
  );
}

List<String> _stores(List<Receipt> receipts) =>
    receipts.map((Receipt r) => r.storeName).toList();

void main() {
  test('an empty filter keeps every receipt', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(store: 'Indomaret'),
      _receipt(id: 2, store: 'Alfamart', categoryId: 2),
    ];

    expect(const ReceiptFilter().apply(receipts, _categoryName), receipts);
  });

  test('search text matches the store name and item names', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(store: 'Indomaret'),
      _receipt(id: 2, store: 'Alfamart', itemName: 'Aqua 600ml'),
    ];

    expect(
      _stores(const ReceiptFilter(query: 'indo').apply(receipts, _categoryName)),
      <String>['Indomaret'],
    );
    expect(
      _stores(const ReceiptFilter(query: 'AQUA').apply(receipts, _categoryName)),
      <String>['Alfamart'],
    );
  });

  test('category keeps receipts that contain an item in that category', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(store: 'Indomaret', categoryId: 1),
      _receipt(id: 2, store: 'Alfamart', categoryId: 2),
    ];

    expect(
      _stores(
        const ReceiptFilter(category: 'Minuman').apply(receipts, _categoryName),
      ),
      <String>['Alfamart'],
    );
  });

  test('a day range includes both ends whatever the time of day', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(date: DateTime(2026, 11, 9, 23, 59), store: 'Sebelum'),
      _receipt(date: DateTime(2026, 11, 10, 8), store: 'Awal'),
      _receipt(date: DateTime(2026, 11, 15, 19, 14), store: 'Akhir'),
      _receipt(date: DateTime(2026, 11, 16, 0, 1), store: 'Sesudah'),
    ];

    final ReceiptFilter filter = ReceiptFilter(
      range: DateTimeRange(
        start: DateTime(2026, 11, 10),
        end: DateTime(2026, 11, 15),
      ),
    );

    expect(
      _stores(filter.apply(receipts, _categoryName)),
      <String>['Awal', 'Akhir'],
    );
  });

  test('nominal bounds are inclusive on the printed total', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(total: 5000, store: 'Kecil'),
      _receipt(total: 25000, store: 'Sedang'),
      _receipt(total: 100000, store: 'Besar'),
    ];

    expect(
      _stores(
        const ReceiptFilter(minAmount: 25000).apply(receipts, _categoryName),
      ),
      <String>['Sedang', 'Besar'],
    );
    expect(
      _stores(
        const ReceiptFilter(maxAmount: 25000).apply(receipts, _categoryName),
      ),
      <String>['Kecil', 'Sedang'],
    );
    expect(
      _stores(
        const ReceiptFilter(minAmount: 5000, maxAmount: 25000)
            .apply(receipts, _categoryName),
      ),
      <String>['Kecil', 'Sedang'],
    );
  });

  test('the store filter is exact, not a substring of the search text', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(store: 'Indomaret'),
      _receipt(id: 2, store: 'Alfamart', itemName: 'Indomie Goreng'),
    ];

    expect(
      _stores(
        const ReceiptFilter(store: 'indomaret').apply(receipts, _categoryName),
      ),
      <String>['Indomaret'],
    );
  });

  test('every refinement has to match', () {
    final List<Receipt> receipts = <Receipt>[
      _receipt(store: 'Indomaret', total: 25000, date: DateTime(2026, 11, 10)),
      _receipt(
        id: 2,
        store: 'Indomaret',
        total: 25000,
        date: DateTime(2026, 10, 10),
      ),
      _receipt(
        id: 3,
        store: 'Alfamart',
        total: 25000,
        date: DateTime(2026, 11, 10),
      ),
    ];

    final ReceiptFilter filter = ReceiptFilter(
      store: 'Indomaret',
      minAmount: 20000,
      range: DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      ),
    );

    expect(
      filter.apply(receipts, _categoryName).map((Receipt r) => r.id).toList(),
      <int?>[1],
    );
  });

  test('advancedCount treats min and max as one refinement', () {
    expect(const ReceiptFilter().advancedCount, 0);
    expect(const ReceiptFilter(minAmount: 1).advancedCount, 1);
    expect(const ReceiptFilter(minAmount: 1, maxAmount: 2).advancedCount, 1);
    expect(
      ReceiptFilter(
        minAmount: 1,
        maxAmount: 2,
        store: 'Indomaret',
        range: DateTimeRange(
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 2),
        ),
      ).advancedCount,
      3,
    );
  });

  test('summary reads like the on-screen filter bar', () {
    expect(
      ReceiptFilter(
        range: DateTimeRange(
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 16),
        ),
        minAmount: 10000,
        store: 'Indomaret',
      ).summary,
      '1 Nov 2026 – 16 Nov 2026 · ≥ Rp10.000 · Indomaret',
    );

    expect(const ReceiptFilter(maxAmount: 50000).summary, '≤ Rp50.000');
    expect(
      const ReceiptFilter(minAmount: 5000, maxAmount: 50000).summary,
      'Rp5.000 – Rp50.000',
    );
    expect(
      ReceiptFilter(
        range: DateTimeRange(
          start: DateTime(2026, 11, 16),
          end: DateTime(2026, 11, 16),
        ),
      ).summary,
      '16 Nov 2026',
    );
  });

  test('clearing advanced filters keeps the search text and category', () {
    final ReceiptFilter filter = ReceiptFilter(
      query: 'indomie',
      category: 'Makanan',
      minAmount: 10000,
    ).clearAdvanced();

    expect(filter.query, 'indomie');
    expect(filter.category, 'Makanan');
    expect(filter.hasAdvancedFilters, isFalse);
  });
}
