import 'dart:math' as math;

import '../models/receipt_model.dart';

/// Result of fitting a simple Linear Regression (`y = a + b·x`) over the
/// monthly spending history.
///
/// [actual] and [fitted] are aligned by index; [predicted] is the fitted value
/// for the month after the last observation. Metrics are in-sample, i.e. the
/// model is scored on the same months it was fitted on — with only a handful of
/// points that is the honest option, and the UI labels it as an estimate.
class ForecastResult {
  const ForecastResult({
    required this.hasEnoughData,
    required this.sampleCount,
    required this.predicted,
    required this.mae,
    required this.rmse,
    required this.rSquared,
    required this.slope,
    required this.actual,
    required this.fitted,
    required this.labels,
  });

  /// Empty result used when there is no usable history at all.
  static const ForecastResult insufficient = ForecastResult(
    hasEnoughData: false,
    sampleCount: 0,
    predicted: 0,
    mae: 0,
    rmse: 0,
    rSquared: 0,
    slope: 0,
    actual: <double>[],
    fitted: <double>[],
    labels: <String>[],
  );

  /// False when fewer than [SpendingForecaster.minMonths] months carry data.
  final bool hasEnoughData;

  final int sampleCount;

  /// Estimated spending for the month after the last observation.
  final double predicted;

  final double mae;
  final double rmse;
  final double rSquared;

  /// Monthly change in rupiah (positive = spending is trending up).
  final double slope;

  final List<double> actual;
  final List<double> fitted;
  final List<String> labels;

  /// Predicted change relative to the last actual month, as a fraction.
  ///
  /// Null when the last month had no spending, because a percentage against
  /// zero would be meaningless.
  double? get changeFromLastMonth {
    if (actual.isEmpty || actual.last == 0) {
      return null;
    }
    return (predicted - actual.last) / actual.last;
  }
}

/// Fits monthly spending with ordinary least squares.
class SpendingForecaster {
  const SpendingForecaster._();

  /// Minimum number of months with spending required to show a forecast.
  ///
  /// Below this the line would be defined by too few points to be meaningful,
  /// so the UI reports "data belum cukup" instead of inventing a number
  /// (business rule BR-08).
  static const int minMonths = 3;

  /// [series] must be ordered oldest → newest, one entry per month.
  static ForecastResult forecast(List<MonthlyTotal> series) {
    if (series.length < minMonths) {
      return ForecastResult(
        hasEnoughData: false,
        sampleCount: series.length,
        predicted: 0,
        mae: 0,
        rmse: 0,
        rSquared: 0,
        slope: 0,
        actual: series.map((MonthlyTotal m) => m.total).toList(),
        fitted: const <double>[],
        labels: series.map((MonthlyTotal m) => label(m.month)).toList(),
      );
    }

    final List<double> y = series.map((MonthlyTotal m) => m.total).toList();
    final int n = y.length;
    final List<double> x = List<double>.generate(n, (int i) => i.toDouble());

    final double meanX = x.reduce((double a, double b) => a + b) / n;
    final double meanY = y.reduce((double a, double b) => a + b) / n;

    double covariance = 0;
    double varianceX = 0;
    for (int i = 0; i < n; i++) {
      covariance += (x[i] - meanX) * (y[i] - meanY);
      varianceX += (x[i] - meanX) * (x[i] - meanX);
    }

    // A flat x-axis (all points in the same month) cannot happen with a
    // contiguous monthly series, but guard anyway.
    final double slope = varianceX == 0 ? 0 : covariance / varianceX;
    final double intercept = meanY - slope * meanX;

    final List<double> fitted = <double>[
      for (int i = 0; i < n; i++) intercept + slope * x[i],
    ];

    double absoluteError = 0;
    double squaredError = 0;
    for (int i = 0; i < n; i++) {
      final double error = y[i] - fitted[i];
      absoluteError += error.abs();
      squaredError += error * error;
    }

    double totalVariance = 0;
    for (int i = 0; i < n; i++) {
      totalVariance += (y[i] - meanY) * (y[i] - meanY);
    }

    final double mae = absoluteError / n;
    final double rmse = math.sqrt(squaredError / n);
    final double rSquared;
    if (totalVariance == 0) {
      // Every month had the same spending: a perfect fit if the line is flat.
      rSquared = squaredError == 0 ? 1 : 0;
    } else {
      rSquared = 1 - squaredError / totalVariance;
    }

    final double predicted = math.max(0, intercept + slope * n);

    return ForecastResult(
      hasEnoughData: true,
      sampleCount: n,
      predicted: predicted,
      mae: mae,
      rmse: rmse,
      rSquared: rSquared,
      slope: slope,
      actual: y,
      fitted: fitted,
      labels: series.map((MonthlyTotal m) => label(m.month)).toList(),
    );
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  /// Short Indonesian month label, e.g. `Sep`.
  static String label(DateTime month) => _months[month.month - 1];

  /// Short label for the month after [month].
  static String nextLabel(DateTime month) =>
      _months[DateTime(month.year, month.month + 1).month - 1];
}
