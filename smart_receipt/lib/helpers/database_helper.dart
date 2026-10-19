import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/categories.dart';
import '../models/receipt_model.dart';
import '../services/correction_training_service.dart';

/// SQLite-backed implementation of [CorrectionStore].
class DatabaseHelper implements CorrectionStore {
  /// [overridePath] lets tests point at a throwaway database file instead of
  /// the app's real one.
  DatabaseHelper({this.overridePath});

  final String? overridePath;

  static const String _dbName = 'smart_receipt.db';
  static const int _dbVersion = 3;

  static const String _tableCategories = 'categories';
  static const String _tableReceipts = 'receipts';
  static const String _tableTransactions = 'transactions';
  static const String _tableCorrections = 'category_corrections';

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final String path = overridePath ?? join(await getDatabasesPath(), _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      // Required for `ON DELETE CASCADE` to actually run when a receipt is
      // deleted; SQLite keeps foreign keys disabled per connection otherwise.
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Applies incremental schema migrations.
  ///
  /// v1 → v2 adds `category_corrections`, the on-device store of user category
  /// fixes that later feed model retraining.
  ///
  /// v2 → v3 replaces the legacy 8-row category seed with the canonical 9-row
  /// taxonomy from [kAppCategories], remapping every existing reference.
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCorrectionsTable(db);
    }
    if (oldVersion < 3) {
      await _migrateToCanonicalCategories(db);
    }
  }

  /// Moves a pre-v3 database onto the canonical category taxonomy.
  ///
  /// The legacy seed used different names and a different order, so ids have to
  /// be remapped — otherwise existing receipts would silently change category.
  /// The mapping is applied with a single `CASE` expression per column because
  /// chaining `UPDATE ... WHERE category_id = ?` calls would cascade (e.g. the
  /// old `2 → 6` rewrite would then be caught by the later `6 → 5` rewrite).
  Future<void> _migrateToCanonicalCategories(Database db) async {
    // Make sure every canonical id exists and carries the canonical name.
    // Ids are updated in place so foreign keys stay satisfied throughout.
    for (final AppCategory category in kAppCategories) {
      final List<Map<String, Object?>> existing = await db.query(
        _tableCategories,
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object>[category.id],
      );
      final Map<String, Object?> values = <String, Object?>{
        'name': category.name,
        'icon': category.icon,
        'color': category.color,
      };
      if (existing.isEmpty) {
        await db.insert(_tableCategories, <String, Object?>{
          'id': category.id,
          ...values,
        });
      } else {
        await db.update(
          _tableCategories,
          values,
          where: 'id = ?',
          whereArgs: <Object>[category.id],
        );
      }
    }

    // Legacy id -> canonical id. Old 1 "Makanan & Minuman" cannot be split into
    // Makanan/Minuman after the fact, so it stays on id 1 (Makanan).
    const Map<int, int> legacyMap = <int, int>{
      1: 1, // Makanan & Minuman -> Makanan
      2: 6, // Transport         -> Transportasi
      3: 3, // Belanja Bulanan   -> Rumah Tangga
      4: 9, // Utilitas          -> Lainnya
      5: 9, // Hiburan           -> Lainnya
      6: 5, // Kesehatan         -> Kesehatan
      7: 9, // Pendidikan        -> Lainnya
      8: 9, // Lainnya           -> Lainnya
    };

    final String cases = legacyMap.entries
        .map((MapEntry<int, int> e) => 'WHEN ${e.key} THEN ${e.value}')
        .join(' ');

    await db.rawUpdate(
      'UPDATE $_tableTransactions '
      'SET category_id = CASE category_id $cases ELSE category_id END',
    );
    await db.rawUpdate(
      'UPDATE $_tableCorrections '
      'SET corrected_category_id = '
      'CASE corrected_category_id $cases ELSE corrected_category_id END',
    );
    await db.rawUpdate(
      'UPDATE $_tableCorrections '
      'SET predicted_category_id = '
      'CASE predicted_category_id $cases ELSE predicted_category_id END '
      'WHERE predicted_category_id IS NOT NULL',
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

  /// Seeds the canonical categories with explicit ids so `category_id` values
  /// stay meaningful across app versions.
  Future<void> _seedCategories(Database db) async {
    for (final AppCategory category in kAppCategories) {
      await db.insert(_tableCategories, <String, Object?>{
        'id': category.id,
        'name': category.name,
        'icon': category.icon,
        'color': category.color,
      });
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

  /// Every receipt with its item rows attached, newest receipt date first.
  ///
  /// Loads the two tables in two queries and groups in Dart instead of doing
  /// N+1 queries for each receipt.
  Future<List<Receipt>> getReceiptsWithTransactions() async {
    final db = await database;
    final List<Map<String, Object?>> receiptRows = await db.query(
      _tableReceipts,
      orderBy: 'transaction_date DESC, id DESC',
    );
    final List<Map<String, Object?>> transactionRows = await db.query(
      _tableTransactions,
      orderBy: 'id ASC',
    );

    final Map<int, List<Transaction>> byReceipt = <int, List<Transaction>>{};
    for (final Map<String, Object?> row in transactionRows) {
      final Transaction item = Transaction.fromMap(row);
      byReceipt.putIfAbsent(item.receiptId, () => <Transaction>[]).add(item);
    }

    return receiptRows.map((Map<String, Object?> row) {
      final Receipt receipt = Receipt.fromMap(row);
      return receipt.copyWith(
        transactions: byReceipt[receipt.id] ?? const <Transaction>[],
      );
    }).toList();
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
    final result = await db.query(_tableCategories, orderBy: 'id ASC');
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
  //
  // All totals filter on `transaction_date` (the date printed on the receipt)
  // and use a half-open range `[from, to)` so the last day of a month is fully
  // included. Filtering on `created_at` would put a receipt entered late into
  // the wrong month.

  Future<double> getTotalSpendingThisMonth({DateTime? now}) async {
    final DateTime reference = now ?? DateTime.now();
    final DateTime start = DateTime(reference.year, reference.month);
    final DateTime end = DateTime(reference.year, reference.month + 1);
    return getTotalSpendingBetween(start, end);
  }

  Future<double> getTotalSpendingBetween(
    DateTime from,
    DateTime toExclusive,
  ) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(total_amount) as total FROM $_tableReceipts
      WHERE transaction_date >= ? AND transaction_date < ?
    ''', <Object>[from.toIso8601String(), toExclusive.toIso8601String()]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Spending per category, optionally limited to `[from, toExclusive)`.
  Future<Map<String, double>> getSpendingByCategory({
    DateTime? from,
    DateTime? toExclusive,
  }) async {
    final db = await database;
    final bool ranged = from != null && toExclusive != null;
    final result = await db.rawQuery('''
      SELECT c.name, SUM(t.total_price) as total
      FROM $_tableTransactions t
      JOIN $_tableCategories c ON t.category_id = c.id
      JOIN $_tableReceipts r ON t.receipt_id = r.id
      ${ranged ? 'WHERE r.transaction_date >= ? AND r.transaction_date < ?' : ''}
      GROUP BY t.category_id
    ''', ranged
        ? <Object>[from.toIso8601String(), toExclusive.toIso8601String()]
        : const <Object>[]);

    final Map<String, double> spending = <String, double>{};
    for (final Map<String, Object?> row in result) {
      spending[row['name'] as String] =
          (row['total'] as num?)?.toDouble() ?? 0.0;
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
