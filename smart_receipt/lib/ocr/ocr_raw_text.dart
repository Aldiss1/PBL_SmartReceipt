/// Raw OCR output: the recognised lines with their on-image geometry plus the
/// concatenated text. Kept free of any plugin types so it can be parsed and
/// unit-tested without a device.
class OcrRawResult {
  const OcrRawResult({required this.lines, required this.fullText});

  const OcrRawResult.empty()
      : lines = const <OcrLine>[],
        fullText = '';

  final List<OcrLine> lines;
  final String fullText;

  bool get isEmpty => lines.isEmpty || fullText.trim().isEmpty;

  /// Number of recognised lines.
  int get lineCount => lines.length;

  /// Mean per-line recognition confidence, or null when no line carries one
  /// (ML Kit reports confidence only on Android; iOS is null). Used as a
  /// tie-breaker between equally good parse candidates.
  double? get averageConfidence {
    double sum = 0;
    int count = 0;
    for (final OcrLine line in lines) {
      final double? confidence = line.confidence;
      if (confidence != null) {
        sum += confidence;
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }
}

/// One recognised line of text and its bounding box in image pixels.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Per-line ML Kit confidence (0.0–1.0). Null on iOS and for lines ML Kit
  /// does not score.
  final double? confidence;

  double get centerY => (top + bottom) / 2;

  @override
  String toString() => 'OcrLine("$text")';
}
