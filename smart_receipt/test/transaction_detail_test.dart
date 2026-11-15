import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_receipt/data/receipt_adapter.dart';
import 'package:smart_receipt/helpers/database_helper.dart';
import 'package:smart_receipt/models/models.dart';
import 'package:smart_receipt/models/receipt_model.dart' as db;
import 'package:smart_receipt/providers/receipt_provider.dart';
import 'package:smart_receipt/screens/transaction_detail.dart';
import 'package:smart_receipt/services/receipt_image_store.dart';

/// In-memory stand-in for [DatabaseHelper].
///
/// A widget test cannot await real SQLite work: `testWidgets` runs the body on a
/// fake clock, so a platform-channel round trip never completes. Every call the
/// provider makes is overridden here and resolves on a microtask instead.
class _InMemoryDatabaseHelper extends DatabaseHelper {
  final Map<int, db.Receipt> _receipts = <int, db.Receipt>{};
  int _nextId = 1;

  @override
  Future<List<db.Receipt>> getReceiptsWithTransactions() async {
    final List<db.Receipt> rows = _receipts.values.toList()
      ..sort((db.Receipt a, db.Receipt b) =>
          b.transactionDate.compareTo(a.transactionDate));
    return rows;
  }

  @override
  Future<List<db.Category>> getAllCategories() async {
    return <db.Category>[
      db.Category(id: 1, name: 'Makanan', icon: '🍔', color: '#FF6B6B'),
    ];
  }

  @override
  Future<int> insertReceipt(db.Receipt receipt) async {
    final int id = _nextId++;
    _receipts[id] = db.Receipt(
      id: id,
      storeName: receipt.storeName,
      transactionDate: receipt.transactionDate,
      totalAmount: receipt.totalAmount,
      taxAmount: receipt.taxAmount,
      subtotal: receipt.subtotal,
      paymentMethod: receipt.paymentMethod,
      imagePath: receipt.imagePath,
      status: receipt.status,
      createdAt: receipt.createdAt,
      transactions: receipt.transactions,
    );
    return id;
  }

  @override
  Future<int> insertTransaction(db.Transaction transaction) async => 1;

  @override
  Future<db.Receipt?> getReceiptById(int id) async => _receipts[id];

  @override
  Future<int> deleteReceipt(int id) async {
    return _receipts.remove(id) == null ? 0 : 1;
  }
}

db.Receipt _receipt(String store) {
  final DateTime date = DateTime(2026, 9, 13, 19, 14);
  return db.Receipt(
    storeName: store,
    transactionDate: date,
    totalAmount: 7000,
    taxAmount: 0,
    subtotal: 7000,
    paymentMethod: 'Tunai',
    status: 'saved',
    createdAt: date,
    transactions: <db.Transaction>[
      db.Transaction(
        receiptId: 0,
        categoryId: 1,
        itemName: 'Indomie Goreng',
        quantity: 2,
        unitPrice: 3500,
        totalPrice: 7000,
        discount: 0,
        createdAt: date,
      ),
    ],
  );
}

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
  late _InMemoryDatabaseHelper helper;
  late ReceiptProvider provider;

  setUp(() {
    helper = _InMemoryDatabaseHelper();
    provider = ReceiptProvider(
      dbHelper: helper,
      imageStore: ReceiptImageStore(),
    );
  });

  testWidgets('deleting a transaction removes it and leaves the screen', (
    WidgetTester tester,
  ) async {
    await provider.addReceipt(_receipt('Indomaret'));
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
    await provider.addReceipt(_receipt('Alfamart'));

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
}
