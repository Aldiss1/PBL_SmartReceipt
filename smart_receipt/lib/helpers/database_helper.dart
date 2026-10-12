import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/receipt_model.dart';

class DatabaseHelper {
  static const String _dbName = 'smart_receipt.db';
  static const int _dbVersion = 1;

  static const String _tableCategories = 'categories';
  static const String _tableReceipts = 'receipts';
  static const String _tableTransactions = 'transactions';

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableCategories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_tableReceipts (
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
      CREATE TABLE $_tableTransactions (
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
        FOREIGN KEY (receipt_id) REFERENCES $_tableReceipts(id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES $_tableCategories(id)
      )
    ''');

    // Seed default categories
    await _seedCategories(db);
  }

  Future<void> _seedCategories(Database db) async {
    final defaultCategories = [
      {'name': 'Makanan & Minuman', 'icon': '🍔', 'color': '#FF6B6B'},
      {'name': 'Transport', 'icon': '🚗', 'color': '#4ECDC4'},
      {'name': 'Belanja Bulanan', 'icon': '🛒', 'color': '#45B7D1'},
      {'name': 'Utilitas', 'icon': '⚡', 'color': '#FFA502'},
      {'name': 'Hiburan', 'icon': '🎬', 'color': '#A29BFE'},
      {'name': 'Kesehatan', 'icon': '⚕️', 'color': '#FF7675'},
      {'name': 'Pendidikan', 'icon': '📚', 'color': '#74B9FF'},
      {'name': 'Lainnya', 'icon': '📌', 'color': '#6C5CE7'},
    ];

    for (var cat in defaultCategories) {
      await db.insert(_tableCategories, cat);
    }
  }

  // RECEIPT OPERATIONS
  Future<int> insertReceipt(Receipt receipt) async {
    final db = await database;
    return db.insert(_tableReceipts, receipt.toMap());
  }

  Future<List<Receipt>> getAllReceipts() async {
    final db = await database;
    final result = await db.query(_tableReceipts, orderBy: 'created_at DESC');
    return result.map((map) => Receipt.fromMap(map)).toList();
  }

  Future<Receipt?> getReceiptById(int id) async {
    final db = await database;
    final result = await db.query(
      _tableReceipts,
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty ? Receipt.fromMap(result.first) : null;
  }

  Future<int> updateReceipt(Receipt receipt) async {
    final db = await database;
    return db.update(
      _tableReceipts,
      receipt.toMap(),
      where: 'id = ?',
      whereArgs: [receipt.id],
    );
  }

  Future<int> deleteReceipt(int id) async {
    final db = await database;
    return db.delete(
      _tableReceipts,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // TRANSACTION OPERATIONS
  Future<int> insertTransaction(Transaction transaction) async {
    final db = await database;
    return db.insert(_tableTransactions, transaction.toMap());
  }

  Future<List<Transaction>> getTransactionsByReceiptId(int receiptId) async {
    final db = await database;
    final result = await db.query(
      _tableTransactions,
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<List<Transaction>> getAllTransactions() async {
    final db = await database;
    final result = await db.query(_tableTransactions, orderBy: 'created_at DESC');
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<int> updateTransaction(Transaction transaction) async {
    final db = await database;
    return db.update(
      _tableTransactions,
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return db.delete(
      _tableTransactions,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CATEGORY OPERATIONS
  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final result = await db.query(_tableCategories);
    return result.map((map) => Category.fromMap(map)).toList();
  }

  Future<Category?> getCategoryById(int id) async {
    final db = await database;
    final result = await db.query(
      _tableCategories,
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty ? Category.fromMap(result.first) : null;
  }

  // ANALYTICS
  Future<double> getTotalSpendingThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).toIso8601String();

    final result = await db.rawQuery('''
      SELECT SUM(total_amount) as total FROM $_tableReceipts 
      WHERE created_at BETWEEN ? AND ?
    ''', [firstDayOfMonth, lastDayOfMonth]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>> getSpendingByCategory() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT c.name, SUM(t.total_price) as total 
      FROM $_tableTransactions t
      JOIN $_tableCategories c ON t.category_id = c.id
      GROUP BY t.category_id
    ''');

    final Map<String, double> spending = {};
    for (var row in result) {
      spending[row['name'] as String] = (row['total'] as num?)?.toDouble() ?? 0.0;
    }
    return spending;
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
