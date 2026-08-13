import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final testCase in <({double width, double textScale})>[
    (width: 480, textScale: 1),
    (width: 480, textScale: 2),
    (width: 1440, textScale: 1),
    (width: 1440, textScale: 2),
  ]) {
    testWidgets(
      'renders at ${testCase.width} logical pixels and ${testCase.textScale}x text scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ArgusTheme.light,
            home: SizedBox(
              width: testCase.width,
              height: 800,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(testCase.width, 800),
                  textScaler: TextScaler.linear(testCase.textScale),
                ),
                child: const SettingsPage(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        expect(
          find.textContaining('Appearance controls will be available'),
          findsOneWidget,
        );
        expect(find.byType(Radio), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
