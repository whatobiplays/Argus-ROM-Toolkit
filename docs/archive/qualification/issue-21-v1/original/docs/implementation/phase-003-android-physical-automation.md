# Phase 003 Physical Android Release Automation

## 1. Purpose and qualification authority

This test infrastructure gathers bounded technical observations from the
unmodified signed Release application on a dedicated physical GT78-VN device
running Android API 30 with `arm64-v8a`. It does not change the production app
or the existing Phase 002 API 36 qualification contract.

Every scenario has independent `automation_status` and
`owner_qualification_status` fields. Individual automated assertions can pass
while the complete automated scenario remains `BLOCKED` or `NOT RUN`.
Only direct owner observations can establish manual qualification. The runner
never edits the authoritative Phase 003 manual record; its current Android,
content, and Android UX owner statuses remain `NOT RUN`.

## 2. Preconditions and execution

1. Use a clean isolated worktree at an explicitly recorded product commit.
   Keep the original checkout and its local edits untouched.
2. Provide one explicit ADB serial through `--device`. The runner requires
   exactly one connected, online, booted physical USB target with the required
   model, API, and ABI. It revalidates the initial transport and device identity
   before every mutation, including cleanup. A replacement or ambiguous target
   receives no destructive command. The serial is never retained in evidence.
3. Provision the four existing `ARGUS_RELEASE_*` signing variables in the
   process environment or an owner-only regular file outside the repository.
   The file must have mode `0600`, quote values with spaces, and resolve an
   absolute keystore path. The default loader reads literal `NAME=value`
   assignments. Use `--source-signing-env` only for an explicitly trusted
   owner-provisioned shell configuration; source output and tracing are
   suppressed, and only the four signing fields cross the subprocess boundary.
4. Supply an independent Release certificate SHA-256 reference with
   `--certificate-sha256` or `ARGUS_RELEASE_CERTIFICATE_SHA256`, when available.
   Signature validity and identity comparison are separate facts. A locally
   built artifact may proceed with an explicitly unavailable independent
   reference; an external APK requires a matching reference.
5. Designate an owned, read-only host fixture collection. Selected copies use
   private external staging and the fixed device directory
   `/sdcard/ArgusPhase003Qualification/fixtures`. No host collection is edited.

Run the signing-independent preflight:

```bash
bash scripts/run_phase_003_android_physical_qualification.sh \
  --device "$ADB_SERIAL" --fixtures "$OWNED_FIXTURE_DIRECTORY" \
  --preflight-only
```

Build and execute the existing signed Release artifact:

```bash
bash scripts/run_phase_003_android_physical_qualification.sh \
  --device "$ADB_SERIAL" --fixtures "$OWNED_FIXTURE_DIRECTORY" \
  --signing-env "$HOME/.config/argus/release-signing.env" \
  --source-signing-env --build
```

Use `--apk` instead of `--build` only for an independently verified external
artifact. The runner checks package, version, minimum SDK, non-debuggable
packaging, ARM64 native libraries, API-30 signature validity, and available
certificate identity. Local builds use the existing repository builder; its
Rust bridge command does not include Cargo's `--release` flag, which is recorded
separately from Flutter/Android Release packaging.

The default fixture cap is 8192 MiB per bundle and across staged bundles;
`--fixture-limit-mib` may lower it. The pinned Flutter SDK determines NDK
selection when `ANDROID_NDK_HOME` is absent. Missing tools, signing material,
valid fixtures, or observable UI state are explicit blockers, not substituted
debug qualification.

## 3. Automated coverage and owner checkpoints

| Scenario set | Automated observations | Required direct owner observation |
| --- | --- | --- |
| AND-01 | Verified build/install/fresh-state boundary; exposed onboarding choices and folder-selection/confirmation taps; post-confirmation admission persistence UNVERIFIED | Successful Add & Scan, truthful progress and correct populated Library |
| AND-02 | Library control observations; List/Grid transition UNVERIFIED (labels pre-existed tap and selected state was checked immediately); sort-direction label changed and returned | Correct browse/search/filter/sort records, selection and detail |
| AND-03 | Exposed product provider/credential-entry boundary without supplying secrets | Production credential storage, real readiness/hydration/artwork and actionable recovery |
| AND-04 | Guarded HOME/foreground transition; fixed Library-control return is a partial fallback | One authoritative runtime/job state and truthful progress/interruption |
| AND-05 | Guarded force-stop/relaunch; fixed Library-control return is a partial fallback | Committed-state persistence, interruption during active refresh, no silent resume and explicit retry |
| AND-06, CNT-11 | Removable-volume prerequisite inspection only | Genuine supported media unavailability and restoration; absent capability is BLOCKED |
| CNT-01–07 | Bounded fixture structure/header and descriptor/playlist dependency inspection | Actual identification, archive extraction, grouping and coherent Library/detail presentation |
| CNT-08–10 | No positive assertion from fixture inventory alone | Equivalent-representation convergence, unmatched fallback, real metadata/artwork hydration |
| CNT-12 | Safe malformed-fixture test infrastructure can establish preparation only | Understandable failure without corrupting unrelated Library state |
| UX-A01 | No inference of announcement quality | Listen to TalkBack labels, roles, focus, progress, errors and recovery |
| UX-A02 | Recognized actionable geometry, where exposed | Practical touch sizing, spacing and usability |
| UX-A03 | Geometry observations during attempted font-scale settings; no applied-scale readback, so scale-specific geometry UNVERIFIED | Critical Library/detail readability, reachability and clipping across supported font/display scales |

Historical automated outcomes report driver observations and host-side checks; a recorded PASS is not proof of the corresponding product outcome. Section 7 separates those emitted statuses from the current evidence assessment. Section 6 preserves the original test records verbatim.

Android folder selection uses Argus's native-backed filesystem browser.
The driver refuses absent, ambiguous, disabled, foreign-package or malformed
accessibility targets. Bounded scrolling derives gestures from a freshly
observed unique scrollable container and still requires exact visible labels
before selection. It does not guess screen coordinates, inject database
state or call debug qualification APIs. Partial UI controls cannot establish
record identity, runtime uniqueness, provider matches or content correctness.

## 4. Privacy, restoration and result handling

1. UI XML and command output exist only transiently in memory. The fixed owned
   XML file is removed after each capture. No screenshots or recordings are
   captured. Evidence uses fixed labels and aggregate technical facts; source
   names, paths, hashes, payloads, serials and signing values are excluded.
2. Configuration changes must go through `SettingsSnapshot`. It captures
   original values before mutation, restores changed values on normal exit,
   exception or interruption, and verifies restoration. Missing original
   settings are restored with `settings delete`. Unreachable/replaced devices
   produce cleanup blockers requiring owner follow-up. The current UI driver
   changes no Android settings itself.
   The runner invokes the geometry probe at font scales 1.3 and 2.0 inside
   the snapshot boundary; display-size coverage remains a direct owner check.
   API 30 all-files access is separately snapshotted for the Argus package,
   temporarily enabled before backend startup, and restored to its original
   app-operation mode with bounded verification. This configuration does not
   accept product privacy terms or bypass provider setup.
3. Private host staging is deleted on exit. Device fixture cleanup remains
   confined to an exclusively created fixed test-owned directory and is
   reported explicitly. Existing directory collisions are refused without
   deleting or reusing their contents.
   `--retain-fixtures-for-owner` explicitly retains the exclusively created
   device collection for immediate owner checkpoints. An uncertain directory
   creation result requires owner inspection and is never reported as cleaned.
   The installed Release app remains installed; its pre-test app data is not
   restored because this dedicated device has authorized fresh-state resets.
4. Sanitized stdout is an execution report, not owner qualification. The owning
   delegation's `RESULT.json` is the sole durable result artifact. Preserve all
   21 rows and their independent owner statuses when transferring evidence.
   Exit `2` means incomplete, blocked or failed coverage; partial execution
   must not become a green command result.

## 5. Verification

Run the focused deterministic safety/fixture/UI tests from the worktree root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/phase_003_android_physical_qualification -p 'test_*.py'
shellcheck scripts/run_phase_003_android_physical_qualification.sh
```

The same host-only Python discovery command is the first stage of `just test`.
It uses generated temporary fixtures and simulated transports; it does not run
the physical qualification runner, ADB, or signing workflows. Running it first
keeps these deterministic regression results visible even when a later
environment-dependent macOS test cannot start.

The qualification harness requires Python 3.9 or newer: it uses
`pathlib.Path.is_relative_to` and built-in generic annotations. The suite passed
on Python 3.10.22 and 3.14.4; Python 3.9 was not installed on the validation
host, so that exact runtime remains unverified.

The repository's allowlisted `all` profile resolves to `just check`. Run it in
the isolated worktree. Report its actual outcome and separately report focused
checks that ran after an early failure. Do not weaken a failed gate or repair
production/build infrastructure outside this delegation's authorization.

## 6. Verbatim original test records

This archive preserves every sanitized string from the original 24-entry `RESULT.tests` array exactly as recorded before the schema-length repair. Records 04–24 are the serialized scenario rows; the parsed matrix follows in section 7. The compact `RESULT.tests` entries point back to this archive and do not replace its evidence.

### Original test record 01

```text
180 focused tests PASS; core97.3%, fixtures96.0%, runner99.3%, UI99.5% executable-line coverage.
```

### Original test record 02

```text
Canonical just check PASS; Rust suite and 620 Flutter tests PASS; ShellCheck PASS.
```

### Original test record 03

```text
Physical setup/build/artifact and cleanup: {"timestamp_utc":"2026-10-12T21:47:49.743970+00:00","blockers":["Full Release UI scenario coverage remains blocked by missing or non-actionable exact accessibility targets and an unproven populated Library.","Independent established Release certificate reference is unavailable.","Real provider-match/hydration fixture evidence, TalkBack installation, and genuine removable-media unavailability prerequisites are outstanding."],"device_mutations":true,"settings_cleanup":"RESTORED","device_fixture_cleanup":"RETAINED FOR OWNER CHECKPOINTS","device":{"model":"GT78-VN","api":30,"abi":"arm64-v8a","physical_usb":true,"boot_completed":true,"target_count":1},"removable_media":{"public_volume_count":0,"genuine_unavailability_test":"OWNER REQUIRED"},"fixtures":{"status":"ok","provider_match":"unverified","selected_ready":true,"rejected_symlinks":0,"scan_errors":0,"seven_zip_tool_available":true,"classes":{"nes":{"candidates":37,"structurally_validated":36,"header_validated":0,"invalid":1,"oversized":0,"unsupported":0,"ready":36},"iso":{"candidates":1,"structurally_validated":0,"header_validated":1,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"cue":{"candidates":4,"structurally_validated":4,"header_validated":0,"invalid":0,"oversized":0,"unsupported":0,"ready":4},"m3u":{"candidates":1,"structurally_validated":1,"header_validated":0,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"zip":{"candidates":1,"structurally_validated":1,"header_validated":0,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"seven_zip":{"candidates":0,"structurally_validated":0,"header_validated":0,"invalid":0,"oversized":0,"unsupported":0,"ready":0},"chd":{"candidates":1,"structurally_validated":0,"header_validated":1,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"rvz":{"candidates":1,"structurally_validated":0,"header_validated":1,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"cso":{"candidates":1,"structurally_validated":0,"header_validated":1,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"wbfs":{"candidates":1,"structurally_validated":0,"header_validated":1,"invalid":0,"oversized":0,"unsupported":0,"ready":1},"unknown":{"candidates":394,"structurally_validated":0,"header_validated":0,"invalid":0,"oversized":0,"unsupported":394,"ready":0}}},"signing":{"configured_fields":4,"required_fields":4,"independent_certificate_reference":"UNAVAILABLE"},"build":{"attempted":true,"status":"PASS"},"artifact":{"package":"com.argusromtoolkit.argus","version":"0.1.0","version_code":1,"min_sdk":30,"abi":"arm64-v8a","debuggable":false,"signature_valid":true,"release_certificate_reference":"UNAVAILABLE","provenance":"built_from_recorded_commit","source_commit":"c945062c0927508ae294c51c2b7d5719a35e5906","native_profile":"existing repository bridge builder; no cargo --release flag"},"staged_fixtures":{"status":"ok","provider_match":"unverified","staged_bundles":9,"staged_bytes":5663089535,"failed_bundles":0,"skipped_bundles":0,"classes":{"nes":{"staged":1,"structural":1,"header_only":0},"iso":{"staged":1,"structural":0,"header_only":1},"cue":{"staged":1,"structural":1,"header_only":0},"m3u":{"staged":1,"structural":1,"header_only":0},"zip":{"staged":1,"structural":1,"header_only":0},"seven_zip":{"staged":0,"structural":0,"header_only":0},"chd":{"staged":1,"structural":0,"header_only":1},"rvz":{"staged":1,"structural":0,"header_only":1},"cso":{"staged":1,"structural":0,"header_only":1},"wbfs":{"staged":1,"structural":0,"header_only":1},"unknown":{"staged":0,"structural":0,"header_only":0}},"synthetic_probes":2},"app_preparation":{"previous_install_removed":true,"installed":true,"fresh_state_confirmed":true,"storage_access_configured":true},"storage_access_cleanup":"RESTORED"}
```

### Original test record 04

```text
{"scenario":"AND-01","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[{"check":"ui_observation","status":"BLOCKED","detail":"Required Release accessibility target was not observed in time."},{"check":"startup_surface","status":"PASS","detail":"A recognized Release Library or onboarding surface is observable."},{"check":"accept_terms","status":"PASS","detail":"An exposed onboarding choice was invoked through the product UI."},{"check":"preferences","status":"PASS","detail":"An exposed onboarding choice was invoked through the product UI."},{"check":"skip_provider","status":"PASS","detail":"An exposed onboarding choice was invoked through the product UI."},{"check":"owned_root_admitted","status":"PASS","detail":"Exact test-owned primary-storage folder selected and confirmed through the unmodified Release UI."},{"check":"library_navigation","status":"BLOCKED","detail":"The observed Library label was non-actionable; the driver refused coordinate guessing."}],"reason":"Root admission completed; actionable Library navigation and populated Library correctness were not established.","owner_checkpoint":"Observe fresh Release onboarding, native folder selection, Add & Scan and a usable populated Library."}
```

### Original test record 05

```text
{"scenario":"AND-02","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[{"check":"library_controls","status":"PASS","detail":"A unique Library refresh control is observable; view and sort controls are evaluated separately."},{"check":"view_list","status":"PASS","detail":"The requested view-mode control exposes selected state."},{"check":"view_grid","status":"PASS","detail":"The requested view-mode control exposes selected state."},{"check":"sort_direction_toggle","status":"PASS","detail":"The sort-direction control changed and returned to its original label."}],"reason":"Control transitions do not prove search/filter results, ordering, paging, stable selection, or game-detail correctness.","owner_checkpoint":"Observe correct browse, search, filter, sort and corresponding game detail."}
```

### Original test record 06

```text
{"scenario":"AND-03","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe provider configuration, secret-safe production credential storage, real hydration and actionable recovery."}
```

### Original test record 07

```text
{"scenario":"AND-04","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[{"check":"surface_return","status":"PASS","detail":"Unique enabled refresh, Grid and List controls are observable after the lifecycle transition."}],"reason":"Fixed surface return does not prove jobs, records, active-work interruption, automatic-resume policy, or explicit retry.","owner_checkpoint":"Observe truthful progress and coherent Library/Jobs state across background and foreground transitions."}
```

### Original test record 08

```text
{"scenario":"AND-05","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[{"check":"surface_return","status":"PASS","detail":"Unique enabled refresh, Grid and List controls are observable after the lifecycle transition."}],"reason":"Fixed surface return does not prove jobs, records, active-work interruption, automatic-resume policy, or explicit retry.","owner_checkpoint":"Observe persisted state, truthful interrupted refresh, no silent resume and successful explicit retry."}
```

### Original test record 09

```text
{"scenario":"AND-06","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[],"reason":"Owner media-unavailability checkpoint required; volumes are not unmounted.","owner_checkpoint":"Disconnect and restore genuine configured removable media; observe non-destructive recovery."}
```

### Original test record 10

```text
{"scenario":"CNT-01","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_nes","status":"PASS","detail":"Structurally checked=36; header-only=0; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe native cartridge identification and coherent Library/detail presentation."}
```

### Original test record 11

```text
{"scenario":"CNT-02","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_iso","status":"PASS","detail":"Structurally checked=0; header-only=1; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe native optical-image identification and coherent presentation."}
```

### Original test record 12

```text
{"scenario":"CNT-03","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_cue","status":"PASS","detail":"Structurally checked=4; header-only=0; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe descriptor plus dependent tracks admitted as coherent logical content."}
```

### Original test record 13

```text
{"scenario":"CNT-04","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_m3u","status":"PASS","detail":"Structurally checked=1; header-only=0; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe playlist/multi-disc grouping without unwanted duplicate games."}
```

### Original test record 14

```text
{"scenario":"CNT-05","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_zip","status":"PASS","detail":"Structurally checked=1; header-only=0; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe a valid ZIP/7z admitted, extracted, identified and presented as one coherent logical game."}
```

### Original test record 15

```text
{"scenario":"CNT-06","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_chd","status":"PASS","detail":"Structurally checked=0; header-only=1; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe valid CHD identification and coherent presentation."}
```

### Original test record 16

```text
{"scenario":"CNT-07","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"host_fixture_rvz","status":"PASS","detail":"Structurally checked=0; header-only=1; device content behavior unverified"},{"check":"host_fixture_cso","status":"PASS","detail":"Structurally checked=0; header-only=1; device content behavior unverified"},{"check":"host_fixture_wbfs","status":"PASS","detail":"Structurally checked=0; header-only=1; device content behavior unverified"}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe a valid RVZ, CSO or WBFS representation identified and presented."}
```

### Original test record 17

```text
{"scenario":"CNT-08","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe two supported equivalent representations converge without duplicate logical games."}
```

### Original test record 18

```text
{"scenario":"CNT-09","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe identified unmatched content remains visible with bounded fallback presentation."}
```

### Original test record 19

```text
{"scenario":"CNT-10","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe successful real provider metadata and artwork hydration in Library/detail."}
```

### Original test record 20

```text
{"scenario":"CNT-11","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[],"reason":"Owner media-unavailability checkpoint required; volumes are not unmounted.","owner_checkpoint":"Observe temporary content/source unavailability and restoration without false orphan/destructive behavior."}
```

### Original test record 21

```text
{"scenario":"CNT-12","automation_status":"NOT RUN","owner_qualification_status":"NOT RUN","assertions":[{"check":"safe_negative_fixture_prepared","status":"PASS","detail":"Two synthetic cartridge probes, including deliberately malformed input, were uploaded; runtime rejection and isolation were not verified."}],"reason":"UI scenario has not been evaluated.","owner_checkpoint":"Observe a malformed/unsupported safe fixture fails understandably without corrupting unrelated Library state."}
```

### Original test record 22

```text
{"scenario":"UX-A01","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[],"reason":"TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks.","owner_checkpoint":"With TalkBack enabled, listen to labels, roles, focus, progress, errors and recovery in Library/detail."}
```

### Original test record 23

```text
{"scenario":"UX-A02","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[{"check":"touch_input_geometry","status":"PASS","detail":"Successful automated view and sort taps used freshly parsed positive control bounds; physical sizing and usability were not assessed."}],"reason":"TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks.","owner_checkpoint":"Directly exercise critical touch actions and judge sizing, spacing and practical usability."}
```

### Original test record 24

```text
{"scenario":"UX-A03","automation_status":"BLOCKED","owner_qualification_status":"NOT RUN","assertions":[{"check":"font_scale_1.3","status":"PASS","detail":"Recognized actionable controls exposed positive geometry at this font scale; readability and clipping require owner observation."},{"check":"font_scale_2.0","status":"PASS","detail":"Recognized actionable controls exposed positive geometry at this font scale; readability and clipping require owner observation."}],"reason":"TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks.","owner_checkpoint":"Inspect Library/detail at supported font and display scales for readable, reachable, unclipped controls."}
```

## 7. Complete 21-row scenario matrix

Each row retains the original automated status and owner qualification status independently. Assertion outcomes, reasons, and direct owner checkpoints are parsed from original test records 04–24. Every owner qualification status remains `NOT RUN`.

| Scenario | Historical automation status | Owner qualification status | Historical recorded assertions | Current evidence assessment | Recorded reason | Direct owner checkpoint | Latest live-probe update |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AND-01 | BLOCKED | NOT RUN | BLOCKED — `ui_observation`: Required Release accessibility target was not observed in time.<br>PASS — `startup_surface`: A recognized Release Library or onboarding surface is observable.<br>PASS — `accept_terms`: An exposed onboarding choice was invoked through the product UI.<br>PASS — `preferences`: An exposed onboarding choice was invoked through the product UI.<br>PASS — `skip_provider`: An exposed onboarding choice was invoked through the product UI.<br>PASS — `owned_root_admitted`: Exact test-owned primary-storage folder selected and confirmed through the unmodified Release UI.<br>BLOCKED — `library_navigation`: The observed Library label was non-actionable; the driver refused coordinate guessing. | INVALIDATED for `owned_root_admitted`: only folder selection/confirmation tap was observed; post-confirmation admission persistence is UNVERIFIED. Other historical onboarding/tap observations remain narrow. Library navigation remains BLOCKED. | Folder selection/confirmation tap observed, but admission persistence was not verified; actionable Library navigation and populated Library correctness were not established. | Observe fresh Release onboarding, native folder selection, Add & Scan and a usable populated Library. | Final 240 dpi / 853 dp fresh-Activity probe still exposed only Library, Refresh, and empty Library; Jobs/Search/LibraryScan/status/Retry/progress/typed errors were absent. Accessibility/control-exposure blocker; route absence and product root cause not established. |
| AND-02 | BLOCKED | NOT RUN | PASS — `library_controls`: A unique Library refresh control is observable; view and sort controls are evaluated separately.<br>PASS — `view_list`: The requested view-mode control exposes selected state.<br>PASS — `view_grid`: The requested view-mode control exposes selected state.<br>PASS — `sort_direction_toggle`: The sort-direction control changed and returned to its original label. | UNVERIFIED transition for `view_list` and `view_grid`: labels already existed before tap and selected state was checked immediately, without a bounded transition oracle. Control visibility and the observed sort-label change remain narrow historical facts; browse/search/filter/order/detail remain unverified. | Control transitions do not prove search/filter results, ordering, paging, stable selection, or game-detail correctness. | Observe correct browse, search, filter, sort and corresponding game detail. | Final Library probe exposed no Jobs/Search/LibraryScan/status/Retry/progress/typed errors. No guessed navigation or action; browse/search/filter/order/detail correctness remains unverified. |
| AND-03 | NOT RUN | NOT RUN | No automated assertions recorded. | No provider/credential outcome established; the historical boundary observation does not verify secure storage, hydration, or recovery. | UI scenario has not been evaluated. | Observe provider configuration, secret-safe production credential storage, real hydration and actionable recovery. | No provider or credential interaction occurred in the final probe; provider setup, secret-safe storage, hydration, and recovery remain unverified. |
| AND-04 | BLOCKED | NOT RUN | PASS — `surface_return`: Unique enabled refresh, Grid and List controls are observable after the lifecycle transition. | Historical surface controls were observable after the lifecycle transition; no authoritative job state, active-work interruption, automatic resume, or retry outcome established. | Fixed surface return does not prove jobs, records, active-work interruption, automatic-resume policy, or explicit retry. | Observe truthful progress and coherent Library/Jobs state across background and foreground transitions. | Normal process relaunch was observed only. Jobs/status controls remained absent; active-job interruption and automatic recovery were NOT RUN. |
| AND-05 | BLOCKED | NOT RUN | PASS — `surface_return`: Unique enabled refresh, Grid and List controls are observable after the lifecycle transition. | Historical surface controls were observable after process relaunch; persistence, active-work interruption, no-silent-resume policy, and explicit retry remain unverified. | Fixed surface return does not prove jobs, records, active-work interruption, automatic-resume policy, or explicit retry. | Observe persisted state, truthful interrupted refresh, no silent resume and successful explicit retry. | Normal process relaunch was observed only. Explicit retry and interrupted-work recovery were NOT RUN; Retry/status controls remained absent. |
| AND-06 | BLOCKED | NOT RUN | No automated assertions recorded. | No removable-media disconnect/restore performed; owner checkpoint remains pending. | Owner media-unavailability checkpoint required; volumes are not unmounted. | Disconnect and restore genuine configured removable media; observe non-destructive recovery. | No removable-media disconnect/restore was performed; existing owner checkpoint remains pending. |
| CNT-01 | NOT RUN | NOT RUN | PASS — `host_fixture_nes`: Structurally checked=36; header-only=0; device content behavior unverified | Host fixture structure only; device identification and Library/detail behavior remain unverified. | UI scenario has not been evaluated. | Observe native cartridge identification and coherent Library/detail presentation. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-02 | NOT RUN | NOT RUN | PASS — `host_fixture_iso`: Structurally checked=0; header-only=1; device content behavior unverified | Host fixture structure only; device identification and presentation remain unverified. | UI scenario has not been evaluated. | Observe native optical-image identification and coherent presentation. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-03 | NOT RUN | NOT RUN | PASS — `host_fixture_cue`: Structurally checked=4; header-only=0; device content behavior unverified | Host fixture structure only; device grouping and presentation remain unverified. | UI scenario has not been evaluated. | Observe descriptor plus dependent tracks admitted as coherent logical content. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-04 | NOT RUN | NOT RUN | PASS — `host_fixture_m3u`: Structurally checked=1; header-only=0; device content behavior unverified | Host fixture structure only; playlist/multi-disc grouping remains unverified. | UI scenario has not been evaluated. | Observe playlist/multi-disc grouping without unwanted duplicate games. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-05 | NOT RUN | NOT RUN | PASS — `host_fixture_zip`: Structurally checked=1; header-only=0; device content behavior unverified | Host fixture structure only; device archive admission, extraction, identification, and presentation remain unverified. | UI scenario has not been evaluated. | Observe a valid ZIP/7z admitted, extracted, identified and presented as one coherent logical game. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-06 | NOT RUN | NOT RUN | PASS — `host_fixture_chd`: Structurally checked=0; header-only=1; device content behavior unverified | Host fixture structure only; device identification and presentation remain unverified. | UI scenario has not been evaluated. | Observe valid CHD identification and coherent presentation. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-07 | NOT RUN | NOT RUN | PASS — `host_fixture_rvz`: Structurally checked=0; header-only=1; device content behavior unverified<br>PASS — `host_fixture_cso`: Structurally checked=0; header-only=1; device content behavior unverified<br>PASS — `host_fixture_wbfs`: Structurally checked=0; header-only=1; device content behavior unverified | Host fixture structure only; device identification and presentation remain unverified. | UI scenario has not been evaluated. | Observe a valid RVZ, CSO or WBFS representation identified and presented. | No new device content-identification evidence; prior host fixture structural result remains host-only. |
| CNT-08 | NOT RUN | NOT RUN | No automated assertions recorded. | No device evidence for equivalent-representation convergence or deduplication. | UI scenario has not been evaluated. | Observe two supported equivalent representations converge without duplicate logical games. | No new device evidence; equivalent-representation convergence and deduplication remain unverified. |
| CNT-09 | NOT RUN | NOT RUN | No automated assertions recorded. | No device evidence for unmatched-content fallback presentation. | UI scenario has not been evaluated. | Observe identified unmatched content remains visible with bounded fallback presentation. | No new device evidence for unmatched-content fallback presentation. |
| CNT-10 | NOT RUN | NOT RUN | No automated assertions recorded. | No device evidence for provider metadata/artwork hydration. | UI scenario has not been evaluated. | Observe successful real provider metadata and artwork hydration in Library/detail. | No provider hydration evidence was produced by the final Library-only probe. |
| CNT-11 | BLOCKED | NOT RUN | No automated assertions recorded. | No media/source unavailability or restoration performed; owner checkpoint remains pending. | Owner media-unavailability checkpoint required; volumes are not unmounted. | Observe temporary content/source unavailability and restoration without false orphan/destructive behavior. | No removable-media/source unavailability or restoration was exercised; owner checkpoint remains pending. |
| CNT-12 | NOT RUN | NOT RUN | PASS — `safe_negative_fixture_prepared`: Two synthetic cartridge probes, including deliberately malformed input, were uploaded; runtime rejection and isolation were not verified. | Fixture preparation only; runtime rejection and isolation remain unverified. | UI scenario has not been evaluated. | Observe a malformed/unsupported safe fixture fails understandably without corrupting unrelated Library state. | No runtime malformed-input rejection/isolation evidence was produced by the final probe. |
| UX-A01 | BLOCKED | NOT RUN | No automated assertions recorded. | No TalkBack/physical accessibility outcome established; owner checkpoint remains pending. | TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks. | With TalkBack enabled, listen to labels, roles, focus, progress, errors and recovery in Library/detail. | TalkBack critical-flow announcements and physical accessibility remain owner NOT RUN; probe establishes missing Jobs/Search controls at this configuration. |
| UX-A02 | BLOCKED | NOT RUN | PASS — `touch_input_geometry`: Successful automated view and sort taps used freshly parsed positive control bounds; physical sizing and usability were not assessed. | Historical positive geometry supports tap targeting only; physical touch sizing and usability remain unverified. | TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks. | Directly exercise critical touch actions and judge sizing, spacing and practical usability. | Density helper tests passed and 240 dpi / 853 dp were confirmed; density/default storage restoration was verified. Physical touch sizing/usability remains owner NOT RUN. |
| UX-A03 | BLOCKED | NOT RUN | PASS — `font_scale_1.3`: Recognized actionable controls exposed positive geometry at this font scale; readability and clipping require owner observation.<br>PASS — `font_scale_2.0`: Recognized actionable controls exposed positive geometry at this font scale; readability and clipping require owner observation. | UNVERIFIED for `font_scale_1.3` and `font_scale_2.0`: applied scale was not read back or associated with the geometry measurements. Readability/clipping and owner checks remain unverified. | TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks. | Inspect Library/detail at supported font and display scales for readable, reachable, unclipped controls. | Density helper tests passed (45); 240 dpi / 853 dp confirmed. Six normal Library captures and final fresh-process probe still showed only Library, Refresh, and empty Library; 240 dpi was not established as exposing Jobs/Search. Owner readability/clipping check remains NOT RUN. |

## 8. Supplemental responsive Jobs observations

A bounded refresh probe confirmed the Argus app operation was `allow`; after Refresh was tapped from an empty Library, a per-root `Failed` result persisted. The overall Job status remains unknown. This observation does not establish a complete Jobs scenario result or a product defect.

At the observed 1280 × 960 physical resolution and 320 dpi, the effective viewport is 640 × 480 dp. The medium-width shell hides NavigationRail labels, so the exact Jobs destination is absent in that layout. This is recorded as a responsive accessibility limitation of the observation surface. Source contains `jobLibraryScan`, `JobStatus`, and conditional retry confirmation, but their presence does not establish the missing overall status or successful retry.

A test-only `DisplayDensitySnapshot` at 240 dpi now supports an effective width of approximately 853 dp. The density-helper tests passed (45). The researcher applied 240 dpi, confirmed the effective 853 dp viewport, and restored the default density and storage settings. The final fresh-process probe at this viewport still exposed only Library, Refresh, and an empty Library; Jobs/Search and related job controls remained absent as recorded above. This establishes the viewport setup/restoration and the observed surface only; it does not establish complete Jobs behavior or an owner qualification pass. The retry flow was not executed and remains unverified.

## 9. Final live-probe and review-history update

### Implementation and verification reported for this checkpoint

The coder reports that the six harness findings from the prior review wave were addressed in the 229-test snapshot; its full focused suite passed 229 tests and targeted regression groups passed 12 and 5 tests. The combined cleanup/product-failure and SIGTERM-during-storage-restoration fix then passed a 230-test full suite and an integrated three-case regression set. The symmetric settings-cleanup SIGTERM fix passed the 231-test suite. The latest retention-status truthfulness fix is in `runner.py` and `test_runner.py`; the coder reports the full focused suite passed 232 tests and `bash -n` passed, and an independent check also reports 232 tests passing. The retention fix ensures a fixture-push failure is not reported as successful retention. The current device fixtures were confirmed present and unaffected. These are reported harness results, not physical qualification evidence. The density-helper verification reported 45 tests passing; the researcher confirmed the 240 dpi / 853 dp viewport and restored default density/storage settings. The integrated settings-restoration regression preserves pending UI/product-failure evidence across SIGTERM, restores settings and storage, prevents a second scaling probe, and keeps owner statuses NOT RUN. UI XML was absent.

### Final bounded physical observation

A fresh Activity and Flutter engine were started after a verified production-component process relaunch at 240 dpi / 853 dp. The visible surface remained Library, Refresh, and an empty Library. Jobs, Search, LibraryScan, overall job status, Retry, progress, and typed errors were not exposed. No guessed navigation, retry, or query was attempted. This supports an accessibility/control-exposure blocker at the tested configuration; it does not establish visual route absence or a product root cause.

A prior per-root `Failed` state persisted while app-op access was allowed and followed an actual scan terminal state. Because no typed error or overall job status was exposed, its cause cannot be classified as permission, source, or product failure. Overall job status remains unknown. Only a normal process relaunch was observed; active-job interruption and recovery remain NOT RUN. Aggregate configuration was not attributable to the Argus Activity; the manifest handles density and a cached engine. Source predicts labels, but the display/system-metric versus Activity-configuration mismatch remains unclassified.

### Review-gate history and remaining findings

The initial reviewer gate returned `ok: true`, accepted the schema, and detected the review bundle, while technical readiness failed because the result remained blocked, TAC-4 was unverified, validation was stale, and 15 later-authorized review-bundle paths were flagged against the immutable original scope. Preserve this as a technical-audit/tool-binding limitation unless the reviewer documents a supported mechanism. The original PROMPT and the approved review materials remain intact.

Cubic’s initial review reported seven findings and its second review reported five; an earlier local run exited 1 with five findings plus a separate hidden-UI-XML cleanup finding. Later reviews found six harness findings, the combined cleanup/cancellation path, and the symmetric settings-cleanup SIGTERM path; the coder reports those fixes are included in the 229-, 230-, and 231-test snapshots respectively. Cubic on the 231-test snapshot exited 1 with three P2 comments: independent triage validated the runner retention-status issue and sent it for correction; the other two comments were disputed because the scan loop has a status guard and the private 0700 staging concern assumes a same-UID actor outside caller ownership. The retention-status truthfulness fix is now in `runner.py` and `test_runner.py` in the 232-test snapshot. The latest local Cubic run on that exact 11-file snapshot exited 1 with one P1 comment. Independent triage disputed that comment: UI failures from UI paths are caught and recorded by the scenario wrapper before storage/settings cleanup, while cleanup interruption carries `ui_product_failure_observed` and scenario metadata. No new validated code issue was found; final Cubic review of this snapshot was requested. The synchronized 11-file bundle includes the 232-test source and reconciled qualification document and is ready for the repository review gate. Final model/Cubic review remains pending; no clean-review result is claimed. RESULT remains blocked pending final review and physical qualification.

All owner qualification checkpoints in the matrix remain NOT RUN. No additional product behavior is claimed from the documentation or host-test results above.

## 10. Final independent review and repository-gate outcome (2026-10-12)

The final independent model review found no validated harness blocker. Independent verification reports 232 focused tests and `bash -n` passing. The final source audit confirmed all 11 bundle copies match the worktree and the SHA-256 manifest; all 21 owner qualification statuses remain NOT RUN.

The final source-inclusive Cubic run exited 1 with one disputed P1: `UIFailed` is recorded by the scenario wrappers before snapshot cleanup, and interrupted capture cleanup preserves failure and scenario metadata. Two earlier P2 comments were also disputed: the outer scan limit has a status guard, and the exclusive private staging tree is outside the caller-ownership boundary. No validated Cubic issue remains. This review outcome does not establish physical qualification.

The final `repo_codex_review` run on the original repository returned `ok: true` and accepted the schema, but technical readiness FAILED. It flagged 15 new bundle additions against the immutable original scope; there is no scope-amendment lineage in the review record. The compact diff summary reported `file_count=0` because review-path recognition was not source-inclusive, despite the verified source bundle. TAC-4 remains unverified, the RESULT remains blocked, and the gate did not pass.

The separate connected `ship_readiness.validation` record is stale: profile `test`, validation id `validation-2026-10-07T23-44-45-375Z-3d6a3e7e`, recorded at old HEAD `ebf98983…` rather than current base `c945062c0927508ae294c51c2b7d5719a35e5906`. The RESULT retains its historical canonical `just check` pass, but the gate accepted no current state-bound canonical validation. This gate-validation gap is separate from TAC-4's unverified physical UI evidence; its authoritative RESULT status and evidence remain unchanged.
