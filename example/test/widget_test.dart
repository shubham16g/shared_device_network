import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network_example/bg_service_screen.dart';
import 'package:shared_device_network_example/main.dart';

void main() {
  testWidgets('SharedDeviceApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SharedDeviceApp());
    expect(find.text('Shared Device Network'), findsOneWidget);
    expect(find.textContaining('Host Server'), findsOneWidget);
    expect(find.textContaining('Client'), findsWidgets);
    expect(find.text('Run as Background Service'), findsOneWidget);
  });

  testWidgets('BgServiceScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BgServiceScreen()));

    expect(find.text('Background Service Server'), findsOneWidget);
    expect(find.textContaining('BG Host'), findsOneWidget);
    expect(find.textContaining('Client'), findsWidgets);
  });
}
