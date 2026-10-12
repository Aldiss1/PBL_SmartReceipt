import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/theme/app_colors.dart';
import 'package:smart_receipt/navigation/app_nav.dart';
import 'package:smart_receipt/screens/home_dashboard.dart';
import 'package:smart_receipt/main.dart';
import 'package:smart_receipt/theme/theme_controller.dart';

void main() {
  testWidgets('toggling dark mode repaints an already-pushed screen', (
    WidgetTester tester,
  ) async {
    themeController.setDark(true);
    await tester.pumpWidget(const SmartReceiptApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Selamat datang, Rian'), findsOneWidget);

    Color scaffoldBg() =>
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

    Color titleColor() => tester
        .widget<Text>(find.text('Transaksi Terbaru'))
        .style!
        .color!;

    expect(scaffoldBg(), AppPalette.dark.bg);
    expect(titleColor(), AppPalette.dark.textDark);

    themeController.setDark(false);
    await tester.pumpAndSettle();

    expect(scaffoldBg(), AppPalette.light.bg);
    expect(titleColor(), AppPalette.light.textDark);

    themeController.setDark(true);
    await tester.pumpAndSettle();

    expect(scaffoldBg(), AppPalette.dark.bg);
  });

  testWidgets('settings switch flips the whole app theme', (
    WidgetTester tester,
  ) async {
    themeController.setDark(true);
    await tester.pumpWidget(const SmartReceiptApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    navigateTab(tester.element(find.byType(HomeDashboard)), 4);
    await tester.pumpAndSettle();

    expect(find.text('Mode Gelap'), findsOneWidget);

    Color bg() =>
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

    expect(bg(), AppPalette.dark.bg);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(bg(), AppPalette.light.bg);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(bg(), AppPalette.dark.bg);
  });
}
