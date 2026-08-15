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
