# Architecture Decision Records

ADRs preserve the context and rationale for durable architectural choices.

**Identifier format:** `ADR-NNN`

Use an ADR when alternatives were materially plausible and future maintainers are likely to ask why the chosen design exists. Do not use ADRs to duplicate subsystem specifications.

ADRs are immutable after acceptance except for status and supersession metadata. A changed decision creates a new ADR that supersedes the old one.

Use [the ADR template](../templates/adr.md).


## Qualification decisions

| ID | Decision | Status |
|---|---|---|
| [ADR-001](adr-001-qualification-artifact-separation.md) | Isolated functional qualification and exact-distributable smoke use distinct artifacts and results | Complete |
| [ADR-002](adr-002-independent-owner-verdicts.md) | Owner verdicts are independent, evidence-linked, and append-only | Complete |
| [ADR-003](adr-003-reversible-source-unavailability.md) | Both simulated source-loss mechanisms are mandatory and reversible; physical removal is supplemental | Complete |
| [ADR-004](adr-004-best-effort-fixture-staging.md) | Owner fixture staging uses an unprivileged best-effort filesystem workflow | Complete |

`Complete` follows the governed status lifecycle. The accepted decision is stated in each ADR's Decision section; `Accepted` is not introduced as a status value.
