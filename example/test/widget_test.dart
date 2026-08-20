import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network_example/main.dart';

void main() {
  testWidgets('SharedDeviceApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SharedDeviceApp());
    expect(find.text('Shared Device Network'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
  });
}
