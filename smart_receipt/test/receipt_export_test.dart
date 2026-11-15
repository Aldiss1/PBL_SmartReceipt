import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/models/receipt_model.dart';
import 'package:smart_receipt/services/receipt_export_service.dart';

Receipt _receipt({
  int? id = 1,
  String store = 'Indomaret',
  DateTime? date,
  double total = 7000,
  String? paymentMethod = 'Tunai',
  List<Transaction> items = const <Transaction>[],
}) {
  final DateTime stamp = date ?? DateTime(2026, 9, 13, 19, 14);
  return Receipt(
    id: id,
    storeName: store,
    transactionDate: stamp,
    totalAmount: total,
    taxAmount: 0,
    subtotal: total,
    paymentMethod: paymentMethod,
    status: 'saved',
    createdAt: stamp,
    transactions: items,
  );
}

Transaction _item({
  String name = 'Indomie Goreng',
  int categoryId = 1,
  int qty = 2,
  double unitPrice = 3500,
}) {
  return Transaction(
    receiptId: 1,
    categoryId: categoryId,
    itemName: name,
    quantity: qty,
    unitPrice: unitPrice,
    totalPrice: qty * unitPrice,
    discount: 0,
    createdAt: DateTime(2026, 9, 13),
  );
}

String _categoryName(int id) => switch (id) {
      1 => 'Makanan',
      2 => 'Minuman',
      _ => 'Lainnya',
    };

/// Splits a CSV body into rows, honouring the quoting used by the service.
List<String> _rows(String csv) => csv
    .replaceFirst('\uFEFF', '')
    .split('\r\n')
    .where((String line) => line.isNotEmpty)
    .toList();

void main() {
  final ReceiptExportService service = ReceiptExportService();

  test('header carries a BOM and the documented column order', () {
    final String csv = service.buildCsv(<Receipt>[], _categoryName);

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(_rows(csv).single, ReceiptExportService.columns.join(','));
  });

  test('one row per item, with receipt totals repeated', () {
    final Receipt receipt = _receipt(
      total: 12500,
      items: <Transaction>[
        _item(name: 'Indomie Goreng', qty: 2, unitPrice: 3500),
        _item(name: 'Aqua 600ml', categoryId: 2, qty: 1, unitPrice: 5500),
      ],
    );

    final List<String> rows = _rows(service.buildCsv(<Receipt>[receipt], _categoryName));

    expect(rows, hasLength(3));
    expect(
      rows[1],
      '1,2026-09-13 19:14,Indomaret,Tunai,Indomie Goreng,Makanan,2,3500,7000,12500',
    );
    expect(
      rows[2],
      '1,2026-09-13 19:14,Indomaret,Tunai,Aqua 600ml,Minuman,1,5500,5500,12500',
    );
  });

  test('a receipt without items keeps its total', () {
    final List<String> rows = _rows(
      service.buildCsv(
        <Receipt>[_receipt(store: 'Toko Kosong', total: 15000)],
        _categoryName,
      ),
    );

    expect(rows[1], '1,2026-09-13 19:14,Toko Kosong,Tunai,,,,,0,15000');
  });

  test('fields with commas, quotes and newlines are escaped', () {
    final Receipt receipt = _receipt(
      store: 'Toko "A", Cabang B',
      items: <Transaction>[_item(name: 'Susu; Cokelat\n1L')],
    );

    final String row = _rows(service.buildCsv(<Receipt>[receipt], _categoryName))[1];

    expect(row.contains('"Toko ""A"", Cabang B"'), isTrue);
    expect(row.contains('"Susu; Cokelat\n1L"'), isTrue);
  });

  test('amounts are plain numbers, not formatted rupiah', () {
    final Receipt receipt = _receipt(
      total: 1420000,
      items: <Transaction>[_item(qty: 4, unitPrice: 355000)],
    );

    final String row = _rows(service.buildCsv(<Receipt>[receipt], _categoryName))[1];

    expect(row.contains('Rp'), isFalse);
    expect(row.contains('1420000'), isTrue);
    expect(row.contains('355000'), isTrue);
  });

  test('missing payment method falls back to Tunai', () {
    final List<String> rows = _rows(
      service.buildCsv(
        <Receipt>[_receipt(paymentMethod: null, items: <Transaction>[_item()])],
        _categoryName,
      ),
    );

    expect(rows[1].split(',')[3], 'Tunai');
  });

  test('writeCsv writes the same bytes it builds', () async {
    final Directory dir =
        Directory.systemTemp.createTempSync('smart_receipt_export_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final ReceiptExportService writer = ReceiptExportService()
      ..outputDirectory = dir;
    final Receipt receipt = _receipt(items: <Transaction>[_item()]);
    final DateTime now = DateTime(2026, 11, 16, 13, 45);

    final File file = await writer.writeCsv(
      <Receipt>[receipt],
      _categoryName,
      now: now,
    );

    expect(file.existsSync(), isTrue);
    expect(file.path.endsWith('transaksi-20261116-1345.csv'), isTrue);

    // Read bytes, not text: Dart's UTF-8 decoder strips a leading BOM, so
    // `readAsString` cannot prove the marker Excel needs is really there.
    final List<int> bytes = await file.readAsBytes();
    expect(bytes.take(3).toList(), <int>[0xEF, 0xBB, 0xBF]);
    expect(
      await file.readAsString(),
      writer
          .buildCsv(<Receipt>[receipt], _categoryName)
          .replaceFirst('\uFEFF', ''),
    );
  });
}
