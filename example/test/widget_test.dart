import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network_example/main.dart';

void main() {
  testWidgets('Tabs: Share, Print, Activity', (tester) async {
    Finder tab(String label) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

    await tester.pumpWidget(const DemoApp());
    expect(find.text('Share printers'), findsOneWidget);
    expect(find.text('No printers yet'), findsOneWidget);

    await tester.tap(tab('Print'));
    await tester.pumpAndSettle();
    expect(find.text('Find printers on this Wi-Fi'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);

    await tester.tap(tab('Activity'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Activity')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
