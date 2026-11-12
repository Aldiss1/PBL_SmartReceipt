// Character and word error rates for OCR output.
//
// A percentage like "60.8% of item names found" hides how wrong the rest are:
// finding nine of ten items still loses a tenth of the money. CER and WER
// measure the actual distance between what was printed and what the pipeline
// produced, so a change can be shown to help instead of merely not hurting.
//
// The metric is deliberately plain Levenshtein over normalised text:
//
//   * case, punctuation and spacing are not errors (OCR casing is arbitrary),
//   * a dropped item costs all of its characters (deletions),
//   * a spurious item costs all of its characters (insertions),
//   * a misread character costs one substitution.
//
// That makes the number comparable across receipts of different length and
// across versions of the parser.
import 'dart:math' as math;

/// Edit counts between a reference and a hypothesis, plus the rate they imply.
class ErrorRate {
  const ErrorRate({required this.edits, required this.units});

  /// Substitutions + deletions + insertions.
  final int edits;

  /// Length of the reference, in characters or words.
  final int units;

  /// Error rate in percent, 0..100 (can exceed 100 when the hypothesis is
  /// much longer than the reference).
  double get percent => units == 0 ? 0 : edits * 100 / units;

  /// `100 - percent`, clamped to 0..100 so a runaway hypothesis reads as 0%
  /// accurate rather than a negative number.
  double get accuracy => (100 - percent).clamp(0, 100).toDouble();

  @override
  String toString() => '${percent.toStringAsFixed(1)}% ($edits/$units)';
}

/// Character and word error rates for the same reference/hypothesis pair.
class ItemNameErrorRates {
  const ItemNameErrorRates({required this.characters, required this.words});

  final ErrorRate characters;
  final ErrorRate words;

  @override
  String toString() =>
      'CER ${characters.percent.toStringAsFixed(1)}%  '
      'WER ${words.percent.toStringAsFixed(1)}%';
}

/// Levenshtein distance between [a] and [b].
///
/// Standard dynamic programme over two rolling rows, so memory is O(min(n, m))
/// even for a whole receipt.
int editDistance<T>(List<T> a, List<T> b) {
  if (a.isEmpty) {
    return b.length;
  }
  if (b.isEmpty) {
    return a.length;
  }
  // Iterate over the shorter side in the inner loop.
  final List<T> row = a.length <= b.length ? a : b;
  final List<T> col = a.length <= b.length ? b : a;

  List<int> previous = List<int>.generate(row.length + 1, (int i) => i);
  List<int> current = List<int>.filled(row.length + 1, 0);

  for (int j = 1; j <= col.length; j++) {
    current[0] = j;
    for (int i = 1; i <= row.length; i++) {
      final int substitution =
          previous[i - 1] + (row[i - 1] == col[j - 1] ? 0 : 1);
      final int deletion = previous[i] + 1;
      final int insertion = current[i - 1] + 1;
      current[i] = math.min(substitution, math.min(deletion, insertion));
    }
    final List<int> swap = previous;
    previous = current;
    current = swap;
  }
  return previous[row.length];
}

/// Lowercase letters and digits only — the form CER is computed on.
String normalizeForCharacterErrorRate(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Lowercase alphanumeric words — the form WER is computed on.
List<String> normalizeForWordErrorRate(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((String w) => w.isNotEmpty)
    .toList();

/// Character error rate between [reference] and [hypothesis].
ErrorRate characterErrorRate(String reference, String hypothesis) {
  final String ref = normalizeForCharacterErrorRate(reference);
  final String hyp = normalizeForCharacterErrorRate(hypothesis);
  return ErrorRate(
    edits: editDistance(ref.split(''), hyp.split('')),
    units: ref.length,
  );
}

/// Word error rate between [reference] and [hypothesis].
ErrorRate wordErrorRate(String reference, String hypothesis) {
  final List<String> ref = normalizeForWordErrorRate(reference);
  final List<String> hyp = normalizeForWordErrorRate(hypothesis);
  return ErrorRate(edits: editDistance(ref, hyp), units: ref.length);
}

/// Error rates for a whole list of item names, scored as one field.
///
/// Joining with a newline and scoring the concatenation is what makes a dropped
/// item count as deletions and an invented item count as insertions, without
/// needing to align names to each other first.
ItemNameErrorRates itemNameErrorRates(
  List<String> reference,
  List<String> hypothesis,
) {
  final String ref = reference.join('\n');
  final String hyp = hypothesis.join('\n');
  return ItemNameErrorRates(
    characters: characterErrorRate(ref, hyp),
    words: wordErrorRate(ref, hyp),
  );
}
