import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_nav.dart';
import 'app_route.dart';
import 'app_widgets.dart';
import 'charts.dart';
import 'models.dart';
import 'spending_prediction.dart';
import 'theme_controller.dart';

/// Screen 9 - Analysis.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int _period = 0;

  static const List<_Period> _periods = <_Period>[
    _Period(label: 'Bulan Ini', total: 1420000, range: '1 - 30 Sep 2026'),
    _Period(label: '3 Bulan', total: 3960000, range: 'Jul - Sep 2026'),
    _Period(label: 'Tahun Ini', total: 15420000, range: 'Jan - Sep 2026'),
  ];

  static const List<double> _trend = <double>[0.98, 1.12, 1.06, 1.24, 1.27, 1.42];
  static const List<String> _trendLabels = <String>['Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep'];

  static List<_CategorySpend> get _categories => <_CategorySpend>[
    _CategorySpend(name: 'Makanan', percent: 44, amount: 620000, color: AppColors.barAccent),
    _CategorySpend(name: 'Rumah Tangga', percent: 24, amount: 340000, color: AppColors.mutedScale[0]),
    _CategorySpend(name: 'Minuman', percent: 20, amount: 280000, color: AppColors.mutedScale[1]),
    _CategorySpend(name: 'Transportasi', percent: 12, amount: 180000, color: AppColors.mutedScale[2]),
  ];

  @override
  Widget build(BuildContext context) {
    final _Period p = _periods[_period];
    ThemeScope.watch(context);

    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: FloatingNavBody(
          nav: AppBottomNav(
            activeIndex: 3,
            onSelect: (int i) => navigateTab(context, i),
            onScan: () => openScan(context),
          ),
          child: Column(
          children: <Widget>[
            const AppStatusBar(),
            AppTopBar(
              title: 'Analisis Pengeluaran',
              subtitle: 'Ringkasan & distribusi',
              actions: <Widget>[CircleIconButton(icon: Icons.tune, onTap: () {})],
            ),
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
                  children: <Widget>[
                    _PeriodSelector(
                      periods: _periods,
                      selected: _period,
                      onSelect: (int i) => setState(() => _period = i),
                    ),
                    const SizedBox(height: 16),
                    _TotalCard(period: p),
                    const SizedBox(height: 14),
                    const _StatsRow(),
                    const SizedBox(height: 16),
                    _CategoryCard(categories: _categories),
                    const SizedBox(height: 16),
                    const _TrendCard(),
                    const SizedBox(height: 16),
                    _PredictionCta(
                      onTap: () => Navigator.push(
                        context,
                        appRoute(const SpendingPredictionScreen()),
                      ),
                    ),
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

class _Period {
  const _Period({required this.label, required this.total, required this.range});

  final String label;
  final int total;
  final String range;
}

class _CategorySpend {
  const _CategorySpend({
    required this.name,
    required this.percent,
    required this.amount,
    required this.color,
  });

  final String name;
  final int percent;
  final int amount;
  final Color color;
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.periods,
    required this.selected,
    required this.onSelect,
  });

  final List<_Period> periods;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < periods.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.buttonBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    periods[i].label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: i == selected ? AppColors.onButton : AppColors.textLabel,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.period});

  final _Period period;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.heroGradient,
          stops: const <double>[0, 0.5, 1],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Total Pengeluaran',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF9BA3B5)),
          ),
          const SizedBox(height: 8),
          Text(
            rupiah(period.total),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            period.range,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF9BA3B5)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.trending_up, size: 15, color: AppColors.orange),
                SizedBox(width: 7),
                Text(
                  '12% lebih tinggi dari periode sebelumnya',
                  style: TextStyle(fontSize: 11, color: Color(0xFFC7CBD6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const <Widget>[
        Expanded(
          child: _MiniStat(
            icon: Icons.receipt_long,
            label: 'Total Struk',
            value: '18',
            suffix: 'struk',
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: _MiniStat(
            icon: Icons.show_chart,
            label: 'Rata-rata / Hari',
            value: 'Rp47.333',
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? suffix;

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
        children: <Widget>[
          Row(
            children: <Widget>[
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
              children: <TextSpan>[
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
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.categories});

  final List<_CategorySpend> categories;

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
        children: <Widget>[
          SectionHeader(
            title: 'Pengeluaran per Kategori',
            trailing: Text(
              '${categories.length} Kategori',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < categories.length; i++)
            _CategoryBar(data: categories[i], isFirst: i == 0),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.data, required this.isFirst});

  final _CategorySpend data;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final double fraction = data.percent / 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
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
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(width: 10),
              Text(
                rupiah(data.amount),
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
              children: <Widget>[
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
                        color: AppColors.barMarker,
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

class _TrendCard extends StatelessWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Tren 6 Bulan',
            trailing: Text(
              'dalam juta Rp',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 18),
          TrendLineChart(
            values: _AnalysisScreenState._trend,
            labels: _AnalysisScreenState._trendLabels,
            highlightLast: true,
            color: AppColors.navy,
          ),
        ],
      ),
    );
  }
}

class _PredictionCta extends StatelessWidget {
  const _PredictionCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.promoBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.insights, size: 24, color: AppColors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Prediksi Bulan Depan',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Estimasi dengan Linear Regression',
                      style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppColors.amber),
            ],
          ),
        ),
      ),
    );
  }
}
