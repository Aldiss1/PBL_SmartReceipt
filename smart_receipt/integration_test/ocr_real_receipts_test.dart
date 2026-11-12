// Development set: ten receipts used while tuning the parser.
//
//   bash tool/ocr_assets.sh run dev
//
// Receipts 1-3 are photographs of Indonesian minimarket receipts with
// hand-checked ground truth. Receipts 4-10 come from CORD v2 (CC-BY-4.0) and
// their expected item names are the dataset annotations, not a human audit.
//
// Numbers from this set are optimistic by construction — the parser was fixed
// against these photos. For the honest figure, run `ocr_heldout_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'ocr_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ten receipts through ML Kit (development set)',
      (WidgetTester tester) async {
    await runReceiptSet(
      tester,
      label: 'DEVELOPMENT SET (10)',
      setName: 'dev',
    );
  });
}
