import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_receipt/models/receipt_model.dart';
import 'package:smart_receipt/providers/receipt_provider.dart';
import 'package:smart_receipt/screens/transaction_history.dart';
import 'package:smart_receipt/services/receipt_export_service.dart';
import 'package:smart_receipt/services/receipt_image_store.dart';

import 'support/fake_receipt_database.dart';

/// Fails before touching any platform channel, so the screen's error path can be
/// asserted without a share sheet.
class _FailingExportService extends ReceiptExportService {
  @override
  Future<File> writeCsv(
    List<Receipt> receipts,
    String Function(int categoryId) categoryName, {
    DateTime? now,
  }) async {
    throw const FileSystemException('penyimpanan tidak tersedia');
  }
}

void main() {
  late FakeReceiptDatabase helper;
  late ReceiptProvider provider;

  setUp(() {
    helper = FakeReceiptDatabase();
    provider = ReceiptProvider(
      dbHelper: helper,
      imageStore: ReceiptImageStore(),
    );
  });

  Future<void> pumpHistory(
    WidgetTester tester, {
    ReceiptExportService? exporter,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ReceiptProvider>.value(
        value: provider,
        child: MaterialApp(
          home: TransactionHistoryScreen(exporter: exporter),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('export action is hidden while there is nothing to export', (
    WidgetTester tester,
  ) async {
    await provider.loadData();
    await pumpHistory(tester);

    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('export action appears once a receipt is saved', (
    WidgetTester tester,
  ) async {
    await provider.addReceipt(sampleReceipt());
    await pumpHistory(tester);

    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });

  testWidgets('a failing export surfaces an error instead of crashing', (
    WidgetTester tester,
  ) async {
    await provider.addReceipt(sampleReceipt());
    await pumpHistory(tester, exporter: _FailingExportService());

    // The writer throws before any platform channel is reached, standing in for
    // a full disk. The screen must report it and stay usable.
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(find.textContaining('Gagal mengekspor transaksi'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });
}
