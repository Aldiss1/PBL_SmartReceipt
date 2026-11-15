import 'package:flutter/material.dart';

import 'models.dart';
import 'receipt_model.dart' as db;

/// Everything the user can narrow the transaction list by.
///
/// Kept out of the screen state so the matching rules can be unit-tested without
/// a widget tree, and so the list, the summary bar and the CSV export cannot
/// drift apart: all three ask the same [matches].
@immutable
class ReceiptFilter {
  const ReceiptFilter({
    this.query = '',
    this.category = allCategories,
    this.range,
    this.minAmount,
    this.maxAmount,
    this.store,
  });

  /// Chip label for "any category"; also the value that disables the check.
  static const String allCategories = 'Semua';

  /// Free text, matched case-insensitively against the store name and every item
  /// name, so hunting for "susu" finds the receipt whether the OCR read it as a
  /// line item or as part of the shop name.
  final String query;

  /// Category name picked from the chips, or [allCategories].
  final String category;

  /// Inclusive day range; the time of day is ignored.
  ///
  /// A receipt belongs to the day printed on it, and the picker hands back
  /// midnight tokens, so comparing the raw [DateTime]s would silently drop
  /// receipts dated on the last day of the range.
  final DateTimeRange? range;

  /// Inclusive bounds on `Receipt.totalAmount`, in whole rupiah.
  ///
  /// The printed total is what the cards show, so a "≥ Rp50.000" filter can never
  /// hide a row whose visible amount is larger than the bound.
  final int? minAmount;
  final int? maxAmount;

  /// Exact store name, or null for every store.
  ///
  /// Deliberately separate from [query]: searching "Indo" also matches an
  /// Indomie purchase at a different shop, while this narrows to one store only.
  final String? store;

  /// Only [query] and [category] are edited in place, by the search box and the
  /// chips. The advanced fields are replaced wholesale by the filter sheet, which
  /// builds a fresh filter rather than patching nullable fields.
  ReceiptFilter copyWith({String? query, String? category}) => ReceiptFilter(
        query: query ?? this.query,
        category: category ?? this.category,
        range: range,
        minAmount: minAmount,
        maxAmount: maxAmount,
        store: store,
      );

  /// Drops the advanced refinements but keeps the search text and the category
  /// chip, which the user set from the screen and can still see.
  ReceiptFilter clearAdvanced() =>
      ReceiptFilter(query: query, category: category);

  /// True when the advanced sheet is narrowing anything, i.e. when the summary
  /// bar earns its space. Search and category stay out: they are already visible
  /// on screen as text in the box and a highlighted chip.
  bool get hasAdvancedFilters =>
      range != null || minAmount != null || maxAmount != null || store != null;

  /// Number of advanced groups in use, for the badge on the filter button. A min
  /// and a max still count once: they are one "nominal" refinement.
  int get advancedCount {
    int count = 0;
    if (range != null) {
      count++;
    }
    if (minAmount != null || maxAmount != null) {
      count++;
    }
    if (store != null) {
      count++;
    }
    return count;
  }

  /// One line for the summary bar, e.g.
  /// "1 Nov 2026 – 16 Nov 2026 · ≥ Rp10.000 · Indomaret".
  String get summary {
    final List<String> parts = <String>[];

    final DateTimeRange? days = range;
    if (days != null) {
      parts.add(
        sameDay(days.start, days.end)
            ? formatDate(dayOnly(days.start))
            : '${formatDate(dayOnly(days.start))} – '
                '${formatDate(dayOnly(days.end))}',
      );
    }

    final int? min = minAmount;
    final int? max = maxAmount;
    if (min != null && max != null) {
      parts.add('${rupiah(min)} – ${rupiah(max)}');
    } else if (min != null) {
      parts.add('≥ ${rupiah(min)}');
    } else if (max != null) {
      parts.add('≤ ${rupiah(max)}');
    }

    final String? shop = store;
    if (shop != null) {
      parts.add(shop);
    }

    return parts.join(' · ');
  }

  /// Receipts matching every active refinement, in their original order.
  List<db.Receipt> apply(
    List<db.Receipt> receipts,
    String Function(int categoryId) categoryName,
  ) {
    return receipts
        .where((db.Receipt receipt) => matches(receipt, categoryName))
        .toList();
  }

  bool matches(
    db.Receipt receipt,
    String Function(int categoryId) categoryName,
  ) {
    if (!_matchesQuery(receipt)) {
      return false;
    }

    if (category != allCategories &&
        !receipt.transactions.any(
          (db.Transaction item) =>
              categoryName(item.categoryId) == category,
        )) {
      return false;
    }

    final DateTimeRange? days = range;
    if (days != null && !_within(days, receipt.transactionDate)) {
      return false;
    }

    final int? min = minAmount;
    if (min != null && receipt.totalAmount < min) {
      return false;
    }

    final int? max = maxAmount;
    if (max != null && receipt.totalAmount > max) {
      return false;
    }

    final String? shop = store;
    if (shop != null &&
        receipt.storeName.trim().toLowerCase() != shop.trim().toLowerCase()) {
      return false;
    }

    return true;
  }

  bool _matchesQuery(db.Receipt receipt) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    return receipt.storeName.toLowerCase().contains(q) ||
        receipt.transactions.any(
          (db.Transaction item) => item.itemName.toLowerCase().contains(q),
        );
  }

  static bool _within(DateTimeRange days, DateTime date) {
    final DateTime day = dayOnly(date);
    return !day.isBefore(dayOnly(days.start)) &&
        !day.isAfter(dayOnly(days.end));
  }
}
