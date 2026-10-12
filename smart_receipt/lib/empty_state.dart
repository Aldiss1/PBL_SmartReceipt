import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_nav.dart';
import 'app_widgets.dart';
import 'theme_controller.dart';

/// Screen 11 - Empty State (reusable view + full screen).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    this.title = 'Belum Ada Transaksi',
    this.message =
        'Mulai catat pengeluaran Anda dengan memindai struk pertama. Hasilnya akan muncul di sini.',
    this.actionLabel = 'Scan Struk Sekarang',
    this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    color: AppColors.iconBox,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    size: 58,
                    color: AppColors.iconMuted,
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 8,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 26,
                      color: Color(0xFF3A2A00),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 26),
            PrimaryButton(
              label: actionLabel,
              icon: Icons.photo_camera_outlined,
              expanded: false,
              onPressed: onAction ?? () => openScan(context),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyStateScreen extends StatelessWidget {
  const EmptyStateScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: AppBottomNav.clearance(context),
                ),
                child: const EmptyStateView(),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
