import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/ocr/tfidf_classifier.dart';
import 'package:smart_receipt/services/model_evaluator.dart';

/// Guards the model asset that actually ships in the app.
///
/// The classifier can be silently replaced by a worse export — a model trained
/// against a different preprocessing pipeline, for example — without any code
/// change and without breaking a single unit test. This test pins the shipped
/// asset to a measured accuracy floor on the bundled evaluation set so such a
/// swap fails loudly instead of degrading the app.
///
/// Measured on `assets/model_kategori_produk.json`: accuracy 0.861,
/// macro-F1 0.863 over 72 samples. The floor is set well below that so ordinary
/// model retraining has room, but a mismatched export (which scores far lower)
/// cannot pass.
void main() {
  late String modelJson;
  late String datasetJson;

  setUpAll(() {
    modelJson = File('assets/model_kategori_produk.json').readAsStringSync();
    datasetJson = File('assets/eval_dataset_dummy.json').readAsStringSync();
  });

  test('shipped model loads and reports its preprocessing contract', () {
    final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
    engine.loadFromJsonString(modelJson);

    expect(engine.classCount, 15);
    expect(engine.reviewMargin, greaterThan(0));

    // If the model is later retrained on preprocessed text, the service must
    // know: it only applies IndonesianTextPreprocessor when this is true.
    // Either value is valid, but it has to be deliberate.
    expect(engine.usesApplicationPreprocessing, isA<bool>());
  });

  test('shipped model keeps its measured accuracy on the bundled eval set', () {
    final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
    engine.loadFromJsonString(modelJson);

    final List<LabeledSample> samples = ModelEvaluator.parseDataset(
      datasetJson,
    );
    expect(samples.length, greaterThan(50));

    final EvaluationReport report = ModelEvaluator(engine: engine).evaluate(
      samples,
    );

    // ignore: avoid_print
    print(
      '[shipped model] n=${report.sampleCount} '
      'acc=${report.accuracy.toStringAsFixed(3)} '
      'macroF1=${report.macroF1.toStringAsFixed(3)}',
    );

    expect(report.accuracy, greaterThanOrEqualTo(0.75));
    expect(report.macroF1, greaterThanOrEqualTo(0.65));
  });

  test('model maps every class it can predict onto an app category', () {
    final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
    engine.loadFromJsonString(modelJson);

    for (final String label in engine.classes) {
      expect(
        TfidfNaiveBayesEngine.classToCategoryId.containsKey(label),
        isTrue,
        reason: 'class "$label" has no mapping to an app category id',
      );
    }
  });
}
