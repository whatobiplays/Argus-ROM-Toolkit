# Owner export prepare and dispatch continuation

The owner export client separates authenticated preparation from mutations.
The staging coordinator receives a lazy preparation bound to the exact grant,
expected manifest digest, and authorization digest. It checks those bindings
and verifies the reviewed manifest bytes and authorization file before native
preparation begins. The native broker then establishes the authenticated
service connection, sends `hello`, and uses the service response to bind consent
and freshness signatures to that connection and session. It returns a prepared
attempt while retaining the broker process and XPC session.

The Python owner client validates the prepared attempt against the same grant,
including its manifest and authorization digests, and records it in the private
lifecycle journal. It may request the broker continuation only after the
attempt is durable. The broker then performs `admit`, `stage`, and `export` in
order. Python accepts completion only from an authenticated, validated receipt.
If dispatch outcome is uncertain, recovery queries the receipt and never
replays the mutation.

The broker session now accepts a native `prepare_export` frame after a
successful `hello`. It uses the service-generated connection and session
bindings to construct and sign the consent and freshness envelopes with the
installed owner key. The broker returns the prepared attempt and retains the
same XPC transport. It rejects a mutation until Python sends the matching
`journal_ack`, then dispatches the prepared operations in order and exits after
export.

A reconnect does not resume a prepared mutation or replace its session
identity. A new `hello` creates a new service session, so an uncertain attempt
remains bound to its original connection, session, service boot, request,
sequence, authorization, and deadline. The owner opens a fresh authenticated
transport only to issue a bounded, read-only `receipt_query` for that exact
binding. The query does not send `hello` or any mutation. A matching receipt
resolves the original obligation; if no receipt can be obtained, the attempt
remains `UNKNOWN` and blocks a new attempt. Query timing uses a separate
monotonic OS deadline and does not extend the original mutation deadline.
The request carries this budget as `query_deadline_ns`, capped at five seconds;
the field is removed before the exact receipt binding is sent to the service.

Synthetic native and Python tests cover the continuation state machine,
ordering, rejection, grant-bound preparation, descriptor and deadline checks,
uncertain recovery, and receipt validation. They do not establish production
owner authority, kernel isolation, or production readiness. Production staging
remains `BLOCKED_UNSUPPORTED_EXCLUSIVITY`.

## Bounded transport and journal limits

Each native broker session line is limited to 12 MiB including its terminating
newline. The owner client applies that bound to preparation requests and
responses. Every submitted document remains limited to 64 KiB, and all decoded
documents together remain limited to 8 MiB; base64 expansion is included in the
12 MiB line limit.

Receipt queries use a separate 256 KiB request and response limit, including
the newline. This covers the duplicated member binding for a 400-member export
without increasing the ordinary 64 KiB document limit. The owner lifecycle
journal has an 8 MiB limit over every canonical record and newline. Append
preflight runs while holding the journal lock, so a full journal rejects a new
attempt before it is durably authorized and before any native dispatch occurs.

On service startup, receipt-journal recovery removes only bounded, service-owned
regular files matching the receipt writer's private temporary-name format.
Recovery preserves durable receipt records and capacity reservations. Unknown,
symlink, shared-link, incorrectly owned, or incorrectly permissioned entries
cause initialization to fail closed.
