import 'package:smart_receipt/helpers/database_helper.dart';
import 'package:smart_receipt/models/receipt_model.dart';

/// In-memory stand-in for [DatabaseHelper].
///
/// Widget tests cannot await real SQLite work: `testWidgets` runs the body on a
/// fake clock, so a platform-channel round trip never completes and the test
/// hangs instead of failing. Every method the provider calls is overridden here
/// and resolves on a microtask instead.
class FakeReceiptDatabase extends DatabaseHelper {
  final Map<int, Receipt> _receipts = <int, Receipt>{};
  int _nextId = 1;

  int get receiptCount => _receipts.length;

  @override
  Future<List<Receipt>> getReceiptsWithTransactions() async {
    return _receipts.values.toList()
      ..sort((Receipt a, Receipt b) =>
          b.transactionDate.compareTo(a.transactionDate));
  }

  @override
  Future<List<Category>> getAllCategories() async {
    return <Category>[
      Category(id: 1, name: 'Makanan', icon: '🍔', color: '#FF6B6B'),
      Category(id: 2, name: 'Minuman', icon: '🥤', color: '#4ECDC4'),
    ];
  }

  @override
  Future<int> insertReceipt(Receipt receipt) async {
    final int id = _nextId++;
    _receipts[id] = Receipt(
      id: id,
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
      transactions: receipt.transactions,
    );
    return id;
  }

  @override
  Future<int> insertTransaction(Transaction transaction) async => 1;

  @override
  Future<Receipt?> getReceiptById(int id) async => _receipts[id];

  @override
  Future<int> updateReceipt(Receipt receipt) async {
    final int? id = receipt.id;
    if (id == null || !_receipts.containsKey(id)) {
      return 0;
    }
    _receipts[id] = receipt;
    return 1;
  }

  @override
  Future<int> deleteTransactionsByReceiptId(int receiptId) async => 1;

  @override
  Future<int> deleteReceipt(int id) async {
    return _receipts.remove(id) == null ? 0 : 1;
  }
}

/// A one-item receipt used by the screen tests.
///
/// Lives next to [FakeReceiptDatabase] so every screen test starts from the same
/// shape: store name, 2 × 3.500 Indomie, total 7.000.
Receipt sampleReceipt({
  String store = 'Indomaret',
  DateTime? date,
  int categoryId = 1,
  String itemName = 'Indomie Goreng',
  int quantity = 2,
  double unitPrice = 3500,
}) {
  final DateTime stamp = date ?? DateTime(2026, 9, 13, 19, 14);
  return Receipt(
    storeName: store,
    transactionDate: stamp,
    totalAmount: quantity * unitPrice,
    taxAmount: 0,
    subtotal: quantity * unitPrice,
    paymentMethod: 'Tunai',
    status: 'saved',
    createdAt: stamp,
    transactions: <Transaction>[
      Transaction(
        receiptId: 0,
        categoryId: categoryId,
        itemName: itemName,
        quantity: quantity,
        unitPrice: unitPrice,
        totalPrice: quantity * unitPrice,
        discount: 0,
        createdAt: stamp,
      ),
    ],
  );
}
