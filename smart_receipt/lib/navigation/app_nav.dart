import 'package:flutter/material.dart';

import '../screens/analysis.dart';
import 'app_route.dart';
import '../screens/home_dashboard.dart';
import '../screens/scan_receipt.dart';
import '../screens/settings.dart';
import '../screens/transaction_history.dart';

/// Switches between the main bottom-navigation tabs.
///
/// Index 0 = Beranda, 1 = Riwayat, 3 = Analisis, 4 = Pengaturan.
void navigateTab(BuildContext context, int index) {
  late final Widget page;
  switch (index) {
    case 0:
      page = const HomeDashboard();
    case 1:
      page = const TransactionHistoryScreen();
    case 3:
      page = const AnalysisScreen();
    case 4:
      page = const SettingsScreen();
    default:
      return;
  }
  Navigator.pushReplacement(context, appRoute(page));
}

/// Opens the scan flow.
void openScan(BuildContext context) {
  Navigator.push(context, appRoute(const ScanReceiptScreen()));
}
