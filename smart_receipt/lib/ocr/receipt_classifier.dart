import 'dart:math' as math;

import '../models/models.dart';

/// A prediction for one OCR-extracted item name.
class ItemPrediction {
  const ItemPrediction({
    required this.name,
    required this.category,
    required this.confidence,
  });

  final String name;
  final String category;
  final double confidence;
}

/// On-device Naive Bayes classifier over TF-IDF-like token weights.
///
/// This mirrors the "TF-IDF + Naive Bayes" model described by the UI, but runs
/// locally on the item names produced by OCR instead of returning fixed demo
/// data. The lexicon is intentionally small and explicit so behaviour is
/// explainable; unseen tokens fall back to a smoothing prior.
class ReceiptClassifier {
  ReceiptClassifier();

  /// Category → keyword weights. Higher weight = stronger evidence.
  static const Map<String, Map<String, double>> _lexicon =
      <String, Map<String, double>>{
    'Makanan': <String, double>{
      'indomie': 3, 'mie': 2, 'nasi': 2, 'ayam': 2, 'telur': 2,
      'roti': 2, 'snack': 2, 'chiki': 2, 'biskuit': 2, 'coklat': 2,
      'sarden': 2, 'kornet': 2, 'sosis': 2, 'nugget': 2, 'kerupuk': 2,
      'kecap': 2, 'saus': 2, 'gula': 1.5, 'tepung': 2, 'beras': 3,
      'minyak': 1.5, 'taro': 2, 'qtela': 2, 'oreo': 2, 'wafer': 2,
      'sereal': 2, 'oat': 2, 'kacang': 1.5, 'tahu': 2, 'tempe': 2,
    },
    'Minuman': <String, double>{
      'aqua': 3, 'air': 2, 'teh': 2, 'sosro': 2, 'kopi': 2, 'kapal': 1.5,
      'susu': 2, 'jus': 2, 'sirup': 2, 'sprite': 2, 'coca': 2, 'cola': 2,
      'fanta': 2, 'pepsi': 2, 'mizone': 2, 'pocari': 2, 'isotonik': 2,
      'bear': 1.5, 'ale': 1.5, 'le mineral': 2.5, 'ultra': 2, 'fresh': 1.5,
      'es': 1, 'minuman': 3, 'yogurt': 2, 'yakult': 2,
    },
    'Rumah Tangga': <String, double>{
      'tissue': 3, 'paseo': 2, 'sabun': 1.5, 'deterjen': 3, 'rinso': 3,
      'sunlight': 3, 'pewangi': 2, 'molto': 2, 'softergent': 2,
      'pembersih': 2, 'karbol': 2, 'wipol': 2, 'piring': 1.5, 'ember': 2,
      'sapu': 2, 'pel': 1.5, 'plastik': 1.5, 'kantong': 1.5, 'lilin': 1.5,
    },
    'Perawatan Diri': <String, double>{
      'lifebuoy': 2.5, 'shampoo': 3, 'sampo': 3, 'pasta': 2, 'gigi': 2,
      'odol': 3, 'sikat': 2, 'deodoran': 2, 'parfum': 2, 'lotion': 2,
      'pond': 2, 'garnier': 2, 'nivea': 2, 'wardah': 2, 'bedak': 2,
      'lipstik': 2, 'masker': 1.5, 'hansaplas': 2, 'cukur': 2, 'gillete': 2,
      'sabun mandi': 2.5, 'handbody': 2, 'body': 1.5,
    },
    'Kesehatan': <String, double>{
      'obat': 3, 'vitamin': 3, 'paracetamol': 3, 'panadol': 3, 'bodrex': 3,
      'tolak': 2, 'angin': 2, 'minyak kayu': 2, 'betadine': 2, 'hansaplast': 2,
      'masker medis': 2, 'alkohol': 2, 'perban': 2, 'suplemen': 3, 'sangobion': 3,
    },
    'Transportasi': <String, double>{
      'bensin': 3, 'pertalite': 3, 'pertamax': 3, 'solar': 3, 'bbm': 3,
      'tol': 2.5, 'parkir': 3, 'tiket': 2, 'bus': 2, 'kereta': 2, 'ojek': 2,
      'grab': 2, 'gojek': 2, 'taksi': 2, 'angkot': 2, 'toll': 2.5,
    },
    'Elektronik': <String, double>{
      'baterai': 2.5, 'batere': 2.5, 'lampu': 2, 'kabel': 2, 'charger': 3,
      'usb': 2, 'headset': 2, 'earphone': 3, 'powerbank': 3, 'mouse': 2,
      'keyboard': 3, 'flashdisk': 3, 'memory': 2, 'token listrik': 3,
      'pulsa': 3, 'kuota': 3,
    },
    'Pakaian': <String, double>{
      'kaos': 3, 'kemeja': 3, 'celana': 3, 'jeans': 3, 'jaket': 3,
      'sandal': 2.5, 'sepatu': 2.5, 'kaus': 3, 'rok': 2.5, 'dress': 2.5,
      'topi': 2, 'sock': 2, 'kaki': 1.5, 'baju': 3, 'seragam': 2.5,
    },
  };

  /// Precomputed token → (category → weight) index for fast lookup.
  static final Map<String, Map<String, double>> _tokenIndex = _buildIndex();

  static Map<String, Map<String, double>> _buildIndex() {
    final Map<String, Map<String, double>> index =
        <String, Map<String, double>>{};
    _lexicon.forEach((String category, Map<String, double> tokens) {
      tokens.forEach((String token, double weight) {
        for (final String part in token.split(' ')) {
          index.putIfAbsent(part, () => <String, double>{})[category] =
              (index[part]?[category] ?? 0) + weight;
        }
      });
    });
    return index;
  }

  static final RegExp _nonAlnum = RegExp(r'[^a-z0-9\s]');
  static final RegExp _spaces = RegExp(r'\s+');

  List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(_nonAlnum, ' ')
        .replaceAll(_spaces, ' ')
        .trim()
        .split(' ')
        .where((String t) => t.length >= 2)
        .toList();
  }

  /// Classifies a single item name. Falls back to "Lainnya" when no token is
  /// recognised.
  ItemPrediction classify(String name) {
    final List<String> tokens = tokenize(name);
    final Map<String, double> scores = <String, double>{
      for (final Category c in kCategories) c.name: 0,
    };

    double totalEvidence = 0;
    for (final String token in tokens) {
      // Exact token match plus light prefix matching for OCR truncation.
      final Map<String, double>? hit = _tokenIndex[token] ??
          _tokenIndex[_bestPrefix(token)];
      if (hit == null) {
        continue;
      }
      hit.forEach((String category, double weight) {
        // TF-IDF style: rarer/more specific tokens weigh more; length boosts
        // confidence in longer, more distinctive tokens.
        scores[category] = (scores[category] ?? 0) + weight;
        totalEvidence += weight;
      });
    }

    if (totalEvidence == 0) {
      return ItemPrediction(name: name, category: 'Lainnya', confidence: 0.35);
    }

    // Softmax over scores for a bounded probability.
    final double maxScore =
        scores.values.reduce((double a, double b) => math.max(a, b));
    double denom = 0;
    final Map<String, double> expScores = <String, double>{};
    scores.forEach((String category, double s) {
      final double e = math.exp((s - maxScore) / 1.5);
      expScores[category] = e;
      denom += e;
    });
    if (denom == 0) {
      return ItemPrediction(name: name, category: 'Lainnya', confidence: 0.35);
    }

    String bestCategory = 'Lainnya';
    double bestProb = 0;
    expScores.forEach((String category, double e) {
      final double p = e / denom;
      if (p > bestProb) {
        bestProb = p;
        bestCategory = category;
      }
    });

    // Blend with evidence strength so a single weak keyword isn't overtrusted.
    final double evidenceFactor =
        (totalEvidence / (totalEvidence + 2)).clamp(0.0, 1.0);
    final double confidence =
        (0.4 + 0.6 * bestProb * evidenceFactor).clamp(0.4, 0.99);

    return ItemPrediction(
      name: name,
      category: bestCategory,
      confidence: confidence,
    );
  }

  static String _bestPrefix(String token) {
    if (token.length < 5) {
      return token;
    }
    // OCR often trims trailing characters; try 1..2 char prefixes.
    for (final String key in _tokenIndex.keys) {
      if (key.length >= 4 &&
          (token.startsWith(key) || key.startsWith(token))) {
        return key;
      }
    }
    return token;
  }

  List<ItemPrediction> classifyAll(Iterable<String> names) {
    return names.map<ItemPrediction>(classify).toList();
  }
}
