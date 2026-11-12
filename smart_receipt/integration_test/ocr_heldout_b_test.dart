// Held-out set B: ten receipts that were still unseen after the fixes that
// set A (`ocr_heldout_test.dart`) revealed.
//
//   bash tool/ocr_assets.sh run heldout_b
//
// Set A was used to find four defects (restaurant tax lines, `CARD` payment
// lines, `SUB TOTAL` split by OCR, and the corrector turning `85G` into `856`).
// Once the parser was tuned against it, set A stopped being held out, so this
// second draw from the remaining 44 CORD validation receipts is the number to
// quote for generalisation.
//
// Same two caveats apply: CORD receipts are restaurant receipts while the
// parser targets Indonesian minimarkets, and item names are dataset
// annotations kept verbatim (including annotation artefacts).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ocr_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ten unseen receipts through ML Kit (held-out set B)',
      (WidgetTester tester) async {
    await runReceiptSet(
      tester,
      label: 'HELD-OUT SET B (10, unseen)',
      setName: 'heldout_b',
    );
  });
}
