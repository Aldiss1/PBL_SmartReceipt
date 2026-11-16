import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import '../widgets/receipt_photo_preview.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
import '../ocr/ocr_raw_text.dart';
import '../ocr/ocr_service.dart';
import '../ocr/receipt_classifier.dart';
import '../ocr/receipt_parser.dart';
import '../providers/receipt_provider.dart';
import '../services/correction_training_service.dart';
import '../services/receipt_image_store.dart';
import '../theme/theme_controller.dart';
import 'transaction_saved.dart';

/// Screen 4 - Review Transaction.
///
/// Prefills the editable items with the names/prices/qty recovered by OCR and
/// the categories predicted by the classifier.
///
/// The same screen also edits an already-saved receipt via
/// [ReviewTransactionScreen.edit]; sharing it means a correction made from the
/// detail screen behaves exactly like one made right after a scan.
class ReviewTransactionScreen extends StatefulWidget {
  const ReviewTransactionScreen({
    super.key,
    required this.scan,
    required this.predictions,
  })  : receipt = null,
        categoryName = null;

  /// Opens the screen on a persisted receipt instead of a fresh scan.
  ///
  /// [categoryName] resolves a `categoryId` to its display name; it comes from
  /// [ReceiptProvider] so the names match the rest of the app.
  const ReviewTransactionScreen.edit({
    super.key,
    required this.receipt,
    required this.categoryName,
  })  : scan = null,
        predictions = const <ItemPrediction>[];

  final OcrScanResult? scan;
  final List<ItemPrediction> predictions;

  /// Receipt being edited; null when reviewing a new scan.
  final db.Receipt? receipt;

  /// Maps a stored `categoryId` to a category name. Only used in edit mode.
  final String Function(int categoryId)? categoryName;

  bool get isEditing => receipt != null;

  @override
  State<ReviewTransactionScreen> createState() => _ReviewTransactionScreenState();
}

class _ReviewTransactionScreenState extends State<ReviewTransactionScreen> {
  /// Store name, prefilled from OCR and editable by the user.
  ///
  /// The parser often lifts the store from a logo or a partially read header,
  /// so a wrong or empty name is common; the value saved to SQLite is whatever
  /// ends up here.
  late String _store;

  late final DateTime _date;
  late List<TransactionItem> _items;

  /// Model prediction behind each entry in [_items], index-aligned.
  ///
  /// Null for items the user added manually (or when the classifier returned
  /// fewer predictions than there are parsed lines). Keeping the list the same
  /// length as [_items] is what makes the correction log trustworthy: it is
  /// indexed by item, not by OCR line, so inserting an item cannot pair a
  /// category fix with someone else's prediction.
  late List<ItemPrediction?> _predictions;

  /// Total printed on the receipt (`TOTAL : 33,900`).
  ///
  /// This is authoritative: the sum of the parsed items can legitimately differ
  /// because of receipt-level discounts, deposits or rounding. Recomputing the
  /// total from items silently turns a parsing mistake into a wrong amount.
  late final int _receiptTotal;

  /// Persists user category fixes so they can feed the next training run.
  final CorrectionTrainingService _corrections = CorrectionTrainingService();

  /// Whether the receipt photo is shown at full height on the review screen.
  ///
  /// Expanded by default: the whole point of this screen is comparing the OCR
  /// output against the print. It can be collapsed to a slim strip when the user
  /// wants the item list closer to the top.
  bool _photoExpanded = true;

  @override
  void initState() {
    super.initState();
    final db.Receipt? existing = widget.receipt;
    if (existing != null) {
      _initFromReceipt(existing);
      return;
    }
    _initFromScan(widget.scan!);
  }

  /// Loads an already-saved receipt for editing.
  ///
  /// Every item gets a null prediction: the model output that produced the
  /// stored category was never saved, so there is nothing to compare against and
  /// nothing to log as a correction.
  void _initFromReceipt(db.Receipt receipt) {
    _store = receipt.storeName;
    _date = receipt.transactionDate;
    _receiptTotal = receipt.totalAmount.round();
    _items = <TransactionItem>[
      for (final db.Transaction item in receipt.transactions)
        TransactionItem(
          name: item.itemName,
          qty: item.quantity,
          price: item.unitPrice.round(),
          category: widget.categoryName?.call(item.categoryId) ?? 'Lainnya',
        ),
    ];
    _predictions = List<ItemPrediction?>.filled(_items.length, null);
  }

  void _initFromScan(OcrScanResult scan) {
    _store = scan.parsed.store;
    _date = scan.parsed.date ?? DateTime.now();
    _receiptTotal = scan.parsed.total;

    final List<ParsedItem> parsedItems = scan.parsed.items;
    _items = <TransactionItem>[];
    _predictions = <ItemPrediction?>[];
    for (int i = 0; i < parsedItems.length; i++) {
      final ParsedItem p = parsedItems[i];
      final ItemPrediction? prediction =
          i < widget.predictions.length ? widget.predictions[i] : null;
      final String category = prediction?.category ?? 'Lainnya';
      _items.add(
        TransactionItem(
          name: p.name,
          qty: p.qty,
          price: p.price,
          category: category,
        ),
      );
      _predictions.add(prediction);
    }
  }

  int get _itemsTotal =>
      _items.fold(0, (int sum, TransactionItem i) => sum + i.subtotal);

  /// Difference between the printed total and the parsed items.
  ///
  /// Zero when everything lines up; non-zero when the receipt applied a
  /// discount/fee we did not model, or when the parser missed/misread a line.
  int get _totalAdjustment => _receiptTotal - _itemsTotal;

  Future<void> _editStore() async {
    final String? name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _StoreEditorSheet(initial: _store),
      ),
    );
    if (name == null || !mounted || name == _store) {
      return;
    }
    setState(() => _store = name);
  }

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
      // Editing a saved receipt has no model prediction behind it, so there is
      // no disagreement to learn from.
      if (!widget.isEditing) {
        _recordCorrection(index, old, selected);
      }
    }
  }

  /// Opens the item editor and appends the result.
  ///
  /// The printed receipt total stays untouched on purpose: a hand-added item is
  /// not on the receipt, so it shows up as a difference in [._totalAdjustment]
  /// rather than silently rewriting what the paper says.
  Future<void> _addItem() async {
    final TransactionItem? item = await showModalBottomSheet<TransactionItem>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _ItemEditorSheet(),
      ),
    );
    if (item == null || !mounted) {
      return;
    }
    setState(() {
      _items.add(item);
      // No model prediction backs a manual item.
      _predictions.add(null);
    });
  }

  /// Opens the item editor prefilled with [index] and applies the result.
  ///
  /// A category change made here is recorded exactly like a chip tap, so fixing
  /// qty and category in one go still produces training data. The same
  /// [._totalAdjustment] rule applies: the printed total is never rewritten.
  Future<void> _editItem(int index) async {
    final TransactionItem old = _items[index];
    final TransactionItem? updated =
        await showModalBottomSheet<TransactionItem>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ItemEditorSheet(initial: old),
      ),
    );
    if (updated == null || !mounted) {
      return;
    }
    setState(() => _items[index] = updated);
    if (updated.category != old.category && !widget.isEditing) {
      _recordCorrection(index, old, updated.category);
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      if (index < _predictions.length) {
        _predictions.removeAt(index);
      }
    });
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
  /// holds genuine disagreements. Items the user typed in by hand have no
  /// prediction to disagree with, so their label is stored as-is.
  Future<void> _recordCategoryCorrections() async {
    for (int i = 0; i < _items.length; i++) {
      final ItemPrediction? prediction =
          i < _predictions.length ? _predictions[i] : null;
      final TransactionItem item = _items[i];
      if (prediction != null && item.category == prediction.category) {
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
            AppTopBar(
              title: widget.isEditing ? 'Edit Transaksi' : 'Review Transaksi',
              subtitle: widget.isEditing
                  ? 'Perbaiki data transaksi tersimpan'
                  : 'Periksa & koreksi hasil OCR',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _StoreCard(store: _store, date: _date, onEdit: _editStore),
                    if (widget.scan != null &&
                        widget.scan!.parsed.warnings.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _ParseWarnings(warnings: widget.scan!.parsed.warnings),
                    ],
                    const SizedBox(height: 18),
                    _ReceiptPhotoSection(
                      imagePath:
                          widget.scan?.sourcePath ?? widget.receipt?.imagePath,
                      expanded: _photoExpanded,
                      onToggle: () =>
                          setState(() => _photoExpanded = !_photoExpanded),
                    ),
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
                      _ItemCard(
                        item: _items[i],
                        onEdit: () => _editItem(i),
                        onCategoryTap: () => _editCategory(i),
                        onDelete: () => _removeItem(i),
                      ),
                    if (_items.isEmpty) const _EmptyItemsNotice(),
                    const SizedBox(height: 4),
                    SecondaryButton(
                      label: 'Tambah Item',
                      icon: Icons.add,
                      onPressed: _addItem,
                    ),
                    const SizedBox(height: 18),
                    _TotalCard(
                      itemsTotal: _itemsTotal,
                      total: _receiptTotal,
                      adjustment: _totalAdjustment,
                    ),
                    const SizedBox(height: 14),
                    if (widget.scan != null)
                      _OcrTextViewer(
                        raw: widget.scan!.raw,
                        parsed: widget.scan!.parsed,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: PrimaryButton(
                label: widget.isEditing
                    ? 'Simpan Perubahan'
                    : 'Simpan Transaksi',
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
    if (widget.isEditing) {
      await _saveEdits();
      return;
    }

    final ReceiptProvider provider =
        Provider.of<ReceiptProvider>(context, listen: false);

    // Copy the capture out of the temporary directory before it is referenced
    // by a row: iOS purges temp files, which would leave the history preview
    // pointing at nothing.
    final String? storedImagePath =
        await ReceiptImageStore().persist(widget.scan!.sourcePath);

    final db.Receipt receipt = db.Receipt(
      storeName: _store,
      transactionDate: _date,
      totalAmount: _receiptTotal.toDouble(),
      taxAmount: widget.scan!.parsed.taxTotal.toDouble(),
      subtotal: _itemsTotal.toDouble(),
      paymentMethod: widget.scan!.parsed.paymentMethod,
      imagePath: storedImagePath,
      ocrText: widget.scan!.raw.fullText,
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
          total: widget.scan!.parsed.total,
          paymentMethod: widget.scan!.parsed.paymentMethod,
        ),
      ),
    );
  }

  /// Writes the edits back over the stored receipt and pops with `true`.
  ///
  /// Everything the capture produced (photo, OCR text, payment method, created
  /// date) is carried over untouched: this screen edits the transaction, not the
  /// evidence behind it. Popping with `true` is what tells the detail screen to
  /// reload its copy.
  Future<void> _saveEdits() async {
    final db.Receipt existing = widget.receipt!;
    final ReceiptProvider provider =
        Provider.of<ReceiptProvider>(context, listen: false);

    final db.Receipt updated = db.Receipt(
      id: existing.id,
      storeName: _store,
      storeAddress: existing.storeAddress,
      transactionDate: _date,
      totalAmount: _receiptTotal.toDouble(),
      taxAmount: existing.taxAmount,
      subtotal: _itemsTotal.toDouble(),
      paymentMethod: existing.paymentMethod,
      receiptNumber: existing.receiptNumber,
      imagePath: existing.imagePath,
      ocrText: existing.ocrText,
      status: existing.status,
      notes: existing.notes,
      createdAt: existing.createdAt,
      transactions: <db.Transaction>[
        for (final TransactionItem i in _items)
          db.Transaction(
            receiptId: existing.id ?? 0,
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
      await provider.updateReceiptWithItems(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan perubahan: $error')),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
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

/// Receipt photo shown next to the corrections, collapsed by default.
///
/// OCR mistakes are far easier to fix while looking at the print, but a
/// permanently full-height photo pushes the item list off screen. So the card
/// keeps a compact strip visible at all times (enough to confirm the right
/// photo was captured) and expands to a readable height on demand.
class _ReceiptPhotoSection extends StatelessWidget {
  const _ReceiptPhotoSection({
    required this.imagePath,
    required this.expanded,
    required this.onToggle,
  });

  final String? imagePath;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bool available =
        imagePath != null &&
        imagePath!.isNotEmpty &&
        File(imagePath!).existsSync();
    if (!available) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: 'Foto Struk',
          trailing: TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  expanded ? 'Ringkas' : 'Tampilkan',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.orange,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ReceiptPhotoPreview(
          imagePath: imagePath,
          heroTag: 'review-receipt-photo',
          height: expanded ? 420 : 96,
        ),
      ],
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.store,
    required this.date,
    required this.onEdit,
  });

  final String store;
  final DateTime date;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onEdit,
    required this.onCategoryTap,
    required this.onDelete,
  });

  final TransactionItem item;

  /// Tapping the card opens the item editor (name, qty, price, category).
  final VoidCallback onEdit;

  /// Tapping the category chip opens only the category picker.
  final VoidCallback onCategoryTap;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(item.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: AppColors.amber,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.qty} × ${rupiah(item.price)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: onCategoryTap,
                        borderRadius: BorderRadius.circular(8),
                        child: CategoryChip(
                          category: item.category,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      rupiah(item.subtotal),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

/// Sheet used to rename the store pulled from OCR.
///
/// Returns the trimmed name, or null when the user backs out.
class _StoreEditorSheet extends StatefulWidget {
  const _StoreEditorSheet({required this.initial});

  final String initial;

  @override
  State<_StoreEditorSheet> createState() => _StoreEditorSheetState();
}

class _StoreEditorSheetState extends State<_StoreEditorSheet> {
  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nama toko wajib diisi');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Edit Nama Toko',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Perbaiki nama toko bila hasil OCR keliru.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              _SheetField(
                controller: _name,
                hint: 'Contoh: Indomaret',
                error: _error,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Simpan Nama Toko',
                icon: Icons.check_circle_outline,
                onPressed: _submit,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Batal',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sheet used to add or edit a line item.
///
/// Returns the resulting [TransactionItem], or null when the user backs out.
/// Passing [initial] switches the sheet into edit mode: the fields are
/// prefilled and the button reads "Simpan Perubahan".
class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({this.initial});

  final TransactionItem? initial;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late int _qty;
  late String _category;
  String? _nameError;
  String? _priceError;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final TransactionItem? initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _price = TextEditingController(
      text: initial == null ? '' : '${initial.price}',
    );
    _qty = initial?.qty ?? 1;
    _category = initial?.category ?? 'Lainnya';
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  int get _priceValue => int.tryParse(_price.text) ?? 0;

  int get _subtotal => _qty * _priceValue;

  Future<void> _pickCategory() async {
    final String? selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => _CategorySheet(current: _category),
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() => _category = selected);
  }

  void _submit() {
    final String name = _name.text.trim();
    final int price = _priceValue;
    setState(() {
      _nameError = name.isEmpty ? 'Nama item wajib diisi' : null;
      _priceError = price <= 0 ? 'Harga harus lebih dari 0' : null;
    });
    if (_nameError != null || _priceError != null) {
      return;
    }
    Navigator.pop(
      context,
      TransactionItem(
        name: name,
        qty: _qty,
        price: price,
        category: _category,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEditing ? 'Edit Item' : 'Tambah Item',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isEditing
                    ? 'Perbaiki nama, jumlah, atau harga item.'
                    : 'Lengkapi nama, jumlah, dan harga item.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              _SheetField(
                label: 'Nama item',
                controller: _name,
                hint: 'Contoh: Indomie Goreng',
                error: _nameError,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SheetLabel('Jumlah'),
                        const SizedBox(height: 8),
                        _QtyStepper(
                          value: _qty,
                          onChanged: (int v) => setState(() => _qty = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _SheetField(
                      label: 'Harga satuan',
                      controller: _price,
                      hint: '0',
                      prefixText: 'Rp ',
                      error: _priceError,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (String _) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SheetLabel('Kategori'),
              const SizedBox(height: 8),
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _pickCategory,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        CategoryChip(category: _category),
                        const Spacer(),
                        Text(
                          'Ubah',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.orange,
                          ),
                        ),
                        Icon(Icons.expand_more, size: 16, color: AppColors.orange),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.iconBox,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'Subtotal',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textLabel,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      rupiah(_subtotal),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: _isEditing ? 'Simpan Perubahan' : 'Tambah Item',
                icon: Icons.check_circle_outline,
                onPressed: _submit,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Batal',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hint,
    this.label,
    this.error,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onSubmitted,
    this.prefixText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;
  final String? error;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? prefixText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          SheetLabel(label!),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: error == null ? AppColors.border : AppColors.red,
              width: 1.2,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            autofocus: autofocus,
            textCapitalization: textCapitalization,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
              prefixText: prefixText,
              prefixStyle: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textLabel,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            error!,
            style: TextStyle(fontSize: 11.5, color: AppColors.red),
          ),
        ],
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          _stepButton(
            icon: Icons.remove,
            onTap: value > 1 ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          _stepButton(
            icon: Icons.add,
            onTap: value < 999 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 48,
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? AppColors.textMuted : AppColors.textDark,
        ),
      ),
    );
  }
}
