import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'categories.dart';

export 'categories.dart'
    show
        AppCategory,
        kAppCategories,
        kFallbackCategoryId,
        kCategoryIdForName,
        kCategoryNameForId;

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

/// The product categories used by the classifier.
///
/// Built from [kAppCategories] so names and ids always match the SQLite seed
/// table. Accent colours are pulled from the active palette so chips and icon
/// tiles stay legible in both light and dark mode.
List<Category> get kCategories => <Category>[
  for (int i = 0; i < kAppCategories.length; i++)
    Category(
      name: kAppCategories[i].name,
      icon: _categoryIcon(kAppCategories[i].id),
      color: AppColors.palette.categoryColors[
          i % AppColors.palette.categoryColors.length],
    ),
];

/// Material icon for a canonical category id.
IconData _categoryIcon(int id) {
  switch (id) {
    case 1:
      return Icons.restaurant;
    case 2:
      return Icons.local_cafe_outlined;
    case 3:
      return Icons.home_outlined;
    case 4:
      return Icons.spa_outlined;
    case 5:
      return Icons.medical_services_outlined;
    case 6:
      return Icons.directions_car_outlined;
    case 7:
      return Icons.devices_other_outlined;
    case 8:
      return Icons.checkroom_outlined;
    default:
      return Icons.category_outlined;
  }
}

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
    this.imagePath,
  });

  final String id;
  final String store;
  final DateTime date;
  final List<TransactionItem> items;
  final String paymentMethod;

  /// Absolute path to the stored receipt photo, when one was kept.
  ///
  /// Null for receipts saved before images were persisted, and for scans whose
  /// capture could not be copied into app storage.
  final String? imagePath;

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
