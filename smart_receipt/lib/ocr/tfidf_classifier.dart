import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Result of classifying one item name with the TF-IDF + Naive Bayes model.
class TfidfPrediction {
  const TfidfPrediction({
    required this.label,
    required this.categoryId,
    required this.confidence,
    required this.needsReview,
    this.alternatives = const <String, double>{},
  });

  /// Raw model class label, e.g. "Makanan", "Tagihan & Utilitas".
  final String label;

  /// Mapped app category id (1..8), aligned with `kCategories` /
  /// the `categories` table in SQLite.
  final int categoryId;

  /// Posterior probability of [label] under the Naive Bayes model (0..1).
  final double confidence;

  /// True when [confidence] is below the model's review threshold, meaning the
  /// prediction should be surfaced to the user for confirmation.
  final bool needsReview;

  /// Top alternative class labels with their posteriors, for transparency.
  final Map<String, double> alternatives;
}

/// Raised when the model asset cannot be loaded or is malformed.
class TfidfModelException implements Exception {
  TfidfModelException(this.message);

  final String message;

  @override
  String toString() => 'TfidfModelException: $message';
}

/// On-device TF-IDF + Multinomial Naive Bayes text classifier.
///
/// The model was trained offline (scikit-learn style `TfidfVectorizer` +
/// `MultinomialNB`) and exported to JSON. This class only *executes* the
/// exported model, exactly mirroring the training-time transform so scores are
/// reproducible:
///
///   1. char n-gram extraction (word-boundary aware, like sklearn `char_wb`)
///   2. sublinear TF    → `1 + ln(tf)`
///   3. IDF weighting   → `tf * idf`
///   4. L2 normalization
///   5. Multinomial NB  → `class_log_prior + Σ tfidf_i * feature_log_prob_i`
///   6. softmax over class scores for a calibrated posterior
///
/// Everything runs locally; no network and no demo values are involved.
class TfidfNaiveBayesEngine {
  TfidfNaiveBayesEngine();

  bool get isLoaded => _vocabulary != null;

  List<String> _classes = <String>[];
  Map<String, int>? _vocabulary;
  List<double>? _idf;
  List<double>? _classLogPrior;
  List<List<double>>? _featureLogProb;

  /// Number of model classes (15 in the shipped dummy dataset).
  int get classCount => _classes.length;

  /// Model classes in their trained order; used by confusion-matrix reports.
  List<String> get classes => List<String>.unmodifiable(_classes);

  int _minN = 2;
  int _maxN = 4;
  double _reviewThreshold = 0.9;
  String _fallbackLabel = 'Perlu Review';

  /// Raw class label → app category id. Kept in sync with [kCategories]
  /// (see `models.dart`) and the seeded `categories` table.
  static const Map<String, int> classToCategoryId = <String, int>{
    'Makanan': 1, // Makanan & Minuman
    'Minuman': 1, // Makanan & Minuman
    'Transportasi': 2, // Transport
    'Bayi & Anak': 3, // Belanja Bulanan
    'Elektronik': 3, // Belanja Bulanan
    'Hewan Peliharaan': 3, // Belanja Bulanan
    'Pakaian & Fashion': 3, // Belanja Bulanan
    'Perawatan Diri': 3, // Belanja Bulanan
    'Rumah Tangga': 3, // Belanja Bulanan
    'Tagihan & Utilitas': 4, // Utilitas
    'Hiburan & Hobi': 5, // Hiburan
    'Kesehatan': 6, // Kesehatan
    'Pendidikan & ATK': 7, // Pendidikan
    'Rokok & Tembakau': 8, // Lainnya
    'Lainnya': 8, // Lainnya
  };

  /// Loads and validates the exported model from `assets/`.
  ///
  /// Safe to call more than once; subsequent calls are no-ops.
  Future<void> load({String assetPath = 'assets/model_kategori_produk.json'}) async {
    if (isLoaded) {
      return;
    }
    final String raw;
    try {
      raw = await rootBundle.loadString(assetPath);
    } catch (e) {
      throw TfidfModelException('Gagal membaca model "$assetPath": $e');
    }
    loadFromJsonString(raw);
  }

  /// Synchronous loader used by tests and by [load].
  void loadFromJsonString(String rawJson) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (e) {
      throw TfidfModelException('Model bukan JSON yang valid: $e');
    }
    loadFromMap(json);
  }

  /// Builds the model from an already-decoded map.
  void loadFromMap(Map<String, dynamic> json) {
    final Object? classes = json['classes'];
    final Object? vocab = json['vocabulary'];
    final Object? idf = json['idf'];
    final Object? prior = json['class_log_prior'];
    final Object? flp = json['feature_log_prob'];

    if (classes is! List || vocab is! Map || idf is! List) {
      throw TfidfModelException(
        'Model tidak lengkap: butuh classes, vocabulary, dan idf.',
      );
    }

    _classes = classes.map((Object? e) => e.toString()).toList();
    _vocabulary = <String, int>{
      for (final MapEntry<Object?, Object?> e in vocab.entries)
        e.key.toString(): (e.value as num).toInt(),
    };
    _idf = idf.map((Object? e) => (e as num).toDouble()).toList();

    final Object? range = json['ngram_range'];
    if (range is List && range.length == 2) {
      _minN = (range[0] as num).toInt();
      _maxN = (range[1] as num).toInt();
    }

    if (prior is List && prior.isNotEmpty) {
      _classLogPrior = prior.map((Object? e) => (e as num).toDouble()).toList();
    }
    if (flp is List && flp.isNotEmpty) {
      _featureLogProb = flp
          .map(
            (Object? row) => (row as List)
                .map((Object? e) => (e as num).toDouble())
                .toList(),
          )
          .toList();
    }

    final Object? threshold = json['threshold'];
    if (threshold is num) {
      _reviewThreshold = threshold.toDouble();
    }
    final Object? fallback = json['fallback_label'];
    if (fallback is String && fallback.isNotEmpty) {
      _fallbackLabel = fallback;
    }

    _validate();
  }

  void _validate() {
    if (_featureLogProb == null || _classLogPrior == null) {
      throw TfidfModelException(
        'Model tidak lengkap: butuh class_log_prior dan feature_log_prob '
        'untuk Multinomial Naive Bayes.',
      );
    }
    final int nFeatures = _vocabulary!.length;
    if (_idf!.length != nFeatures) {
      throw TfidfModelException(
        'Jumlah idf (${_idf!.length}) tidak sama dengan vocabulary '
        '($nFeatures).',
      );
    }
    for (final int index in _vocabulary!.values) {
      if (index < 0 || index >= nFeatures) {
        throw TfidfModelException(
          'Indeks vocabulary $index di luar rentang 0..${nFeatures - 1}.',
        );
      }
    }
    if (_classLogPrior!.length != _classes.length) {
      throw TfidfModelException(
        'class_log_prior (${_classLogPrior!.length}) tidak cocok dengan '
        'jumlah kelas (${_classes.length}).',
      );
    }
    if (_featureLogProb!.length != _classes.length) {
      throw TfidfModelException(
        'feature_log_prob punya ${_featureLogProb!.length} baris, '
        'seharusnya ${_classes.length}.',
      );
    }
    for (final List<double> row in _featureLogProb!) {
      if (row.length != nFeatures) {
        throw TfidfModelException(
          'Setiap baris feature_log_prob harus punya $nFeatures nilai, '
          'ditemukan ${row.length}.',
        );
      }
    }
  }

  /// Extracts the char n-grams that make up the vocabulary.
  ///
  /// Mirrors sklearn's `char_wb` analyzer: a word is padded with one space on
  /// each side and n-grams are taken only within word boundaries. This matters
  /// because the exported vocabulary was built the same way.
  List<String> charNgrams(String text) {
    if (_minN <= 0) {
      return const <String>[];
    }
    final List<String> grams = <String>[];
    final String normalized = text.toLowerCase();
    for (final String word in normalized.split(RegExp(r'\s+'))) {
      if (word.isEmpty) {
        continue;
      }
      final String padded = ' $word ';
      for (int n = _minN; n <= _maxN; n++) {
        if (padded.length < n) {
          continue;
        }
        for (int i = 0; i + n <= padded.length; i++) {
          grams.add(padded.substring(i, i + n));
        }
      }
    }
    return grams;
  }

  /// Builds the L2-normalized TF-IDF vector for [text].
  ///
  /// Sparse by construction: only vocabulary terms actually present are kept.
  Map<int, double> vectorize(String text) {
    if (!isLoaded) {
      throw TfidfModelException('Model belum dimuat.');
    }
    final List<String> grams = charNgrams(text);
    if (grams.isEmpty) {
      return <int, double>{};
    }

    // Term frequency.
    final Map<String, int> counts = <String, int>{};
    for (final String gram in grams) {
      counts[gram] = (counts[gram] ?? 0) + 1;
    }

    // Sublinear TF * IDF, accumulated per vocabulary index.
    final Map<int, double> weighted = <int, double>{};
    counts.forEach((String term, int count) {
      final int? index = _vocabulary![term];
      if (index == null) {
        return; // out-of-vocabulary term
      }
      final double sublinearTf = 1 + math.log(count.toDouble());
      weighted[index] = (weighted[index] ?? 0) + sublinearTf * _idf![index];
    });

    // L2 normalization.
    double sumSquares = 0;
    for (final double value in weighted.values) {
      sumSquares += value * value;
    }
    if (sumSquares <= 0) {
      return <int, double>{};
    }
    final double norm = math.sqrt(sumSquares);
    return weighted.map<int, double>(
      (int index, double value) => MapEntry<int, double>(index, value / norm),
    );
  }

  /// Raw Naive Bayes decision-function scores (log-joint) per class.
  ///
  /// Uses the standard multinomial NB formula recovered from the export:
  /// `log_prior_c + Σ x_i * log_prob_ci`.
  List<double> decisionScores(Map<int, double> vector) {
    return <double>[
      for (int c = 0; c < _classes.length; c++)
        _classLogPrior![c] +
            vector.entries.fold<double>(
              0,
              (double sum, MapEntry<int, double> e) =>
                  sum + e.value * _featureLogProb![c][e.key],
            ),
    ];
  }

  /// Classifies [text] into a model label plus mapped app category id.
  ///
  /// Returns the fallback label with [TfidfPrediction.needsReview] set when the
  /// text has no in-vocabulary features or the posterior is below the model's
  /// review threshold.
  TfidfPrediction predict(String text) {
    if (!isLoaded) {
      throw TfidfModelException('Model belum dimuat.');
    }
    final Map<int, double> vector = vectorize(text);
    if (vector.isEmpty) {
      return TfidfPrediction(
        label: _fallbackLabel,
        categoryId: classToCategoryId[_fallbackLabel] ?? 8,
        confidence: 0.0,
        needsReview: true,
      );
    }

    final List<double> scores = decisionScores(vector);
    final List<double> posteriors = _softmax(scores);

    int bestIndex = 0;
    for (int i = 1; i < posteriors.length; i++) {
      if (posteriors[i] > posteriors[bestIndex]) {
        bestIndex = i;
      }
    }

    // Rank labels by posterior so the top alternatives can be shown.
    final List<int> order = List<int>.generate(_classes.length, (int i) => i)
      ..sort((int a, int b) => posteriors[b].compareTo(posteriors[a]));

    final double confidence = posteriors[bestIndex];
    final Map<String, double> alternatives = <String, double>{
      for (final int i in order.skip(1).take(2)) _classes[i]: posteriors[i],
    };

    final bool needsReview = confidence < _reviewThreshold;
    return TfidfPrediction(
      label: needsReview ? _fallbackLabel : _classes[bestIndex],
      categoryId: needsReview
          ? _reviewCategoryId(alternatives)
          : (classToCategoryId[_classes[bestIndex]] ?? 8),
      confidence: confidence,
      needsReview: needsReview,
      alternatives: alternatives,
    );
  }

  /// When a prediction is uncertain we still need *some* category id for the
  /// review screen, so we fall back to the best alternative's mapping.
  int _reviewCategoryId(Map<String, double> alternatives) {
    if (alternatives.isEmpty) {
      return 8;
    }
    final String top = alternatives.keys.first;
    return classToCategoryId[top] ?? 8;
  }

  List<double> _softmax(List<double> scores) {
    if (scores.isEmpty) {
      return const <double>[];
    }
    final double maxScore =
        scores.reduce((double a, double b) => a > b ? a : b);
    double denom = 0;
    final List<double> exps = <double>[];
    for (final double s in scores) {
      final double e = math.exp(s - maxScore);
      exps.add(e);
      denom += e;
    }
    if (denom <= 0) {
      return List<double>.filled(scores.length, 0);
    }
    return exps.map((double e) => e / denom).toList();
  }
}
