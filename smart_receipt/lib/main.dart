import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/receipt_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/scan_receipt_screen.dart';

void main() {
  runApp(const SmartReceiptApp());
}

class SmartReceiptApp extends StatelessWidget {
  const SmartReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ReceiptProvider()..loadData()),
      ],
      child: MaterialApp(
        title: 'SmartReceipt',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        home: const DashboardScreen(),
        routes: {
          '/scan': (_) => const ScanReceiptScreen(),
        },
      ),
    );
  }
}
