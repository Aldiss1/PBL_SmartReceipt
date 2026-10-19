import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/models/models.dart';
import 'package:smart_receipt/ocr/tfidf_classifier.dart';
import 'package:smart_receipt/services/ml_classifier_service.dart';
import 'package:smart_receipt/services/model_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canonical taxonomy', () {
    test('ids are unique and contiguous from 1', () {
      final List<int> ids =
          kAppCategories.map((AppCategory c) => c.id).toList();
      expect(ids, List<int>.generate(kAppCategories.length, (int i) => i + 1));
      expect(ids.toSet().length, ids.length);
    });

    test('names are unique', () {
      final List<String> names =
          kAppCategories.map((AppCategory c) => c.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('the fallback category exists and is named Lainnya', () {
      expect(kCategoryNameForId(kFallbackCategoryId), 'Lainnya');
    });

    test('name and id lookups round-trip', () {
      for (final AppCategory category in kAppCategories) {
        expect(kCategoryIdForName(category.name), category.id);
        expect(kCategoryNameForId(category.id), category.name);
      }
    });

    test('unknown ids and names fall back to Lainnya', () {
      expect(kCategoryNameForId(0), 'Lainnya');
      expect(kCategoryNameForId(999), 'Lainnya');
      expect(kCategoryIdForName('Tidak Ada'), kFallbackCategoryId);
    });

    test('lookup is case-insensitive and trims whitespace', () {
      expect(kCategoryIdForName('  makanan '), 1);
      expect(kCategoryIdForName('TRANSPORTASI'), 6);
    });

    test('UI category list is derived from the canonical list', () {
      final List<Category> ui = kCategories;
      expect(ui.length, kAppCategories.length);
      for (int i = 0; i < ui.length; i++) {
        expect(ui[i].name, kAppCategories[i].name);
        // Colours come from the palette, one per category.
        expect(ui[i].color, isNotNull);
      }
    });
  });

  group('classifier label mapping', () {
    test('every mapped category id is a canonical id', () {
      final Set<int> validIds =
          kAppCategories.map((AppCategory c) => c.id).toSet();
      for (final MapEntry<String, int> entry
          in TfidfNaiveBayesEngine.classToCategoryId.entries) {
        expect(
          validIds.contains(entry.value),
          isTrue,
          reason: 'Label "${entry.key}" maps to unknown id ${entry.value}',
        );
      }
    });

    test('every model class has a mapping', () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();
      for (final String label in engine.classes) {
        expect(
          TfidfNaiveBayesEngine.classToCategoryId.containsKey(label),
          isTrue,
          reason: 'Model class "$label" has no app category mapping',
        );
      }
    });

    test('model predictions resolve to a real category name', () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();

      // Model labels that used to be mapped to the wrong UI name.
      const Map<String, String> expected = <String, String>{
        'PERTAMAX': 'Transportasi',
        'OBAT PARACETAMOL': 'Kesehatan',
        'PULSA TELKOMSEL 50K': 'Lainnya',
        'AQUA 600ML': 'Minuman',
        'INDOMIE GORENG': 'Makanan',
        'KAOS POLOS HITAM': 'Pakaian',
      };

      expected.forEach((String text, String category) {
        final TfidfPrediction prediction = engine.predict(text);
        expect(
          kCategoryNameForId(prediction.categoryId),
          category,
          reason: '"$text" predicted ${prediction.label} '
              '(id ${prediction.categoryId})',
        );
      });
    });

    test('uncertain predictions keep the model top pick, not a runner-up',
        () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();

      final TfidfPrediction prediction = engine.predict('ABC');
      expect(prediction.needsReview, isTrue);

      // Recompute the model's own best class from the public scoring API.
      final List<double> scores = engine.decisionScores(
        engine.vectorize('ABC'),
      );
      int best = 0;
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > scores[best]) {
          best = i;
        }
      }
      final String topClass = engine.classes[best];

      expect(
        prediction.categoryId,
        TfidfNaiveBayesEngine.classToCategoryId[topClass],
        reason: 'Needs-review prediction should keep the top class '
            '"$topClass" instead of a runner-up alternative',
      );
      expect(
        kAppCategories.any((AppCategory c) => c.id == prediction.categoryId),
        isTrue,
      );
    });
  });

  group('review policy', () {
    test('uses a margin threshold, not a saturated posterior', () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();

      expect(engine.reviewMargin, greaterThan(0));

      // Clear item: the runner-up is far away, so no review.
      final TfidfPrediction clear = engine.predict('INDOMIE GORENG');
      expect(clear.margin, greaterThanOrEqualTo(engine.reviewMargin));
      expect(clear.needsReview, isFalse);
      expect(clear.confidence, greaterThan(0.95));

      // Ambiguous item: the top two classes are nearly tied.
      final TfidfPrediction ambiguous = engine.predict('ABC');
      expect(ambiguous.margin, lessThan(engine.reviewMargin));
      expect(ambiguous.needsReview, isTrue);
      expect(ambiguous.confidence, lessThan(0.5));
    });

    test('confidence is not the saturating softmax posterior', () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();

      final TfidfPrediction ambiguous = engine.predict('ABC');
      // The raw posterior is high even though the runner-up is close; the
      // reported confidence is the conservative margin-derived value.
      expect(ambiguous.posterior, greaterThan(0.5));
      expect(ambiguous.confidence, lessThan(ambiguous.posterior));
    });

    test('needsReview matches the margin rule exactly', () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();

      for (final String text in <String>[
        'ABC',
        'ZXQW',
        'TOTAL',
        'AQUA 600ML',
        'PERTAMAX',
        'INDOMIE GORENG',
        'TISSUE PASEO',
        'KAOS POLOS HITAM',
      ]) {
        final TfidfPrediction p = engine.predict(text);
        expect(
          p.needsReview,
          p.margin < engine.reviewMargin,
          reason: '"$text": margin ${p.margin} vs ${engine.reviewMargin}',
        );
      }
    });

    test('flags a sane share of the eval dataset for review', () async {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      await engine.load();

      final List<LabeledSample> samples = ModelEvaluator.parseDataset(
        File('assets/eval_dataset_dummy.json').readAsStringSync(),
      );
      final int flagged =
          samples.where((LabeledSample s) => engine.predict(s.text).needsReview).length;
      final double rate = flagged / samples.length;

      // The old posterior threshold (0.9) flagged 0% because posteriors
      // saturate. The margin rule must actually do something, without asking
      // the user to confirm everything.
      expect(rate, greaterThan(0.03));
      expect(rate, lessThan(0.30));
    });
  });

  group('MLClassifierService inference contract', () {
    test('classifies raw OCR text, not normalized text', () async {
      final MLClassifierService service = MLClassifierService();
      expect(await service.loadModel(), isTrue);

      // These are exactly the cases the normalizer used to break:
      //   SABUN LIFEBUOY -> "sabun sabun", PERTAMAX -> "bensin".
      const Map<String, String> expected = <String, String>{
        'SABUN LIFEBUOY': 'Perawatan Diri',
        'PERTAMAX': 'Transportasi',
        'TISSUE PASEO': 'Rumah Tangga',
        'AQUA 600ML': 'Minuman',
        'INDOMIE GORENG': 'Makanan',
      };

      expected.forEach((String text, String category) {
        expect(
          kCategoryNameForId(service.predictCategoryId(text)),
          category,
          reason: 'predictCategoryId("$text") must use the raw-text contract',
        );
        expect(
          kCategoryNameForId(service.predict(text).categoryId),
          category,
          reason: 'predict("$text") must use the raw-text contract',
        );
      });
    });
  });
}
