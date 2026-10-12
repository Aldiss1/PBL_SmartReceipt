import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Preprocessing result applied to a captured receipt image, plus the quality
/// signals used to warn the user about problems that hurt OCR accuracy.
class ImageQualityReport {
  const ImageQualityReport({
    required this.brightness,
    required this.blurScore,
    required this.rotationDegrees,
    required this.width,
    required this.height,
    required this.preparedPath,
    this.lowLight = false,
    this.blurry = false,
    this.rotated = false,
  });

  /// Mean luminance, 0 (black) .. 255 (white).
  final double brightness;

  /// Variance of the Laplacian. Higher = sharper. Below [kBlurThreshold] the
  /// image is considered blurred.
  final double blurScore;

  /// Degrees the image was rotated during preprocessing to make text upright.
  final int rotationDegrees;

  final int width;
  final int height;

  /// Path of the preprocessed image actually sent to the OCR engine.
  final String preparedPath;

  final bool lowLight;
  final bool blurry;
  final bool rotated;

  /// True when at least one quality issue could degrade recognition.
  bool get hasIssue => lowLight || blurry || rotated;

  /// Human readable issues for the UI.
  List<String> get issues {
    final List<String> out = <String>[];
    if (blurry) {
      out.add('Gambar tampak buram');
    }
    if (lowLight) {
      out.add('Pencahayaan rendah / gelap');
    }
    if (rotated) {
      out.add('Gambar diputar $rotationDegrees° agar teks tegak');
    }
    return out;
  }
}

/// Blur is detected from Laplacian variance; the threshold is tuned for
/// downscaled receipt photos and errs toward warning rather than failing.
const double kBlurThreshold = 45;

/// Below this mean luminance we treat the capture as low-light.
const double kLowLightThreshold = 82;

class ImagePreprocessor {
  /// Longest edge used for OCR and analysis. Receipts are text-dense, but
  /// 1600px keeps ML Kit accurate while avoiding huge allocations on phones.
  static const int _maxDimension = 1600;

  /// Analyzes [sourcePath] and writes a normalized copy for OCR to
  /// [outputPath].
  ///
  /// - Downscales very large photos (speed + memory).
  /// - Estimates the text skew angle and rotates the image upright.
  /// - Measures brightness and sharpness to flag low-light/blur.
  /// - Applies contrast/brightness equalisation when the capture is dark.
  Future<ImageQualityReport> prepare({
    required String sourcePath,
    required String outputPath,
  }) async {
    final img.Image? decoded = await _decode(sourcePath);
    if (decoded == null) {
      // Let the OCR engine surface the real error; nothing to preprocess.
      throw ImageQualityException('Gambar tidak dapat dibaca.');
    }

    img.Image working = img.bakeOrientation(decoded);

    if (math.max(working.width, working.height) > _maxDimension) {
      working = working.width >= working.height
          ? img.copyResize(working, width: _maxDimension)
          : img.copyResize(working, height: _maxDimension);
    }

    final double brightness = _meanLuminance(working);
    final double blurScore = _laplacianVariance(working);

    final int angle = _estimateSkewDegrees(working);
    final bool rotated = angle.abs() >= 1;
    if (rotated) {
      working = img.copyRotate(working, angle: -angle.toDouble(), interpolation: img.Interpolation.linear);
    }

    final bool lowLight = brightness < kLowLightThreshold;
    if (lowLight) {
      working = _normalizeBrightness(working, brightness);
    }

    final img.Image finalImage = rotated || lowLight
        ? working
        : img.Image.from(working);

    // Binarization-friendly grayscale contrast boost materially improves ML Kit
    // on faded thermal receipts.
    _boostContrastInPlace(finalImage);

    final File out = File(outputPath);
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(img.encodeJpg(finalImage, quality: 92));

    return ImageQualityReport(
      brightness: brightness,
      blurScore: blurScore,
      rotationDegrees: angle,
      width: finalImage.width,
      height: finalImage.height,
      preparedPath: outputPath,
      lowLight: lowLight,
      blurry: blurScore < kBlurThreshold,
      rotated: rotated,
    );
  }

  Future<img.Image?> _decode(String path) async {
    final File file = File(path);
    if (!file.existsSync()) {
      throw ImageQualityException('File gambar tidak ditemukan.');
    }
    final img.Image? decoded = img.decodeImage(await file.readAsBytes());
    return decoded;
  }

  double _meanLuminance(img.Image image) {
    final img.Image small = image.width > 200
        ? img.copyResize(image, width: 200)
        : image;
    double sum = 0;
    int count = 0;
    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final img.Pixel p = small.getPixel(x, y);
        sum += img.getLuminanceRgb(p.r.toDouble(), p.g.toDouble(), p.b.toDouble());
        count++;
      }
    }
    return count == 0 ? 255 : sum / count;
  }

  /// Variance of the (4-neighbour) Laplacian over a grayscale, downscaled copy.
  double _laplacianVariance(img.Image image) {
    final img.Image gray = img.grayscale(
      image.width > 600 ? img.copyResize(image, width: 600) : image,
    );
    final int w = gray.width;
    final int h = gray.height;
    if (w < 3 || h < 3) {
      return 0;
    }

    double sum = 0;
    double sumSq = 0;
    int count = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final double center = gray.getPixel(x, y).r.toDouble();
        final double lap = 4 * center -
            gray.getPixel(x - 1, y).r -
            gray.getPixel(x + 1, y).r -
            gray.getPixel(x, y - 1).r -
            gray.getPixel(x, y + 1).r;
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }
    if (count == 0) {
      return 0;
    }
    final double mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }

  /// Estimates receipt skew in degrees using a coarse projection profile:
  /// rows of text produce a variance peak when horizontal.
  int _estimateSkewDegrees(img.Image image) {
    final img.Image small = img.copyResize(
      img.grayscale(image),
      width: image.width > 400 ? 400 : image.width,
    );

    double bestVariance = -1;
    int bestAngle = 0;
    for (int angle = -6; angle <= 6; angle++) {
      final double variance = _rowVariance(img.copyRotate(small, angle: angle.toDouble()));
      if (variance > bestVariance) {
        bestVariance = variance;
        bestAngle = angle;
      }
    }
    // Only report a non-zero skew when it is clearly better than straight.
    if (bestAngle == 0) {
      return 0;
    }
    final double upright = _rowVariance(small);
    final double gain = (bestVariance - upright) / (upright.abs() + 1);
    return gain > 0.12 ? bestAngle : 0;
  }

  double _rowVariance(img.Image gray) {
    final int w = gray.width;
    final int h = gray.height;
    if (h < 2) {
      return 0;
    }
    final List<double> rowDarkness = List<double>.filled(h, 0);
    for (int y = 0; y < h; y++) {
      double sum = 0;
      for (int x = 0; x < w; x++) {
        sum += 255 - gray.getPixel(x, y).r;
      }
      rowDarkness[y] = sum / w;
    }
    final double mean =
        rowDarkness.reduce((double a, double b) => a + b) / h;
    double variance = 0;
    for (final double v in rowDarkness) {
      variance += (v - mean) * (v - mean);
    }
    return variance / h;
  }

  img.Image _normalizeBrightness(img.Image image, double brightness) {
    final double lift = (128 - brightness).clamp(20, 90);
    return img.adjustColor(image, brightness: lift * 0.9, contrast: 1.06);
  }

  void _boostContrastInPlace(img.Image image) {
    // Apply a mild contrast stretch around mid-gray.
    for (final img.Pixel p in image) {
      p.r = _stretch(p.r.toInt());
      p.g = _stretch(p.g.toInt());
      p.b = _stretch(p.b.toInt());
    }
  }

  int _stretch(int channel) {
    const double contrast = 1.12;
    final double v = (channel - 128) * contrast + 128;
    return v.clamp(0, 255).round();
  }
}

class ImageQualityException implements Exception {
  ImageQualityException(this.message);

  final String message;

  @override
  String toString() => 'ImageQualityException: $message';
}
