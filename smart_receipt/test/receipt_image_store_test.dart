import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/data/receipt_adapter.dart';
import 'package:smart_receipt/models/models.dart' as ui;
import 'package:smart_receipt/models/receipt_model.dart' as db;
import 'package:smart_receipt/services/receipt_image_store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('receipt_img_');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('ReceiptImageStore', () {
    test('copies a capture out of the temporary directory', () async {
      final File source = File('${tmp.path}/picked.jpg');
      await source.writeAsBytes(<int>[1, 2, 3, 4]);

      final Directory docs = Directory('${tmp.path}/docs');
      final String? stored = await ReceiptImageStore(
        directory: docs,
      ).persist(source.path);

      expect(stored, isNotNull);
      expect(File(stored!).existsSync(), isTrue);
      // It must be a copy in managed storage, not the original path.
      expect(stored, isNot(source.path));
      expect(stored, contains('receipt_images'));
      expect(await File(stored).readAsBytes(), <int>[1, 2, 3, 4]);
    });

    test('is idempotent for files already inside managed storage', () async {
      final Directory docs = Directory('${tmp.path}/docs');
      final ReceiptImageStore store = ReceiptImageStore(directory: docs);
      final File source = File('${tmp.path}/first.jpg');
      await source.writeAsBytes(<int>[9]);

      final String? first = await store.persist(source.path);
      final String? second = await store.persist(first);

      expect(second, first);
    });

    test('returns null when the capture no longer exists', () async {
      final String? stored = await ReceiptImageStore(
        directory: Directory('${tmp.path}/docs'),
      ).persist('${tmp.path}/missing.jpg');

      expect(stored, isNull);
    });

    test('returns null for an empty path', () async {
      expect(await ReceiptImageStore().persist(null), isNull);
      expect(await ReceiptImageStore().persist(''), isNull);
    });

    test('preserves a known image extension', () async {
      final File source = File('${tmp.path}/shot.png');
      await source.writeAsBytes(<int>[0]);

      final String? stored = await ReceiptImageStore(
        directory: Directory('${tmp.path}/docs'),
      ).persist(source.path);

      expect(stored, endsWith('.png'));
    });

    test('falls back to .jpg for unknown extensions', () async {
      final File source = File('${tmp.path}/shot.unknown');
      await source.writeAsBytes(<int>[0]);

      final String? stored = await ReceiptImageStore(
        directory: Directory('${tmp.path}/docs'),
      ).persist(source.path);

      expect(stored, endsWith('.jpg'));
    });

    test('remove deletes only files it manages', () async {
      final Directory docs = Directory('${tmp.path}/docs');
      final ReceiptImageStore store = ReceiptImageStore(directory: docs);
      final File source = File('${tmp.path}/keep.jpg');
      await source.writeAsBytes(<int>[7]);
      final String? stored = await store.persist(source.path);

      await store.remove(stored);
      expect(File(stored!).existsSync(), isFalse);

      // A path outside managed storage must survive.
      await store.remove(source.path);
      expect(source.existsSync(), isTrue);
    });

    test('exists reflects the file system', () async {
      final File f = File('${tmp.path}/x.jpg');
      expect(ReceiptImageStore.exists(f.path), isFalse);
      await f.writeAsBytes(<int>[1]);
      expect(ReceiptImageStore.exists(f.path), isTrue);
      expect(ReceiptImageStore.exists(null), isFalse);
    });
  });

  group('toUiTransaction', () {
    db.Receipt receipt({String? imagePath}) => db.Receipt(
      storeName: 'Indomaret',
      transactionDate: DateTime(2026, 10, 20),
      totalAmount: 15000,
      taxAmount: 0,
      subtotal: 15000,
      paymentMethod: 'Tunai',
      imagePath: imagePath,
      ocrText: 'INDOMIE',
      status: 'saved',
      createdAt: DateTime(2026, 10, 20),
      transactions: <db.Transaction>[
        db.Transaction(
          receiptId: 1,
          categoryId: 1,
          itemName: 'Indomie Goreng',
          quantity: 1,
          unitPrice: 15000,
          totalPrice: 15000,
          discount: 0,
          createdAt: DateTime(2026, 10, 20),
        ),
      ],
    );

    test('carries the receipt photo path through to the UI model', () {
      final ui.Transaction t = toUiTransaction(
        receipt(imagePath: '/docs/receipt_images/a.jpg'),
        (int id) => 'Makanan',
      );
      expect(t.imagePath, '/docs/receipt_images/a.jpg');
    });

    test('leaves imagePath null when the receipt has no photo', () {
      final ui.Transaction t = toUiTransaction(
        receipt(),
        (int id) => 'Makanan',
      );
      expect(t.imagePath, isNull);
    });
  });
}
