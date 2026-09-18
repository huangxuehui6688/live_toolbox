import 'package:flutter_test/flutter_test.dart';

import 'package:live_toolbox/main.dart';

void main() {
  testWidgets('app boots and shows home', (WidgetTester tester) async {
    await tester.pumpWidget(const LiveToolboxApp());
    expect(find.text('AI直播副驾驶'), findsWidgets);
  });
}
