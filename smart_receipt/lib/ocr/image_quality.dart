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
  /// Longest edge used for OCR.
  ///
  /// A camera capture frames the receipt tightly, so 1600px is plenty. A
  /// gallery photo is usually a full-resolution shot with the receipt occupying
  /// part of the frame; downscaling that to 1600px shrinks the printed text
  /// below what ML Kit can read reliably. 2400px keeps small thermal print
  /// legible without exhausting memory.
  static const int _maxDimension = 2400;

  /// If the image is smaller than this on its short edge it is upscaled, so
  /// text that came from a screenshot or a distant gallery shot still has
  /// enough pixels per character for the recognizer.
  static const int _minShortEdge = 900;

  /// Crops to a region of interest and upscales it for a second OCR pass.
  ///
  /// Gallery photos usually show more than the receipt: a table, a hand, the
  /// floor. When the recognized text occupies only a small part of the frame,
  /// cropping to it and scaling the crop up gives the recognizer far more
  /// pixels per character than re-reading the full frame.
  Future<String> prepareCrop({
    required String preparedPath,
    required String outputPath,
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) async {
    final img.Image? decoded = await _decode(preparedPath);
    if (decoded == null) {
      return preparedPath;
    }

    final double padX = (right - left) * 0.04;
    final double padY = (bottom - top) * 0.04;
    final int x0 = (left - padX).floor().clamp(0, decoded.width - 1);
    final int y0 = (top - padY).floor().clamp(0, decoded.height - 1);
    final int x1 = (right + padX).ceil().clamp(x0 + 1, decoded.width);
    final int y1 = (bottom + padY).ceil().clamp(y0 + 1, decoded.height);

    img.Image cropped = img.copyCrop(
      decoded,
      x: x0,
      y: y0,
      width: x1 - x0,
      height: y1 - y0,
    );

    final int shortEdge = math.min(cropped.width, cropped.height);
    if (shortEdge > 0 && shortEdge < _minShortEdge) {
      final double factor = _minShortEdge / shortEdge;
      cropped = img.copyResize(
        cropped,
        width: (cropped.width * factor).round(),
        height: (cropped.height * factor).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    final File out = File(outputPath);
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(img.encodeJpg(cropped, quality: 92));
    return outputPath;
  }

  /// Rotates an already-prepared image by [degrees] and writes it to
  /// [outputPath].
  ///
  /// Used as a last-resort OCR retry: a photo imported from the gallery may be
  /// stored sideways with no EXIF orientation left to correct it, in which case
  /// the recognizer reads almost nothing until the image is turned upright.
  Future<String> prepareRotated({
    required String preparedPath,
    required String outputPath,
    required int degrees,
  }) async {
    final img.Image? decoded = await _decode(preparedPath);
    if (decoded == null) {
      return preparedPath;
    }
    final img.Image rotated =
        img.copyRotate(decoded, angle: degrees.toDouble());
    final File out = File(outputPath);
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(img.encodeJpg(rotated, quality: 92));
    return outputPath;
  }

  /// Produces a high-contrast, grayscale copy of an already-prepared image.
  ///
  /// Used as a second OCR attempt when the first pass reads too little: thermal
  /// receipts fade unevenly, and a locally thresholded image often recovers the
  /// digits that the colour pass lost. This is a standard fallback in document
  /// OCR pipelines and is only paid for when the first attempt looks weak.
  Future<String> prepareBinarized({
    required String preparedPath,
    required String outputPath,
  }) async {
    final img.Image? decoded = await _decode(preparedPath);
    if (decoded == null) {
      return preparedPath;
    }

    final img.Image gray = img.grayscale(decoded);
    final img.Image binary = img.Image(
      width: gray.width,
      height: gray.height,
      numChannels: 3,
    );

    // Adaptive mean threshold over a sliding window keeps faint strokes while
    // removing the background gradient that confuses the recognizer.
    const int window = 31;
    final int w = gray.width;
    final int h = gray.height;

    // Integral image for O(1) window sums.
    final List<int> integral = List<int>.filled((w + 1) * (h + 1), 0);
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += gray.getPixel(x, y).r.toInt();
        integral[(y + 1) * (w + 1) + (x + 1)] =
            integral[y * (w + 1) + (x + 1)] + rowSum;
      }
    }

    int windowSum(int x0, int y0, int x1, int y1) {
      return integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int x0 = math.max(0, x - window ~/ 2);
        final int y0 = math.max(0, y - window ~/ 2);
        final int x1 = math.min(w, x + window ~/ 2 + 1);
        final int y1 = math.min(h, y + window ~/ 2 + 1);
        final int count = (x1 - x0) * (y1 - y0);
        final double mean = windowSum(x0, y0, x1, y1) / count;
        // Slightly below the local mean: printed ink is darker than paper.
        final int value =
            gray.getPixel(x, y).r < mean - 8 ? 0 : 255;
        final img.Pixel p = binary.getPixel(x, y);
        p.r = value;
        p.g = value;
        p.b = value;
      }
    }

    final File out = File(outputPath);
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(img.encodeJpg(binary, quality: 92));
    return outputPath;
  }

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

    // Gallery photos are often taken from further away than the in-app camera
    // framing, leaving the receipt small in the frame. Upscaling the short edge
    // restores the pixels-per-character the recognizer needs.
    final int shortEdge = math.min(working.width, working.height);
    if (shortEdge < _minShortEdge && shortEdge > 0) {
      final double factor = _minShortEdge / shortEdge;
      working = img.copyResize(
        working,
        width: (working.width * factor).round(),
        height: (working.height * factor).round(),
        interpolation: img.Interpolation.cubic,
      );
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
    // A single global contrast stretch cannot fix a receipt photographed under
    // uneven light: the bright half is already clipped while the shadowed half
    // stays flat. Local (tile-based) normalisation — the same idea as CLAHE,
    // the standard preprocessing step for document OCR — equalises each region
    // independently so faded thermal print becomes legible everywhere.
    _normalizeLocalContrastInPlace(image);
  }

  /// Tile-based local contrast normalisation with bilinear interpolation
  /// between tiles, so no tile seams appear.
  void _normalizeLocalContrastInPlace(img.Image image) {
    const int tilesX = 8;
    const int tilesY = 8;
    const double targetStd = 52;
    const double minStd = 8;

    final int w = image.width;
    final int h = image.height;
    if (w < tilesX * 4 || h < tilesY * 4) {
      return;
    }

    final int tileW = (w / tilesX).ceil();
    final int tileH = (h / tilesY).ceil();

    // Per-tile mean and standard deviation of luminance.
    final List<double> means = List<double>.filled(tilesX * tilesY, 128);
    final List<double> stds = List<double>.filled(tilesX * tilesY, minStd);
    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final int x0 = tx * tileW;
        final int y0 = ty * tileH;
        final int x1 = math.min(x0 + tileW, w);
        final int y1 = math.min(y0 + tileH, h);
        double sum = 0;
        double sumSq = 0;
        int count = 0;
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            final img.Pixel p = image.getPixel(x, y);
            final double luma = img
                .getLuminanceRgb(
                  p.r.toDouble(),
                  p.g.toDouble(),
                  p.b.toDouble(),
                )
                .toDouble();
            sum += luma;
            sumSq += luma * luma;
            count++;
          }
        }
        final int index = ty * tilesX + tx;
        if (count > 0) {
          final double mean = sum / count;
          final double variance = math.max(sumSq / count - mean * mean, 0);
          means[index] = mean;
          stds[index] = math.max(math.sqrt(variance), minStd);
        }
      }
    }

    for (int y = 0; y < h; y++) {
      final double gy = (y / tileH) - 0.5;
      final int ty0 = gy.floor().clamp(0, tilesY - 1);
      final int ty1 = (ty0 + 1).clamp(0, tilesY - 1);
      final double fy = (gy - ty0).clamp(0.0, 1.0);

      for (int x = 0; x < w; x++) {
        final double gx = (x / tileW) - 0.5;
        final int tx0 = gx.floor().clamp(0, tilesX - 1);
        final int tx1 = (tx0 + 1).clamp(0, tilesX - 1);
        final double fx = (gx - tx0).clamp(0.0, 1.0);

        final double m00 = means[ty0 * tilesX + tx0];
        final double m10 = means[ty0 * tilesX + tx1];
        final double m01 = means[ty1 * tilesX + tx0];
        final double m11 = means[ty1 * tilesX + tx1];
        final double s00 = stds[ty0 * tilesX + tx0];
        final double s10 = stds[ty0 * tilesX + tx1];
        final double s01 = stds[ty1 * tilesX + tx0];
        final double s11 = stds[ty1 * tilesX + tx1];

        final double mean = _bilerp(m00, m10, m01, m11, fx, fy);
        final double std = _bilerp(s00, s10, s01, s11, fx, fy);
        final double gain = targetStd / std;

        final img.Pixel p = image.getPixel(x, y);
        p.r = _applyLocal(p.r.toDouble(), mean, gain);
        p.g = _applyLocal(p.g.toDouble(), mean, gain);
        p.b = _applyLocal(p.b.toDouble(), mean, gain);
      }
    }
  }

  double _bilerp(
    double v00,
    double v10,
    double v01,
    double v11,
    double fx,
    double fy,
  ) {
    final double top = v00 + (v10 - v00) * fx;
    final double bottom = v01 + (v11 - v01) * fx;
    return top + (bottom - top) * fy;
  }

  int _applyLocal(double channel, double mean, double gain) {
    // Preserve the mid-tone the tile was centred on, then stretch around it.
    final double v = (channel - mean) * gain + mean;
    return v.clamp(0, 255).round();
  }
}

class ImageQualityException implements Exception {
  ImageQualityException(this.message);

  final String message;

  @override
  String toString() => 'ImageQualityException: $message';
}
