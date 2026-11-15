import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../navigation/app_nav.dart';
import '../navigation/app_route.dart';
import '../widgets/app_widgets.dart';
import 'empty_state.dart';
import '../models/models.dart';
import '../models/receipt_filter.dart';
import '../models/receipt_model.dart' as db;
import '../data/receipt_adapter.dart';
import '../providers/receipt_provider.dart';
import '../services/receipt_export_service.dart';
import '../services/receipt_image_store.dart';
import '../theme/theme_controller.dart';
import 'transaction_detail.dart';
import 'transaction_filter_sheet.dart';

/// Screen 7 - Transaction History.
///
/// Reads the receipts saved in SQLite through [ReceiptProvider], so a scan that
/// was just saved appears here immediately along with its local receipt photo.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key, this.exporter});

  /// Overrides the CSV writer. Only tests pass this: the real one talks to
  /// `path_provider`, whose platform channel never answers in a widget test.
  final ReceiptExportService? exporter;

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final TextEditingController _search = TextEditingController();
  late final ReceiptExportService _exporter =
      widget.exporter ?? ReceiptExportService();

  /// Every refinement the list currently applies, search text included.
  ReceiptFilter _filter = const ReceiptFilter();

  /// Guards against a second tap while the file is being written and shared.
  bool _exporting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Writes the receipts currently on screen to CSV and hands the file to the
  /// system share sheet.
  ///
  /// Exports [_resultsFor] rather than every receipt: the search box and the
  /// category chip are already the user's own selection, and ignoring them would
  /// make "export" quietly contradict "export what I see".
  Future<void> _export(ReceiptProvider provider) async {
    if (_exporting) {
      return;
    }
    final List<db.Receipt> receipts = _resultsFor(provider);
    if (receipts.isEmpty) {
      return;
    }

    setState(() => _exporting = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final File file = await _exporter.writeCsv(
        receipts,
        provider.categoryNameFor,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
          subject: 'Transaksi Smart Receipt',
          text: '${receipts.length} transaksi dari Smart Receipt.',
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal mengekspor transaksi: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
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

  /// Receipts matching the search box, the category chips and the advanced
  /// filter sheet, in the order the provider returned them.
  List<db.Receipt> _resultsFor(ReceiptProvider provider) =>
      _filter.apply(provider.receipts, provider.categoryNameFor);

  /// Store names present in the saved receipts, for the sheet's store pills.
  List<String> _storesFor(ReceiptProvider provider) {
    final Set<String> names = <String>{
      for (final db.Receipt receipt in provider.receipts)
        if (receipt.storeName.trim().isNotEmpty) receipt.storeName.trim(),
    };
    return names.toList()..sort();
  }

  Future<void> _openFilterSheet(ReceiptProvider provider) async {
    final ReceiptFilter? next = await showTransactionFilterSheet(
      context,
      current: _filter,
      stores: _storesFor(provider),
    );
    if (next != null && mounted) {
      setState(() => _filter = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReceiptProvider provider = context.watch<ReceiptProvider>();
    final List<String> filters = _filtersFor(provider);
    final List<db.Receipt> results = _resultsFor(provider);
    final int total = provider.receipts.length;
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
                // Showing "3 dari 12" is the cheapest way to make a filter
                // visible: the sheet is closed most of the time, and a silently
                // shortened list looks like lost data.
                subtitle: results.length == total
                    ? '$total transaksi tercatat'
                    : '${results.length} dari $total transaksi',
                actions: <Widget>[
                  // Hidden when there is nothing to export: a button that
                  // silently does nothing is worse than no button.
                  if (results.isNotEmpty) ...<Widget>[
                    CircleIconButton(
                      icon: _exporting ? Icons.hourglass_top : Icons.ios_share,
                      onTap: () => _export(provider),
                    ),
                    const SizedBox(width: 10),
                  ],
                  CircleIconButton(
                    icon: Icons.refresh,
                    onTap: provider.loadData,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _SearchField(
                        controller: _search,
                        onChanged: (String v) => setState(
                          () => _filter = _filter.copyWith(query: v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _FilterButton(
                      count: _filter.advancedCount,
                      onTap: () => _openFilterSheet(provider),
                    ),
                  ],
                ),
              ),
              if (_filter.hasAdvancedFilters) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  child: _ActiveFilterBar(
                    summary: _filter.summary,
                    onClear: () =>
                        setState(() => _filter = _filter.clearAdvanced()),
                  ),
                ),
              ],
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
                    return FilterPill(
                      label: f,
                      active: f == _filter.category,
                      onTap: () => setState(
                        () => _filter = _filter.copyWith(category: f),
                      ),
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
        message: 'Coba ubah kata kunci, pilih kategori lain, atau longgarkan '
            'filter lanjutan.',
        actionLabel: 'Reset Filter',
        onAction: () => setState(() {
          _search.clear();
          _filter = const ReceiptFilter();
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _HistoryCard(
            receipt: receipt,
            categoryName: provider.categoryNameFor,
            onTap: () => Navigator.push(
              context,
              appRoute(
                TransactionDetailScreen(
                  transaction:
                      toUiTransaction(receipt, provider.categoryNameFor),
                ),
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
          contentPadding:
              const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
          hintText: 'Cari toko atau item',
          hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textMuted),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// Square button beside the search box that opens the advanced filter sheet.
///
/// [count] badges how many advanced groups are active, so a filter set weeks ago
/// cannot be forgotten and mistaken for an empty history.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = count > 0;
    return Semantics(
      button: true,
      label: 'Filter lanjutan',
      child: Material(
        color: active ? AppColors.buttonBg : AppColors.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Center(
                  child: Icon(
                    Icons.tune,
                    size: 20,
                    color: active ? AppColors.onButton : AppColors.textDark,
                  ),
                ),
                if (active)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 15,
                      height: 15,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 1.2),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3A2A00),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One-line reminder of the advanced filters plus a shortcut to drop them.
class _ActiveFilterBar extends StatelessWidget {
  const _ActiveFilterBar({required this.summary, required this.onClear});

  final String summary;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.filter_alt_outlined, size: 14, color: AppColors.orange),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textLabel,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.close, size: 15, color: AppColors.textMuted),
            ),
          ),
        ],
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
    final bool hasPhoto = ReceiptImageStore.exists(receipt.imagePath);

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
              if (hasPhoto)
                _ReceiptThumbnail(file: File(receipt.imagePath!))
              else
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
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textMuted),
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
                        if (hasPhoto) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.iconBox,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.image_outlined,
                                  size: 11,
                                  color: AppColors.amber,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Foto',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textLabel,
                                  ),
                                ),
                              ],
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
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.textMuted),
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

class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: 160,
              ),
            ),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.card, width: 1.5),
              ),
              child: const Icon(
                Icons.receipt_long,
                size: 10,
                color: Color(0xFF3A2A00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
