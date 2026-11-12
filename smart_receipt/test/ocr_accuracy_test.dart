import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/ocr/ocr_accuracy.dart';

void main() {
  group('editDistance', () {
    test('identical sequences need no edits', () {
      expect(editDistance('abc'.split(''), 'abc'.split('')), 0);
    });

    test('one substitution costs one edit', () {
      expect(editDistance('abc'.split(''), 'abd'.split('')), 1);
    });

    test('deletion and insertion are counted', () {
      expect(editDistance('abc'.split(''), 'ab'.split('')), 1);
      expect(editDistance('ab'.split(''), 'abc'.split('')), 1);
    });

    test('an empty side costs the whole other side', () {
      expect(editDistance(<String>[], 'abcd'.split('')), 4);
      expect(editDistance('abcd'.split(''), <String>[]), 4);
    });

    test('a transposition costs two edits, not one', () {
      // Plain Levenshtein has no transposition operation; documenting it here
      // keeps the number in the report interpretable.
      expect(editDistance('ab'.split(''), 'ba'.split('')), 2);
    });
  });

  group('characterErrorRate', () {
    test('identical text is 0%', () {
      final ErrorRate r = characterErrorRate('SABUN 85G', 'SABUN 85G');

      expect(r.edits, 0);
      expect(r.percent, 0);
      expect(r.accuracy, 100);
    });

    test('one wrong character in eight is 12.5%', () {
      // `85G` read as `856`: the unit suffix is the only difference.
      final ErrorRate r = characterErrorRate('SABUN 85G', 'SABUN 856');

      expect(r.units, 8);
      expect(r.edits, 1);
      expect(r.percent, closeTo(12.5, 1e-9));
    });

    test('punctuation and case are not counted as errors', () {
      final ErrorRate r =
          characterErrorRate('Sabun Lifebuoy 85G', 'SABUN LIFEBUOY 85G');

      expect(r.edits, 0);
    });

    test('a missing item costs all of its characters', () {
      // `aqua600ml` is nine characters.
      final ErrorRate r = characterErrorRate('AQUA 600ML', '');

      expect(r.edits, 9);
      expect(r.percent, 100);
    });

    test('an extra item is counted as insertions', () {
      final ErrorRate r = characterErrorRate('AQUA 600ML', 'AQUA 600ML TISU');

      expect(r.edits, 4);
      expect(r.units, 9);
    });

    test('an empty reference is guarded instead of dividing by zero', () {
      final ErrorRate r = characterErrorRate('', '');

      expect(r.percent, 0);
    });
  });

  group('wordErrorRate', () {
    test('one wrong word in four is 25%', () {
      final ErrorRate r =
          wordErrorRate('KOPI KAPAL API 65G', 'KOPI KAPAL API 656');

      expect(r.units, 4);
      expect(r.edits, 1);
      expect(r.percent, closeTo(25, 1e-9));
    });

    test('a character error inside a word costs one word', () {
      final ErrorRate r = wordErrorRate('TISSUE PASEO 250S', 'TISSUE PASEO 2505');

      expect(r.edits, 1);
      expect(r.units, 3);
    });

    test('extra whitespace does not create words', () {
      final ErrorRate r = wordErrorRate('AQUA  600ML', 'AQUA 600ML');

      expect(r.edits, 0);
    });
  });

  group('itemNameErrorRates', () {
    test('scores the whole item list as one field', () {
      final ItemNameErrorRates r = itemNameErrorRates(
        <String>['SABUN 85G', 'AQUA 600ML'],
        <String>['SABUN 856', 'AQUA 600ML'],
      );

      expect(r.characters.edits, 1);
      expect(r.words.edits, 1);
      expect(r.characters.units, greaterThan(15));
    });

    test('a dropped item shows up as deletions', () {
      final ItemNameErrorRates r = itemNameErrorRates(
        <String>['SABUN 85G', 'AQUA 600ML'],
        <String>['SABUN 85G'],
      );

      // `sabun85gaqua600ml` is 17 characters; the hypothesis keeps 8.
      expect(r.characters.edits, 9);
      expect(r.words.edits, 2);
    });
  });
}
