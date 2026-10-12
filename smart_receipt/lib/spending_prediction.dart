import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_widgets.dart';
import 'charts.dart';
import 'models.dart';
import 'theme_controller.dart';

/// Screen 10 - Spending Prediction.
class SpendingPredictionScreen extends StatelessWidget {
  const SpendingPredictionScreen({super.key});

  static const int _predicted = 1580000;
  static const List<double> _series = <double>[0.98, 1.12, 1.06, 1.24, 1.27, 1.42, 1.58];
  static const List<String> _labels = <String>['Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt'];

  static const List<List<String>> _metrics = <List<String>>[
    <String>['MAE', 'Rp42.000'],
    <String>['RMSE', 'Rp58.000'],
    <String>['R²', '0.87'],
  ];

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const AppStatusBar(),
            AppTopBar(
              title: 'Prediksi Pengeluaran',
              subtitle: 'Linear Regression',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _PredictionCard(),
                    const SizedBox(height: 16),
                    const _ChartCard(),
                    const SizedBox(height: 16),
                    const _MetricsCard(),
                    const SizedBox(height: 16),
                    const _InsightCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: PrimaryButton(
                label: 'Kembali ke Analisis',
                icon: Icons.bar_chart,
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard();

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
          Row(
            children: <Widget>[
              const Text(
                'Prediksi Bulan Depan',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF9BA3B5)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Okt 2026',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC7CBD6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rupiah(SpendingPredictionScreen._predicted),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.trending_up, size: 15, color: AppColors.orange),
                    const SizedBox(width: 6),
                    Text(
                      '+11.3% dari bulan ini',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard();

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Aktual vs Prediksi',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              _LegendDot(color: AppColors.navy, label: 'Aktual'),
              const SizedBox(width: 12),
              _LegendDot(color: AppColors.orange, label: 'Prediksi'),
            ],
          ),
          const SizedBox(height: 18),
          TrendLineChart(
            values: SpendingPredictionScreen._series,
            labels: SpendingPredictionScreen._labels,
            highlightLast: true,
            color: AppColors.navy,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Metrik Evaluasi Model',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (int i = 0; i < SpendingPredictionScreen._metrics.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.iconBox,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          SpendingPredictionScreen._metrics[i][1],
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          SpendingPredictionScreen._metrics[i][0],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.promoBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.auto_awesome, size: 20, color: AppColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Berdasarkan 6 bulan histori, pengeluaran cenderung meningkat sekitar 11% tiap bulan. Model cukup baik dalam menjelaskan variasi data (R² = 0.87).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
