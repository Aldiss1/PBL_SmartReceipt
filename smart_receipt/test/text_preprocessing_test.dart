import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/ocr/tfidf_classifier.dart';
import 'package:smart_receipt/services/text_normalizer.dart';

void main() {
  group('IndonesianTextPreprocessor.clean — stage 1', () {
    final IndonesianTextPreprocessor p = IndonesianTextPreprocessor();

    test('lower-cases and strips currency amounts', () {
      expect(p.clean('INDOMIE GORENG Rp 3.500'), 'indomie goreng');
      expect(p.clean('TOTAL Rp1.420.000'), 'total');
    });

    test('drops plain numbers, quantities and percentages', () {
      expect(p.clean('AQUA 600ML 2 X 4.000'), 'aqua');
      expect(p.clean('DISKON 25%'), 'diskon');
    });

    test('removes measurement and packaging units', () {
      expect(p.clean('BERAS 5 KG'), 'beras');
      expect(p.clean('TISU 250S 2 PAK'), 'tisu');
    });

    test('collapses OCR stutter such as "aquaaa"', () {
      expect(p.clean('AQUAAA'), 'aquaa');
      expect(p.clean('INDOMIEEEE GORENG'), 'indomiee goreng');
    });

    test('strips punctuation and normalizes unicode look-alikes', () {
      expect(p.clean('KOPI “KENANGAN”'), 'kopi kenangan');
      expect(p.clean('TEH—SOSRO'), 'teh sosro');
    });

    test('drops a quantity multiplier glued to a product name', () {
      expect(p.clean('KOPI KENANGAN 2×'), 'kopi kenangan');
      expect(p.clean('AQUA 2 X'), 'aqua');
    });
  });

  group('IndonesianTextPreprocessor.tokenize — stage 2', () {
    final IndonesianTextPreprocessor p = IndonesianTextPreprocessor();

    test('splits on whitespace and drops single characters', () {
      expect(p.tokenize('a bbb cc dddd'), <String>['bbb', 'cc', 'dddd']);
    });

    test('empty input yields no tokens', () {
      expect(p.tokenize('   '), isEmpty);
    });
  });

  group('IndonesianTextPreprocessor.normalizeTokens — stage 3', () {
    final IndonesianTextPreprocessor p = IndonesianTextPreprocessor();

    test('expands Indonesian brand/abbreviation slangs', () {
      expect(p.normalizeTokens(<String>['indomie', 'goreng']),
          <String>['mie', 'instan', 'goreng']);
      expect(p.normalizeTokens(<String>['aqua']), <String>['air', 'mineral']);
      expect(p.normalizeTokens(<String>['pertalite']), <String>['bensin']);
    });

    test('removes Indonesian stopwords', () {
      final List<String> out =
          p.normalizeTokens(<String>['susu', 'untuk', 'anak', 'yang', 'baik']);
      expect(out, isNot(contains('untuk')));
      expect(out, isNot(contains('yang')));
      expect(out, contains('susu'));
    });

    test('removes units that survived tokenization', () {
      expect(p.normalizeTokens(<String>['beras', 'kg']), <String>['beras']);
    });

    test('full pipeline produces a normalized, joined string', () {
      final ProcessedText processed =
          p.process('INDOMIE GORENG Rp 3.500 2 X');
      expect(processed.normalized, 'mie instan goreng');
      expect(processed.tokens, contains('indomie'));
      expect(processed.isEmpty, isFalse);
    });

    test('text made only of stopwords and numbers is empty', () {
      final ProcessedText processed = p.process('TOTAL 12.000 UNTUK');
      expect(processed.isEmpty, isTrue);
    });
  });

  group('IndonesianTextPreprocessor rule table', () {
    test('loadFromMap overrides the built-in defaults', () {
      final IndonesianTextPreprocessor p = IndonesianTextPreprocessor();
      p.loadFromMap(<String, dynamic>{
        'abbreviations': <String, String>{'mystery': 'obat'},
        'stopwords': <String>['hapus'],
        'units': <String>['zz'],
      });
      expect(p.normalizeTokens(<String>['mystery']), <String>['obat']);
      expect(p.normalizeTokens(<String>['hapus']), isEmpty);
      expect(p.normalizeTokens(<String>['zz']), isEmpty);
      // Untouched tokens still pass through.
      expect(p.normalizeTokens(<String>['ayam']), <String>['ayam']);
    });
  });

  group('Preprocessing feeds the classifier', () {
    test('normalized tokens produce a usable TF-IDF vector', () {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      engine.loadFromJsonString(_modelFixtureJson());

      final IndonesianTextPreprocessor p = IndonesianTextPreprocessor();
      final String normalized = p.normalize('INDOMIE GORENG 2 X Rp3.500');
      expect(normalized, isNotEmpty);

      // Sanity: the vectorizer accepts the preprocessed output.
      expect(engine.vectorize(normalized), isNotEmpty);
    });

    test('raw OCR text also vectorizes before preprocessing', () {
      final TfidfNaiveBayesEngine engine = TfidfNaiveBayesEngine();
      engine.loadFromJsonString(_modelFixtureJson());
      expect(engine.vectorize('INDOMIE GORENG 2 X Rp3.500'), isNotEmpty);
    });
  });
}

/// Reads the exported model from the test fixture copy of the asset.
String _modelFixtureJson() {
  final File file = File('test/fixtures/model_kategori_produk.json');
  if (!file.existsSync()) {
    fail('Fixture model tidak ditemukan di ${file.path}');
  }
  return file.readAsStringSync();
}
