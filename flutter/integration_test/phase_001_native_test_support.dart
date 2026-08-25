import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/presentation/library_onboarding_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns the single application client composed by [ArgusBootstrap].
ArgusClient phase001RootClient(WidgetTester tester) {
  final app = find.byType(ArgusApp);
  expect(app, findsOneWidget);
  final container = ProviderScope.containerOf(
    tester.element(app),
    listen: false,
  );
  return container.read(argusClientProvider);
}

/// Completes Library onboarding through the durable client authority.
///
/// Native Phase 001 scenarios exercise Sources and restart recovery rather than
/// onboarding itself. Each fresh process therefore establishes the durable
/// onboarding fact first, using [temporaryRootPath] as the required root, waits
/// for the admitted refreshes, and removes that root through the Sources API.
/// The test never mutates onboarding state in Flutter memory or bypasses the
/// production route guard.
Future<ArgusClient> completePhase001LibraryOnboarding(
  WidgetTester tester, {
  required String temporaryRootPath,
}) async {
  final client = phase001RootClient(tester);
  await _waitForPhase001RuntimeReady(tester, client);

  var state = await client.onboarding.getState();
  if (!state.complete && state.requiresPrivacyAcceptance) {
    state = await client.settings
        .acceptPrivacyTerms(
          PrivacyTermsVersion(state.requiredPrivacyTermsVersion),
        )
        .then((_) => client.onboarding.getState());
  }

  if (!state.complete && !state.progress.metadataPreferencesConfirmed) {
    final settings = await client.metadataSettings.getMetadataSettings();
    state = await client.onboarding.confirmMetadataPreferences(settings);
  }

  if (!state.complete &&
      state.progress.providerSetupOutcome ==
          LibraryProviderSetupOutcome.pending) {
    state = await client.onboarding.recordProviderSetup(
      LibraryProviderSetupDecision.skipped,
    );
  }

  LibraryRoot? temporaryRoot;
  try {
    if (!state.complete && state.requiresRootSelection) {
      final result = await client.onboarding.addLibraryRootAndRefresh(
        LocalFilesystemRootSelection(temporaryRootPath),
      );
      switch (result) {
        case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted(
          :final root,
          :final handle,
        ):
          temporaryRoot = root;
          final terminal = await _waitForPhase001TerminalJob(
            tester,
            client,
            handle.jobRunId,
          );
          expect(
            terminal.job.lifecycleState,
            anyOf(
              JobLifecycleState.completed,
              JobLifecycleState.completedWithIssues,
            ),
            reason: 'temporary onboarding refresh must finish successfully',
          );
        case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted(
          :final root,
          :final error,
        ):
          temporaryRoot = root;
          fail('temporary onboarding refresh was not admitted: $error');
        case AddLibraryRootAndRefreshResultAlreadyConfigured():
          fail('temporary onboarding root was unexpectedly already configured');
        case AddLibraryRootAndRefreshResultOverlapsExisting():
          fail(
            'temporary onboarding root unexpectedly overlapped an existing root',
          );
      }
    }

    state = await client.onboarding.getState();
    if (!state.complete) {
      final result = await client.onboarding.completeAndRefresh();
      switch (result) {
        case CompleteLibraryOnboardingAndRefreshResultAdmitted(:final handle):
          final terminal = await _waitForPhase001TerminalJob(
            tester,
            client,
            handle.jobRunId,
          );
          expect(
            terminal.job.lifecycleState,
            anyOf(
              JobLifecycleState.completed,
              JobLifecycleState.completedWithIssues,
            ),
            reason: 'onboarding refresh must finish successfully',
          );
        case CompleteLibraryOnboardingAndRefreshResultNotAdmitted(:final error):
          fail('onboarding refresh was not admitted: $error');
      }
    }
  } finally {
    if (temporaryRoot case final root?) {
      final removal = await client.sources.removeLibraryRoot(root.id);
      switch (removal) {
        case RemoveLibraryRootResultRemoved():
          break;
        case RemoveLibraryRootResultRootHasActiveScan(:final jobRunId):
          fail('temporary onboarding root still has active JobRun $jobRunId');
      }
    }
  }

  final completed = await client.onboarding.getState();
  expect(
    completed.complete,
    isTrue,
    reason: 'onboarding completion must come from durable backend state',
  );
  final onboardingPage = find.byType(LibraryOnboardingPage);
  if (onboardingPage.evaluate().isNotEmpty) {
    final context = tester.element(onboardingPage);
    const LibraryRoute().go(context);
    await tester.pump(const Duration(milliseconds: 200));
  }
  return client;
}

Future<void> _waitForPhase001RuntimeReady(
  WidgetTester tester,
  ArgusClient client, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  RuntimeState? lastState;
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastState = await client.runtime.getRuntimeState();
      if (lastState is RuntimeStateReady) return;
      if (lastState case RuntimeStateStartupFailed(:final failure)) {
        fail('macOS runtime startup failed: $failure');
      }
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('macOS runtime did not reach Ready; state=$lastState error=$lastError');
}

Future<JobDetail> _waitForPhase001TerminalJob(
  WidgetTester tester,
  ArgusClient client,
  JobRunId jobRunId, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final detail = await client.jobs.getJob(jobRunId);
    if (detail.job.lifecycleState.isTerminal) return detail;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('onboarding JobRun $jobRunId did not reach a terminal state');
}
