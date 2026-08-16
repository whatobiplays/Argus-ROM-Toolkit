import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'application/sources_state.dart';

part 'sources_composition.g.dart';

/// Focused Sources capability injected by app composition.
///
/// This is a dependency-injection seam only: it contains no root-client
/// construction, retries, caching, or workflow.
@Riverpod(keepAlive: true)
SourcesApi sourcesApi(Ref ref) {
  throw StateError('sourcesApiProvider must be supplied by app composition');
}

/// Presentation-only capabilities selected by app composition.
///
/// App-composition switches for presentation-only Sources capabilities.
///
/// The switches describe which existing workflows the current host may show;
/// they do not replace backend admission or query authority. Desktop keeps all
/// existing workflows enabled. Android enables the single-root surface while
/// deferring multi-root Scan All and active-root cancel-and-remove.
final class SourcesPresentationCapabilities {
  const SourcesPresentationCapabilities({
    this.singleRootScanExecution = true,
    this.scanAllExecution = true,
    this.activeRootCancelAndRemove = true,
    this.localFilesystemBrowser = false,
  });

  final bool singleRootScanExecution;
  final bool scanAllExecution;
  final bool activeRootCancelAndRemove;
  final bool localFilesystemBrowser;
}

@Riverpod(keepAlive: true)
SourcesPresentationCapabilities sourcesPresentationCapabilities(Ref ref) =>
    const SourcesPresentationCapabilities();

/// Focused Jobs capability injected for Sources-owned coordination (Scan All
/// ambiguity reconciliation and cancel-and-remove).
///
/// This is a dependency-injection seam only: Sources never reconstructs Jobs
/// truth from events and never owns the full job-detail surface.
@Riverpod(keepAlive: true)
JobsApi sourcesJobsApi(Ref ref) {
  throw StateError(
    'sourcesJobsApiProvider must be supplied by app composition',
  );
}

/// Runtime generation context injected by app composition.
///
/// The default is pre-ready; app composition supplies the current runtime
/// identity derived from backend readiness.
@Riverpod(keepAlive: true)
SourcesRuntimeContext sourcesRuntimeContext(Ref ref) =>
    const SourcesRuntimeContext.preReady();

/// Sources reconciliation demand channel injected by app composition.
///
/// This is a dependency-injection seam only: the Sources feature never
/// interprets transport or event-envelope mechanics. The default is an empty
/// source so the feature remains inert without app composition.
@Riverpod(keepAlive: true)
SourcesReconciliationDemandSource sourcesReconciliationDemand(Ref ref) =>
    const SourcesReconciliationDemandSource(
      Stream<SourcesReconciliationDemand>.empty(),
    );
