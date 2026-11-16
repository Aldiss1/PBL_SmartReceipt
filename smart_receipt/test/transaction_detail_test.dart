import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_receipt/data/receipt_adapter.dart';
import 'package:smart_receipt/models/models.dart';
import 'package:smart_receipt/models/receipt_model.dart' as db;
import 'package:smart_receipt/providers/receipt_provider.dart';
import 'package:smart_receipt/screens/transaction_detail.dart';
import 'package:smart_receipt/services/receipt_image_store.dart';
import 'package:smart_receipt/widgets/app_widgets.dart';

import 'support/fake_receipt_database.dart';

/// Pushes the detail screen from a placeholder route so tests can assert that
/// deleting pops back to where the user came from.
Future<void> _openDetail(
  WidgetTester tester,
  ReceiptProvider provider,
  Transaction transaction,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ReceiptProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TransactionDetailScreen(transaction: transaction),
                  ),
                ),
                child: const Text('Buka Detail'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Buka Detail'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeReceiptDatabase helper;
  late ReceiptProvider provider;

  setUp(() {
    helper = FakeReceiptDatabase();
    provider = ReceiptProvider(
      dbHelper: helper,
      imageStore: ReceiptImageStore(),
    );
  });

  testWidgets('deleting a transaction removes it and leaves the screen', (
    WidgetTester tester,
  ) async {
    await provider.addReceipt(sampleReceipt());
    expect(provider.receipts.length, 1);

    final Transaction transaction = toUiTransaction(
      provider.receipts.single,
      provider.categoryNameFor,
    );
    expect(transaction.receiptId, isNotNull);

    await _openDetail(tester, provider, transaction);
    expect(find.text('Detail Transaksi'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Hapus transaksi?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
    await tester.pumpAndSettle();

    // Back on the placeholder route, receipt gone from the provider.
    expect(find.text('Buka Detail'), findsOneWidget);
    expect(provider.receipts, isEmpty);
    expect(await helper.getReceiptsWithTransactions(), isEmpty);
    expect(find.text('Transaksi Indomaret dihapus.'), findsOneWidget);
  });

  testWidgets('cancelling the dialog keeps the transaction', (
    WidgetTester tester,
  ) async {
    await provider.addReceipt(sampleReceipt(store: 'Alfamart'));

    final Transaction transaction = toUiTransaction(
      provider.receipts.single,
      provider.categoryNameFor,
    );

    await _openDetail(tester, provider, transaction);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Detail Transaksi'), findsOneWidget);
    expect(provider.receipts.length, 1);
    expect(await helper.getReceiptsWithTransactions(), hasLength(1));
  });

  testWidgets('editing from detail saves and refreshes the screen', (
    WidgetTester tester,
  ) async {
    await provider.addReceipt(sampleReceipt());

    final Transaction transaction = toUiTransaction(
      provider.receipts.single,
      provider.categoryNameFor,
    );

    await _openDetail(tester, provider, transaction);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // The shared review screen opens in edit mode, prefilled from the provider.
    expect(find.text('Edit Transaksi'), findsOneWidget);
    expect(find.text('Indomie Goreng'), findsOneWidget);
    expect(find.text('2 × Rp3.500'), findsOneWidget);

    await tester.tap(find.text('Indomaret').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Indomaret Sudirman');
    await tester.pump();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Simpan Nama Toko'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Simpan Perubahan'));
    await tester.pumpAndSettle();

    // Detail screen reloaded from the provider with the edited store name.
    expect(find.text('Detail Transaksi'), findsOneWidget);
    expect(find.text('Indomaret Sudirman'), findsWidgets);
    expect(provider.receipts.single.storeName, 'Indomaret Sudirman');
  });

  testWidgets('a receipt without a stored id hides the write actions', (
    WidgetTester tester,
  ) async {
    final db.Receipt saved = sampleReceipt();
    // ui.Transaction built without receiptId stands in for a preview row.
    final Transaction unsaved = Transaction(
      id: 'TRX---',
      store: saved.storeName,
      date: saved.transactionDate,
      items: const <TransactionItem>[
        TransactionItem(
          name: 'Indomie Goreng',
          qty: 2,
          price: 3500,
          category: 'Makanan',
        ),
      ],
    );

    await _openDetail(tester, provider, unsaved);

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
}
