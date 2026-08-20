import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network_example/main.dart';

void main() {
  testWidgets('SharedDeviceApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SharedDeviceApp());
    expect(find.text('Shared Device Network'), findsOneWidget);
    expect(find.textContaining('Host Server'), findsOneWidget);
    expect(find.textContaining('Client Discover'), findsOneWidget);
  });
}
