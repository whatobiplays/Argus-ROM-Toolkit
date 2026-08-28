import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'local_filesystem_platform_api.dart';
import 'platform_host_api.dart';
import 'platform_readiness_state.dart';

part 'platform_readiness_controller.g.dart';

/// Identifies whether app-lifecycle resume must certify platform readiness
/// before composition may request reconciliation.
final platformReadinessRequiredProvider = Provider<bool>((ref) => false);

/// DI seam for the platform host; app composition always supplies it.
@Riverpod(keepAlive: true)
PlatformHostApi platformHostApi(Ref ref) {
  throw StateError(
    'platformHostApiProvider must be supplied by app composition',
  );
}

/// Narrow platform seam used to re-evaluate mounted-volume facts after a
/// lifecycle resume. The reader is optional so desktop composition and tests
/// that do not model mounted volumes remain inert.
typedef PlatformMountedVolumesReader =
    Future<List<PlatformMountedVolume>> Function();

@Riverpod(keepAlive: true)
PlatformMountedVolumesReader? platformMountedVolumesReader(Ref ref) => null;

/// The only platform transitions that can request a Sources root refresh.
enum PlatformStorageReconciliationReason {
  readinessRestored,
  mountedVolumesChanged,
}

/// Bounded app-composition signal for authoritative Sources root rereads.
final class PlatformStorageReconciliationDemand {
  const PlatformStorageReconciliationDemand(this.reason);

  final PlatformStorageReconciliationReason reason;
}

/// Stream carrier owned by the readiness controller and consumed by app
/// composition. Jobs deliberately do not consume this channel: their existing
/// event and recovery authorities remain responsible for job refreshes.
final class PlatformStorageReconciliationDemandSource {
  const PlatformStorageReconciliationDemandSource(this.stream);

  final Stream<PlatformStorageReconciliationDemand> stream;
}

/// Exposes the readiness-owned storage transition channel without rebuilding
/// it every time the readiness state changes.
@Riverpod(keepAlive: true)
PlatformStorageReconciliationDemandSource platformStorageReconciliationDemand(
  Ref ref,
) {
  final controller = ref.watch(platformReadinessControllerProvider.notifier);
  return controller.storageReconciliationDemandSource;
}

/// Keep-alive authority for live platform readiness.
///
/// The first Ready snapshot latches the runtime configuration for the
/// process lifetime. Later permission revocation hides the application
/// through the readiness gate but never invalidates the client factory or
/// replaces an already initialized root runtime.
@Riverpod(keepAlive: true)
class PlatformReadinessController extends _$PlatformReadinessController {
  bool _refreshing = false;
  PlatformRuntimeConfiguration? _runtimeConfiguration;
  final StreamController<PlatformStorageReconciliationDemand> _demands =
      StreamController<PlatformStorageReconciliationDemand>.broadcast();
  String? _mountedVolumesFingerprint;
  bool _hasMountedVolumesBaseline = false;
  bool _hasObservedMountedVolumes = false;

  /// Process-lifetime runtime configuration from the first Ready snapshot.
  PlatformRuntimeConfiguration? get runtimeConfiguration =>
      _runtimeConfiguration;

  /// Platform storage transitions that require a Sources root reread.
  PlatformStorageReconciliationDemandSource
  get storageReconciliationDemandSource =>
      PlatformStorageReconciliationDemandSource(_demands.stream);

  @override
  PlatformReadinessState build() {
    ref.onDispose(() => unawaited(_demands.close()));
    unawaited(refresh());
    return const PlatformReadinessLoading();
  }

  /// Re-reads the authoritative OS snapshot without showing a loading state.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await ref.read(platformHostApiProvider).readSnapshot();
      final previous = state;
      final classified = classifyPlatformReadiness(snapshot);
      if (classified case PlatformReadinessReady(
        :final runtimeConfiguration,
        :final notificationAuthorization,
      )) {
        _runtimeConfiguration ??= runtimeConfiguration;
        final readinessRestored =
            previous is PlatformReadinessRequiresAllFilesAccess ||
            previous is PlatformReadinessUnavailable;
        final mountedVolumesReader = ref.read(
          platformMountedVolumesReaderProvider,
        );
        final mountedVolumesChanged = mountedVolumesReader == null
            ? false
            : await _reconcileMountedVolumes(mountedVolumesReader);
        state = PlatformReadinessReady(
          runtimeConfiguration: _runtimeConfiguration!,
          notificationAuthorization: notificationAuthorization,
        );
        if (readinessRestored) {
          _emit(PlatformStorageReconciliationReason.readinessRestored);
        } else if (mountedVolumesChanged) {
          _emit(PlatformStorageReconciliationReason.mountedVolumesChanged);
        }
      } else {
        state = classified;
      }
    } catch (_) {
      state = const PlatformReadinessUnavailable(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    } finally {
      _refreshing = false;
    }
  }

  /// Compares current bounded OS volume facts with the previous observation.
  /// A first observation is only a baseline; it cannot replay the initial
  /// Sources load. A later changed or recovered observation requests exactly
  /// one focused root reread.
  Future<bool> _reconcileMountedVolumes(
    PlatformMountedVolumesReader reader,
  ) async {
    try {
      final volumes = await reader();
      final fingerprint = _fingerprint(volumes);
      final changed =
          (_hasMountedVolumesBaseline &&
              _mountedVolumesFingerprint != fingerprint) ||
          (!_hasMountedVolumesBaseline && _hasObservedMountedVolumes);
      _mountedVolumesFingerprint = fingerprint;
      _hasMountedVolumesBaseline = true;
      _hasObservedMountedVolumes = true;
      return changed;
    } catch (_) {
      // A failed re-evaluation is not itself permission to mutate or erase
      // durable root state. Mark the baseline unknown so a later successful
      // recovery can trigger one authoritative availability reread.
      _mountedVolumesFingerprint = null;
      _hasMountedVolumesBaseline = false;
      return false;
    }
  }

  String _fingerprint(List<PlatformMountedVolume> volumes) {
    final facts = [
      for (final volume in volumes)
        [
          volume.providerVolumeId,
          volume.transientMountPath,
          volume.safeDisplayName,
          volume.isPrimary,
          volume.isRemovable,
        ].join('\u0000'),
    ]..sort();
    return facts.join('\u001f');
  }

  void _emit(PlatformStorageReconciliationReason reason) {
    if (!_demands.isClosed) {
      _demands.add(PlatformStorageReconciliationDemand(reason));
    }
  }

  /// Launches the All files settings surface, then re-reads OS state.
  Future<void> openAllFilesAccessSettings() async {
    try {
      await ref.read(platformHostApiProvider).openAllFilesAccessSettings();
    } catch (_) {
      state = const PlatformReadinessRequiresAllFilesAccess(
        failure: PlatformReadinessFailureKind.settingsLaunchFailed,
      );
      return;
    }
    await refresh();
  }

  /// Requests the optional notification permission, then re-reads OS state.
  Future<void> requestNotificationPermission() async {
    try {
      final authorization = await ref
          .read(platformHostApiProvider)
          .requestNotificationPermission();
      // An interrupted/dismissed prompt is not a terminal response; stay on
      // the notification step until the user or OS resolves it.
      if (authorization == NotificationAuthorization.promptRequired) {
        return;
      }
    } catch (_) {
      state = const PlatformReadinessRequiresNotificationPermission(
        failure: PlatformReadinessFailureKind.notificationRequestFailed,
      );
      return;
    }
    await refresh();
  }
}
