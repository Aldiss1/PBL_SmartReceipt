import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/ocr/ocr_raw_text.dart';
import 'package:smart_receipt/ocr/ocr_text_corrector.dart';
import 'package:smart_receipt/ocr/receipt_parser.dart';

OcrRawResult _raw(List<String> lines) {
  return OcrRawResult(
    lines: <OcrLine>[
      for (int i = 0; i < lines.length; i++)
        OcrLine(
          text: lines[i],
          left: 0,
          top: i * 22.0,
          right: 100,
          bottom: i * 22.0 + 18,
        ),
    ],
    fullText: lines.join('\n'),
  );
}

String _fix(String line) =>
    correctOcrText(_raw(<String>[line])).lines.first.text;

void main() {
  group('Post-OCR text corrector', () {
    // -----------------------------------------------------------------------
    // Keyword fixes
    // -----------------------------------------------------------------------
    group('keyword correction', () {
      test('T0TAL → TOTAL', () {
        expect(_fix('T0TAL  33.900'), contains('TOTAL'));
      });

      test('SUBT0TAL → SUBTOTAL or SUB TOTAL', () {
        final String result = _fix('SUBT0TAL  15.000');
        expect(
          result.contains('SUBTOTAL') || result.contains('SUB TOTAL'),
          isTrue,
        );
      });

      test('TUNAl → TUNAI', () {
        expect(_fix('TUNAl  50.000'), contains('TUNAI'));
      });

      test('KEMBALl → KEMBALI', () {
        expect(_fix('KEMBALl  16.100'), contains('KEMBALI'));
      });

      test('D1SK0N → DISKON', () {
        expect(_fix('D1SK0N  1.000'), contains('DISKON'));
      });

      test('QR1S → QRIS', () {
        expect(_fix('QR1S  33.900'), contains('QRIS'));
      });
    });

    // -----------------------------------------------------------------------
    // Amount-part corrections (letters → digits in price fields)
    // -----------------------------------------------------------------------
    group('amount correction (letters → digits)', () {
      test('O in amount becomes 0: Rp 1O.OOO → Rp 10.000', () {
        final String result = _fix('SABUN  Rp 1O.OOO');
        expect(result, contains('10.000'));
      });

      test('l in amount becomes 1: Rp l5.000 → Rp 15.000', () {
        final String result = _fix('SUSU  Rp l5.000');
        expect(result, contains('15.000'));
      });

      test('I in amount becomes 1: Rp I0.000 → Rp 10.000', () {
        final String result = _fix('ROTI  Rp I0.000');
        expect(result, contains('10.000'));
      });

      test('S in amount becomes 5: 3.S00 → 3.500', () {
        final String result = _fix('MIE  3.S00');
        expect(result, contains('3.500'));
      });

      test('B in amount becomes 8: B.000 → 8.000', () {
        final String result = _fix('TELUR  B.000');
        expect(result, contains('8.000'));
      });

      test('comma-thousands normalised: 10,000 → 10.000', () {
        final String result = _fix('AQUA  10,000');
        expect(result, contains('10.000'));
      });

      test('attached quantity multiplier 1x / Ix is preserved as 1 x, never Ix', () {
        expect(_fix('1x 2.000'), '1 x 2.000');
        expect(_fix('Ix 9.000'), '1 x 9.000');
        expect(_fix('lx 8.000'), '1 x 8.000');
      });
    });

    // -----------------------------------------------------------------------
    // Name-part corrections (digits → letters when flanked by letters)
    // -----------------------------------------------------------------------
    group('name correction (digits → letters when flanked by letters)', () {
      test('0 between letters → O: SAB0N → SABON', () {
        final String result = _fix('SAB0N  5.000');
        expect(result, contains('SABON'));
      });

      test('1 at start before letters → I: 1NDOMIE → INDOMIE', () {
        final String result = _fix('1NDOMIE  3.500');
        expect(result, contains('INDOMIE'));
      });

      test('5 before letters → S: 5ABUN → SABUN', () {
        final String result = _fix('5ABUN LIFEBUOY  10.000');
        expect(result, contains('SABUN'));
      });

      test('8 before letters → B: 8ERAS → BERAS', () {
        final String result = _fix('8ERAS 5KG  45.000');
        expect(result, contains('BERAS'));
      });

      test('digit NOT flanked by letters stays: MILD 16 unchanged', () {
        final String result = _fix('MILD 16  25.000');
        expect(result, contains('16'));
      });

      test('digit NOT flanked by letters stays: AQUA 600ML 600 unchanged', () {
        final String result = _fix('AQUA 600ML  4.000');
        // 600 should stay, ML should stay
        expect(result, contains('600'));
      });
    });

    // -----------------------------------------------------------------------
    // Full-line integration
    // -----------------------------------------------------------------------
    group('full-line integration', () {
      test('complex line with both name and amount errors', () {
        // "5ABUN LIFEBU0Y  Rp 1O.O0O"  →  name: SABUN LIFEBUOY, price: 10.000
        final String result = _fix('5ABUN LIFEBU0Y  Rp 1O.O0O');
        expect(result, contains('SABUN'));
        expect(result, contains('10.000'));
      });

      test('total line corrected end-to-end', () {
        final String result = _fix('T0TAL  Rp 3l.5OO');
        expect(result, contains('TOTAL'));
        expect(result, contains('31.500'));
      });

      test('empty line returned unchanged', () {
        expect(_fix(''), isEmpty);
      });

      test('pure number line returned with digits corrected', () {
        // A price-only line like `3.5OO` on its own.
        final String result = _fix('3.5OO');
        expect(result, contains('3.500'));
      });

      test('Alfamart 2-line receipt with 1x does not emit Ix noise items', () {
        final OcrRawResult raw = _raw(<String>[
          'Alfamart Jogja',
          'Jl. Kenangan',
          'Jogja',
          '08897482739',
          '18.7.2024 08:49 #281',
          'Cimory',
          '1x 2.000',
          '2.000',
          'Cimory hazelnut',
          '1x 9.000',
          '9.000',
          'Frestea madu',
          '1x 8.000',
          '8.000',
          'Ice cream aice',
          '1x 5.000',
          '5.000',
          'Kanzler',
          '1x 10.000',
          '10.000',
          'Le Minerale',
          '1x 4.000',
          '4.000',
          'Total Rp38.000',
          'Tunai Rp38.000',
          'Lunas',
          'Barang yang sudah dibeli tidak b',
          'isa dikembalikan lagi',
          'Kasir : Sinta',
          'Terima kasih',
        ]);

        final OcrRawResult corrected = correctOcrText(raw);
        final ParsedReceipt parsed = ReceiptParser().parse(corrected);

        expect(
          parsed.items.map((ParsedItem i) => i.name).toList(),
          <String>[
            'Cimory',
            'Cimory hazelnut',
            'Frestea madu',
            'Ice cream aice',
            'Kanzler',
            'Le Minerale',
          ],
        );
        expect(
          parsed.items.map((ParsedItem i) => i.price).toList(),
          <int>[2000, 9000, 8000, 5000, 10000, 4000],
        );
        expect(parsed.total, 38000);
      });
    });

    // -----------------------------------------------------------------------
    // correctOcrText: result has same line count
    // -----------------------------------------------------------------------
    test('correctOcrText preserves line count', () {
      final OcrRawResult input = _raw(<String>[
        '1NDOMIE GORENG  Rp 3.5OO',
        'AQUA 600ML  Rp 4.OOO',
        'T0TAL  Rp 7.5OO',
      ]);
      final OcrRawResult output = correctOcrText(input);
      expect(output.lines.length, input.lines.length);
    });

    test('correctOcrText returns empty unchanged', () {
      const OcrRawResult empty = OcrRawResult.empty();
      final OcrRawResult result = correctOcrText(empty);
      expect(result.isEmpty, isTrue);
    });
  });
}
