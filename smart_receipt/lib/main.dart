import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'splash_screen.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  runApp(const SmartReceiptApp());
}

class SmartReceiptApp extends StatefulWidget {
  const SmartReceiptApp({super.key});

  @override
  State<SmartReceiptApp> createState() => _SmartReceiptAppState();
}

class _SmartReceiptAppState extends State<SmartReceiptApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeController.setPlatformDark(_deviceIsDark);
    themeController.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _deviceIsDark =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;

  @override
  void didChangePlatformBrightness() {
    themeController.setPlatformDark(_deviceIsDark);
    if (mounted) {
      setState(() {});
    }
  }

  ThemeData _theme(AppPalette palette, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.navy,
        brightness: brightness,
        primary: palette.navy,
        surface: palette.bg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = themeController.isDark;
    return ThemeScope(
      controller: themeController,
      child: MaterialApp(
        title: 'Smart Receipt',
        debugShowCheckedModeBanner: false,
        theme: _theme(AppPalette.light, Brightness.light),
        darkTheme: _theme(AppPalette.dark, Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: const SplashScreen(),
      ),
    );
  }
}
