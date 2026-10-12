class Category {
  final int id;
  final String name;
  final String icon;
  final String color;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int,
      name: map['name'] as String,
      icon: map['icon'] as String,
      color: map['color'] as String,
    );
  }
}

class Transaction {
  final int? id;
  final int receiptId;
  final int categoryId;
  final String itemName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final double discount;
  final String? notes;
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.receiptId,
    required this.categoryId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.discount,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_id': receiptId,
      'category_id': categoryId,
      'item_name': itemName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'discount': discount,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      receiptId: map['receipt_id'] as int,
      categoryId: map['category_id'] as int,
      itemName: map['item_name'] as String,
      quantity: map['quantity'] as int,
      unitPrice: map['unit_price'] as double,
      totalPrice: map['total_price'] as double,
      discount: map['discount'] as double,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class Receipt {
  final int? id;
  final String storeName;
  final String? storeAddress;
  final DateTime transactionDate;
  final double totalAmount;
  final double taxAmount;
  final double subtotal;
  final String? paymentMethod;
  final String? receiptNumber;
  final String? imagePath;
  final String? ocrText;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final List<Transaction> transactions;

  Receipt({
    this.id,
    required this.storeName,
    this.storeAddress,
    required this.transactionDate,
    required this.totalAmount,
    required this.taxAmount,
    required this.subtotal,
    this.paymentMethod,
    this.receiptNumber,
    this.imagePath,
    this.ocrText,
    this.status = 'processed',
    this.notes,
    required this.createdAt,
    this.transactions = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_name': storeName,
      'store_address': storeAddress,
      'transaction_date': transactionDate.toIso8601String(),
      'total_amount': totalAmount,
      'tax_amount': taxAmount,
      'subtotal': subtotal,
      'payment_method': paymentMethod,
      'receipt_number': receiptNumber,
      'image_path': imagePath,
      'ocr_text': ocrText,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Receipt.fromMap(Map<String, dynamic> map) {
    return Receipt(
      id: map['id'] as int?,
      storeName: map['store_name'] as String,
      storeAddress: map['store_address'] as String?,
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      totalAmount: map['total_amount'] as double,
      taxAmount: map['tax_amount'] as double,
      subtotal: map['subtotal'] as double,
      paymentMethod: map['payment_method'] as String?,
      receiptNumber: map['receipt_number'] as String?,
      imagePath: map['image_path'] as String?,
      ocrText: map['ocr_text'] as String?,
      status: map['status'] as String,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
