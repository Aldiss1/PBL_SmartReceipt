import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_nav.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'theme_controller.dart';

/// Screen 6 - Transaction Saved.
///
/// Confirms the transaction that was just extracted by OCR and saved.
class TransactionSavedScreen extends StatelessWidget {
  const TransactionSavedScreen({
    super.key,
    required this.store,
    required this.date,
    required this.items,
    this.paymentMethod = 'Tunai',
  });

  final String store;
  final DateTime date;
  final List<TransactionItem> items;
  final String paymentMethod;

  int get _total =>
      items.fold(0, (int sum, TransactionItem i) => sum + i.subtotal);

  @override
  Widget build(BuildContext context) {
    ThemeScope.watch(context);

    return Scaffold(
      key: ValueKey<AppPalette>(AppColors.palette),
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            children: <Widget>[
              const AppStatusBar(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 28),
                      Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          color: AppColors.greenSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          size: 62,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Transaksi Tersimpan',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Data struk berhasil diproses dan ditambahkan ke riwayat pengeluaran.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: <Widget>[
                            _row('Toko', store),
                            const SizedBox(height: 12),
                            _row('Tanggal', formatDate(date)),
                            const SizedBox(height: 12),
                            _row('Jumlah Item', '${items.length} item'),
                            const SizedBox(height: 12),
                            _row('Metode', paymentMethod),
                             Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1, color: AppColors.border),
                            ),
                            Row(
                              children: <Widget>[
                                Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  rupiah(_total),
                                  style:  TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                label: 'Lihat Riwayat',
                icon: Icons.receipt_long_outlined,
                onPressed: () => navigateTab(context, 1),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Kembali ke Beranda',
                onPressed: () => navigateTab(context, 0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(String label, String value) {
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
