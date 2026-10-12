import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/screens/analysis.dart';
import 'package:smart_receipt/screens/category_classification.dart';
import 'package:smart_receipt/screens/empty_state.dart';
import 'package:smart_receipt/main.dart';
import 'package:smart_receipt/data/sample_data.dart';
import 'package:smart_receipt/models/models.dart';
import 'package:smart_receipt/ocr/image_quality.dart';
import 'package:smart_receipt/ocr/ocr_raw_text.dart';
import 'package:smart_receipt/ocr/ocr_service.dart';
import 'package:smart_receipt/ocr/receipt_classifier.dart';
import 'package:smart_receipt/ocr/receipt_parser.dart';
import 'package:smart_receipt/screens/review_transaction.dart';
import 'package:smart_receipt/screens/scan_receipt.dart';
import 'package:smart_receipt/screens/settings.dart';
import 'package:smart_receipt/screens/spending_prediction.dart';
import 'package:smart_receipt/screens/transaction_detail.dart';
import 'package:smart_receipt/screens/transaction_history.dart';
import 'package:smart_receipt/screens/transaction_saved.dart';

/// Builds a deterministic OCR result so downstream screens can render without a
/// camera or the native OCR engine.
OcrScanResult _fakeScan() {
  return OcrScanResult(
    sourcePath: '/nonexistent/receipt.jpg',
    quality: const ImageQualityReport(
      brightness: 180,
      blurScore: 120,
      rotationDegrees: 0,
      width: 1000,
      height: 1400,
      preparedPath: '/nonexistent/prepared.jpg',
    ),
    raw: const OcrRawResult(
      fullText: 'INDOMARET\nINDOMIE GORENG 2 x 3.500 7.000\nTOTAL 7.000',
      lines: <OcrLine>[
        OcrLine(text: 'INDOMARET', left: 0, top: 0, right: 100, bottom: 20),
        OcrLine(
          text: 'INDOMIE GORENG 2 x 3.500 7.000',
          left: 0,
          top: 30,
          right: 200,
          bottom: 50,
        ),
      ],
    ),
    parsed: ParsedReceipt(
      store: 'Indomaret',
      date: DateTime(2026, 9, 13, 19, 14),
      items: <ParsedItem>[
        ParsedItem(name: 'Indomie Goreng', qty: 2, price: 3500),
      ],
      total: 7000,
      paymentMethod: 'Tunai',
    ),
  );
}

void main() {
  testWidgets('Splash appears then navigates to the home dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmartReceiptApp());

    expect(find.text('ANALYZER'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Beranda'), findsWidgets);
    expect(find.text('Selamat datang, Rian'), findsOneWidget);
  });

  testWidgets('OCR downstream screens render without exceptions', (
    WidgetTester tester,
  ) async {
    final OcrScanResult scan = _fakeScan();
    final List<ItemPrediction> predictions =
        ReceiptClassifier().classifyAll(<String>['Indomie Goreng']);

    final List<Widget> screens = <Widget>[
      const ScanReceiptScreen(),
      CategoryClassificationScreen(scan: scan),
      ReviewTransactionScreen(scan: scan, predictions: predictions),
      TransactionSavedScreen(
        store: 'Indomaret',
        date: DateTime(2026, 9, 13),
        items: <TransactionItem>[
          const TransactionItem(
            name: 'Indomie Goreng',
            qty: 2,
            price: 3500,
            category: 'Makanan',
          ),
        ],
      ),
      const TransactionHistoryScreen(),
      TransactionDetailScreen(transaction: kSampleTransactions.first),
      const AnalysisScreen(),
      const SpendingPredictionScreen(),
      const EmptyStateScreen(),
      const SettingsScreen(),
    ];

    for (final Widget screen in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Failed to render ${screen.runtimeType}',
      );
    }
  });

  test('Receipt parser extracts items, store and total from OCR text', () {
    const OcrRawResult raw = OcrRawResult(
      fullText: 'INDOMARET\n13/09/2026 19:14\n'
          'INDOMIE GORENG 2 x 3.500 7.000\nAQUA 600ML 1 x 4.000 4.000\n'
          'TOTAL 11.000\nTUNAI 20.000',
      lines: <OcrLine>[
        OcrLine(text: 'INDOMARET', left: 0, top: 0, right: 100, bottom: 20),
        OcrLine(text: '13/09/2026 19:14', left: 0, top: 25, right: 150, bottom: 45),
        OcrLine(
          text: 'INDOMIE GORENG 2 x 3.500 7.000',
          left: 0,
          top: 50,
          right: 250,
          bottom: 70,
        ),
        OcrLine(
          text: 'AQUA 600ML 1 x 4.000 4.000',
          left: 0,
          top: 75,
          right: 250,
          bottom: 95,
        ),
        OcrLine(text: 'TOTAL 11.000', left: 0, top: 100, right: 120, bottom: 120),
        OcrLine(text: 'TUNAI 20.000', left: 0, top: 125, right: 120, bottom: 145),
      ],
    );

    final ParsedReceipt parsed = ReceiptParser().parse(raw);

    expect(parsed.store, 'Indomaret');
    expect(parsed.total, 11000);
    expect(parsed.items.length, 2);
    // Item names keep the receipt's original casing.
    expect(parsed.items.first.name, 'INDOMIE GORENG');
    expect(parsed.items.first.qty, 2);
    expect(parsed.items.first.price, 3500);
    expect(parsed.date?.year, 2026);
    expect(parsed.date?.month, 9);
    expect(parsed.date?.day, 13);
    expect(parsed.paymentMethod, 'Tunai');
  });

  test('parser ignores change/NPWP lines and reads the real date', () {
    const OcrRawResult raw = OcrRawResult(
      fullText: 'INDOMARET\n'
          'NPWP: 01.234.567.8-901.000\n'
          '13/09/2026  19:14:32\n'
          'INDOMIE GORENG   2 x 3.500  7.000\n'
          'TOTAL 7.000\n'
          'TUNAI 100.000\n'
          'KEMBALI 93.000',
      lines: <OcrLine>[
        OcrLine(text: 'INDOMARET', left: 0, top: 0, right: 100, bottom: 20),
        OcrLine(
          text: 'NPWP: 01.234.567.8-901.000',
          left: 0,
          top: 25,
          right: 260,
          bottom: 45,
        ),
        OcrLine(
          text: '13/09/2026  19:14:32',
          left: 0,
          top: 50,
          right: 200,
          bottom: 70,
        ),
        OcrLine(
          text: 'INDOMIE GORENG   2 x 3.500  7.000',
          left: 0,
          top: 75,
          right: 300,
          bottom: 95,
        ),
        OcrLine(text: 'TOTAL 7.000', left: 0, top: 100, right: 120, bottom: 120),
        OcrLine(text: 'TUNAI 100.000', left: 0, top: 125, right: 140, bottom: 145),
        OcrLine(text: 'KEMBALI 93.000', left: 0, top: 150, right: 150, bottom: 170),
      ],
    );

    final ParsedReceipt parsed = ReceiptParser().parse(raw);

    // The NPWP line must not poison the date.
    expect(parsed.date?.year, 2026);
    expect(parsed.date?.month, 9);
    expect(parsed.date?.day, 13);
    // "KEMBALI" (change) must not become a purchased item.
    expect(parsed.items.length, 1);
    expect(parsed.items.single.name, 'INDOMIE GORENG');
    expect(parsed.total, 7000);
  });

  test('parser rebuilds column-split ML Kit rows into items', () {
    // Verbatim output captured from Google ML Kit on a real device: the
    // recognizer emits price/qty lines separately from the product name.
    const List<String> deviceLines = <String>[
      'INDOMARET',
      'Jl. Sudirman No. 12, Jakarta',
      'NPWP: 01.234.567.8-901.000',
      '13/09/ 2026 19:14:32',
      'No: 0123',
      'Kasir: RINA',
      '7.000',
      '2 x 3.500',
      'INDOMIE GORENG',
      '4.000',
      '1 X 4.000',
      'AQUA 60OML',
      '5.500',
      '1 x 5.500',
      'SABUN LIFEBUOY',
      '2 X 12.000 24.000',
      'TISSUE PASEO',
      '5.000',
      '1 x 5.000',
      'TEH BOTOL SOSRO',
      '1 x 14.000 14.000',
      'ROTI TAWAR',
      '59.500',
      'SUBTOTAL',
      '100.000',
      'TUNAI',
      '40.500',
      'KEMBALI',
    ];
    final OcrRawResult raw = OcrRawResult(
      fullText: deviceLines.join('\n'),
      lines: <OcrLine>[
        for (int i = 0; i < deviceLines.length; i++)
          OcrLine(
            text: deviceLines[i],
            left: 0,
            top: i * 30.0,
            right: 200,
            bottom: i * 30.0 + 20,
          ),
      ],
    );

    final ParsedReceipt parsed = ReceiptParser().parse(raw);

    expect(parsed.store, 'Indomaret');
    expect(parsed.total, 59500);
    // Six real products must be recovered despite the column split.
    final List<String> names =
        parsed.items.map((ParsedItem i) => i.name).toList();
    expect(names.any((String n) => n.contains('INDOMIE')), isTrue);
    expect(names.any((String n) => n.contains('AQUA')), isTrue);
    expect(names.any((String n) => n.contains('LIFEBUOY')), isTrue);
    expect(names.any((String n) => n.contains('PASEO')), isTrue);
    expect(names.any((String n) => n.contains('SOSRO')), isTrue);
    expect(names.any((String n) => n.contains('ROTI')), isTrue);
    // Change/total lines must not appear as items.
    expect(names.any((String n) => n.contains('KEMBALI')), isFalse);
    expect(names.any((String n) => n.contains('SUBTOTAL')), isFalse);
    expect(names.any((String n) => n.contains('TUNAI')), isFalse);
    // Date must survive the NPWP line.
    expect(parsed.date?.day, 13);
    expect(parsed.date?.month, 9);
  });
}
