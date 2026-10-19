import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'package:smart_receipt/helpers/database_helper.dart';
import 'package:smart_receipt/models/receipt_model.dart';
import 'package:smart_receipt/providers/receipt_provider.dart';

Receipt _receipt({
  required String store,
  required DateTime date,
  required double total,
  required int categoryId,
  required double itemTotal,
}) {
  return Receipt(
    storeName: store,
    transactionDate: date,
    totalAmount: total,
    taxAmount: 0,
    subtotal: total,
    paymentMethod: 'QRIS',
    status: 'saved',
    createdAt: date,
    transactions: <Transaction>[
      Transaction(
        receiptId: 0,
        categoryId: categoryId,
        itemName: 'Item',
        quantity: 1,
        unitPrice: itemTotal,
        totalPrice: itemTotal,
        discount: 0,
        createdAt: date,
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late DatabaseHelper helper;
  late ReceiptProvider provider;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('smart_receipt_provider_');
    helper = DatabaseHelper(overridePath: p.join(dir.path, 'test.db'));
    provider = ReceiptProvider(dbHelper: helper);
    await provider.loadData();
  });

  tearDown(() async {
    await helper.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('starts empty', () {
    expect(provider.receipts, isEmpty);
    expect(provider.totalThisMonth, 0);
    expect(provider.totalAllTime, 0);
    expect(provider.spendingByCategory, isEmpty);
    expect(provider.monthOverMonthChange, isNull);
  });

  test('a saved receipt immediately feeds every aggregate', () async {
    final DateTime now = DateTime.now();
    await provider.addReceipt(
      _receipt(
        store: 'Indomaret',
        date: now,
        total: 50000,
        categoryId: 1,
        itemTotal: 50000,
      ),
    );

    expect(provider.receipts.length, 1);
    expect(provider.receipts.single.storeName, 'Indomaret');
    expect(provider.receipts.single.transactions.length, 1);
    expect(provider.totalThisMonth, 50000);
    expect(provider.totalAllTime, 50000);
    expect(provider.countThisMonth, 1);
    expect(provider.countAllTime, 1);
    expect(provider.spendingByCategory['Makanan'], 50000);
    expect(provider.monthlyTotals.last.total, 50000);
    expect(provider.recentReceipts(3).length, 1);
    expect(provider.averagePerDayThisMonth, greaterThan(0));
  });

  test('month over month change compares with the previous month', () async {
    final DateTime now = DateTime.now();
    final DateTime lastMonth = DateTime(now.year, now.month - 1, 15);
    final DateTime thisMonth = DateTime(now.year, now.month, 10);

    await provider.addReceipt(
      _receipt(
        store: 'Bulan Lalu',
        date: lastMonth,
        total: 100000,
        categoryId: 1,
        itemTotal: 100000,
      ),
    );
    await provider.addReceipt(
      _receipt(
        store: 'Bulan Ini',
        date: thisMonth,
        total: 150000,
        categoryId: 2,
        itemTotal: 150000,
      ),
    );

    expect(provider.totalThisMonth, 150000);
    expect(provider.totalLastMonth, 100000);
    expect(provider.monthOverMonthChange, closeTo(0.5, 1e-9));
    // Item-level category totals are per category, not mixed together.
    expect(provider.spendingByCategory['Minuman'], 150000);
  });

  test('deleting a receipt removes it from every aggregate', () async {
    final DateTime now = DateTime.now();
    final int id = await provider.addReceipt(
      _receipt(
        store: 'Hapus',
        date: now,
        total: 25000,
        categoryId: 1,
        itemTotal: 25000,
      ),
    );
    expect(provider.totalThisMonth, 25000);

    await provider.deleteReceipt(id);

    expect(provider.receipts, isEmpty);
    expect(provider.totalThisMonth, 0);
    expect(provider.totalAllTime, 0);
    expect(provider.spendingByCategory, isEmpty);
  });

  test('category names resolve through the seeded categories', () {
    expect(provider.categoryNameFor(1), 'Makanan');
    expect(provider.categoryNameFor(999), 'Lainnya');
    expect(provider.getCategoryById(2)?.name, 'Minuman');
  });
}
