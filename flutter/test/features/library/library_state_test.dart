import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_test_fakes.dart';

void main() {
  test('LibraryState is value-equal and exposes unmodifiable collections', () {
    final row = libraryRow();
    final state = LibraryState.initial(
      const LibraryScope.all(),
    ).copyWith(games: [row], selectedGameIds: {row.gameId});
    final equivalent = LibraryState.initial(
      const LibraryScope.all(),
    ).copyWith(games: [row], selectedGameIds: {row.gameId});

    expect(state, equivalent);
    expect(() => state.games.add(row), throwsUnsupportedError);
    expect(
      () => state.selectedGameIds.add(GameId('2' * 32)),
      throwsUnsupportedError,
    );
  });

  test('runtime context equality is based on the runtime generation', () {
    expect(
      const LibraryRuntimeContext.ready(
        runtimeInstanceId: RuntimeInstanceId(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      const LibraryRuntimeContext.ready(
        runtimeInstanceId: RuntimeInstanceId(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
    );
  });
}
