import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_receipt/app_route.dart';

void main() {
  testWidgets('push is instant but pop keeps its animation', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Center(child: Text('A'))),
      ),
    );

    final ModalRoute<void> route =
        appRoute<void>(const Scaffold(body: Center(child: Text('B'))))
            as ModalRoute<void>;
    expect(route.transitionDuration, Duration.zero);

    navKey.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // Instant push: the new page is already fully settled.
    expect(find.text('B'), findsOneWidget);
    expect(route.animation!.value, 1.0);
    expect(tester.hasRunningAnimations, isFalse);

    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Animated pop: the page is still on screen and mid-transition.
    expect(find.text('B'), findsOneWidget);
    expect(route.animation!.value, greaterThan(0.0));
    expect(route.animation!.value, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
