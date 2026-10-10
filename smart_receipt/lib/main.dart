import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'home_dashboard.dart';

void main() {
  runApp(const SmartReceiptApp());
}

class SmartReceiptApp extends StatelessWidget {
  const SmartReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Receipt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          primary: AppColors.navy,
          surface: AppColors.bg,
        ),
      ),
      home: const HomeDashboard(),
    );
  }
}
