import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_receipt/models/models.dart';
import 'package:smart_receipt/providers/receipt_provider.dart';
import 'package:smart_receipt/screens/transaction_history.dart';
import 'package:smart_receipt/services/receipt_image_store.dart';
import 'package:smart_receipt/widgets/app_widgets.dart';

import 'support/fake_receipt_database.dart';

void main() {
  late FakeReceiptDatabase helper;
  late ReceiptProvider provider;

  setUp(() async {
    helper = FakeReceiptDatabase();
    provider = ReceiptProvider(
      dbHelper: helper,
      imageStore: ReceiptImageStore(),
    );

    // Three receipts that differ in store, month and total, so each filter can
    // be judged by which rows survive:
    //   7.000  Indomaret, 10 Nov
    //   5.500  Alfamart, 15 Nov
    //  25.000  Indomaret,  1 Okt
    await provider.addReceipt(sampleReceipt(
      store: 'Indomaret',
      date: DateTime(2026, 11, 10, 19, 14),
      categoryId: 1,
      itemName: 'Indomie Goreng',
      quantity: 2,
      unitPrice: 3500,
    ));
    await provider.addReceipt(sampleReceipt(
      store: 'Alfamart',
      date: DateTime(2026, 11, 15, 9),
      categoryId: 2,
      itemName: 'Aqua 600ml',
      quantity: 1,
      unitPrice: 5500,
    ));
    await provider.addReceipt(sampleReceipt(
      store: 'Indomaret',
      date: DateTime(2026, 10, 1, 12),
      categoryId: 2,
      itemName: 'Susu Ultra',
      quantity: 1,
      unitPrice: 25000,
    ));
  });

  Future<void> pumpHistory(WidgetTester tester) async {
    // A tall phone surface: the sheet is taller than the default 800x600 test
    // window, and a tap on an off-screen button would fail as not hit-testable.
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ReceiptProvider>.value(
        value: provider,
        child: const MaterialApp(home: TransactionHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
  }

  Future<void> applySheet(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(PrimaryButton, 'Terapkan Filter'));
    await tester.pumpAndSettle();
  }

  /// Pill inside the filter sheet, as opposed to a chip on the screen behind it.
  Finder sheetPill(String label) => find.descendant(
        of: find.byType(FilterPill),
        matching: find.text(label),
      );

  testWidgets('a nominal bound narrows the list and explains itself', (
    WidgetTester tester,
  ) async {
    await pumpHistory(tester);
    expect(find.text('3 transaksi tercatat'), findsOneWidget);

    await openSheet(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Minimal'), '10000');
    await applySheet(tester);

    // Only the 25.000 receipt is left, so the 7.000 and 5.500 rows are gone.
    expect(find.text('Alfamart'), findsNothing);
    expect(find.text('Indomaret'), findsOneWidget);
    expect(find.text('≥ Rp10.000'), findsOneWidget);
    expect(find.text('1 dari 3 transaksi'), findsOneWidget);
  });

  testWidgets('a store pill narrows to that store only', (
    WidgetTester tester,
  ) async {
    await pumpHistory(tester);

    await openSheet(tester);
    await tester.tap(sheetPill('Alfamart'));
    await tester.pump();
    await applySheet(tester);

    // The store name also appears in the summary bar, so count only the cards.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Alfamart'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 dari 3 transaksi'), findsOneWidget);
  });

  testWidgets('clearing the summary bar brings every receipt back', (
    WidgetTester tester,
  ) async {
    await pumpHistory(tester);

    await openSheet(tester);
    await tester.tap(sheetPill('Alfamart'));
    await tester.pump();
    await applySheet(tester);
    expect(find.text('Indomaret'), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('3 transaksi tercatat'), findsOneWidget);
    expect(find.text('Indomaret'), findsNWidgets(2));
    expect(find.text('Alfamart'), findsOneWidget);
  });

  testWidgets('a range with the minimum above the maximum is rejected', (
    WidgetTester tester,
  ) async {
    await pumpHistory(tester);

    await openSheet(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Minimal'), '50000');
    await tester.enterText(find.widgetWithText(TextField, 'Maksimal'), '10000');
    await applySheet(tester);

    // The sheet stays open with the error instead of applying a filter that can
    // never match anything.
    expect(
      find.text('Nominal minimum tidak boleh melebihi maksimum'),
      findsOneWidget,
    );
    expect(find.text('Filter Lanjutan'), findsOneWidget);
  });

  testWidgets('a quick preset fills in a date range', (WidgetTester tester) async {
    await pumpHistory(tester);

    await openSheet(tester);
    expect(find.text('Semua tanggal'), findsOneWidget);

    await tester.tap(sheetPill('Bulan Ini'));
    await tester.pump();

    final DateTime now = DateTime.now();
    final String expected = '${formatDate(DateTime(now.year, now.month, 1))}'
        ' – ${formatDate(DateTime(now.year, now.month, now.day))}';
    expect(find.text(expected), findsOneWidget);
    expect(find.text('Semua tanggal'), findsNothing);
  });

  testWidgets('picking two days in the calendar fills the date field', (
    WidgetTester tester,
  ) async {
    await pumpHistory(tester);

    await openSheet(tester);
    await tester.tap(find.text('Semua tanggal'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih Rentang Tanggal'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('10'));
    await tester.pump();

    final DateTime now = DateTime.now();
    final String expected = '${formatDate(DateTime(now.year, now.month, 1))}'
        ' – ${formatDate(DateTime(now.year, now.month, 10))}';
    expect(find.text(expected), findsOneWidget);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Terapkan'));
    await tester.pumpAndSettle();

    // Back on the filter sheet, with the range filled in and ready to apply.
    expect(find.text('Pilih Rentang Tanggal'), findsNothing);
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('the search box and the sheet combine instead of overriding', (
    WidgetTester tester,
  ) async {
    await pumpHistory(tester);

    await tester.enterText(find.byType(TextField).first, 'indomaret');
    await tester.pumpAndSettle();
    expect(find.text('2 dari 3 transaksi'), findsOneWidget);

    await openSheet(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Minimal'), '10000');
    await applySheet(tester);

    // Still only Indomaret, and of those two only the 25.000 one.
    expect(find.text('Alfamart'), findsNothing);
    expect(find.text('Indomaret'), findsOneWidget);
    expect(find.textContaining('Rp10.000'), findsWidgets);
    expect(find.text('1 dari 3 transaksi'), findsOneWidget);
  });
}
