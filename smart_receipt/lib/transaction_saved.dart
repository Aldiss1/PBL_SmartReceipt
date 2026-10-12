import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_nav.dart';
import 'app_widgets.dart';
import 'models.dart';
import 'sample_data.dart';

/// Screen 6 - Transaction Saved.
class TransactionSavedScreen extends StatelessWidget {
  const TransactionSavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Transaction t = kSampleTransactions.first;

    return Scaffold(
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
                        decoration: const BoxDecoration(
                          color: AppColors.greenSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          size: 62,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Transaksi Tersimpan',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: <Widget>[
                            _row('Toko', t.store),
                            const SizedBox(height: 12),
                            _row('Tanggal', formatDate(t.date)),
                            const SizedBox(height: 12),
                            _row('Jumlah Item', '${t.itemCount} item'),
                            const SizedBox(height: 12),
                            _row('Metode', t.paymentMethod),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1, color: AppColors.border),
                            ),
                            Row(
                              children: <Widget>[
                                const Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  rupiah(t.total),
                                  style: const TextStyle(
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
          style: const TextStyle(fontSize: 13, color: AppColors.textLabel),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}
