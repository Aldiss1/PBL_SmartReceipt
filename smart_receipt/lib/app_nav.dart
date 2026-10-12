import 'package:flutter/material.dart';

import 'analysis.dart';
import 'home_dashboard.dart';
import 'scan_receipt.dart';
import 'settings.dart';
import 'transaction_history.dart';

Route<void> _route(Widget page) =>
    MaterialPageRoute<void>(builder: (BuildContext context) => page);

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
  Navigator.pushReplacement(context, _route(page));
}

/// Opens the scan flow.
void openScan(BuildContext context) {
  Navigator.push(context, _route(const ScanReceiptScreen()));
}
