import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// P02-001 denied-permission scenario: with live All files access denied, the
/// real Android composition must stay behind the platform readiness gate and
/// must not create the host-standard SQLite database.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('denied All files access blocks startup and database creation', (
    tester,
  ) async {
    const channel = MethodChannel('argus/platform_readiness');

    await tester.pumpWidget(const ArgusBootstrap());

    await _pumpUntilFound(tester, find.text('Storage access required'));

    expect(find.text('Storage access required'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Settings')),
      findsNothing,
      reason: 'normal app shell must not render before readiness',
    );

    final snapshot = (await channel.invokeMapMethod<Object?, Object?>(
      'readSnapshot',
    ))!;
    expect(snapshot['allFilesAccessRequired'], isTrue);
    expect(snapshot['allFilesAccessGranted'], isFalse);

    final standardDirectory = snapshot['standardApplicationDataDirectory'];
    expect(standardDirectory, isA<String>());
    expect(
      standardDirectory,
      startsWith('/data/user/0/com.argusromtoolkit.argus/files/argus'),
    );
    expect(
      File('$standardDirectory/argus.sqlite3').existsSync(),
      isFalse,
      reason: 'Rust startup must not run before platform readiness',
    );
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
