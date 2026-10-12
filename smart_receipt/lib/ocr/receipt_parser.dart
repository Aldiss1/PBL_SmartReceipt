import 'ocr_raw_text.dart';

/// Structured data extracted from raw OCR text of an Indonesian receipt.
class ParsedReceipt {
  ParsedReceipt({
    required this.store,
    required this.date,
    required this.items,
    required this.total,
    required this.paymentMethod,
  });

  final String store;
  final DateTime? date;
  final List<ParsedItem> items;
  final int total;
  final String paymentMethod;

  bool get isEmpty => items.isEmpty && total == 0;
}

class ParsedItem {
  ParsedItem({required this.name, required this.qty, required this.price});

  final String name;
  final int qty;
  final int price;

  int get subtotal => qty * price;
}

class _DateParts {
  const _DateParts({required this.year, required this.month, required this.day});

  final int year;
  final int month;
  final int day;
}

/// Parses receipt text. Handles common Indonesian receipt shapes:
///
/// ```
/// INDOMARET
/// Jl. Sudirman No. 12
/// 13/09/2026 19:14
/// INDOMIE GORENG 2 x 3.500  7.000
/// AQUA 600ML 1 x 4.000      4.000
/// TOTAL                     11.000
/// TUNAI                     20.000
/// ```
class ReceiptParser {
  static final RegExp _datePattern = RegExp(
    r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})',
  );

  static final RegExp _timePattern = RegExp(r'(\d{1,2})[:.](\d{2})');

  /// A trailing rupiah amount, e.g. "Rp 11.000", "11.000", "11,000".
  static final RegExp _trailingAmount = RegExp(
    r'(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+)\s*$',
    caseSensitive: false,
  );

  static final RegExp _qtyTimes = RegExp(
    r'(\d+)\s*[xX*]\s*(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d+)',
  );

  /// Words that mark a line as a total/summary rather than a purchased item.
  static final RegExp _totalWords = RegExp(
    r'\b(total|grand\s*total|jumlah|sub\s*total|subtotal|tagihan|bayar)\b',
    caseSensitive: false,
  );

  static final RegExp _paymentWords = RegExp(
    r'\b(tunai|cash|debit|kredit|qris|gopay|ovo|dana|shopeepay|bca|mandiri|bri|bni)\b',
    caseSensitive: false,
  );

  static final RegExp _storeNoise = RegExp(
    r'\b(struk|nota|invoice|kwitansi|npwp|telp|tel|jl\.?|jalan|no\.?|kasir|npk|tanggal|jam|waktu)\b',
    caseSensitive: false,
  );

  /// Lines that carry a summary amount rather than a purchased product:
  /// change, cash tendered, tax, discounts, loyalty points, etc.
  static final RegExp _nonItemWords = RegExp(
    r'\b(kembali|kembalian|change|tunai|cash|debit|kredit|qris|gopay|ovo|dana|'
    r'shopeepay|ppn|pajak|tax|diskon|discount|potongan|hemat|voucher|poin|point|'
    r'saldo|sisa|bayar|pembayaran|total|subtotal|sub\s*total|jumlah|tagihan|'
    r'grand\s*total|terima\s*kasih|terimakasih|npwp)\b',
    caseSensitive: false,
  );

  /// Bare numbers / phone numbers that should never be a store name.
  static final RegExp _nonStoreLine = RegExp(r'^[\d\s\-+().,:]+$');

  ParsedReceipt parse(OcrRawResult raw) {
    final List<String> lines = raw.lines.map((OcrLine l) => l.text).toList();

    final String store = _extractStore(lines);
    final DateTime? date = _extractDate(raw.fullText);
    final String payment = _extractPayment(lines);

    final int? explicitTotal = _extractTotal(lines);

    // ML Kit frequently splits a receipt's columns onto separate lines
    // ("7.000", "2 x 3.500", "INDOMIE GORENG"). Rebuild logical item rows
    // first, then parse those.
    final List<String> rowLines = _reconstructItemRows(lines);

    final List<ParsedItem> items = <ParsedItem>[];
    for (final String line in rowLines) {
      final ParsedItem? item = _parseItemLine(line);
      if (item != null) {
        items.add(item);
      }
    }

    final int computedTotal = items.fold(0, (int s, ParsedItem i) => s + i.subtotal);
    final int total = explicitTotal ?? computedTotal;

    return ParsedReceipt(
      store: store,
      date: date,
      items: items,
      total: total,
      paymentMethod: payment,
    );
  }

  /// A line that is only a quantity×unit price, e.g. "2 x 3.500" or "2 X 4.000".
  static final RegExp _pureQtyLine = RegExp(
    r'^\s*(?:rp\.?\s*)?(\d{1,3})\s*[xX*]\s*(?:rp\.?\s*)?([\d.,]+)\s*$',
  );

  /// A quantity×unit line that also carries the line total, e.g.
  /// "2 X 12.000 24.000".
  static final RegExp _qtyWithTotal = RegExp(
    r'^\s*(?:rp\.?\s*)?(\d{1,3})\s*[xX*]\s*(?:rp\.?\s*)?([\d.,]+)\s+([\d.,]+)\s*$',
  );

  /// A line that is only an amount, e.g. "7.000" or "Rp 7.000".
  static final RegExp _pureAmountLine = RegExp(
    r'^\s*(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+|\d{3,})\s*$',
    caseSensitive: false,
  );

  /// A line that looks like a product name: has letters and no trailing bare
  /// amount (those are handled by [_parseItemLine] directly).
  bool _looksLikeName(String line) {
    final String t = line.trim();
    if (t.length < 2) {
      return false;
    }
    if (_nonItemWords.hasMatch(t) || _totalWords.hasMatch(t)) {
      return false;
    }
    if (_datePattern.hasMatch(t)) {
      return false;
    }
    // Needs a reasonable amount of letters.
    return t.replaceAll(RegExp(r'[^A-Za-z]'), '').length >= 2;
  }

  /// Rebuilds item rows from column-split OCR output.
  ///
  /// ML Kit renders a receipt table column-by-column, so a single product often
  /// arrives as three lines:
  ///
  /// ```
  /// 7.000            <- line total
  /// 2 x 3.500        <- qty × unit
  /// INDOMIE GORENG   <- product name
  /// ```
  ///
  /// (or `2 X 12.000 24.000` combining qty, unit and total). This anchors on
  /// the name line, pulls the immediately preceding numeric lines into one
  /// logical row, and marks them consumed so nothing is double-counted.
  List<String> _reconstructItemRows(List<String> lines) {
    final List<String> src = lines.map((String l) => l.trim()).toList();
    final List<bool> consumed = List<bool>.filled(src.length, false);
    final List<String> out = <String>[];

    for (int i = 0; i < src.length; i++) {
      if (consumed[i] || src[i].isEmpty) {
        continue;
      }
      final String line = src[i];

      if (_looksLikeName(line)) {
        String? qtyPart;
        String? amountPart;

        // Look backwards up to two lines for the numeric columns.
        for (int j = i - 1; j >= 0 && j >= i - 2; j--) {
          if (consumed[j] || src[j].isEmpty) {
            continue;
          }
          final String prev = src[j];
          final RegExpMatch? qt = _qtyWithTotal.firstMatch(prev);
          if (qt != null) {
            qtyPart = '${qt.group(1)} x ${qt.group(2)}';
            amountPart ??= qt.group(3);
            consumed[j] = true;
            continue;
          }
          final RegExpMatch? q = _pureQtyLine.firstMatch(prev);
          if (q != null) {
            qtyPart ??= '${q.group(1)} x ${q.group(2)}';
            consumed[j] = true;
            continue;
          }
          final RegExpMatch? a = _pureAmountLine.firstMatch(prev);
          if (a != null) {
            amountPart ??= a.group(1);
            consumed[j] = true;
            continue;
          }
          break;
        }

        // If nothing preceded the name, look ahead for name-then-numbers.
        if (qtyPart == null && amountPart == null) {
          for (int j = i + 1; j < src.length && j <= i + 2; j++) {
            if (consumed[j] || src[j].isEmpty) {
              continue;
            }
            final String next = src[j];
            final RegExpMatch? qt = _qtyWithTotal.firstMatch(next);
            if (qt != null) {
              qtyPart = '${qt.group(1)} x ${qt.group(2)}';
              amountPart ??= qt.group(3);
              consumed[j] = true;
              break;
            }
            final RegExpMatch? q = _pureQtyLine.firstMatch(next);
            if (q != null) {
              qtyPart = '${q.group(1)} x ${q.group(2)}';
              consumed[j] = true;
              break;
            }
            break;
          }
        }

        final StringBuffer merged = StringBuffer(line);
        if (qtyPart != null) {
          merged.write(' $qtyPart');
        }
        if (amountPart != null) {
          merged.write(' $amountPart');
        }
        out.add(merged.toString());
        consumed[i] = true;
        continue;
      }

      out.add(line);
    }
    return out;
  }

  /// Store name: usually the first prominent, mostly-alphabetic line that is
  /// not a header/date/phone line and has no trailing price.
  String _extractStore(List<String> lines) {
    for (final String line in lines.take(6)) {
      final String t = line.trim();
      if (t.length < 3 || t.length > 40) {
        continue;
      }
      if (_nonStoreLine.hasMatch(t)) {
        continue;
      }
      if (_datePattern.hasMatch(t)) {
        continue;
      }
      if (_storeNoise.hasMatch(t)) {
        continue;
      }
      if (_paymentWords.hasMatch(t)) {
        continue;
      }
      // Reject lines that are mostly a price.
      if (_trailingAmount.firstMatch(t) != null && _digitRatio(t) > 0.4) {
        continue;
      }
      final String letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length >= 3) {
        return _titleCase(t);
      }
    }
    return 'Struk Tanpa Nama';
  }

  double _digitRatio(String s) {
    if (s.isEmpty) {
      return 0;
    }
    final int digits = s.replaceAll(RegExp(r'[^0-9]'), '').length;
    return digits / s.length;
  }

  String _titleCase(String s) {
    return s
        .toLowerCase()
        .split(' ')
        .map((String w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Parses "NAMA BARANG 2 x 3.500  7.000" and simpler "NAMA  7.000" lines.
  ParsedItem? _parseItemLine(String rawLine) {
    final String line = rawLine.trim();
    if (line.length < 3) {
      return null;
    }
    if (_totalWords.hasMatch(line) ||
        _paymentWords.hasMatch(line) ||
        _nonItemWords.hasMatch(line) ||
        _storeNoise.hasMatch(line)) {
      return null;
    }

    final RegExpMatch? qtyMatch = _qtyTimes.firstMatch(line);
    if (qtyMatch != null && qtyMatch.start > 0) {
      final String name = _cleanName(line.substring(0, qtyMatch.start));
      final int qty = int.tryParse(qtyMatch.group(1)!) ?? 1;
      final int unit = _parseAmount(qtyMatch.group(2)!);
      if (name.isEmpty || unit <= 0) {
        return null;
      }
      int price = unit;
      // If there is a total after the qty×unit part, prefer the line total.
      final String rest = line.substring(qtyMatch.end);
      final RegExpMatch? lineTotal = _trailingAmount.firstMatch(rest);
      if (lineTotal != null) {
        final int parsed = _parseAmount(lineTotal.group(1)!);
        if (parsed > 0) {
          price = (parsed / qty).round();
        }
      }
      return ParsedItem(name: name, qty: qty <= 0 ? 1 : qty, price: price);
    }

    // "NAMA BARANG   7.000" — name then a trailing amount.
    final RegExpMatch? amountMatch = _trailingAmount.firstMatch(line);
    if (amountMatch == null || amountMatch.start == 0) {
      return null;
    }
    final String name = _cleanName(line.substring(0, amountMatch.start));
    final int price = _parseAmount(amountMatch.group(1)!);
    if (name.isEmpty || price <= 0) {
      return null;
    }
    // Require the name to look like a product, not a stray number.
    if (name.replaceAll(RegExp(r'[^A-Za-z]'), '').length < 2) {
      return null;
    }
    return ParsedItem(name: name, qty: 1, price: price);
  }

  String _cleanName(String s) {
    return s
        .replaceAll(RegExp(r'[\s.\-:*]+$'), '')
        .replaceAll(RegExp(r'^\s*\d+[.)]\s*'), '')
        .trim();
  }

  int _parseAmount(String s) {
    final String digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  int? _extractTotal(List<String> lines) {
    for (final String line in lines.reversed) {
      if (_totalWords.hasMatch(line) && !_paymentWords.hasMatch(line)) {
        final RegExpMatch? m = _trailingAmount.firstMatch(line.trim());
        if (m != null) {
          final String before = line.substring(0, m.start);
          // The matched number must be the value, not part of the label.
          if (_totalWords.hasMatch(before) || before.trim().isEmpty) {
            final int v = _parseAmount(m.group(1)!);
            if (v > 0) {
              return v;
            }
          }
        }
      }
    }
    return null;
  }

  String _extractPayment(List<String> lines) {
    for (final String line in lines.reversed) {
      final RegExpMatch? m = _paymentWords.firstMatch(line);
      if (m != null && _trailingAmount.hasMatch(line)) {
        return _normalizePayment(m.group(1)!);
      }
    }
    for (final String line in lines.reversed) {
      final RegExpMatch? m = _paymentWords.firstMatch(line);
      if (m != null) {
        return _normalizePayment(m.group(1)!);
      }
    }
    return 'Tunai';
  }

  String _normalizePayment(String raw) {
    switch (raw.toLowerCase()) {
      case 'cash':
        return 'Tunai';
      case 'gopay':
        return 'GoPay';
      case 'ovo':
        return 'OVO';
      case 'dana':
        return 'DANA';
      case 'qris':
        return 'QRIS';
      default:
        return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
    }
  }

  /// Matches a plausible date: `dd/mm/yyyy`, `dd-mm-yy`, or `yyyy-mm-dd`.
  /// Tolerates stray spaces around separators (`13/09/ 2026`, common in OCR)
  /// and uses `(?!\d)` so it does not fire in the middle of a longer dotted
  /// number such as an NPWP (`01.234.567.8-901.000`).
  static final RegExp _dateCandidate = RegExp(
    r'(?<!\d)(\d{1,4})\s*([/\-.])\s*(\d{1,2})\s*\2\s*(\d{1,4})(?!\d)',
  );

  /// Lines carrying tax IDs / phone numbers are a common source of false dates.
  static final RegExp _dateNoise = RegExp(
    r'\b(npwp|telp|tel|phone|hp|no\.?\s*(telp|hp)|fax)\b',
    caseSensitive: false,
  );

  DateTime? _extractDate(String fullText) {
    _DateParts? date;
    String? dateLine;
    for (final String line in fullText.split('\n')) {
      if (_dateNoise.hasMatch(line)) {
        continue;
      }
      date = _parseDateCandidate(line);
      if (date != null) {
        dateLine = line;
        break;
      }
    }
    // Fall back to scanning the whole text if no clean line matched.
    date ??= _parseDateCandidate(fullText);
    if (date == null) {
      return null;
    }

    int hour = 0;
    int minute = 0;
    // Prefer a time on the same line as the date; only then scan the whole
    // text, so unrelated numbers (e.g. "No: 0123") can't masquerade as a time.
    final RegExpMatch? t = (dateLine != null ? _timePattern.firstMatch(dateLine) : null) ??
        _timePattern.firstMatch(fullText);
    if (t != null) {
      hour = int.tryParse(t.group(1)!) ?? 0;
      minute = int.tryParse(t.group(2)!) ?? 0;
      if (hour > 23 || minute > 59) {
        hour = 0;
        minute = 0;
      }
    }
    try {
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  _DateParts? _parseDateCandidate(String text) {
    for (final RegExpMatch m in _dateCandidate.allMatches(text)) {
      final int a = int.parse(m.group(1)!);
      final int c = int.parse(m.group(4)!);
      final String sep = m.group(2)!;

      int day;
      int month;
      int year;

      if (a > 31) {
        // Leading 4-digit year: yyyy-mm-dd.
        if (a < 1900 || a > 2100) {
          continue;
        }
        year = a;
        month = c;
        day = int.parse(m.group(3)!);
      } else {
        // Trailing year: dd/mm/yy(yy).
        if (c < 100) {
          year = 2000 + c;
        } else if (c >= 1900 && c <= 2100) {
          year = c;
        } else {
          continue;
        }
        day = a;
        month = int.parse(m.group(3)!);
      }

      // Only `/` and `-` delimit dates; a dotted group is almost always an
      // amount or an ID, so require separators to agree and be non-dot.
      if (sep == '.') {
        continue;
      }

      if (month < 1 || month > 12 || day < 1 || day > 31) {
        continue;
      }
      return _DateParts(year: year, month: month, day: day);
    }
    return null;
  }
}
