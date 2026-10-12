import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/analysis.dart';
import 'package:smart_receipt/category_classification.dart';
import 'package:smart_receipt/empty_state.dart';
import 'package:smart_receipt/main.dart';
import 'package:smart_receipt/ocr_processing.dart';
import 'package:smart_receipt/review_transaction.dart';
import 'package:smart_receipt/sample_data.dart';
import 'package:smart_receipt/scan_receipt.dart';
import 'package:smart_receipt/settings.dart';
import 'package:smart_receipt/spending_prediction.dart';
import 'package:smart_receipt/transaction_detail.dart';
import 'package:smart_receipt/transaction_history.dart';
import 'package:smart_receipt/transaction_saved.dart';

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
    expect(find.text('Rp1.420.000'), findsOneWidget);
    expect(find.text('Pengeluaran per Kategori'), findsOneWidget);
    expect(find.text('Transaksi Terbaru'), findsOneWidget);
    expect(find.text('Indomaret'), findsOneWidget);
  });

  testWidgets('Every screen renders without exceptions', (
    WidgetTester tester,
  ) async {
    final List<Widget> screens = <Widget>[
      const ScanReceiptScreen(),
      const CategoryClassificationScreen(),
      const ReviewTransactionScreen(),
      const TransactionSavedScreen(),
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

  testWidgets('OCR processing advances to category classification', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: OcrProcessingScreen()));

    expect(find.text('Memproses OCR'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text('Klasifikasi Kategori'), findsOneWidget);
  });
}
