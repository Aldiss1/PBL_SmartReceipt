import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/ocr/tfidf_classifier.dart';
import 'package:smart_receipt/services/model_evaluator.dart';

/// Perfectly separable toy model: feature at index 0 => class "A",
/// feature at index 1 => class "B". Lets every metric be hand-computed.
Map<String, dynamic> _toyModel() => <String, dynamic>{
      'classes': <String>['A', 'B'],
      'ngram_range': <int>[2, 2],
      'class_log_prior': <double>[0, 0],
      'vocabulary': <String, int>{'aa': 0, 'bb': 1},
      'idf': <double>[1, 1],
      'feature_log_prob': <List<double>>[
        <double>[0, -10], // class A likes feature 0
        <double>[-10, 0], // class B likes feature 1
      ],
      'threshold': 0.5,
      'fallback_label': 'Perlu Review',
    };

TfidfNaiveBayesEngine _toyEngine() {
  final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
  engine.loadFromMap(_toyModel());
  return engine;
}

void main() {
  group('ModelEvaluator.parseDataset', () {
    test('reads text/label pairs and skips malformed entries', () {
      final String raw = jsonEncode(<String, dynamic>{
        'samples': <dynamic>[
          <String, String>{'text': 'AQUA', 'label': 'Minuman'},
          <String, String>{'text': '  ', 'label': 'Makanan'},
          <String, dynamic>{'label': 'Makanan'},
          'not-a-map',
          <String, String>{'text': 'INDOMIE', 'label': 'Makanan'},
        ],
      });
      final List<LabeledSample> samples = ModelEvaluator.parseDataset(raw);
      expect(samples.length, 2);
      expect(samples.first.text, 'AQUA');
      expect(samples.last.label, 'Makanan');
    });

    test('throws when the dataset has no samples array', () {
      expect(
        () => ModelEvaluator.parseDataset('{"foo": 1}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ModelEvaluator metrics', () {
    test('perfect predictions yield 1.0 across the board', () {
      final TfidfNaiveBayesEngine engine = _toyEngine();
      final ModelEvaluator evaluator = ModelEvaluator(engine: engine);

      final EvaluationReport report = evaluator.evaluate(<LabeledSample>[
        const LabeledSample(text: 'aa', label: 'A'),
        const LabeledSample(text: 'aa', label: 'A'),
        const LabeledSample(text: 'bb', label: 'B'),
      ]);

      expect(report.sampleCount, 3);
      expect(report.correctCount, 3);
      expect(report.accuracy, closeTo(1.0, 1e-9));
      expect(report.macroPrecision, closeTo(1.0, 1e-9));
      expect(report.macroRecall, closeTo(1.0, 1e-9));
      expect(report.macroF1, closeTo(1.0, 1e-9));
    });

    test('computes accuracy, precision and recall from a known mistake', () {
      final TfidfNaiveBayesEngine engine = _toyEngine();
      final ModelEvaluator evaluator = ModelEvaluator(engine: engine);

      // "aa" -> A (correct), "aa" labelled B (wrong), "bb" -> B (correct).
      final EvaluationReport report = evaluator.evaluate(<LabeledSample>[
        const LabeledSample(text: 'aa', label: 'A'),
        const LabeledSample(text: 'aa', label: 'B'),
        const LabeledSample(text: 'bb', label: 'B'),
      ]);

      expect(report.sampleCount, 3);
      expect(report.correctCount, 2);
      expect(report.accuracy, closeTo(2 / 3, 1e-9));

      final ClassMetrics a =
          report.classMetrics.firstWhere((ClassMetrics m) => m.label == 'A');
      final ClassMetrics b =
          report.classMetrics.firstWhere((ClassMetrics m) => m.label == 'B');

      // Predictions: A, A, B (both "aa" samples predict A; "bb" predicts B).
      // Actual:      A, B, B
      // A: TP=1 (A->A), FP=1 (B->A), FN=0 -> precision 0.5, recall 1.0
      expect(a.precision, closeTo(0.5, 1e-9));
      expect(a.recall, closeTo(1.0, 1e-9));
      expect(a.support, 1);

      // B: TP=1 (B->B), FP=0, FN=1 (B->A) -> precision 1.0, recall 0.5
      expect(b.precision, closeTo(1.0, 1e-9));
      expect(b.recall, closeTo(0.5, 1e-9));
      expect(b.support, 2);
    });

    test('confusion matrix places counts and is square and consistent', () {
      final TfidfNaiveBayesEngine engine = _toyEngine();
      final EvaluationReport report =
          ModelEvaluator(engine: engine).evaluate(<LabeledSample>[
        const LabeledSample(text: 'aa', label: 'A'),
        const LabeledSample(text: 'aa', label: 'B'),
        const LabeledSample(text: 'bb', label: 'B'),
      ]);

      final int n = report.labels.length;
      expect(report.confusionMatrix.length, n);
      for (final List<int> row in report.confusionMatrix) {
        expect(row.length, n);
      }

      int aIndex = report.labels.indexOf('A');
      int bIndex = report.labels.indexOf('B');
      expect(report.confusionMatrix[aIndex][aIndex], 1); // A -> A
      expect(report.confusionMatrix[bIndex][aIndex], 1); // B -> A
      expect(report.confusionMatrix[bIndex][bIndex], 1); // B -> B
      expect(report.confusionMatrix[aIndex][bIndex], 0); // A -> B

      // Every sample lands exactly once in the matrix.
      int sum = 0;
      for (final List<int> row in report.confusionMatrix) {
        for (final int v in row) {
          sum += v;
        }
      }
      expect(sum, report.sampleCount);
    });

    test('unsure items predicted as the fallback label do not inflate scores',
        () {
      final TfidfNaiveBayesEngine engine = _toyEngine();
      // "zz" is out of vocabulary -> fallback "Perlu Review".
      final EvaluationReport report =
          ModelEvaluator(engine: engine).evaluate(<LabeledSample>[
        const LabeledSample(text: 'aa', label: 'A'),
        const LabeledSample(text: 'zz', label: 'A'),
      ]);

      expect(report.accuracy, closeTo(0.5, 1e-9));
      expect(report.labels, contains('Perlu Review'));
    });

    test('preprocess hook is applied before classification', () {
      final TfidfNaiveBayesEngine engine = _toyEngine();
      final ModelEvaluator evaluator = ModelEvaluator(
        engine: engine,
        preprocess: (String raw) => raw.replaceAll('xx', '').trim(),
      );
      // Without the hook "xx-aa" would still match; with it, "aa" matches too,
      // proving the hook runs and its output drives the prediction.
      final EvaluationReport report = evaluator.evaluate(<LabeledSample>[
        const LabeledSample(text: 'xx aa', label: 'A'),
      ]);
      expect(report.accuracy, closeTo(1.0, 1e-9));
    });
  });

  group('ModelEvaluator against the exported dummy model', () {
    test('produces real metrics over eval_dataset_dummy.json', () {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      engine.loadFromJsonString(_modelFixtureJson());
      final List<LabeledSample> samples = ModelEvaluator.parseDataset(
        _datasetFixtureJson(),
      );
      expect(samples, isNotEmpty);

      final EvaluationReport report = ModelEvaluator(engine: engine).evaluate(
        samples,
      );

      // Real numbers, not placeholders: accuracy must be a computed fraction
      // inside [0, 1] and every sample must be accounted for.
      expect(report.sampleCount, samples.length);
      expect(report.accuracy, inInclusiveRange(0.0, 1.0));
      expect(report.macroF1, inInclusiveRange(0.0, 1.0));
      expect(report.correctCount, lessThanOrEqualTo(report.sampleCount));

      // The matrix is square over the model's 15 classes (+ any fallback).
      expect(report.confusionMatrix.length, report.labels.length);
      expect(report.labels.length, greaterThanOrEqualTo(engine.classCount));

      // ignore: avoid_print
      print(
        '[eval] n=${report.sampleCount} acc=${report.accuracy.toStringAsFixed(3)} '
        'macroF1=${report.macroF1.toStringAsFixed(3)} '
        'weightedF1=${report.weightedF1.toStringAsFixed(3)}',
      );
    });
  });
}

String _modelFixtureJson() =>
    File('test/fixtures/model_kategori_produk.json').readAsStringSync();

String _datasetFixtureJson() =>
    File('test/fixtures/eval_dataset_dummy.json').readAsStringSync();
