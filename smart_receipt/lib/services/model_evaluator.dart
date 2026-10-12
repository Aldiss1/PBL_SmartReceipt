import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../ocr/tfidf_classifier.dart';

/// A single labelled example used to score the classifier.
class LabeledSample {
  const LabeledSample({required this.text, required this.label});

  /// Raw item name / OCR line.
  final String text;

  /// Ground-truth model class label, e.g. "Makanan".
  final String label;
}

/// Per-class precision / recall / F1 plus the support (number of true items).
class ClassMetrics {
  const ClassMetrics({
    required this.label,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.support,
  });

  final String label;
  final double precision;
  final double recall;
  final double f1;
  final int support;
}

/// Complete evaluation report for the classifier over a labelled dataset.
class EvaluationReport {
  const EvaluationReport({
    required this.accuracy,
    required this.macroPrecision,
    required this.macroRecall,
    required this.macroF1,
    required this.weightedPrecision,
    required this.weightedRecall,
    required this.weightedF1,
    required this.classMetrics,
    required this.confusionMatrix,
    required this.labels,
    required this.sampleCount,
    required this.correctCount,
  });

  /// Fraction of samples whose predicted label matches the ground truth.
  final double accuracy;

  final double macroPrecision;
  final double macroRecall;
  final double macroF1;
  final double weightedPrecision;
  final double weightedRecall;
  final double weightedF1;

  /// Metrics broken down per class, ordered by [labels].
  final List<ClassMetrics> classMetrics;

  /// `confusionMatrix[actualIndex][predictedIndex] = count`.
  final List<List<int>> confusionMatrix;

  /// Label order for both [confusionMatrix] rows/columns and [classMetrics].
  final List<String> labels;

  final int sampleCount;
  final int correctCount;

  /// Total predicted+actual cells, handy for a quick "sample size" subtitle.
  int get labelCount => labels.length;
}

/// Computes real classification metrics from a labelled dataset.
///
/// Nothing here is hard-coded: accuracy, per-class precision/recall/F1 (macro
/// and support-weighted) and the full confusion matrix are derived from the
/// model's actual predictions. Precision/recall use the standard definitions,
/// with a zero-division guard returning 0.0 for classes the model never
/// predicts and that never appear in the ground truth.
class ModelEvaluator {
  ModelEvaluator({
    required this.engine,
    this.preprocess,
  });

  final TfidfNaiveBayesEngine engine;

  /// Optional preprocessing applied before vectorization; when omitted the raw
  /// sample text is classified directly.
  final String Function(String raw)? preprocess;

  /// Loads the labelled dataset from `assets/`.
  ///
  /// Expected shape:
  /// ```json
  /// { "samples": [ { "text": "INDOMIE GORENG", "label": "Makanan" } ] }
  /// ```
  static Future<List<LabeledSample>> loadDataset({
    String assetPath = 'assets/eval_dataset_dummy.json',
  }) async {
    final String raw = await rootBundle.loadString(assetPath);
    return parseDataset(raw);
  }

  /// Parses a dataset already in memory. Extracted so tests need no assets.
  static List<LabeledSample> parseDataset(String rawJson) {
    final Map<String, dynamic> json = jsonDecode(rawJson) as Map<String, dynamic>;
    final Object? samples = json['samples'];
    if (samples is! List) {
      throw const FormatException(
        'Dataset evaluasi harus punya array "samples".',
      );
    }
    final List<LabeledSample> result = <LabeledSample>[];
    for (final Object? entry in samples) {
      if (entry is! Map) {
        continue;
      }
      final Object? text = entry['text'];
      final Object? label = entry['label'];
      if (text is String && label is String && text.trim().isNotEmpty) {
        result.add(LabeledSample(text: text, label: label));
      }
    }
    return result;
  }

  /// Runs the model over [samples] and returns the full report.
  EvaluationReport evaluate(Iterable<LabeledSample> samples) {
    // Label universe = every label the model knows, so confusion-matrix rows
    // are stable regardless of which classes appear in this dataset. Kept as a
    // growable list because unseen predictions (e.g. the fallback label) are
    // appended on the fly.
    final List<String> labels = <String>[...engine.classes];
    for (final LabeledSample s in samples) {
      if (!labels.contains(s.label)) {
        labels.add(s.label);
      }
    }
    final Map<String, int> indexOf = <String, int>{
      for (int i = 0; i < labels.length; i++) labels[i]: i,
    };

    final List<List<int>> matrix = <List<int>>[
      for (int i = 0; i < labels.length; i++) <int>[
        for (int j = 0; j < labels.length; j++) 0,
      ],
    ];

    int correct = 0;
    int total = 0;
    for (final LabeledSample sample in samples) {
      final String input = preprocess == null ? sample.text : preprocess!(sample.text);
      final String predicted = engine.predict(input).label;
      final int actualIndex = indexOf[sample.label] ?? -1;
      if (actualIndex < 0) {
        continue;
      }
      // Predictions may fall back to a label not present in the dataset
      // (e.g. "Perlu Review"); map unknown predictions to their own slot.
      int predictedIndex = indexOf[predicted] ?? -1;
      if (predictedIndex < 0) {
        labels.add(predicted);
        indexOf[predicted] = labels.length - 1;
        for (final List<int> row in matrix) {
          row.add(0);
        }
        matrix.add(<int>[for (int j = 0; j < labels.length; j++) 0]);
        predictedIndex = labels.length - 1;
      }
      matrix[actualIndex][predictedIndex] += 1;
      total += 1;
      if (actualIndex == predictedIndex) {
        correct += 1;
      }
    }

    final List<ClassMetrics> perClass = <ClassMetrics>[];
    double macroP = 0;
    double macroR = 0;
    double macroF1 = 0;
    double weightedP = 0;
    double weightedR = 0;
    double weightedF1 = 0;
    int consideredClasses = 0;

    for (int c = 0; c < labels.length; c++) {
      int truePositive = matrix[c][c];
      int falsePositive = 0;
      int falseNegative = 0;
      for (int r = 0; r < labels.length; r++) {
        if (r != c) {
          falsePositive += matrix[r][c];
          falseNegative += matrix[c][r];
        }
      }
      final int support = truePositive + falseNegative;
      if (support == 0 && (truePositive + falsePositive) == 0) {
        // Class never occurs and is never predicted: skip from macro averages.
        perClass.add(
          ClassMetrics(
            label: labels[c],
            precision: 0,
            recall: 0,
            f1: 0,
            support: 0,
          ),
        );
        continue;
      }

      final double precision = (truePositive + falsePositive) == 0
          ? 0
          : truePositive / (truePositive + falsePositive);
      final double recall =
          support == 0 ? 0 : truePositive / support;
      final double f1 = (precision + recall) == 0
          ? 0
          : 2 * precision * recall / (precision + recall);

      perClass.add(
        ClassMetrics(
          label: labels[c],
          precision: precision,
          recall: recall,
          f1: f1,
          support: support,
        ),
      );

      macroP += precision;
      macroR += recall;
      macroF1 += f1;
      weightedP += precision * support;
      weightedR += recall * support;
      weightedF1 += f1 * support;
      consideredClasses += 1;
    }

    if (consideredClasses > 0) {
      macroP /= consideredClasses;
      macroR /= consideredClasses;
      macroF1 /= consideredClasses;
    }
    if (total > 0) {
      weightedP /= total;
      weightedR /= total;
      weightedF1 /= total;
    }

    return EvaluationReport(
      accuracy: total == 0 ? 0 : correct / total,
      macroPrecision: macroP,
      macroRecall: macroR,
      macroF1: macroF1,
      weightedPrecision: weightedP,
      weightedRecall: weightedR,
      weightedF1: weightedF1,
      classMetrics: perClass,
      confusionMatrix: matrix,
      labels: labels,
      sampleCount: total,
      correctCount: correct,
    );
  }
}
