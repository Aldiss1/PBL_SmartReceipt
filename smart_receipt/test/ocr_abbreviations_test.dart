import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/ocr/ocr_abbreviations.dart';

void main() {
  group('OcrAbbreviationExpander', () {
    late OcrAbbreviationExpander expander;

    setUp(() {
      expander = OcrAbbreviationExpander();
    });

    test('expands common minimarket abbreviations', () {
      expect(expander.expand('RDSO ANTI NDA COR'), 'RINSO ANTI NODA CAIR');
      expect(expander.expand('INDM GRG SPL'), 'INDOMIE GORENG SPECIAL');
      expect(expander.expand('FF LW FAT VAN 225'), 'FRISIAN FLAG LW FAT VANILLA 225');
      expect(expander.expand('LFB BW RFL 450'), 'LIFEBUOY BODY WASH REFILL 450');
      expect(expander.expand('LE MIN 600ML'), 'LE MINERAL 600ML');
    });

    test('handles Indomaret S/ brand prefixes', () {
      expect(expander.expand('S/ROTI KRIM KSRY'), 'SARI ROTI KRIM KASURI');
      expect(expander.expand('S/MIE AYM'), 'SUPERMI AYAM');
    });

    test('preserves unknown tokens intact', () {
      expect(expander.expand('KECAP MANIS BANGO'), 'KECAP MANIS BANGO');
      expect(expander.expand(''), '');
    });
  });
}
