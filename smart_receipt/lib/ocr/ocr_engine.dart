import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_raw_text.dart';

/// Thin wrapper around Google ML Kit's on-device Text Recognition.
///
/// The engine is intentionally kept as an interface so the rest of the app
/// never talks to a third-party API directly. On mobile, [MlKitOcrEngine]
/// runs fully offline using the bundled ML Kit model.
abstract class OcrEngine {
  /// Recognises text on [imagePath] (a scannable local file path).
  ///
  /// Returns the raw text plus per-line geometry so callers can reason about
  /// layout (receipts are highly structured, line order matters).
  Future<OcrRawResult> recognize(String imagePath);

  /// Releases native resources held by the engine.
  Future<void> dispose();
}

/// Raised when the OCR engine itself cannot complete (not "no text found").
class OcrEngineException implements Exception {
  OcrEngineException(this.message);

  final String message;

  @override
  String toString() => 'OcrEngineException: $message';
}

/// Google ML Kit implementation of [OcrEngine].
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _recognizer;

  /// ML Kit's Latin script model recognises Indonesian text well and is
  /// bundled with the app, so OCR keeps working without a network connection.
  TextRecognizer _ensureRecognizer() {
    return _recognizer ??=
        TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  Future<OcrRawResult> recognize(String imagePath) async {
    final File file = File(imagePath);
    if (!file.existsSync()) {
      throw OcrEngineException('File gambar tidak ditemukan: $imagePath');
    }

    try {
      final InputImage input = InputImage.fromFilePath(imagePath);
      final RecognizedText text = await _ensureRecognizer().processImage(input);
      return _toRawResult(text);
    } on OcrEngineException {
      rethrow;
    } catch (error) {
      throw OcrEngineException('Gagal menjalankan OCR: $error');
    }
  }

  OcrRawResult _toRawResult(RecognizedText recognized) {
    final List<OcrLine> lines = <OcrLine>[];
    for (final TextBlock block in recognized.blocks) {
      for (final TextLine line in block.lines) {
        final String value = line.text.trim();
        if (value.isEmpty) {
          continue;
        }
        lines.add(
          OcrLine(
            text: value,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            right: line.boundingBox.right,
            bottom: line.boundingBox.bottom,
          ),
        );
      }
    }

    // ML Kit generally returns blocks/lines top-to-bottom, but sort defensively
    // so downstream parsing can rely on reading order.
    lines.sort((OcrLine a, OcrLine b) {
      final double dy = a.top - b.top;
      if (dy.abs() > 6) {
        return dy.compareTo(0);
      }
      return a.left.compareTo(b.left);
    });

    return OcrRawResult(lines: lines, fullText: recognized.text);
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
