import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/receipt_model.dart';

/// Builds a CSV of saved receipts for the user to take out of the app.
///
/// One row per line item rather than one row per receipt: a receipt-level table
/// cannot answer "how much did I spend on Minuman", which is the main reason to
/// export at all. Receipts with no items still get a single row so their total is
/// not silently dropped.
///
/// Deliberately free of platform calls so it can be unit-tested: [buildCsv] is
/// pure and [writeCsv] only touches the file system through [outputDirectory].
class ReceiptExportService {
  /// Overrides where the file is written. Defaults to the temp directory.
  ///
  /// A setter rather than a constructor argument, matching
  /// `CorrectionTrainingService.outputDirectory`, so tests can point the service
  /// at a throwaway folder.
  Directory? _outputDirectory;
  set outputDirectory(Directory directory) => _outputDirectory = directory;

  /// Column order is fixed so downstream spreadsheets keep working across
  /// versions; new columns must be appended, never inserted.
  static const List<String> columns = <String>[
    'ID Transaksi',
    'Tanggal',
    'Toko',
    'Metode Bayar',
    'Item',
    'Kategori',
    'Qty',
    'Harga Satuan',
    'Subtotal',
    'Total Struk',
  ];

  /// Renders [receipts] as CSV text.
  ///
  /// [categoryName] resolves a `categoryId` to its display name so the export
  /// matches the labels on screen instead of exposing raw ids.
  String buildCsv(
    List<Receipt> receipts,
    String Function(int categoryId) categoryName,
  ) {
    final StringBuffer buffer = StringBuffer();

    // Excel refuses UTF-8 unless the file starts with a BOM, which turns every
    // Indonesian item name into mojibake. The BOM is invisible to other tools.
    buffer.write('\uFEFF');
    buffer.write(columns.map(_escape).join(','));
    buffer.write('\r\n');

    for (final Receipt receipt in receipts) {
      final String id = receipt.id?.toString() ?? '';
      final String date = _csvDate(receipt.transactionDate);
      final String store = receipt.storeName;
      final String payment = receipt.paymentMethod ?? 'Tunai';
      final String receiptTotal = _amount(receipt.totalAmount);

      if (receipt.transactions.isEmpty) {
        buffer.write(<String>[
          id,
          date,
          store,
          payment,
          '',
          '',
          '',
          '',
          '0',
          receiptTotal,
        ].map(_escape).join(','));
        buffer.write('\r\n');
        continue;
      }

      for (final Transaction item in receipt.transactions) {
        buffer.write(<String>[
          id,
          date,
          store,
          payment,
          item.itemName,
          categoryName(item.categoryId),
          item.quantity.toString(),
          _amount(item.unitPrice),
          _amount(item.totalPrice),
          receiptTotal,
        ].map(_escape).join(','));
        buffer.write('\r\n');
      }
    }

    return buffer.toString();
  }

  /// Writes the CSV to disk and returns the file.
  ///
  /// The temp directory is right for a share-sheet handoff: the receiving app
  /// copies what it needs, and the OS reclaims the rest. [File] name carries a
  /// timestamp so repeated exports do not overwrite each other before sharing.
  Future<File> writeCsv(
    List<Receipt> receipts,
    String Function(int categoryId) categoryName, {
    DateTime? now,
  }) async {
    final Directory dir =
        _outputDirectory ??= await getTemporaryDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final File file = File('${dir.path}${Platform.pathSeparator}${fileName(now)}');
    await file.writeAsString(
      buildCsv(receipts, categoryName),
      flush: true,
    );
    return file;
  }

  /// e.g. `transaksi-20261116-1345.csv`.
  static String fileName(DateTime? now) {
    final DateTime stamp = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'transaksi-${stamp.year}${two(stamp.month)}${two(stamp.day)}'
        '-${two(stamp.hour)}${two(stamp.minute)}.csv';
  }

  /// `2026-09-13 19:14`, sortable and unambiguous across locales.
  ///
  /// The on-screen `formatDateTime` is Indonesian prose ("13 Sep 2026 • 19:14")
  /// which spreadsheets read as text, so exports use ISO instead.
  static String _csvDate(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  /// Whole rupiah, no separators: `12500`, not `Rp12.500`, so spreadsheets treat
  /// the column as numbers. The app never stores fractional amounts.
  static String _amount(double value) => value.round().toString();

  /// Quotes a field when it would otherwise break the row.
  ///
  /// Store names routinely contain commas ("Toko A, Cabang B") and the app also
  /// runs on an Indonesian locale where `;` is the list separator, so both are
  /// quoted along with quotes and line breaks. Quoting is the only correct
  /// escape in CSV: doubling the inner quote is the RFC 4180 rule.
  static String _escape(String field) {
    final bool needsQuotes = field.contains(',') ||
        field.contains(';') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r') ||
        field.trim() != field;
    if (!needsQuotes) {
      return field;
    }
    return '"${field.replaceAll('"', '""')}"';
  }
}
