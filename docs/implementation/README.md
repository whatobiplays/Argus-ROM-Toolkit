# Implementation Slices

Implementation slices define independently testable vertical increments within one phase.

**Identifier format:** `SLICE-P<phase>-NNN`

Example: `SLICE-P00-004`.

A slice references its parent phase and required specifications. It defines observable outcomes, boundaries, acceptance criteria, and verification. It does not restate architecture rationale or expand unresolved product scope.

Recommended layout:

```text
implementation/
└── phase-00/
    ├── README.md
    └── slice-001-<name>.md
```

Use [the implementation slice template](../templates/implementation-slice.md).
