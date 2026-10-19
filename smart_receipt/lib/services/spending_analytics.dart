import '../models/receipt_model.dart';

/// Pure-Dart spending aggregations over saved receipts.
///
/// All totals are derived from [Receipt.transactionDate] (the date printed on
/// the receipt), not from the row's `created_at`, so a receipt entered late
/// still lands in the month it actually belongs to.
///
/// Kept free of Flutter imports so it can be unit-tested without a widget or
/// database environment.
class SpendingAnalytics {
  const SpendingAnalytics._();

  /// Midnight on the first day of [d]'s month.
  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  /// Adds [months] calendar months to [d], normalising to the first day.
  static DateTime addMonths(DateTime d, int months) =>
      DateTime(d.year, d.month + months);

  /// Whether [date] falls inside the half-open range `[from, toExclusive)`.
  static bool inRange(DateTime date, DateTime from, DateTime toExclusive) =>
      !date.isBefore(from) && date.isBefore(toExclusive);

  /// Sum of `totalAmount` for receipts inside `[from, toExclusive)`.
  static double totalBetween(
    List<Receipt> receipts, {
    required DateTime from,
    required DateTime toExclusive,
  }) {
    double total = 0;
    for (final Receipt receipt in receipts) {
      if (inRange(receipt.transactionDate, from, toExclusive)) {
        total += receipt.totalAmount;
      }
    }
    return total;
  }

  /// Number of receipts inside `[from, toExclusive)`.
  static int countBetween(
    List<Receipt> receipts, {
    required DateTime from,
    required DateTime toExclusive,
  }) {
    int count = 0;
    for (final Receipt receipt in receipts) {
      if (inRange(receipt.transactionDate, from, toExclusive)) {
        count += 1;
      }
    }
    return count;
  }

  /// Spending per category name inside `[from, toExclusive)`.
  ///
  /// Item-level totals are used (not the receipt header) so the breakdown adds
  /// up to the item sum even when a receipt also carries tax or rounding.
  static Map<String, double> byCategory(
    List<Receipt> receipts,
    Map<int, String> categoryNames, {
    required DateTime from,
    required DateTime toExclusive,
  }) {
    final Map<String, double> spending = <String, double>{};
    for (final Receipt receipt in receipts) {
      if (!inRange(receipt.transactionDate, from, toExclusive)) {
        continue;
      }
      for (final Transaction item in receipt.transactions) {
        final String name = categoryNames[item.categoryId] ?? 'Lainnya';
        spending[name] = (spending[name] ?? 0) + item.totalPrice;
      }
    }
    return spending;
  }

  /// Total spending per month for the last [months] calendar months, oldest
  /// first, ending with the current month. Months without receipts are present
  /// with a total of `0` so the trend chart keeps an even x-axis.
  static List<MonthlyTotal> monthlyTotals(
    List<Receipt> receipts, {
    int months = 6,
    DateTime? now,
  }) {
    final DateTime current = monthStart(now ?? DateTime.now());
    final List<MonthlyTotal> series = <MonthlyTotal>[];
    for (int offset = months - 1; offset >= 0; offset--) {
      final DateTime start = addMonths(current, -offset);
      series.add(
        MonthlyTotal(
          month: start,
          total: totalBetween(
            receipts,
            from: start,
            toExclusive: addMonths(start, 1),
          ),
        ),
      );
    }
    return series;
  }

  /// Drops leading months with no spending.
  ///
  /// Without this, months before the user's first receipt would act as zero
  /// data points and pull the regression line down artificially.
  static List<MonthlyTotal> trimLeadingEmpty(List<MonthlyTotal> series) {
    final int firstWithData = series.indexWhere((MonthlyTotal m) => m.total > 0);
    if (firstWithData < 0) {
      return const <MonthlyTotal>[];
    }
    return series.sublist(firstWithData);
  }
}
