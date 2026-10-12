import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MLClassifierService {
  Map<String, dynamic>? _tfidfModel;
  
  // Mapping dari 15 classes model ke 8 kategori app
  final Map<String, int> classToCategory = {
    "Bayi & Anak": 3,           // Belanja Bulanan
    "Elektronik": 3,            // Belanja Bulanan
    "Hewan Peliharaan": 3,      // Belanja Bulanan
    "Hiburan & Hobi": 5,        // Hiburan
    "Kesehatan": 6,             // Kesehatan
    "Lainnya": 8,               // Lainnya
    "Makanan": 1,               // Makanan & Minuman
    "Minuman": 1,               // Makanan & Minuman
    "Pakaian & Fashion": 3,     // Belanja Bulanan
    "Pendidikan & ATK": 7,      // Pendidikan
    "Perawatan Diri": 3,        // Belanja Bulanan
    "Rokok & Tembakau": 8,      // Lainnya
    "Rumah Tangga": 3,          // Belanja Bulanan
    "Tagihan & Utilitas": 4,    // Utilitas
    "Transportasi": 2,          // Transport
  };

  Future<void> loadModel() async {
    try {
      final String response = await rootBundle.loadString('assets/model_kategori_produk.json');
      _tfidfModel = jsonDecode(response);
      debugPrint('✅ TF-IDF Model loaded successfully');
    } catch (e) {
      debugPrint('❌ Error loading model: $e');
    }
  }

  // Generate char n-grams [2,4]
  List<String> _generateNgrams(String text, int minN, int maxN) {
    final ngrams = <String>[];
    final cleanText = text.toLowerCase();
    
    for (int n = minN; n <= maxN; n++) {
      for (int i = 0; i <= cleanText.length - n; i++) {
        ngrams.add(cleanText.substring(i, i + n));
      }
    }
    
    return ngrams;
  }

  // Hitung TF (term frequency)
  Map<String, double> _computeTF(List<String> ngrams) {
    final tf = <String, double>{};
    final totalTerms = ngrams.length;
    
    if (totalTerms == 0) return tf;
    
    for (var ngram in ngrams) {
      tf[ngram] = (tf[ngram] ?? 0) + 1;
    }
    
    // Sublinear TF: tf(t) = 1 + log(tf(t))
    for (var key in tf.keys) {
      tf[key] = 1.0 + (tf[key]! > 0 ? log(1.0 + tf[key]!) : 0);
    }
    
    // Normalize by total terms
    for (var key in tf.keys) {
      tf[key] = tf[key]! / (totalTerms > 0 ? totalTerms : 1);
    }
    
    return tf;
  }

  // Hitung TF-IDF vector
  Map<String, double> _computeTFIDF(Map<String, double> tf) {
    final vocabulary = _tfidfModel!['vocabulary'] as Map<String, dynamic>;
    final tfidf = <String, double>{};
    
    for (var term in tf.keys) {
      if (vocabulary.containsKey(term)) {
        final weight = vocabulary[term] as int;
        tfidf[term] = tf[term]! * (weight.toDouble() / 100.0); // Normalize weight
      }
    }
    
    return tfidf;
  }

  // Normalisasi L2
  Map<String, double> _normalizeL2(Map<String, double> vector) {
    double norm = 0.0;
    for (var value in vector.values) {
      norm += value * value;
    }
    norm = (norm > 0) ? sqrt(norm) : 1.0;
    
    final normalized = <String, double>{};
    for (var entry in vector.entries) {
      normalized[entry.key] = entry.value / norm;
    }
    
    return normalized;
  }

  Future<int> predictCategory(String ocrText) async {
    if (_tfidfModel == null) {
      debugPrint('⚠️ Model belum dimuat');
      return 8;
    }

    try {
      // Tokenize char n-gram [2,4]
      final ngrams = _generateNgrams(ocrText, 2, 4);
      
      if (ngrams.isEmpty) return 8;
      
      // Compute TF
      final tf = _computeTF(ngrams);
      
      // Compute TF-IDF
      final tfidf = _computeTFIDF(tf);
      
      // Normalize L2
      final normalized = _normalizeL2(tfidf);
      
      // Score setiap class berdasarkan TF-IDF features
      final classes = _tfidfModel!['classes'] as List;
      double maxScore = 0.0;
      String predictedClass = "Lainnya";
      
      for (var className in classes) {
        double score = 0.0;
        for (var entry in normalized.entries) {
          score += entry.value;
        }
        
        // Bias untuk class tertentu berdasarkan keyword
        final lowerText = ocrText.toLowerCase();
        if (className == "Makanan" && (lowerText.contains("makan") || lowerText.contains("nasi"))) {
          score *= 1.5;
        }
        if (className == "Minuman" && (lowerText.contains("minum") || lowerText.contains("teh"))) {
          score *= 1.5;
        }
        if (className == "Transportasi" && (lowerText.contains("bensin") || lowerText.contains("gojek"))) {
          score *= 1.5;
        }
        
        if (score > maxScore) {
          maxScore = score;
          predictedClass = className;
        }
      }
      
      // Map ke kategori app
      final appCategoryId = classToCategory[predictedClass] ?? 8;
      
      debugPrint('🎯 TF-IDF Class: $predictedClass → App Category: $appCategoryId');
      return appCategoryId;
    } catch (e) {
      debugPrint('❌ Prediction error: $e');
      return 8;
    }
  }

  void dispose() {}
}
