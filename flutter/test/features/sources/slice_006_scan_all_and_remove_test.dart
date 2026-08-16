import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/sources/application/root_list_controller.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:argus/features/sources/presentation/root_detail_page.dart';
import 'package:argus/features/sources/presentation/sources_page.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../jobs/jobs_test_fakes.dart';
import 'sources_test_fakes.dart';

const _rootId = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _runtimeId = RuntimeInstanceId('1234567890abcdef1234567890abcdef');
const _jobId = JobRunId('11111111111111111111111111111111');

LibraryRoot _root({LibraryRootActiveScan? activeScan}) => LibraryRoot(
  id: _rootId,
  displayName: 'Games',
  safeLocationPresentation: '/library/Games',
  availability: LibraryRootAvailability.available,
  activeScan: activeScan,
);

ProviderContainer _container(
  FakeSourcesApi api,
  FakeJobsApi jobsApi, {
  SourcesPresentationCapabilities capabilities =
      const SourcesPresentationCapabilities(),
}) {
  final container = ProviderContainer(
    overrides: [
      sourcesApiProvider.overrideWithValue(api),
      sourcesJobsApiProvider.overrideWithValue(jobsApi),
      sourcesPresentationCapabilitiesProvider.overrideWithValue(capabilities),
      sourcesRuntimeContextProvider.overrideWith(
        (ref) =>
            const SourcesRuntimeContext.ready(runtimeInstanceId: _runtimeId),
      ),
      sourcesReconciliationDemandProvider.overrideWith(
        (ref) => const SourcesReconciliationDemandSource(
          Stream<SourcesReconciliationDemand>.empty(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpSources(
  WidgetTester tester,
  ProviderContainer container, {
  required void Function(JobRunId jobRunId) onOpenJob,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ArgusTheme.light,
        home: SourcesPage(onOpenRoot: (_) {}, onOpenJob: onOpenJob),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester,
  ProviderContainer container, {
  VoidCallback? onRemoved,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ArgusTheme.light,
        home: SourcesRootDetailPage(
          rootId: _rootId,
          onMissingRoot: () {},
          onRemoved: onRemoved ?? () {},
          onOpenRoot: (_) {},
          onOpenJob: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Android root-management capabilities hide every scan control', (
    tester,
  ) async {
    final api = FakeSourcesApi(roots: [_root()]);
    final container = _container(
      api,
      FakeJobsApi(),
      capabilities: const SourcesPresentationCapabilities(
        scanExecution: false,
        localFilesystemBrowser: true,
      ),
    );

    await _pumpSources(tester, container, onOpenJob: (_) {});
    expect(find.byKey(const ValueKey('sources-scan-all')), findsNothing);

    await _pumpDetail(tester, container);
    expect(find.byKey(const ValueKey('sources-start-scan')), findsNothing);
    expect(find.byKey(const ValueKey('sources-view-last-job')), findsNothing);
  });

  testWidgets('Scan All control is gated by authoritative totalCount', (
    tester,
  ) async {
    final api = FakeSourcesApi(roots: []);
    final container = _container(api, FakeJobsApi());
    await _pumpSources(tester, container, onOpenJob: (_) {});

    expect(find.byKey(const ValueKey('sources-scan-all')), findsNothing);

    api.roots = [_root()];
    await container.read(sourcesRootListControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sources-scan-all')), findsOneWidget);
  });

  testWidgets('admitted Scan All stays on Sources with concise feedback', (
    tester,
  ) async {
    final api = FakeSourcesApi(roots: [_root()]);
    api.onStartScanAll = (identity) => StartLibraryScanAllResult.admitted(
      handle: const OperationHandle(
        jobRunId: _jobId,
        operationType: 'library_scan',
      ),
      admittedRoots: const [_rootId],
      exclusions: const [],
    );
    final jobsApi = FakeJobsApi();
    JobRunId? openedJob;
    final container = _container(api, jobsApi);
    await _pumpSources(
      tester,
      container,
      onOpenJob: (jobRunId) => openedJob = jobRunId,
    );

    await tester.tap(find.byKey(const ValueKey('sources-scan-all')));
    await tester.pumpAndSettle();

    expect(api.startScanAllCalls, 1);
    expect(find.text('Scan started for 1 folder.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sources-scan-all-view-job')),
      findsOneWidget,
    );
    expect(find.byType(SourcesPage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sources-scan-all-view-job')));
    expect(openedJob, _jobId);
  });

  testWidgets('NothingEligible shows typed reasons without a job action', (
    tester,
  ) async {
    final api = FakeSourcesApi(roots: [_root()]);
    api.onStartScanAll = (identity) =>
        StartLibraryScanAllResult.nothingEligible(
          exclusions: const [
            LibraryScanAdmissionExclusion(
              libraryRootId: _rootId,
              reason: 'already_scanning',
            ),
            LibraryScanAdmissionExclusion(
              libraryRootId: LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
              reason: 'invalid_configuration',
            ),
          ],
        );
    final container = _container(api, FakeJobsApi());
    await _pumpSources(tester, container, onOpenJob: (_) {});

    await tester.tap(find.byKey(const ValueKey('sources-scan-all')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('one folder is already being scanned'),
      findsOneWidget,
    );
    expect(
      find.textContaining('one folder has an invalid configuration'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sources-scan-all-view-job')),
      findsNothing,
    );
  });

  testWidgets(
    'ambiguous Scan All reuses the identity and blocks conflicting submission',
    (tester) async {
      final api = FakeSourcesApi(roots: [_root()]);
      final jobsApi = FakeJobsApi();
      final resolutionCompleter = Completer<LibraryScanAllRequestResolution>();
      final submittedIdentities = <String>[];
      final resolvedIdentities = <String>[];
      api.onStartScanAll = (identity) {
        submittedIdentities.add(identity.value);
        throw const TransportFailure('ambiguous');
      };
      jobsApi.onResolveScanAllRequest = (identity) {
        resolvedIdentities.add(identity.value);
        return resolutionCompleter.future;
      };
      final container = _container(api, jobsApi);
      await _pumpSources(tester, container, onOpenJob: (_) {});

      await tester.tap(find.byKey(const ValueKey('sources-scan-all')));
      await tester.pump();
      expect(find.textContaining('Scan not confirmed'), findsOneWidget);

      // Conflicting submission is blocked while uncertain.
      await tester.tap(
        find.byKey(const ValueKey('sources-scan-all')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(api.startScanAllCalls, 1);

      resolutionCompleter.complete(
        const LibraryScanAllRequestResolution.nothingAdmitted(),
      );
      await tester.pumpAndSettle();

      expect(submittedIdentities, resolvedIdentities);
      expect(submittedIdentities.length, 1);
      expect(find.textContaining('Scan not confirmed'), findsNothing);
    },
  );

  testWidgets('known active removal opens Cancel Scan & Remove directly', (
    tester,
  ) async {
    final api = FakeSourcesApi(
      roots: [
        _root(
          activeScan: const LibraryRootActiveScan(
            scanRunId: '22222222222222222222222222222222',
            jobRunId: '11111111111111111111111111111111',
            owningJobRootCount: 2,
          ),
        ),
      ],
    );
    final jobsApi = FakeJobsApi();
    final cancelledJobs = <JobRunId>[];
    final removedRoots = <LibraryRootId>[];
    jobsApi.onCancel = (jobRunId) {
      cancelledJobs.add(jobRunId);
      api.roots = [_root()];
      return CancelJobResult.cancellationRequested;
    };
    api.onRemove = (rootId) {
      removedRoots.add(rootId);
      return const RemoveLibraryRootResult.removed();
    };
    final container = _container(api, jobsApi);
    var removed = false;
    await _pumpDetail(tester, container, onRemoved: () => removed = true);

    await tester.tap(
      find.byKey(const ValueKey('sources-remove-library-folder')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancel Scan & Remove Library Folder?'), findsOneWidget);
    expect(find.textContaining('other 1 folder'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cancel-remove-confirm')));
    await tester.pumpAndSettle();

    expect(cancelledJobs, [_jobId]);
    expect(removedRoots, [_rootId]);
    expect(removed, isTrue);
  });

  testWidgets('definite cancel failure stops removal', (tester) async {
    final api = FakeSourcesApi(
      roots: [
        _root(
          activeScan: const LibraryRootActiveScan(
            scanRunId: '22222222222222222222222222222222',
            jobRunId: '11111111111111111111111111111111',
            owningJobRootCount: 1,
          ),
        ),
      ],
    );
    final jobsApi = FakeJobsApi();
    jobsApi.onCancel = (jobRunId) {
      throw ApplicationFailure(
        ClientApplicationError(
          code: const ErrorCode('ARGUS.V1.OPERATION.CANCELLATION_REJECTED'),
          category: ErrorCategory.operation,
          severity: ApplicationSeverity.warning,
          recoverability: Recoverability.userAction,
          retryPolicy: RetryPolicy.never,
          messageKey: const MessageKey('errors.operation.rejected'),
          traceId: const TraceId('33333333333333333333333333333333'),
          safeContext: const [],
        ),
      );
    };
    api.onRemove = (rootId) => const RemoveLibraryRootResult.removed();
    final container = _container(api, jobsApi);
    await _pumpDetail(tester, container);

    await tester.tap(
      find.byKey(const ValueKey('sources-remove-library-folder')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel-remove-confirm')));
    await tester.pumpAndSettle();

    expect(api.removeCalls, 0);
    expect(find.textContaining('could not be confirmed'), findsNothing);
    expect(
      find.byKey(const ValueKey('sources-remove-library-folder')),
      findsOneWidget,
    );
  });

  testWidgets('ambiguous cancel only removes after ownership is proven gone', (
    tester,
  ) async {
    final api = FakeSourcesApi(
      roots: [
        _root(
          activeScan: const LibraryRootActiveScan(
            scanRunId: '22222222222222222222222222222222',
            jobRunId: '11111111111111111111111111111111',
            owningJobRootCount: 1,
          ),
        ),
      ],
    );
    final jobsApi = FakeJobsApi();
    jobsApi.onCancel = (jobRunId) {
      throw const TransportFailure('ambiguous cancel');
    };
    api.onRemove = (rootId) => const RemoveLibraryRootResult.removed();
    final container = _container(api, jobsApi);
    await _pumpDetail(tester, container);

    await tester.tap(
      find.byKey(const ValueKey('sources-remove-library-folder')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cancel-remove-confirm')));
    await tester.pumpAndSettle();

    // Still owned after reconciliation -> removal never happened.
    expect(api.removeCalls, 0);
    expect(
      find.textContaining('Cancellation could not be confirmed'),
      findsOneWidget,
    );
  });

  testWidgets('removal race enters the same guided flow', (tester) async {
    final api = FakeSourcesApi(roots: [_root()]);
    final jobsApi = FakeJobsApi();
    api.onRemove = (rootId) => const RemoveLibraryRootResult.rootHasActiveScan(
      libraryRootId: _rootId,
      jobRunId: _jobId,
      scanRunId: ScanRunId('22222222222222222222222222222222'),
      owningJobRootCount: 2,
    );
    final container = _container(api, jobsApi);
    await _pumpDetail(tester, container);

    await tester.tap(
      find.byKey(const ValueKey('sources-remove-library-folder')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-root-confirm')));
    await tester.pumpAndSettle();

    // The race result blocked removal with the authoritative owner.
    expect(find.textContaining('other 1 folder'), findsOneWidget);
    expect(api.removeCalls, 1);

    // A second attempt enters the guided Cancel Scan & Remove flow directly.
    await tester.tap(
      find.byKey(const ValueKey('sources-remove-library-folder')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cancel Scan & Remove Library Folder?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-remove-confirm')));
    await tester.pumpAndSettle();
    expect(api.removeCalls, 2);
  });
}
