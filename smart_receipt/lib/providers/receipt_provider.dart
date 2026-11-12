import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../helpers/database_helper.dart';
import '../models/receipt_model.dart';
import '../services/spending_analytics.dart';

/// Single source of truth for saved receipts and the aggregates derived from
/// them.
///
/// Every screen reads through this provider, so a receipt saved on the review
/// screen immediately shows up in the history, dashboard, analysis and
/// forecast. Totals are computed in Dart from the loaded receipts (via
/// [SpendingAnalytics]) so they cannot drift from the rows on screen.
class ReceiptProvider with ChangeNotifier {
  ReceiptProvider({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  List<Receipt> _receipts = <Receipt>[];
  List<Category> _categories = <Category>[];
  Map<int, String> _categoryNames = <int, String>{};
  bool _isLoading = false;

  double _totalThisMonth = 0;
  double _totalLastMonth = 0;
  int _countThisMonth = 0;
  Map<String, double> _spendingByCategory = <String, double>{};
  List<MonthlyTotal> _monthlyTotals = const <MonthlyTotal>[];

  List<Receipt> get receipts => _receipts;
  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;

  double get totalThisMonth => _totalThisMonth;
  double get totalLastMonth => _totalLastMonth;
  int get countThisMonth => _countThisMonth;

  /// Item spending per category for the current month.
  Map<String, double> get spendingByCategory => _spendingByCategory;

  /// Last six calendar months, oldest first, zero-filled.
  List<MonthlyTotal> get monthlyTotals => _monthlyTotals;

  /// Fractional change versus last month, or null when last month had no
  /// spending (a percentage against zero would be misleading).
  double? get monthOverMonthChange {
    if (_totalLastMonth == 0) {
      return null;
    }
    return (_totalThisMonth - _totalLastMonth) / _totalLastMonth;
  }

  /// Average spending per calendar day elapsed so far this month.
  double get averagePerDayThisMonth {
    final int elapsed = DateTime.now().day;
    return elapsed == 0 ? 0 : _totalThisMonth / elapsed;
  }

  /// Newest receipts first, at most [count].
  List<Receipt> recentReceipts([int count = 3]) =>
      _receipts.take(count).toList();

  String categoryNameFor(int id) => _categoryNames[id] ?? 'Lainnya';

  // ---------------------------------------------------------------- loading

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final List<Receipt> loaded = await _dbHelper.getReceiptsWithTransactions();
      final List<Category> categories = await _dbHelper.getAllCategories();

      _categories = categories;
      _categoryNames = <int, String>{
        for (final Category c in categories) c.id: c.name,
      };
      _receipts = loaded;
      _recompute();
    } catch (e) {
      debugPrint('Gagal memuat data: $e');
      _receipts = <Receipt>[];
      _recompute();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Recomputes every derived total from [_receipts].
  void _recompute() {
    final DateTime now = DateTime.now();
    final DateTime thisMonth = SpendingAnalytics.monthStart(now);
    final DateTime nextMonth = SpendingAnalytics.addMonths(thisMonth, 1);
    final DateTime lastMonth = SpendingAnalytics.addMonths(thisMonth, -1);

    _totalThisMonth = SpendingAnalytics.totalBetween(
      _receipts,
      from: thisMonth,
      toExclusive: nextMonth,
    );
    _totalLastMonth = SpendingAnalytics.totalBetween(
      _receipts,
      from: lastMonth,
      toExclusive: thisMonth,
    );
    _countThisMonth = SpendingAnalytics.countBetween(
      _receipts,
      from: thisMonth,
      toExclusive: nextMonth,
    );
    _spendingByCategory = SpendingAnalytics.byCategory(
      _receipts,
      _categoryNames,
      from: thisMonth,
      toExclusive: nextMonth,
    );
    _monthlyTotals = SpendingAnalytics.monthlyTotals(_receipts);
  }

  // ------------------------------------------------------------------ writes

  /// Persists a receipt and its items, then refreshes all derived totals.
  Future<int> addReceipt(Receipt receipt) async {
    final int id = await _dbHelper.insertReceipt(receipt);

    for (final Transaction transaction in receipt.transactions) {
      await _dbHelper.insertTransaction(
        Transaction(
          receiptId: id,
          categoryId: transaction.categoryId,
          itemName: transaction.itemName,
          quantity: transaction.quantity,
          unitPrice: transaction.unitPrice,
          totalPrice: transaction.totalPrice,
          discount: transaction.discount,
          notes: transaction.notes,
          createdAt: transaction.createdAt,
        ),
      );
    }

    await loadData();
    return id;
  }
}
