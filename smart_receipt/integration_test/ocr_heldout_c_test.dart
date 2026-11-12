// Held-out set C: ten receipts that were still unseen after the vocabulary
// fixes that set B revealed.
//
//   bash tool/ocr_assets.sh run heldout_c
//
// Set B exposed four defects (`PB1` split by OCR, `Kartu` payment lines, a
// `TOTAL` that lost its last letter, and a `TOTA.` label), so it is no longer
// held out. This is a third draw from the remaining 34 CORD validation
// receipts and is the current honest figure.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ocr_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ten unseen receipts through ML Kit (held-out set C)',
      (WidgetTester tester) async {
    await runReceiptSet(
      tester,
      label: 'HELD-OUT SET C (10, unseen)',
      setName: 'heldout_c',
    );
  });
}
