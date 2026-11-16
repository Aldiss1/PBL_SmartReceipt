import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/app_route.dart';
import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../widgets/app_widgets.dart';
import '../widgets/receipt_photo_preview.dart';
import '../data/receipt_adapter.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
import '../providers/receipt_provider.dart';
import '../services/receipt_image_store.dart';
import '../theme/theme_controller.dart';
import 'review_transaction.dart';

/// Screen 8 - Transaction Detail.
class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  final Transaction transaction;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  /// Kept in state so the screen can show the edited values after the review
  /// screen returns; the constructor argument is only the entry point.
  late Transaction _transaction = widget.transaction;

  /// Opens the shared review screen in edit mode, then reloads this receipt.
  ///
  /// The stored row is re-read from the provider instead of patching the local
  /// copy: the edit screen can add and remove items, so the totals have to come
  /// from one place.
  Future<void> _edit() async {
    final int? receiptId = _transaction.receiptId;
    if (receiptId == null) {
      return;
    }

    final ReceiptProvider provider = context.read<ReceiptProvider>();
    final db.Receipt? receipt =
        await provider.getReceiptWithTransactions(receiptId);
    if (!mounted) {
      return;
    }
    if (receipt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi tidak ditemukan.')),
      );
      return;
    }

    final bool? saved = await Navigator.push<bool>(
      context,
      appRoute(
        ReviewTransactionScreen.edit(
          receipt: receipt,
          categoryName: provider.categoryNameFor,
        ),
      ),
    );
    if (saved != true || !mounted) {
      return;
    }

    final db.Receipt? refreshed =
        await provider.getReceiptWithTransactions(receiptId);
    if (!mounted) {
      return;
    }
    if (refreshed != null) {
      setState(() {
        _transaction = toUiTransaction(refreshed, provider.categoryNameFor);
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perubahan transaksi disimpan.')),
    );
  }

  /// Deletes the receipt, its items and its stored photo, then leaves the
  /// screen.
  ///
  /// Nothing here is recoverable, so the confirmation dialog names the store and
  /// amount: the two details that tell the user they picked the right row.
  Future<void> _delete() async {
    final int? receiptId = _transaction.receiptId;
    if (receiptId == null) {
      return;
    }

    final bool confirmed = await _confirmDelete() ?? false;
    if (!confirmed || !mounted) {
      return;
    }

    final ReceiptProvider provider = context.read<ReceiptProvider>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    try {
      await provider.deleteReceipt(receiptId);
    } catch (error) {
      // A failed delete must leave the user on the screen with the receipt
      // still listed, not on a stale detail page.
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menghapus transaksi: $error')),
      );
      return;
    }

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Transaksi ${_transaction.store} dihapus.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Hapus transaksi?',
          style: TextStyle(color: AppColors.textDark),
        ),
        content: Text(
          '${_transaction.store} • ${rupiah(_transaction.total)} akan dihapus '
          'beserta item dan foto struknya. Tindakan ini tidak bisa dibatalkan.',
          style: TextStyle(color: AppColors.textLabel, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Batal',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Hapus',
              style: TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Transaction transaction = _transaction;
    ThemeScope.watch(context);
    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AppTopBar(
              title: 'Detail Transaksi',
              subtitle: transaction.id,
              onBack: () => Navigator.maybePop(context),
              actions: <Widget>[
                if (transaction.receiptId != null) ...<Widget>[
                  CircleIconButton(
                    icon: Icons.delete_outline,
                    onTap: _delete,
                  ),
                  const SizedBox(width: 10),
                  CircleIconButton(
                    icon: Icons.edit_outlined,
                    onTap: _edit,
                  ),
                ],
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ReceiptHeader(transaction: transaction),
                    const SizedBox(height: 18),
                    _ReceiptPhotoCard(transaction: transaction),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Rincian Item',
                      trailing: Text(
                        '${transaction.itemCount} item',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < transaction.items.length; i++)
                            _ItemRow(
                              item: transaction.items[i],
                              last: i == transaction.items.length - 1,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SummaryCard(transaction: transaction),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
              child: PrimaryButton(
                label: 'Scan Struk Baru',
                icon: Icons.photo_camera_outlined,
                onPressed: () => openScan(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptHeader extends StatelessWidget {
  const _ReceiptHeader({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final List<Color>? bannerGradient = AppColors.spendBannerGradient;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.spendBanner,
        gradient: bannerGradient == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bannerGradient,
                stops: const <double>[0.0, 0.5, 1.0],
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.spendBannerObjectBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  size: 23,
                  color: AppColors.spendBannerAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      transaction.store,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSpendBanner,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatDateTime(transaction.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSpendBannerMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Total Pembayaran',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onSpendBannerMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            rupiah(transaction.total),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.onSpendBanner,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _Badge(icon: Icons.credit_card, label: transaction.paymentMethod),
              const SizedBox(width: 8),
              _Badge(icon: Icons.receipt_long_outlined, label: '${transaction.itemCount} item'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Preview of the receipt photo that was captured for this transaction.
///
/// Tapping opens a full-screen, pinch-zoomable view — receipt text is far too
/// small to read from a thumbnail, and verifying a saved total against the
/// printed one is the main reason to look at the original at all.
class _ReceiptPhotoCard extends StatelessWidget {
  const _ReceiptPhotoCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final String? path = transaction.imagePath;
    if (path == null || path.isEmpty) {
      return const SizedBox.shrink();
    }
    final bool available = ReceiptImageStore.exists(path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: 'Foto Struk',
          trailing: available
              ? Text(
                  'Ketuk untuk memperbesar',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (!available)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 20,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Foto struk tidak tersedia.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ReceiptPhotoPreview(
            imagePath: path,
            heroTag: 'receipt-photo-${transaction.id}',
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.spendBannerObjectBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: AppColors.spendBannerAccent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.onSpendBannerSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.last});

  final TransactionItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(item.category);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: <Widget>[
              IconBox(
                icon: c.icon,
                size: 38,
                iconSize: 19,
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.qty} × ${rupiah(item.price)} • ${item.category}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rupiah(item.subtotal),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.transaction});

  final Transaction transaction;

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
          _row('Subtotal', rupiah(transaction.total)),
          const SizedBox(height: 12),
          _row('Kategori', '${transaction.categories.length} kategori'),
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
                rupiah(transaction.total),
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
