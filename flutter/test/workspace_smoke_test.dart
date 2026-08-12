import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter test harness is operational', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    expect(find.byType(SizedBox), findsOneWidget);
  });
}
