/// Single source of truth for the app's spending categories.
///
/// Before this file existed the project carried three different taxonomies that
/// disagreed with each other:
///
///   * the SQLite seed table (8 rows, e.g. `Makanan & Minuman`, `Transport`),
///   * the UI list in `models.dart` (9 rows, e.g. `Makanan`, `Transportasi`),
///   * the exported ML model (15 labels, e.g. `Rokok & Tembakau`).
///
/// Category ids were then translated between those lists by position, which
/// silently mapped e.g. model `Transportasi` to UI `Minuman`. Every lookup now
/// goes through this list, so ids, names, the database seed and the model
/// mapping can no longer drift apart.
///
/// Kept free of Flutter imports so [DatabaseHelper] can seed the table from it.
library;

/// One app category. [id] is the primary key in the `categories` table and the
/// value stored in `transactions.category_id`.
class AppCategory {
  const AppCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  });

  /// Stable 1-based id. Never renumber existing rows without a migration.
  final int id;

  /// Display name, also the ground-truth label used by the ML model mapping.
  final String name;

  /// Emoji stored in SQLite for quick visual identification.
  final String icon;

  /// Hex colour stored in SQLite, e.g. `#FF6B6B`.
  final String color;
}

/// The canonical category list, in id order.
///
/// Matches the taxonomy described in the project proposal: Makanan, Minuman,
/// Rumah Tangga, Perawatan Diri, Kesehatan, Transportasi, Elektronik, Pakaian,
/// dan Lainnya.
const List<AppCategory> kAppCategories = <AppCategory>[
  AppCategory(id: 1, name: 'Makanan', icon: '🍔', color: '#FF6B6B'),
  AppCategory(id: 2, name: 'Minuman', icon: '🥤', color: '#4ECDC4'),
  AppCategory(id: 3, name: 'Rumah Tangga', icon: '🛒', color: '#45B7D1'),
  AppCategory(id: 4, name: 'Perawatan Diri', icon: '🧴', color: '#B45BCB'),
  AppCategory(id: 5, name: 'Kesehatan', icon: '⚕️', color: '#FF7675'),
  AppCategory(id: 6, name: 'Transportasi', icon: '🚗', color: '#FFA502'),
  AppCategory(id: 7, name: 'Elektronik', icon: '💻', color: '#74B9FF'),
  AppCategory(id: 8, name: 'Pakaian', icon: '👕', color: '#DB6B8C'),
  AppCategory(id: 9, name: 'Lainnya', icon: '📌', color: '#6C5CE7'),
];

/// Id of the catch-all category. Used whenever a label has no dedicated row,
/// including the classifier's "needs review" fallback.
const int kFallbackCategoryId = 9;

/// Canonical display name for [id]; falls back to `Lainnya` for unknown ids.
String kCategoryNameForId(int id) {
  for (final AppCategory category in kAppCategories) {
    if (category.id == id) {
      return category.name;
    }
  }
  return kAppCategories.last.name;
}

/// Canonical id for [name] (case-insensitive); falls back to `Lainnya`.
int kCategoryIdForName(String name) {
  final String needle = name.trim().toLowerCase();
  for (final AppCategory category in kAppCategories) {
    if (category.name.toLowerCase() == needle) {
      return category.id;
    }
  }
  return kFallbackCategoryId;
}
