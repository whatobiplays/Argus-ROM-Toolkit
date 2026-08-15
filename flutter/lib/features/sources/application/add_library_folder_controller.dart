import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart' show jobsApiProvider;
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

  const factory SourcesAddOperation.addedAndScanAdmitted({
    required LibraryRoot root,
    required OperationHandle handle,
  }) = SourcesAddOperationAddedAndScanAdmitted;

  const factory SourcesAddOperation.addedButScanNotAdmitted({
    required LibraryRoot root,
    required LibraryScanChildAdmissionIssue issue,
  }) = SourcesAddOperationAddedButScanNotAdmitted;

  /// The ambiguous composite outcome cannot yet be proven resolved; the
  /// authoritative reconciliation must complete before conflicting mutation.
  const factory SourcesAddOperation.scanReconciliationUncertain({
    required LibraryRoot root,
  }) = SourcesAddOperationScanReconciliationUncertain;

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

  /// Re-runs the authoritative ambiguity reconciliation after uncertainty.
  Future<void> refreshReconciliation(LibraryRootId rootId) async {
    if (state is! SourcesAddOperationScanReconciliationUncertain ||
        state is SourcesAddOperationSubmitting) {
      return;
    }
    await _reconcileAdmissionAuthority(rootId);
  }

  /// Submits the Add & Scan composite workflow.
  Future<void> addAndScan(LocalFilesystemRootSelection selection) async {
    if (state is SourcesAddOperationSubmitting) return;
    state = const SourcesAddOperation.submitting();
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .addLocalLibraryRootAndScan(selection);
      _adoptAndScan(result);
    } on ApplicationFailure catch (failure) {
      state = SourcesAddOperation.failed(failure);
    } on TransportFailure catch (failure) {
      await _reconcileAmbiguousAddAndScan(selection, failure);
    }
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

  void _adoptAndScan(AddLocalLibraryRootAndScanResult result) {
    state = switch (result) {
      AddLocalLibraryRootAndScanResultAddedAndScanAdmitted(
        :final root,
        :final handle,
      ) =>
        SourcesAddOperation.addedAndScanAdmitted(root: root, handle: handle),
      AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted(
        :final root,
        :final issue,
      ) =>
        SourcesAddOperation.addedButScanNotAdmitted(root: root, issue: issue),
      AddLocalLibraryRootAndScanResultAlreadyConfigured(
        :final existingLibraryRootId,
      ) =>
        SourcesAddOperation.alreadyConfigured(existingLibraryRootId),
      AddLocalLibraryRootAndScanResultOverlapsExisting(
        :final existingLibraryRootId,
        :final relationship,
      ) =>
        SourcesAddOperation.overlapsExisting(
          existingLibraryRootId: existingLibraryRootId,
          relationship: relationship,
        ),
    };
  }

  /// Reconciles an ambiguous Add & Scan transport outcome.
  ///
  /// The composite is never replayed. Only the exact idempotent root-only add
  /// establishes the authoritative root identity; root and Jobs authority are
  /// then queried. An explicit scan starts only when both reads prove that no
  /// child admission exists. `lastScan` alone is never treated as proof.
  Future<void> _reconcileAmbiguousAddAndScan(
    LocalFilesystemRootSelection selection,
    TransportFailure failure,
  ) async {
    late final LibraryRootId rootId;
    try {
      final replay = await ref
          .read(sourcesApiProvider)
          .addLocalLibraryRoot(selection);
      switch (replay) {
        case AddLocalLibraryRootResultAdded(:final root):
          rootId = root.id;
        case AddLocalLibraryRootResultAlreadyConfigured(
          :final existingLibraryRootId,
        ):
          rootId = existingLibraryRootId;
        case AddLocalLibraryRootResultOverlapsExisting(
          :final existingLibraryRootId,
          :final relationship,
        ):
          state = SourcesAddOperation.overlapsExisting(
            existingLibraryRootId: existingLibraryRootId,
            relationship: relationship,
          );
          return;
      }
    } on ClientFailure {
      state = SourcesAddOperation.ambiguous(failure);
      return;
    }
    await _reconcileAdmissionAuthority(rootId);
  }

  Future<void> _reconcileAdmissionAuthority(LibraryRootId rootId) async {
    try {
      final root = await ref.read(sourcesApiProvider).getLibraryRoot(rootId);
      final admission = await ref
          .read(jobsApiProvider)
          .getRootScanAdmission(rootId);
      if (admission != null) {
        state = SourcesAddOperation.addedAndScanAdmitted(
          root: root,
          handle: OperationHandle(
            jobRunId: admission.jobRunId,
            operationType: 'library_scan',
          ),
        );
        return;
      }
      final activeScan = root.activeScan;
      if (activeScan != null) {
        state = SourcesAddOperation.addedAndScanAdmitted(
          root: root,
          handle: OperationHandle(
            jobRunId: JobRunId(activeScan.jobRunId),
            operationType: 'library_scan',
          ),
        );
        return;
      }
      // No child admission is authoritatively present: the explicit
      // StartLibraryScan replay is now safe and backend-authoritative.
      try {
        final result = await ref
            .read(sourcesApiProvider)
            .startLibraryScan(rootId);
        switch (result) {
          case StartLibraryScanResultAdmitted(:final handle):
            state = SourcesAddOperation.addedAndScanAdmitted(
              root: root,
              handle: handle,
            );
          case StartLibraryScanResultAlreadyScanning(:final activeJobRunId):
            state = SourcesAddOperation.addedAndScanAdmitted(
              root: root,
              handle: OperationHandle(
                jobRunId: activeJobRunId,
                operationType: 'library_scan',
              ),
            );
        }
      } on ClientFailure {
        state = SourcesAddOperation.scanReconciliationUncertain(root: root);
      }
    } on ClientFailure {
      state = const SourcesAddOperation.ambiguous(
        TransportFailure(
          'Add & Scan outcome remains uncertain; authoritative reconciliation failed',
          kind: TransportFailureKind.unexpectedTransportFailure,
        ),
      );
    }
  }
}
