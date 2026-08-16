# Design-System Foundation and Accessibility Baseline

**Document ID:** SPEC-FE-007  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-002, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-FE-004, SPEC-FE-005, SPEC-FE-006, SPEC-X-001, SPEC-X-002, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Phase 000 Flutter design-system foundation and accessibility baseline for Argus ROM Toolkit.

It turns the visual, responsive, interaction, focus, semantics, scaling, motion, and visual-regression decisions deferred by earlier frontend specifications into one implementation-ready contract.

The Phase 000 design system is intentionally restrained. It exists to make the startup, recovery, application shell, Settings, appearance initialization, and future feature presentation consistent and accessible without creating a second UI framework on top of Flutter.

The central invariant is:

> **Argus has one restrained Material 3 presentation foundation rather than a parallel UI framework: shared components are promoted only when they encode genuine reusable semantics, application structure derives from one responsive system, feature presentation retains domain meaning, accessibility is preserved across every interaction mode, visual state remains measurable and testable, and the MVP architecture leaves room for a future official Material 3 Expressive evolution without making that future dependency part of today's implementation.**

## 2. Responsibilities

This specification owns frontend rules for:

- the official Material 3 MVP presentation baseline;
- future Material 3 Expressive compatibility boundaries;
- `core/design_system` ownership;
- `core/responsive` concrete width-class policy;
- root Light and Dark `ThemeData` construction;
- semantic color usage;
- typography ownership;
- spacing, radius, border, and motion token scope;
- global application width classes and exact thresholds;
- local-constraint adaptation rules;
- standard page/content composition;
- MVP visual density policy;
- shared-component promotion criteria;
- loading, error, empty-state, notice, dialog, icon, and overlay presentation conventions;
- keyboard accessibility;
- focus behavior;
- interactive target sizing;
- text and non-text contrast baselines;
- text-scaling behavior;
- screen-reader/semantics requirements;
- reduced-animation behavior;
- targeted golden/visual-regression policy as applied to the design system;
- design-system architecture enforcement;
- Phase 000 design/accessibility verification.

## 3. Non-Responsibilities

This specification does not own:

- feature state, controllers, or business behavior, owned by the applicable feature specification;
- application location, branch state, or shell routing semantics, owned by SPEC-FE-004;
- startup/recovery behavior or error authority, owned by SPEC-FE-005;
- persisted Theme Mode authority or appearance synchronization, owned by SPEC-FE-006;
- Flutter project/module boundaries, owned by SPEC-FE-001;
- Riverpod/controller state conventions, owned by SPEC-FE-002;
- client/bridge behavior, owned by SPEC-FE-003;
- final product branding or an approved marketing identity;
- a custom icon family;
- a custom bundled font family;
- a component-catalog application;
- advanced data-table/grid design for future Library work;
- game-detail visual design;
- native title-bar/window-chrome styling;
- persisted accessibility preferences;
- application-defined high-contrast mode;
- Material 3 Expressive adoption during MVP;
- third-party Material 3 Expressive compatibility packages.

## 4. Governing Principles

The following principles govern all Phase 000 frontend presentation work:

1. Official Flutter Material 3 is the MVP component foundation.
2. Argus customizes Material rather than replacing it.
3. Standard Material widgets are preferred whenever their semantics match the required interaction.
4. Cross-feature design abstractions exist only when they encode a real shared contract.
5. Feature-specific meaning remains feature-owned.
6. `ThemeData` and Material component themes are the normal styling mechanism.
7. Semantic visual roles are preferred over feature-local color/typography literals.
8. Application structure responds to available width rather than device category.
9. Nested components respond to their own constraints.
10. Accessibility is part of feature correctness, not a later polish pass.
11. Keyboard, pointer/touch, and assistive-technology use remain valid interaction paths.
12. State is never communicated by color or motion alone.
13. Text scaling may change layout but must not remove essential content or functionality.
14. Motion communicates state/hierarchy and honors platform accessibility requests.
15. Golden tests are selective visual-regression evidence, not a replacement for semantic tests.
16. The MVP remains structurally ready for later official Material 3 Expressive adoption without speculative adapters.

## 5. Architectural Position

The presentation architecture is:

```text
Flutter Material 3
        ↓
core/design_system
├── root theme construction
├── semantic presentation tokens
├── justified shared components
└── accessibility-supporting defaults
        ↓
feature/app presentation
        ↓
feature/controller state
```

Responsive structure is adjacent rather than nested into the visual design system:

```text
core/responsive
├── WindowSizeClass
├── canonical thresholds
└── narrow responsive helpers
        ↓
app shell / feature presentation
```

No design-system primitive owns business state, backend state, route state, or bridge access.

## 6. Material 3 Baseline

Phase 000 uses Flutter's official Material 3 implementation.

Application theme construction must opt into and remain compatible with the current supported Material 3 behavior for the pinned Flutter SDK.

Argus must not emulate legacy Material 2 visual behavior as a separate design target.

## 7. Material 3 Expressive Is Deferred

Material 3 Expressive is explicitly out of scope for MVP/Phase 000.

Argus must not add a third-party Expressive package or implement an unofficial parallel Expressive widget set merely to approximate a future Flutter API.

This deferral is a deliberate product/maintenance decision, not a rejection of Expressive as a future visual direction.

## 8. Expressive-Ready Boundary

The Phase 000 architecture must allow future official Material 3 Expressive adoption to change primarily:

- theme definitions;
- shape tokens;
- motion tokens;
- typography configuration;
- selected Material component themes;
- selected shared design-system components.

It should not require changes to:

- feature controllers;
- Riverpod authority;
- route contracts;
- `ArgusClient`/focused APIs;
- persistence semantics;
- feature ownership.

That separation is the meaning of Expressive-ready in this specification.

## 9. No Speculative Expressive Adapter

Phase 000 must not introduce abstractions such as:

```text
ExpressiveButtonAdapter
FutureMaterialFacade
ExpressiveMotionBridge
MaterialVersionCompatibilityLayer
```

before an official Flutter API and concrete Argus adoption decision exist.

The existing semantic theme/component boundaries are the compatibility seam.

## 10. Future Expressive Adoption Gate

A future adoption must be an explicit design-system revision or successor decision that evaluates at least:

- official Flutter API maturity;
- pinned Flutter SDK compatibility;
- desktop behavior;
- keyboard/focus behavior;
- screen-reader semantics;
- reduced-motion behavior;
- component coverage;
- performance;
- visual-regression impact;
- migration cost.

It must not arrive silently through an unrelated dependency update.

## 11. `core/design_system` Ownership

`core/design_system` owns reusable Argus presentation foundations that are genuinely cross-feature.

It may own:

- root theme factories;
- semantic design tokens;
- justified `ThemeExtension` values;
- reusable page/section composition;
- repeated status/error presentation primitives;
- focus treatment policy;
- reusable accessibility-supporting presentation helpers where Material does not already solve the need.

It must remain presentation-focused.

## 12. `core/design_system` Dependency Rule

Production `core/design_system` code must not depend on:

- `features/*`;
- `ArgusClient`;
- `RuntimeApi`;
- `SettingsApi`;
- `DiagnosticsApi`;
- FRB/generated bridge types;
- backend DTOs;
- feature controllers;
- repositories or persistence.

A feature may consume a design-system primitive. The primitive never reaches upward into the feature to obtain its own data.

## 13. `core/responsive` Ownership

`core/responsive` owns application-wide responsive primitives shared across app and feature presentation.

At Phase 000 this includes:

- `WindowSizeClass` or the equivalent typed concept;
- one canonical width-classification function;
- one canonical set of global width thresholds;
- narrowly shared helpers that expose those semantics without duplicating constants.

It does not own feature-specific layout state.

## 14. Responsive and Design-System Separation

Responsive width classification and visual tokens remain separate ownership concerns even though both are defined by this specification.

`core/responsive` answers:

> What structural width class is currently available to the application?

`core/design_system` answers:

> What shared visual and interaction rules apply to presentation?

Do not move all responsive behavior into `core/design_system` merely because breakpoints affect layout.

## 15. Shared-Component Promotion Rule

A widget belongs in `core/design_system` only when at least one of these is true:

1. it implements recurring cross-feature semantic presentation;
2. it enforces a design/accessibility invariant that should not be reimplemented;
3. it composes multiple Material primitives into one stable Argus presentation concept;
4. two or more real consumers require substantially the same behavior and semantics.

Visual similarity alone is not sufficient.

## 16. No Speculative Component Families

Phase 000 must not prebuild a broad wrapper library such as:

```text
ArgusButton
ArgusIconButton
ArgusCheckbox
ArgusRadio
ArgusSwitch
ArgusTextField
ArgusDialog
ArgusCard
ArgusListTile
```

when the wrapper contributes no semantic behavior beyond changing ordinary Material styling.

## 17. Standard Material Controls First

Use standard Flutter/Material controls when they match the interaction requirement, including:

- buttons;
- icon buttons;
- navigation bar;
- navigation rail;
- menus;
- dialogs;
- progress indicators;
- text fields;
- radio/single-selection controls;
- switches/checkboxes where later required;
- tooltips.

Custom interactive widgets require a concrete product need and a complete keyboard/focus/semantics story.

## 18. Component Theme Before Wrapper

When an Argus-wide requirement is primarily visual, prefer:

```text
ThemeData
    ↓
Material component theme
```

over a wrapper that adds no meaningful semantics.

Examples include button styling, dialog styling, navigation styling, input decoration, progress appearance, or tooltip treatment.

## 19. Feature-Specific Widgets Remain Feature-Owned

Feature concepts remain with their owning feature even when they use shared visual primitives.

Examples:

```text
ThemeModeSelector
→ features/settings/presentation

StartupRecoveryView
TechnicalDetailsPanel
→ features/startup/presentation
```

They do not move into `core/design_system` solely because another screen contains visually similar controls.

## 20. Shared Components Do Not Interpret Domain Failures

A shared status/error primitive may accept already-presentable semantic content such as:

- heading;
- message;
- severity/presentation role;
- optional action content.

It must not accept `ApplicationFailure`, `TransportFailure`, or `StartupFailure` and decide domain meaning or user recovery behavior itself.

Failure interpretation stays with the owning feature/application layer.

## 21. One Production Root Theme Owner

Production Light and Dark `ThemeData` construction has exactly one design-system owner.

Feature code must not construct independent application themes.

Tests may construct intentionally scoped test themes, but production root themes remain centralized.

## 22. Root Theme Factory

Conceptually the design system exposes:

```text
ArgusTheme.light
ArgusTheme.dark
```

or an equivalent pure API.

Theme construction must be deterministic for the same build configuration.

## 23. Relationship to SPEC-FE-006

SPEC-FE-006 remains the authority for persisted user choice:

```text
System
Light
Dark
```

SPEC-FE-007 owns the actual Light and Dark theme definitions.

Conceptually:

```text
SPEC-FE-006 ThemeMode
        +
SPEC-FE-007 ThemeData
        ↓
MaterialApp
```

No design-system code persists Theme Mode.

## 24. System Is Not a Third Theme

When authoritative Theme Mode is `System`, Flutter/platform brightness selects between the same approved Light and Dark theme definitions.

Argus does not build a separate `SystemThemeData`.

## 25. `ColorScheme` Is the Primary Color Contract

Feature presentation uses semantic Material roles such as:

- `primary` / `onPrimary`;
- `surface` / `onSurface`;
- surface-container roles;
- `outline`;
- `error` / `onError`;
- other justified semantic scheme roles.

Feature-local constants such as `settingsRed`, `darkGray3`, or `panelBlue` are prohibited for ordinary UI state.

## 26. Brand Palette Is Replaceable

Phase 000 does not have an approved permanent brand palette.

Any initial seed or explicit Light/Dark palette must therefore be:

- centrally owned;
- deterministic;
- contrast-verified;
- used through semantic roles;
- replaceable without changing feature contracts.

Exact palette values are implementation/design assets rather than cross-feature business semantics.

## 27. No OS Dynamic Accent Palette in Phase 000

Phase 000 must not make core application colors depend on arbitrary operating-system accent/dynamic-color values.

FE-006 `System` means follow system Light/Dark brightness. It does not mean adopt an OS-provided application color palette.

Dynamic color may be evaluated later as a distinct appearance capability.

## 28. Typography Baseline

Phase 000 uses the maintained Flutter/Material typography baseline and platform-resolved font behavior.

Feature presentation consumes semantic `TextTheme` roles rather than scattering custom font size/weight combinations.

## 29. No Custom Bundled Font for MVP

A custom bundled font is not required by Phase 000.

This avoids adding font assets, licensing obligations, platform rendering variance, and brand coupling without an approved typography requirement.

A future branded typography decision can replace centralized theme typography without changing feature ownership.

## 30. Semantic Text Roles

Feature widgets should use semantic theme roles such as headings, titles, body text, and labels through the root text theme.

Repeated Argus-specific typography semantics may be introduced only when the Material type roles demonstrably do not express the repeated need.

## 31. Token Surface Is Deliberately Small

Phase 000 authors only the design tokens needed to keep real UI consistent.

Expected token categories are:

```text
Spacing
Radius
Border
Motion
```

Responsive thresholds live under `core/responsive` rather than the visual token namespace.

Material semantic color and typography roles are not duplicated into Argus constants without need.

## 32. Spacing Scale

The standard Phase 000 spacing scale is:

```text
4
8
12
16
24
32
48
```

logical pixels.

This scale covers normal gaps, padding, section separation, page gutters, and major composition spacing.

## 33. Spacing Is a Convention, Not Geometry Prohibition

Standard composition should use the shared spacing scale.

Component-specific geometry may use another value where the visual/interaction requirement genuinely requires it.

The architecture must not ban every non-token number from presentation code.

## 34. Semantic Spacing Aliases Stay Generic

If named spacing aliases are used, keep the shared vocabulary generic and small, for example:

```text
xs
sm
md
lg
xl
```

Do not create global tokens named after individual feature screens or controls.

## 35. Radius Tokens

Phase 000 should expose only a small radius vocabulary, conceptually:

```text
small
medium
large
```

Material component defaults remain preferred where no Argus-specific radius is required.

## 36. Border and Surface Hierarchy

Surface hierarchy should normally use Material surface roles, grouping, spacing, and restrained borders before arbitrary drop shadows.

Ordinary Settings sections or shell regions do not need decorative elevation solely to look like separate cards.

## 37. Elevation Use

Elevation is reserved for genuine layered presentation such as:

- dialogs;
- menus;
- overlays;
- exceptional floating surfaces.

Do not build card-on-card-on-card hierarchy as the default desktop composition.

## 38. Motion Token Surface

Phase 000 may expose a small semantic motion vocabulary such as:

```text
instant/reduced
fast
standard
emphasized
```

Exact naming is implementation-derived.

Feature widgets should not scatter arbitrary durations/curves when an application-wide semantic transition exists.

## 39. Expressive-Ready Motion

The semantic motion layer must be replaceable beneath feature semantics.

MVP does not prescribe Expressive spring physics or shape morphing.

A future official Expressive adoption may revise the underlying motion definitions without changing feature/controller contracts.

# Responsive Foundation

## 40. Global Window Size Classes

Argus uses exactly four global application width classes:

```text
Compact
Medium
Expanded
Large
```

These classes determine application-shell structure, not hardware identity.

## 41. Canonical Breakpoints

The global width thresholds are:

```text
Compact   width < 600
Medium    600 <= width < 840
Expanded  840 <= width < 1200
Large     width >= 1200
```

All values are Flutter logical pixels.

## 42. Boundary Semantics

The exact boundary classification is:

```text
599  → Compact
600  → Medium
839  → Medium
840  → Expanded
1199 → Expanded
1200 → Large
```

The half-open ranges are normative.

## 43. One Breakpoint Source

The numbers `600`, `840`, and `1200` have one production source under the responsive owner.

Shell and feature code consume `WindowSizeClass` or approved helpers rather than repeating breakpoint numbers.

## 44. Width Means Available Application Width

Classification uses the width currently available to the application root.

It does not use:

- OS name;
- hardware category;
- phone/tablet/desktop labels;
- screen diagonal;
- pointer availability.

## 45. No `isDesktop` Layout Authority

Presentation must not propagate or derive structural layout from booleans such as:

```text
isDesktop
isTablet
isPhone
```

when available width is the actual requirement.

## 46. Global Class Controls Application Structure

SPEC-FE-004 shell behavior maps the global class to the approved navigation presentation:

```text
Compact
→ bottom navigation + More

Medium
→ navigation rail

Expanded / Large
→ full sidebar presentation
```

FE-007 supplies the concrete width classification; FE-004 retains route/destination semantics.

## 47. Local Components Use Local Constraints

A child component or pane may adapt to the width available to itself using normal Flutter layout mechanisms such as local constraints.

A Large application window may contain a narrow child pane that uses compact local arrangement.

## 48. No Shared Local Taxonomy Without Evidence

Phase 000 does not introduce a second global vocabulary such as:

```text
PaneCompact
FormMedium
ComponentWide
```

Individual components may branch on local constraints. Shared local size classes require repeated demonstrated semantics across real components.

## 49. Resize Preserves Semantic State

A width-class transition changes presentation only.

It does not change:

- route identity;
- active semantic destination;
- FE-004 branch history;
- feature controller authority;
- persisted state.

## 50. Responsive Classification Is Pure

The width-classification function is deterministic and side-effect free.

It performs no platform calls, routing, persistence, or controller mutation.

# Page and Layout Foundation

## 51. Standard Constrained Page Composition

A shared page/content composition should support common configuration/readable screens across large application widths.

It may provide:

- standard page gutters;
- vertical composition spacing;
- alignment;
- optional readable maximum content width.

It must not impose one width policy on all future features.

## 52. Canonical Page Gutters

The Phase 000 starting page-gutter policy is:

```text
Compact   16
Medium    24
Expanded  32
Large     32
```

logical pixels, unless the owning composition has a justified local requirement.

These values are page/content gutters, not universal padding for every widget.

## 53. Readable Content Does Not Stretch Indefinitely

Configuration and message-heavy content such as Settings and recovery should use an appropriate readable maximum width on large windows.

Full-width application chrome may still span the window.

The design system must not force inherently wide future content such as library grids/tables into the same constrained width.

## 54. Large Does Not Scale Basic Controls Up

The Large width class provides more layout opportunity. It does not automatically enlarge text, icons, button heights, or control geometry.

Large-space composition should use the additional room intentionally rather than scaling the entire UI.

# Density

## 55. MVP Uses Standard/Comfortable Material Density

Phase 000 uses standard/comfortable Material 3 density as the global baseline.

Do not globally force compact/shrink-wrapped density merely because desktop is a primary platform.

## 56. Density and Hit Area Are Separate

Future data-dense presentation may reduce visual row density without reducing required effective interactive target size or keyboard focus clarity.

This distinction must remain possible in the architecture.

## 57. Phase 000 Forms Are Comfortable

Settings, startup, and recovery prioritize readability, grouping, focus traversal, and accessible actions over maximum information density.

They are not treated like future data tables.

# State Presentation

## 58. No Universal `AsyncView`

Do not create one generic component that receives arbitrary `AsyncValue<T>` and decides loading/error/empty/content semantics for every feature.

State interpretation remains owned by the controller/feature contract under SPEC-FE-002.

## 59. Blocking Initialization Presentation

Blocking initialization is appropriate when no usable application presentation exists, for example:

- backend startup;
- first authoritative appearance initialization before normal-shell admission.

It may occupy the root application presentation.

## 60. Local Initial Loading

When a routed feature exists but its required initial data is unavailable, initial loading belongs inside the feature's presentation region rather than replacing the whole application.

The applicable future feature contract owns the exact behavior.

## 61. Background/Refresh Operation Presentation

Once usable state exists, refresh/save/synchronization work retains that usable state and presents operation status explicitly.

It must not replace the whole feature with a generic spinner solely because background work is active.

This preserves SPEC-FE-002, FE-005, and FE-006 behavior.

## 62. Progress Must Be Truthful

Determinate progress is displayed only when the owning operation exposes meaningful quantitative progress.

Otherwise use indeterminate progress.

The design system owns consistent visual treatment, not progress authority.

## 63. Error Scope

Error visuals must match semantic scope:

```text
field/control error
section error
feature/page error
root blocking failure
transient non-authoritative notice
```

Not every error becomes a global banner or toast.

## 64. Inline Error Placement

An error caused by a specific interaction remains associated with that interaction where practical.

Examples include:

- FE-006 Theme Mode save failure;
- startup recovery-operation failure.

The design system supplies consistent presentation primitives while the feature owns the error semantics.

## 65. Empty State Is Not Error State

A valid zero-content/result condition is not visually or semantically an error solely because no items exist.

Future feature contracts own the meaning, copy, and actions for their empty states.

## 66. No Generic Empty Business Model

FE-007 may later supply reusable empty-state visual composition, but it does not define one generic domain state for concepts such as:

- no games indexed;
- no search results;
- no active jobs.

Those remain feature semantics.

## 67. Transient Notices Are Subordinate

FE-004 `AppNotice` presentation may use shared visual tokens/components, but transient notices never replace durable state requiring user attention.

A disappearing notice cannot be the only representation of:

- a failed save;
- startup failure;
- synchronization uncertainty;
- durable recovery-operation error.

# Dialogs, Menus, and Overlays

## 68. Standard Material Modal Behavior

Phase 000 uses standard Material dialog/menu/overlay interaction where it satisfies the requirement.

This preserves normal focus, dismissal, keyboard, and semantics behavior rather than rebuilding it.

## 69. Dialog Content Remains Feature-Owned

For example, Reset Appearance Settings supplies feature-owned:

- title;
- explanation;
- confirm action;
- cancel action.

The design system/Material supplies modal presentation and shared visual behavior.

## 70. Consequence-Appropriate Emphasis

Visual danger/destructive emphasis must match real consequence.

Reset Appearance Settings must not look like database deletion because the operation resets one preference aggregate and retries startup.

Future genuinely destructive operations require deliberate destructive semantics.

# Icons and Imagery

## 71. Material Icons Are the Default MVP Vocabulary

Phase 000 does not require a separate icon dependency or custom icon pack.

Use icons by semantic meaning rather than decoration.

## 72. Icons Do Not Replace Critical Labels

Critical recovery and settings actions should not become unexplained icon-only controls merely to save space.

Where icon-only controls are appropriate, accessible names/tooltips must communicate the operation.

## 73. Decorative Illustration Is Deferred

Phase 000 does not require bespoke startup artwork, mascots, empty-state illustration, or decorative backgrounds.

Such assets may be introduced later without changing the design-system ownership model.

# Theme Implementation

## 74. `ThemeData` Is the Primary Implementation Surface

The root design-system owner configures shared presentation through `ThemeData` and Material component themes where those components are actually used.

Likely Phase 000 theme surfaces include:

- `ColorScheme`;
- `TextTheme`;
- navigation bar/rail themes;
- button themes;
- dialog theme;
- input decoration theme where required;
- progress indicator theme;
- tooltip theme;
- other justified Material component themes.

Do not configure every possible Material component speculatively.

## 75. `ThemeExtension` Requires Semantic Need

A typed `ThemeExtension` is appropriate only for repeated Argus semantic values not adequately represented by Material theme roles.

Potential examples include:

- application-specific status roles;
- specialized surface roles;
- explicit shared focus tokens.

Do not mirror the complete Material `ColorScheme` into an Argus extension.

## 76. Theme Extensions Are Complete

Every production extension must be:

- immutable/typed;
- deliberately defined for Light and Dark;
- usable through normal Flutter copy/interpolation behavior where relevant;
- independent from feature-specific state.

No feature may assume a shared extension exists only in one brightness mode.

## 77. Shared Interaction States

Interactive presentation should use Material/Flutter state machinery for states such as:

- enabled;
- hovered;
- focused;
- pressed;
- selected;
- disabled;
- error where applicable.

Feature widgets should not independently calculate their own generic interaction-state colors.

# Accessibility Ownership

## 78. Accessibility Is Distributed Responsibility

The design system provides accessible defaults and shared primitives.

Each presentation owner remains responsible for the semantics and interaction meaning of its own feature.

Accessibility must not be isolated into one helper module and assumed solved globally.

## 79. Native Semantics First

Prefer standard Material controls and their built-in semantics/focus behavior.

Add explicit `Semantics`, focus nodes, shortcuts/actions, or custom accessibility handling only when standard behavior does not express the actual requirement.

## 80. Custom Interactive Component Contract

Any custom interactive component must define and test, as applicable:

- accessible name;
- role/semantic action;
- current state/value;
- keyboard activation;
- focusability and traversal;
- pointer/touch activation;
- disabled semantics;
- error semantics;
- target sizing.

A gesture-only custom hit region is not acceptable as an implementation shortcut.

# Keyboard and Focus

## 81. Keyboard Operability

Every Phase 000 user operation available by pointer must also be operable by ordinary keyboard interaction unless the operation inherently depends on spatial pointer input.

This includes:

- shell navigation;
- Compact More;
- Settings navigation;
- Theme Mode selection;
- retry/reconciliation actions;
- Reset Appearance Settings confirmation;
- diagnostics actions;
- technical-details disclosure;
- Exit.

## 82. Standard Keyboard Semantics

Follow Flutter/platform conventions for ordinary control behavior.

Conceptually:

```text
Tab / Shift+Tab
→ focus traversal

Enter / Space
→ activate appropriate focused control

Arrow keys
→ navigate controls whose Material semantics define arrow navigation

Escape
→ dismiss appropriate transient/modal surfaces
```

Do not invent custom shortcuts for basic control operation.

## 83. No Keyboard Traps

A focusable component must provide normal focus exit/dismissal behavior.

Dialogs, menus, disclosures, and future complex widgets must not require undocumented special keystrokes to escape.

## 84. Logical Focus Order

Focus traversal follows visual/task order rather than incidental private widget-tree order.

A recovery surface conceptually traverses from primary recovery behavior through secondary actions and technical/exit actions in a predictable order.

## 85. Responsive Focus Semantics

Switching between Compact, Medium, Expanded, and Large shell presentations preserves the semantic destination model and logical navigation order.

Responsive rendering must not create a different conceptual application for keyboard users.

## 86. Visible Keyboard Focus

Keyboard focus must be visibly distinguishable on interactive controls.

Where Argus supplies an explicit custom focus indicator, the target baseline is approximately:

- at least a 2 logical-pixel perimeter-equivalent indicator;
- at least 3:1 contrast between the focused and unfocused visual treatment.

Material defaults may satisfy this requirement without custom drawing.

## 87. Focus Must Not Be Obscured

Argus-owned overlays, banners, notices, or persistent chrome must not make the currently focused control effectively invisible.

When focus is moved programmatically, the user must be able to perceive the focused target.

## 88. Input-Modality-Appropriate Focus Styling

Pointer interaction does not require the same heavy focus treatment as keyboard traversal if Material/Flutter appropriately differentiates modalities.

Visible keyboard focus remains mandatory.

# Interactive Target Size

## 89. Default Target Baseline

The normal Phase 000 minimum interactive hit target is:

```text
48 × 48 logical pixels
```

An icon or visual glyph may be smaller inside that target.

## 90. Do Not Globally Shrink Tap Targets

The application must not globally opt into compact/shrink-wrapped tap-target behavior solely to increase desktop density.

Density should be solved through layout rather than by making common actions unnecessarily difficult to target.

## 91. Target Exceptions

Specialized controls such as inline links may legitimately have smaller geometry where a 48×48 box would damage the interaction.

Such exceptions must still provide adequate separation and equivalent keyboard/assistive access.

They require deliberate component-level justification rather than becoming the default.

# Color and Contrast

## 92. Text Contrast Baseline

Approved Light and Dark themes must meet at least:

```text
normal text ≥ 4.5:1
large text  ≥ 3.0:1
```

against the relevant background for governed text combinations.

## 93. Meaningful Non-Text Contrast

Meaningful control boundaries, icons, focus indicators, or graphical status elements that users must perceive should provide approximately 3:1 contrast against adjacent colors where the distinction carries meaning.

Decorative graphics are not treated as information solely because they contain color.

## 94. State Is Never Color-Only

States such as:

- error;
- selected;
- pending;
- warning;
- success;
- synchronization uncertainty;
- disabled/unavailable;

must have a non-color signal appropriate to the interaction, such as text, shape, selection state, iconography with semantics, or control state.

## 95. Light and Dark Are Verified Independently

Passing contrast in one theme does not imply the other theme passes.

Governed semantic combinations must be evaluated independently for Light and Dark.

# Text and Display Scaling

## 96. Respect Platform Text Scaling

Argus must not globally disable or arbitrarily clamp user-requested text scaling to protect fixed layouts.

Essential presentation must adapt.

## 97. Deterministic 200 Percent Baseline

Phase 000 widget/presentation tests must exercise essential real surfaces at both:

```text
1.0× text scale
2.0× text scale
```

where the test environment supports deterministic text scaling.

## 98. Scaling May Change Layout

Accessibility requires preserved information/functionality, not identical pixel geometry.

At larger text scale, presentation may:

- wrap;
- stack horizontally arranged controls vertically;
- increase height;
- introduce scrolling where appropriate.

## 99. Critical Text Must Not Be Silently Clipped

Error messages, recovery guidance, setting labels, navigation labels, and action labels must not disappear behind fixed-height clipping at approved scaling baselines.

Ellipsis is allowed only when omitted content is non-critical or the complete accessible value remains available through an approved interaction.

# Semantics and Assistive Technology

## 100. Control Semantics

For meaningful interactive controls, assistive technology must be able to determine the equivalent of:

- accessible name;
- role/action;
- current selected/checked/expanded state where relevant;
- current value where relevant;
- enabled/disabled state.

## 101. Semantic Structure

Visual grouping should have corresponding meaningful semantic structure where practical.

Settings and recovery surfaces require comprehensible headings, groups, labels, and related error/state information rather than one flat sequence of unrelated semantics nodes.

## 102. Heading Semantics

Where Flutter/platform support allows, major page/section headings should expose appropriate heading semantics rather than relying only on large/bold text styling.

Do not fabricate excessively deep heading levels merely to mirror widget nesting.

## 103. Icon-Only Control Labels

Icon-only controls must expose a meaningful accessible name such as:

- Copy;
- Close;
- More;
- Refresh;
- Open folder.

The icon glyph itself is not an accessible label.

## 104. Decorative Content Is Excluded

Decorative gradients, dividers, ornamental logos, or non-informational visual embellishment should not create noisy assistive-technology announcements.

Semantics should describe application information and controls rather than paint operations.

# Status and Announcements

## 105. Announce Meaningful State Changes

Accessibility announcements/status semantics are appropriate for meaningful transitions such as:

- saving begins where the change is otherwise not apparent;
- save failure;
- diagnostics export completion;
- synchronization failure;
- other user-relevant asynchronous outcome.

They must not announce every animation frame or rebuild.

## 106. Focus Movement and Announcement Are Different Tools

Programmatic focus movement is reserved for genuine context changes, such as transition from blocking startup to an actionable failure surface.

Operation/status changes that should not steal the user's working position use status/announcement semantics instead.

# Motion and Accessibility Preferences

## 107. Motion Has Semantic Purpose

MVP motion is allowed to communicate:

- navigation continuity;
- state transition;
- hierarchy;
- opening/closing;
- progress;
- interaction feedback.

Continuous decorative motion without comprehension value is avoided.

## 108. Reduced/Disabled Animation

Argus-authored animation must honor the platform/Flutter accessibility request to disable or reduce animations where available.

When reduced:

- meaningful state change remains clear;
- decorative/intermediate motion is removed or substantially simplified;
- feature correctness is unchanged.

## 109. Animation Is Never Required for Understanding

Selection, expansion, completion, failure, and other meaningful states must remain understandable if the transition animation is not seen.

## 110. Do Not Defeat Platform Accessibility Features

Standard Material controls and custom Argus presentation must not deliberately override platform accessibility behavior in a way that reduces usability.

This includes applicable platform signals for animation, text styling, high contrast, and accessibility navigation.

Phase 000 does not introduce persisted Argus accessibility settings merely to mirror those platform signals.

# Feature-Specific Accessibility Baseline

## 111. Application Shell Accessibility

The adaptive shell must provide:

- semantic navigation destinations;
- selected destination state;
- keyboard-operable destination switching;
- Compact More with accessible name/role and keyboard operation;
- equivalent destination meaning across size classes;
- visible focus.

## 112. Startup and Recovery Accessibility

FE-005 remains authoritative for startup/recovery semantics.

FE-007 requires the shared visual implementation to preserve:

- meaningful failure heading;
- deliberate one-time focus entry for actionable failure context;
- keyboard-operable recovery actions;
- accessible indeterminate progress semantics;
- non-color-only failure/running state;
- accessible technical-details disclosure;
- readable/selectable technical content.

## 113. Settings and Appearance Accessibility

FE-006 remains authoritative for appearance behavior.

FE-007 requires the shared visual implementation to preserve:

- one semantically related Theme Mode single-selection group;
- System/Light/Dark selected state;
- keyboard operation;
- pending state semantics;
- inline error association;
- synchronization-uncertain presentation;
- usable Retry/Refresh action;
- large-text operation.

## 114. Dialog Accessibility

Phase 000 modal confirmation must:

- receive modal focus appropriately;
- expose meaningful title/content/actions;
- permit keyboard confirmation/cancellation;
- restore or deliberately transfer focus on close;
- avoid focus escape behind the modal while active.

Exact Flutter primitives remain implementation details.

# Testing Strategy

## 115. Semantic Tests Are Primary

Behavioral widget/integration tests remain primary for:

- keyboard interaction;
- semantics;
- focus order;
- state changes;
- routing;
- controller behavior;
- responsive identity preservation.

A screenshot/golden cannot substitute for these assertions.

## 116. Design-System Unit Tests

Deterministic design-system/responsive tests must cover at least:

- width classification;
- theme construction;
- shared token invariants where valuable;
- pure shared-component behavior;
- reduced-animation policy where authored behavior exists.

## 117. Breakpoint Tests

Exact boundary tests must include:

```text
599
600
839
840
1199
1200
```

and assert the canonical `WindowSizeClass` result.

## 118. Theme Construction Tests

Tests verify both production themes construct through the central owner and provide required shared extensions/component configuration used by Phase 000.

Feature tests should consume the real production theme where the visual/accessibility contract matters.

## 119. Contrast Verification

Where Flutter accessibility-guideline tooling or deterministic project checks can validate relevant contrast requirements, Phase 000 should use that automation.

Automated checks do not remove manual review responsibility for semantic color use.

## 120. Interactive Target Verification

Representative custom/shared controls must be tested against the approved minimum target behavior where Flutter's accessibility-guideline tooling supports it.

Standard Material controls need not be redundantly re-proven in every feature test.

## 121. Keyboard Tests

At minimum deterministic tests exercise:

- primary navigation traversal/activation;
- Compact More;
- Settings traversal;
- Theme Mode selection;
- recovery actions;
- Reset Appearance Settings confirmation/cancellation;
- technical-details expansion/collapse;
- absence of keyboard traps in the tested flows.

## 122. Text-Scaling Tests

Representative Compact and wide Phase 000 surfaces are tested at 1.0× and 2.0× text scale.

Assertions focus on preserved accessibility/functionality rather than exact pixel identity.

## 123. Semantics Tests

Representative semantics tests cover:

- navigation destination labels and selected state;
- Theme Mode group/value;
- loading/progress state;
- failure heading/context;
- recovery actions;
- Settings inline error;
- synchronization state;
- technical-details disclosure.

## 124. Responsive Shell Tests

The same semantic destination is exercised under Compact, Medium, Expanded, and Large classifications.

Tests verify that changing width presentation does not alter URI, destination identity, or branch history as governed by SPEC-FE-004.

# Golden and Visual Regression Testing

## 125. Golden Tests Are Selective

Golden tests are used only where visual stability has substantial regression value.

Do not golden-test every widget.

This preserves CONV-TEST-001.

## 126. Phase 000 Golden Baseline

The initial reviewed golden set should cover a small set of stable high-value surfaces, such as:

- custom/shared design-system primitives with meaningful Argus styling;
- representative adaptive shell state(s);
- representative startup/recovery state;
- representative Settings/Theme Mode state.

The exact count is implementation-derived from real custom presentation, not a quota.

## 127. Light and Dark Golden Coverage

Where color/surface/focus/error/selection presentation differs materially, representative visual coverage should exist under both Light and Dark.

Do not blindly duplicate every golden solely because two root themes exist.

## 128. Canonical Golden Widths

Visual golden tests use stable widths safely inside each global class, conceptually:

```text
Compact   480
Medium    720
Expanded  1024
Large     1440
```

These widths are recommended deterministic fixtures for visual regression, not new responsive breakpoints.

Breakpoint correctness is tested separately at the exact class boundaries.

## 129. Deterministic Golden Environment

Golden tests control relevant environment inputs, including as applicable:

- logical surface size;
- brightness/theme;
- text scale;
- locale;
- animation state;
- deterministic fake data/state.

They must not depend on live backend state, network resources, system time, uncontrolled animation, or OS dynamic color.

## 130. Golden Changes Require Visual Review

A changed golden baseline is a visual-contract change requiring deliberate review.

CI/test tooling must not auto-accept new baselines merely to make a failing run pass.

# Manual Accessibility Verification

## 131. Automated Tests Are Insufficient Alone

Phase 000 manual verification includes at least:

- keyboard-only traversal;
- screen-reader smoke test on the primary development platform;
- Light and Dark themes;
- large text/display scaling;
- reduced/disabled animation where the platform supports it;
- pointer interaction.

## 132. Manual Verification Is Bounded

Manual checks focus on the canonical Phase 000 demonstration surfaces rather than becoming an unbounded visual QA process.

Any discovered accessibility defect should receive deterministic automated regression coverage where practical.

# Architecture Enforcement

## 133. Enforce High-Value Boundaries

Architecture/static checks should enforce where practical:

- feature → `core/design_system` dependency is allowed;
- `core/design_system` → business feature dependency is forbidden;
- one production root theme owner;
- one global responsive breakpoint owner;
- feature presentation does not call FRB/client merely for design-system behavior;
- no device-category boolean becomes the global responsive authority.

## 134. Breakpoint Duplication Is Detectable

Architecture review/static checks should make obvious copies of the canonical global breakpoint numbers in shell/feature code detectable where practical.

Tests remain the final authority for classification behavior.

## 135. Hard-Coded Ordinary UI Colors Are Restricted

Feature presentation should use `ColorScheme`, Material component themes, or approved semantic theme extensions for ordinary UI colors.

Literal color values are allowed only where the value is genuinely domain/content-specific rather than an application-theme role.

## 136. Do Not Over-Lint Spacing Geometry

The project must not introduce a brittle rule that rejects every numeric spacing/size literal in Flutter code.

Review/static analysis should target repeated/scattered design decisions, not prohibit legitimate component-specific geometry.

## 137. Root Theme Construction Check

Production feature/app code must not create independent Light/Dark application themes outside the approved design-system owner.

Test-scoped theme construction remains permitted where explicit and isolated.

# Phase 000 Scope

## 138. Minimum Responsive Foundation

Phase 000 implements at least:

```text
core/responsive
├── WindowSizeClass
├── canonical 600 / 840 / 1200 thresholds
└── pure width classifier
```

with exact boundary tests.

## 139. Minimum Theme Foundation

Phase 000 implements one production theme owner providing:

```text
Light ThemeData
Dark ThemeData
```

with:

- Material 3;
- centralized semantic `ColorScheme`;
- typography through `TextTheme`;
- component themes actually used by Phase 000;
- small shared spacing/radius/border/motion policy as needed;
- any justified semantic theme extensions.

## 140. Minimum Shared Presentation Surface

Phase 000 introduces only shared presentation primitives demanded by real screens.

Expected candidates include:

- constrained page/content composition;
- shared section composition where repeated semantics justify it;
- shared status/error presentation where multiple real consumers justify it.

No arbitrary minimum number of custom components is required.

## 141. Real Surfaces Prove the Design System

The foundation is exercised by genuine Phase 000 surfaces:

```text
startup/loading
startup failure/recovery
application shell
Compact More
Settings
Theme Mode
authoritative appearance-load failure
Reset Appearance Settings confirmation
diagnostic actions
```

No fake product feature is required to demonstrate the design system.

## 142. No Component Showcase in Phase 000

Do not build Storybook/Widgetbook/design-system-explorer tooling merely because a design system exists.

Focused widget/golden tests are sufficient for Phase 000.

A future showcase may be justified once component volume makes isolated catalog development materially useful.

# Derived Decisions

## 143. Derived Phase 000 Choices

The following are derived from the approved architecture rather than open implementation forks:

- official Material 3 rather than a custom widget framework;
- Material 3 Expressive deferred from MVP;
- no unofficial/third-party Expressive dependency;
- future Expressive compatibility through semantic theme/component boundaries;
- `core/design_system` as the shared presentation owner;
- `core/responsive` as the responsive primitive owner;
- four exact global width classes;
- one root Light/Dark theme owner;
- no custom font requirement;
- no OS dynamic accent palette requirement;
- standard/comfortable global Material density;
- 48×48 normal interactive-target baseline;
- 200% deterministic text-scale verification baseline;
- selective rather than blanket golden coverage;
- no component showcase for Phase 000.

# Future Decisions

## 144. Decisions Requiring Later Product/Feature Design

This specification intentionally leaves later decisions for:

- permanent brand palette;
- branded typography/custom font;
- official Material 3 Expressive adoption;
- dynamic OS accent color support;
- user-selectable palettes/themes beyond Light/Dark/System;
- persisted high-contrast/accessibility appearance preferences;
- dense Library list/table presentation;
- advanced game-detail layout components;
- feature-specific empty-state illustrations;
- component showcase tooling;
- custom native window/title-bar styling.

Those decisions must preserve the architectural and accessibility boundaries here unless explicitly superseded.

# Acceptance Criteria

## 145. Acceptance Properties

SPEC-FE-007 is satisfied when:

1. Official Material 3 is the Phase 000/MVP component foundation.
2. Material 3 Expressive is explicitly deferred from MVP.
3. No third-party/unofficial Expressive dependency is required.
4. Theme, motion, shape, typography, and component boundaries remain suitable for later official Expressive adoption.
5. `core/design_system` owns genuine cross-feature presentation foundations only.
6. `core/design_system` does not depend on business features or backend/client APIs.
7. `core/responsive` separately owns application-wide responsive primitives.
8. Global width classes are exactly Compact `<600`, Medium `600–839`, Expanded `840–1199`, and Large `>=1200` logical pixels.
9. Breakpoints have one canonical production source.
10. Application structure uses available width rather than hardware/device category.
11. Nested components may adapt to their own local constraints.
12. Width-class changes do not change route identity or feature authority.
13. One production design-system owner constructs root Light and Dark `ThemeData`.
14. SPEC-FE-006 remains the authority selecting System/Light/Dark.
15. System selects between the same approved Light/Dark themes rather than a third theme definition.
16. `ColorScheme` and Material component themes are the normal styling mechanism.
17. Ordinary feature UI does not invent local theme colors.
18. No custom bundled font is required for Phase 000.
19. Standard shared spacing uses the approved small scale.
20. Shared radius/border/motion vocabularies remain small and semantic.
21. Standard Material controls are preferred over custom/wrapper equivalents.
22. Shared components require genuine reusable semantic/accessibility/composition value.
23. Feature-specific startup/settings controls remain feature-owned.
24. Configuration/readable content does not stretch indefinitely merely because the application window is large.
25. Phase 000 uses standard/comfortable global Material density.
26. Interactive targets normally provide at least 48×48 logical-pixel hit areas.
27. Every Phase 000 user action is keyboard-operable.
28. Focus traversal is logical and no tested flow creates a keyboard trap.
29. Keyboard focus is visibly distinguishable.
30. Argus-owned overlays/chrome do not obscure focused controls.
31. Normal text contrast is at least 4.5:1 and approved large-text contrast at least 3:1 for governed theme combinations.
32. Meaningful non-text contrast uses approximately a 3:1 baseline where visual distinction carries information/operation meaning.
33. State is not communicated solely through color.
34. Essential presentation remains usable at 200% text scaling.
35. Critical labels/errors/actions are not silently clipped by fixed layouts at the approved scale baseline.
36. Standard/native semantics are preferred.
37. Feature presentation remains responsible for semantic meaning.
38. Icon-only controls have accessible names.
39. Dynamic status announcements are meaningful and not emitted on every rebuild/animation frame.
40. Programmatic focus movement is reserved for genuine context changes rather than ordinary status announcements.
41. Authored motion honors platform reduced/disabled-animation requests.
42. Feature correctness never depends on observing an animation.
43. Loading presentation distinguishes blocking initialization, local initial loading, and retained-state/background operations.
44. Determinate progress is used only with authoritative quantitative progress.
45. Error presentation reflects semantic scope.
46. Empty state remains distinct from error state.
47. Transient notices do not replace durable failure/synchronization state.
48. Standard Material modal/menu behavior is preferred for Phase 000.
49. Visual destructive emphasis matches actual consequence.
50. Material icons are sufficient for the MVP icon vocabulary.
51. Decorative illustration is not required by Phase 000.
52. Theme extensions exist only for real semantic gaps in Material theme roles.
53. Design-system/responsive boundary tests are deterministic.
54. Semantic widget/integration tests remain primary for interaction/accessibility correctness.
55. Exact responsive boundaries are tested at 599/600/839/840/1199/1200.
56. Representative real surfaces are tested for keyboard operation, semantics, focus, target sizing, and text scaling.
57. Golden tests remain selective and secondary to semantic tests.
58. Golden fixtures control theme/size/text/animation/data inputs deterministically.
59. Changed golden baselines require visual review.
60. Manual Phase 000 verification includes keyboard-only and screen-reader smoke testing on the primary development platform.
61. Architecture checks protect design-system dependency direction, breakpoint ownership, and root-theme ownership where practical.
62. Phase 000 proves the design system through genuine startup, shell, recovery, and Settings surfaces rather than a speculative component catalog.

# Phase 000 Minimum Implementation

## 146. Minimum Production Surface

Phase 000 requires at least:

```text
core/responsive
├── WindowSizeClass
├── canonical thresholds
└── pure classifier

core/design_system
├── theme construction
├── semantic shared tokens
├── justified shared presentation primitives
└── accessibility-supporting presentation defaults

app composition
└── root Material theme application
```

with feature-owned startup/recovery/settings surfaces consuming those foundations.

## 147. Minimum Behavior

Phase 000 must demonstrate:

- correct four-class responsive shell switching;
- route/state preservation across resize;
- authoritative FE-006 Light/Dark/System theme application;
- first-shell theme restoration without a wrong-theme normal-shell flash;
- readable/usable startup and Settings content across representative widths;
- accessible keyboard operation across all real Phase 000 actions;
- visible focus;
- practical target sizing;
- semantic state/error/progress presentation;
- 200% text-scale usability;
- reduced-animation behavior for Argus-authored motion;
- Light/Dark visual consistency;
- selective visual-regression protection.

## 148. Minimum Test Surface

At minimum deterministic verification covers:

- width-class boundary classification;
- representative Compact/Medium/Expanded/Large shell rendering;
- Light/Dark theme construction;
- System effective brightness behavior through FE-006;
- representative contrast/accessibility-guideline checks;
- representative custom/shared target-size checks;
- keyboard traversal/activation;
- no keyboard trap in Phase 000 modal/recovery flows;
- visible focus behavior where Argus customizes it;
- 1.0× and 2.0× text-scale behavior;
- representative semantics tree/state assertions;
- reduced/disabled animation handling;
- selected reviewed goldens;
- manual keyboard/screen-reader smoke verification in the Phase 000 release checklist.

# Out of Scope

## 149. Explicitly Deferred Work

This specification does not introduce:

- Material 3 Expressive widgets/packages during MVP;
- a custom UI framework;
- a comprehensive design-token database;
- a replacement for Material standard controls;
- permanent branding;
- custom fonts;
- custom icon packs;
- dynamic operating-system accent palettes;
- a generic `AsyncValue` presentation framework;
- a generic business empty-state model;
- dense library/grid/table component contracts;
- application-defined persisted accessibility preferences;
- generic feature dialogs/effects bus;
- Storybook/Widgetbook/design-system explorer;
- blanket golden testing for all widgets;
- native title-bar/window chrome design.

# Phase 002 Android Design-System Amendment

Android remains governed by the same width/local-constraint responsive system rather than device-type checks. There is no Argus orientation lock.

Android-applicable presentation must:

- preserve practical Material touch targets and semantics at Compact widths;
- remain keyboard/pointer-capable when Android runs in desktop-like/windowed environments where those inputs exist, without making pointer presence layout authority;
- respect system bars, display cutouts, gesture navigation, IME, and safe insets through normal Flutter constraint/inset APIs rather than device-specific constants;
- preserve readable scaling and focus/semantics behavior through rotation, split screen, resizing, and fold/unfold transitions;
- use platform-adapted interactions such as Android Back without creating a separate visual language or route hierarchy.

Physical phone/tablet/handheld labels are test scenarios, not design tokens or breakpoint authority.

# References

## 150. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](spec-fe-004-routing-and-adaptive-application-shell.md)
- [SPEC-FE-005 — Startup and Recovery UI](spec-fe-005-startup-and-recovery-ui.md)
- [SPEC-FE-006 — Appearance Settings and Theme Application](spec-fe-006-appearance-settings-and-theme-application.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [Frontend Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
- [Flutter — Material Design](https://docs.flutter.dev/ui/design/material)
- [Flutter — Adaptive and Responsive Design](https://docs.flutter.dev/ui/adaptive-responsive)
- [Flutter — Accessibility](https://docs.flutter.dev/ui/accessibility)
- [Web Content Accessibility Guidelines (WCAG) 2.2](https://www.w3.org/TR/WCAG22/)
