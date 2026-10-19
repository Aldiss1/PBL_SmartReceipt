import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
import '../ocr/ocr_raw_text.dart';
import '../ocr/ocr_service.dart';
import '../ocr/receipt_classifier.dart';
import '../ocr/receipt_parser.dart';
import '../providers/receipt_provider.dart';
import '../services/correction_training_service.dart';
import '../theme/theme_controller.dart';
import 'transaction_saved.dart';

/// Screen 4 - Review Transaction.
///
/// Prefills the editable items with the names/prices/qty recovered by OCR and
/// the categories predicted by the classifier.
class ReviewTransactionScreen extends StatefulWidget {
  const ReviewTransactionScreen({
    super.key,
    required this.scan,
    required this.predictions,
  });

  final OcrScanResult scan;
  final List<ItemPrediction> predictions;

  @override
  State<ReviewTransactionScreen> createState() => _ReviewTransactionScreenState();
}

class _ReviewTransactionScreenState extends State<ReviewTransactionScreen> {
  late final String _store;
  late final DateTime _date;
  late List<TransactionItem> _items;
  late final List<ItemPrediction> _predictions;

  /// Total printed on the receipt (`TOTAL : 33,900`).
  ///
  /// This is authoritative: the sum of the parsed items can legitimately differ
  /// because of receipt-level discounts, deposits or rounding. Recomputing the
  /// total from items silently turns a parsing mistake into a wrong amount.
  late final int _receiptTotal;

  /// Persists user category fixes so they can feed the next training run.
  final CorrectionTrainingService _corrections = CorrectionTrainingService();

  @override
  void initState() {
    super.initState();
    _store = widget.scan.parsed.store;
    _date = widget.scan.parsed.date ?? DateTime.now();
    _predictions = widget.predictions;
    _receiptTotal = widget.scan.parsed.total;

    final List<ParsedItem> parsedItems = widget.scan.parsed.items;
    _items = <TransactionItem>[];
    for (int i = 0; i < parsedItems.length; i++) {
      final ParsedItem p = parsedItems[i];
      final String category = i < widget.predictions.length
          ? widget.predictions[i].category
          : 'Lainnya';
      _items.add(
        TransactionItem(
          name: p.name,
          qty: p.qty,
          price: p.price,
          category: category,
        ),
      );
    }
  }

  int get _itemsTotal =>
      _items.fold(0, (int sum, TransactionItem i) => sum + i.subtotal);

  /// Difference between the printed total and the parsed items.
  ///
  /// Zero when everything lines up; non-zero when the receipt applied a
  /// discount/fee we did not model, or when the parser missed/misread a line.
  int get _totalAdjustment => _receiptTotal - _itemsTotal;

  Future<void> _editCategory(int index) async {
    final String current = _items[index].category;
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => _CategorySheet(current: current),
    );
    if (selected != null && selected != current) {
      final TransactionItem old = _items[index];
      setState(() {
        _items[index] = TransactionItem(
          name: old.name,
          qty: old.qty,
          price: old.price,
          category: selected,
        );
      });
      // Record the correction as training data (best-effort, never blocks UI).
      _recordCorrection(index, old, selected);
    }
  }

  /// Stores (preprocessed item name -> user-corrected category) so the
  /// classifier can learn from real user feedback.
  Future<void> _recordCorrection(
    int index,
    TransactionItem old,
    String selected,
  ) async {
    final ItemPrediction? prediction =
        index < _predictions.length ? _predictions[index] : null;
    final int saved = await _corrections.recordCorrection(
      itemName: old.name,
      correctedCategoryName: selected,
      correctedCategoryId: _categoryIdFor(selected),
      prediction: prediction,
    );
    if (!mounted || saved < 0) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Koreksi disimpan sebagai data training.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Sweeps every item on save and persists corrections for those whose final
  /// category differs from the model's prediction.
  ///
  /// The per-tap [_recordCorrection] already covers the common flow; this
  /// catches edits made and then reverted, guaranteeing the training set only
  /// holds genuine disagreements.
  Future<void> _recordCategoryCorrections() async {
    for (int i = 0; i < _items.length; i++) {
      if (i >= _predictions.length) {
        continue;
      }
      final ItemPrediction prediction = _predictions[i];
      final TransactionItem item = _items[i];
      if (item.category == prediction.category) {
        continue;
      }
      await _corrections.recordCorrection(
        itemName: item.name,
        correctedCategoryName: item.category,
        correctedCategoryId: _categoryIdFor(item.category),
        prediction: prediction,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);
    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const AppStatusBar(),
            AppTopBar(
              title: 'Review Transaksi',
              subtitle: 'Periksa & koreksi hasil OCR',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _StoreCard(store: _store, date: _date),
                    if (widget.scan.parsed.warnings.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _ParseWarnings(warnings: widget.scan.parsed.warnings),
                    ],
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Daftar Item',
                      trailing: Text(
                        '${_items.length} item',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < _items.length; i++)
                      _ItemCard(item: _items[i], onTap: () => _editCategory(i)),
                    if (_items.isEmpty) const _EmptyItemsNotice(),
                    const SizedBox(height: 4),
                    SecondaryButton(
                      label: 'Tambah Item',
                      icon: Icons.add,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 18),
                    _TotalCard(
                      itemsTotal: _itemsTotal,
                      total: _receiptTotal,
                      adjustment: _totalAdjustment,
                    ),
                    const SizedBox(height: 14),
                    _OcrTextViewer(raw: widget.scan.raw, parsed: widget.scan.parsed),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: PrimaryButton(
                label: 'Simpan Transaksi',
                icon: Icons.check_circle_outline,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final ReceiptProvider provider =
        Provider.of<ReceiptProvider>(context, listen: false);
    final db.Receipt receipt = db.Receipt(
      storeName: _store,
      transactionDate: _date,
      totalAmount: _receiptTotal.toDouble(),
      taxAmount: 0,
      subtotal: _itemsTotal.toDouble(),
      paymentMethod: widget.scan.parsed.paymentMethod,
      imagePath: widget.scan.sourcePath,
      ocrText: widget.scan.raw.fullText,
      status: 'saved',
      createdAt: DateTime.now(),
      transactions: <db.Transaction>[
        for (final TransactionItem i in _items)
          db.Transaction(
            receiptId: 0,
            categoryId: _categoryIdFor(i.category),
            itemName: i.name,
            quantity: i.qty,
            unitPrice: i.price.toDouble(),
            totalPrice: i.subtotal.toDouble(),
            discount: 0,
            createdAt: DateTime.now(),
          ),
      ],
    );

    try {
      await provider.addReceipt(receipt);
    } catch (_) {
      // Storage failure should not block the confirmation screen.
    }

    // Record any category the user changed away from the model's prediction.
    await _recordCategoryCorrections();

    if (!mounted) {
      return;
    }
    Navigator.pushReplacement(
      context,
      appRoute(
        TransactionSavedScreen(
          store: _store,
          date: _date,
          items: _items,
          paymentMethod: widget.scan.parsed.paymentMethod,
        ),
      ),
    );
  }

  /// Maps a UI category name to its canonical SQLite category id.
  int _categoryIdFor(String category) => kCategoryIdForName(category);
}

/// Shown when OCR found no line items; the user can add them manually.
class _EmptyItemsNotice extends StatelessWidget {
  const _EmptyItemsNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.edit_note_outlined, color: AppColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tidak ada item yang terbaca dari struk. '
              'Tambahkan item secara manual dengan tombol di bawah.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.date});

  final String store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          const IconBox(icon: Icons.storefront_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  store,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatDateTime(date),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, size: 19, color: AppColors.amber),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});

  final TransactionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(item.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconBox(
            icon: c.icon,
            size: 40,
            iconSize: 20,
            background: c.color.withValues(alpha: 0.14),
            color: c.color,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.qty} × ${rupiah(item.price)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CategoryChip(category: item.category, dense: true),
                      const SizedBox(width: 6),
                      Icon(Icons.edit, size: 13, color: AppColors.amber),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            rupiah(item.subtotal),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible view of the raw OCR text behind the parsed items.
///
/// Kept on the review screen on purpose: when an item looks wrong, the fastest
/// way to tell whether the OCR or the parser is at fault is to read the text the
/// parser actually received.
class _OcrTextViewer extends StatefulWidget {
  const _OcrTextViewer({required this.raw, required this.parsed});

  final OcrRawResult raw;
  final ParsedReceipt parsed;

  @override
  State<_OcrTextViewer> createState() => _OcrTextViewerState();
}

enum _OcrView { text, geometry, parser }

class _OcrTextViewerState extends State<_OcrTextViewer> {
  _OcrView _view = _OcrView.text;

  /// Raw text plus each line's bounding box. The boxes are what the parser uses
  /// to decide which price belongs to which product, so they are the first thing
  /// to look at when an item comes out with the wrong price.
  String get _geometryDump {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('== BARIS + KOORDINAT (${widget.raw.lines.length} baris) ==');
    buffer.writeln('left  top  right bottom | teks');
    for (final OcrLine line in widget.raw.lines) {
      buffer.writeln(
        '${line.left.toStringAsFixed(0).padLeft(5)} '
        '${line.top.toStringAsFixed(0).padLeft(5)} '
        '${line.right.toStringAsFixed(0).padLeft(5)} '
        '${line.bottom.toStringAsFixed(0).padLeft(5)} | ${line.text}',
      );
    }
    return buffer.toString();
  }

  /// What the parser actually made of the OCR output: which reconstruction won,
  /// every rebuilt row, and the numbers it read from each row.
  String get _parserDump {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('sumber: ${widget.parsed.source}');
    buffer.writeln(
      'total=${widget.parsed.total} '
      'items=${widget.parsed.itemsTotal} '
      'diskon=${widget.parsed.discountTotal}',
    );
    buffer.writeln();
    buffer.writeln('== BARIS HASIL REKONSTRUKSI ==');
    for (final String row in widget.parsed.rowDump) {
      buffer.writeln(row);
    }
    buffer.writeln();
    buffer.writeln('== ITEM TERBACA ==');
    for (final ParsedItem item in widget.parsed.items) {
      buffer.writeln(
        '${item.name} | qty=${item.qty} '
        'harga=${item.price} total=${item.lineTotal}',
      );
    }
    return buffer.toString();
  }

  String get _diagnostic {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('== TEKS MENTAH ==');
    buffer.writeln(
      widget.raw.fullText.trim().isEmpty
          ? '(tidak ada teks)'
          : widget.raw.fullText.trim(),
    );
    buffer.writeln();
    buffer.write(_geometryDump);
    buffer.writeln();
    buffer.write(_parserDump);
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: AppColors.textMuted,
        collapsedIconColor: AppColors.textMuted,
        title: Text(
          'Teks OCR',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        subtitle: Text(
          'Ketuk untuk memeriksa hasil pembacaan mentah',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              _ModeChip(
                label: 'Teks',
                selected: _view == _OcrView.text,
                onTap: () => setState(() => _view = _OcrView.text),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: 'Koordinat',
                selected: _view == _OcrView.geometry,
                onTap: () => setState(() => _view = _OcrView.geometry),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: 'Baris parser',
                selected: _view == _OcrView.parser,
                onTap: () => setState(() => _view = _OcrView.parser),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Salin',
                icon: Icon(Icons.copy_all_outlined,
                    size: 18, color: AppColors.textMuted),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _diagnostic));
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Teks OCR disalin ke clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              switch (_view) {
                _OcrView.text => _rawTextOnly,
                _OcrView.geometry => _geometryDump,
                _OcrView.parser => _parserDump,
              },
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                fontFamily: 'monospace',
                color: AppColors.textLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _rawTextOnly {
    final String text = widget.raw.fullText.trim();
    return text.isEmpty ? '(tidak ada teks)' : text;
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.iconBox : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.navy : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ParseWarnings extends StatelessWidget {
  const _ParseWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final String warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      warning,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.itemsTotal,
    required this.total,
    required this.adjustment,
  });

  /// Sum of the parsed line items.
  final int itemsTotal;

  /// Total printed on the receipt.
  final int total;

  /// `total - itemsTotal`; non-zero for receipt-level discounts or fees.
  final int adjustment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          _row('Subtotal item', rupiah(itemsTotal)),
          const SizedBox(height: 10),
          _row(
            'Diskon & biaya lain',
            adjustment == 0
                ? 'Rp0'
                : '${adjustment < 0 ? '-' : '+'}'
                    '${rupiah(adjustment.abs())}',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            children: <Widget>[
              Text(
                'Total struk',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                rupiah(total),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 13, color: AppColors.textLabel),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pilih Kategori',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final Category c in kCategories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconBox(
                      icon: c.icon,
                      size: 40,
                      iconSize: 20,
                      background: c.color.withValues(alpha: 0.14),
                      color: c.color,
                    ),
                    title: Text(
                      c.name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    trailing: c.name == current
                        ? Icon(Icons.check_circle, color: AppColors.green)
                        : null,
                    onTap: () => Navigator.pop(context, c.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
