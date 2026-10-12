import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/receipt_model.dart';
import '../services/correction_training_service.dart';

/// SQLite-backed implementation of [CorrectionStore].
class DatabaseHelper implements CorrectionStore {
  static const String _dbName = 'smart_receipt.db';
  static const int _dbVersion = 2;

  static const String _tableCategories = 'categories';
  static const String _tableReceipts = 'receipts';
  static const String _tableTransactions = 'transactions';
  static const String _tableCorrections = 'category_corrections';

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
      onUpgrade: _upgradeDB,
    );
  }

  /// Applies incremental schema migrations.
  ///
  /// v1 → v2 adds `category_corrections`, the on-device store of user category
  /// fixes that later feed model retraining.
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCorrectionsTable(db);
    }
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

    await _createCorrectionsTable(db);

    // Seed default categories
    await _seedCategories(db);
  }

  /// Stores one row per user correction: what the model predicted vs. the
  /// category the user chose, for a given item name.
  ///
  /// Kept separate from `transactions` so the training signal survives even if
  /// the receipt is deleted, and so `retraining_service.dart` can export it
  /// without touching business data.
  Future<void> _createCorrectionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableCorrections (
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
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_corrections_used
      ON $_tableCorrections (used_in_training)
    ''');
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

  // ---------------------------------------------------------------- training
  // User category corrections: the raw material for on-device retraining.

  /// Records a single user correction.
  ///
  /// [itemName] is the normalized item name (what the model sees), while
  /// [originalName] keeps the OCR text for traceability.
  @override
  Future<int> insertCategoryCorrection(CategoryCorrection correction) async {
    final db = await database;
    return db.insert(_tableCorrections, correction.toMap());
  }

  /// All corrections, newest first. Optionally only those not yet consumed by
  /// a training run.
  @override
  Future<List<CategoryCorrection>> getCategoryCorrections({
    bool onlyUnused = false,
  }) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      _tableCorrections,
      where: onlyUnused ? 'used_in_training = 0' : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(CategoryCorrection.fromMap).toList();
  }

  @override
  Future<int> countCategoryCorrections({bool onlyUnused = false}) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_tableCorrections'
      '${onlyUnused ? ' WHERE used_in_training = 0' : ''}',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Number of corrections per corrected category, e.g. to preview how much
  /// new training data the user has generated.
  @override
  Future<Map<String, int>> getCorrectionCountsByCategory() async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT corrected_category_name AS name, COUNT(*) AS total
      FROM $_tableCorrections
      GROUP BY corrected_category_id
      ORDER BY total DESC
    ''');
    return <String, int>{
      for (final Map<String, Object?> row in rows)
        row['name'] as String: (row['total'] as num).toInt(),
    };
  }

  /// Marks corrections as consumed by a training run.
  @override
  Future<int> markCorrectionsUsed(Iterable<int> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    final db = await database;
    final String placeholders = List<String>.filled(ids.length, '?').join(',');
    return db.update(
      _tableCorrections,
      <String, Object?>{'used_in_training': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
  }

  Future<int> deleteCategoryCorrection(int id) async {
    final db = await database;
    return db.delete(_tableCorrections, where: 'id = ?', whereArgs: <Object>[id]);
  }
}
