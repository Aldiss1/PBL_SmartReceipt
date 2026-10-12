import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import '../widgets/charts.dart';
import '../models/models.dart';
import '../ocr/tfidf_classifier.dart';
import '../services/model_evaluator.dart';
import '../services/text_normalizer.dart';
import 'spending_prediction.dart';
import '../theme/theme_controller.dart';

/// Screen 9 - Analysis.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int _period = 0;

  /// Real evaluation of the classifier, computed on first build.
  EvaluationReport? _evaluation;
  bool _evaluating = true;

  @override
  void initState() {
    super.initState();
    _runEvaluation();
  }

  /// Scores the exported model over the dummy eval dataset and reports the
  /// real accuracy / precision / recall / F1 / confusion matrix.
  Future<void> _runEvaluation() async {
    final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
    final IndonesianTextPreprocessor preprocessor = IndonesianTextPreprocessor();
    EvaluationReport? report;
    try {
      await engine.load();
      await preprocessor.loadFromAsset();
      final List<LabeledSample> samples = await ModelEvaluator.loadDataset();
      report = ModelEvaluator(
        engine: engine,
        preprocess: preprocessor.normalize,
      ).evaluate(samples);
    } catch (_) {
      report = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _evaluation = report;
      _evaluating = false;
    });
  }

  static const List<_Period> _periods = <_Period>[
    _Period(label: 'Bulan Ini', total: 1420000, range: '1 - 30 Sep 2026'),
    _Period(label: '3 Bulan', total: 3960000, range: 'Jul - Sep 2026'),
    _Period(label: 'Tahun Ini', total: 15420000, range: 'Jan - Sep 2026'),
  ];

  static const List<double> _trend = <double>[0.98, 1.12, 1.06, 1.24, 1.27, 1.42];
  static const List<String> _trendLabels = <String>['Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep'];

  static List<_CategorySpend> get _categories => <_CategorySpend>[
    _CategorySpend(name: 'Makanan', percent: 44, amount: 620000, color: AppColors.navy),
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
                    _ModelEvaluationCard(
                      report: _evaluation,
                      loading: _evaluating,
                    ),
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
    final List<Color>? bannerGradient = AppColors.spendBannerGradient;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.spendBanner,
        gradient: bannerGradient == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bannerGradient,
                stops: const <double>[0.0, 0.5, 1.0],
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Total Pengeluaran',
            style: TextStyle(fontSize: 12.5, color: AppColors.onSpendBannerMuted),
          ),
          const SizedBox(height: 8),
          Text(
            rupiah(period.total),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.onSpendBanner,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            period.range,
            style: TextStyle(fontSize: 11.5, color: AppColors.onSpendBannerMuted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.spendBannerObjectBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
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
                  Icons.trending_up,
                  size: 15,
                  color: AppColors.spendBannerAccent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '12% lebih tinggi dari periode sebelumnya',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSpendBannerSubtle,
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
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.insights, size: 24, color: AppColors.bg),
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

// ---------------------------------------------------------------------------
// Model evaluation (real metrics, no hard-coded numbers)
// ---------------------------------------------------------------------------

/// Reports the classifier's real performance on the dummy evaluation dataset.
///
/// Numbers come from [ModelEvaluator] at runtime — accuracy, macro/weighted
/// precision-recall-F1 and the confusion matrix are computed from the model's
/// actual predictions, replacing the old hard-coded 92.4% / 90.1% placeholders.
class _ModelEvaluationCard extends StatelessWidget {
  const _ModelEvaluationCard({required this.report, required this.loading});

  final EvaluationReport? report;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.verified_outlined, size: 18, color: AppColors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evaluasi Model Klasifikasi',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'TF-IDF + Naive Bayes • dihitung dari dataset dummy',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (loading)
            Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.navy),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Menghitung metrik…',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textLabel),
                ),
              ],
            )
          else if (report == null)
            Text(
              'Metrik belum tersedia — model atau dataset evaluasi gagal dimuat.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textLabel,
              ),
            )
          else ...<Widget>[
            _metricsGrid(report!),
            const SizedBox(height: 18),
            Text(
              'Confusion Matrix (${report!.labels.length}×${report!.labels.length})',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Baris = label asli, kolom = prediksi model',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            _ConfusionMatrixView(report: report!),
          ],
        ],
      ),
    );
  }

  Widget _metricsGrid(EvaluationReport r) {
    final List<List<String>> items = <List<String>>[
      <String>['Akurasi', _pct(r.accuracy)],
      <String>['Precision', _pct(r.weightedPrecision)],
      <String>['Recall', _pct(r.weightedRecall)],
      <String>['F1-Score', _pct(r.weightedF1)],
      <String>['Macro F1', _pct(r.macroF1)],
      <String>['Data uji', '${r.sampleCount} item'],
    ];
    return Column(
      children: <Widget>[
        for (int row = 0; row < items.length; row += 3) ...<Widget>[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (int col = 0; col < 3; col++) ...<Widget>[
                if (col > 0) const SizedBox(width: 8),
                Expanded(
                  child: col + row < items.length
                      ? _MetricTile(
                          label: items[row + col][0],
                          value: items[row + col][1],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.iconBox,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact, horizontally scrollable confusion-matrix heatmap.
///
/// Each cell is tinted by its share of the row (recall contribution) so correct
/// predictions stand out along the diagonal.
class _ConfusionMatrixView extends StatelessWidget {
  const _ConfusionMatrixView({required this.report});

  final EvaluationReport report;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = report.labels;
    final List<List<int>> matrix = report.confusionMatrix;
    int maxCell = 1;
    for (final List<int> row in matrix) {
      for (final int v in row) {
        if (v > maxCell) {
          maxCell = v;
        }
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int r = 0; r < labels.length; r++)
            Row(
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    labels[r],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLabel,
                    ),
                  ),
                ),
                for (int c = 0; c < labels.length; c++)
                  _MatrixCell(
                    value: matrix[r][c],
                    intensity: matrix[r][c] / maxCell,
                    diagonal: r == c,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    required this.value,
    required this.intensity,
    required this.diagonal,
  });

  final int value;
  final double intensity;
  final bool diagonal;

  @override
  Widget build(BuildContext context) {
    final Color base = diagonal ? AppColors.green : AppColors.orange;
    return Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: value == 0
            ? AppColors.iconBox
            : base.withValues(alpha: 0.14 + 0.72 * intensity),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        value == 0 ? '' : '$value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: value == 0 || intensity < 0.4
              ? AppColors.textDark
              : AppColors.onButton,
        ),
      ),
    );
  }
}
