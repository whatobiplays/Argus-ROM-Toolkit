import 'dart:io';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/presentation/library_onboarding_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns the single application client composed by [ArgusBootstrap].
ArgusClient phase002RootClient(WidgetTester tester) {
  final app = find.byType(ArgusApp);
  expect(app, findsOneWidget);
  final container = ProviderScope.containerOf(
    tester.element(app),
    listen: false,
  );
  return container.read(argusClientProvider);
}

/// Waits for the Android platform gate to publish its latched data-directory
/// configuration before any test reads the composed root client provider.
Future<void> waitForPhase002PlatformReady(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final app = find.byType(ArgusApp);
  expect(app, findsOneWidget);
  final container = ProviderScope.containerOf(
    tester.element(app),
    listen: false,
  );
  final deadline = DateTime.now().add(timeout);
  PlatformReadinessState? lastState;
  while (DateTime.now().isBefore(deadline)) {
    lastState = container.read(platformReadinessControllerProvider);
    if (lastState is PlatformReadinessReady) return;
    if (lastState case PlatformReadinessRequiresAllFilesAccess()) {
      fail('Android platform readiness still requires All files access');
    }
    if (lastState case PlatformReadinessUnavailable(:final failure)) {
      fail('Android platform readiness is unavailable: $failure');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('Android platform readiness did not reach Ready: $lastState');
}

/// Waits for Android backend startup without making the ready shell the only
/// observable startup contract. P03-003 intentionally permits the app to be
/// runtime-ready while Library onboarding still owns presentation routing.
Future<void> waitForPhase002RuntimeReady(
  WidgetTester tester, {
  ArgusClient? client,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final rootClient = client ?? phase002RootClient(tester);
  final deadline = DateTime.now().add(timeout);
  RuntimeState? lastState;
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastState = await rootClient.runtime.getRuntimeState();
      if (lastState is RuntimeStateReady) return;
      if (lastState case RuntimeStateStartupFailed(:final failure)) {
        fail('Android runtime startup failed: $failure');
      }
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail(
    'Android runtime did not reach Ready; state=$lastState error=$lastError',
  );
}

/// Establishes the durable Library completion fact for a fresh native test.
///
/// The helper uses the real onboarding APIs and the real composed refresh
/// admission. It creates one temporary app-visible directory only when a root
/// is required, waits for the admitted parent JobRun to finish, removes that
/// root through the authoritative Sources capability, and then navigates to
/// the Library route. No in-memory completion flag or production-only bypass is
/// involved. The completion timestamp remains durable after the temporary root
/// is removed, which keeps root-management scenarios independent of the setup.
Future<ArgusClient> completePhase002LibraryOnboarding(
  WidgetTester tester,
) async {
  await waitForPhase002PlatformReady(tester);
  await _waitForPhase002Presentation(tester);
  final client = phase002RootClient(tester);
  await waitForPhase002RuntimeReady(tester, client: client);

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
    final decision = state.credentialConfigured
        ? LibraryProviderSetupDecision.configured
        : LibraryProviderSetupDecision.skipped;
    state = await client.onboarding.recordProviderSetup(decision);
  }

  Directory? temporaryDirectory;
  LibraryRoot? temporaryRoot;
  try {
    if (!state.complete && state.requiresRootSelection) {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'argus-phase-002-onboarding-',
      );
      final result = await client.onboarding.addLibraryRootAndRefresh(
        LocalFilesystemRootSelection.path(temporaryDirectory.path),
      );
      switch (result) {
        case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted(
          :final root,
          :final handle,
        ):
          temporaryRoot = root;
          final terminal = await _waitForPhase002TerminalJob(
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
          final completion = await client.onboarding.completeAndRefresh();
          switch (completion) {
            case CompleteLibraryOnboardingAndRefreshResultAdmitted(
              :final handle,
            ):
              final completionTerminal = await _waitForPhase002TerminalJob(
                tester,
                client,
                handle.jobRunId,
              );
              expect(
                completionTerminal.job.lifecycleState,
                anyOf(
                  JobLifecycleState.completed,
                  JobLifecycleState.completedWithIssues,
                ),
                reason:
                    'onboarding completion refresh must finish successfully',
              );
            case CompleteLibraryOnboardingAndRefreshResultNotAdmitted(
              :final error,
            ):
              fail('onboarding completion refresh was not admitted: $error');
          }
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
    } else if (!state.complete) {
      final result = await client.onboarding.completeAndRefresh();
      switch (result) {
        case CompleteLibraryOnboardingAndRefreshResultAdmitted(:final handle):
          final terminal = await _waitForPhase002TerminalJob(
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
    final directory = temporaryDirectory;
    if (directory != null) {
      await directory.delete(recursive: true);
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

Future<void> _waitForPhase002Presentation(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  final shell = find.byKey(const ValueKey<String>('compact-navigation-bar'));
  final onboarding = find.byType(LibraryOnboardingPage);
  while (DateTime.now().isBefore(deadline)) {
    if (shell.evaluate().isNotEmpty || onboarding.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('Android presentation did not reach Library onboarding or the shell');
}

Future<JobDetail> _waitForPhase002TerminalJob(
  WidgetTester tester,
  ArgusClient client,
  JobRunId jobRunId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    final detail = await client.jobs.getJob(jobRunId);
    if (detail.job.lifecycleState.isTerminal) return detail;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('onboarding JobRun $jobRunId did not reach a terminal state');
}
