import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'package:smart_receipt/helpers/database_helper.dart';
import 'package:smart_receipt/models/categories.dart';
import 'package:smart_receipt/models/receipt_model.dart';

Receipt _receipt({
  required String store,
  required DateTime date,
  required double total,
  required DateTime createdAt,
}) {
  return Receipt(
    storeName: store,
    transactionDate: date,
    totalAmount: total,
    taxAmount: 0,
    subtotal: total,
    paymentMethod: 'Tunai',
    status: 'saved',
    createdAt: createdAt,
    transactions: <Transaction>[
      Transaction(
        receiptId: 0,
        categoryId: 1, // Makanan
        itemName: 'Indomie Goreng',
        quantity: 2,
        unitPrice: 3500,
        totalPrice: 7000,
        discount: 0,
        createdAt: date,
      ),
      Transaction(
        receiptId: 0,
        categoryId: 2, // Minuman
        itemName: 'Ongkos',
        quantity: 1,
        unitPrice: 3000,
        totalPrice: 3000,
        discount: 0,
        createdAt: date,
      ),
    ],
  );
}

/// Inserts a receipt and all of its items, the way [ReceiptProvider] does.
Future<int> _save(DatabaseHelper helper, Receipt receipt) async {
  final int id = await helper.insertReceipt(receipt);
  for (final Transaction item in receipt.transactions) {
    await helper.insertTransaction(
      Transaction(
        receiptId: id,
        categoryId: item.categoryId,
        itemName: item.itemName,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        totalPrice: item.totalPrice,
        discount: item.discount,
        createdAt: item.createdAt,
      ),
    );
  }
  return id;
}

void main() {
  setUpAll(() {    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late DatabaseHelper helper;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('smart_receipt_db_');
    helper = DatabaseHelper(overridePath: p.join(dir.path, 'test.db'));
  });

  tearDown(() async {
    await helper.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('creates and seeds the schema', () async {
    final List<Category> categories = await helper.getAllCategories();
    expect(categories.length, kAppCategories.length);
    expect(
      categories.map((Category c) => c.name),
      contains('Makanan'),
    );
  });

  test('round-trips a receipt with its items', () async {
    await _save(
      helper,
      _receipt(
        store: 'Indomaret',
        date: DateTime(2026, 10, 5, 19, 14),
        total: 10000,
        createdAt: DateTime(2026, 10, 5, 19, 20),
      ),
    );

    final List<Receipt> receipts = await helper.getReceiptsWithTransactions();
    expect(receipts.length, 1);
    expect(receipts.single.storeName, 'Indomaret');
    expect(receipts.single.transactions.length, 2);
    expect(receipts.single.transactions.first.itemName, 'Indomie Goreng');
  });

  test('analytics use transaction_date, not created_at', () async {
    // Printed in October but entered much later.
    await _save(
      helper,
      _receipt(
        store: 'Lama',
        date: DateTime(2026, 10, 31, 23, 30),
        total: 50000,
        createdAt: DateTime(2026, 12, 1),
      ),
    );
    await _save(
      helper,
      _receipt(
        store: 'November',
        date: DateTime(2026, 11, 1),
        total: 90000,
        createdAt: DateTime(2026, 11, 1),
      ),
    );

    final double october = await helper.getTotalSpendingBetween(
      DateTime(2026, 10, 1),
      DateTime(2026, 11, 1),
    );
    expect(october, 50000);

    final Map<String, double> byCategory = await helper.getSpendingByCategory(
      from: DateTime(2026, 10, 1),
      toExclusive: DateTime(2026, 11, 1),
    );
    expect(byCategory['Makanan'], 7000);
    expect(byCategory['Minuman'], 3000);
  });

  test('deleting a receipt cascades to its items', () async {
    final int id = await _save(
      helper,
      _receipt(
        store: 'Alfamart',
        date: DateTime(2026, 10, 8),
        total: 10000,
        createdAt: DateTime(2026, 10, 8),
      ),
    );

    expect((await helper.getTransactionsByReceiptId(id)).length, 2);
    await helper.deleteReceipt(id);
    expect(await helper.getTransactionsByReceiptId(id), isEmpty);
    expect(await helper.getAllReceipts(), isEmpty);
  });

  test('seeds exactly the canonical taxonomy', () async {
    final List<Category> categories = await helper.getAllCategories();
    expect(
      categories.map((Category c) => c.name).toList(),
      kAppCategories.map((AppCategory c) => c.name).toList(),
    );
    expect(
      categories.map((Category c) => c.id).toList(),
      kAppCategories.map((AppCategory c) => c.id).toList(),
    );
  });

  test('v2 database is migrated to the canonical taxonomy', () async {
    // Build a v2 database by hand: legacy 8-row seed plus rows in every
    // category that has to be remapped.
    final String legacyPath = p.join(dir.path, 'legacy.db');
    final Database legacy = await databaseFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              icon TEXT NOT NULL,
              color TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE receipts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_name TEXT NOT NULL,
              store_address TEXT,
              transaction_date TEXT NOT NULL,
              total_amount REAL NOT NULL,
              tax_amount REAL NOT NULL,
              subtotal REAL NOT NULL,
              payment_method TEXT,
              receipt_number TEXT,
              image_path TEXT,
              ocr_text TEXT,
              status TEXT NOT NULL DEFAULT 'processed',
              notes TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              receipt_id INTEGER NOT NULL,
              category_id INTEGER NOT NULL,
              item_name TEXT NOT NULL,
              quantity INTEGER NOT NULL,
              unit_price REAL NOT NULL,
              total_price REAL NOT NULL,
              discount REAL NOT NULL DEFAULT 0,
              notes TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY (receipt_id) REFERENCES receipts(id) ON DELETE CASCADE,
              FOREIGN KEY (category_id) REFERENCES categories(id)
            )
          ''');
          await db.execute('''
            CREATE TABLE category_corrections (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_name TEXT NOT NULL,
              original_name TEXT,
              predicted_label TEXT,
              predicted_category_id INTEGER,
              corrected_category_id INTEGER NOT NULL,
              corrected_category_name TEXT NOT NULL,
              confidence REAL,
              source TEXT NOT NULL DEFAULT 'review',
              used_in_training INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');

          const List<Map<String, Object?>> legacyCategories =
              <Map<String, Object?>>[
            <String, Object?>{'id': 1, 'name': 'Makanan & Minuman', 'icon': '🍔', 'color': '#FF6B6B'},
            <String, Object?>{'id': 2, 'name': 'Transport', 'icon': '🚗', 'color': '#4ECDC4'},
            <String, Object?>{'id': 3, 'name': 'Belanja Bulanan', 'icon': '🛒', 'color': '#45B7D1'},
            <String, Object?>{'id': 4, 'name': 'Utilitas', 'icon': '⚡', 'color': '#FFA502'},
            <String, Object?>{'id': 5, 'name': 'Hiburan', 'icon': '🎬', 'color': '#A29BFE'},
            <String, Object?>{'id': 6, 'name': 'Kesehatan', 'icon': '⚕️', 'color': '#FF7675'},
            <String, Object?>{'id': 7, 'name': 'Pendidikan', 'icon': '📚', 'color': '#74B9FF'},
            <String, Object?>{'id': 8, 'name': 'Lainnya', 'icon': '📌', 'color': '#6C5CE7'},
          ];
          for (final Map<String, Object?> row in legacyCategories) {
            await db.insert('categories', row);
          }

          await db.insert('receipts', <String, Object?>{
            'id': 1,
            'store_name': 'Legacy',
            'transaction_date': DateTime(2026, 10, 5).toIso8601String(),
            'total_amount': 10000.0,
            'tax_amount': 0.0,
            'subtotal': 10000.0,
            'status': 'saved',
            'created_at': DateTime(2026, 10, 5).toIso8601String(),
          });

          // One item per legacy category id 1..8.
          for (int categoryId = 1; categoryId <= 8; categoryId++) {
            await db.insert('transactions', <String, Object?>{
              'receipt_id': 1,
              'category_id': categoryId,
              'item_name': 'Item $categoryId',
              'quantity': 1,
              'unit_price': 1000.0,
              'total_price': 1000.0,
              'discount': 0.0,
              'created_at': DateTime(2026, 10, 5).toIso8601String(),
            });
          }

          await db.insert('category_corrections', <String, Object?>{
            'item_name': 'mie instan',
            'predicted_category_id': 2,
            'corrected_category_id': 6,
            'corrected_category_name': 'Kesehatan',
            'used_in_training': 0,
            'created_at': DateTime(2026, 10, 5).toIso8601String(),
          });
        },
      ),
    );
    await legacy.close();

    // Opening through DatabaseHelper runs the v2 -> v3 migration.
    final DatabaseHelper migrated = DatabaseHelper(overridePath: legacyPath);
    addTearDown(migrated.close);

    final List<Category> categories = await migrated.getAllCategories();
    expect(categories.length, kAppCategories.length);
    expect(
      categories.map((Category c) => c.name).toList(),
      kAppCategories.map((AppCategory c) => c.name).toList(),
    );

    final List<Transaction> items = await migrated.getTransactionsByReceiptId(1);
    final Map<String, int> byName = <String, int>{
      for (final Transaction t in items) t.itemName: t.categoryId,
    };

    // Old id -> canonical id, per the documented mapping.
    expect(byName['Item 1'], 1); // Makanan & Minuman -> Makanan
    expect(byName['Item 2'], 6); // Transport         -> Transportasi
    expect(byName['Item 3'], 3); // Belanja Bulanan   -> Rumah Tangga
    expect(byName['Item 4'], 9); // Utilitas          -> Lainnya
    expect(byName['Item 5'], 9); // Hiburan           -> Lainnya
    expect(byName['Item 6'], 5); // Kesehatan         -> Kesehatan
    expect(byName['Item 7'], 9); // Pendidikan        -> Lainnya
    expect(byName['Item 8'], 9); // Lainnya           -> Lainnya

    final List<CategoryCorrection> corrections =
        await migrated.getCategoryCorrections();
    expect(corrections.single.predictedCategoryId, 6);
    expect(corrections.single.correctedCategoryId, 5);
  });
}
