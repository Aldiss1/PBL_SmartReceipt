import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../widgets/app_widgets.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
import '../providers/receipt_provider.dart';
import '../theme/theme_controller.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    final ReceiptProvider provider = context.watch<ReceiptProvider>();
    final List<_TransactionData> recent = <_TransactionData>[
      for (final db.Receipt receipt in provider.recentReceipts(3))
        _TransactionData(
          icon: receipt.transactions.isEmpty
              ? Icons.receipt_long_outlined
              : categoryByName(
                  provider.categoryNameFor(receipt.transactions.first.categoryId),
                ).icon,
          name: receipt.storeName,
          category: receipt.transactions.isEmpty
              ? 'Lainnya'
              : provider.categoryNameFor(receipt.transactions.first.categoryId),
          datetime: formatDateTime(receipt.transactionDate),
          amount: '-${rupiah(receipt.totalAmount.round())}',
        ),
    ];

    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: FloatingNavBody(
          nav: AppBottomNav(
            activeIndex: 0,
            onSelect: (int i) => navigateTab(context, i),
            onScan: () => openScan(context),
          ),
          child: Column(
          children: [
            const AppStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  22,
                  6,
                  22,
                  24 + AppBottomNav.clearance(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Header(),
                    const SizedBox(height: 20),
                    const _GreetingSection(),
                    const SizedBox(height: 18),
                    _MonthlySpendCard(
                      total: provider.totalThisMonth,
                      change: provider.monthOverMonthChange,
                    ),
                    const SizedBox(height: 14),
                    _StatsRow(
                      receiptCount: provider.countThisMonth,
                      averagePerDay: provider.averagePerDayThisMonth,
                    ),
                    const SizedBox(height: 14),
                    _CategoryCard(data: _categoryData(provider)),
                    const SizedBox(height: 18),
                    const _RecentTransactionsHeader(),
                    const SizedBox(height: 10),
                    if (recent.isEmpty)
                      const _NoTransactionsHint()
                    else
                      ...recent.map(_TransactionCard.new),
                    const SizedBox(height: 8),
                    const _ScanPromoCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Turns the current month's category totals into rows for the breakdown card,
/// largest first, keeping at most four.
List<_CategoryData> _categoryData(ReceiptProvider provider) {
  final List<MapEntry<String, double>> entries =
      provider.spendingByCategory.entries.toList()
        ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
            b.value.compareTo(a.value));

  final double total = entries.fold<double>(
    0,
    (double sum, MapEntry<String, double> e) => sum + e.value,
  );
  final List<Color> colors = AppColors.palette.categoryColors;

  return <_CategoryData>[
    for (int i = 0; i < entries.length && i < 4; i++)
      _CategoryData(
        name: entries[i].key,
        percent: total == 0 ? 0 : (entries[i].value / total * 100).round(),
        amount: rupiah(entries[i].value.round()),
        color: colors[i % colors.length],
      ),
  ];
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Beranda',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
        Icon(Icons.notifications_none, size: 26, color: AppColors.textDark),
        const SizedBox(width: 14),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.avatarColor('Rian Pratama'),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, size: 22, color: Colors.white),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Greeting
// ---------------------------------------------------------------------------

class _GreetingSection extends StatelessWidget {
  const _GreetingSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DASHBOARD FINANSIAL',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLabel,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Selamat datang, Rian',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '',
                style: TextStyle(fontSize: 20, height: 1.1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const _DateChip(),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip();

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    const List<String> months = <String>[
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 6, 9, 6),
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_month, size: 18, color: AppColors.amber),
          SizedBox(width: 7),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                months[now.month - 1],
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '${now.year}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textDark),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly spend card
// ---------------------------------------------------------------------------

class _MonthlySpendCard extends StatelessWidget {
  const _MonthlySpendCard({required this.total, required this.change});

  final double total;

  /// Fractional change versus last month; null when last month was empty.
  final double? change;

  @override
  Widget build(BuildContext context) {
    final List<Color>? bannerGradient = AppColors.spendBannerGradient;
    return Container(
      height: 158,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.spendBanner,
        gradient: bannerGradient == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bannerGradient,
                stops: const [0.0, 0.5, 1.0],
              ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 18,
            right: 18,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.spendBannerObjectBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.center_focus_strong,
                size: 22,
                color: AppColors.spendBannerAccent,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pengeluaran Bulan Ini',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSpendBannerMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  rupiah(total.round()),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: AppColors.onSpendBanner,
                  ),
                ),
                const SizedBox(height: 14),
                _GrowthBadge(change: change),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthBadge extends StatelessWidget {
  const _GrowthBadge({required this.change});

  final double? change;

  @override
  Widget build(BuildContext context) {
    final double? change = this.change;
    final bool up = (change ?? 0) >= 0;
    final String label;
    if (change == null) {
      label = 'Belum ada data bulan lalu';
    } else {
      label = '${(change.abs() * 100).toStringAsFixed(0)}% '
          '${up ? 'lebih tinggi' : 'lebih rendah'} dari bulan lalu';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.spendBannerObjectBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 7,
            height: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.spendBannerAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            change == null
                ? Icons.remove
                : (up ? Icons.trending_up : Icons.trending_down),
            size: 15,
            color: AppColors.spendBannerAccent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.onSpendBannerSubtle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.receiptCount, required this.averagePerDay});

  final int receiptCount;
  final double averagePerDay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.receipt_long,
            label: 'Struk Bulan Ini',
            value: '$receiptCount',
            suffix: 'struk',
            subtitle: receiptCount == 0
                ? 'Belum ada struk bulan ini'
                : 'Tersimpan di perangkat',
            subtitleColor:
                receiptCount == 0 ? AppColors.textMuted : AppColors.green,
            subtitleWeight:
                receiptCount == 0 ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            icon: Icons.show_chart,
            label: 'Rata-rata / Hari',
            value: rupiah(averagePerDay.round()),
            subtitle: 'Basis ${DateTime.now().day} hari berjalan',
            subtitleColor: AppColors.textMuted,
            subtitleWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.subtitleColor,
    required this.subtitleWeight,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? suffix;
  final String subtitle;
  final Color subtitleColor;
  final FontWeight subtitleWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.amber),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                if (suffix != null)
                  TextSpan(
                    text: ' $suffix',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: subtitleWeight,
              color: subtitleColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category breakdown
// ---------------------------------------------------------------------------

class _CategoryData {
  const _CategoryData({
    required this.name,
    required this.percent,
    required this.amount,
    required this.color,
  });

  final String name;
  final int percent;
  final String amount;
  final Color color;
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.data});

  final List<_CategoryData> data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pengeluaran per Kategori',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                '${data.length} Kategori',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(
                'Belum ada pengeluaran bulan ini.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            )
          else
            for (var i = 0; i < data.length; i++)
              _CategoryRow(data: data[i], isFirst: i == 0),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.data, required this.isFirst});

  final _CategoryData data;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final double fraction = data.percent / 100;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: isFirst ? AppColors.orange : AppColors.heroTrack,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                '${data.percent}%',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                data.amount,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 12,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.track,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: data.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (isFirst)
                  Align(
                    alignment: Alignment(fraction * 2 - 1, 0),
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent transactions
// ---------------------------------------------------------------------------

class _TransactionData {
  const _TransactionData({
    required this.icon,
    required this.name,
    required this.category,
    required this.datetime,
    required this.amount,
  });

  final IconData icon;
  final String name;
  final String category;
  final String datetime;
  final String amount;
}

class _NoTransactionsHint extends StatelessWidget {
  const _NoTransactionsHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.receipt_long_outlined, size: 22, color: AppColors.iconMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Belum ada transaksi tersimpan. Pindai struk pertama Anda untuk '
              'melihat ringkasan di sini.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTransactionsHeader extends StatelessWidget {
  const _RecentTransactionsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Transaksi Terbaru',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => navigateTab(context, 1),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: <Widget>[
              Text(
                'Lihat Semua',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.amber,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: AppColors.amber),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard(this.t);

  final _TransactionData t;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.iconBox,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(t.icon, size: 22, color: AppColors.iconMuted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lavender,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t.category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.chipText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  t.datetime,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t.amount,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 13, color: AppColors.green),
                  const SizedBox(width: 3),
                  Text(
                    'Valid',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan promo
// ---------------------------------------------------------------------------

class _ScanPromoCard extends StatelessWidget {
  const _ScanPromoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.promoBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              size: 24,
              color: Color(0xFF3A2A00),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ada struk belanjaan baru?',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Otomatis deteksi pos & total pengeluaran',
                  maxLines: 2,
                  style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => openScan(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.buttonBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.center_focus_strong,
                    size: 17,
                    color: AppColors.onButton,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Scan',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onButton,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation is provided by AppBottomNav (see app_widgets.dart).
// ---------------------------------------------------------------------------

