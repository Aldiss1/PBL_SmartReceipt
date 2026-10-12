import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'image_quality.dart';
import 'ocr_engine.dart';
import 'ocr_raw_text.dart';
import 'receipt_parser.dart';

/// Everything produced by scanning one receipt.
class OcrScanResult {
  const OcrScanResult({
    required this.sourcePath,
    required this.quality,
    required this.raw,
    required this.parsed,
  });

  /// Original captured/gallery image.
  final String sourcePath;

  /// Preprocessing report + path of the image that was actually OCR'd.
  final ImageQualityReport quality;

  final OcrRawResult raw;
  final ParsedReceipt parsed;

  bool get hasRecognizedText => !raw.isEmpty;
}

/// Raised for user-facing OCR failures (empty result, unreadable image, ...).
class OcrFailure implements Exception {
  OcrFailure(this.message, {this.hint});

  final String message;
  final String? hint;

  @override
  String toString() => message;
}

/// Pipeline stages, surfaced so the UI can show real progress.
enum OcrStage { preprocessing, recognizing, parsing, done }

/// Orchestrates the full pipeline:
/// capture → preprocess (rotation/blur/low-light) → ML Kit OCR → parse.
class OcrService {
  OcrService({OcrEngine? engine, ImagePreprocessor? preprocessor})
      : _engine = engine ?? MlKitOcrEngine(),
        _preprocessor = preprocessor ?? ImagePreprocessor();

  final OcrEngine _engine;
  final ImagePreprocessor _preprocessor;
  final ReceiptParser _parser = ReceiptParser();

  Future<OcrScanResult> process(
    String sourcePath, {
    void Function(OcrStage stage)? onStage,
  }) async {
    final Directory dir = await getTemporaryDirectory();
    final String preparedPath =
        '${dir.path}/ocr_prepared_${DateTime.now().millisecondsSinceEpoch}.jpg';

    onStage?.call(OcrStage.preprocessing);
    final ImageQualityReport quality;
    try {
      quality = await _preprocessor.prepare(
        sourcePath: sourcePath,
        outputPath: preparedPath,
      );
    } catch (e) {
      throw OcrFailure(
        'Gambar tidak dapat diproses.',
        hint: 'Pastikan file gambar valid lalu coba lagi.',
      );
    }

    onStage?.call(OcrStage.recognizing);
    final OcrRawResult raw;
    try {
      raw = await _engine.recognize(quality.preparedPath);
    } on OcrEngineException catch (e) {
      throw OcrFailure('OCR gagal dijalankan.', hint: e.message);
    }

    if (raw.isEmpty) {
      throw OcrFailure(
        'Tidak ada teks yang terbaca pada struk.',
        hint: 'Coba foto ulang dengan pencahayaan lebih terang dan '
            'posisikan struk memenuhi bingkai.',
      );
    }

    onStage?.call(OcrStage.parsing);
    final ParsedReceipt parsed = _parser.parse(raw);
    onStage?.call(OcrStage.done);

    developer.log(
      'OCR selesai: ${raw.lineCount} baris, '
      'store="${parsed.store}", items=${parsed.items.length}, '
      'total=${parsed.total}, brightness=${quality.brightness.toStringAsFixed(0)}, '
      'blur=${quality.blurScore.toStringAsFixed(1)}, '
      'rotated=${quality.rotationDegrees}°',
      name: 'SmartReceipt.OCR',
    );

    return OcrScanResult(
      sourcePath: sourcePath,
      quality: quality,
      raw: raw,
      parsed: parsed,
    );
  }

  Future<void> dispose() => _engine.dispose();
}
