# Durable Authenticated Production Staging Sessions

- **Document ID:** ADR-004
- **Status:** Accepted; implementation and production qualification remain separate
- **Owner:** Daniel
**Decision date:** 2026-10-26

## Context

Production fixture staging needs an authenticated owner session that preserves
request order across broker reconnections and can recover safely after process
interruption. The existing AQStore owns staging, mutation sequencing,
publication, cleanup, and store recovery. Moving those responsibilities would
change established authority and failure semantics.

The production path must also distinguish a completed durable export from a
process that merely emitted bytes or closed a pipe. Any uncertain mutation or
export needs a durable recovery obligation so a retry cannot repeat an
unobserved effect.

## Decision

Keep AQStore as the sole authority for staging, mutation, publication, cleanup,
and store recovery. Add a sequential authenticated broker session through the
existing owner-side adapter and native service/broker boundary. The native
service or broker owns production admission and durable export acceptance
behind narrow IPC. Python owns request orchestration and durable lifecycle
journaling.

Readiness and each request must bind the reviewed authorization, owner and
consent, installed service and broker identities, authenticated peer, session
and connection, boot epoch, request and operation, one-use nonce and strict
sequence, immutable original deadline, manifest and generation, and ordered
member declarations and digests. Freshness is signed and bound to the current
session epoch. Reconnection must authenticate the same installed identities
and continue the durable sequence state. A changed identity or boot epoch,
expired deadline, reused nonce, or out-of-order request fails closed. A
reconnection never renews the original deadline.

The private receiver accepts an export only after verifying the complete frame,
member order and digests, generation, authenticated native receipt, and durable
delivery. It acknowledges only durable acceptance. Missing or ambiguous
completion becomes `UNKNOWN` with a durable recovery obligation. Uncertain
mutations are never replayed; uncertain exports are not redelivered without a
receipt. Recovery does not extend deadlines or trigger cleanup.

The receipt trust boundary is the already authenticated XPC connection between
the installed broker and service. The service authenticates the broker process
identity before accepting a completion report or answering a receipt query; the
broker authenticates the service identity before accepting a query response.
The service stores completion in its fixed, service-owned, protected durable
journal only after the broker reports that the complete export passed frame,
member-order, digest, generation, deadline, and receiver-durability checks.
Every response is bound to the original request ID, session, service boot epoch,
sequence, deadline, manifest digest, generation, and ordered member digests.
The receipt is returned only over that authenticated XPC connection. It is not
a detached signature or a transferable credential, and no new receipt key is
introduced. Owner consent and freshness continue to use the existing signed
request path. Python acknowledges only a peer-authenticated, matching durable
receipt; after reconnect it queries for that receipt and never resends an
uncertain export.

Missing signing, consent, exact installed service identity, reviewed
authorization, or any other mandatory authority fails closed. Synthetic
qualification may exercise protocol behavior but cannot enable production.
Production staging remains `BLOCKED_UNSUPPORTED_EXCLUSIVITY` until required
installed identities, authorization, consent, and production isolation are
independently established.

## Consequences

Session recovery is possible only while the original identity, ordering,
epoch, and deadline remain verifiable. Lost acknowledgments create explicit
recovery work rather than implicit retries. Export completion means the
private receiver verified and durably accepted the declared generation and
members. AQStore retains its existing contracts and remains the sole authority
for store effects.

Host tests can qualify protocol and recovery logic. They cannot establish
installed signing, owner-key enrollment, consent, or production isolation.
This decision does not itself authorize production use or change the blocked
production status.

## Addendum: Versioned owner export evidence

The owner-side export consumer uses a versioned canonical evidence record
binding the request ID, session, service boot epoch, sequence, nonce, original
deadline, manifest digest, generation, ordered member digests, authenticated
native receipt, and durable receiver completion. Admission also binds the
reviewed authorization, owner consent and signing, installed service and
broker identities, authenticated peer, and current-session freshness. These
authority inputs are acquired and verified at the existing native service and
authenticated IPC boundary; caller-prepared flags or identity strings are not
production evidence. If that authority is unavailable, admission fails closed
with `BLOCKED_UNSUPPORTED_EXCLUSIVITY`. Host fixtures may test canonicalization
and rejection behavior but cannot issue production evidence. Recovery remains
receipt-query-only and never replays an uncertain export.
