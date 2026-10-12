import 'package:flutter/foundation.dart';

import '../ocr/tfidf_classifier.dart';
import 'text_normalizer.dart';

/// Application-level wrapper around the on-device TF-IDF + Naive Bayes model.
///
/// The heavy lifting (vectorization + scoring) lives in
/// [TfidfNaiveBayesEngine]; this service owns the model lifecycle (load once,
/// reuse across screens) and exposes a category-id-oriented API plus a
/// preprocessed-text variant for the classification UI.
///
/// Asset: `assets/model_kategori_produk.json` — the *dummy* dataset model used
/// while a real receipt dataset is not yet available.
class MLClassifierService {
  MLClassifierService({TfidfNaiveBayesEngine? engine})
      : _engine = engine ?? TfidfNaiveBayesEngine();

  final TfidfNaiveBayesEngine _engine;

  bool get isReady => _engine.isLoaded;
  int get classCount => _engine.classCount;

  IndonesianTextPreprocessor _preprocessing = IndonesianTextPreprocessor();

  /// Loads the model exactly once. Subsequent calls resolve immediately.
  ///
  /// Never throws: a load failure is logged, leaves [isReady] false, and lets
  /// the UI degrade gracefully instead of crashing mid-scan.
  Future<bool> loadModel() async {
    try {
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

  /// Full prediction for [rawText] (typically an OCR line or item name).
  TfidfPrediction predict(String rawText) {
    if (!isReady) {
      return const TfidfPrediction(
        label: 'Perlu Review',
        categoryId: 8,
        confidence: 0,
        needsReview: true,
      );
    }
    return _engine.predict(rawText);
  }

  /// Runs the Indonesian NLP preprocessing pipeline first, then classifies.
  ///
  /// Falls back to the raw text when cleaning removes everything.
  TfidfPrediction predictProcessed(String rawText) {
    if (!isReady) {
      return predict(rawText);
    }
    final ProcessedText processed = _preprocessing.process(rawText);
    if (processed.isEmpty) {
      return const TfidfPrediction(
        label: 'Perlu Review',
        categoryId: 8,
        confidence: 0,
        needsReview: true,
      );
    }
    return _engine.predict(processed.normalized);
  }

  /// Convenience API returning just the app category id (1..8).
  ///
  /// Prefer [predict] / [predictProcessed] when the confidence or label is
  /// needed, e.g. to show the user why an item was categorised a certain way.
  int predictCategoryId(String rawText) => predictProcessed(rawText).categoryId;

  /// Kept for backwards compatibility with the earlier async call site.
  @Deprecated('Use predictCategoryId() instead')
  Future<int> predictCategory(String ocrText) async =>
      predictCategoryId(ocrText);

  void dispose() {}
}
