import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/ocr/ocr_raw_text.dart';
import 'package:smart_receipt/ocr/ocr_voting.dart';

OcrLine _l(String text, double left, double top, double right, double bottom) =>
    OcrLine(text: text, left: left, top: top, right: right, bottom: bottom);

OcrRawResult _r(List<OcrLine> lines) => OcrRawResult(
      lines: lines,
      fullText: lines.map((OcrLine l) => l.text).join('\n'),
    );

void main() {
  group('OcrRawResult.averageConfidence', () {
    test('averages only non-null lines', () {
      final r = OcrRawResult(lines: <OcrLine>[
        OcrLine(text: 'a', left: 0, top: 0, right: 1, bottom: 1, confidence: 0.9),
        OcrLine(text: 'b', left: 0, top: 2, right: 1, bottom: 3), // null (iOS-style)
        OcrLine(text: 'c', left: 0, top: 4, right: 1, bottom: 5, confidence: 0.7),
      ], fullText: 'a b c');
      expect(r.averageConfidence, 0.8);
    });

    test('is null when no line has confidence', () {
      final r = OcrRawResult(lines: <OcrLine>[
        OcrLine(text: 'a', left: 0, top: 0, right: 1, bottom: 1),
      ], fullText: 'a');
      expect(r.averageConfidence, isNull);
      expect(const OcrRawResult.empty().averageConfidence, isNull);
    });
  });

  group('combineAmountVotes', () {
    // Box: baris 1 di y=10..30, baris 2 di y=50..70; lebar ~300, tinggi 20.
    final OcrRawResult primary = _r(<OcrLine>[
      _l('SABUN LIFEBUOY 856', 10, 10, 310, 30),
      _l('TOTAL 856', 10, 50, 310, 70),
    ]);

    test('amount disepakati 2 dari 3 -> teks primary utuh', () {
      // '85G' = tanpa bacaan amount (Rule 1). v2 membaca 856 -> 2 setuju.
      final v1 = _r(<OcrLine>[
        _l('SABUN LIFEBUOY 85G', 10, 10, 310, 30),
        _l('TOTAL 850', 10, 50, 310, 70),
      ]);
      final v2 = _r(<OcrLine>[
        _l('SABUN LIFEBUOY 856', 12, 12, 308, 28),
        _l('TOTAL 85.00', 10, 52, 310, 72),
      ]);
      final out = combineAmountVotes(primary, <OcrRawResult>[v1, v2]);
      expect(out.lines[0].text, 'SABUN LIFEBUOY 856'); // dikonfirmasi (primary+v2)
      expect(out.lines[1].text, 'TOTAL 856'); // semua beda -> primary
    });

    test('amount mayoritas beda -> token primary diganti string varian pertama', () {
      final p = _r(<OcrLine>[_l('TOTAL 856', 10, 10, 310, 30)]);
      final v1 = _r(<OcrLine>[_l('TOTAL 85,000', 10, 10, 310, 30)]);
      final v2 = _r(<OcrLine>[_l('TOTAL 85000', 10, 10, 310, 30)]);
      final out = combineAmountVotes(p, <OcrRawResult>[v1, v2]);
      expect(out.lines.single.text, 'TOTAL 85,000');
    });

    test('beda pemisah = nilai sama; primary yang dikonfirmasi tidak diubah', () {
      final p = _r(<OcrLine>[_l('TOTAL 154.000', 10, 10, 310, 30)]);
      final v1 = _r(<OcrLine>[_l('TOTAL 154,000', 10, 10, 310, 30)]);
      final v2 = _r(<OcrLine>[_l('TOTAL 154000', 10, 10, 310, 30)]);
      final out = combineAmountVotes(p, <OcrRawResult>[v1, v2]);
      expect(out.lines.single.text, 'TOTAL 154.000');
    });

    test('baris tanpa amount tidak disentuh', () {
      final p = _r(<OcrLine>[_l('SUSU ULTRA', 10, 10, 310, 30)]);
      final v1 = _r(<OcrLine>[_l('SUSU ULTRA 7500', 10, 10, 310, 30)]);
      final out = combineAmountVotes(p, <OcrRawResult>[v1]);
      expect(out.lines.single.text, 'SUSU ULTRA');
    });

    test('IoU < 0.6 tidak dipasangkan -> varian tidak ikut vote', () {
      final p = _r(<OcrLine>[_l('TOTAL 856', 10, 10, 310, 30)]);
      // Box jauh (y=500) -> tak berpasangan, meski isinya "menghakimi" primary.
      final v1 = _r(<OcrLine>[_l('TOTAL 999', 10, 500, 310, 520)]);
      final v2 = _r(<OcrLine>[_l('TOTAL 999', 10, 502, 310, 522)]);
      final out = combineAmountVotes(p, <OcrRawResult>[v1, v2]);
      expect(out.lines.single.text, 'TOTAL 856');
    });

    test('2 varian (sharpened gagal) -> 2 dari 2 masih mengunci', () {
      final p = _r(<OcrLine>[_l('TOTAL 856', 10, 10, 310, 30)]);
      final v1 = _r(<OcrLine>[_l('TOTAL 85,000', 10, 10, 310, 30)]);
      final v2 = _r(<OcrLine>[_l('TOTAL 85000', 10, 10, 310, 30)]);
      final out = combineAmountVotes(p, <OcrRawResult>[v1, v2]);
      expect(out.lines.single.text, 'TOTAL 85,000');
    });

    test('geometry dan urutan baris utuh; fullText mengikuti teks baris', () {
      final p = _r(<OcrLine>[
        _l('A 100', 1, 2, 3, 4),
        _l('TOTAL 200', 1, 10, 3, 12),
      ]);
      final v1 = _r(<OcrLine>[
        _l('A 100', 1, 2, 3, 4),
        _l('TOTAL 2.000', 1, 10, 3, 12),
      ]);
      final v2 = _r(<OcrLine>[
        _l('A 100', 1, 2, 3, 4),
        _l('TOTAL 2.000', 1, 10, 3, 12),
      ]);
      final out = combineAmountVotes(p, <OcrRawResult>[v1, v2]);
      expect(out.lines[1].top, 10);
      expect(out.lines.length, 2);
      expect(out.fullText, 'A 100\nTOTAL 2.000');
    });
  });

  group('candidateBeats', () {
    test('score lebih tinggi selalu menang', () {
      expect(candidateBeats(candidateScore: 5, candidateConfidence: 0.1,
          bestScore: 4, bestConfidence: 0.9), isTrue);
    });

    test('skor sama + confidence lebih tinggi menang', () {
      expect(candidateBeats(candidateScore: 4, candidateConfidence: 0.8,
          bestScore: 4, bestConfidence: 0.6), isTrue);
    });

    test('skor sama + confidence null -> tidak menang (jalur lama)', () {
      expect(candidateBeats(candidateScore: 4, candidateConfidence: null,
          bestScore: 4, bestConfidence: 0.6), isFalse);
      expect(candidateBeats(candidateScore: 4, candidateConfidence: 0.8,
          bestScore: 4, bestConfidence: null), isFalse);
    });

    test('skor sama + confidence sama -> tidak menang', () {
      expect(candidateBeats(candidateScore: 4, candidateConfidence: 0.7,
          bestScore: 4, bestConfidence: 0.7), isFalse);
    });
  });
}
