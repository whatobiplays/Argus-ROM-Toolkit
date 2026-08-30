# Library capability qualification record

Qualification result: COMPLETE
Completion declaration: COMPLETE
Recorded: 2026-08-29

This record is the checked-in boundary for the supported library capability
set. `PASS` means the named evidence was observed, `FAIL` means the evidence
observed a defect, and `NOT RUN` means an external prerequisite was unavailable.
The completion declaration cannot change to `COMPLETE` while any mandatory
gate below is not `PASS`.

## Provider-specific live matrix

The live runner intentionally qualifies each provider against the platform
and identifier form that its production boundary supports. Canonical Argus
platform mappings remain unchanged.

| Provider | Argus platform | Provider input contract | Known non-secret probe pair |
| --- | --- | --- | --- |
| Playmatch | `nintendo.gb` / `PlatformId::NintendoGb` | `ARGUS_LIVE_PLAYMATCH_IDENTITY` is a lowercase, 64-character SHA-256 digest. The v2 adapter submits it to `GET https://playmatch.retrorealm.dev/api/v2/identify/relations` with fixed `fileName=argus-probe.rom` and `fileSize=0`; it does not require ROM bytes. | identity `2920c755dea482c7e465cce62ee54ccdc103181b18a867fac289d0cd68b5d262`; external game ID `c3c628c2-74f4-45a5-8a98-940b30362067`, both from the same successful Game Boy SHA-256 response. |
| GameTDB | `nintendo.nds` / `PlatformId::NintendoNds` | `ARGUS_LIVE_GAMETDB_IDENTIFIER` is the exact prefixed native ID accepted by the adapter (`product:` or `native:` followed by four uppercase alphanumeric characters). The adapter reads the official `GET https://www.gametdb.com/dstdb.txt?LANG=EN` catalog and does not title-search. | identifier `product:A2DE`; external ID `A2DE`; the pair is the official Nintendo DS record for *New Super Mario Bros.* |
| SteamGridDB | `nintendo.gb` / Game Boy-compatible | `ARGUS_LIVE_STEAMGRIDDB_EXTERNAL_ID` and `ARGUS_LIVE_STEAMGRIDDB_ASSET_ID` are decimal provider IDs. The API credential is never an environment input: production reads it only from keyring service `org.argus-rom-toolkit.providers`, account `steamgriddb`. The v2 adapter discovers grids, heroes, logos, and icons through the documented `/grids/game/{gameId}`, `/heroes/game/{gameId}`, `/logos/game/{gameId}`, and `/icons/game/{gameId}` endpoints. | external game ID `5249689`; asset ID `740598`, a bounded public discovery pair for Tetris (Game Boy). |

The six non-secret environment names are therefore:

```text
ARGUS_LIVE_PLAYMATCH_IDENTITY
ARGUS_LIVE_PLAYMATCH_EXTERNAL_ID
ARGUS_LIVE_GAMETDB_IDENTIFIER
ARGUS_LIVE_GAMETDB_EXTERNAL_ID
ARGUS_LIVE_STEAMGRIDDB_EXTERNAL_ID
ARGUS_LIVE_STEAMGRIDDB_ASSET_ID
```

The Playmatch response platform is validated as `Game Boy`; the GameTDB
catalog is explicitly DS-only; and SteamGridDB remains on the Game Boy probe.
No API key, authorization header, signed URL, or credential-bearing value is
accepted by the runner or written to this record.

SteamGridDB maps grids to `CoverFront`, heroes to `Banner`, logos to
`Logo`, and icons to `Icon`. A documented response's stable, credential-free
full-size `url` is validated and used transiently for original-byte download;
the application-generated opaque `asset:{id}` form is resolved back through
the corresponding documented game endpoint. Authorization is sent only to the
API discovery request, never to the CDN image request.

## Mandatory gates

| Gate | Status | Evidence |
| --- | --- | --- |
| identity-matrix | PASS | evidence: the closed catalog, transformation registry, cartridge fixture, optical fixture, and CHD fixture tests cover every advertised row with explicit expected values. |
| deterministic-providers | PASS | evidence: offline provider adapter tests use fixture transport and cover the real Playmatch v2 relations response, exact SHA-256/platform binding, co-hashed ambiguity, official GameTDB DS catalog records and artwork locators, SteamGridDB v2 grids/heroes/logos/icons envelopes and mappings, stable URL and opaque-locator resolution, malformed responses, bounds, failure isolation, redaction, and credential-store short-circuiting. |
| live-playmatch | PASS | evidence: the ignored production test passed against `https://playmatch.retrorealm.dev/api/v2/identify/relations` using the recorded Game Boy SHA-256 response and verified UUID, submitted identity, response identity, and `nintendo.gb` platform binding. |
| live-gametdb | PASS | evidence: the ignored production test passed against the official `https://www.gametdb.com/dstdb.txt?LANG=EN` DS catalog, resolving `product:A2DE` to external ID `A2DE`, then successfully repeating the exact metadata lookup for `nintendo.nds`. |
| live-steamgriddb | PASS | evidence: the focused and aggregate ignored production tests authenticated through the keyring-backed session, discovered Game Boy game `5249689` and artwork `740598` through the documented v2 API, verified its stable full-size source, and retrieved non-empty original bytes without sending the credential to the CDN. |
| library-scale | PASS | evidence: the 10,000-row Rust scale suite passed indexed page and cursor checks, facet/detail statement bounds, and one-row projection-write accounting. |
| migration | PASS | evidence: the embedded migration-chain tests pass through schema version 17 and verify the existing derived-provenance backfill without network or filesystem work. |
| security-privacy | PASS | evidence: provider, archive, source-boundary, artwork-store, safe-context, and credential tests pass their redaction, resource, traversal, and app-private-storage assertions. |
| generated-source | PASS | evidence: `just check-generated` regenerated FRB and Dart outputs and found no registered-output drift or machine-specific paths. |
| documentation-consistency | PASS | evidence: this record contains one row for every mandatory gate and one row for every PAC/TAC criterion, with status-specific evidence. |
| just-check | PASS | evidence: `just check` passed the generated-source, formatting, lint, architecture, and full deterministic Rust/Flutter repository gates. |
| desktop-native | PASS | evidence: the existing `test-library-desktop-qualification` target passed its real macOS Library lifecycle reconciliation run. |
| android-api36-arm64 | PASS | evidence: the existing `test-library-android-qualification` target passed on device `01411YEF01035740`, API 36, ARM64, with one Activity identity and one runtime generation preserved through lifecycle and foreground-host scenarios. |

## Product acceptance criteria

| Criterion | Status | Evidence |
| --- | --- | --- |
| PAC-1 | PASS | deterministic matrix and negative-path suites cover explicit identity rows, convergence, separation, malformed input, and deferred representations. |
| PAC-2 | PASS | Playmatch Game Boy, GameTDB Nintendo DS, and SteamGridDB Game Boy-compatible provider-specific production probes all passed on their documented adapter contracts. |
| PAC-3 | PASS | the backend page/cursor and projection-write scale checks pass on 10,000 synthetic games; Flutter controller tests assert page-sized requests and continuation-only loading. |
| PAC-4 | PASS | desktop and API 36 ARM64 native qualification both passed through the existing product/runtime architecture. |
| PAC-5 | PASS | Every mandatory identity, provider, scale, migration, security/privacy, generated-source, documentation, deterministic, desktop, and API 36 ARM64 gate has concrete PASS evidence, including all three live providers. |

## Technical acceptance criteria

| Criterion | Status | Evidence |
| --- | --- | --- |
| TAC-1 | PASS | explicit closed-world identity fixtures and existing malformed, ambiguity, mutation, dependency, convergence, separation, container-limit, and cancellation suites pass. |
| TAC-2 | PASS | offline adapter tests use no network and cover all three provider sessions, bounded payloads, failures, invalid credential paths, the Playmatch v2 and GameTDB DS wire fixtures, SteamGridDB v2 artwork endpoints and type mappings, and redaction. |
| TAC-3 | PASS | evidence: the separate live-provider runner emitted exactly one PASS for Playmatch `nintendo.gb`, GameTDB `nintendo.nds`, and SteamGridDB `nintendo.gb`; SGDB discovery and original-byte retrieval passed through the production keyring boundary. |
| TAC-4 | PASS | scale tests account for SQLite VM/full-scan work, stable query plans, statement growth, projection writes, and Flutter page ownership. |
| TAC-5 | PASS | migration tests exercise supported historical chains through v17 and keep identity absent unless durable proof exists. |
| TAC-6 | PASS | existing security/resource tests cover credential secrecy, safe diagnostics, archive traversal, parser budgets, bounded artwork, and private storage. |
| TAC-7 | PASS | `just check-generated` passed after regeneration with no registered generated-output drift. |
| TAC-8 | PASS | the qualification-record validator is wired into `just check` and enforces unique gates, statuses, and truthful completion state. |
| TAC-9 | PASS | the existing desktop runner remains the only desktop native target and passed on macOS. |
| TAC-10 | PASS | the existing Android runner remains the only API 36 ARM64 target and passed on the available API 36 ARM64 device. |
| TAC-11 | PASS | `just check` passed the complete generated-source, formatting, lint, architecture, Rust, Flutter, and qualification-record gates. |
| TAC-12 | PASS | evidence: this bounded record lists every mandatory gate and all PAC/TAC criteria with concrete PASS evidence; all three live providers passed, so the completion declaration is COMPLETE. |
