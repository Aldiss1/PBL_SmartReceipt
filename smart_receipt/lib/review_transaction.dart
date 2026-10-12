import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_route.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'sample_data.dart';
import 'theme_controller.dart';
import 'transaction_saved.dart';

/// Screen 4 - Review Transaction.
class ReviewTransactionScreen extends StatefulWidget {
  const ReviewTransactionScreen({super.key});

  @override
  State<ReviewTransactionScreen> createState() => _ReviewTransactionScreenState();
}

class _ReviewTransactionScreenState extends State<ReviewTransactionScreen> {
  late final String _store;
  late final DateTime _date;
  late List<TransactionItem> _items;

  @override
  void initState() {
    super.initState();
    final Transaction t = kSampleTransactions.first;
    _store = t.store;
    _date = t.date;
    _items = List<TransactionItem>.of(t.items);
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
                onPressed: () => Navigator.pushReplacement(
                  context,
                  appRoute(const TransactionSavedScreen()),
                ),
              ),
            ),
          ],
        ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
