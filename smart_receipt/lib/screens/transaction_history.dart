import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import 'empty_state.dart';
import '../models/models.dart';
import '../models/receipt_model.dart' as db;
import '../data/receipt_adapter.dart';
import '../providers/receipt_provider.dart';
import '../theme/theme_controller.dart';
import 'transaction_detail.dart';

/// Screen 7 - Transaction History.
///
/// Reads the receipts saved in SQLite through [ReceiptProvider], so a scan that
/// was just saved appears here immediately.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _filter = 'Semua';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Filter chips: "Semua" plus every category that actually has a receipt.
  List<String> _filtersFor(ReceiptProvider provider) {
    final Set<String> names = <String>{};
    for (final db.Receipt receipt in provider.receipts) {
      for (final db.Transaction item in receipt.transactions) {
        names.add(provider.categoryNameFor(item.categoryId));
      }
    }
    final List<String> sorted = names.toList()..sort();
    return <String>['Semua', ...sorted];
  }

  /// Receipts matching the current search text and category chip.
  List<db.Receipt> _resultsFor(ReceiptProvider provider) {
    final String q = _query.trim().toLowerCase();
    return provider.receipts.where((db.Receipt receipt) {
      final bool matchesQuery = q.isEmpty ||
          receipt.storeName.toLowerCase().contains(q) ||
          receipt.transactions.any(
            (db.Transaction item) => item.itemName.toLowerCase().contains(q),
          );
      final bool matchesCategory = _filter == 'Semua' ||
          receipt.transactions.any(
            (db.Transaction item) =>
                provider.categoryNameFor(item.categoryId) == _filter,
          );
      return matchesQuery && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ReceiptProvider provider = context.watch<ReceiptProvider>();
    final List<String> filters = _filtersFor(provider);
    final List<db.Receipt> results = _resultsFor(provider);
    ThemeScope.watch(context);

    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: FloatingNavBody(
          nav: AppBottomNav(
            activeIndex: 1,
            onSelect: (int i) => navigateTab(context, i),
            onScan: () => openScan(context),
          ),
          child: Column(
            children: <Widget>[
              const AppStatusBar(),
              AppTopBar(
                title: 'Riwayat Transaksi',
                subtitle: '${provider.receipts.length} transaksi tercatat',
                actions: <Widget>[
                  CircleIconButton(
                    icon: Icons.refresh,
                    onTap: provider.loadData,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                child: _SearchField(
                  controller: _search,
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  itemCount: filters.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(width: 9),
                  itemBuilder: (BuildContext context, int i) {
                    final String f = filters[i];
                    final bool active = f == _filter;
                    return _FilterChip(
                      label: f,
                      active: active,
                      onTap: () => setState(() => _filter = f),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _body(provider, results),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ReceiptProvider provider, List<db.Receipt> results) {
    if (provider.isLoading && provider.receipts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.receipts.isEmpty) {
      return EmptyStateView(
        title: 'Belum Ada Transaksi',
        message: 'Mulai catat pengeluaran Anda dengan memindai struk pertama. '
            'Hasilnya akan muncul di sini.',
        actionLabel: 'Scan Struk Sekarang',
        onAction: () => openScan(context),
      );
    }

    if (results.isEmpty) {
      return EmptyStateView(
        title: 'Transaksi Tidak Ditemukan',
        message: 'Coba ubah kata kunci pencarian atau pilih kategori lain.',
        actionLabel: 'Reset Filter',
        onAction: () => setState(() {
          _search.clear();
          _query = '';
          _filter = 'Semua';
        }),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        24 + AppBottomNav.clearance(context),
      ),
      itemCount: results.length,
      itemBuilder: (BuildContext context, int i) {
        final db.Receipt receipt = results[i];
        return _HistoryCard(
          receipt: receipt,
          categoryName: provider.categoryNameFor,
          onTap: () => Navigator.push(
            context,
            appRoute(
              TransactionDetailScreen(
                transaction: toUiTransaction(receipt, provider.categoryNameFor),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 13.5, color: AppColors.textDark),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
          hintText: 'Cari toko atau item',
          hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textMuted),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: active ? AppColors.buttonBg : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppColors.buttonBg : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.onButton : AppColors.textLabel,
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.receipt,
    required this.categoryName,
    required this.onTap,
  });

  final db.Receipt receipt;
  final String Function(int categoryId) categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final List<String> categories = <String>[
      for (final db.Transaction item in receipt.transactions)
        categoryName(item.categoryId),
    ];
    final String primary = categories.isEmpty ? 'Lainnya' : categories.first;
    final int distinct = categories.toSet().length;
    final Category category = categoryByName(primary);

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              IconBox(
                icon: category.icon,
                size: 44,
                iconSize: 22,
                background: category.color.withValues(alpha: 0.14),
                color: category.color,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      receipt.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(receipt.transactionDate),
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        CategoryChip(category: primary, dense: true),
                        if (distinct > 1) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(
                            '+${distinct - 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '-${rupiah(receipt.totalAmount.round())}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${receipt.transactions.length} item',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
