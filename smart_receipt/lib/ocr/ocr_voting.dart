import 'dart:math' as math;

import 'ocr_raw_text.dart';

/// Amount voting across OCR variants and the candidate comparison used by the
/// retry pipeline. Pure functions over [OcrRawResult] only: no plugin types,
/// no parser, no image access — so the voting rules are unit-testable without
/// a device.
///
/// Invariant: item names are never touched. Only the trailing amount of a
/// line may be replaced, and only when the vote is unambiguous enough
/// (two or more same-resolution variants agree on the digits).

/// True when [candidate] should replace the best reading so far: a strictly
/// higher parse score, or — only when the scores are exactly equal — a
/// strictly higher average recognition confidence.
///
/// A null confidence never wins a tie. ML Kit reports confidence on Android
/// but not on iOS, so on iOS (or for lines it does not score) the historical
/// ordering is preserved instead of introducing a platform-dependent bias.
bool candidateBeats({
  required int candidateScore,
  required double? candidateConfidence,
  required int bestScore,
  required double? bestConfidence,
}) {
  if (candidateScore != bestScore) {
    return candidateScore > bestScore;
  }
  if (candidateConfidence == null || bestConfidence == null) {
    return false;
  }
  return candidateConfidence > bestConfidence;
}

/// The combined reading: [primary] with the amounts confirmed by the vote.
///
/// A digit a single pass drops or misreads on a faded receipt is often read
/// correctly by sibling variants of the same image. For every line of
/// [primary] that ends in an amount, the variant lines that sit in the same
/// place (bounding-box IoU >= 0.6) are consulted. When two or more readings
/// agree on the digits, that value wins; when the primary reading is part of
/// the agreement, its exact spelling is kept. Lines without a trailing amount
/// are left untouched, and a variant without a matching line casts no vote.
///
/// The result reuses the primary's geometry and line order; only replaced
/// lines are copied.
OcrRawResult combineAmountVotes(OcrRawResult primary, List<OcrRawResult> variants) {
  final List<OcrLine> lines = <OcrLine>[];
  for (final OcrLine line in primary.lines) {
    final RegExpMatch? amount = _trailingAmountMatch(line.text);
    if (amount == null) {
      lines.add(line);
      continue;
    }
    final String? replacement = _votedAmount(line, amount, variants);
    if (replacement == null || replacement == amount.group(0)) {
      lines.add(line);
    } else {
      lines.add(_copyLine(
        line,
        line.text.substring(0, amount.start) +
            replacement +
            line.text.substring(amount.end),
      ));
    }
  }
  return OcrRawResult(
    lines: lines,
    fullText: lines.map((OcrLine line) => line.text).join('\n'),
  );
}

/// The amount [line] should carry after the vote, or null when the vote
/// confirms the current reading (or finds no consensus to change it).
String? _votedAmount(
  OcrLine line,
  RegExpMatch current,
  List<OcrRawResult> variants,
) {
  final String currentMatch = current.group(0)!;
  final String currentValue = _amountValue(currentMatch);

  // Readings in vote order: the primary first, then each variant in list
  // order. A variant with no paired line (or a line without a trailing
  // amount) contributes null — "no reading", not a mismatching one.
  final List<String?> readings = <String?>[currentMatch];
  for (final OcrRawResult variant in variants) {
    final OcrLine? paired = _pairedLine(line, variant.lines);
    readings.add(_trailingAmountMatch(paired?.text ?? '')?.group(0));
  }

  final Map<String, int> valueCounts = <String, int>{};
  for (final String? reading in readings) {
    if (reading == null) {
      continue;
    }
    final String value = _amountValue(reading);
    valueCounts[value] = (valueCounts[value] ?? 0) + 1;
  }

  // The primary is part of a majority: keep its exact spelling.
  if ((valueCounts[currentValue] ?? 0) >= 2) {
    return null;
  }
  // Otherwise the first variant (in list order) whose value has a majority
  // supplies the replacement string, in that variant's exact spelling.
  for (final String? reading in readings.skip(1)) {
    if (reading == null) {
      continue;
    }
    final String value = _amountValue(reading);
    if (value != currentValue && (valueCounts[value] ?? 0) >= 2) {
      return reading;
    }
  }
  return null;
}

final RegExp _amountPattern = RegExp(r'\d[\d.,]*');

/// The trailing amount of a receipt line, or null when the line does not end
/// in one. The match must reach the end of the right-trimmed text, so a
/// package size like "85G" (match "85" stops before the "G") is not mistaken
/// for money.
RegExpMatch? _trailingAmountMatch(String text) {
  final String trimmed = text.trimRight();
  for (final RegExpMatch match in _amountPattern.allMatches(trimmed)) {
    if (match.end == trimmed.length) {
      return match;
    }
  }
  return null;
}

/// The digit-only value of an amount spelling, so "154.000", "154,000" and
/// "154000" compare equal.
String _amountValue(String amountMatch) =>
    amountMatch.replaceAll(RegExp(r'[^0-9]'), '');

/// The line of [candidates] that sits closest to [line] with bounding-box
/// IoU >= 0.6, or null when nothing is close enough to be the same line.
OcrLine? _pairedLine(OcrLine line, List<OcrLine> candidates) {
  OcrLine? best;
  double bestIou = 0;
  for (final OcrLine candidate in candidates) {
    final double iou = _iou(line, candidate);
    if (iou >= 0.6 && iou > bestIou) {
      best = candidate;
      bestIou = iou;
    }
  }
  return best;
}

double _iou(OcrLine a, OcrLine b) {
  final double width = math.min(a.right, b.right) - math.max(a.left, b.left);
  final double height = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (width <= 0 || height <= 0) {
    return 0;
  }
  final double intersection = width * height;
  final double areaA = (a.right - a.left) * (a.bottom - a.top);
  final double areaB = (b.right - b.left) * (b.bottom - b.top);
  return intersection / (areaA + areaB - intersection);
}

OcrLine _copyLine(OcrLine line, String text) => OcrLine(
      text: text,
      left: line.left,
      top: line.top,
      right: line.right,
      bottom: line.bottom,
      confidence: line.confidence,
    );
