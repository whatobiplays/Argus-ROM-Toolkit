import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/presentation/library_onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns the single application client composed by [ArgusBootstrap].
ArgusClient nativeTestRootClient(WidgetTester tester) {
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
/// Native scenarios exercise capabilities other than onboarding. Each fresh
/// process therefore establishes the durable onboarding fact first, using
/// [temporaryRootPath] as the required root, waits for the admitted refreshes,
/// and removes that root through the Sources API. The test never mutates
/// onboarding state in Flutter memory or bypasses the production route guard.
Future<ArgusClient> completeNativeLibraryOnboarding(
  WidgetTester tester, {
  required String temporaryRootPath,
}) async {
  final client = nativeTestRootClient(tester);
  await _waitForNativeRuntimeReady(tester, client);

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
          final terminal = await _waitForNativeTerminalJob(
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
          final terminal = await _waitForNativeTerminalJob(
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
  await _leaveNativeOnboarding(tester);
  return client;
}

Future<void> _leaveNativeOnboarding(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  var routeRequested = false;
  while (DateTime.now().isBefore(deadline)) {
    final onboardingPage = find.byType(LibraryOnboardingPage);
    if (onboardingPage.evaluate().isEmpty) {
      if (_nativeShellVisible(tester)) return;
    } else {
      final openLibrary = find.text('Open Library').hitTestable();
      if (openLibrary.evaluate().isNotEmpty) {
        await tester.tap(openLibrary.first);
      } else if (!routeRequested) {
        final context = tester.element(onboardingPage);
        const LibraryRoute().go(context);
        routeRequested = true;
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('native Library onboarding did not open the ready shell');
}

bool _nativeShellVisible(WidgetTester tester) =>
    find.byType(NavigationBar).evaluate().isNotEmpty ||
    find.byType(NavigationRail).evaluate().isNotEmpty;

Future<void> _waitForNativeRuntimeReady(
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

Future<JobDetail> _waitForNativeTerminalJob(
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
