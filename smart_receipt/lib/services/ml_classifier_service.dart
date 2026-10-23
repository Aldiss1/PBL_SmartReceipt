import 'package:flutter/foundation.dart';

import '../models/categories.dart';
import '../ocr/tfidf_classifier.dart';
import 'text_normalizer.dart';

/// Application-level wrapper around the on-device TF-IDF + Naive Bayes model.
///
/// The heavy lifting (vectorization + scoring) lives in
/// [TfidfNaiveBayesEngine]; this service owns the model lifecycle (load once,
/// reuse across screens) and exposes a category-id-oriented API plus a
/// preprocessed-text variant for the classification UI.
///
/// Asset: `assets/model_kategori_produk.json` — the model trained on
/// `ML/Dataset_SmartReceipt_Sintetis.csv` (6.026 rows, 15 categories). Its
/// export carries no `preprocessing` marker, so it expects raw OCR text; see
/// [TfidfNaiveBayesEngine.usesApplicationPreprocessing].
class MLClassifierService {
  MLClassifierService({TfidfNaiveBayesEngine? engine})
    : _engine = engine ?? TfidfNaiveBayesEngine();

  final TfidfNaiveBayesEngine _engine;

  bool get isReady => _engine.isLoaded;
  int get classCount => _engine.classCount;

  IndonesianTextPreprocessor _preprocessing = IndonesianTextPreprocessor();

  /// Loads the model exactly once. Subsequent calls resolve immediately.
  ///
  /// Also loads the Indonesian preprocessing rule table so the full
  /// clean → tokenize → normalize → classify pipeline is available afterwards.
  ///
  /// Never throws: a load failure is logged, leaves [isReady] false, and lets
  /// the UI degrade gracefully instead of crashing mid-scan.
  Future<bool> loadModel() async {
    try {
      await _preprocessing.loadFromAsset();
      await _engine.load();
      return true;
    } on TfidfModelException catch (e) {
      debugPrint('❌ TF-IDF model tidak dapat dimuat: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ TF-IDF model error tak terduga: $e');
      return false;
    }
  }

  /// Replaces the default Indonesian preprocessor.
  void attachPreprocessor(IndonesianTextPreprocessor preprocessor) {
    _preprocessing = preprocessor;
  }

  /// Exposes the active preprocessor for callers that want the intermediate
  /// stages (e.g. showing the tokenized form in a debug/analysis view).
  IndonesianTextPreprocessor get preprocessor => _preprocessing;

  /// Full prediction for [rawText] (typically an OCR line or item name).
  ///
  /// When the loaded model was trained on preprocessed text (its JSON carries
  /// `"preprocessing": "flutter_id_v1"`), the same [IndonesianTextPreprocessor]
  /// pipeline is applied here first. Skipping this would feed the model text it
  /// was never trained on and quietly cost several points of accuracy.
  TfidfPrediction predict(String rawText) {
    if (!isReady) {
      return const TfidfPrediction(
        label: 'Perlu Review',
        categoryId: kFallbackCategoryId,
        confidence: 0,
        posterior: 0,
        needsReview: true,
      );
    }
    final String input =
        _engine.usesApplicationPreprocessing ? _preprocessing.normalize(rawText) : rawText;
    return _engine.predict(input);
  }

  /// Convenience API returning just the app category id (1..9).
  ///
  /// Prefer [predict] when the confidence or label is needed, e.g. to show the
  /// user why an item was categorised a certain way.
  int predictCategoryId(String rawText) => predict(rawText).categoryId;

  void dispose() {}
}
