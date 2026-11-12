// Held-out set D: the honest figure.
//
//   bash tool/ocr_assets.sh run heldout_d
//
// Sets A, B and C each revealed defects and were then used to fix them, so
// their numbers are no longer held out. This fourth draw from the remaining 24
// CORD validation receipts was measured **once**, with no tuning afterwards,
// and is the number to quote for generalisation.
//
// Same two caveats apply: CORD receipts are restaurant receipts while the
// parser targets Indonesian minimarkets, and item names are dataset
// annotations kept verbatim (including annotation artefacts).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ocr_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ten unseen receipts through ML Kit (held-out set D)',
      (WidgetTester tester) async {
    await runReceiptSet(
      tester,
      label: 'HELD-OUT SET D (10, measured once)',
      setName: 'heldout_d',
    );
  });
}
