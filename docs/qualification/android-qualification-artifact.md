# Android qualification artifact packaging

The qualification artifact is an Android Release-configured APK with a
separate install identity. It can be installed beside the ordinary application
without sharing application data or weakening the ordinary Release signing
requirements.

This document covers host packaging and inspection only. It does not authorize
ADB, emulator, device, installation, fixture, credential, or physical
qualification work.

## Artifact contract

| Property | Expected value |
| --- | --- |
| Android application ID | `com.argusromtoolkit.argus.qualification` |
| Ordinary application ID | `com.argusromtoolkit.argus` |
| Android build type | `qualification`, initialized from `release` |
| Flutter execution mode | Release AOT output |
| Debuggable | `false`, including the merged manifest |
| Signing | ordinary Android debug signing configuration |
| Native ABI | `arm64-v8a` only |
| Required native libraries | bridge and native keyring libraries |
| Native Cargo profile | `release` with the production default features |
| Packaged permissions | the exact approved inventory; `INTERNET` and any other addition are rejected |
| FileProvider | `${applicationId}.diagnostics`, URI grants enabled, one `files-path` named `diagnostics` for `argus/diagnostics/` |
| Rust workspace version | equals the Flutter version name embedded in the APK |
| Native debug sections | `.debug_info`, `.debug_line`, and `.debug_str` absent |

The ordinary Release variant continues to require
`ARGUS_RELEASE_KEYSTORE`, `ARGUS_RELEASE_STORE_PASSWORD`,
`ARGUS_RELEASE_KEY_ALIAS`, and `ARGUS_RELEASE_KEY_PASSWORD`. Qualification
packaging does not use that signing configuration. Production Release
packaging fails closed when any required signing value is absent.

The expected debug certificate fingerprint is read from the configured Android
debug keystore with `keytool`. It is not inferred from the APK being inspected.
Gradle or the build script initializes the standard debug keystore on a fresh
host before verification.

## Build and verify

```bash
just build-android-qualification
just verify-android-qualification
```

The public recipe runs `scripts/check_android_qualification_artifact.sh`,
which delegates to the Python verifier. The script name distinguishes an
inspection command from the build command; the recipe name remains the public
interface.

The build command packages `:app:packageQualification` and writes these host
outputs:

- `flutter/build/qualification/argus-qualification.apk`
- `flutter/build/qualification/argus-qualification-provenance.json`
- `flutter/build/qualification/qualification-build.json`
- `flutter/build/qualification/native-build.json`
- `flutter/build/qualification/prebuild-source.json`

The build also works from a checkout that has not generated the Flutter
Android Gradle wrapper. Before it records `prebuild-source.json`, the script
runs:

```bash
fvm flutter build apk --release --config-only --target-platform android-arm64
```

This configuration-only Flutter command creates the ignored Gradle wrapper and
Android local properties without packaging or signing an APK. It requires no
production Release credentials. The qualification packaging step then runs
`:app:packageQualification`. A Debug build is not a prerequisite, and no
blanket Gradle clean task is used.

Android/Gradle tooling may create generated Kotlin state during the build
workflow. Generated Kotlin compiler state under `flutter/android/.kotlin/` is
excluded by `flutter/.gitignore`; it is not product source and therefore cannot
perturb the source fingerprint. Tracked source edits and new untracked,
non-ignored source files remain part of the fingerprint.

The build script records the existing Release and Debug APK SHA-256 values
before the configuration-only Flutter prerequisite runs. It immediately
checks that both files are unchanged after that prerequisite, then repeats
the check after qualification packaging and fails if either artifact was
removed or modified, or if configuration-only created an ordinary APK where
none existed. It never runs a repository-wide or Android `clean` task.

Debug and Release native outputs use separate directories:

- `flutter/build/native-jni/debug`
- `flutter/build/native-jni/release`

The former `flutter/android/app/src/main/jniLibs` directory is excluded from
the Gradle source set. The verifier also compares the complete packaged
non-Flutter native inventory with `native-build.json`, so an undeclared stale
library is rejected even if a source-set regression packages it.

An explicit `--output-dir` is treated as build-owned only when it is empty or
already carries the marker written by the build script. A non-empty unmarked
directory, a non-canonical path containing any symbolic-link component, and a
symlinked `arm64-v8a` entry are rejected before any replacement. The default
Debug and Release directories remain build-owned. This prevents cleanup from
deleting unrelated content. A new ABI directory is staged and stripped before
replacement. The final commit reopens the output directory without following a
symlink, rechecks its ownership marker, and performs the ABI and metadata swap
relative to that pinned directory. If the build fails before commit, the
previous complete ABI remains in place.

`just build-android-bridge` continues to build the Debug-profile bridge used
by the existing Debug workflow. Release and qualification builds run
`cargo ndk ... build --package argus-bridge --locked --release` with
`CARGO_NDK_PLATFORM=30`. The build script applies the pinned NDK's
`llvm-strip --strip-unneeded` to the owned output before hashing. Those hashes
therefore describe the bytes Gradle packages.

## Source stability

Before Gradle starts, the build script records `HEAD`, dirty-tree status, the
changed-path count, and a deterministic SHA-256 fingerprint. Fingerprint format
version 2 covers the complete tracked diff and every untracked non-ignored
source file. For untracked regular files it binds both the file bytes and
permission mode; for untracked symbolic links it binds the target text. Version
1 fingerprints did not bind untracked file modes and are not reused.

Tracked diffs use full Git object IDs, so a checkout's local `core.abbrev`
setting does not change the fingerprint. The same baseline and working-tree
bytes therefore produce the same fingerprint in an independent CI checkout.

The embedded build record and native metadata each carry the source state
observed by their own task. The record task compares its observation with the
pre-build snapshot before Flutter AOT compilation starts. The native task is
shared with the ordinary Release build, so it computes its own snapshot instead
of depending on the qualification record. Final verification recomputes the
working-tree state and requires the pre-build, native, and embedded-record
observations to agree.

The native Gradle task is never considered up to date because its metadata
depends on Git state outside ordinary source-file inputs. This prevents a
revision or dirty-state transition from reusing stale native metadata.

## Flutter Release evidence

For the pinned Flutter 3.44.7 Android engine, normal Profile packaging includes
`lib/arm64-v8a/libvmservice_snapshot.so`. Release does not. The verifier
requires all of the following from packaged APK contents:

- `lib/arm64-v8a/libapp.so` is present;
- `lib/arm64-v8a/libflutter.so` is present;
- `lib/arm64-v8a/libvmservice_snapshot.so` is absent;
- `assets/flutter_assets/kernel_blob.bin` is absent;
- `assets/flutter_assets/isolate_snapshot_data` is absent;
- `assets/flutter_assets/vm_snapshot_data` is absent.

Profile and Release are both non-debuggable, so debuggability alone cannot
distinguish them. The absent VM-service snapshot is an independently observed
packaging consequence of the pinned engine's Release build graph. Normal
packaging is checked here; deliberate repackaging or tampering is outside the
scope of this verifier.

## Independent verification

The verifier opens the APK rather than trusting Gradle task success. Its
APK-derived checks include:

- application ID, version code, version name, minimum SDK, and effective
  non-debuggable state from Android build tools and the merged manifest;
- Application, launch Activity, foreground Service, AndroidX startup provider,
  FileProvider, receivers, exported flags, intent metadata, and unique
  qualification-scoped provider authorities;
- exact equality between the packaged permission set and the approved
  qualification inventory, including the generated
  `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; an unexpected permission such as
  `android.permission.INTERNET` is rejected. The inventory includes
  every `uses-permission*` element, including `uses-permission-sdk-23` and
  `uses-permission-sdk-m`, so API-scoped declarations cannot bypass the
  comparison;
- FileProvider URI grants are enabled and the packaged paths resource exposes
  exactly one `files-path` entry named `diagnostics` at `argus/diagnostics/`;
- ARM64-only library entries, ELF64 class, little-endian encoding, AArch64
  machine type, shared-object type, and absence of `.debug_info`, `.debug_line`,
  and `.debug_str` sections;
- exact equality between every packaged non-Flutter native entry and the
  declared `native-build.json` inventory, including SHA-256 and byte size;
- equality between the `rust/Cargo.toml` workspace version and the packaged
  qualification version name;
- the Flutter Release discriminator described above;
- APK signature validity, signer count, signer certificate SHA-256, and ZIP
  alignment;
- the Android Gradle Plugin version written into the APK's own build metadata.

The verifier also rejects malformed ZIPs, duplicate entries, ZIP members that
declare more than 128 MiB decompressed or more than 256 MiB in aggregate,
absent required libraries, stale extra libraries, unsupported ABIs, invalid
metadata, source mismatches, invalid signatures, Debug payloads, and Profile
payloads. Decompressed-size metadata is checked before the verifier reads an
entry payload.

Exit statuses distinguish failure classes:

| Status | Meaning |
| ---: | --- |
| `0` | Artifact inspection completed; result validated or explicitly provisional |
| `1` | Artifact content or metadata is invalid |
| `2` | Command-line usage is invalid |
| `3` | Required host inspection tooling or input is unavailable |
| `4` | Source state is not eligible for final artifact verification |

## Provenance classification

The provenance document separates two categories:

- `verified` contains facts recovered from the APK: package identity, manifest
  component inventory and flags, signature facts, packaged native hashes and
  ELF facts, Flutter payload markers, APK build metadata, and alignment.
- `declared` contains build-time inputs: the embedded build record, pinned tool
  versions, Cargo command, requested native profile and features, rustc and
  cargo-ndk observations emitted by the native build script, lockfile digest,
  declared native hashes, and source-state records.

The APK does not contain a recoverable Flutter framework version or native
Cargo profile marker. The document therefore labels the Flutter version as a
repository pin and the native command/profile/features as build declarations.
The Android Gradle Plugin version is independently recoverable from the APK's
`META-INF/com/android/build/gradle/app-metadata.properties` entry and is
cross-checked against the repository pin.

The source fingerprint binds a development artifact to the exact source tree.
It does not establish binary equivalence with a distributable Release APK.

## Optional Release comparison

An ordinary Release APK may be supplied for an independent component
comparison. Both environment values are required together:

```bash
ARGUS_QUALIFICATION_COMPARISON_APK=/path/to/app-release.apk \
ARGUS_QUALIFICATION_COMPARISON_REVISION=<full-git-sha> \
just build-android-qualification
```

The revision is an operator declaration because an ordinary Flutter APK does
not embed one. The verifier requires a full 40-character Git revision and never
defaults it to the qualification revision.

For a supplied comparison, verification checks that the APK is a valid,
non-debuggable ordinary application with a Flutter Release payload. It compares
the complete native inventory, hashes, and sizes between both APKs. The APK
digests are expected to differ because package identity and signing differ.
Provenance records the comparison certificate for review but does not claim a
production signer identity unless that identity is independently established.

## Provisional and final results

A dirty source tree produces `PROVISIONAL_ARTIFACT`. The verifier requires the
explicit `--allow-provisional` option for that result, and the artifact is not
eligible for later admission. Without the option, a dirty artifact is rejected
with exit status `4`.

`ARTIFACT_VALIDATED` requires a clean, pinned source revision and matching
pre-build, embedded-record, native-metadata, and final worktree fingerprints.

## CI and limitations

The `android-qualification-release` CI job runs the qualification Python
tests, checks production Release fail-closed behavior, builds the qualification
APK, verifies its provenance, and uploads the APK and provenance files. The
job has not been executed merely by being defined in the workflow.

Host inspection does not install or execute the APK. It does not establish
device behavior, secure-storage isolation, fixture behavior, owner approval, or
physical qualification. These checks require separately authorized
device-admission work.
