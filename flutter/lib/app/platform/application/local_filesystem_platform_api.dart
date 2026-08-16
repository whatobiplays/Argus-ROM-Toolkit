/// Framework-neutral mounted local-filesystem facts and discovery capability.
///
/// The mount path is transient input for the Rust provider registry. It is not
/// a durable identity and must never be persisted or rendered as Sources copy.
library;

/// Maximum mounted-volume facts accepted from Android in one snapshot.
const int maxPlatformMountedVolumes = 32;

/// One bounded current mounted-volume fact supplied by the operating system.
final class PlatformMountedVolume {
  const PlatformMountedVolume({
    required this.providerVolumeId,
    required this.transientMountPath,
    required this.safeDisplayName,
    required this.isPrimary,
    required this.isRemovable,
  });

  final String providerVolumeId;
  final String transientMountPath;
  final String safeDisplayName;
  final bool isPrimary;
  final bool isRemovable;
}

/// Bounded local-filesystem platform failure vocabulary.
enum LocalFilesystemPlatformFailureKind {
  discoveryUnavailable,
  malformedSnapshot,
}

/// Typed local-filesystem platform failure with no native text payload.
final class LocalFilesystemPlatformException implements Exception {
  const LocalFilesystemPlatformException(this.kind);

  final LocalFilesystemPlatformFailureKind kind;
}

/// Platform capability used by app composition to refresh mounted volumes.
abstract interface class LocalFilesystemPlatformApi {
  Future<List<PlatformMountedVolume>> readMountedVolumes();
}
