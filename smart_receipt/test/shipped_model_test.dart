import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/ocr/tfidf_classifier.dart';
import 'package:smart_receipt/services/model_evaluator.dart';
import 'package:smart_receipt/services/text_normalizer.dart';

/// Guards the model asset that actually ships in the app.
///
/// The classifier can be silently replaced by a worse export — a model trained
/// against a different preprocessing pipeline, for example — without any code
/// change and without breaking a single unit test. This test pins the shipped
/// asset to a measured accuracy floor on the bundled evaluation set so such a
/// swap fails loudly instead of degrading the app.
///
/// Measured on `assets/model_kategori_produk.json` (train+val, no test
/// leakage) over 300 balanced samples from the held-out test split:
/// accuracy 0.770, macro-F1 0.713, review coverage 69.3%, accuracy of
/// auto-accepted items 0.913.
///
/// The floors sit well below those numbers so ordinary retraining has room,
/// but a mismatched export (which scores far lower) cannot pass.
void main() {
  late String modelJson;
  late String datasetJson;
  late Map<String, dynamic> model;
  late TfidfNaiveBayesEngine engine;
  late IndonesianTextPreprocessor preprocessor;

  setUpAll(() {
    modelJson = File('assets/model_kategori_produk.json').readAsStringSync();
    datasetJson = File('assets/eval_dataset_dummy.json').readAsStringSync();
    model = modelJson.isEmpty ? <String, dynamic>{} : _decode(modelJson);
    engine = TfidfNaiveBayesEngine()..loadFromJsonString(modelJson);
    preprocessor = IndonesianTextPreprocessor()
      ..loadFromMap(
        _decode(File('assets/text_normalization_id.json').readAsStringSync()),
      );
  });

  /// The model was trained on preprocessed text, so evaluation must run the
  /// same pipeline the app runs — exactly what [MLClassifierService] does.
  ModelEvaluator buildEvaluator() => ModelEvaluator(
    engine: engine,
    preprocess: engine.usesApplicationPreprocessing
        ? preprocessor.normalize
        : null,
  );

  test('shipped model declares its preprocessing contract', () {
    expect(engine.classCount, 15);

    // The JSON must state whether the model expects raw OCR text or text run
    // through IndonesianTextPreprocessor. Either value is valid, but it has to
    // be deliberate: `MLClassifierService` reads this flag to decide.
    expect(model.containsKey('preprocessing'), isTrue);
    expect(
      engine.usesApplicationPreprocessing,
      model['preprocessing'] == 'flutter_id_v1',
    );
  });

  test('shipped model carries a calibrated review margin', () {
    // `review_margin` is what the UI uses to decide "Perlu Review". An export
    // that forgets it silently falls back to the hard-coded default, so the
    // calibrated value would be lost without any error.
    expect(model['review_margin'], isA<num>());
    expect(model['review_margin'] as num, greaterThan(0));
    expect(engine.reviewMargin, (model['review_margin'] as num).toDouble());
  });

  test('shipped model keeps its measured accuracy on the bundled eval set', () {
    final List<LabeledSample> samples = ModelEvaluator.parseDataset(
      datasetJson,
    );
    expect(samples.length, greaterThanOrEqualTo(200));

    final EvaluationReport report = buildEvaluator().evaluate(samples);

    // ignore: avoid_print
    print(
      '[shipped model] n=${report.sampleCount} '
      'acc=${report.accuracy.toStringAsFixed(3)} '
      'macroF1=${report.macroF1.toStringAsFixed(3)} '
      'reviewCoverage=${report.reviewCoverage.toStringAsFixed(3)}',
    );

    expect(report.accuracy, greaterThanOrEqualTo(0.72));
    expect(report.macroF1, greaterThanOrEqualTo(0.63));
    // The review gate must leave most items auto-accepted, otherwise every
    // scan becomes manual work.
    expect(report.reviewCoverage, greaterThanOrEqualTo(0.50));
  });

  test('model maps every class it can predict onto an app category', () {
    for (final String label in engine.classes) {
      expect(
        TfidfNaiveBayesEngine.classToCategoryId.containsKey(label),
        isTrue,
        reason: 'class "$label" has no mapping to an app category id',
      );
    }
  });
}

Map<String, dynamic> _decode(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;
