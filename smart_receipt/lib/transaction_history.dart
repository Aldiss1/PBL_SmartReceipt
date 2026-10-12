import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_nav.dart';
import 'app_route.dart';
import 'app_widgets.dart';
import 'empty_state.dart';
import 'models.dart';
import 'sample_data.dart';
import 'theme_controller.dart';
import 'transaction_detail.dart';

/// Screen 7 - Transaction History.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  static const List<String> _filters = <String>[
    'Semua',
    'Makanan',
    'Minuman',
    'Rumah Tangga',
    'Perawatan Diri',
    'Transportasi',
  ];

  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _filter = 'Semua';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Transaction> get _results {
    final String q = _query.trim().toLowerCase();
    final List<Transaction> list = kSampleTransactions.where((Transaction t) {
      final bool matchesQuery = q.isEmpty || t.store.toLowerCase().contains(q);
      final bool matchesCategory = _filter == 'Semua' || t.categories.contains(_filter);
      return matchesQuery && matchesCategory;
    }).toList();
    list.sort((Transaction a, Transaction b) => b.date.compareTo(a.date));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final List<Transaction> results = _results;
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
              subtitle: '${kSampleTransactions.length} transaksi tercatat',
              actions: <Widget>[
                CircleIconButton(icon: Icons.tune, onTap: () {}),
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
                itemCount: _filters.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 9),
                itemBuilder: (BuildContext context, int i) {
                  final String f = _filters[i];
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
              child: results.isEmpty
                  ? EmptyStateView(
                      title: 'Transaksi Tidak Ditemukan',
                      message:
                          'Coba ubah kata kunci pencarian atau pilih kategori lain.',
                      actionLabel: 'Reset Filter',
                      onAction: () => setState(() {
                        _search.clear();
                        _query = '';
                        _filter = 'Semua';
                      }),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        22,
                        10,
                        22,
                        24 + AppBottomNav.clearance(context),
                      ),
                      itemCount: results.length,
                      itemBuilder: (BuildContext context, int i) => _HistoryCard(
                        transaction: results[i],
                        onTap: () => Navigator.push(
                          context,
                          appRoute(
                            TransactionDetailScreen(transaction: results[i]),
                          ),
                        ),
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
          hintText: 'Cari toko atau transaksi',
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
  const _HistoryCard({required this.transaction, required this.onTap});

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Category c = categoryByName(transaction.categories.first);
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
                icon: c.icon,
                size: 44,
                iconSize: 22,
                background: c.color.withValues(alpha: 0.14),
                color: c.color,
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(transaction.date),
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        CategoryChip(category: transaction.categories.first, dense: true),
                        if (transaction.categories.length > 1) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(
                            '+${transaction.categories.length - 1}',
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
                    '-${rupiah(transaction.total)}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${transaction.itemCount} item',
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
