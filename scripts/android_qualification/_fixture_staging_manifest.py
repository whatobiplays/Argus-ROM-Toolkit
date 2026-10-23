"""Strictly load and validate pinned fixture plans, manifests, and authority."""

from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from scripts.android_qualification import manifest
from typing import Any
import hashlib
import json
import os
import re
import stat
import unicodedata
import weakref
from ._fixture_staging_model import CompanionEdge, CoverageMode, FixtureCoverage, FixtureExpectation, FixtureFileExpectation, FixtureStagingError, FixtureStagingErrorCode, FixtureStagingGrant, IdentityEvidenceKind, _PrivateInputPin


FIXTURE_MANIFEST_SCHEMA_VERSION = 1


FIXTURE_PLAN_SCHEMA_VERSION = 1


MAX_PRIVATE_DOCUMENT_BYTES = 8 * 1024 * 1024


_SHA256 = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class _GrantBinding:
    reference: weakref.ReferenceType[FixtureStagingGrant]
    integrity: tuple[object, ...]


_GRANT_SEAL = object()


_GRANT_BINDINGS: dict[int, _GrantBinding] = {}


class _DuplicateKey(ValueError):
    pass


class _InvalidJsonConstant(ValueError):
    pass


def _reject_constant(_value: str) -> None:
    raise _InvalidJsonConstant


def _reject_float(_value: str) -> None:
    raise _InvalidJsonConstant


def _object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKey
        result[key] = value
    return result


def _private_document(path: Path) -> tuple[dict[str, Any], bytes, _PrivateInputPin]:
    """Read one owner-private JSON document without following file aliases."""

    try:
        absolute = Path(path).absolute()
        parent_path = absolute.parent
        parent_status = parent_path.lstat()
        status = absolute.lstat()
    except (OSError, TypeError, ValueError):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE) from None
    if (
        not stat.S_ISDIR(parent_status.st_mode)
        or parent_status.st_uid != os.geteuid()
        or stat.S_IMODE(parent_status.st_mode) & 0o077
        or not stat.S_ISREG(status.st_mode)
        or status.st_uid != os.geteuid()
        or stat.S_IMODE(status.st_mode) != 0o600
        or status.st_nlink != 1
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE)
    if status.st_size > MAX_PRIVATE_DOCUMENT_BYTES:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    parent_descriptor = -1
    descriptor = -1
    try:
        parent_descriptor = os.open(parent_path, directory_flags)
    except OSError:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE) from None
    try:
        opened_parent = os.fstat(parent_descriptor)
        parent_identity = (parent_status.st_dev, parent_status.st_ino)
        if (
            not stat.S_ISDIR(opened_parent.st_mode)
            or parent_identity != (opened_parent.st_dev, opened_parent.st_ino)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE)
        try:
            descriptor = os.open(
                absolute.name,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=parent_descriptor,
            )
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE) from None
        opened = os.fstat(descriptor)
        identity = (status.st_dev, status.st_ino, status.st_size, status.st_mtime_ns, status.st_ctime_ns)
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_uid != os.geteuid()
            or opened.st_nlink != 1
            or identity != (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE)
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(64 * 1024, MAX_PRIVATE_DOCUMENT_BYTES + 1 - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAX_PRIVATE_DOCUMENT_BYTES:
                raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
        encoded = b"".join(chunks)
        after = os.fstat(descriptor)
        if identity != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE)
        parent_after = os.fstat(parent_descriptor)
        path_parent_after = parent_path.lstat()
        if (
            parent_identity != (parent_after.st_dev, parent_after.st_ino)
            or parent_identity != (path_parent_after.st_dev, path_parent_after.st_ino)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNSAFE)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent_descriptor)
    try:
        document = json.loads(
            encoded.decode("utf-8"),
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
            parse_float=_reject_float,
        )
    except (
        UnicodeDecodeError,
        json.JSONDecodeError,
        _DuplicateKey,
        _InvalidJsonConstant,
        RecursionError,
        ValueError,
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID) from None
    if type(document) is not dict:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    pin = _PrivateInputPin(
        absolute,
        parent_status.st_dev,
        parent_status.st_ino,
        status.st_dev,
        status.st_ino,
        status.st_size,
        status.st_mtime_ns,
        status.st_ctime_ns,
        _canonical_sha256(document),
        hashlib.sha256(encoded).hexdigest(),
    )
    return document, encoded, pin


def _utc_now() -> datetime:
    """Return the current UTC wall time used for authority checks."""

    return datetime.now(timezone.utc)


def _canonical_sha256(document: object) -> str:
    try:
        encoded = json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (RecursionError, TypeError, ValueError, UnicodeEncodeError):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID) from None
    return hashlib.sha256(encoded).hexdigest()


def _fields(value: object, expected: set[str], *, optional: set[str] | None = None) -> dict[str, Any]:
    if type(value) is not dict:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    optional_fields = optional or set()
    if set(value) - expected - optional_fields or expected - set(value):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return value


def _string(value: object, *, maximum: int = 4096) -> str:
    if (
        type(value) is not str
        or not value
        or len(value) > maximum
        or value != value.strip()
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return value


def _digest(value: object) -> str:
    if type(value) is not str or _SHA256.fullmatch(value) is None:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return value


def _identifier(value: object) -> str:
    identifier = _string(value, maximum=256)
    if identifier in {".", ".."} or "/" in identifier or "\\" in identifier or ":" in identifier:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return identifier


def _destination_identifier_key(value: str) -> str:
    """Normalize one fixture identifier for case-insensitive destination names."""

    normalized = unicodedata.normalize("NFD", value).casefold()
    return unicodedata.normalize("NFD", normalized)


def _string_list(value: object) -> tuple[str, ...]:
    if type(value) is not list or not value:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    result = tuple(_string(item, maximum=256) for item in value)
    if len(result) != len(set(result)):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return result


def _safe_relative_path(value: object) -> str:
    path = _string(value)
    pieces = path.split("/")
    pure_path = PurePosixPath(path)
    if (
        path.startswith("/")
        or "\\" in path
        or ":" in path
        or any(piece in ("", ".", "..") for piece in pieces)
        or pure_path.is_absolute()
        or str(pure_path) != path
        or unicodedata.normalize("NFC", path) != path
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return path


def _parse_edges(value: object) -> tuple[CompanionEdge, ...]:
    if type(value) is not list:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    edges: list[CompanionEdge] = []
    for item in value:
        edge = _fields(item, {"source", "target"})
        edges.append(CompanionEdge(_safe_relative_path(edge["source"]), _safe_relative_path(edge["target"])))
    if len(set(edges)) != len(edges):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    return tuple(edges)


def _parse_fixture(value: object) -> FixtureExpectation:
    fixture = _fields(
        value,
        {
            "fixture_id",
            "platform",
            "representation",
            "identity",
            "group_id",
            "order",
            "entrypoint",
            "files",
            "companions",
            "identity_evidence",
        },
    )
    fixture_id = _identifier(fixture["fixture_id"])
    platform = _string(fixture["platform"], maximum=256)
    representation = _string(fixture["representation"], maximum=256)
    identity = _string(fixture["identity"], maximum=512)
    group_id = _string(fixture["group_id"], maximum=256)
    order = fixture["order"]
    if type(order) is not int or order < 0:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    entrypoint = _safe_relative_path(fixture["entrypoint"])
    raw_files = fixture["files"]
    if type(raw_files) is not list or not raw_files:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    files: list[FixtureFileExpectation] = []
    paths: set[str] = set()
    folded_paths: set[str] = set()
    folded_components: dict[tuple[str, ...], tuple[str, ...]] = {}
    for raw_file in raw_files:
        member = _fields(raw_file, {"path", "role", "size", "sha256"})
        path = _safe_relative_path(member["path"])
        role = _string(member["role"], maximum=64)
        size = member["size"]
        if type(size) is not int or size < 0:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
        digest = _digest(member["sha256"])
        if path in paths or path.casefold() in folded_paths:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
        components = tuple(path.split("/"))
        for index in range(1, len(components) + 1):
            spelling = components[:index]
            folded = tuple(component.casefold() for component in spelling)
            previous = folded_components.setdefault(folded, spelling)
            if previous != spelling:
                raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
        paths.add(path)
        folded_paths.add(path.casefold())
        files.append(FixtureFileExpectation(path, role, size, digest))
    if any(
        "/".join(path.split("/")[:index]) in paths
        for path in paths
        for index in range(1, len(path.split("/")))
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    if entrypoint not in paths:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    companions = _parse_edges(fixture["companions"])
    if any(edge.source not in paths or edge.target not in paths for edge in companions):
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
    try:
        evidence_kind = IdentityEvidenceKind(
            _string(fixture["identity_evidence"], maximum=64)
        )
    except ValueError:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID) from None
    expectation = FixtureExpectation(
        fixture_id,
        platform,
        representation,
        identity,
        group_id,
        order,
        entrypoint,
        tuple(files),
        companions,
        evidence_kind,
    )
    _validate_declared_companion_graph(expectation)
    return expectation


def _walk_companion_graph(
    entrypoint: str,
    adjacency: dict[str, list[str]],
) -> set[str] | None:
    """Return nodes reachable from ``entrypoint``; return ``None`` on a cycle."""

    active = {entrypoint}
    visited: set[str] = set()
    stack = [(entrypoint, iter(adjacency.get(entrypoint, ())))]
    while stack:
        path, targets = stack[-1]
        try:
            target = next(targets)
        except StopIteration:
            stack.pop()
            active.remove(path)
            visited.add(path)
            continue
        if target in active:
            return None
        if target in visited:
            continue
        active.add(target)
        stack.append((target, iter(adjacency.get(target, ()))))
    return visited


def _validate_declared_companion_graph(fixture: FixtureExpectation) -> None:
    """Reject declared cycles and members unreachable from the entrypoint."""

    paths = {item.path for item in fixture.files}
    adjacency: dict[str, list[str]] = {}
    for edge in fixture.companions:
        if edge.source not in paths or edge.target not in paths:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)
        adjacency.setdefault(edge.source, []).append(edge.target)
    visited = _walk_companion_graph(fixture.entrypoint, adjacency)
    if visited is None or visited != paths:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_INVALID)


def _parse_plan(document: dict[str, Any], authorization: manifest.SessionAuthorization) -> FixtureCoverage:
    plan = _fields(
        document,
        {"schema_version", "rules", "scenario_ids", "fixture_coverage", "host_reserve_bytes"},
        optional={"destination_reserve_bytes", "cleanup_authorized"},
    )
    if type(plan["schema_version"]) is not int or plan["schema_version"] != FIXTURE_PLAN_SCHEMA_VERSION:
        raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID)
    if type(plan["rules"]) is not dict:
        raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID)
    if _canonical_sha256(plan["rules"]) != authorization.rules_sha256:
        raise FixtureStagingError(FixtureStagingErrorCode.DIGEST_MISMATCH)
    scenarios = _string_list(plan["scenario_ids"])
    if scenarios != authorization.scenario_ids:
        raise FixtureStagingError(FixtureStagingErrorCode.DIGEST_MISMATCH)
    coverage = _fields(
        plan["fixture_coverage"],
        {"mode", "required_fixture_ids", "selected_fixture_ids", "mandatory_fixture_ids"},
    )
    try:
        mode = CoverageMode(_string(coverage["mode"], maximum=64))
    except ValueError:
        raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID) from None
    required = tuple(
        _identifier(item) for item in _string_list(coverage["required_fixture_ids"])
    )
    selected = tuple(
        _identifier(item) for item in _string_list(coverage["selected_fixture_ids"])
    )
    mandatory = tuple(
        _identifier(item) for item in _string_list(coverage["mandatory_fixture_ids"])
    )
    if not set(mandatory) <= set(required) or not set(mandatory) <= set(selected):
        raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID)
    if mode is CoverageMode.MANDATORY_FULL_PLAN and selected != required:
        raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID)
    if mode is CoverageMode.AUTHORIZED_PARTIAL_PLAN:
        selected_set = set(selected)
        ordered_selection = tuple(item for item in required if item in selected_set)
        if not selected_set < set(required) or selected != ordered_selection:
            raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID)
    host_reserve = plan["host_reserve_bytes"]
    destination_reserve = plan.get("destination_reserve_bytes", 0)
    if (
        type(host_reserve) is not int
        or host_reserve < 0
        or type(destination_reserve) is not int
        or destination_reserve < 0
        or type(plan.get("cleanup_authorized", False)) is not bool
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID)
    return FixtureCoverage(
        mode,
        required,
        selected,
        mandatory,
        host_reserve,
        destination_reserve,
        plan.get("cleanup_authorized", False),
    )


def _parse_fixture_manifest(
    document: dict[str, Any],
    authorization: manifest.SessionAuthorization,
    coverage: FixtureCoverage,
) -> tuple[FixtureExpectation, ...]:
    root = _fields(
        document,
        {"schema_version", "plan_sha256", "rules_sha256", "coverage_mode", "selected_fixture_ids", "fixtures"},
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != FIXTURE_MANIFEST_SCHEMA_VERSION:
        raise FixtureStagingError(FixtureStagingErrorCode.MANIFEST_INVALID)
    if (
        _digest(root["plan_sha256"]) != authorization.plan_sha256
        or _digest(root["rules_sha256"]) != authorization.rules_sha256
        or root["coverage_mode"] != coverage.mode.value
        or _string_list(root["selected_fixture_ids"]) != coverage.selected_fixture_ids
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.DIGEST_MISMATCH)
    raw_fixtures = root["fixtures"]
    if type(raw_fixtures) is not list:
        raise FixtureStagingError(FixtureStagingErrorCode.MANIFEST_INVALID)
    fixtures = tuple(_parse_fixture(item) for item in raw_fixtures)
    fixture_ids = tuple(item.fixture_id for item in fixtures)
    destination_keys = tuple(_destination_identifier_key(item) for item in fixture_ids)
    if len(destination_keys) != len(set(destination_keys)):
        raise FixtureStagingError(FixtureStagingErrorCode.MANIFEST_INVALID)
    if fixture_ids != coverage.selected_fixture_ids:
        raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)
    grouped_order: dict[str, list[int]] = {}
    for item in fixtures:
        grouped_order.setdefault(item.group_id, []).append(item.order)
    if any(
        values != sorted(values) or len(values) != len(set(values))
        for values in grouped_order.values()
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)
    return fixtures


def _register_grant(grant: FixtureStagingGrant) -> None:
    identity = id(grant)

    def discard(reference: weakref.ReferenceType[FixtureStagingGrant]) -> None:
        current = _GRANT_BINDINGS.get(identity)
        if current is not None and current.reference is reference:
            del _GRANT_BINDINGS[identity]

    _GRANT_BINDINGS[identity] = _GrantBinding(weakref.ref(grant, discard), _grant_integrity(grant))


def _grant_integrity(grant: FixtureStagingGrant) -> tuple[object, ...]:
    expectations = tuple(
        (
            fixture.fixture_id,
            fixture.platform,
            fixture.representation,
            fixture.identity,
            fixture.group_id,
            fixture.order,
            fixture.entrypoint,
            fixture.files,
            fixture.companions,
            fixture.identity_evidence,
        )
        for fixture in grant._fixture_expectations
    )
    return (
        grant.authorization_sha256,
        grant.approval_sha256,
        grant.approval_authorization_sha256,
        grant.fixture_manifest_sha256,
        grant.plan_sha256,
        grant.rules_sha256,
        grant.operation_id,
        grant.operation_timeout_seconds,
        grant.required_fixture_ids,
        grant.fixture_ids,
        grant.coverage_mode,
        grant.scenario_ids,
        grant.host_reserve_bytes,
        grant.destination_reserve_bytes,
        grant.cleanup_authorized,
        id(grant._authorization),
        id(grant._approval),
        expectations,
        grant._plan_pin,
        grant._fixture_pin,
        grant._seal is _GRANT_SEAL,
    )


def _is_issued_grant(grant: object) -> bool:
    if type(grant) is not FixtureStagingGrant:
        return False
    binding = _GRANT_BINDINGS.get(id(grant))
    if binding is None or binding.reference() is not grant:
        return False
    try:
        return binding.integrity == _grant_integrity(grant)
    except (AttributeError, RecursionError):
        return False


def authorize_fixture_staging(
    authorization: manifest.SessionAuthorization,
    approval: manifest.OwnerApproval,
    *,
    plan_path: Path,
    fixture_manifest_path: Path,
    operation_id: str,
) -> FixtureStagingGrant:
    """Issue an ephemeral grant bound to loader-validated owner inputs."""

    instant = _utc_now()
    if (
        type(authorization) is not manifest.SessionAuthorization
        or not manifest._is_loaded_session_authorization(authorization)
        or type(approval) is not manifest.OwnerApproval
        or not manifest._is_loaded_owner_approval(approval)
        or approval.authorization_sha256 != authorization.canonical_sha256
        or approval.owner_identity != authorization.owner_identity
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    if (
        type(instant) is not datetime
        or instant.tzinfo is None
        or instant.utcoffset() != timezone.utc.utcoffset(instant)
        or not authorization.issued_at <= instant < authorization.session_deadline
        or not approval.valid_from <= instant < approval.valid_until
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.AUTHORIZATION_EXPIRED)
    approval_source_details = manifest._loaded_owner_approval_source_details(approval)
    if (
        not manifest._owner_approval_source_matches(approval)
        or approval_source_details is None
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    if type(operation_id) is not str or not operation_id:
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_UNAUTHORIZED)
    operations = [item for item in authorization.operations if item.operation_id == operation_id]
    if len(operations) != 1:
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_UNAUTHORIZED)
    operation = operations[0]
    if (
        operation.category is not manifest.OperationCategory.FIXTURE_STAGING
        or operation.phase != "admission"
        or operation.target_serial != authorization.target_serial
        or operation.package_name != manifest.QUALIFICATION_PACKAGE
        or operation.permission_name is not None
        or operation.expected_prior_state is not None
        or operation.desired_state is not None
        or operation.restoration is not None
        or type(operation.timeout_seconds) is not int
        or operation.timeout_seconds <= 0
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_UNAUTHORIZED)

    plan_document, _plan_bytes, plan_pin = _private_document(plan_path)
    fixture_document, _fixture_bytes, fixture_pin = _private_document(fixture_manifest_path)
    if plan_pin.sha256 != authorization.plan_sha256 or fixture_pin.sha256 != authorization.fixture_manifest_sha256:
        raise FixtureStagingError(FixtureStagingErrorCode.DIGEST_MISMATCH)
    if _canonical_sha256(plan_document) != authorization.plan_sha256:
        raise FixtureStagingError(FixtureStagingErrorCode.DIGEST_MISMATCH)
    try:
        coverage = _parse_plan(plan_document, authorization)
    except FixtureStagingError as error:
        if error.code is FixtureStagingErrorCode.INPUT_INVALID:
            raise FixtureStagingError(FixtureStagingErrorCode.PLAN_INVALID) from None
        raise
    try:
        expectations = _parse_fixture_manifest(fixture_document, authorization, coverage)
    except FixtureStagingError as error:
        if error.code is FixtureStagingErrorCode.INPUT_INVALID:
            raise FixtureStagingError(FixtureStagingErrorCode.MANIFEST_INVALID) from None
        raise
    if any(item.identity_evidence is IdentityEvidenceKind.STRUCTURAL_ONLY for item in expectations):
        raise FixtureStagingError(FixtureStagingErrorCode.STRUCTURAL_ONLY)
    if not expectations or any(
        item.identity_evidence
        is not IdentityEvidenceKind.OWNER_APPROVED_EXPECTATION_MATCH
        for item in expectations
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)
    grant = FixtureStagingGrant(
        authorization.canonical_sha256,
        approval_source_details[3],
        approval.authorization_sha256,
        fixture_pin.sha256,
        plan_pin.sha256,
        authorization.rules_sha256,
        operation_id,
        operation.timeout_seconds,
        coverage.required_fixture_ids,
        tuple(item.fixture_id for item in expectations),
        coverage.mode.value,
        authorization.scenario_ids,
        coverage.host_reserve_bytes,
        max(coverage.destination_reserve_bytes, authorization.storage_reserve_bytes),
        coverage.cleanup_authorized,
        authorization,
        approval,
        expectations,
        plan_pin,
        fixture_pin,
        _GRANT_SEAL,
    )
    _register_grant(grant)
    return grant


def _private_pin_matches(pin: _PrivateInputPin) -> bool:
    try:
        _document, _encoded, current = _private_document(pin.path)
    except FixtureStagingError:
        return False
    return current == pin


def _validate_grant_for_use(
    grant: object, now: datetime, *, cleanup_window: bool = False
) -> FixtureStagingGrant:
    if not _is_issued_grant(grant):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    if (
        grant._seal is not _GRANT_SEAL
        or not manifest._is_loaded_session_authorization(grant._authorization)
        or not manifest._is_loaded_owner_approval(grant._approval)
        or grant.authorization_sha256 != grant._authorization.canonical_sha256
        or grant.approval_authorization_sha256 != grant._approval.authorization_sha256
        or grant.approval_authorization_sha256 != grant.authorization_sha256
        or grant._approval.owner_identity != grant._authorization.owner_identity
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    deadline = (
        grant._authorization.cleanup_deadline
        if cleanup_window and type(grant) is FixtureStagingGrant
        else grant._authorization.session_deadline
        if type(grant) is FixtureStagingGrant
        else None
    )
    if cleanup_window and not getattr(grant, "cleanup_authorized", False):
        raise FixtureStagingError(FixtureStagingErrorCode.CLEANUP_UNAUTHORIZED)
    if (
        type(now) is not datetime
        or now.tzinfo is None
        or now.utcoffset() != timezone.utc.utcoffset(now)
        or deadline is None
        or not grant._authorization.issued_at <= now < deadline
        or (
            not cleanup_window
            and not grant._approval.valid_from <= now < grant._approval.valid_until
        )
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.AUTHORIZATION_EXPIRED)
    approval_source_details = manifest._loaded_owner_approval_source_details(
        grant._approval
    )
    if (
        not manifest._owner_approval_source_matches(grant._approval)
        or approval_source_details is None
        or grant.approval_sha256 != approval_source_details[3]
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    operation = next(
        (item for item in grant._authorization.operations if item.operation_id == grant.operation_id),
        None,
    )
    if (
        operation is None
        or operation.category is not manifest.OperationCategory.FIXTURE_STAGING
        or operation.phase != "admission"
        or operation.target_serial != grant._authorization.target_serial
        or operation.package_name != manifest.QUALIFICATION_PACKAGE
        or operation.permission_name is not None
        or operation.expected_prior_state is not None
        or operation.desired_state is not None
        or operation.restoration is not None
        or type(operation.timeout_seconds) is not int
        or operation.timeout_seconds != grant.operation_timeout_seconds
        or operation.timeout_seconds <= 0
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_UNAUTHORIZED)
    if not _private_pin_matches(grant._plan_pin) or not _private_pin_matches(grant._fixture_pin):
        raise FixtureStagingError(FixtureStagingErrorCode.DIGEST_MISMATCH)
    return grant
