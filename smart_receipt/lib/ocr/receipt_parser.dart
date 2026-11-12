import 'dart:math' as math;

import 'ocr_raw_text.dart';

/// Structured data extracted from the raw OCR text of an Indonesian receipt.
class ParsedReceipt {
  ParsedReceipt({
    required this.store,
    required this.date,
    required this.items,
    required this.total,
    required this.paymentMethod,
    int? itemsTotal,
    this.discountTotal = 0,
    this.taxTotal = 0,
    this.totalFromReceipt = false,
    this.source = 'teks',
    List<String>? rowDump,
    List<String>? warnings,
  })  : itemsTotal = itemsTotal ??
            items.fold<int>(0, (int sum, ParsedItem i) => sum + i.subtotal),
        rowDump = rowDump ?? const <String>[],
        warnings = warnings ?? const <String>[];

  /// Merchant name.
  final String store;

  /// Transaction date, when one could be read.
  final DateTime? date;

  /// Purchased line items.
  final List<ParsedItem> items;

  /// Total printed on the receipt, or the sum of [items] when no total line was
  /// recognised.
  final int total;

  /// Payment method, e.g. `Tunai`, `QRIS`.
  final String paymentMethod;

  /// Sum of the line items as parsed.
  final int itemsTotal;

  /// Sum of receipt-level discounts (always positive).
  final int discountTotal;

  /// Tax added on top of the items (`PPN`, `PB1`), always positive.
  ///
  /// Kept out of [difference] because a tax line is not a missing item: without
  /// this, every receipt that prints PPN would warn about a discrepancy.
  final int taxTotal;

  /// True when [total] came from a `TOTAL` line instead of being computed.
  final bool totalFromReceipt;

  /// Which reconstruction produced this result: `geometri` or `teks`.
  final String source;

  /// The reconstructed rows, one per line, for diagnostics in the UI.
  final List<String> rowDump;

  /// Non-fatal problems worth surfacing to the user.
  final List<String> warnings;

  /// `total - itemsTotal`. Zero when the items add up to the printed total;
  /// negative for discounts, positive when the parser missed something.
  int get difference => total - itemsTotal;
  bool get isEmpty => items.isEmpty && total == 0;
}

/// One purchased line item.
class ParsedItem {
  ParsedItem({
    required this.name,
    required this.qty,
    required this.price,
    int? lineTotal,
  }) : lineTotal = lineTotal ?? qty * price;

  final String name;

  /// Quantity printed on the receipt.
  final int qty;

  /// Unit price.
  final int price;

  /// Line total as printed. Kept separate from `qty * price` because receipts
  /// sometimes apply a per-line discount, and because a quantity that does not
  /// divide the total evenly would otherwise lose a rupiah.
  final int lineTotal;

  int get subtotal => lineTotal;
}

class _DateParts {
  const _DateParts({required this.year, required this.month, required this.day});

  final int year;
  final int month;
  final int day;
}

/// One OCR cell with its horizontal extent. Cells on the same visual row are
/// sorted by [left] so column order is preserved.
class _Cell {
  const _Cell({required this.text, required this.left, required this.right});

  final String text;
  final double left;
  final double right;
}

/// A visual row of the receipt.
class _Row {
  _Row(this.cells);

  final List<_Cell> cells;

  String get text =>
      cells.map((_Cell c) => c.text.trim()).where((String t) => t.isNotEmpty).join(' ');
}

/// One plausible reading of an item row's numbers.
class _ItemCandidate {
  const _ItemCandidate({
    required this.qty,
    required this.unit,
    required this.lineTotal,
  });

  final int qty;
  final int unit;
  final int lineTotal;

  int get subtotal => lineTotal;
}

/// A parsed item plus every plausible reading of its numbers, so the parser can
/// pick the one that makes the receipt add up.
class _ItemDraft {
  _ItemDraft(this.name, this.candidates, this.rowIndex);

  final String name;
  final List<_ItemCandidate> candidates;

  /// Index of the row this draft came from, so header rows can be told apart
  /// from products.
  final int rowIndex;
  int index = 0;

  _ItemCandidate get selected => candidates[index];
}

/// Parses Indonesian receipt text into items, quantities, prices and totals.
///
/// The pipeline is deliberately staged so each step can be reasoned about and
/// tested in isolation:
///
///   1. **Rows** – rebuild visual rows from ML Kit's per-cell lines using the
///      bounding boxes. Without geometry, fall back to text lines and stitch
///      stacked cells back together.
///   2. **Classify** – label each row as item / total / payment / discount /
///      noise using keyword sets.
///   3. **Interpret** – turn each item row's trailing numbers into
///      `qty`, `unit price` and `line total`, keeping every plausible reading
///      (printers differ in column order).
///   4. **Reconcile** – if the receipt prints a `TOTAL`, choose the readings
///      whose sum matches `total + discounts`. This is what stops a price from
///      being attached to the wrong item.
class ReceiptParser {
  // ---------------------------------------------------------------------------
  // Vocabulary
  // ---------------------------------------------------------------------------

  /// Words that mark a line as a total/summary rather than a purchased item.
  static final RegExp _totalWords = RegExp(
    r'\b(grand\s*total|total\s*bayar|total|jumlah|sub\s*total|subtotal|'
    r'tagihan|amount\s*due)\b',
    caseSensitive: false,
  );

  /// `SUB TOTAL` must never win over `TOTAL`.
  static final RegExp _subtotalWords = RegExp(
    r'\b(sub\s*total|subtotal|sub\s*t[o0]t\s*a\s*l)\b',
    caseSensitive: false,
  );

  static final RegExp _paymentWords = RegExp(
    r'\b(tunai|cash|tendered|tender|debit|kredit|kartu|qris|gopay|go-?pay|ovo|dana|'
    r'shopeepay|linkaja|bca|mandiri|bri|bni|cimb|permata|card|edc|other)\b',
    caseSensitive: false,
  );

  static final RegExp _discountWords = RegExp(
    r'\b(diskon|discount|disc|potongan|voucher|hemat)\b',
    caseSensitive: false,
  );

  /// Tax lines added on top of the items: `PPN 11%`, `PB1`, `TAX`.
  ///
  /// `PBI` is included because OCR reads `PB1` that way on restaurant receipts.
  /// `RESTO`/`RESTORAN`/`REST` and `SERVICE`/`SVC` are the restaurant surcharges
  /// printed below `SUB TOTAL`; they are added on top of the items exactly like
  /// tax, so treating them as tax is what lets the receipt reconcile.
  static final RegExp _taxWords = RegExp(
    r'\b(ppn|pajak|tax|vat|pb\s*1|pbi|resto|restoran|rest|service|svc|suc\s*chg)\b',
    caseSensitive: false,
  );

  /// Tax words that prove a line is a summary line on their own.
  ///
  /// Deliberately excludes `resto`/`restoran`/`rest`: those appear in shop names
  /// (`RESTO ITALIA`), so treating them as conclusive would cut the item list
  /// at the header and lose the whole receipt. They stay in [_taxWords], where
  /// a line still has to look like a label by the ordinary rules.
  static final RegExp _conclusiveTaxWords = RegExp(
    r'\b(ppn|pajak|tax|vat|pb\s*1|pbi|service|svc|suc\s*chg)\b',
    caseSensitive: false,
  );

  /// Savings summaries that restate a discount already counted above, e.g.
  /// `ANDA HEMAT : 1,300`. Counting them would double the discount.
  static final RegExp _savingsSummary = RegExp(
    r'(anda|total)\s*hemat|harga\s*jual',
    caseSensitive: false,
  );

  /// Lines that indicate item/unit count rather than monetary total.
  /// E.g. `TOTAL ITEM : 2`, `TOTAL QTY : 3`, `TOTAL BARANG : 4`.
  static final RegExp _itemCountWords = RegExp(
    r'\b(item|items|qty|kuantitas|pcs|barang|kupon|poin|point)\b',
    caseSensitive: false,
  );

  /// Change/kembalian lines that might follow or contain the word 'total'.
  static final RegExp _changeWords = RegExp(
    r'\b(kembali|kembalian|change|kembaliannya)\b',
    caseSensitive: false,
  );

  /// Closing pleasantries at the bottom of a receipt. They are not summary
  /// labels, even though `SELAMAT BERBELANJA KEMBALI` contains `kembali`.
  static final RegExp _footerWords = RegExp(
    r'selamat|terima\s*kasih|kasih|barang\s+yang|tidak\s+dapat|dapat\s+ditukar|'
    r'thank|welcome',
    caseSensitive: false,
  );

  /// Lines that carry receipt metadata rather than a purchased product.
  ///
  /// Summary labels (`TOTAL`, `JUMLAH`, `ANDA HEMAT`) are deliberately **not**
  /// listed here: they are matched by [_isBareSummaryLabel] instead, which only
  /// accepts a line that is nothing but the label. Matching them here would
  /// also reject products that merely contain the word, such as
  /// `SABUN LIFEBUOY TOTAL CARE`.
  static final RegExp _noiseWords = RegExp(
    r'\b(kembali|kembalian|change|tunai|cash|tendered|tender|debit|kredit|kartu|'
    r'qris|gopay|go-?pay|'
    r'ovo|dana|shopeepay|linkaja|bca|mandiri|bri|bni|cimb|permata|edc|'
    r'ppn|pajak|tax|pb\s*1|pbi|diskon|discount|disc|potongan|hemat|'
    r'voucher|kupon|coupon|service|svc|suc\s*chg|poin|point|saldo|sisa|bayar|pembayaran|'
    r'visa|mastercard|master\s*card|cc\.|card|other|'
    r'resto|restoran|rest|service\s*charge|'
    r'harga\s*jual|anda\s*hemat|terima\s*kasih|terimakasih|npwp|'
    r'kasir|npk|struk|nota|invoice|kwitansi|tanggal|jam|waktu|telp|tel|'
    r'fax|phone|jl\.?|jalan|persero|layanan|konsumen|call|sms|email|www)\b',
    caseSensitive: false,
  );

  /// Bare numbers / phone numbers that should never be a store name.
  static final RegExp _nonStoreLine = RegExp(r'^[\d\s\-+().,:]+$');

  /// Merchant names printed as text somewhere on the receipt. The logo is an
  /// image, so OCR reads it as noise; the name almost always appears in a
  /// footer such as `LAYANAN KONSUMEN INDOMARET`.
  static const List<String> _knownMerchants = <String>[
    'indomaret',
    'alfamart',
    'alfamidi',
    'alfa express',
    'lawson',
    'circle k',
    'familymart',
    'hypermart',
    'transmart',
    'carrefour',
    'superindo',
    'indogrosir',
    'yogya',
    'lotte mart',
    'ranch market',
  ];

  /// Merchant stems that survive OCR errors. Checked in order after the exact
  /// names in [_knownMerchants] fail.
  static const Map<String, String> _merchantStems = <String, String>{
    'indomar': 'Indomaret',
    'alfam': 'Alfamart',
    'alfami': 'Alfamidi',
    'lawson': 'Lawson',
    'circle k': 'Circle K',
    'familymart': 'FamilyMart',
    'superindo': 'Superindo',
    'indogrosir': 'Indogrosir',
    'transmart': 'Transmart',
    'hypermart': 'Hypermart',
  };

  // ---------------------------------------------------------------------------
  // Numbers
  // ---------------------------------------------------------------------------

  /// A printed amount: `4500`, `18,000`, `18.000`, `Rp 4.500`, `(1,300)`.
  static final RegExp _amountShape =
      RegExp(r'^(?:\d{1,3}(?:[.,]\d{3})+|\d{1,7})$');

  /// Returns the integer value of [raw] if it is a printed amount, else `null`.
  ///
  /// Both `,` and `.` are accepted as thousands separators, matching how
  /// Indonesian receipts are printed. A parenthesised or trailing-minus value
  /// is returned negative.
  int? amountValue(String raw) {
    String t = raw.trim();
    if (t.isEmpty) {
      return null;
    }
    // Drop trailing punctuation left behind by OCR, e.g. "7.000,".
    t = t.replaceAll(RegExp(r'[,:;]+$'), '');
    t = t.replaceAll(RegExp(r'^rp\.?', caseSensitive: false), '').trim();

    bool negative = false;
    if (t.startsWith('(') && t.endsWith(')')) {
      negative = true;
      t = t.substring(1, t.length - 1).trim();
    }
    if (t.startsWith('-')) {
      negative = true;
      t = t.substring(1).trim();
    }
    if (t.endsWith('-')) {
      negative = true;
      t = t.substring(0, t.length - 1).trim();
    }

    if (!_amountShape.hasMatch(t)) {
      return null;
    }
    final int? value = int.tryParse(t.replaceAll(RegExp(r'[^0-9]'), ''));
    if (value == null) {
      return null;
    }
    return negative ? -value : value;
  }

  static bool _isMultiplier(String token) {
    final String t = token.toLowerCase();
    return t == 'x' || t == '*' || t == '@';
  }

  // ---------------------------------------------------------------------------
  // Entry point
  // ---------------------------------------------------------------------------

  ParsedReceipt parse(OcrRawResult raw) {
    // Both reconstructions are attempted and scored, because neither is
    // trustworthy on its own: geometry can be wrong if ML Kit returns useless
    // boxes, and text order is wrong for any real receipt. The score rewards a
    // printed total that matches the items, then item count.
    final List<ParsedReceipt> candidates = <ParsedReceipt>[];

    final List<_Row>? geometry = _rowsFromGeometry(raw.lines);
    if (geometry != null) {
      candidates.add(
        _parseRows(_mergeStackedCells(geometry), raw, 'geometri'),
      );
    }

    // The skew repair below can only measure a column's offset modulo one text
    // row, so the same receipt is rebuilt at a few row offsets and the scorer
    // picks whichever actually adds up.
    for (final int extraRows in <int>[-2, -1, 0, 1, 2]) {
      final List<_Row>? nearest =
          _rowsFromNearestName(raw.lines, extraRows: extraRows);
      if (nearest == null) {
        break;
      }
      candidates.add(
        _parseRows(
          _mergeStackedCells(nearest),
          raw,
          extraRows == 0 ? 'kolom' : 'kolom$extraRows',
        ),
      );
    }

    candidates.add(
      _parseRows(_mergeStackedCells(_rowsFromText(raw.lines)), raw, 'teks'),
    );

    candidates.sort((ParsedReceipt a, ParsedReceipt b) {
      final int byScore = scoreOf(b).compareTo(scoreOf(a));
      if (byScore != 0) {
        return byScore;
      }
      // Prefer geometry on a tie: it is the only reconstruction that respects
      // the receipt's table layout.
      return b.source == 'geometri' ? 1 : -1;
    });
    return candidates.first;
  }

  /// True when the parsed items account for the printed total.
  ///
  /// The OCR pipeline uses this to decide whether a scan is worth retrying, so
  /// it must agree with [scoreOf] about what "adding up" means.
  static bool reconciles(ParsedReceipt p) {
    if (!p.totalFromReceipt) {
      return false;
    }
    final int gap =
        (p.total + p.discountTotal - p.taxTotal - p.itemsTotal).abs();
    return gap <= 100;
  }

  /// Ranks a parse result. The printed total is the strongest evidence that the
  /// rows were reconstructed correctly, so a receipt that adds up outranks one
  /// that merely found more lines.
  static int scoreOf(ParsedReceipt p) {
    int score = p.items.length * 10;
    if (p.totalFromReceipt) {
      score += 20;
      // A taxed receipt prints the total after the tax was added, so the tax
      // has to come back out before the items can be compared with it.
      final int gap =
          (p.total + p.discountTotal - p.taxTotal - p.itemsTotal).abs();
      if (gap <= 1) {
        score += 100;
      } else if (gap <= 100) {
        score += 10;
      }
    } else if ((p.taxTotal > 0 || p.discountTotal > 0) &&
        p.itemsTotal + p.taxTotal - p.discountTotal == p.total) {
      // The printed total was unreadable but the items, the discount and the
      // tax still agree with it. That is stronger evidence than a printed total
      // that does not reconcile, so it outweighs the plain `+20` below and
      // separates a correct reconstruction from one that merely found the same
      // number of products.
      score += 40;
    }
    if (p.items.isEmpty) {
      score -= 50;
    }
    return score;
  }

  ParsedReceipt _parseRows(List<_Row> rows, OcrRawResult raw, String source) {
    rows = _pairSummaryLabels(rows);
    final String store = _extractStore(rows);
    final DateTime? date = _extractDate(raw.fullText);
    final String payment = _extractPayment(rows);
    final int? printedTotal = _extractTotal(rows);
    final int discounts = _extractDiscounts(rows);
    final int tax = _extractTax(rows);

    // Everything from the first summary line down is a total, a discount, a
    // payment or a footer — never a purchased product. Cutting the item scan
    // here keeps badly OCR'd summary words (`TOTAL` -> `TMAL`,
    // `KEMBALIAN` -> `KEDNLINN`) out of the item list, which no per-word rule
    // could recognise reliably.
    final int itemCutoff = _firstSummaryIndex(rows);

    // A printed table heading (`ITEM  QTY  HARGA  JUMLAH`) marks where the
    // products start. Everything above it is the shop's own header — name,
    // address, NPWP, cashier — and must not become a product, even when a
    // postcode in the address ends up looking like a price.
    int itemStart = 0;
    for (int i = 0; i < itemCutoff; i++) {
      if (_isColumnHeader(rows[i].text)) {
        itemStart = i;
        break;
      }
    }

    final List<_ItemDraft> drafts = <_ItemDraft>[];
    for (int i = itemStart; i < itemCutoff; i++) {
      // The heading words themselves sit on the same lines as the first
      // products, so they are skipped rather than read as products.
      if (_isColumnHeader(rows[i].text)) {
        continue;
      }
      final _ItemDraft? draft = _readItem(rows[i], i);
      if (draft != null) {
        drafts.add(draft);
      }
    }

    // The shop's own header line often carries a branch or phone number
    // (`INDOMARET 12345`). It passes every product test, so it is removed by
    // name: a purchased line never repeats the shop's name.
    drafts.removeWhere((_ItemDraft d) => _isStoreLine(d, store));

    // Reconciliation: choose the reading of each ambiguous row that makes the
    // items add up to the printed total (plus receipt-level discounts, minus
    // any tax the receipt adds on top of the items).
    final int? target =
        printedTotal == null ? null : printedTotal + discounts - tax;
    _reconcile(drafts, target);

    final List<ParsedItem> items = <ParsedItem>[
      for (final _ItemDraft d in drafts)
        ParsedItem(
          name: d.name,
          qty: d.selected.qty,
          price: d.selected.unit,
          lineTotal: d.selected.lineTotal,
        ),
    ];

    final int itemsTotal =
        items.fold<int>(0, (int sum, ParsedItem i) => sum + i.subtotal);
    final List<String> warnings = <String>[];

    final int total;
    if (printedTotal != null) {
      total = printedTotal;
    } else {
      // The `TOTAL` amount is the one figure OCR destroys most often (faded
      // thermal print, a crease through the middle). It can still be rebuilt
      // when the items add up exactly to the printed subtotal: then
      // `subtotal - discount + tax` is the total, and `TUNAI - KEMBALIAN` is an
      // independent check on it. Only accepted when the two agree.
      final int? subtotal = _extractSubtotal(rows);
      final int? cash = _extractCash(rows);
      final int? change = _extractChange(rows);
      final int derived = itemsTotal - discounts + tax;
      final bool rebuilt = items.isNotEmpty &&
          subtotal != null &&
          subtotal == itemsTotal &&
          (discounts > 0 || tax > 0) &&
          derived > 0 &&
          (cash == null ||
              change == null ||
              (cash - change - derived).abs() <= 1);
      if (rebuilt) {
        total = derived;
      } else {
        total = itemsTotal;
        if (items.isNotEmpty) {
          warnings.add('Baris TOTAL tidak terbaca; total dihitung dari item.');
        }
      }
    }

    if (items.isEmpty) {
      warnings.add('Tidak ada item yang terbaca dari struk.');
    } else if (printedTotal != null) {
      // Tax is not an item, so it must not count as a discrepancy.
      final int gap = total + discounts - tax - itemsTotal;
      if (gap.abs() > 1) {
        warnings.add(
          'Total struk dan jumlah item berbeda '
          '${gap.abs()} rupiah. Periksa harga item.',
        );
      }
    }

    final List<String> rowDump = <String>[
      for (final _Row row in rows)
        if (row.text.trim().isNotEmpty)
          '${row.text}   => ${_splitRow(row).numbers}',
    ];

    return ParsedReceipt(
      store: store,
      date: date,
      items: items,
      total: total,
      paymentMethod: payment,
      itemsTotal: itemsTotal,
      discountTotal: discounts,
      taxTotal: tax,
      totalFromReceipt: printedTotal != null,
      source: source,
      rowDump: rowDump,
      warnings: warnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Stage 1 — rebuild visual rows
  // ---------------------------------------------------------------------------

  /// Groups OCR cells into visual rows.
  ///
  /// ML Kit does **not** return a receipt in reading order: it emits text
  /// blocks, and on a receipt those blocks are the table's columns. The raw
  /// text therefore reads "all product names, then all quantities, then all
  /// prices", which is unusable on its own. The bounding boxes are the only
  /// link between a product and its numbers, so rows are rebuilt by clustering
  /// lines on their vertical centre and sorting each cluster left to right.
  List<_Row>? _rowsFromGeometry(List<OcrLine> lines) {
    if (lines.length < 3) {
      return null;
    }

    // Median line height is the natural unit of vertical tolerance: receipt
    // rows are about one line apart, and boxes on the same row rarely differ by
    // more than half a line.
    final List<double> heights = <double>[
      for (final OcrLine l in lines)
        if ((l.bottom - l.top).abs() > 0) (l.bottom - l.top).abs(),
    ]..sort();
    if (heights.isEmpty) {
      return null;
    }
    final double medianHeight = heights[heights.length ~/ 2];
    final double tolerance = math.max(medianHeight * 0.6, 1.0);

    final List<OcrLine> sorted = List<OcrLine>.of(lines)
      ..sort((OcrLine a, OcrLine b) {
        final int byY = a.centerY.compareTo(b.centerY);
        return byY != 0 ? byY : a.left.compareTo(b.left);
      });

    final List<List<OcrLine>> groups = <List<OcrLine>>[];
    for (final OcrLine line in sorted) {
      if (groups.isNotEmpty) {
        final List<OcrLine> current = groups.last;
        final double meanY = current
                .map((OcrLine l) => l.centerY)
                .reduce((double a, double b) => a + b) /
            current.length;
        if ((line.centerY - meanY).abs() <= tolerance) {
          current.add(line);
          continue;
        }
      }
      groups.add(<OcrLine>[line]);
    }

    return <_Row>[
      for (final List<OcrLine> group in groups)
        _Row(<_Cell>[
          for (final OcrLine line in (List<OcrLine>.of(group)
            ..sort((OcrLine a, OcrLine b) => a.left.compareTo(b.left))))
            _Cell(text: line.text, left: line.left, right: line.right),
        ]),
    ];
  }

  /// Pairs each numeric cell with the text line it belongs to using vertical
  /// proximity, without assuming the two columns have the same number of lines.
  ///
  /// This is the safety net for real ML Kit output. The recognizer returns the
  /// receipt as text blocks (one per column) and it merges cells it thinks are
  /// adjacent, so the quantity column may have two lines while the name column
  /// has five. Row clustering then produces ragged rows; anchoring on the text
  /// lines and attaching the nearest numbers on the right is immune to that.
  List<_Row>? _rowsFromNearestName(
    List<OcrLine> lines, {
    int extraRows = 0,
  }) {
    if (lines.length < 4) {
      return null;
    }

    bool isNumericLine(OcrLine line) {
      final _RowParts parts = _splitRow(
        _Row(<_Cell>[
          _Cell(text: line.text, left: line.left, right: line.right),
        ]),
      );
      final String withoutMultipliers =
          line.text.replaceAll(RegExp(r'[xX*@]'), '');
      return parts.numbers.isNotEmpty && !_hasLetters(withoutMultipliers);
    }

    final List<OcrLine> anchors =
        lines.where((OcrLine l) => !isNumericLine(l)).toList();
    final List<OcrLine> numbers =
        lines.where(isNumericLine).toList();
    if (anchors.isEmpty || numbers.isEmpty) {
      return null;
    }

    // Only meaningful when numbers actually sit to the right of the text, i.e.
    // the OCR output really is laid out as columns.
    final bool columnLayout = numbers.any(
      (OcrLine n) => anchors.any((OcrLine a) => n.left > a.left + 1),
    );
    if (!columnLayout) {
      return null;
    }

    // A table heading (`QTY`, `HARGA`, `JUMLAH`) sits on the same line as a
    // product and would steal that product's amounts. Row labels always start
    // at the receipt's left margin, so only anchors in that band may own
    // numbers.
    double leftEdge = double.infinity;
    double rightEdge = 0;
    for (final OcrLine anchor in anchors) {
      leftEdge = math.min(leftEdge, anchor.left);
    }
    for (final OcrLine line in lines) {
      rightEdge = math.max(rightEdge, line.right);
    }
    final double labelLimit = leftEdge + (rightEdge - leftEdge) * 0.3;
    final List<OcrLine> labelAnchors =
        anchors.where((OcrLine a) => a.left <= labelLimit).toList();
    List<OcrLine> rowAnchors =
        labelAnchors.length >= 3 ? labelAnchors : anchors;

    // A printed table heading (`ITEM  QTY  HARGA  JUMLAH`) marks where the
    // products start. Everything above it is the shop's own header — name,
    // address, NPWP, cashier — and must not become a product, even when the
    // postcode ends up looking like a price.
    // The heading's own boxes are staggered by the same skew as the amounts,
    // so the cut is the topmost of them: the first product starts just below
    // the heading row, not below the lowest of its words.
    double? headingTop;
    for (final OcrLine anchor in anchors) {
      if (_isColumnHeader(anchor.text)) {
        headingTop = math.min(headingTop ?? double.infinity, anchor.centerY);
      }
    }
    if (headingTop != null) {
      final List<OcrLine> below =
          rowAnchors.where((OcrLine a) => a.centerY > headingTop!).toList();
      if (below.length >= 3) {
        rowAnchors = below;
      }
    }

    // Remove the skew first: the amounts of a column all sit a fixed distance
    // below their row, and matching them as printed pairs each one with the
    // product underneath.
    final Map<OcrLine, double> alignedY = <OcrLine, double>{};
    _alignColumnsToRows(lines, rowAnchors, numbers, alignedY, extraRows);

    // `2 x 3.500` is printed under the product it multiplies, which puts the
    // box closer to the *next* product's name. It always belongs to the line
    // above it, so it is matched upwards instead of by distance.
    bool isMultiplierLine(OcrLine line) =>
        RegExp(r'^\s*\d+\s*[xX*@]\s*[\d.,]+\s*$').hasMatch(line.text);

    final Map<OcrLine, List<OcrLine>> attached =
        <OcrLine, List<OcrLine>>{};
    for (final OcrLine number in numbers) {
      if (isMultiplierLine(number)) {
        continue;
      }
      OcrLine? best;
      double bestDistance = double.infinity;
      for (final OcrLine anchor in rowAnchors) {
        if (number.left <= anchor.left + 1) {
          continue;
        }
        final double distance =
            (alignedY[number]! - anchor.centerY).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = anchor;
        }
      }
      if (best != null) {
        attached.putIfAbsent(best, () => <OcrLine>[]).add(number);
      }
    }
    for (final OcrLine number in numbers.where(isMultiplierLine)) {
      OcrLine? above;
      for (final OcrLine anchor in rowAnchors) {
        if (anchor.centerY < number.centerY) {
          above = anchor;
        }
      }
      if (above != null) {
        attached.putIfAbsent(above, () => <OcrLine>[]).add(number);
      }
    }


    // Every text line is kept, so the shop name and address are still there for
    // the header parsing; only rows below the table heading can own amounts.
    return <_Row>[
      for (final OcrLine anchor in anchors)
        _Row(<_Cell>[
          _Cell(text: anchor.text, left: anchor.left, right: anchor.right),
          for (final OcrLine number in (attached[anchor] ?? <OcrLine>[])
            ..sort((OcrLine a, OcrLine b) => a.left.compareTo(b.left)))
            _Cell(text: number.text, left: number.left, right: number.right),
        ]),
    ];
  }

  /// Straightens each numeric column against the text rows before matching.
  ///
  /// A receipt photographed at an angle is a rotated, perspective-warped
  /// rectangle, but ML Kit still reports axis-aligned boxes. The paper is a
  /// parallelogram in the frame, so the further right a column sits the lower
  /// its boxes land: on one photo the names were 31 px above their quantity,
  /// 38 px above their unit price and 50 px above their line total. Nearest-row
  /// matching then hands every amount to the product *below* it.
  ///
  /// The offset is constant within a column, so it can be measured and removed.
  /// Amounts are right-aligned, so a column is the set of amounts sharing a
  /// right edge; for each column the shift that puts the most amounts on top of
  /// a text row is the one the photo actually has.
  void _alignColumnsToRows(
    List<OcrLine> lines,
    List<OcrLine> anchors,
    List<OcrLine> numbers,
    Map<OcrLine, double> alignedY,
    int extraRows,
  ) {
    for (final OcrLine n in numbers) {
      alignedY[n] = n.centerY;
    }
    if (anchors.length < 4 || numbers.length < 4) {
      return;
    }
    final double pitch = _rowPitch(anchors);
    if (pitch <= 0) {
      return;
    }

    final List<List<OcrLine>> columns =
        _clusterByRightEdge(numbers, _columnTolerance(lines));
    for (final List<OcrLine> column in columns) {
      // Too few entries to measure a shift from; leaving them alone is safer
      // than guessing.
      if (column.length < 4) {
        continue;
      }
      final double shift =
          _measureColumnShift(anchors, column, pitch) + extraRows * pitch;
      if (shift == 0) {
        continue;
      }
      for (final OcrLine n in column) {
        alignedY[n] = n.centerY - shift;
      }
    }
  }

  /// Median vertical distance between consecutive text rows.
  double _rowPitch(List<OcrLine> anchors) {
    final List<double> ys = <double>[
      for (final OcrLine a in anchors) a.centerY,
    ]..sort();
    final List<double> gaps = <double>[
      for (int i = 1; i < ys.length; i++) ys[i] - ys[i - 1],
    ]..sort();
    if (gaps.isEmpty) {
      return 0;
    }
    return gaps[gaps.length ~/ 2];
  }

  /// The downward offset of one column, or 0 when it is already aligned.
  ///
  /// Found by trying every offset across a row and keeping the one that leaves
  /// the amounts closest to a text row. Distances are capped at one row so a
  /// single amount with no matching row cannot drag the whole column.
  double _measureColumnShift(
    List<OcrLine> anchors,
    List<OcrLine> column,
    double pitch,
  ) {
    // The offset can go either way: a sheet leaning away on the right pushes
    // its amounts *down*, one leaning away on the left pushes them *up*.
    const int steps = 96;
    final double lo = -2.2 * pitch;
    final double hi = 2.2 * pitch;

    double bestShift = 0;
    double bestCost = double.infinity;
    for (int s = 0; s <= steps; s++) {
      final double shift = lo + (hi - lo) * s / steps;
      double cost = 0;
      for (final OcrLine n in column) {
        final double y = n.centerY - shift;
        double nearest = pitch;
        for (final OcrLine a in anchors) {
          final double d = (y - a.centerY).abs();
          if (d < nearest) {
            nearest = d;
          }
        }
        cost += nearest;
      }
      if (cost < bestCost) {
        bestCost = cost;
        bestShift = shift;
      }
    }

    // An offset that leaves every amount a third of a row away from any text is
    // not a real column, it is a coincidence.
    final double mean = bestCost / column.length;
    if (mean > pitch * 0.2) {
      return 0;
    }
    return bestShift.abs() < pitch * 0.08 ? 0 : bestShift;
  }

  /// How far apart two amounts can be and still count as the same column.
  ///
  /// Scaled to the receipt, not fixed: a photo of a receipt filling the frame
  /// spreads its columns wider than a tightly cropped one.
  double _columnTolerance(List<OcrLine> lines) {
    double left = double.infinity;
    double right = 0;
    for (final OcrLine line in lines) {
      left = math.min(left, line.left);
      right = math.max(right, line.right);
    }
    return math.max(20.0, (right - left) * 0.05);
  }

  /// Groups amounts into columns by their right edge.
  ///
  /// Amounts are printed right-aligned, so the right edge is the stable part of
  /// the box; the left edge moves with the number of digits. Clustering on the
  /// left would split `9.500` from `17.500` in the same column.
  List<List<OcrLine>> _clusterByRightEdge(
    List<OcrLine> numbers,
    double tolerance,
  ) {
    final List<OcrLine> sorted = List<OcrLine>.of(numbers)
      ..sort((OcrLine a, OcrLine b) => a.right.compareTo(b.right));
    final List<List<OcrLine>> columns = <List<OcrLine>>[];
    for (final OcrLine number in sorted) {
      if (columns.isNotEmpty &&
          (number.right - columns.last.last.right).abs() <= tolerance) {
        columns.last.add(number);
      } else {
        columns.add(<OcrLine>[number]);
      }
    }
    return columns;
  }

  List<_Row> _rowsFromText(List<OcrLine> lines) {    return <_Row>[
      for (final OcrLine line in lines)
        _Row(<_Cell>[
          _Cell(text: line.text, left: line.left, right: line.right),
        ]),
    ];
  }

  /// Stitches rows that belong together but were emitted as separate lines.
  ///
  /// Two shapes are handled:
  ///
  /// ```
  /// 18,000          <- line total
  /// 4 4500          <- qty + unit
  /// S/ROTI KRIM...  <- name          (name below the numbers)
  /// ```
  ///
  /// and
  ///
  /// ```
  /// S/ROTI KRIM...  <- name
  /// 4 4500          <- qty + unit
  /// 18,000          <- line total    (numbers below the name)
  /// ```
  List<_Row> _mergeStackedCells(List<_Row> rows) {
    final int n = rows.length;
    final List<bool> isName = List<bool>.filled(n, false);
    final List<bool> isNumbers = List<bool>.filled(n, false);

    for (int i = 0; i < n; i++) {
      final _RowParts parts = _splitRow(rows[i]);
      // `2 x 3.500` is a numbers-only row even though it contains the letter
      // `x`; strip the multiplier glyphs before looking for real letters.
      final String withoutLetters =
          rows[i].text.replaceAll(RegExp(r'[xX*@]'), '');
      // A quantity printed in its own column arrives as a bare `1`. `_splitRow`
      // deliberately reads a lone small integer as part of a product name
      // (`ROKOK MILD 16`), so it has to be recognised here instead: without
      // this the quantity cell is invisible, the name below it claims the prices
      // and every amount on the receipt shifts up by one product.
      final bool loneQuantity = RegExp(r'^\d{1,3}$').hasMatch(rows[i].text.trim());
      isNumbers[i] = !_hasLetters(withoutLetters) &&
          (parts.numbers.isNotEmpty || loneQuantity);
      isName[i] = parts.numbers.isEmpty &&
          _hasLetters(rows[i].text) &&
          !_noiseWords.hasMatch(rows[i].text) &&
          // A mangled summary label (`TOTAL` -> `TMAL`) passes every product
          // test, then claims the amount printed below it — so the totals block
          // ends up one row out of step and `TMAL` steals the subtotal. Keep
          // summary labels out of the product scan; `_pairSummaryLabels` handles
          // them afterwards. Only a *bare* label counts: a product whose name
          // contains `TOTAL` (`SABUN LIFEBUOY TOTAL CARE`) is still a product.
          !_isBareSummaryLabel(rows[i].text) &&
          _looksLikeProductName(rows[i].text);
    }

    // Decide which numeric rows belong to which product name before emitting
    // anything, so a numeric row is never consumed by the wrong item.
    final List<int> owner = List<int>.filled(n, -1);
    for (int i = 0; i < n; i++) {
      if (!isName[i]) {
        continue;
      }

      // Numbers printed above the name belong to it only when the previous
      // item has not already claimed them. This handles both column orders:
      //   numbers / name  (Indomaret)   -> claim above
      //   name / numbers  (most others) -> claim below
      final List<int> before = <int>[];
      for (int j = i - 1; j >= 0 && j >= i - 3; j--) {
        if (!isNumbers[j] || owner[j] != -1) {
          break;
        }
        before.insert(0, j);
      }
      if (before.isNotEmpty) {
        for (final int j in before) {
          owner[j] = i;
        }
        continue;
      }

      // ML Kit commonly emits the quantity, the unit price and the line total
      // as three separate lines, so the window has to reach three rows or the
      // last amount is orphaned and every price shifts up by one item.
      for (int j = i + 1; j < n && j <= i + 3; j++) {
        if (!isNumbers[j] || owner[j] != -1) {
          // OCR sometimes drops a scrap of punctuation between the name and
          // its price (`AQUA AIR MINERAL 600ML`, `. i.`, `7.000`). Step over it
          // instead of abandoning the price, otherwise the whole product is
          // lost.
          if (!isName[j] && _isOcrScrap(rows[j].text)) {
            continue;
          }
          break;
        }
        owner[j] = i;
      }
    }

    // --- Shifted price column ------------------------------------------------
    // ML Kit sometimes emits every price one row lower than the product it
    // belongs to, so the first product ends up with no price and the last
    // price is orphaned:
    //
    //   BERAS PREMIUM 5KG        <- no price
    //   MINYAK GORENG 2L
    //     72.000                 <- actually BERAS' price
    //   ...
    //   KOPI KAPAL API 656
    //     24.500                 <- actually SUSU's price
    //     9.500                  <- orphan, actually KOPI's price
    //
    // When the products and the prices are equal in number but shifted like
    // this, pairing them by position restores the receipt. Restricting the
    // count to the item region keeps the summary block (SUBTOTAL/PPN/TOTAL)
    // out of the tally.
    final int itemEnd = _firstSummaryIndex(rows);
    // The item block starts at the top-most product name that sits directly
    // above the first price; walking back keeps the header (`INDOMARET`, the
    // address) out of the tally.
    int itemStart = itemEnd;
    for (int i = 0; i < itemEnd; i++) {
      if (isNumbers[i]) {
        itemStart = i;
        break;
      }
    }
    while (itemStart > 0 && isName[itemStart - 1]) {
      itemStart--;
    }

    final List<int> nameIdx = <int>[
      for (int i = itemStart; i < itemEnd; i++)
        if (isName[i]) i,
    ];
    final List<int> numIdx = <int>[
      for (int i = itemStart; i < itemEnd; i++)
        if (isNumbers[i]) i,
    ];
    if (nameIdx.length >= 2) {
      // The tell-tale of the shifted layout: one price ends up owned by nobody
      // at the very end of the block, and the products/prices are equal in
      // number. Combined with either a first product that got no price at all,
      // or a first product whose total came from its own `2 x 3.500` line (so
      // it looks priced even though the printed price belongs to it too), that
      // is enough to pair them by position.
      final int bareNames = nameIdx
          .where((int i) => !numIdx.any((int j) => owner[j] == i))
          .length;
      final int greedyNames = nameIdx
          .where((int i) => numIdx.where((int j) => owner[j] == i).length > 1)
          .length;
      final List<int> orphans =
          numIdx.where((int j) => owner[j] == -1).toList();
      final bool firstDerived =
          _splitRow(rows[nameIdx.first]).hasMultiplier;
      final bool shifted = nameIdx.length == numIdx.length &&
          ((bareNames == 1 && greedyNames == 1) ||
              (orphans.length == 1 &&
                  orphans.single == numIdx.last &&
                  (bareNames == 1 || firstDerived)));
      if (shifted) {
        for (final int j in numIdx) {
          owner[j] = -1;
        }
        for (int k = 0; k < nameIdx.length; k++) {
          owner[numIdx[k]] = nameIdx[k];
        }
      }
    }

    final List<_Row> out = <_Row>[];
    for (int i = 0; i < n; i++) {
      if (owner[i] != -1) {
        continue; // claimed by a product name
      }
      if (isName[i]) {
        final List<int> claimed = <int>[
          for (int j = 0; j < n; j++)
            if (owner[j] == i) j,
        ];
        if (claimed.isNotEmpty) {
          // Keep the product name first: `_splitRow` reads the trailing
          // numbers, so numbers printed above the name move after it.
          final StringBuffer text = StringBuffer(rows[i].text);
          for (final int j in claimed) {
            text.write(' ${rows[j].text}');
          }
          out.add(_Row(<_Cell>[
            _Cell(text: text.toString().trim(), left: 0, right: 0),
          ]));
          continue;
        }
      }
      out.add(rows[i]);
    }
    return out;
  }

  /// A row left over from OCR noise: a couple of stray letters or punctuation,
  /// no amount. Seen between a product name and its price on faded photos.
  bool _isOcrScrap(String text) {
    final String t = text.trim();
    if (t.isEmpty || t.length > 6) {
      return false;
    }
    if (_hasDigits(t)) {
      return false;
    }
    return t.replaceAll(RegExp(r'[^A-Za-z]'), '').length <= 2;
  }

  /// Index of the first row that belongs to the totals block, or
  /// [rows]`.length` when the receipt has no summary.
  ///
  /// A summary row carries a label (`SUBTOTAL`, `PPN`, `TOTAL`, `TUNAI`, …) but
  /// no amount of its own, because OCR emitted the amount on a different line.
  int _firstSummaryIndex(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      final _Row row = _withoutPercentages(rows[i]);
      if (_splitRow(row).numbers.isNotEmpty) {
        continue;
      }
      if (_isBareSummaryLabel(row.text) && !_isColumnHeader(row.text)) {
        return i;
      }
    }
    return rows.length;
  }

  /// Drops `11%` / `5 %` tokens from a *label* row. A percentage is a rate, not
  /// a printed amount, and leaving it in makes `PPN 11%` look like a row that
  /// already has a value.
  ///
  /// Only label rows are touched. On a faded photo an amount can come back as
  /// `133.0%`; stripping that would delete the total outright.
  _Row _withoutPercentages(_Row row) {
    if (!row.text.contains('%') || !_hasLetters(row.text)) {
      return row;
    }
    final String text =
        row.text.replaceAll(RegExp(r'\d+(?:[.,]\d+)?\s*%'), ' ').trim();
    return _Row(<_Cell>[_Cell(text: text, left: 0, right: 0)]);
  }

  bool _isSummaryLabel(String text) {
    if (!_hasLetters(text)) {
      return false;
    }
    if (_totalWords.hasMatch(text) ||
        _subtotalWords.hasMatch(text) ||
        _taxWords.hasMatch(text) ||
        _discountWords.hasMatch(text) ||
        _paymentWords.hasMatch(text) ||
        _changeWords.hasMatch(text) ||
        _itemCountWords.hasMatch(text)) {
      return true;
    }
    return _matchesFuzzyKeyword(text);
  }

  /// Words that may make up a summary label on their own.
  static const Set<String> _summaryWords = <String>{
    'total', 'subtotal', 'jumlah', 'tagihan', 'tunai', 'kembali', 'kembalian',
    'diskon', 'disc', 'discount', 'potongan', 'voucher', 'hemat', 'pajak',
    'ppn', 'tax', 'vat', 'pb1', 'bayar', 'cash', 'debit', 'kredit',
    'kartu', 'qris', 'tendered', 'tender', 'edc', 'bca', 'mandiri', 'bri',
    'bni', 'cimb', 'permata',
    'gopay', 'ovo', 'dana', 'shopeepay', 'linkaja', 'change', 'item', 'items',
    'qty', 'kuantitas', 'barang', 'kupon', 'poin', 'point', 'jlh',
    'resto', 'restoran', 'rest', 'service', 'svc', 'card', 'other',
  };

  /// Summary words that are safe to accept on the **first** token alone.
  ///
  /// `_summaryWords` also holds words that double as shop or product names —
  /// `RESTO ITALIA`, `SERVICE CENTER`, `KARTU UCAPAN`. Accepting those as the
  /// first token would cut the item list at the header and lose the receipt,
  /// so they are only ever accepted when the whole line is label-like.
  static const Set<String> _unambiguousLabelWords = <String>{
    'total', 'subtotal', 'jumlah', 'tagihan', 'tunai', 'kembali', 'kembalian',
    'diskon', 'disc', 'discount', 'potongan', 'voucher', 'hemat', 'pajak',
    'ppn', 'tax', 'vat', 'pb1', 'tendered', 'tender', 'edc', 'qris', 'gopay',
    'ovo', 'dana', 'shopeepay', 'linkaja', 'change', 'qty', 'kuantitas', 'jlh',
  };

  /// Filler words that decorate a summary label without changing what it is,
  /// e.g. `ANDA HEMAT`, `GRAND TOTAL`, `TOTAL BELANJA`.
  static const Set<String> _summaryFillers = <String>{
    'anda', 'grand', 'sub', 'belanja', 'harga', 'jual', 'akhir', 'pembelian',
    'rp', 'satuan',
  };

  /// True when [text] is nothing but a summary label, or *begins* with one.
  ///
  /// `_isSummaryLabel` matches the word anywhere, which is right for a line that
  /// carries its own amount but wrong for a bare product name: `SABUN LIFEBUOY
  /// TOTAL CARE` is a product, not the start of the totals block. Requiring
  /// every word to be a label word (or a filler) keeps the two apart.
  ///
  /// A line that *starts* with a label word is also a label, because printers
  /// decorate totals with a count OCR mangles: `TOTAL (2 iten)`. No product name
  /// begins with `TOTAL`, `JUMLAH` or `SERVICE`, so this stays safe.
  ///
  /// The first word is compared **exactly**, never fuzzily: `BATERAI` and
  /// `BAYAR` reduce to the same consonant skeleton (`BTR` / `BYR`), and a fuzzy
  /// match here would throw away every battery on the receipt.
  bool _isBareSummaryLabel(String text) {
    // `_isTotalLabel` is checked too: it tolerates a label that lost its last
    // letter (`TOTA.`), which `_isSummaryLabel` does not.
    if (!_isSummaryLabel(text) && !_isTotalLabel(text)) {
      return false;
    }
    // `SUB TOTAL` is never a product name, so a match anywhere in the line is
    // conclusive — and it must survive OCR splitting the last letter off
    // (`Sub Tota l`). This is deliberately narrower than `_isSummaryLabel`,
    // which also matches `TOTAL` inside names like `LIFEBUOY TOTAL CARE`.
    if (_subtotalWords.hasMatch(text)) {
      return true;
    }
    // A tax line is never a product either, and OCR splits `PB1` into `PB 1`,
    // which leaves a first token (`pb`) that is not a summary word on its own.
    if (_conclusiveTaxWords.hasMatch(text)) {
      return true;
    }
    final List<String> tokens = text
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((String t) => t.length >= 3)
        .toList();
    if (tokens.isNotEmpty && _unambiguousLabelWords.contains(tokens.first)) {
      return true;
    }
    for (final String token in tokens) {
      if (!_isLabelToken(token)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [token] can be part of a summary label.
  bool _isLabelToken(String token) {
    return _summaryWords.contains(token) ||
        _summaryFillers.contains(token) ||
        _fuzzyKeywords.any((String k) => _fuzzyMatch(token, k)) ||
        // OCR drops the last letter of a label (`TOTA.` for `TOTAL`), leaving a
        // prefix that fuzzy matching cannot see because the final consonant is
        // missing. Only whole-line label checks use this, so a product that
        // merely starts with `TOTA` is unaffected.
        (token.length >= 4 &&
            _fuzzyKeywords.any((String k) => k.startsWith(token)));
  }

  /// A bare table heading (`ITEM`, `QTY`, `HARGA`, `JUMLAH`) is not a summary
  /// label, even though `TOTAL ITEM` and `TOTAL QTY` are. Treating the heading
  /// as the start of the totals block would cut the item list to nothing.
  bool _isColumnHeader(String text) {
    return RegExp(
      r'^\s*(item|items|qty|kuantitas|nama|nama\s+barang|barang|produk|'
      r'deskripsi|harga|hrg|harga\s+satuan|jumlah|jlh|total\s+harga)\s*$',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// Summary and footer words that OCR frequently mangles. Thermal printing
  /// drops strokes and camera blur smears them, so `TOTAL` arrives as `TMAL`
  /// and `ANDA HEMAT` as `ANDA BEMAT`. Matching them by edit distance keeps
  /// those lines out of the item list.
  ///
  /// Deliberately excludes header words (`KASIR`, `NPWP`, `TELP`): they appear
  /// *above* the products, so treating them as a summary marker would cut the
  /// item list to nothing.
  static const List<String> _fuzzyKeywords = <String>[
    'total',
    'subtotal',
    'jumlah',
    'tagihan',
    'tunai',
    'kembalian',
    'diskon',
    'potongan',
    'hemat',
    'pajak',
    'bayar',
    'qty',
  ];

  bool _matchesFuzzyKeyword(String text) {
    for (final String token in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (token.length < 4) {
        continue;
      }
      for (final String keyword in _fuzzyKeywords) {
        if (_fuzzyMatch(token, keyword)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Whether [token] is [keyword] with up to one letter dropped or misread.
  ///
  /// Compared on consonants, with the first and last one pinned. Thermal
  /// printing loses vowels first, so `TOTAL` becomes `TMAL`; comparing the raw
  /// strings would need a tolerance wide enough to also swallow `BOTOL`, and
  /// pinning the outer consonants keeps that from happening.
  static bool _fuzzyMatch(String token, String keyword) {
    if (token == keyword) {
      return true;
    }
    final String a = _consonants(token);
    final String b = _consonants(keyword);
    if (a.length < 2 || b.length < 2) {
      return false;
    }
    // A two-consonant skeleton is too short to be evidence on its own
    // (`TANI` and `TUNAI` both reduce to `tn`), so it also needs the raw words
    // to differ by a single letter. `TMAL`/`TOTAL` has a three-consonant
    // skeleton and does not need that.
    if ((a.length < 3 || b.length < 3) &&
        _editDistance(token, keyword) > 1) {
      return false;
    }
    if (a[0] != b[0] || a[a.length - 1] != b[b.length - 1]) {
      return false;
    }
    if ((a.length - b.length).abs() > 1) {
      return false;
    }
    return _editDistance(a, b) <= 1;
  }

  /// Reattaches amounts to summary labels when OCR emitted the whole label
  /// column first and the whole amount column afterwards:
  ///
  /// ```
  /// SUB TOTAL          SUB TOTAL      263.900
  /// PPN 11%       ->   PPN 11%         29.029
  ///   263.900          TOTAL          292.929
  /// TOTAL
  ///    29.029
  ///   292.929
  /// ```
  ///
  /// Pairing them by position is the only reading that keeps `PPN` and `TOTAL`
  /// with their own amounts; pairing each label with the *next* amount would
  /// give `PPN = 263.900` and `TOTAL = 29.029`.
  List<_Row> _pairSummaryLabels(List<_Row> rows) {
    final int start = _firstSummaryIndex(rows);
    if (start >= rows.length) {
      return rows;
    }

    final List<int> labelRows = <int>[];
    final List<int> amountRows = <int>[];
    for (int i = start; i < rows.length; i++) {
      final _Row stripped = _withoutPercentages(rows[i]);
      final _RowParts parts = _splitRow(stripped);
      if (parts.numbers.isEmpty) {
        if (_isSummaryLabel(stripped.text)) {
          labelRows.add(i);
        }
        continue;
      }
      if (!_hasLetters(stripped.text)) {
        amountRows.add(i);
      }
    }

    if (labelRows.length < 2 || labelRows.length != amountRows.length) {
      return rows;
    }

    final Map<int, String> amounts = <int, String>{
      for (int k = 0; k < labelRows.length; k++)
        labelRows[k]: rows[amountRows[k]].text.trim(),
    };
    final Set<int> consumed = amountRows.toSet();

    return <_Row>[
      for (int i = 0; i < rows.length; i++)
        if (!consumed.contains(i))
          amounts.containsKey(i)
              ? _Row(<_Cell>[
                  ...rows[i].cells,
                  _Cell(text: amounts[i]!, left: 0, right: 0),
                ])
              : rows[i],
    ];
  }

  // ---------------------------------------------------------------------------
  // Stage 2 — split a row into name tokens and trailing numbers
  // ---------------------------------------------------------------------------

  /// Repairs amounts that ML Kit split at the thousands separator.
  ///
  /// On real receipts the recognizer frequently emits `18,` + `000`, `8,` +
  /// `500` or `(1,` + `300)` as separate tokens, especially when the column is
  /// narrow. Joining them back is essential: read on their own, `8,` becomes
  /// `8` and `500` becomes `500`, which silently corrupts the line total.
  List<String> _joinSplitAmounts(List<String> tokens) {
    final List<String> out = <String>[];
    final RegExp threeDigits = RegExp(r'^\d{3}[.,;:)\]]*$');
    final RegExp startsWithDotDigits = RegExp(r'^[.]\d{3}');

    for (int i = 0; i < tokens.length; i++) {
      final String token = tokens[i];
      final bool endsWithSeparator = RegExp(r'[.,]$').hasMatch(token);
      if (endsWithSeparator && i + 1 < tokens.length) {
        final String next = tokens[i + 1];
        // `18,` + `000`  -> `18,000`;  `(1,` + `300)` -> `(1,300)`
        if (threeDigits.hasMatch(next)) {
          out.add('$token$next');
          i++;
          continue;
        }
        // `8,` + `500` where the next token carries trailing punctuation.
        if (RegExp(r'^\d{3}$').hasMatch(next)) {
          out.add('$token$next');
          i++;
          continue;
        }
      }

      // `18` + `.000` -> `18.000` — OCR splits at the Indonesian thousands
      // separator (dot) when the dot begins a new token.
      if (i + 1 < tokens.length &&
          RegExp(r'^\d{1,3}$').hasMatch(token) &&
          startsWithDotDigits.hasMatch(tokens[i + 1])) {
        out.add('$token${tokens[i + 1]}');
        i++;
        continue;
      }

      // `18` + `.` + `000` -> `18.000` — isolated separator token between digits.
      if (i + 2 < tokens.length &&
          RegExp(r'^\d{1,3}$').hasMatch(token) &&
          (tokens[i + 1] == '.' || tokens[i + 1] == ',') &&
          threeDigits.hasMatch(tokens[i + 2])) {
        out.add('$token.${tokens[i + 2]}');
        i += 2;
        continue;
      }

      out.add(token);
    }
    return out;
  }

  _RowParts _splitRow(_Row row) {
    final List<String> tokens = _joinSplitAmounts(
      row.text
          .split(RegExp(r'\s+'))
          .where((String t) => t.isNotEmpty)
          .toList(),
    );

    // Scan from the right for the trailing numeric block.
    bool hasMultiplier = false;
    int cut = tokens.length;
    while (cut > 0) {
      final String token = tokens[cut - 1];
      if (amountValue(token) != null) {
        cut--;
        continue;
      }
      if (_isMultiplier(token) && cut < tokens.length) {
        hasMultiplier = true;
        cut--;
        continue;
      }
      break;
    }

    // Positions of the amount tokens inside the numeric block.
    final List<int> amountPositions = <int>[];
    for (int i = cut; i < tokens.length; i++) {
      if (amountValue(tokens[i]) != null) {
        amountPositions.add(i);
      }
    }

    // A lone small integer is far more likely to be part of the product name
    // ("ROKOK MILD 16", "TELUR 1 KG") than a price.
    if (amountPositions.length == 1 && !hasMultiplier) {
      final String token = tokens[amountPositions.first];
      final int value = amountValue(token)!;
      // Parenthesised/minus values are discounts, never part of a name.
      if (value > 0 &&
          value < 1000 &&
          !token.contains(RegExp(r'[.,()\-]'))) {
        amountPositions.clear();
        cut = tokens.length;
      }
    }

    // Only the last three numbers are `qty`, `unit` and `line total`. Anything
    // before them belongs to the product name, e.g. the `225` in
    // "FF LOW FAT VAN 225 1 5200 5,200".
    if (amountPositions.length > 3) {
      cut = amountPositions[amountPositions.length - 3];
    }

    // Three numbers that do not multiply out usually mean the first one is a
    // pack size rather than a quantity: "FF LOW FAT VAN 225 5200 5,200". A real
    // quantity is small (receipts rarely sell 100+ units), so a value above 99
    // in that position is folded back into the name.
    //
    // The pack size can be four digits: `250S` comes back from OCR as `2505`,
    // and `1000ML` as `1000`. Left in the numeric block those readings can never
    // multiply out, so the row yields no candidate at all and the whole product
    // disappears. Prices in that position are far larger than any pack size, so
    // the fold stops at four digits.
    if (amountPositions.length == 3 && !hasMultiplier) {
      final int a = amountValue(tokens[amountPositions[0]])!;
      final int b = amountValue(tokens[amountPositions[1]])!;
      final int c = amountValue(tokens[amountPositions[2]])!;
      final bool multiplies = a * b == c || b * c == a || a * c == b;
      if (!multiplies && a > 99 && a < 10000 && c >= 1000) {
        cut = amountPositions[0] + 1;
      }
    }

    final List<int> numbers = <int>[
      for (int i = cut; i < tokens.length; i++)
        if (amountValue(tokens[i]) case final int v) v,
    ];

    final List<String> nameTokens = tokens
        .sublist(0, cut)
        .where((String t) => t.trim().isNotEmpty)
        .toList();
    while (nameTokens.isNotEmpty &&
        nameTokens.last.toLowerCase().replaceAll('.', '') == 'rp') {
      nameTokens.removeLast();
    }

    return _RowParts(
      name: _cleanName(nameTokens.join(' ')),
      numbers: numbers,
      hasMultiplier: hasMultiplier,
    );
  }

  // ---------------------------------------------------------------------------
  // Stage 3 — interpret a row as an item
  // ---------------------------------------------------------------------------

  _ItemDraft? _readItem(_Row row, int rowIndex) {
    final _RowParts parts = _splitRow(row);
    if (parts.numbers.isEmpty || parts.name.isEmpty) {
      return null;
    }
    if (_noiseWords.hasMatch(parts.name) || _isBareSummaryLabel(parts.name)) {
      return null;
    }
    if (!_looksLikeProductName(parts.name)) {
      return null;
    }

    final List<_ItemCandidate> candidates =
        _candidates(parts.numbers, parts.hasMultiplier);
    if (candidates.isEmpty) {
      return null;
    }
    return _ItemDraft(parts.name, candidates, rowIndex);
  }

  /// True when [draft] is the shop's own header rather than a purchased line.
  ///
  /// Only a *recognised* merchant can be a header line. When the shop is
  /// unknown, [_extractStore] falls back to the first line that has letters —
  /// which is the first product — and dropping it would silently lose an item.
  /// The first rows are the only candidates, so a product further down that
  /// happens to repeat the shop name is never removed.
  bool _isStoreLine(_ItemDraft draft, String store) {
    if (draft.rowIndex > 2 || !_isKnownMerchant(store)) {
      return false;
    }
    final String a = draft.name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final String b = store.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (a.length < 4 || b.length < 4) {
      return false;
    }
    return a.startsWith(b);
  }

  /// Whether [store] is one of the merchants in [_knownMerchants].
  bool _isKnownMerchant(String store) {
    final String s = store.toLowerCase();
    return _knownMerchants.any((String m) => _titleCase(m) == _titleCase(s));
  }

  /// Every plausible `(qty, unit, lineTotal)` reading of the trailing numbers.
  ///
  /// The first candidate is the most likely one; the rest exist so
  /// [_reconcile] can switch to a different column order when the receipt
  /// total proves it.
  List<_ItemCandidate> _candidates(List<int> numbers, bool hasMultiplier) {
    if (numbers.isEmpty) {
      return const <_ItemCandidate>[];
    }

    // Keep only the last three numbers; anything earlier belongs to the name.
    final List<int> nums = numbers.length > 3
        ? numbers.sublist(numbers.length - 3)
        : numbers;

    if (nums.length >= 3) {
      final int a = nums[nums.length - 3];
      final int b = nums[nums.length - 2];
      final int c = nums[nums.length - 1];
      final List<_ItemCandidate> out = <_ItemCandidate>[];

      // `qty x unit total` — the explicit multiplier settles the order.
      if (hasMultiplier && a > 99 && b > 0 && b <= 99 && c > 0) {
        // A number too large to be a quantity sits in front of `2 x 3.500`:
        // it is the pack size OCR glued onto the name (`85G` -> `856`), and the
        // line total was printed on a line OCR dropped. Multiply it out.
        out.add(_ItemCandidate(qty: b, unit: c, lineTotal: b * c));
      }
      if (hasMultiplier && a > 0 && a <= 99 && b >= 0) {
        out.add(_ItemCandidate(qty: a, unit: b, lineTotal: c));
      }
      // `qty unit total`
      if (a > 0 && a <= 999 && a * b == c) {
        out.add(_ItemCandidate(qty: a, unit: b, lineTotal: c));
      }
      // `total qty unit` (Indomaret prints the line total above the name)
      if (b > 0 && b <= 999 && b * c == a) {
        out.add(_ItemCandidate(qty: b, unit: c, lineTotal: a));
      }
      // `qty total unit`
      if (a > 0 && a <= 999 && a * c == b) {
        out.add(_ItemCandidate(qty: a, unit: c, lineTotal: b));
      }
      // As printed, even if it does not multiply out (line-level discount).
      if (a > 0 && a <= 999 && c > 0) {
        out.add(_ItemCandidate(qty: a, unit: b, lineTotal: c));
      }
      return _dedupe(out);
    }

    if (nums.length == 2) {
      final int a = nums[0];
      final int b = nums[1];
      final List<_ItemCandidate> out = <_ItemCandidate>[];

      // `qty lineTotal` — receipts print the line total, so when it divides
      // evenly the first number is the quantity.
      if (a > 0 && a <= 99 && b % a == 0 && b ~/ a >= 100) {
        out.add(_ItemCandidate(qty: a, unit: b ~/ a, lineTotal: b));
      }
      // `qty unit`
      if (a > 0 && a <= 99) {
        out.add(_ItemCandidate(qty: a, unit: b, lineTotal: a * b));
      }
      // `unit total`
      if (a > 0 && b > 0 && b % a == 0 && b ~/ a <= 99) {
        out.add(_ItemCandidate(qty: b ~/ a, unit: a, lineTotal: b));
      }
      // Nothing above fits, and the first number is too large to be a quantity:
      // it is a pack size that OCR glued onto the name (`65G` -> `656`, giving
      // `KOPI KAPAL API 656 9.500`). The price then stands alone. Dropping the
      // row instead would lose the whole line from the receipt.
      if (out.isEmpty && a > 99) {
        out.add(_ItemCandidate(qty: 1, unit: b, lineTotal: b));
      }
      return _dedupe(out);
    }

    // Single amount: one unit at that price.
    if (nums.first <= 0) {
      return const <_ItemCandidate>[];
    }
    return <_ItemCandidate>[
      _ItemCandidate(qty: 1, unit: nums.first, lineTotal: nums.first),
    ];
  }

  List<_ItemCandidate> _dedupe(List<_ItemCandidate> candidates) {
    final List<_ItemCandidate> out = <_ItemCandidate>[];
    final Set<String> seen = <String>{};
    for (final _ItemCandidate c in candidates) {
      if (c.qty <= 0 || c.unit < 0 || c.lineTotal < 0) {
        continue;
      }
      final String key = '${c.qty}:${c.unit}:${c.lineTotal}';
      if (seen.add(key)) {
        out.add(c);
      }
    }
    return out;
  }

  /// Picks, for each ambiguous row, the reading that brings the item sum
  /// closest to the receipt's own total. Two passes are enough to settle
  /// interacting choices.
  void _reconcile(List<_ItemDraft> drafts, int? target) {
    if (target == null || drafts.isEmpty) {
      return;
    }
    int sum() => drafts.fold<int>(0, (int s, _ItemDraft d) => s + d.selected.subtotal);

    for (int pass = 0; pass < 2; pass++) {
      for (final _ItemDraft draft in drafts) {
        if (draft.candidates.length < 2) {
          continue;
        }
        final int current = sum();
        int bestIndex = draft.index;
        int bestDiff = (current - target).abs();
        for (int i = 0; i < draft.candidates.length; i++) {
          if (i == draft.index) {
            continue;
          }
          final int candidateSum =
              current - draft.selected.subtotal + draft.candidates[i].subtotal;
          final int diff = (candidateSum - target).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestIndex = i;
          }
        }
        draft.index = bestIndex;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Stage 4 — totals, discounts, payment
  // ---------------------------------------------------------------------------

  /// Finds the printed total.
  ///
  /// Searched from the bottom up, preferring `GRAND TOTAL` and skipping
  /// `SUB TOTAL`, because receipts print subtotals above the final total.
  int? _extractTotal(List<_Row> rows) {
    int? best;
    int bestRank = -1;

    for (int i = rows.length - 1; i >= 0; i--) {
      final _Row row = rows[i];
      final String text = row.text;
      if (!_isTotalLabel(text) ||
          _subtotalWords.hasMatch(text) ||
          _itemCountWords.hasMatch(text) ||
          _changeWords.hasMatch(text)) {
        continue;
      }
      if (_paymentWords.hasMatch(text)) {
        continue;
      }
      final int rank = _totalRank(text);
      final int? value = _valueForLabel(rows, i);
      if (value == null || value <= 0) {
        continue;
      }
      // On Indonesian receipts, a monetary total in Rupiah is never under 100
      // (products are almost always >= 500 IDR). Small values are item counts.
      if (value < 100) {
        continue;
      }
      if (rank > bestRank ||
          (rank == bestRank && (best == null || value > best))) {
        best = value;
        bestRank = rank;
      }
    }
    return best;
  }

  /// A total label, tolerating OCR damage: thermal printing and blur turn
  /// `TOTAL` into `TMAL` or `TOTAI`.
  ///
  /// Compared on consonants only, because the dropped letter is nearly always a
  /// vowel (`TOTAL` -> `TMAL`). Comparing the raw strings would need a tolerance
  /// wide enough to also swallow products like `TOMAT`.
  bool _isTotalLabel(String text) {
    if (_totalWords.hasMatch(text)) {
      return true;
    }
    for (final String token in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (token.length < 4) {
        continue;
      }
      for (final String keyword in const <String>['total', 'jumlah', 'tagihan']) {
        if (_fuzzyMatch(token, keyword)) {
          return true;
        }
        // OCR drops the last letter of a label far more often than it corrupts
        // one in the middle: `TOTAL` reads as `TOTA.` or `TOTAI`. A four-letter
        // prefix of a label word is therefore enough evidence, and no product
        // name starts with `TOTA`, `JUML` or `TAGI`.
        if (token.length >= 4 && keyword.startsWith(token)) {
          return true;
        }
      }
    }
    return false;
  }

  static String _consonants(String s) => s.replaceAll(RegExp(r'[aeiou]'), '');

  int _totalRank(String text) {
    final String t = text.toLowerCase();
    if (t.contains('grand')) {
      return 4;
    }
    if (t.contains('total bayar') ||
        t.contains('total akhir') ||
        t.contains('total belanja') ||
        t.contains('total tagihan') ||
        t.contains('total pembelian') ||
        t.contains('total harga')) {
      return 3;
    }
    if (t.contains('total')) {
      return 2;
    }
    if (t.contains('jumlah') || t.contains('tagihan')) {
      return 1;
    }
    return 0;
  }

  /// Sum of all discount lines, as a positive number.
  int _extractDiscounts(List<_Row> rows) {
    int total = 0;
    for (int i = 0; i < rows.length; i++) {
      final _Row row = rows[i];
      if (!_discountWords.hasMatch(row.text) ||
          _isTotalLabel(row.text) ||
          _savingsSummary.hasMatch(row.text)) {
        continue;
      }
      final int? value = _valueForLabel(rows, i);
      if (value != null) {
        total += value.abs();
      }
    }
    return total;
  }

  /// Sum of all tax lines (`PPN`, `PB1`), as a positive number.
  ///
  /// A receipt prints `SUBTOTAL`, then the tax, then the `TOTAL` that includes
  /// it. The items only account for the subtotal, so the tax has to be set
  /// aside before comparing the two, otherwise every taxed receipt looks like
  /// it is missing an item worth exactly the tax.
  /// The amount printed on a `SUBTOTAL` line, when there is one.
  ///
  /// Used to rebuild the total on receipts whose `TOTAL` amount OCR destroyed:
  /// the items adding up exactly to the printed subtotal is proof the item list
  /// was read correctly, so `subtotal - discount + tax` is the real total.
  int? _extractSubtotal(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      if (!_subtotalWords.hasMatch(rows[i].text)) {
        continue;
      }
      final int? value = _valueForLabel(rows, i);
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  /// The `TUNAI`/cash amount the customer handed over.
  int? _extractCash(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      final String text = rows[i].text;
      if (!RegExp(r'\b(tunai|cash|bayar)\b', caseSensitive: false)
          .hasMatch(text)) {
        continue;
      }
      final int? value = _valueForLabel(rows, i);
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  /// The `KEMBALIAN`/change amount.
  int? _extractChange(List<_Row> rows) {
    for (int i = 0; i < rows.length; i++) {
      if (!_changeWords.hasMatch(rows[i].text) ||
          _footerWords.hasMatch(rows[i].text)) {
        continue;
      }
      final int? value = _valueForLabel(rows, i);
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  int _extractTax(List<_Row> rows) {
    int total = 0;
    for (int i = 0; i < rows.length; i++) {
      final _Row row = rows[i];
      if (!_taxWords.hasMatch(row.text) || _isTotalLabel(row.text)) {
        continue;
      }
      final int? value = _valueForLabel(rows, i);
      if (value != null) {
        total += value.abs();
      }
    }
    return total;
  }

  /// The amount belonging to a label row: the right-most number on the row, or
  /// the first number on the next row when OCR split the label from its value.
  int? _valueForLabel(List<_Row> rows, int index) {
    final _RowParts parts = _splitRow(_withoutPercentages(rows[index]));
    if (parts.numbers.isNotEmpty) {
      return parts.numbers.last;
    }
    // "TOTAL :" on one line, "33,900" on the next.
    for (int j = index + 1; j < rows.length && j <= index + 2; j++) {
      final _RowParts next = _splitRow(_withoutPercentages(rows[j]));
      if (next.numbers.isEmpty) {
        if (rows[j].text.trim().isEmpty) {
          continue;
        }
        return null;
      }
      if (_hasLetters(_withoutPercentages(rows[j]).text)) {
        return null;
      }
      return next.numbers.first;
    }
    return null;
  }

  String _extractPayment(List<_Row> rows) {
    for (int i = rows.length - 1; i >= 0; i--) {
      final RegExpMatch? m = _paymentWords.firstMatch(rows[i].text);
      if (m == null) {
        continue;
      }
      return _normalizePayment(m.group(1)!);
    }
    return 'Tunai';
  }

  String _normalizePayment(String raw) {
    switch (raw.toLowerCase().replaceAll('-', '')) {
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
      case 'shopeepay':
        return 'ShopeePay';
      case 'linkaja':
        return 'LinkAja';
      default:
        final String t = raw.trim();
        return t.isEmpty ? 'Tunai' : t[0].toUpperCase() + t.substring(1).toLowerCase();
    }
  }

  // ---------------------------------------------------------------------------
  // Store
  // ---------------------------------------------------------------------------

  String _extractStore(List<_Row> rows) {
    final String haystack =
        rows.map((_Row r) => r.text).join(' ').toLowerCase();
    // Whole-word match: a plain `contains` turns the city in the address
    // ("Yogyakarta") into the merchant "Yogya" and hides the real store name.
    for (final String merchant in _knownMerchants) {
      if (RegExp('\\b${RegExp.escape(merchant)}\\b').hasMatch(haystack)) {
        return _titleCase(merchant);
      }
    }
    // OCR mangles merchant names in footers ("INDOMAREMBALI", "ALFAMART" with
    // a dropped letter). Match on the distinctive stem instead of the full
    // name so the store is still recognised.
    for (final MapEntry<String, String> alias in _merchantStems.entries) {
      if (haystack.contains(alias.key)) {
        return alias.value;
      }
    }

    // Last resort for the header: thermal printing and camera blur drop single
    // letters, so `INDOMARET` becomes `INDOMRET`. Match the closest known
    // merchant by edit distance rather than falling through to the raw text.
    for (final _Row row in rows.take(4)) {
      final String t = row.text.trim().toLowerCase();
      if (t.length < 6 || t.length > 24 || _hasDigits(t)) {
        continue;
      }
      final String? fuzzy = _closestMerchant(t);
      if (fuzzy != null) {
        return fuzzy;
      }
    }

    for (final _Row row in rows.take(6)) {
      final String t = row.text.trim();
      if (t.length < 3 || t.length > 40) {
        continue;
      }
      if (_nonStoreLine.hasMatch(t) || _datePattern.hasMatch(t)) {
        continue;
      }
      if (_noiseWords.hasMatch(t) || _paymentWords.hasMatch(t)) {
        continue;
      }
      if (_digitRatio(t) > 0.4) {
        continue;
      }
      final String letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length >= 3) {
        return _titleCase(t);
      }
    }
    return 'Struk Tanpa Nama';
  }

  /// Nearest known merchant to a mangled header line, or `null` when nothing is
  /// close enough. Two edits is enough for a dropped or doubled letter, which is
  /// what camera blur and thermal printing produce.
  String? _closestMerchant(String line) {
    String? best;
    int bestDistance = 3;
    for (final String merchant in _knownMerchants) {
      if ((merchant.length - line.length).abs() > 2) {
        continue;
      }
      final int d = _editDistance(line, merchant);
      if (d < bestDistance) {
        bestDistance = d;
        best = _titleCase(merchant);
      }
    }
    return best;
  }

  static int _editDistance(String a, String b) {
    List<int> previous = List<int>.generate(b.length + 1, (int i) => i);
    List<int> current = List<int>.filled(b.length + 1, 0);
    for (int i = 1; i <= a.length; i++) {
      current[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final int del = previous[j] + 1;
        final int ins = current[j - 1] + 1;
        final int sub = previous[j - 1] + cost;
        current[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final List<int> swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }

  double _digitRatio(String s) {
    if (s.isEmpty) {
      return 0;
    }
    return s.replaceAll(RegExp(r'[^0-9]'), '').length / s.length;
  }

  String _titleCase(String s) {
    return s
        .toLowerCase()
        .split(' ')
        .map((String w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _hasLetters(String text) => RegExp(r'[A-Za-z]').hasMatch(text);
  bool _hasDigits(String text) => RegExp(r'[0-9]').hasMatch(text);

  /// True when [name] plausibly is a product name rather than metadata.
  ///
  /// The leading character is not required to be a letter: OCR routinely reads
  /// `S/ROTI` as `5/ROTI`. The letter ratio is what rejects register lines such
  /// as `2.0. 31 914115/ALIA MU/01`.
  ///
  /// Thresholds are intentionally lenient (≥ 2 letters, ≥ 30% letter ratio)
  /// because minimarket receipts abbreviate aggressively (`GG FLT 12`,
  /// `FF LW FAT 225`), so the product name often contains more digits and
  /// symbols than letters.
  bool _looksLikeProductName(String name) {
    final String t = name.trim();
    if (t.isEmpty) {
      return false;
    }
    final int letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
    if (letters < 2) {
      return false;
    }
    return letters / t.length >= 0.3;
  }

  String _cleanName(String s) {
    return s
        .replaceAll(RegExp(r'[\s.\-:*]+$'), '')
        .replaceAll(RegExp(r'^\s*\d+[.)]\s*'), '')
        // A leading one- or two-digit token is the quantity column bleeding into
        // the name (`1 Chicken Baked Rice`). Three digits are left alone because
        // they are part of real product names (`100 PLUS`).
        .replaceAll(RegExp(r'^\s*\d{1,2}\s+(?=[A-Za-z])'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // Date
  // ---------------------------------------------------------------------------

  static final RegExp _datePattern = RegExp(
    r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})',
  );

  static final RegExp _timePattern = RegExp(r'(\d{1,2})[:.](\d{2})');

  /// Colon-separated time, preferred over [_timePattern] because a dotted date
  /// (`14.09.16`) also looks like `hh.mm`.
  static final RegExp _timeColon = RegExp(r'(\d{1,2}):(\d{2})');

  /// Matches a plausible date: `dd/mm/yyyy`, `dd-mm-yy`, `dd.mm.yy` or
  /// `yyyy-mm-dd`. Tolerates stray spaces around separators (`13/09/ 2026`)
  /// and uses `(?!\d)` so it does not fire inside an NPWP.
  static final RegExp _dateCandidate = RegExp(
    r'(?<!\d)(\d{1,4})\s*([/\-.])\s*(\d{1,2})\s*\2\s*(\d{1,4})(?!\d)',
  );

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
    date ??= _parseDateCandidate(fullText);
    if (date == null) {
      return null;
    }

    int hour = 0;
    int minute = 0;
    final String timeSource = dateLine ?? fullText;
    final RegExpMatch? t =
        _timeColon.firstMatch(timeSource) ?? _timePattern.firstMatch(timeSource);
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
        if (a < 1900 || a > 2100) {
          continue;
        }
        year = a;
        month = int.parse(m.group(3)!);
        day = c;
      } else {
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

      // Dotted dates are common (`14.09.16`), but a dotted number is also how
      // amounts are written, so only accept shapes that cannot be an amount.
      if (sep == '.') {
        final bool isDmy = m.group(1)!.length <= 2 &&
            m.group(3)!.length == 2 &&
            (m.group(4)!.length == 2 || m.group(4)!.length == 4);
        final bool isYmd = m.group(1)!.length == 4 &&
            m.group(3)!.length == 2 &&
            m.group(4)!.length == 2;
        if (!isDmy && !isYmd) {
          continue;
        }
      }

      if (month < 1 || month > 12 || day < 1 || day > 31) {
        continue;
      }
      return _DateParts(year: year, month: month, day: day);
    }
    return null;
  }
}

/// A row split into its product name and its trailing numbers.
class _RowParts {
  const _RowParts({
    required this.name,
    required this.numbers,
    required this.hasMultiplier,
  });

  final String name;
  final List<int> numbers;
  final bool hasMultiplier;
}
