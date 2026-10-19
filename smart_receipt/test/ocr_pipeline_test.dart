import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:smart_receipt/ocr/image_quality.dart';
import 'package:smart_receipt/ocr/receipt_classifier.dart';

/// Paints a synthetic receipt: dark text lines on a light background.
img.Image _receiptImage({
  int width = 600,
  int height = 900,
  int background = 245,
  int ink = 25,
}) {
  final img.Image im = img.Image(width: width, height: height);
  img.fill(im, color: img.ColorRgb8(background, background, background));
  for (int y = 60; y < height - 40; y += 34) {
    // Vary line length so the projection profile has real structure.
    final int len = width - 120 - (y % 100);
    img.drawRect(
      im,
      x1: 60,
      y1: y,
      x2: 60 + len,
      y2: y + 10,
      color: img.ColorRgb8(ink, ink, ink),
    );
  }
  return im;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocr_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  Future<String> write(img.Image image, String name) async {
    final File f = File('${tmp.path}/$name');
    await f.writeAsBytes(img.encodeJpg(image, quality: 95));
    return f.path;
  }

  group('ImagePreprocessor quality detection', () {
    test('clean, well-lit receipt is neither blurry nor low-light', () async {
      final String src = await write(_receiptImage(), 'clean.jpg');
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/clean_out.jpg',
      );

      expect(r.brightness, greaterThan(kLowLightThreshold));
      expect(r.lowLight, isFalse);
      expect(r.blurry, isFalse);
      expect(File(r.preparedPath).existsSync(), isTrue);
    });

    test('dark capture is flagged as low-light and brightened', () async {
      final String src = await write(
        _receiptImage(background: 40, ink: 8),
        'dark.jpg',
      );
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/dark_out.jpg',
      );

      expect(r.brightness, lessThan(kLowLightThreshold));
      expect(r.lowLight, isTrue);
      expect(r.issues.any((String s) => s.contains('Pencahayaan')), isTrue);

      // The prepared output should be measurably brighter than the source.
      final img.Image out = img.decodeImage(
        File(r.preparedPath).readAsBytesSync(),
      )!;
      final img.Image inImg = img.decodeImage(File(src).readAsBytesSync())!;
      expect(_mean(out), greaterThan(_mean(inImg)));
    });

    test('blurred capture reports low sharpness', () async {
      final img.Image sharp = _receiptImage();
      final String src = await write(img.gaussianBlur(sharp, radius: 6), 'blur.jpg');
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/blur_out.jpg',
      );

      expect(r.blurry, isTrue);
      expect(r.issues.any((String s) => s.contains('buram')), isTrue);
    });

    test('rotated receipt is detected and corrected', () async {
      final String src = await write(
        img.copyRotate(_receiptImage(), angle: 4),
        'rotated.jpg',
      );
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/rot_out.jpg',
      );

      expect(r.rotated, isTrue);
      expect(r.rotationDegrees.abs(), inInclusiveRange(1, 6));
    });

    test('oversized image is downscaled', () async {
      final String src = await write(
        _receiptImage(width: 3200, height: 2400),
        'big.jpg',
      );
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/big_out.jpg',
      );

      expect(r.width <= 3000 && r.height <= 3000, isTrue);
    });

    test('small gallery photo is upscaled for legibility', () async {
      final String src = await write(
        _receiptImage(width: 600, height: 800),
        'small.jpg',
      );
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/small_out.jpg',
      );

      // The short edge must reach the minimum text-legibility size.
      expect(math.min(r.width, r.height) >= 900, isTrue);
    });

    test('crops to the receipt region for a second OCR pass', () async {
      final String src = await write(
        _receiptImage(width: 1200, height: 1600),
        'crop_src.jpg',
      );
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/crop_prepared.jpg',
      );

      final String cropPath = '${tmp.path}/crop_out.jpg';
      await ImagePreprocessor().prepareCrop(
        preparedPath: r.preparedPath,
        outputPath: cropPath,
        left: r.width * 0.2,
        top: r.height * 0.3,
        right: r.width * 0.8,
        bottom: r.height * 0.7,
      );

      final img.Image? decoded =
          img.decodeImage(await File(cropPath).readAsBytes());
      expect(decoded, isNotNull);
      // The crop is upscaled so the characters get more pixels than they had in
      // the full frame; that is the whole point of the second pass.
      expect(math.min(decoded!.width, decoded.height) >= 1600, isTrue);
      // It must still be a crop: the aspect ratio follows the requested region.
      final double requested = (r.width * 0.6) / (r.height * 0.4);
      final double actual = decoded.width / decoded.height;
      expect((actual - requested).abs() < 0.05, isTrue);
    });

    test('detects the receipt region inside a larger photo', () async {
      // A photo where the receipt is a small block of print surrounded by a
      // plain background — the gallery case that used to OCR badly.
      final img.Image photo = img.Image(width: 1200, height: 1600);
      img.fill(photo, color: img.ColorRgb8(235, 235, 235));
      // Filled print, like real receipt text rather than a hollow outline.
      final img.Image receipt = img.Image(width: 700, height: 900);
      img.fill(receipt, color: img.ColorRgb8(245, 245, 245));
      for (int y = 60; y < 860; y += 30) {
        img.fillRect(
          receipt,
          x1: 60,
          y1: y,
          x2: 60 + (560 - (y % 90)),
          y2: y + 9,
          color: img.ColorRgb8(25, 25, 25),
        );
      }
      img.compositeImage(photo, receipt, dstX: 250, dstY: 350);

      final String src = await write(photo, 'region.jpg');
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/region_out.jpg',
      );

      final ImageRegion? region =
          await ImagePreprocessor().detectInkBounds(r.preparedPath);
      expect(region, isNotNull);

      // The detected box must sit inside the pasted receipt, not the whole frame.
      final double w = region!.width / r.width;
      final double h = region.height / r.height;
      expect(w < 0.75, isTrue);
      expect(h < 0.75, isTrue);
      expect(region.left / r.width > 0.1, isTrue);
      expect(region.top / r.height > 0.1, isTrue);
    });

    test('returns no region for a blank image', () async {
      final img.Image blank = img.Image(width: 800, height: 800);
      img.fill(blank, color: img.ColorRgb8(250, 250, 250));
      final String src = await write(blank, 'blank.jpg');
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/blank_out.jpg',
      );

      expect(await ImagePreprocessor().detectInkBounds(r.preparedPath), isNull);
    });

    test('binarized copy is written as a readable image', () async {
      final String src = await write(
        _receiptImage(width: 900, height: 1200),
        'bin_src.jpg',
      );
      final ImageQualityReport r = await ImagePreprocessor().prepare(
        sourcePath: src,
        outputPath: '${tmp.path}/bin_prepared.jpg',
      );
      final String binaryPath = '${tmp.path}/bin_out.jpg';
      await ImagePreprocessor().prepareBinarized(
        preparedPath: r.preparedPath,
        outputPath: binaryPath,
      );

      final img.Image? decoded =
          img.decodeImage(await File(binaryPath).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, r.width);
    });

    test('missing file raises a readable error', () async {
      expect(
        () => ImagePreprocessor().prepare(
          sourcePath: '${tmp.path}/nope.jpg',
          outputPath: '${tmp.path}/x.jpg',
        ),
        throwsA(isA<ImageQualityException>()),
      );
    });
  });

  group('ReceiptClassifier', () {
    final ReceiptClassifier clf = ReceiptClassifier();

    test('maps common groceries to sensible categories', () {
      expect(clf.classify('INDOMIE GORENG').category, 'Makanan');
      expect(clf.classify('AQUA 600ML').category, 'Minuman');
      expect(clf.classify('SABUN LIFEBUOY').category, 'Perawatan Diri');
      expect(clf.classify('TISSUE PASEO').category, 'Rumah Tangga');
      expect(clf.classify('PERTALITE').category, 'Transportasi');
      expect(clf.classify('POWERBANK 10000MAH').category, 'Elektronik');
      expect(clf.classify('KAOS POLOS').category, 'Pakaian');
    });

    test('unknown item falls back to Lainnya with low confidence', () {
      final ItemPrediction p = clf.classify('ZXQW PRD 99');
      expect(p.category, 'Lainnya');
      expect(p.confidence, lessThan(0.5));
    });

    test('confidence stays within bounds', () {
      for (final String name in <String>[
        'INDOMIE GORENG',
        'AQUA',
        'XYZ',
        'SABUN LIFEBUOY MANDI',
      ]) {
        final ItemPrediction p = clf.classify(name);
        expect(p.confidence, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}

double _mean(img.Image image) {
  double sum = 0;
  int n = 0;
  for (final img.Pixel p in image) {
    sum += p.r.toDouble();
    n++;
  }
  return n == 0 ? 0 : sum / n;
}
