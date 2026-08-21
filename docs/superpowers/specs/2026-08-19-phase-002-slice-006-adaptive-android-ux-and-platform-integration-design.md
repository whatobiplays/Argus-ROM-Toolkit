# P02-006 Adaptive Android UX and Platform Integration Design

**Status:** Approved design
**Date:** 2026-08-19
**Phase:** PHASE-002
**Slice:** SLICE-P02-006

## 1. Purpose

P02-006 hardens the existing Argus Flutter and Android presentation/platform integration across phones, tablets, foldables, split-screen windows, and gaming handhelds. It preserves the established route, controller, runtime, provider, foreground-execution, and persistence authorities while making adaptive transitions, Android Back, system insets, accessibility, picker interaction, and Activity lifecycle behavior production-ready.

This is targeted hardening over the existing architecture, not a redesign or a new Android presentation stack.

## 2. Architecture

- `core/responsive` remains the sole global size-class authority: Compact `<600`, Medium `600–839`, Expanded `840–1199`, Large `>=1200` logical pixels.
- Shared Flutter presentation owns width-driven layout, touch targets, text scaling, accessibility semantics, focus behavior, overflow handling, and local inset-aware layout.
- Shared adaptive defects are fixed in shared Flutter presentation rather than hidden behind Android-specific wrappers.
- `go_router` remains the sole routed-navigation authority. Android Back and predictive Back use Flutter's supported navigator/pop pipeline rather than a second Back coordinator or route graph.
- Feature-local transient presentation may consume Back only when it has a meaningful action to perform, such as navigating to a picker parent, retreating through Compact hierarchy, or dismissing an active transient inspector/modal.
- `app/platform` owns only genuinely Android-specific mechanics, including native system-UI integration, lifecycle observation, and platform qualification hooks.
- Existing Sources, Jobs, Settings, startup, Rust/application runtime, SQLite, foreground-service, job, provider, and reconciliation authorities remain unchanged.
- Rotation, Activity recreation, resize, split-screen, and fold/unfold preserve the application-scoped Flutter engine/composition and valid process-lifetime UI state.
- Process death remains a restart boundary governed by existing recovery semantics. P02-006 does not add durable persistence for picker position, scroll state, open inspectors, or other transient presentation state.

The central invariant is: environmental presentation changes may restructure the UI, but must not change semantic route identity, backend authority, or valid user context.

## 3. Scope

### 3.1 Shared adaptive hardening

P02-006 fixes both behavioral defects and targeted presentation weaknesses where current UI is technically functional but poor on Android-relevant form factors. Work may include layout structure, spacing, overflow, touch targets, large-text behavior, focus, semantics, and local constraint handling while preserving the existing design system and feature architecture.

No layout decision may depend on Android device category, orientation name, hardware model, or pointer presence. Global application structure remains width-driven, with child regions free to adapt to their own local constraints.

### 3.2 Application shell

The application shell must:

- preserve canonical route identity and branch history through Compact/Medium/Expanded/Large transitions;
- retain Sources, Jobs, and Settings as direct Compact destinations under the current Phase 002 catalog;
- preserve Jobs active-work badge semantics across presentations;
- remain usable by touch and by keyboard/pointer when those inputs are present;
- tolerate live resize, rotation, split-screen, and fold/unfold without constructing a second navigation state model.

### 3.3 Sources

Sources must preserve valid process-lifetime context across adaptive and Activity-lifecycle changes, including selected root and hierarchy context. Compact drill-down and wider hierarchy presentations share the existing controller state and stable identities. When presentation structure changes, semantic selection remains stable where valid.

Transient hierarchy state that becomes invalid because authoritative data changed retreats to the nearest valid ancestor/root or clears only the invalid selection. Environmental changes alone do not reset valid hierarchy state.

### 3.4 Argus folder picker

P02-006 hardens the existing Argus-owned local-filesystem picker without redesigning its provider model or selection contract.

The picker must:

- preserve its valid current opaque browse location and loaded process-lifetime state across rotation, Activity recreation, resize, split-screen, and fold/unfold;
- consume Back as parent-hierarchy navigation before picker dismissal when a parent exists;
- preserve provider-owned opaque location/cursor contracts and never expose raw provider identity as presentation authority;
- handle unavailable/removable-volume transitions safely through existing platform/provider refresh behavior;
- present bounded loading, error, empty, and unavailable states;
- remain usable with long names, large paged directories, large text, touch, keyboard/pointer input, and system insets;
- restore focus to a sensible originating control or surviving item after transient surfaces close where practical.

### 3.5 Jobs, Settings, startup, and readiness

These existing surfaces receive targeted adaptive, accessibility, focus, text-scaling, overflow, and inset hardening. Activity recreation and presentation changes must not reset their existing authoritative controller state or create Android-specific controller variants.

### 3.6 Android Back and predictive Back

Back follows one ordered semantic pipeline:

1. an active modal/transient surface dismisses when it owns the topmost meaningful action;
2. a picker or Compact hierarchy retreats to its parent when applicable;
3. otherwise the existing router/navigator performs the routed pop;
4. only when no meaningful in-app pop/dismiss action exists may Android exit/background the Activity.

Predictive Back uses the supported Flutter/Android integration over this same navigation authority. P02-006 does not introduce an app-level Back coordinator or duplicate route state.

### 3.7 Edge-to-edge, system bars, cutouts, gestures, and IME

Android uses modern edge-to-edge presentation. Flutter presentation respects status/navigation bars, display cutouts, gesture navigation, safe regions, and IME through normal Flutter constraint/inset APIs at the local boundaries that need them.

The app must not solve this by globally wrapping every surface in `SafeArea`, by hard-coding device padding, or by introducing hardware-specific constants. Insets are presentation constraints, not route or domain state.

### 3.8 Accessibility

Accessibility is release-blocking correctness for Android-applicable P02-006 UI. Representative and deterministic coverage must establish:

- practical Material touch targets;
- semantic names, roles, selected/disabled/busy state where applicable;
- logical traversal and visible focus for keyboard/pointer use;
- usable 2x text scaling without loss of required functionality;
- non-color-only communication of important state;
- usable controls under system font scaling and narrow local constraints.

Accessibility fixes that are inherently shared remain shared rather than Android forks.

### 3.9 Lifecycle integration

P02-004 remains authoritative for foreground execution, host detach/reattach, process death, timeout, cancellation, and recovery semantics. P02-006 does not redesign those contracts.

P02-006 verifies and fixes presentation/platform integration when those established semantics are exercised through rotation, Activity recreation, resize, fold/unfold, temporary backgrounding, permission overlays, picker interaction, Back, and IME/system-UI transitions.

Activity recreation, rotation, resizing, split-screen, fold/unfold, and temporary backgrounding must not:

- create a second Flutter/Rust application composition;
- create a second SQLite authority;
- invoke general shutdown solely because the Activity changed;
- reset valid controller state;
- fabricate job/provider state from presentation lifecycle.

### 3.10 Process-lifetime state preservation

Valid feature-local transient state is preserved for the lifetime of the surviving application-scoped Flutter composition. This includes picker location and Sources hierarchy context where those existing controllers already own the state, plus scroll/focus/transient presentation state where practical and safe.

P02-006 does not add durable storage for transient presentation state. Actual process death follows existing cold-start and abandoned-work recovery semantics.

## 4. Environmental failure handling

Permission loss and removable-volume disappearance remain environmental availability changes, not destructive source reconciliation.

- Configured roots, indexed data, settings, and Jobs history remain durable.
- Existing P02-005 readiness/provider refresh and reconciliation paths remain authoritative for regrant/remount.
- Presentation pointing at an entity or location that is no longer valid retreats to the nearest valid context or shows authoritative unavailability rather than crashing or inventing state.
- Resize, rotation, inset, or input-mode changes never authorize backend mutation.

## 5. Testing strategy

### 5.1 Deterministic Flutter coverage

Tests cover at minimum:

- exact global width boundaries at 599/600, 839/840, and 1199/1200 logical pixels;
- live Compact -> Medium -> Expanded -> Large transitions and reverse transitions while preserving route identity and branch history;
- Sources root/detail and hierarchy context across layout transitions;
- picker current location, Back hierarchy, paging, long names, loading, empty, error, unavailable, and remount behavior;
- representative 1x and 2x text-scale behavior;
- semantics, focus order, visible focus, touch-target practicality, and keyboard/pointer activation;
- Jobs, Settings, startup/readiness, dialogs, and failure surfaces at narrow widths and large text;
- inset/IME-aware presentation without device-specific padding;
- feature-local state preservation across simulated process-lifetime Activity/presentation reconstruction seams where deterministic Flutter tests can exercise it.

### 5.2 Android native qualification

P02-006 owns a repository-run Android native qualification milestone. On the supported ARM64 API 36 emulator environment, it exercises representative:

- rotation and Activity recreation;
- background/foreground transitions;
- live window/size changes where emulator tooling permits;
- Android Back and predictive Back where supported by the platform/tooling;
- picker parent navigation and dismissal ordering;
- permission-overlay return;
- IME and system-bar/inset interaction;
- preservation of the single application runtime/composition through non-process-death lifecycle transitions.

A required native scenario that cannot be exercised is recorded as unverified rather than inferred from widget tests.

P02-007 remains responsible for ARM64-only CI wiring of Android native gates, removal of residual non-ARM64 build, packaging, harness, and CI paths, signed direct-distribution artifacts, desktop regression closure, future-phase applicability guards, and final physical ARM64 evidence.

## 6. Expected implementation boundaries

Likely implementation work is concentrated in:

- `flutter/lib/core/responsive/**` and shared design-system primitives only where existing primitives need hardening;
- `flutter/lib/app/shell/**` and `flutter/lib/app/routing/**` for adaptive shell and standard pop integration;
- `flutter/lib/app/platform/**` and Android host files for genuinely Android-specific system UI/lifecycle integration;
- `flutter/lib/features/sources/presentation/**` and existing Sources application state only where preservation behavior requires it;
- `flutter/lib/features/jobs/presentation/**`;
- `flutter/lib/features/settings/presentation/**`;
- `flutter/lib/features/startup/presentation/**` and readiness presentation where necessary;
- corresponding Flutter and Android native test/milestone files.

No new backend/domain contract is expected. If correctness requires changing Rust/application authority, provider identity contracts, persistence, foreground execution semantics, or job lifecycle semantics, implementation must stop and request a scope amendment rather than silently expanding P02-006.

## 7. Explicit exclusions

P02-006 does not include:

- a new Android-specific UI architecture or route graph;
- an app-level Back coordinator parallel to Flutter navigation;
- a redesign of the Argus folder picker provider/selection model;
- durable persistence of transient presentation state;
- redesign of P02-004 foreground execution/runtime lifecycle semantics;
- Android 10 / API 29 compatibility;
- Google Play policy/submission work;
- signed release artifact production;
- Android CI wiring;
- final physical ARM64 phase evidence;
- broad unrelated visual redesign.

## 7.1 Approved acceptance clarification (2026-08-20)

The following qualification applicability rules are part of the approved P02-006 contract:

- `flutter/integration_test/**` is an authorized canonical qualification location for P02-006 Android integration evidence. Tests there may coordinate production Flutter/runtime assertions with the real Android host, but must not introduce product authority, raw provider identity, or test-only product behavior.
- Predictive Back acceptance is limited to behavior that the repository's pinned Flutter/Android stack can expose through supported APIs without adding a second Back/navigation authority. Ordinary Back and semantic pop ordering remain required. If nested local predictive progress is not observable or implementable through supported Flutter APIs, the native evidence must record that precise framework/tooling limitation; that limitation does not block P02-006 completion when ordinary Back semantics and routed predictive integration are otherwise preserved.
- Native IME qualification is required only when a P02-006 product workflow exposes an applicable text-input surface. When no such product interaction exists, deterministic `MediaQuery`/`viewInsets` coverage plus native system-bar/inset qualification is sufficient; P02-006 must not add a fake or product-irrelevant text field solely to manufacture IME evidence.
- Tooling/framework-unexercisable scenarios must remain explicitly documented rather than being falsely marked as native passes. Completion is based on passing all exercisable required scenarios plus truthful applicability evidence for the exceptions above.

## 8. Completion criteria

P02-006 is complete when:

1. shared adaptive behavior is correct and usable across Compact, Medium, Expanded, and Large widths without device-category branching;
2. valid route, branch, controller, Sources hierarchy, and picker context survive process-lifetime adaptive/Activity transitions;
3. Android Back/predictive Back follows the existing semantic pop hierarchy without duplicate route authority;
4. Android edge-to-edge, system bars, cutouts, gestures, safe regions, and IME do not obscure or destabilize required UI;
5. Android-applicable UI meets the accessibility requirements defined above, including representative 2x text scaling;
6. picker hardening covers hierarchy navigation, environmental loss, paging, long names, failure/empty/loading states, input methods, and state preservation;
7. P02-004/P02-005 runtime, job, permission, removable-volume, and reconciliation semantics remain authoritative and unchanged except for concrete integration defect fixes within authorized scope;
8. deterministic Flutter coverage is green;
9. the repository-owned API 36 native qualification milestone records passing evidence for exercisable required scenarios and explicitly records any tooling-blocked scenario as unverified;
10. P02-007 remains the only remaining Phase 002 implementation slice.
