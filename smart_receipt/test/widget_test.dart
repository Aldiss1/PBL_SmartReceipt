import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/main.dart';

void main() {
  testWidgets('Home dashboard renders its main sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmartReceiptApp());

    expect(find.text('Beranda'), findsWidgets);
    expect(find.text('Selamat datang, Rian'), findsOneWidget);
    expect(find.text('Rp1.420.000'), findsOneWidget);
    expect(find.text('Pengeluaran per Kategori'), findsOneWidget);
    expect(find.text('Transaksi Terbaru'), findsOneWidget);
    expect(find.text('Indomaret'), findsOneWidget);
  });
}
