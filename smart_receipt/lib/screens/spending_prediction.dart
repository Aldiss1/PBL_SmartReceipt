import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../widgets/charts.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
import '../providers/receipt_provider.dart';
import '../services/spending_analytics.dart';
import '../services/spending_forecaster.dart';
import '../theme/theme_controller.dart';

/// Screen 10 - Spending Prediction.
///
/// Fits a Linear Regression over the last months of saved spending and shows
/// the estimate together with its MAE / RMSE / R². When there is not enough
/// history it says so instead of showing made-up numbers.
class SpendingPredictionScreen extends StatelessWidget {
  const SpendingPredictionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    final ReceiptProvider provider = context.watch<ReceiptProvider>();

    // Months before the first receipt are dropped so they do not act as zero
    // data points in the regression.
    final List<db.MonthlyTotal> series =
        SpendingAnalytics.trimLeadingEmpty(provider.monthlyTotals);
    final ForecastResult forecast = SpendingForecaster.forecast(series);

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
                  children: forecast.hasEnoughData
                      ? <Widget>[
                          _PredictionCard(forecast: forecast, series: series),
                          const SizedBox(height: 16),
                          _ChartCard(forecast: forecast, series: series),
                          const SizedBox(height: 16),
                          _MetricsCard(forecast: forecast),
                          const SizedBox(height: 16),
                          _InsightCard(forecast: forecast),
                        ]
                      : <Widget>[
                          _InsufficientDataCard(forecast: forecast),
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

/// Shown when fewer than [SpendingForecaster.minMonths] months have spending.
class _InsufficientDataCard extends StatelessWidget {
  const _InsufficientDataCard({required this.forecast});

  final ForecastResult forecast;

  @override
  Widget build(BuildContext context) {
    final int missing = SpendingForecaster.minMonths - forecast.sampleCount;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.hourglass_empty, size: 22, color: AppColors.amber),
              const SizedBox(width: 10),
              Text(
                'Data Belum Cukup',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Prediksi membutuhkan minimal ${SpendingForecaster.minMonths} bulan '
            'riwayat pengeluaran. Saat ini tersedia ${forecast.sampleCount} bulan '
            'dengan data.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textLabel,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Pindai struk setidaknya di ${missing > 0 ? missing : 1} bulan lain '
            'agar model dapat menghitung tren tanpa mengarang angka.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.forecast, required this.series});

  final ForecastResult forecast;
  final List<db.MonthlyTotal> series;

  @override
  Widget build(BuildContext context) {
    final List<Color>? bannerGradient = AppColors.spendBannerGradient;
    final DateTime nextMonth = SpendingAnalytics.addMonths(
      series.last.month,
      1,
    );
    final double? change = forecast.changeFromLastMonth;
    final bool up = (change ?? 0) >= 0;

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
          Row(
            children: <Widget>[
              Text(
                'Prediksi Bulan Depan',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.onSpendBannerMuted,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.spendBannerObjectBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${SpendingForecaster.nextLabel(series.last.month)} ${nextMonth.year}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSpendBannerSubtle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rupiah(forecast.predicted.round()),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.onSpendBanner,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.spendBannerObjectBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
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
                    change == null
                        ? 'Perbandingan tidak tersedia'
                        : '${up ? '+' : '-'}${(change.abs() * 100).toStringAsFixed(1)}% dari bulan ini',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.spendBannerAccent,
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.forecast, required this.series});

  final ForecastResult forecast;
  final List<db.MonthlyTotal> series;

  @override
  Widget build(BuildContext context) {
    final List<double> values = <double>[
      ...forecast.actual,
      forecast.predicted,
    ];
    final List<String> labels = <String>[
      ...forecast.labels,
      SpendingForecaster.nextLabel(series.last.month),
    ];

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
                  'Aktual & Prediksi',
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
            values: values,
            labels: labels,
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
  const _MetricsCard({required this.forecast});

  final ForecastResult forecast;

  @override
  Widget build(BuildContext context) {
    final List<List<String>> metrics = <List<String>>[
      <String>['MAE', rupiah(forecast.mae.round())],
      <String>['RMSE', rupiah(forecast.rmse.round())],
      <String>['R²', forecast.rSquared.toStringAsFixed(2)],
    ];

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
          const SizedBox(height: 6),
          Text(
            'Dihitung dari ${forecast.sampleCount} bulan data tersimpan.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (int i = 0; i < metrics.length; i++) ...<Widget>[
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            metrics[i][1],
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          metrics[i][0],
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
  const _InsightCard({required this.forecast});

  final ForecastResult forecast;

  String get _fitNote {
    if (forecast.rSquared >= 0.7) {
      return 'Model menjelaskan variasi data dengan baik (R² = '
          '${forecast.rSquared.toStringAsFixed(2)}).';
    }
    if (forecast.rSquared >= 0.4) {
      return 'Model cukup menjelaskan variasi data (R² = '
          '${forecast.rSquared.toStringAsFixed(2)}), tetapi tetap perkiraan.';
    }
    return 'Model masih lemah dalam menjelaskan variasi data (R² = '
        '${forecast.rSquared.toStringAsFixed(2)}); anggap angka ini estimasi kasar.';
  }

  @override
  Widget build(BuildContext context) {
    final bool up = forecast.slope >= 0;
    final String direction = up ? 'naik' : 'turun';
    final String text = 'Berdasarkan ${forecast.sampleCount} bulan histori, '
        'pengeluaran cenderung $direction sekitar '
        '${rupiah(forecast.slope.abs().round())} per bulan. $_fitNote';

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
              text,
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
