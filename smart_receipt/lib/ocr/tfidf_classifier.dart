import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../models/categories.dart';

/// Result of classifying one item name with the TF-IDF + Naive Bayes model.
class TfidfPrediction {
  const TfidfPrediction({
    required this.label,
    required this.categoryId,
    required this.confidence,
    required this.posterior,
    required this.needsReview,
    this.margin = 0,
    this.alternatives = const <String, double>{},
  });

  /// Raw model class label, e.g. "Makanan", "Tagihan & Utilitas".
  final String label;

  /// Mapped app category id (1..9), aligned with `kAppCategories` /
  /// the `categories` table in SQLite.
  final int categoryId;

  /// Conservative confidence in [label], in 0..1.
  ///
  /// Derived from [margin] as `1 / (1 + (K-1)·e^-margin)`, i.e. the probability
  /// of the winner if every other class were as likely as the runner-up. This
  /// is a *lower bound* on the model's true posterior and, unlike the raw
  /// softmax posterior, it does not saturate at 1.000 — so the number shown in
  /// the UI always agrees with [needsReview].
  final double confidence;

  /// Raw softmax posterior of [label]; kept for auditability.
  ///
  /// Saturates near 1.0 on this model (median 1.000), which is why it is not
  /// used for the review decision.
  final double posterior;

  /// Gap between the top-1 and top-2 log-joint scores (`s1 - s2`)
  ///
  /// Because the TF-IDF vector is L2-normalized this gap is roughly scale-free
  /// and comparable across item names. A small gap means the runner-up class is
  /// nearly as plausible as the winner, which is the actual signal that the
  /// prediction should be confirmed by the user.
  final double margin;

  /// True when [margin] is below the model's review margin, meaning the top two
  /// classes are too close to trust without confirmation.
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
  String _fallbackLabel = 'Perlu Review';

  /// Default log-odds gap below which a prediction is surfaced for review.
  ///
  /// Tuned on the exported model: on the dummy eval set a margin of 4.0 flags
  /// ~12% of items, and those items carry a ~22% error rate versus ~1.6% for
  /// the ones left alone. The model's own posterior cannot be used for this
  /// (it saturates at 1.0 — median 1.000), so the gap between the best and
  /// second-best class is the decision signal.
  static const double defaultReviewMargin = 4.0;

  double _reviewMargin = defaultReviewMargin;

  /// The active review margin; predictions with a smaller [TfidfPrediction.margin]
  /// are flagged with [TfidfPrediction.needsReview].
  double get reviewMargin => _reviewMargin;

  /// Raw class label → canonical app category id ([kAppCategories]).
  ///
  /// The model knows 15 labels while the app has 9 categories, so several model
  /// labels intentionally collapse onto one category. Keeping this table in one
  /// place means the classifier output, the review screen and the database all
  /// agree on what an id means.
  static const Map<String, int> classToCategoryId = <String, int>{
    'Makanan': 1, // Makanan
    'Minuman': 2, // Minuman
    'Rumah Tangga': 3, // Rumah Tangga
    'Perawatan Diri': 4, // Perawatan Diri
    'Kesehatan': 5, // Kesehatan
    'Transportasi': 6, // Transportasi
    'Elektronik': 7, // Elektronik
    'Pakaian & Fashion': 8, // Pakaian
    'Lainnya': kFallbackCategoryId, // Lainnya
    // Model classes with no dedicated app category.
    'Bayi & Anak': kFallbackCategoryId,
    'Hewan Peliharaan': kFallbackCategoryId,
    'Hiburan & Hobi': kFallbackCategoryId,
    'Pendidikan & ATK': kFallbackCategoryId,
    'Rokok & Tembakau': kFallbackCategoryId,
    'Tagihan & Utilitas': kFallbackCategoryId,
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

    // Review policy. `threshold` (a posterior cutoff) is ignored on purpose:
    // this model's posteriors saturate, so the cutoff never fired.
    final Object? reviewMargin = json['review_margin'];
    if (reviewMargin is num && reviewMargin > 0) {
      _reviewMargin = reviewMargin.toDouble();
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
  /// text has no in-vocabulary features or the gap between the best and
  /// second-best class is below [reviewMargin].
  TfidfPrediction predict(String text) {
    if (!isLoaded) {
      throw TfidfModelException('Model belum dimuat.');
    }
    final Map<int, double> vector = vectorize(text);
    if (vector.isEmpty) {
      return TfidfPrediction(
        label: _fallbackLabel,
        categoryId: kFallbackCategoryId,
        confidence: 0.0,
        posterior: 0.0,
        needsReview: true,
        margin: 0,
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

    final double posterior = posteriors[bestIndex];
    final Map<String, double> alternatives = <String, double>{
      for (final int i in order.skip(1).take(2)) _classes[i]: posteriors[i],
    };

    // Log-odds gap between the winner and the runner-up. Scale-free because the
    // TF-IDF vector is L2-normalized, so it is comparable across item names.
    final double margin = scores.length > 1
        ? scores[order[0]] - scores[order[1]]
        : double.infinity;

    final bool needsReview = margin < _reviewMargin;
    return TfidfPrediction(
      label: needsReview ? _fallbackLabel : _classes[bestIndex],
      // Even when flagged for review, the category shown to the user must be
      // the model's own top pick — not a runner-up alternative.
      categoryId: classToCategoryId[_classes[bestIndex]] ?? kFallbackCategoryId,
      confidence: _conservativeConfidence(margin),
      posterior: posterior,
      needsReview: needsReview,
      margin: margin,
      alternatives: alternatives,
    );
  }

  /// Lower-bound confidence implied by [margin], assuming every non-winning
  /// class is at least as likely as the runner-up.
  double _conservativeConfidence(double margin) {
    if (!margin.isFinite) {
      return 1.0;
    }
    final int others = _classes.length > 1 ? _classes.length - 1 : 1;
    final double odds = others * math.exp(-margin);
    if (!odds.isFinite) {
      return 1.0;
    }
    return 1.0 / (1.0 + odds);
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
