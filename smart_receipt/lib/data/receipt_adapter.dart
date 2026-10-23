import '../models/models.dart' as ui;
import '../models/receipt_model.dart' as db;

/// Converts a persisted receipt into the lightweight UI model used by the
/// history and detail screens.
///
/// The two models exist for good reasons — [db.Receipt] mirrors the SQLite
/// schema, [ui.Transaction] is what the widgets render — so this adapter is the
/// single place where they meet.
ui.Transaction toUiTransaction(
  db.Receipt receipt,
  String Function(int categoryId) categoryName,
) {
  return ui.Transaction(
    id: _displayId(receipt),
    store: receipt.storeName,
    date: receipt.transactionDate,
    paymentMethod: receipt.paymentMethod ?? 'Tunai',
    imagePath: receipt.imagePath,
    items: <ui.TransactionItem>[
      for (final db.Transaction item in receipt.transactions)
        ui.TransactionItem(
          name: item.itemName,
          qty: item.quantity,
          price: item.unitPrice.round(),
          category: categoryName(item.categoryId),
        ),
    ],
  );
}

/// Stable, human-readable id such as `TRX007`.
String _displayId(db.Receipt receipt) {
  final int? id = receipt.id;
  if (id == null) {
    return 'TRX---';
  }
  return 'TRX${id.toString().padLeft(3, '0')}';
}
