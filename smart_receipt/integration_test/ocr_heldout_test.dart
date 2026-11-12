// Held-out set: ten receipts the parser has never been tuned against.
//
//   bash tool/ocr_assets.sh run heldout
//
// The photos are CORD v2 validation-split receipts (CC-BY-4.0), drawn with
// `random.Random(42)` from the 54 validation receipts that carry at least two
// annotated menu items. None of them was inspected while fixing the parser, so
// this is the number to quote for generalisation.
//
// Two caveats that are not parser bugs:
//   * CORD receipts are restaurant/cafe receipts; the parser targets
//     Indonesian minimarket receipts, so layout and vocabulary differ.
//   * Item names are dataset annotations, kept verbatim. Some are annotation
//     artefacts — a discount line such as `Discount BCA 15%` is labelled as a
//     menu item — and the parser is right to drop it even though CER counts it.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ocr_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ten unseen receipts through ML Kit (held-out set)',
      (WidgetTester tester) async {
    await runReceiptSet(
      tester,
      label: 'HELD-OUT SET (10, unseen)',
      setName: 'heldout',
    );
  });
}
