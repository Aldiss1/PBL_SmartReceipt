import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
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

  /// Persists user category fixes so they can feed the next training run.
  final CorrectionTrainingService _corrections = CorrectionTrainingService();

  @override
  void initState() {
    super.initState();
    _store = widget.scan.parsed.store;
    _date = widget.scan.parsed.date ?? DateTime.now();
    _predictions = widget.predictions;

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

  int get _total =>
      _items.fold(0, (int sum, TransactionItem i) => sum + i.subtotal);

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
                    _TotalCard(subtotal: _total, total: _total),
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
      totalAmount: _total.toDouble(),
      taxAmount: 0,
      subtotal: _total.toDouble(),
      paymentMethod: widget.scan.parsed.paymentMethod,
      imagePath: widget.scan.sourcePath,
      ocrText: widget.scan.raw.fullText,
      status: 'completed',
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

  /// Maps a UI category name to the SQLite seed category id used by the
  /// pulled database layer.
  int _categoryIdFor(String category) {
    switch (category) {
      case 'Makanan':
      case 'Minuman':
        return 1;
      case 'Transportasi':
        return 2;
      case 'Rumah Tangga':
      case 'Perawatan Diri':
      case 'Pakaian':
        return 3;
      case 'Kesehatan':
        return 6;
      case 'Elektronik':
        return 7;
      default:
        return 8;
    }
  }
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

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.subtotal, required this.total});

  final int subtotal;
  final int total;

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
          _row('Subtotal', rupiah(subtotal)),
          const SizedBox(height: 10),
          _row('Diskon', '-Rp0'),
          const SizedBox(height: 10),
          _row('Pajak & biaya', 'Rp0'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            children: <Widget>[
              Text(
                'Total',
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
