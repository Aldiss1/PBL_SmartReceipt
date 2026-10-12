import 'package:flutter/material.dart';

/// Formats an integer amount as Indonesian Rupiah, e.g. 1420000 -> "Rp1.420.000".
String rupiah(int value) {
  final String digits = value.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}Rp$buffer';
}

const List<String> _kMonths = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// e.g. 13 Sep 2026
String formatDate(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';

/// e.g. 13 Sep 2026 • 19:14
String formatDateTime(DateTime d) =>
    '${formatDate(d)} • ${_two(d.hour)}:${_two(d.minute)}';

/// A product category used by the TF-IDF + Naive Bayes classifier.
class Category {
  const Category({required this.name, required this.icon, required this.color});

  final String name;
  final IconData icon;
  final Color color;
}

const List<Category> kCategories = [
  Category(
    name: 'Makanan',
    icon: Icons.restaurant,
    color: Color(0xFFFEA619),
  ),
  Category(
    name: 'Minuman',
    icon: Icons.local_cafe_outlined,
    color: Color(0xFF4C8DF6),
  ),
  Category(
    name: 'Rumah Tangga',
    icon: Icons.home_outlined,
    color: Color(0xFF8C5D10),
  ),
  Category(
    name: 'Perawatan Diri',
    icon: Icons.spa_outlined,
    color: Color(0xFFB45BCB),
  ),
  Category(
    name: 'Kesehatan',
    icon: Icons.medical_services_outlined,
    color: Color(0xFF009668),
  ),
  Category(
    name: 'Transportasi',
    icon: Icons.directions_car_outlined,
    color: Color(0xFF3D445C),
  ),
  Category(
    name: 'Elektronik',
    icon: Icons.devices_other_outlined,
    color: Color(0xFF5B6472),
  ),
  Category(
    name: 'Pakaian',
    icon: Icons.checkroom_outlined,
    color: Color(0xFFDB6B8C),
  ),
  Category(
    name: 'Lainnya',
    icon: Icons.category_outlined,
    color: Color(0xFF8A8D97),
  ),
];

Category categoryByName(String name) {
  return kCategories.firstWhere(
    (Category c) => c.name == name,
    orElse: () => kCategories.last,
  );
}

/// A single line item on a receipt.
class TransactionItem {
  const TransactionItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.category,
  });

  final String name;
  final int qty;
  final int price;
  final String category;

  int get subtotal => qty * price;
}

/// A saved receipt transaction.
class Transaction {
  const Transaction({
    required this.id,
    required this.store,
    required this.date,
    required this.items,
    this.paymentMethod = 'Tunai',
  });

  final String id;
  final String store;
  final DateTime date;
  final List<TransactionItem> items;
  final String paymentMethod;

  int get total =>
      items.fold(0, (int sum, TransactionItem i) => sum + i.subtotal);

  int get itemCount => items.length;

  /// Distinct categories contained in this transaction.
  List<String> get categories {
    final Set<String> seen = <String>{};
    for (final TransactionItem i in items) {
      seen.add(i.category);
    }
    return seen.toList();
  }
}
