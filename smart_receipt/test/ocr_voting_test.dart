import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/ocr/ocr_raw_text.dart';

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
}
