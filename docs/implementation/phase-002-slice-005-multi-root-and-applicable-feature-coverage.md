# Phase 002 Slice 005 implementation

This slice enables the existing Phase 001 Sources and Jobs workflows on
Android through composition. Rust remains the authority for configured roots,
availability, Scan All admission, job ownership, cancellation, persistence,
and terminal state.

## Readiness and storage transitions

Android readiness emits a narrow Sources reconciliation demand only when an
authoritative transition requires it:

- All files access changes from unavailable to granted.
- A later mounted-volume snapshot changes or recovers from an unavailable
  snapshot.
- An unchanged ready-state lifecycle notification emits nothing.

The demand is merged into the existing Sources reconciliation stream. Jobs is
not refreshed from platform resume or unchanged readiness; its existing event
and recovery boundaries remain authoritative. Permission or media loss changes
availability and blocks destructive absence reconciliation. Regrant, remount,
or restart makes the state readable again but does not create or resume work.

## Diagnostics artifact boundary

The backend/platform contract is the relative artifact
`diagnostics/startup-diagnostics-v1.zip` beneath the already-authoritative
Android application data root. The Android application exposes that root once
through its existing standard-data bootstrap getter; the diagnostics operation
does not add a path argument or return a path.

Rust writes sanitized, bounded contributors to a temporary artifact, finishes
the ZIP, and atomically renames it into the contract location. The FRB and
Flutter client return only the existing safe `DiagnosticsExport` summary. The
Android bridge validates only publication facts: the exact confined file,
regular-file/existence, a 10 MiB bound, Activity availability, FileProvider
confinement, and share-intent availability. It never parses ZIP contents and
never returns a filesystem path or content URI to Flutter.

Desktop keeps the existing destination-based
`exportStartupDiagnostics(expected, destination)` contract. Android adds the
no-destination sharing capability and publishes through a non-exported
AndroidX FileProvider restricted to `argus/diagnostics/`.

## Focused Android scenarios

Each scenario is independently invokable so a failed native boundary is
diagnosable without rerunning unrelated lifecycle windows:

```text
just test-phase-002-android-applicable-features
just test-phase-002-android-multi-root
just test-phase-002-android-permission-reconciliation
just test-phase-002-android-removable-volume
just test-phase-002-android-diagnostics
just test-phase-002-android-foreground
```

The last command is the existing P02-004 regression and remains separate.
The P02-005 commands require an API 36 ARM64 device or emulator, `adb`,
`fvm`, and the Android NDK required by the repository's Rust packaging task.
Fixtures are small and are removed only from their scenario-scoped paths. The
diagnostics scenario builds its migration fixture on the host and copies it
with `adb`/`run-as`; Dart does not attempt to load an unbundled SQLite FFI
library on Android.

## Removable-volume qualification mechanism

The trustworthy remount scenario requires a real public removable volume
reported by Android `StorageManager`, not a fake provider identity. The
focused script first records mounted public volumes, adoptable disks, and
`dumpsys mount` metadata. If a mounted public volume is already backed by a
disk with the native SD/USB removable flag, it is reused without provisioning.

Otherwise, the script checks the connected device's actual `sm help` output
for `set-virtual-disk`, `list-disks`, `partition`, `mount`, and `unmount`. When
all are present, it enables Android's supported virtual removable disk and
polls for exactly one new adoptable disk relative to the baseline:

```text
adb shell sm set-virtual-disk true
adb shell sm list-disks adoptable
adb shell sm partition <new-disk-id> public
adb shell sm list-volumes public
adb shell sm mount <new-public-volume-id>
```

The harness polls each state transition with a bounded timeout. It identifies
the new public volume by baseline difference rather than a fixed vold ID, then
captures its public volume ID, provider UUID, removable classification, and
`/storage/<uuid>` mount path from `dumpsys mount` and the real StorageManager
bridge. A qualification run observed `disk:7,424`, `public:7,425`, and
provider UUID `8362-1B15` on the API 36 ARM64 emulator.

The Flutter native-boundary test independently confirms the same
`StorageVolume.uuid`, `isRemovable`, opaque browse identity, and durable
`LibraryRootId`. It then uses the device-supported commands below to make
that exact volume unavailable and restore it:

```text
adb shell sm unmount <public-volume-id>
adb shell sm mount <public-volume-id>
```

After the remount, the test requires the same trustworthy provider-volume
identity and the same existing `LibraryRootId`, with no auto-resumed job. A
virtual disk introduced by the run is unmounted, forgotten, and disabled only
when the baseline proved there were no pre-existing adoptable disks. Scoped
evidence is removed on every exit; pre-existing disks and public volumes are
never repartitioned or disabled. If required `sm` functionality is unavailable,
the baseline delta is ambiguous, or same-identity remount cannot be proved,
the script exits with explicit `UNVERIFIED` rather than substituting an
injected identity.

## Verification evidence

The applicable-feature, multi-root Scan All, permission revoke/regrant,
diagnostics publication, existing P02-004 foreground/restart, and removable
volume scenarios passed on the API 36 ARM64 emulator with the repository NDK
selected through `ANDROID_NDK_HOME`. The removable scenario self-provisioned
one virtual public disk, proved the same provider UUID and `LibraryRootId`
across `sm unmount`/`sm mount`, observed no active jobs after remount, and
cleaned the virtual disk and evidence paths back to the empty baseline.
