import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WindowSizeClass exposes exactly four structural classes', () {
    expect(WindowSizeClass.values, <WindowSizeClass>[
      WindowSizeClass.compact,
      WindowSizeClass.medium,
      WindowSizeClass.expanded,
      WindowSizeClass.large,
    ]);
  });

  for (final testCase in <({double width, WindowSizeClass expected})>[
    (width: 599, expected: WindowSizeClass.compact),
    (width: 600, expected: WindowSizeClass.medium),
    (width: 839, expected: WindowSizeClass.medium),
    (width: 840, expected: WindowSizeClass.expanded),
    (width: 1199, expected: WindowSizeClass.expanded),
    (width: 1200, expected: WindowSizeClass.large),
  ]) {
    test('${testCase.width} classifies as ${testCase.expected.name}', () {
      expect(classifyWindowWidth(testCase.width), testCase.expected);
    });
  }

  test('page gutters derive from the structural size class', () {
    expect(pageGutterFor(WindowSizeClass.compact), 16);
    expect(pageGutterFor(WindowSizeClass.medium), 24);
    expect(pageGutterFor(WindowSizeClass.expanded), 32);
    expect(pageGutterFor(WindowSizeClass.large), 32);
  });
}
