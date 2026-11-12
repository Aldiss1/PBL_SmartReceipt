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

    test('expands the heavy vowel-dropping style used by Superindo', () {
      // Thermal paper plus a narrow column makes cashiers drop vowels, and the
      // photo blurs what is left: `SBN LI FBUY` is Sabun Lifebuoy.
      expect(expander.expand('SBN LI FBUY 85G'), 'SABUN LIFEBUOY 85G');
      expect(expander.expand('BTR ABC AA 2PCS'), 'BATERAI ABC AA 2PCS');
      expect(expander.expand('RTI KRIM KEJU'), 'ROTI KRIM KEJU');
      expect(expander.expand('PST GIGI PEPSDN'), 'PASTA GIGI PEPSODENT');
      expect(expander.expand('AIR MNRAL AQUA 600'), 'AIR MINERAL AQUA 600');
      expect(expander.expand('MIE GRG INDOME 85G'), 'MIE GORENG INDOMIE 85G');
      expect(expander.expand('SU UHT ULTRA 1L'), 'SUSU UHT ULTRA 1L');
      expect(expander.expand('TISU PASEO 250S'), 'TISSUE PASEO 250S');
    });

    test('preserves unknown tokens intact', () {
      expect(expander.expand('KECAP MANIS BANGO'), 'KECAP MANIS BANGO');
      expect(expander.expand(''), '');
    });
  });
}
