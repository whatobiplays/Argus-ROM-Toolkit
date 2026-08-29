import 'package:argus/features/startup/presentation/startup_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source validation indeterminate has a specific user-safe message', () {
    expect(
      messageForKey('errors.content.source_validation_indeterminate'),
      'Argus could not verify that a source remained unchanged.',
    );
  });
}
