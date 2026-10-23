import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/widgets/receipt_photo_preview.dart';

void main() {
  late Directory tmp;
  late File image;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('photo_preview_');
    image = File('${tmp.path}/receipt.png');
    // A tiny valid PNG so Image.file has something decodable to work with.
    image.writeAsBytesSync(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('renders nothing when no photo was stored', (WidgetTester tester) async {
    await pump(
      tester,
      const ReceiptPhotoPreview(imagePath: null, heroTag: 't'),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders nothing when the file is gone', (WidgetTester tester) async {
    await pump(
      tester,
      ReceiptPhotoPreview(
        imagePath: '${tmp.path}/deleted.jpg',
        heroTag: 't',
      ),
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the photo and the enlarge hint', (WidgetTester tester) async {
    await pump(
      tester,
      ReceiptPhotoPreview(imagePath: image.path, heroTag: 't'),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Perbesar'), findsOneWidget);
  });

  testWidgets('tapping opens the zoomable full-screen viewer', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      ReceiptPhotoPreview(imagePath: image.path, heroTag: 't'),
    );

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
