import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';

part 'add_library_folder_controller.freezed.dart';
part 'add_library_folder_controller.g.dart';

/// One root-only add workflow operation.
///
/// Typed duplicate/overlap outcomes are expected non-mutating results, not
/// failures. A transport-ambiguous root-only add is safely replayable because
/// backend creation is explicitly idempotent; the composite Add & Scan is
/// never replayed here.
@freezed
sealed class SourcesAddOperation with _$SourcesAddOperation {
  const factory SourcesAddOperation.idle() = SourcesAddOperationIdle;

  const factory SourcesAddOperation.submitting() =
      SourcesAddOperationSubmitting;

  const factory SourcesAddOperation.added(LibraryRoot root) =
      SourcesAddOperationAdded;

  const factory SourcesAddOperation.alreadyConfigured(
    LibraryRootId existingLibraryRootId,
  ) = SourcesAddOperationAlreadyConfigured;

  const factory SourcesAddOperation.overlapsExisting({
    required LibraryRootId existingLibraryRootId,
    required RootRelationship relationship,
  }) = SourcesAddOperationOverlapsExisting;

  const factory SourcesAddOperation.failed(ClientFailure failure) =
      SourcesAddOperationFailed;

  const factory SourcesAddOperation.ambiguous(TransportFailure failure) =
      SourcesAddOperationAmbiguous;
}

/// One application-lifetime owner of the root-only add workflow state.
@Riverpod(keepAlive: true)
class SourcesAddLibraryFolderController
    extends _$SourcesAddLibraryFolderController {
  @override
  SourcesAddOperation build() => const SourcesAddOperation.idle();

  /// Submits one validated root-only add.
  Future<void> add(LocalFilesystemRootSelection selection) async {
    if (state is SourcesAddOperationSubmitting) return;
    state = const SourcesAddOperation.submitting();
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .addLocalLibraryRoot(selection);
      _adopt(result);
    } on ApplicationFailure catch (failure) {
      state = SourcesAddOperation.failed(failure);
    } on TransportFailure catch (failure) {
      // The exact same root-only selection is idempotent at the backend:
      // replay it once to establish the authoritative root identity instead
      // of fabricating state from an ambiguous response.
      try {
        final result = await ref
            .read(sourcesApiProvider)
            .addLocalLibraryRoot(selection);
        _adopt(result);
      } on ClientFailure {
        state = SourcesAddOperation.ambiguous(failure);
      }
    }
  }

  /// Resets the workflow to idle after presentation consumes an outcome.
  void reset() {
    state = const SourcesAddOperation.idle();
  }

  void _adopt(AddLocalLibraryRootResult result) {
    state = switch (result) {
      AddLocalLibraryRootResultAdded(:final root) => SourcesAddOperation.added(
        root,
      ),
      AddLocalLibraryRootResultAlreadyConfigured(
        :final existingLibraryRootId,
      ) =>
        SourcesAddOperation.alreadyConfigured(existingLibraryRootId),
      AddLocalLibraryRootResultOverlapsExisting(
        :final existingLibraryRootId,
        :final relationship,
      ) =>
        SourcesAddOperation.overlapsExisting(
          existingLibraryRootId: existingLibraryRootId,
          relationship: relationship,
        ),
    };
  }
}
