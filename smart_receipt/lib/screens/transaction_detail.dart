import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../widgets/app_widgets.dart';
import '../models/models.dart';
import '../theme/theme_controller.dart';

/// Screen 8 - Transaction Detail.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  final Transaction transaction;

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
              title: 'Detail Transaksi',
              subtitle: transaction.id,
              onBack: () => Navigator.maybePop(context),
              actions: <Widget>[
                CircleIconButton(icon: Icons.delete_outline, onTap: () {}),
                const SizedBox(width: 10),
                CircleIconButton(icon: Icons.edit_outlined, onTap: () {}),
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
          _row('Diskon', '-Rp0'),
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
