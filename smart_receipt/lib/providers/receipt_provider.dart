import 'package:flutter/material.dart';
import '../models/receipt_model.dart';
import '../helpers/database_helper.dart';

class ReceiptProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  List<Receipt> _receipts = [];
  List<Category> _categories = [];
  bool _isLoading = false;
  double _totalSpendingThisMonth = 0.0;
  Map<String, double> _spendingByCategory = {};

  List<Receipt> get receipts => _receipts;
  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  double get totalSpendingThisMonth => _totalSpendingThisMonth;
  Map<String, double> get spendingByCategory => _spendingByCategory;

  // Load semua data saat app start
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _receipts = await _dbHelper.getAllReceipts();
      _categories = await _dbHelper.getAllCategories();
      _totalSpendingThisMonth = await _dbHelper.getTotalSpendingThisMonth();
      _spendingByCategory = await _dbHelper.getSpendingByCategory();
    } catch (e) {
      debugPrint('Error loading data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Tambah receipt baru
  Future<void> addReceipt(Receipt receipt) async {
    final id = await _dbHelper.insertReceipt(receipt);
    
    // Insert transactions
    for (var transaction in receipt.transactions) {
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
  }

  // Update receipt
  Future<void> updateReceipt(Receipt receipt) async {
    await _dbHelper.updateReceipt(receipt);
    await loadData();
  }

  // Hapus receipt
  Future<void> deleteReceipt(int id) async {
    await _dbHelper.deleteReceipt(id);
    await loadData();
  }

  // Get receipt by ID dengan transactions
  Future<Receipt?> getReceiptWithTransactions(int receiptId) async {
    final receipt = await _dbHelper.getReceiptById(receiptId);
    if (receipt == null) return null;

    final transactions = await _dbHelper.getTransactionsByReceiptId(receiptId);
    return Receipt(
      id: receipt.id,
      storeName: receipt.storeName,
      storeAddress: receipt.storeAddress,
      transactionDate: receipt.transactionDate,
      totalAmount: receipt.totalAmount,
      taxAmount: receipt.taxAmount,
      subtotal: receipt.subtotal,
      paymentMethod: receipt.paymentMethod,
      receiptNumber: receipt.receiptNumber,
      imagePath: receipt.imagePath,
      ocrText: receipt.ocrText,
      status: receipt.status,
      notes: receipt.notes,
      createdAt: receipt.createdAt,
      transactions: transactions,
    );
  }

  // Get category by ID
  Category? getCategoryById(int id) {
    try {
      return _categories.firstWhere((cat) => cat.id == id);
    } catch (e) {
      return null;
    }
  }
}
