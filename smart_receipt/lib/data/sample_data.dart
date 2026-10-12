import '../models/models.dart';

/// Placeholder data mirroring the MVP dataset until the local database lands.
final List<Transaction> kSampleTransactions = <Transaction>[
  Transaction(
    id: 'TRX018',
    store: 'Indomaret',
    date: DateTime(2026, 9, 13, 19, 14),
    paymentMethod: 'QRIS',
    items: const <TransactionItem>[
      TransactionItem(name: 'Indomie Goreng', qty: 2, price: 3500, category: 'Makanan'),
      TransactionItem(name: 'Aqua 600ml', qty: 1, price: 4000, category: 'Minuman'),
      TransactionItem(name: 'Sabun Lifebuoy', qty: 1, price: 6500, category: 'Perawatan Diri'),
      TransactionItem(name: 'Tissue Paseo', qty: 1, price: 12500, category: 'Rumah Tangga'),
      TransactionItem(name: 'Teh Botol Sosro', qty: 1, price: 5000, category: 'Minuman'),
      TransactionItem(name: 'Roti Tawar', qty: 1, price: 14000, category: 'Makanan'),
    ],
  ),
  Transaction(
    id: 'TRX017',
    store: 'Kopi Kenangan',
    date: DateTime(2026, 9, 12, 14, 2),
    paymentMethod: 'QRIS',
    items: const <TransactionItem>[
      TransactionItem(name: 'Kopi Susu Gula Aren', qty: 1, price: 22000, category: 'Minuman'),
      TransactionItem(name: 'Croissant', qty: 1, price: 6000, category: 'Makanan'),
    ],
  ),
  Transaction(
    id: 'TRX016',
    store: 'Warung Bu Kris',
    date: DateTime(2026, 9, 12, 12, 45),
    paymentMethod: 'Tunai',
    items: const <TransactionItem>[
      TransactionItem(name: 'Nasi Rawon', qty: 1, price: 25000, category: 'Makanan'),
      TransactionItem(name: 'Es Teh Manis', qty: 1, price: 5000, category: 'Minuman'),
      TransactionItem(name: 'Tempe Mendoan', qty: 1, price: 5000, category: 'Makanan'),
    ],
  ),
  Transaction(
    id: 'TRX015',
    store: 'Alfamart',
    date: DateTime(2026, 9, 10, 8, 30),
    paymentMethod: 'Tunai',
    items: const <TransactionItem>[
      TransactionItem(name: 'Shampoo Pantene', qty: 1, price: 32000, category: 'Perawatan Diri'),
      TransactionItem(name: 'Pasta Gigi Pepsodent', qty: 1, price: 14000, category: 'Perawatan Diri'),
      TransactionItem(name: 'Beras Pandan Wangi 5kg', qty: 1, price: 68000, category: 'Rumah Tangga'),
    ],
  ),
  Transaction(
    id: 'TRX014',
    store: 'SPBU Pertamina',
    date: DateTime(2026, 9, 8, 17, 5),
    paymentMethod: 'Debit',
    items: const <TransactionItem>[
      TransactionItem(name: 'Pertamax', qty: 1, price: 180000, category: 'Transportasi'),
    ],
  ),
];

int get kMonthlySpend =>
    kSampleTransactions.fold(0, (int sum, Transaction t) => sum + t.total);
