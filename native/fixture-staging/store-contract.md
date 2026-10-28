# Native snapshot store contract

## 1. Integration boundary

`core/AQStore.h` is the native-internal interface. Production opens only the
fixed protected service root after AQSecurity checks. The initializer duplicates
that descriptor and independently requires the store root to be euid-owned,
mode `0700`, and free of extended ACL entries before pinning its device/inode
and installation identity. This prevents an operator-UID process from replacing
a checked cleanup entry between identity validation and the pathname-based
`unlinkat` call. Production additionally relies on AQSecurity's protected
ancestor validation. Tests use private temporary roots; these tests confer no
production authority. The parent validates canonical external documents, owner
signatures, XPC connection, manifest/oracle graph, plan coverage, and the
complete timing-schema-2 record.
`deadline_ticks` is the immutable raw `mach_continuous_time()` store deadline.
For schema-1 service consent, the service samples this clock before sampling
`mach_absolute_time()` nanoseconds, then maps only the remaining signed deadline
duration into continuous ticks using the platform timebase and floor rounding.
The signed `deadline_ns` remains authoritative for service checks; the supplied
store deadline must be later than the sampled store tick and no later than the
mapped bound. This mapping can make store authority expire early after suspend,
but cannot extend the sleep-exclusive service deadline. The store checks its
original tick value before and after bounded IO and dispatch; it never rebases
or renews the deadline.

The exact authority/request dictionaries and methods are documented in the
header. The manifest remains the complete version-2 document described in
`docs/qualification/production-staging/oracle-contract.md`. Source descriptor
keys and exported paths are `fixture_id/file.path`. The source path is never
an eligibility dependency after the protected snapshot is sealed.

## 2. Persistence and recovery

`core/AQStore.m` keeps one canonical append-only record per accepted state
change in `.aq-record-<20 decimal digits>` files directly below the pinned root.
Each record is written to a new descriptor-relative file, made read-only and
fully synchronized before the root directory is synchronized. A sequence is
consumed by the dispatch record before payload effects. A crash therefore
retains the intent record and any partial payload directory.
Session mutations and journal appends share one reentrant store lock. The
session representation is snapshotted while that lock is held, and the lock
remains held through the durable record and root-directory sync. This makes the
event snapshot and its state transition one serialized operation.

Staging follows this order:

1. Validate authority, request bindings, sequence, generation, operations and
   the exact source-descriptor set.
2. Duplicate and validate every source descriptor, then persist dispatch and
   stage-intent records containing the random pending and final names.
3. Stream each declared member through a fixed 1 MiB buffer, checking the
   original raw-tick deadline, revocation state, capacity and source identity
   around every chunk.
4. Seal each file read-only with its source time, synchronize it, reopen it by
   descriptor and verify the complete size and SHA-256.
5. Verify the exact pending tree, atomically publish it with an exclusive
   no-replace rename, synchronize the root, verify the published tree again,
   and only then persist the eligible generation.

Capacity admission requires the remaining bytes plus the larger of the host
and destination reserves. Arithmetic is checked in 64 bits. Payload size has no
fixed fixture limit; the 1 MiB value is only the IO buffer size. Journal records
are limited to 4 MiB because they contain bounded metadata, never payload.

On construction, records are parsed in ordinal order. Missing ordinals, unknown
events, invalid canonical bytes, broken bindings, duplicate request digests at
different sequences, duplicate grant identifiers across sessions, or a
truncated record mark the root `blocked_retained`. Grant identifiers are
single-use: live admission consumes an identifier with its durable initial
`admitted` record, and recovery rebuilds the consumed set from each session's
first `admitted` record. Replay also validates event transitions: only a
`dispatch` record advances the request sequence, all follow-up records preserve
that sequence and request digest, only `stage_eligible` advances generation,
and each event must follow a compatible predecessor with a matching state and
effect. Impossible canonical histories mark the root `blocked_retained` without
changing the journal schema or record bytes.
Recovered sessions remain `blocked_retained`; the store does not repair,
replay or re-admit them. Inspection and recovery classification make no writes.

Export returns only the nonblocking read end of an anonymous pipe. The writer
uses descriptor-relative reads and emits the complete frame described by
`AQStore.h`; a revoked or expired writer closes the pipe without inventing a
terminal frame. Export-thread liveness checks read the root-blocked flag,
revocation flag, and immutable deadline under the store synchronization lock so
a concurrent revocation is observed consistently. Bytes already in the pipe
remain readable after revocation. Only a separate receiver can validate the
frame and record delivery. The canonical metadata header is limited to 64 KiB
by a shared store/broker bound. The store builds and validates that header
before consuming a request sequence or writing its dispatch record. This limit
applies only to header metadata; member payload bytes remain streamed without an
artificial size cap.

Cleanup first verifies the exact recorded tree and retains each observed file
and directory device/inode identity plus each file's type, mode, link count,
size, and expected digest. Every unlink and rmdir attempt is recorded before the
syscall. Immediately before mutation, descriptor-relative no-follow traversal
repeats `fstatat` for the exact entry and, for files, reopens and rehashes the
target. A replacement that no longer matches the preflight identity causes
`blocked_retained`; the replacement is not unlinked. A successful unlink is
synchronized before a completion record is written. Repeated cleanup is refused
after any attempted member, and an unconfirmed effect remains `uncertain` and
retained. Foreign entries cause preflight failure without deleting recorded
members.

The final identity check and pathname unlink are separate POSIX operations; the
store cannot atomically unlink by the verified descriptor's inode. A process
with the service UID could replace the directory entry in that interval. The
protected service-owned directory excludes ordinary owner-UID reach, but this
source does not prove safety against a same-service-UID adversary. Public
cleanup therefore remains `BLOCKED_UNSUPPORTED_EXCLUSIVITY` until approved
isolation evidence excludes that race. The identity checks do not qualify
production cleanup as safe.

Production construction accepts only the descriptor for
`/private/var/db/argus-qualification/staging`, owned by the running service,
with no group or other write permission. Test construction requires
`AQ_STORE_TESTING` and a private directory descriptor; it cannot grant
production authority. There is no environment, pathname or synthetic fallback.
The `before_record_snapshot` test boundary pauses under the store lock before
the immutable record is created; `recordWritten` receives that snapshot only
after the journal record is durable.

## 3. Executed validation

Host ARM64 build with the macOS 12.0 deployment target:

```sh
bash scripts/build_fixture_staging_native.sh store
```

The focused executable compiles `AQJSON.m`, `AQStore.m` and `store_tests.m`
with ARC and `AQ_STORE_TESTING`/`AQ_STORE_STANDALONE`. It completed with
`store tests: 0 failure(s)`. This synthetic test evidence does not establish
service isolation, reboot durability, receiver authentication, genuine ROM
provenance, physical-device behavior, very large real transfers or Issue #24
acceptance.
Store regressions cover fresh and recovered grant reuse, concurrent admission
of a single-use grant, and a deterministic interleaving between journal
snapshot creation and session revocation.
