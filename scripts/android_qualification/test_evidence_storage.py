"""Test durable execution evidence through the public store capability."""

from __future__ import annotations

import errno
import hashlib
import json
import os
import stat
import tempfile
import unittest
import fcntl
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from scripts.android_qualification import evidence
from scripts.android_qualification import _evidence_storage


def _alias(kind: str, label: str) -> str:
    digest = hashlib.sha256(f"{kind}:{label}".encode("utf-8")).hexdigest()
    return f"{kind}-{digest[:32]}"


def _operation(label: str) -> str:
    return _alias("operation", label)


class _PublicationCrash(BaseException):
    pass


class EvidenceStorageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "qualification-evidence"

    @staticmethod
    def _session_spec() -> evidence.SessionSpec:
        return evidence.SessionSpec(
            session_id="1" * 32,
            scenario_id=_alias("scenario", "synthetic"),
            artifact=evidence.ArtifactPin(
                artifact_ref=_alias("artifact", "synthetic"),
                artifact_sha256="2" * 64,
                artifact_class=evidence.ArtifactClass.QUALIFICATION_VARIANT,
            ),
            authorization=evidence.AuthorizationPin(
                manifest_version=1,
                manifest_sha256="3" * 64,
            ),
            fixtures=evidence.FixturePin(
                manifest_version=1,
                manifest_sha256="4" * 64,
                corpus_ref=_alias("corpus", "fixture-synthetic"),
            ),
            plan=evidence.PlanPin(
                plan_ref=_alias("plan", "synthetic"),
                plan_version=1,
                plan_sha256="5" * 64,
            ),
            rules=evidence.AcceptanceRulesPin(
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
            ),
            environment=evidence.EnvironmentPin(
                platform=evidence.Platform.ANDROID,
                platform_version=_alias("platform-version", "api-35"),
                environment_ref=_alias("environment", "synthetic"),
                target_ref=_alias("target", "synthetic"),
            ),
            review_requirements=evidence.ReviewRequirements(
                required_evidence_refs=(_alias("evidence", "synthetic"),),
                objective_review_allowed=True,
                direct_owner_observation_allowed=True,
                retrospective_allowed=False,
            ),
        )

    def _rewrite_record(
        self,
        session_directory: Path,
        sequence: int,
        record: dict[str, object],
    ) -> None:
        event = record["event"]
        self.assertIsInstance(event, dict)
        record["event_sha256"] = hashlib.sha256(
            json.dumps(
                event,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
        ).hexdigest()
        digest_document = dict(record)
        digest_document.pop("record_sha256", None)
        record["record_sha256"] = hashlib.sha256(
            json.dumps(
                digest_document,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
        ).hexdigest()
        path = session_directory / f"record-{sequence:08d}.json"
        path.write_bytes(
            json.dumps(
                record,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
        )

    def _finalize_session(self, writer: object) -> evidence.ExecutionManifest:
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:01Z",
                evidence_refs=(_alias("evidence", "synthetic"),),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        return writer.verify_execution("1" * 32)

    @staticmethod
    def _failing_directory_sync(path: Path):
        target = (path.stat().st_dev, path.stat().st_ino)
        real_sync = _evidence_storage._fsync_directory

        def fail_target(descriptor: int) -> None:
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == target:
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
            real_sync(descriptor)

        return patch.object(_evidence_storage, "_fsync_directory", side_effect=fail_target)

    def test_each_new_evidence_directory_syncs_its_parent_before_acknowledgement(self) -> None:
        spec = self._session_spec()

        with self.subTest(directory="root"), tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name) / "evidence"
            writer = evidence.EvidenceStore(root).execution_writer()
            with self._failing_directory_sync(root.parent):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.open_session(spec, evidence.WriteRequest(operation_id=_operation("root-sync")))
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with self.subTest(directory="executions"), tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name) / "evidence"
            root.mkdir(mode=0o700)
            writer = evidence.EvidenceStore(root).execution_writer()
            with self._failing_directory_sync(root):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.open_session(spec, evidence.WriteRequest(operation_id=_operation("executions-sync")))
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with self.subTest(directory="session"), tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name) / "evidence"
            executions = root / "executions"
            executions.mkdir(mode=0o700, parents=True)
            root.chmod(0o700)
            executions.chmod(0o700)
            writer = evidence.EvidenceStore(root).execution_writer()
            with self._failing_directory_sync(executions):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.open_session(spec, evidence.WriteRequest(operation_id=_operation("session-sync")))
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with self.subTest(
            directory="owner-verdicts"
        ), tempfile.TemporaryDirectory() as temporary_name:
            root = Path(temporary_name) / "evidence"
            root.mkdir(mode=0o700)
            reviewer = evidence.EvidenceStore(root).owner_reviewer(_alias("owner", "synthetic"))
            with self._failing_directory_sync(root):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer._directory()
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_reopened_root_repeats_parent_sync_before_append_acknowledgement(self) -> None:
        spec = self._session_spec()
        writer = evidence.EvidenceStore(self.root).execution_writer()
        target = (self.root.parent.stat().st_dev, self.root.parent.stat().st_ino)
        real_sync = _evidence_storage._fsync_directory
        sync_attempts = 0
        events: list[str] = []

        def fail_once_then_record(descriptor: int) -> None:
            nonlocal sync_attempts
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == target:
                sync_attempts += 1
                if sync_attempts == 1:
                    events.append("root-parent-sync-failed")
                    raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
                if sync_attempts == 2:
                    events.append("root-parent-sync-repeated")
            real_sync(descriptor)

        def record_publication_parent_sync(stage: str) -> None:
            if stage == "after_parent_sync":
                events.append("record-parent-sync")

        request = evidence.WriteRequest(operation_id=_operation("reopened-root-sync"))
        with (
            patch.object(
                _evidence_storage,
                "_fsync_directory",
                side_effect=fail_once_then_record,
            ),
            patch.object(
                _evidence_storage,
                "_transition",
                side_effect=record_publication_parent_sync,
            ),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.open_session(spec, request)
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)
            self.assertTrue(self.root.is_dir())
            self.assertFalse((self.root / "executions").exists())

            receipt = writer.open_session(spec, request)

        events.append("append-acknowledged")
        self.assertFalse(receipt.idempotent)
        self.assertGreaterEqual(sync_attempts, 2)
        self.assertEqual(
            events,
            [
                "root-parent-sync-failed",
                "root-parent-sync-repeated",
                "record-parent-sync",
                "append-acknowledged",
            ],
        )

    def test_reopened_session_repeats_parent_sync_before_append_acknowledgement(self) -> None:
        spec = self._session_spec()
        self.root.mkdir(mode=0o700)
        executions = self.root / "executions"
        executions.mkdir(mode=0o700)
        writer = evidence.EvidenceStore(self.root).execution_writer()
        target = (executions.stat().st_dev, executions.stat().st_ino)
        real_sync = _evidence_storage._fsync_directory
        sync_attempts = 0
        events: list[str] = []

        def fail_once_then_record(descriptor: int) -> None:
            nonlocal sync_attempts
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == target:
                sync_attempts += 1
                if sync_attempts == 1:
                    events.append("session-parent-sync-failed")
                    raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
                events.append("session-parent-sync-repeated")
            real_sync(descriptor)

        def record_publication_parent_sync(stage: str) -> None:
            if stage == "after_parent_sync":
                events.append("record-parent-sync")

        request = evidence.WriteRequest(operation_id=_operation("reopened-session-sync"))
        with (
            patch.object(
                _evidence_storage,
                "_fsync_directory",
                side_effect=fail_once_then_record,
            ),
            patch.object(
                _evidence_storage,
                "_transition",
                side_effect=record_publication_parent_sync,
            ),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.open_session(spec, request)
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)
            self.assertTrue((executions / spec.session_id).is_dir())
            self.assertFalse(
                (executions / spec.session_id / "record-00000001.json").exists()
            )
            receipt = writer.open_session(spec, request)

        events.append("append-acknowledged")
        self.assertFalse(receipt.idempotent)
        self.assertEqual(sync_attempts, 2)
        self.assertEqual(
            events,
            [
                "session-parent-sync-failed",
                "session-parent-sync-repeated",
                "record-parent-sync",
                "append-acknowledged",
            ],
        )

    def test_multi_level_missing_private_root_validates_and_syncs_each_component(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            base = Path(temporary_name)
            level_one = base / "level-one"
            level_two = level_one / "level-two"
            root = level_two / "evidence"
            synced_parents: list[tuple[int, int]] = []
            real_sync = _evidence_storage._fsync_directory

            def record_sync(descriptor: int) -> None:
                opened = os.fstat(descriptor)
                synced_parents.append((opened.st_dev, opened.st_ino))
                real_sync(descriptor)

            with patch.object(_evidence_storage, "_fsync_directory", side_effect=record_sync):
                info = _evidence_storage._ensure_private_directory(root, create=True)

            for path in (level_one, level_two, root):
                with self.subTest(path=path.name):
                    opened = path.lstat()
                    self.assertTrue(stat.S_ISDIR(opened.st_mode))
                    self.assertEqual(opened.st_uid, os.geteuid())
                    self.assertEqual(stat.S_IMODE(opened.st_mode), 0o700)
            self.assertEqual((info.st_dev, info.st_ino), (root.lstat().st_dev, root.lstat().st_ino))
            self.assertEqual(
                synced_parents,
                [
                    (base.lstat().st_dev, base.lstat().st_ino),
                    (level_one.lstat().st_dev, level_one.lstat().st_ino),
                    (level_two.lstat().st_dev, level_two.lstat().st_ino),
                ],
            )

    def test_each_missing_root_parent_sync_failure_stops_before_descendant_creation(self) -> None:
        for failure_index in range(3):
            with self.subTest(failure_index=failure_index), tempfile.TemporaryDirectory() as temporary_name:
                base = Path(temporary_name)
                paths = (
                    base / "level-one",
                    base / "level-one" / "level-two",
                    base / "level-one" / "level-two" / "evidence",
                )
                real_sync = _evidence_storage._fsync_directory
                sync_count = 0

                def fail_at_parent(descriptor: int) -> None:
                    nonlocal sync_count
                    if sync_count == failure_index:
                        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
                    sync_count += 1
                    real_sync(descriptor)

                with patch.object(
                    _evidence_storage,
                    "_fsync_directory",
                    side_effect=fail_at_parent,
                ):
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        _evidence_storage._ensure_private_directory(paths[-1], create=True)

                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)
                for path in paths[failure_index + 1 :]:
                    self.assertFalse(path.exists())

    def test_parent_sync_failure_closes_unacknowledged_directory_descriptor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            base = Path(temporary_name)
            root = base / "level-one"
            opened_children: list[int] = []
            real_open = _evidence_storage.os.open

            def record_child(
                path: object,
                flags: int,
                mode: int = 0o777,
                *,
                dir_fd: int | None = None,
            ) -> int:
                descriptor = real_open(path, flags, mode, dir_fd=dir_fd)
                if path == "level-one" and dir_fd is not None:
                    opened_children.append(descriptor)
                return descriptor

            sync_failure = evidence.EvidenceError(
                evidence.EvidenceErrorCode.UNAVAILABLE
            )
            with (
                patch.object(_evidence_storage.os, "open", side_effect=record_child),
                patch.object(
                    _evidence_storage,
                    "_fsync_directory",
                    side_effect=sync_failure,
                ),
            ):
                with self.assertRaises(evidence.EvidenceError):
                    _evidence_storage._ensure_private_directory(root, create=True)

            self.assertEqual(len(opened_children), 1)
            child_descriptor = opened_children[0]
            try:
                with self.assertRaises(OSError) as caught:
                    os.fstat(child_descriptor)
                self.assertEqual(caught.exception.errno, errno.EBADF)
            finally:
                try:
                    os.close(child_descriptor)
                except OSError:
                    pass

    def test_canonical_directory_maps_child_access_and_identity_failures(self) -> None:
        target = self.root / "level-one" / "level-two"
        _evidence_storage._ensure_private_directory(
            target,
            create=True,
            root=self.root,
        )
        real_open = os.open

        def fail_child_open(path: object, *args: object, **kwargs: object) -> int:
            if kwargs.get("dir_fd") is not None:
                raise OSError(errno.EIO, "expected child open failure")
            return real_open(path, *args, **kwargs)  # type: ignore[arg-type]

        with patch.object(_evidence_storage.os, "open", side_effect=fail_child_open):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._open_canonical_directory(target)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

        real_stat = os.stat

        def differing_child_identity(
            path: object,
            *args: object,
            **kwargs: object,
        ) -> object:
            result = real_stat(path, *args, **kwargs)  # type: ignore[arg-type]
            if path == target.name and kwargs.get("dir_fd") is not None:
                return SimpleNamespace(
                    st_mode=result.st_mode,
                    st_dev=result.st_dev,
                    st_ino=result.st_ino + 1,
                )
            return result

        with patch.object(
            _evidence_storage.os,
            "stat",
            side_effect=differing_child_identity,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._open_canonical_directory(target)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_private_child_maps_unsafe_and_unavailable_entries(self) -> None:
        target = self.root / "private-child"
        _evidence_storage._ensure_private_directory(
            target,
            create=True,
            root=self.root,
        )
        regular_file = target / "regular-file"
        regular_file.write_bytes(b"not a directory")
        regular_file.chmod(0o600)
        symlink = target / "symlink"
        symlink.symlink_to("nested", target_is_directory=True)
        nested = target / "nested"
        _evidence_storage._ensure_private_directory(
            nested,
            create=True,
            root=self.root,
        )

        descriptor = _evidence_storage._open_canonical_directory(target)
        try:
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._open_private_child(descriptor, symlink.name)
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._open_private_child(descriptor, regular_file.name)
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

            with patch.object(
                _evidence_storage.os,
                "open",
                side_effect=OSError(errno.EIO, "private-child"),
            ):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    _evidence_storage._open_private_child(descriptor, nested.name)
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

            existing_descriptor = _evidence_storage._create_private_child(
                descriptor,
                nested.name,
            )
            os.close(existing_descriptor)

            with patch.object(
                _evidence_storage.os,
                "mkdir",
                side_effect=OSError(errno.EIO, "private-child"),
            ):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    _evidence_storage._create_private_child(descriptor, "new-child")
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)
        finally:
            os.close(descriptor)

    def test_private_path_maps_scope_missing_and_access_failures(self) -> None:
        outside = Path(self.temporary_directory.name) / "outside"
        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._open_private_path(self.root, outside, create=False)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

        existing = self.root / "existing"
        _evidence_storage._ensure_private_directory(
            existing,
            create=True,
            root=self.root,
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._open_private_path(
                self.root,
                self.root / "missing",
                create=False,
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        real_stat = os.stat

        def fail_existing_stat(
            path: object,
            *args: object,
            **kwargs: object,
        ) -> object:
            if path == existing.name and kwargs.get("dir_fd") is not None:
                raise OSError(errno.EIO, "private-path")
            return real_stat(path, *args, **kwargs)  # type: ignore[arg-type]

        with patch.object(
            _evidence_storage.os,
            "stat",
            side_effect=fail_existing_stat,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._open_private_path(
                    self.root,
                    existing,
                    create=False,
                )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_private_root_maps_type_and_metadata_failures(self) -> None:
        non_directory = Path(self.temporary_directory.name) / "not-a-directory"
        non_directory.write_bytes(b"not a directory")
        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._ensure_private_root(non_directory, create=True)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        blocked_child = non_directory / "evidence"
        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._ensure_private_root(blocked_child, create=True)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        missing = Path(self.temporary_directory.name) / "missing-root"
        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._ensure_private_root(missing, create=False)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with patch.object(
            Path,
            "lstat",
            side_effect=OSError(errno.EIO, "private-root"),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._ensure_private_root(missing, create=True)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_session_directory_collision_returns_a_bounded_error(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        executions = self.root / "executions"
        executions.mkdir(mode=0o700, parents=True)
        self.root.chmod(0o700)
        executions.chmod(0o700)
        collision = executions / ("1" * 32)
        collision.write_text("not a directory")
        collision.chmod(0o600)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.open_session(
                self._session_spec(),
                evidence.WriteRequest(operation_id=_operation("session-collision")),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)
        self.assertNotIn(str(self.root), str(caught.exception))

    def test_public_writes_reject_malformed_requests_after_type_check(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        spec = self._session_spec()

        with self.assertRaises(evidence.EvidenceError) as open_error:
            writer.open_session(spec, None)  # type: ignore[arg-type]
        self.assertEqual(open_error.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)

        opened = writer.open_session(
            spec,
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        with self.assertRaises(evidence.EvidenceError) as terminal_error:
            writer.append_terminal(
                "1" * 32,
                evidence.TerminalObservation(
                    outcome=evidence.TerminalOutcome.COMPLETED,
                    reason=evidence.TerminalReason.PLAN_COMPLETE,
                    ended_at="2026-10-23T01:00:01Z",
                    evidence_refs=(),
                ),
                None,  # type: ignore[arg-type]
            )
        self.assertEqual(terminal_error.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertEqual(opened.sequence, 1)
        self.assertEqual(writer.snapshot("1" * 32).record_count, 1)

    def test_open_session_rejects_malformed_expected_head_on_first_call(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.open_session(
                self._session_spec(),
                evidence.WriteRequest(
                    operation_id=_operation("open-malformed-head"),
                    occurred_at="2026-10-23T01:00:00Z",
                    expected_head_sha256="not-a-sha256",
                ),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertFalse(self.root.exists())

    def test_open_session_rejects_malformed_expected_head_on_replay(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        request = evidence.WriteRequest(
            operation_id=_operation("open-malformed-replay"),
            occurred_at="2026-10-23T01:00:00Z",
        )
        opened = writer.open_session(self._session_spec(), request)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.open_session(
                self._session_spec(),
                replace(request, expected_head_sha256="not-a-sha256"),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        snapshot = writer.snapshot("1" * 32)
        self.assertEqual(snapshot.record_count, 1)
        self.assertEqual(snapshot.head_sha256, opened.head_sha256)

    def test_append_rejects_observation_after_occurrence_without_publishing(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-ordering"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_assertion(
                "1" * 32,
                evidence.AssertionObservation(
                    assertion_ref=_alias("assertion", "ordering"),
                    rules_ref=_alias("rules", "synthetic"),
                    rules_version="1.0.0",
                    rules_sha256="6" * 64,
                    observed_at="2026-10-23T01:00:03Z",
                    expected_outcome=evidence.AssertionOutcome.PASSED,
                    actual_outcome=evidence.AssertionOutcome.PASSED,
                    evidence_refs=(_alias("evidence", "ordering"),),
                    measurements=(),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("assertion-ordering"),
                    occurred_at="2026-10-23T01:00:02Z",
                    expected_head_sha256=opened.head_sha256,
                ),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        session_directory = self.root / "executions" / ("1" * 32)
        self.assertFalse((session_directory / "record-00000002.json").exists())
        snapshot = writer.snapshot("1" * 32)
        self.assertEqual(snapshot.record_count, 1)
        self.assertEqual(snapshot.head_sha256, opened.head_sha256)

    def test_open_session_publishes_canonical_private_opened_record(self) -> None:
        store = evidence.EvidenceStore(self.root)
        writer = store.execution_writer()

        receipt = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(operation_id=_operation("open-session-synthetic")),
        )

        self.assertEqual(receipt.sequence, 1)
        self.assertFalse(receipt.idempotent)
        session_directory = self.root / "executions" / ("1" * 32)
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(session_directory.stat().st_mode), 0o700)
        record_path = session_directory / "record-00000001.json"
        self.assertEqual(stat.S_IMODE(record_path.stat().st_mode), 0o600)
        raw = record_path.read_bytes()
        record = json.loads(raw)
        digest_document = dict(record)
        record_digest = digest_document.pop("record_sha256")
        canonical_for_digest = json.dumps(
            digest_document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        canonical_record = json.dumps(
            record,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        self.assertEqual(raw, canonical_record)
        self.assertEqual(record_digest, hashlib.sha256(canonical_for_digest).hexdigest())
        self.assertEqual(record["event"]["event_type"], "session_opened")
        self.assertEqual(
            record["event"]["provenance"]["rules"]["rules_version"],
            "1.0.0",
        )
        self.assertEqual(record["previous_record_sha256"], None)
        self.assertEqual(record["sequence"], 1)

    def test_assertion_append_extends_the_digest_chain(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )

        assertion = writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(
                    evidence.Measurement(
                        name=_alias("measurement", "elapsed"),
                        value=250,
                        unit=evidence.MeasurementUnit.MILLISECONDS,
                    ),
                ),
            ),
            evidence.WriteRequest(
                operation_id=_operation("assertion-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )

        self.assertEqual(assertion.sequence, 2)
        snapshot = writer.snapshot("1" * 32)
        self.assertEqual(snapshot.head_sha256, assertion.record_sha256)
        self.assertEqual(len(snapshot.records), 2)
        self.assertEqual(snapshot.records[1].previous_record_sha256, opened.record_sha256)
        self.assertEqual(snapshot.records[1].event_type, "assertion")

    def test_unknown_assertion_fields_are_rejected(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("assertion-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000002.json"
        record = json.loads(record_path.read_bytes())
        record["event"]["arbitrary_log"] = "not-allowed"
        self._rewrite_record(session_directory, 2, record)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_snapshot_rejects_noncanonical_json_bytes(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000001.json"
        record = json.loads(record_path.read_bytes())
        record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_pre_sync_crash_retains_sidecar_and_retry_publishes_once(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.AssertionObservation(
            assertion_ref=_alias("assertion", "synthetic"),
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            observed_at="2026-10-23T01:00:01Z",
            expected_outcome=evidence.AssertionOutcome.PASSED,
            actual_outcome=evidence.AssertionOutcome.PASSED,
            evidence_refs=(_alias("evidence", "synthetic"),),
            measurements=(),
        )
        request = evidence.WriteRequest(
            operation_id=_operation("assertion-synthetic"),
            occurred_at="2026-10-23T01:00:02Z",
            expected_head_sha256=opened.head_sha256,
        )
        with patch.object(
            _evidence_storage,
            "_transition",
            side_effect=_PublicationCrash,
        ):
            with self.assertRaises(_PublicationCrash):
                writer.append_assertion("1" * 32, observation, request)

        retry = writer.append_assertion("1" * 32, observation, request)

        self.assertFalse(retry.idempotent)
        snapshot = writer.snapshot("1" * 32)
        self.assertEqual(snapshot.record_count, 2)
        session_directory = self.root / "executions" / ("1" * 32)
        self.assertEqual(len(list(session_directory.glob(".record-*.tmp-*"))), 1)

    def test_terminal_event_publishes_immutable_execution_manifest(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        lifecycle = writer.append_lifecycle(
            "1" * 32,
            evidence.LifecycleObservation(
                lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                evidence_refs=(_alias("evidence", "synthetic"),),
            ),
            evidence.WriteRequest(
                operation_id=_operation("execution-started-synthetic"),
                occurred_at="2026-10-23T01:00:01Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        terminal = writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:03Z",
                evidence_refs=(_alias("evidence", "synthetic"),),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-synthetic"),
                occurred_at="2026-10-23T01:00:04Z",
                expected_head_sha256=lifecycle.head_sha256,
            ),
        )

        manifest = writer.verify_execution("1" * 32)
        self.assertEqual(manifest.record_count, 3)
        self.assertEqual(manifest.terminal_record_sha256, terminal.record_sha256)
        self.assertEqual(manifest.head_sha256, terminal.record_sha256)
        self.assertEqual(writer.snapshot("1" * 32).state, "finalized")
        session_directory = self.root / "executions" / ("1" * 32)
        manifest_path = session_directory / "manifest.json"
        self.assertEqual(stat.S_IMODE(manifest_path.stat().st_mode), 0o600)
        raw_manifest = manifest_path.read_bytes()
        document = json.loads(raw_manifest)
        self.assertEqual(document["provenance"]["rules"]["rules_version"], "1.0.0")
        digest_document = dict(document)
        manifest_digest = digest_document.pop("manifest_sha256")
        self.assertEqual(
            manifest_digest,
            hashlib.sha256(
                json.dumps(
                    digest_document,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                    allow_nan=False,
                ).encode("utf-8")
            ).hexdigest(),
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_assertion(
                "1" * 32,
                evidence.AssertionObservation(
                    assertion_ref=_alias("assertion", "late"),
                    rules_ref=_alias("rules", "synthetic"),
                    rules_version="1.0.0",
                    rules_sha256="6" * 64,
                    observed_at="2026-10-23T01:00:05Z",
                    expected_outcome=evidence.AssertionOutcome.PASSED,
                    actual_outcome=evidence.AssertionOutcome.PASSED,
                    evidence_refs=(_alias("evidence", "synthetic"),),
                    measurements=(),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("assertion-late"),
                    occurred_at="2026-10-23T01:00:06Z",
                ),
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.FINALIZED)

    def test_terminal_exact_retry_ignores_occurrence_before_ended_at(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-terminal-retry"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.TerminalObservation(
            outcome=evidence.TerminalOutcome.COMPLETED,
            reason=evidence.TerminalReason.PLAN_COMPLETE,
            ended_at="2026-10-23T01:00:02Z",
            evidence_refs=(_alias("evidence", "terminal-retry"),),
        )
        request = evidence.WriteRequest(
            operation_id=_operation("terminal-retry-occurrence"),
            occurred_at="2026-10-23T01:00:05Z",
            expected_head_sha256=opened.head_sha256,
        )

        first = writer.append_terminal("1" * 32, observation, request)
        retry = writer.append_terminal(
            "1" * 32,
            observation,
            replace(request, occurred_at="2026-10-23T01:00:01Z"),
        )

        self.assertFalse(first.idempotent)
        self.assertTrue(retry.idempotent)
        self.assertEqual(retry.record_sha256, first.record_sha256)
        self.assertEqual(retry.head_sha256, first.head_sha256)
        self.assertEqual(writer.snapshot("1" * 32).record_count, 2)

    def test_terminal_changed_content_same_operation_conflicts(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-terminal-conflict"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.TerminalObservation(
            outcome=evidence.TerminalOutcome.COMPLETED,
            reason=evidence.TerminalReason.PLAN_COMPLETE,
            ended_at="2026-10-23T01:00:02Z",
            evidence_refs=(_alias("evidence", "terminal-conflict-original"),),
        )
        request = evidence.WriteRequest(
            operation_id=_operation("terminal-content-conflict"),
            occurred_at="2026-10-23T01:00:05Z",
            expected_head_sha256=opened.head_sha256,
        )

        first = writer.append_terminal("1" * 32, observation, request)
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_terminal(
                "1" * 32,
                replace(
                    observation,
                    evidence_refs=(
                        _alias("evidence", "terminal-conflict-changed"),
                    ),
                ),
                replace(request, occurred_at="2026-10-23T01:00:01Z"),
            )

        self.assertFalse(first.idempotent)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.OPERATION_CONFLICT,
        )
        self.assertEqual(writer.snapshot("1" * 32).record_count, 2)

    def test_snapshot_reuses_the_active_lock_when_verifying_a_finalized_manifest(
        self,
    ) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        self._finalize_session(writer)

        real_open = _evidence_storage.os.open
        lock_open_count = 0

        def track_lock_open(path: object, *args: object, **kwargs: object) -> int:
            nonlocal lock_open_count
            if path == ".execution.lock":
                lock_open_count += 1
            return real_open(path, *args, **kwargs)  # type: ignore[arg-type]

        with (
            patch.object(_evidence_storage.os, "open", side_effect=track_lock_open),
            patch.object(
                _evidence_storage.fcntl,
                "flock",
                wraps=fcntl.flock,
            ) as flock,
        ):
            snapshot = writer.snapshot("1" * 32)

        self.assertEqual(snapshot.state, "finalized")
        self.assertEqual(lock_open_count, 1)
        flock.assert_called_once()

    def test_recovery_finalizes_durable_terminal_before_missing_manifest(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        terminal = writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:01Z",
                evidence_refs=(_alias("evidence", "synthetic"),),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        manifest_path = session_directory / "manifest.json"
        expected_bytes = manifest_path.read_bytes()
        manifest_path.unlink()

        recovered = writer.recover("1" * 32)

        self.assertEqual(recovered.state, evidence.RecoveryState.FINALIZED)
        self.assertFalse(recovered.appended_interruption)
        self.assertEqual(manifest_path.read_bytes(), expected_bytes)
        self.assertEqual(writer.verify_execution("1" * 32).head_sha256, terminal.head_sha256)

    def test_recovery_rejects_executions_symlink_swap_before_manifest_read(
        self,
    ) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-recovery-symlink-race"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )

        session_id = "1" * 32
        executions = self.root / "executions"
        real_session_directory = executions.with_name("executions.real") / session_id
        outside_executions = (
            Path(self.temporary_directory.name) / "outside" / "executions"
        )
        outside_session = outside_executions / session_id
        outside_session.mkdir(parents=True, mode=0o700)
        outside_executions.parent.chmod(0o700)
        outside_executions.chmod(0o700)
        outside_session.chmod(0o700)
        outside_manifest = outside_session / "manifest.json"
        outside_manifest_bytes = b"outside manifest must not be read"
        outside_manifest.write_bytes(outside_manifest_bytes)
        outside_manifest.chmod(0o600)
        outside_manifest_inode = (
            outside_manifest.stat().st_dev,
            outside_manifest.stat().st_ino,
        )

        real_read_private_file = _evidence_storage._read_private_file
        manifest_root: Path | None = None
        race_hook_called = False

        def swap_executions_before_manifest_read(
            directory: Path,
            name: str,
            *,
            root: Path | None = None,
        ) -> bytes:
            nonlocal manifest_root, race_hook_called
            if name == "manifest.json":
                self.assertFalse(race_hook_called)
                self.assertEqual(root, self.root)
                manifest_root = root
                executions.rename(executions.with_name("executions.real"))
                executions.symlink_to(outside_executions, target_is_directory=True)
                race_hook_called = True
            return real_read_private_file(directory, name, root=root)

        open_calls = 0
        outside_opens = 0
        real_open = os.open

        def track_outside_manifest_open(
            path: str | bytes | os.PathLike[str] | os.PathLike[bytes],
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal open_calls, outside_opens
            open_calls += 1
            descriptor = real_open(path, flags, mode, dir_fd=dir_fd)
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == outside_manifest_inode:
                outside_opens += 1
            return descriptor

        with (
            patch.object(
                _evidence_storage,
                "_read_private_file",
                side_effect=swap_executions_before_manifest_read,
            ),
            patch.object(
                _evidence_storage.os,
                "open",
                side_effect=track_outside_manifest_open,
            ),
            self.assertRaises(evidence.EvidenceError) as caught,
        ):
            writer.recover(
                session_id,
                abandoned_before="2026-10-23T01:00:01Z",
            )

        self.assertTrue(race_hook_called)
        self.assertEqual(manifest_root, self.root)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)
        self.assertGreater(open_calls, 0)
        self.assertEqual(outside_opens, 0)
        self.assertEqual(outside_manifest.read_bytes(), outside_manifest_bytes)
        self.assertFalse((real_session_directory / "manifest.json").exists())

    def test_active_writer_makes_recovery_busy_without_changes(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        lock_path = session_directory / ".execution.lock"
        descriptor = os.open(lock_path, os.O_RDWR | os.O_NOFOLLOW)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            recovered = writer.recover(
                "1" * 32,
                abandoned_before="2026-10-24T00:00:00Z",
            )
        finally:
            os.close(descriptor)

        self.assertEqual(recovered.state, evidence.RecoveryState.BUSY)
        self.assertFalse(recovered.appended_interruption)
        self.assertFalse((session_directory / "manifest.json").exists())
        self.assertEqual(writer.snapshot("1" * 32).record_count, 1)

    def test_only_explicit_abandonment_cutoff_interrupts_open_execution(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )

        idle = writer.recover("1" * 32)
        recent = writer.recover(
            "1" * 32,
            abandoned_before="2026-10-23T00:59:59Z",
        )
        interrupted = writer.recover(
            "1" * 32,
            abandoned_before="2026-10-23T01:00:00Z",
        )
        repeated = writer.recover("1" * 32)

        self.assertEqual(idle.state, evidence.RecoveryState.INCOMPLETE)
        self.assertEqual(recent.state, evidence.RecoveryState.INCOMPLETE)
        self.assertEqual(interrupted.state, evidence.RecoveryState.INTERRUPTED)
        self.assertTrue(interrupted.appended_interruption)
        self.assertEqual(repeated.state, evidence.RecoveryState.FINALIZED)
        self.assertFalse(repeated.appended_interruption)
        snapshot = writer.snapshot("1" * 32)
        self.assertEqual(snapshot.record_count, 2)
        self.assertEqual(snapshot.records[-1].event_type, "terminal")

    def test_crash_before_publication_does_not_publish_observation(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.AssertionObservation(
            assertion_ref=_alias("assertion", "synthetic"),
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            observed_at="2026-10-23T01:00:01Z",
            expected_outcome=evidence.AssertionOutcome.PASSED,
            actual_outcome=evidence.AssertionOutcome.PASSED,
            evidence_refs=(_alias("evidence", "synthetic"),),
            measurements=(),
        )
        request = evidence.WriteRequest(
            operation_id=_operation("assertion-synthetic"),
            occurred_at="2026-10-23T01:00:02Z",
            expected_head_sha256=opened.head_sha256,
        )

        def crash(stage: str) -> None:
            if stage == "before_publish":
                raise _PublicationCrash

        with patch.object(_evidence_storage, "_transition", side_effect=crash):
            with self.assertRaises(_PublicationCrash):
                writer.append_assertion("1" * 32, observation, request)

        self.assertEqual(writer.snapshot("1" * 32).record_count, 1)
        retry = writer.append_assertion("1" * 32, observation, request)
        self.assertEqual(retry.sequence, 2)

    def test_persisted_json_rejects_duplicate_floats_nonfinite_and_schema(self) -> None:
        variants = {
            evidence.EvidenceErrorCode.DUPLICATE_KEY: lambda raw: (
                raw[:-1] + b',"sequence":1}'
            ),
            evidence.EvidenceErrorCode.FLOAT_REJECTED: lambda raw: raw.replace(
                b'"sequence":1',
                b'"sequence":1.0',
                1,
            ),
            evidence.EvidenceErrorCode.NON_FINITE_NUMBER: lambda raw: raw.replace(
                b'"sequence":1',
                b'"sequence":NaN',
                1,
            ),
            evidence.EvidenceErrorCode.UNSUPPORTED_SCHEMA: lambda raw: raw.replace(
                b'"schema_version":1',
                b'"schema_version":2',
                1,
            ),
        }
        for expected, mutate in variants.items():
            with self.subTest(expected=expected):
                with tempfile.TemporaryDirectory() as temporary_name:
                    root = Path(temporary_name) / "evidence"
                    writer = evidence.EvidenceStore(root).execution_writer()
                    writer.open_session(
                        self._session_spec(),
                        evidence.WriteRequest(
                            operation_id=_operation("open-session-synthetic"),
                            occurred_at="2026-10-23T01:00:00Z",
                        ),
                    )
                    record_path = (
                        root
                        / "executions"
                        / ("1" * 32)
                        / "record-00000001.json"
                    )
                    record_path.write_bytes(mutate(record_path.read_bytes()))
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        writer.snapshot("1" * 32)
                    self.assertEqual(caught.exception.code, expected)

    def test_persisted_record_rejects_boolean_schema_and_sequence(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000001.json"
        original = record_path.read_bytes()

        for field in ("schema_version", "sequence"):
            with self.subTest(field=field):
                document = json.loads(original)
                document[field] = True
                self._rewrite_record(session_directory, 1, document)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.CORRUPT,
                )

    def test_record_parser_maps_malformed_bytes_and_digest_failures(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-parser-fault"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        record_path = self.root / "executions" / ("1" * 32) / "record-00000001.json"
        original = record_path.read_bytes()
        original_document = json.loads(original)
        bad_record_digest = dict(original_document)
        bad_record_digest["record_sha256"] = "0" * 64
        bad_event_digest = dict(original_document)
        bad_event_digest["event_sha256"] = "0" * 64
        cases = (
            (b"\xff", evidence.EvidenceErrorCode.INVALID_INPUT),
            (b"{", evidence.EvidenceErrorCode.INVALID_INPUT),
            (b"[]", evidence.EvidenceErrorCode.CORRUPT),
            (original + b"\n", evidence.EvidenceErrorCode.CORRUPT),
            (
                _evidence_storage._canonical_bytes(bad_record_digest),
                evidence.EvidenceErrorCode.CORRUPT,
            ),
            (
                _evidence_storage._canonical_bytes(bad_event_digest),
                evidence.EvidenceErrorCode.CORRUPT,
            ),
        )

        for index, (raw, expected) in enumerate(cases):
            with self.subTest(index=index):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    _evidence_storage._parse_record(
                        raw,
                        session_id="1" * 32,
                        sequence=1,
                    )
                self.assertEqual(caught.exception.code, expected)

        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._record_pattern("record-00000000.json")
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_manifest_rejects_boolean_integer_fields(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        self._finalize_session(writer)
        manifest_path = self.root / "executions" / ("1" * 32) / "manifest.json"
        original = manifest_path.read_bytes()

        for field in ("schema_version", "record_count", "terminal_sequence"):
            with self.subTest(field=field):
                document = json.loads(original)
                document[field] = True
                digest_document = dict(document)
                digest_document.pop("manifest_sha256")
                document["manifest_sha256"] = _evidence_storage._canonical_sha256(
                    digest_document
                )
                manifest_path.write_bytes(_evidence_storage._canonical_bytes(document))
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.verify_execution("1" * 32)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
                )

    def test_symlinked_ancestor_above_root_is_supported_without_linked_store_paths(
        self,
    ) -> None:
        actual_parent = Path(self.temporary_directory.name) / "actual-parent"
        actual_parent.mkdir(mode=0o700)
        ancestor_link = Path(self.temporary_directory.name) / "ancestor-link"
        ancestor_link.symlink_to(actual_parent, target_is_directory=True)
        root = ancestor_link / "nested" / "qualification-evidence"
        writer = evidence.EvidenceStore(root).execution_writer()

        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-linked-ancestor"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )

        canonical_root = actual_parent / "nested" / "qualification-evidence"
        self.assertEqual(writer.snapshot("1" * 32).record_count, 1)
        self.assertFalse(canonical_root.is_symlink())
        self.assertEqual(stat.S_IMODE(canonical_root.stat().st_mode), 0o700)
        for path in canonical_root.rglob("*"):
            self.assertFalse(path.is_symlink(), path)

    def test_intermediate_execution_symlink_never_accesses_outside_tree(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-before-symlink"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )

        session_id = "1" * 32
        executions = self.root / "executions"
        outside_executions = Path(self.temporary_directory.name) / "outside" / "executions"
        outside_session = outside_executions / session_id
        outside_session.mkdir(parents=True, mode=0o700)
        outside_executions.parent.chmod(0o700)
        outside_executions.chmod(0o700)
        outside_session.chmod(0o700)

        source_record = executions / session_id / "record-00000001.json"
        outside_record = outside_session / source_record.name
        outside_record.write_bytes(source_record.read_bytes())
        outside_record.chmod(0o600)
        executions.rename(executions.with_name("executions.real"))
        executions.symlink_to(outside_executions, target_is_directory=True)

        outside_inode = (outside_record.stat().st_dev, outside_record.stat().st_ino)
        outside_reads = 0
        real_read = os.read

        def track_outside_read(descriptor: int, length: int) -> bytes:
            nonlocal outside_reads
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == outside_inode:
                outside_reads += 1
            return real_read(descriptor, length)

        with patch.object(_evidence_storage.os, "read", side_effect=track_outside_read):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.snapshot(session_id)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)
        self.assertEqual(outside_reads, 0)
        self.assertFalse((outside_session / ".execution.lock").exists())
        self.assertEqual(outside_record.read_bytes(), source_record.read_bytes())

    def test_filesystem_faults_are_stable_evidence_errors(self) -> None:
        secret = "raw-os-text-/private/outside"
        real_open = os.open
        real_stat = os.stat

        def fail_temporary_open(path: object, *args: object, **kwargs: object) -> int:
            if isinstance(path, str) and path.startswith(".record-00000002.tmp-"):
                raise OSError(errno.EIO, secret)
            return real_open(path, *args, **kwargs)  # type: ignore[arg-type]

        def fail_post_publication_stat(
            path: object,
            *args: object,
            **kwargs: object,
        ) -> os.stat_result:
            if path == "record-00000002.json" and kwargs.get("dir_fd") is not None:
                raise OSError(errno.EIO, secret)
            return real_stat(path, *args, **kwargs)  # type: ignore[arg-type]

        cases = (
            (
                "lock-io",
                lambda: patch.object(
                    _evidence_storage.fcntl,
                    "flock",
                    side_effect=OSError(errno.EIO, secret),
                ),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "lock-contention",
                lambda: patch.object(
                    _evidence_storage.fcntl,
                    "flock",
                    side_effect=OSError(errno.EAGAIN, secret),
                ),
                evidence.EvidenceErrorCode.BUSY,
            ),
            (
                "temporary-open",
                lambda: patch.object(_evidence_storage.os, "open", side_effect=fail_temporary_open),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "temporary-write",
                lambda: patch.object(
                    _evidence_storage.os,
                    "write",
                    side_effect=OSError(errno.EIO, secret),
                ),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "temporary-fsync",
                lambda: patch.object(
                    _evidence_storage.os,
                    "fsync",
                    side_effect=OSError(errno.EIO, secret),
                ),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "post-publication-stat",
                lambda: patch.object(
                    _evidence_storage.os,
                    "stat",
                    side_effect=fail_post_publication_stat,
                ),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
        )

        for case, fault, expected_code in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary_name:
                root = Path(temporary_name) / "qualification-evidence"
                writer = evidence.EvidenceStore(root).execution_writer()
                opened = writer.open_session(
                    self._session_spec(),
                    evidence.WriteRequest(
                        operation_id=_operation("fault-open-session"),
                        occurred_at="2026-10-23T01:00:00Z",
                    ),
                )
                observation = evidence.AssertionObservation(
                    assertion_ref=_alias("assertion", "fault"),
                    rules_ref=_alias("rules", "synthetic"),
                    rules_version="1.0.0",
                    rules_sha256="6" * 64,
                    observed_at="2026-10-23T01:00:01Z",
                    expected_outcome=evidence.AssertionOutcome.PASSED,
                    actual_outcome=evidence.AssertionOutcome.PASSED,
                    evidence_refs=(_alias("evidence", "fault"),),
                    measurements=(),
                )

                with fault():
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        writer.append_assertion(
                            "1" * 32,
                            observation,
                            evidence.WriteRequest(
                                operation_id=_operation("fault-assertion"),
                                occurred_at="2026-10-23T01:00:02Z",
                                expected_head_sha256=opened.head_sha256,
                            ),
                        )

                self.assertEqual(caught.exception.code, expected_code)
                self.assertNotIn(secret, str(caught.exception))
                self.assertNotIn(str(root), str(caught.exception))

    def test_private_file_maps_identity_and_concurrent_mutation_failures(self) -> None:
        directory = self.root / "private-files"
        _evidence_storage._ensure_private_directory(
            directory,
            create=True,
            root=self.root,
        )
        entry = directory / "record.json"
        entry.write_bytes(b"{}")
        entry.chmod(0o600)

        with self.assertRaises(evidence.EvidenceError) as caught:
            _evidence_storage._read_private_file(directory, "../record.json")
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

        real_fstat = os.fstat

        def changed_stat(stat_result: os.stat_result, **changes: int) -> object:
            values = {
                name: getattr(stat_result, name)
                for name in (
                    "st_mode",
                    "st_uid",
                    "st_size",
                    "st_nlink",
                    "st_dev",
                    "st_ino",
                    "st_mtime_ns",
                    "st_ctime_ns",
                )
            }
            values.update(changes)
            return SimpleNamespace(**values)

        def mismatch_identity(descriptor: int) -> object:
            opened = real_fstat(descriptor)
            if stat.S_ISREG(opened.st_mode):
                return changed_stat(opened, st_ino=opened.st_ino + 1)
            return opened

        with patch.object(_evidence_storage.os, "fstat", side_effect=mismatch_identity):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._read_private_file(directory, entry.name)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

        with patch.object(
            _evidence_storage.os,
            "read",
            return_value=b"x" * (_evidence_storage.MAX_RECORD_BYTES + 1),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._read_private_file(directory, entry.name)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)

        regular_stats = 0

        def changing_after_read(descriptor: int) -> object:
            nonlocal regular_stats
            opened = real_fstat(descriptor)
            if stat.S_ISREG(opened.st_mode):
                regular_stats += 1
                if regular_stats == 2:
                    return changed_stat(opened, st_mtime_ns=opened.st_mtime_ns + 1)
            return opened

        with patch.object(
            _evidence_storage.os,
            "fstat",
            side_effect=changing_after_read,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._read_private_file(directory, entry.name)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_private_storage_rejects_symlink_and_hardlink_aliases(self) -> None:
        real_root = Path(self.temporary_directory.name) / "real-evidence"
        real_root.mkdir(mode=0o700)
        symlink_root = Path(self.temporary_directory.name) / "evidence-link"
        symlink_root.symlink_to(real_root, target_is_directory=True)
        with self.assertRaises(evidence.EvidenceError) as caught:
            evidence.EvidenceStore(symlink_root).execution_writer().open_session(
                self._session_spec(),
                evidence.WriteRequest(operation_id=_operation("symlink-root")),
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000001.json"
        alias = session_directory / "record-alias.json"
        alias.write_bytes(record_path.read_bytes())
        os.chmod(alias, 0o600)
        record_path.unlink()
        os.link(alias, record_path)
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_private_root_permissions_are_exact(self) -> None:
        self.root.mkdir(mode=0o755)
        os.chmod(self.root, 0o755)
        with self.assertRaises(evidence.EvidenceError) as caught:
            evidence.EvidenceStore(self.root).execution_writer().open_session(
                self._session_spec(),
                evidence.WriteRequest(operation_id=_operation("unsafe-root")),
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_opaque_references_reject_paths_and_credentials(self) -> None:
        for value in (
            "../private",
            "/private/rom.gba",
            "https://example.invalid/token",
            "device-serial:ABC123",
            "password-secret",
        ):
            with self.subTest(value=value):
                spec = self._session_spec()
                object.__setattr__(spec.artifact, "artifact_ref", value)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    evidence.EvidenceStore(self.root).execution_writer().open_session(
                        spec,
                        evidence.WriteRequest(operation_id=_operation("unsafe-reference")),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED,
                )

    def test_typed_alias_fields_reject_private_and_payload_values_on_write(self) -> None:
        session_cases = (
            ("scenario-private-identity", lambda spec: object.__setattr__(
                spec, "scenario_id", "pokemon-red"
            )),
            ("scenario-private-hash", lambda spec: object.__setattr__(
                spec, "scenario_id", "a" * 64
            )),
            ("artifact-path", lambda spec: object.__setattr__(
                spec.artifact, "artifact_ref", "../private/rom.gba"
            )),
            ("corpus-log-payload", lambda spec: object.__setattr__(
                spec.fixtures, "corpus_ref", "log-entry"
            )),
            ("plan-screenshot-payload", lambda spec: object.__setattr__(
                spec.plan, "plan_ref", "screenshot"
            )),
            ("rules-credential", lambda spec: object.__setattr__(
                spec.rules, "rules_ref", "password-secret"
            )),
            ("platform-private-hash", lambda spec: object.__setattr__(
                spec.environment, "platform_version", "b" * 64
            )),
            ("target-private-identity", lambda spec: object.__setattr__(
                spec.environment, "target_ref", "pokemon-red"
            )),
            ("required-evidence-log", lambda spec: object.__setattr__(
                spec.review_requirements, "required_evidence_refs", ("log-entry",)
            )),
        )
        for case, mutate in session_cases:
            with self.subTest(case=case):
                spec = self._session_spec()
                mutate(spec)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    evidence.EvidenceStore(self.root).execution_writer().open_session(
                        spec,
                        evidence.WriteRequest(operation_id=_operation(f"invalid-{case}")),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED,
                )
                self.assertEqual(
                    list(self.root.glob("executions/*/record-*.json")),
                    [],
                )

        for operation_id in ("screenshot", "pokemon-red", "a" * 64):
            with self.subTest(operation_id=operation_id):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    evidence.EvidenceStore(self.root).execution_writer().open_session(
                        self._session_spec(),
                        evidence.WriteRequest(operation_id=operation_id),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED,
                )

        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("typed-alias-observation"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.AssertionObservation(
            assertion_ref=_alias("assertion", "synthetic"),
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            observed_at="2026-10-23T01:00:01Z",
            expected_outcome=evidence.AssertionOutcome.PASSED,
            actual_outcome=evidence.AssertionOutcome.PASSED,
            evidence_refs=(_alias("evidence", "synthetic"),),
            measurements=(
                evidence.Measurement(
                    name=_alias("measurement", "elapsed"),
                    value=250,
                    unit=evidence.MeasurementUnit.MILLISECONDS,
                ),
            ),
        )
        observation_cases = (
            ("evidence-screenshot", replace(
                observation, evidence_refs=("screenshot",)
            )),
            ("evidence-log", replace(observation, evidence_refs=("log-entry",))),
            ("assertion-private-identity", replace(
                observation, assertion_ref="pokemon-red"
            )),
            ("rules-credential", replace(observation, rules_ref="password-secret")),
            ("measurement-private-identity", replace(
                observation,
                measurements=(
                    evidence.Measurement(
                        name="pokemon-red",
                        value=250,
                        unit=evidence.MeasurementUnit.MILLISECONDS,
                    ),
                ),
            )),
        )
        for index, (case, mutated) in enumerate(observation_cases):
            with self.subTest(case=case):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.append_assertion(
                        "1" * 32,
                        mutated,
                        evidence.WriteRequest(
                            operation_id=_operation(f"invalid-observation-{index}"),
                            occurred_at="2026-10-23T01:00:02Z",
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED,
                )

    def test_hash_recomputed_session_aliases_are_revalidated_on_read(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("typed-alias-read-session"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000001.json"
        original = record_path.read_bytes()
        cases = {
            "private-scenario-identity": lambda event: event.__setitem__(
                "scenario_id", "pokemon-red"
            ),
            "private-scenario-hash": lambda event: event.__setitem__(
                "scenario_id", "a" * 64
            ),
            "artifact-path": lambda event: event["provenance"]["artifact"].__setitem__(
                "artifact_ref", "../private/rom.gba"
            ),
            "corpus-log-payload": lambda event: event["provenance"]["fixtures"].__setitem__(
                "corpus_ref", "log-entry"
            ),
            "plan-screenshot-payload": lambda event: event["provenance"]["plan"].__setitem__(
                "plan_ref", "screenshot"
            ),
            "rules-credential": lambda event: event["provenance"]["rules"].__setitem__(
                "rules_ref", "password-secret"
            ),
            "platform-private-hash": lambda event: event["provenance"]["environment"].__setitem__(
                "platform_version", "b" * 64
            ),
            "required-evidence-log": lambda event: event["provenance"][
                "review_requirements"
            ].__setitem__("required_evidence_refs", ["log-entry"]),
            "operation-payload-label": lambda event: event.__setitem__(
                "operation_id", "screenshot"
            ),
        }

        for case, mutate in cases.items():
            with self.subTest(case=case):
                record = json.loads(original)
                mutate(record["event"])
                self._rewrite_record(session_directory, 1, record)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)
            record_path.write_bytes(original)

    def test_hash_recomputed_observation_aliases_are_revalidated_on_read(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("typed-alias-read-open"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(
                    evidence.Measurement(
                        name=_alias("measurement", "elapsed"),
                        value=250,
                        unit=evidence.MeasurementUnit.MILLISECONDS,
                    ),
                ),
            ),
            evidence.WriteRequest(
                operation_id=_operation("typed-alias-read-assertion"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000002.json"
        original = record_path.read_bytes()
        cases = {
            "evidence-screenshot": lambda event: event.__setitem__(
                "evidence_refs", ["screenshot"]
            ),
            "evidence-log": lambda event: event.__setitem__(
                "evidence_refs", ["log-entry"]
            ),
            "assertion-private-identity": lambda event: event.__setitem__(
                "assertion_ref", "pokemon-red"
            ),
            "rules-credential": lambda event: event.__setitem__(
                "rules_ref", "password-secret"
            ),
            "measurement-private-identity": lambda event: event["measurements"][0].__setitem__(
                "name", "pokemon-red"
            ),
        }

        for case, mutate in cases.items():
            with self.subTest(case=case):
                record = json.loads(original)
                mutate(record["event"])
                self._rewrite_record(session_directory, 2, record)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)
            record_path.write_bytes(original)

    def test_nested_provenance_is_an_exact_allowlist(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000001.json"
        record = json.loads(record_path.read_bytes())
        record["event"]["provenance"]["artifact"]["arbitrary_log"] = "not-allowed"
        self._rewrite_record(session_directory, 1, record)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_append_retries_expected_heads_and_operation_identity_conflict(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.AssertionObservation(
            assertion_ref=_alias("assertion", "synthetic"),
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            observed_at="2026-10-23T01:00:01Z",
            expected_outcome=evidence.AssertionOutcome.PASSED,
            actual_outcome=evidence.AssertionOutcome.PASSED,
            evidence_refs=(_alias("evidence", "synthetic"),),
            measurements=(),
        )
        request = evidence.WriteRequest(
            operation_id=_operation("assertion-synthetic"),
            occurred_at="2026-10-23T01:00:02Z",
            expected_head_sha256=opened.head_sha256,
        )
        first = writer.append_assertion("1" * 32, observation, request)
        retry = writer.append_assertion(
            "1" * 32,
            observation,
            replace(request, occurred_at="2026-10-23T01:00:03Z"),
        )
        self.assertTrue(retry.idempotent)
        self.assertEqual(retry.record_sha256, first.record_sha256)
        self.assertEqual(writer.snapshot("1" * 32).record_count, 2)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_assertion(
                "1" * 32,
                observation,
                replace(request, operation_id=_operation("stale-head"), expected_head_sha256="f" * 64),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT,
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_assertion(
                "1" * 32,
                replace(observation, actual_outcome=evidence.AssertionOutcome.FAILED),
                request,
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.OPERATION_CONFLICT)

    def test_replayed_operation_returns_its_original_receipt_after_later_append(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-receipt-replay"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        observation = evidence.AssertionObservation(
            assertion_ref=_alias("assertion", "receipt-replay"),
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            observed_at="2026-10-23T01:00:01Z",
            expected_outcome=evidence.AssertionOutcome.PASSED,
            actual_outcome=evidence.AssertionOutcome.PASSED,
            evidence_refs=(_alias("evidence", "receipt-replay"),),
            measurements=(),
        )
        request_a = evidence.WriteRequest(
            operation_id=_operation("receipt-replay-a"),
            occurred_at="2026-10-23T01:00:02Z",
            expected_head_sha256=opened.head_sha256,
        )

        receipt_a = writer.append_assertion("1" * 32, observation, request_a)
        receipt_b = writer.append_lifecycle(
            "1" * 32,
            evidence.LifecycleObservation(
                lifecycle=evidence.Lifecycle.CLEANUP_STARTED,
                evidence_refs=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("receipt-replay-b"),
                occurred_at="2026-10-23T01:00:03Z",
                expected_head_sha256=receipt_a.head_sha256,
            ),
        )
        self.assertNotEqual(receipt_b.head_sha256, receipt_a.head_sha256)

        replay_a = writer.append_assertion("1" * 32, observation, request_a)

        self.assertTrue(replay_a.idempotent)
        self.assertEqual(replace(replay_a, idempotent=False), receipt_a)

    def test_append_refuses_an_active_cooperating_writer(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        lock_path = self.root / "executions" / ("1" * 32) / ".execution.lock"
        descriptor = os.open(lock_path, os.O_RDWR | os.O_NOFOLLOW)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.append_lifecycle(
                    "1" * 32,
                    evidence.LifecycleObservation(
                        lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                        evidence_refs=(),
                    ),
                    evidence.WriteRequest(
                        operation_id=_operation("busy-append"),
                        occurred_at="2026-10-23T01:00:01Z",
                        expected_head_sha256=opened.head_sha256,
                    ),
                )
        finally:
            os.close(descriptor)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.BUSY)
        self.assertEqual(writer.snapshot("1" * 32).record_count, 1)

    def test_recovery_rejects_conflicting_manifest_before_appending(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:01Z",
                evidence_refs=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        (session_directory / "record-00000002.json").unlink()
        before_names = sorted(path.name for path in session_directory.glob("record-*.json"))
        before_bytes = {
            name: (session_directory / name).read_bytes() for name in before_names
        }

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.recover("1" * 32, abandoned_before="2026-10-23T01:00:03Z")

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
        after_names = sorted(path.name for path in session_directory.glob("record-*.json"))
        after_bytes = {
            name: (session_directory / name).read_bytes() for name in after_names
        }
        self.assertEqual(after_names, before_names)
        self.assertEqual(after_bytes, before_bytes)

    def test_recovery_fails_before_interruption_when_manifest_is_unreadable(self) -> None:
        if os.geteuid() == 0:
            self.skipTest("permission denial is not observable for the root user")
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        manifest_path = session_directory / "manifest.json"
        manifest_path.write_bytes(b"not-readable")
        manifest_path.chmod(0o000)
        before_names = sorted(path.name for path in session_directory.glob("record-*.json"))
        before_bytes = {
            name: (session_directory / name).read_bytes() for name in before_names
        }

        try:
            with self.assertRaises(evidence.EvidenceError):
                writer.recover("1" * 32, abandoned_before="2026-10-23T01:00:01Z")
        finally:
            manifest_path.chmod(0o600)

        after_names = sorted(path.name for path in session_directory.glob("record-*.json"))
        after_bytes = {
            name: (session_directory / name).read_bytes() for name in after_names
        }
        self.assertEqual(after_names, before_names)
        self.assertEqual(after_bytes, before_bytes)

    def test_recovery_maps_manifest_read_io_failure_before_interruption(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        manifest_path = session_directory / "manifest.json"
        manifest_path.write_bytes(b"not-readable")
        manifest_path.chmod(0o600)
        before_names = sorted(path.name for path in session_directory.glob("record-*.json"))
        before_bytes = {
            name: (session_directory / name).read_bytes() for name in before_names
        }
        before_manifest_bytes = manifest_path.read_bytes()
        manifest_identity = (manifest_path.stat().st_dev, manifest_path.stat().st_ino)
        real_read = os.read

        def fail_manifest_read(descriptor: int, size: int) -> bytes:
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == manifest_identity:
                raise OSError(errno.EIO, "injected manifest read failure")
            return real_read(descriptor, size)

        with patch.object(_evidence_storage.os, "read", side_effect=fail_manifest_read):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.recover("1" * 32, abandoned_before="2026-10-23T01:00:01Z")

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)
        after_names = sorted(path.name for path in session_directory.glob("record-*.json"))
        after_bytes = {
            name: (session_directory / name).read_bytes() for name in after_names
        }
        self.assertEqual(after_names, before_names)
        self.assertEqual(after_bytes, before_bytes)
        self.assertEqual(manifest_path.read_bytes(), before_manifest_bytes)

    def test_caller_operation_ids_cannot_enter_the_internal_namespace(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.open_session(
                self._session_spec(),
                evidence.WriteRequest(operation_id="internal-recovery-interruption"),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertFalse(self.root.exists())

    def test_hash_recomputed_internal_operation_is_reserved_for_recovery(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("reserved-operation-read"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        record_path = session_directory / "record-00000001.json"
        original = record_path.read_bytes()

        try:
            record = json.loads(original)
            record["event"]["operation_id"] = "internal-" + "a" * 32
            self._rewrite_record(session_directory, 1, record)
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.snapshot("1" * 32)
            self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)
        finally:
            record_path.write_bytes(original)

    def test_recovery_never_resumes_interrupted_execution(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.recover(
            "1" * 32,
            abandoned_before="2026-10-23T01:00:00Z",
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_lifecycle(
                "1" * 32,
                evidence.LifecycleObservation(
                    lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                    evidence_refs=(),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("attempt-resume"),
                    occurred_at="2026-10-23T01:00:01Z",
                ),
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.FINALIZED)

    def test_manifest_mismatch_and_gapped_record_chain_are_rejected(self) -> None:
        for mode in ("manifest", "gap"):
            with self.subTest(mode=mode):
                with tempfile.TemporaryDirectory() as temporary_name:
                    root = Path(temporary_name) / "evidence"
                    writer = evidence.EvidenceStore(root).execution_writer()
                    opened = writer.open_session(
                        self._session_spec(),
                        evidence.WriteRequest(
                            operation_id=_operation("open-session-synthetic"),
                            occurred_at="2026-10-23T01:00:00Z",
                        ),
                    )
                    assertion = writer.append_lifecycle(
                        "1" * 32,
                        evidence.LifecycleObservation(
                            lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                            evidence_refs=(),
                        ),
                        evidence.WriteRequest(
                            operation_id=_operation("execution-started"),
                            occurred_at="2026-10-23T01:00:01Z",
                            expected_head_sha256=opened.head_sha256,
                        ),
                    )
                    writer.append_terminal(
                        "1" * 32,
                        evidence.TerminalObservation(
                            outcome=evidence.TerminalOutcome.COMPLETED,
                            reason=evidence.TerminalReason.PLAN_COMPLETE,
                            ended_at="2026-10-23T01:00:02Z",
                            evidence_refs=(),
                        ),
                        evidence.WriteRequest(
                            operation_id=_operation("terminal-synthetic"),
                            occurred_at="2026-10-23T01:00:03Z",
                            expected_head_sha256=assertion.head_sha256,
                        ),
                    )
                    session_directory = root / "executions" / ("1" * 32)
                    if mode == "gap":
                        (session_directory / "record-00000002.json").unlink()
                        with self.assertRaises(evidence.EvidenceError) as caught:
                            writer.verify_execution("1" * 32)
                        self.assertEqual(
                            caught.exception.code,
                            evidence.EvidenceErrorCode.CORRUPT,
                        )
                    else:
                        path = session_directory / "manifest.json"
                        document = json.loads(path.read_bytes())
                        document["record_count"] = 99
                        digest_document = dict(document)
                        digest_document.pop("manifest_sha256")
                        document["manifest_sha256"] = hashlib.sha256(
                            json.dumps(
                                digest_document,
                                ensure_ascii=False,
                                sort_keys=True,
                                separators=(",", ":"),
                            ).encode("utf-8")
                        ).hexdigest()
                        path.write_bytes(
                            json.dumps(
                                document,
                                ensure_ascii=False,
                                sort_keys=True,
                                separators=(",", ":"),
                            ).encode("utf-8")
                        )
                        with self.assertRaises(evidence.EvidenceError) as caught:
                            writer.verify_execution("1" * 32)
                        self.assertEqual(
                            caught.exception.code,
                            evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
                        )

    def test_oversized_record_is_rejected_before_content_read(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        record_path = (
            self.root
            / "executions"
            / ("1" * 32)
            / "record-00000001.json"
        )
        with record_path.open("ab") as stream:
            stream.write(b" " * (64 * 1024))
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)

    def test_assertion_rules_must_match_the_pinned_session(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_assertion(
                "1" * 32,
                evidence.AssertionObservation(
                    assertion_ref=_alias("assertion", "mismatch"),
                    rules_ref=_alias("rules", "other"),
                    rules_version="2.0.0",
                    rules_sha256="7" * 64,
                    observed_at="2026-10-23T01:00:01Z",
                    expected_outcome=evidence.AssertionOutcome.PASSED,
                    actual_outcome=evidence.AssertionOutcome.PASSED,
                    evidence_refs=(),
                    measurements=(),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("assertion-mismatch"),
                    occurred_at="2026-10-23T01:00:02Z",
                    expected_head_sha256=opened.head_sha256,
                ),
            )
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)

    def test_persisted_assertion_rules_must_still_match_the_pinned_session(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("assertion-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        path = session_directory / "record-00000002.json"
        document = json.loads(path.read_text())
        document["event"]["rules_version"] = "2.0.0"
        self._rewrite_record(session_directory, 2, document)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_enum_and_private_values_return_corrupt(self) -> None:
        for mode in ("enum", "private"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary_name:
                root = Path(temporary_name) / "evidence"
                writer = evidence.EvidenceStore(root).execution_writer()
                opened = writer.open_session(
                    self._session_spec(),
                    evidence.WriteRequest(
                        operation_id=_operation("open-session-synthetic"),
                        occurred_at="2026-10-23T01:00:00Z",
                    ),
                )
                writer.append_lifecycle(
                    "1" * 32,
                    evidence.LifecycleObservation(
                        lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                        evidence_refs=(_alias("evidence", "synthetic"),),
                    ),
                    evidence.WriteRequest(
                        operation_id=_operation("execution-started-synthetic"),
                        occurred_at="2026-10-23T01:00:01Z",
                        expected_head_sha256=opened.head_sha256,
                    ),
                )
                session_directory = root / "executions" / ("1" * 32)
                path = session_directory / "record-00000002.json"
                document = json.loads(path.read_text())
                if mode == "enum":
                    document["event"]["lifecycle"] = []
                else:
                    document["event"]["evidence_refs"] = ["token"]
                self._rewrite_record(session_directory, 2, document)

                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_stream_lock_symlink_is_rejected_as_unsafe(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        lock_path = session_directory / ".execution.lock"
        target = session_directory / "lock-target"
        target.write_bytes(b"not-a-lock")
        os.chmod(target, 0o600)
        lock_path.unlink()
        lock_path.symlink_to(target)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_lifecycle(
                "1" * 32,
                evidence.LifecycleObservation(
                    lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                    evidence_refs=(),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("after-lock-symlink"),
                    occurred_at="2026-10-23T01:00:01Z",
                    expected_head_sha256=opened.head_sha256,
                ),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_stream_lock_rejects_changed_entry_identity(self) -> None:
        directory = self.root / "lock-identity"
        _evidence_storage._ensure_private_directory(
            directory,
            create=True,
            root=self.root,
        )
        real_stat = os.stat

        def changed_lock_identity(
            path: object,
            *args: object,
            **kwargs: object,
        ) -> object:
            result = real_stat(path, *args, **kwargs)  # type: ignore[arg-type]
            if path == ".identity.lock" and kwargs.get("dir_fd") is not None:
                return SimpleNamespace(
                    st_mode=result.st_mode,
                    st_uid=result.st_uid,
                    st_dev=result.st_dev,
                    st_ino=result.st_ino + 1,
                    st_nlink=result.st_nlink,
                )
            return result

        with patch.object(
            _evidence_storage.os,
            "stat",
            side_effect=changed_lock_identity,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                with _evidence_storage._stream_lock(
                    directory,
                    root=self.root,
                    lock_name=".identity.lock",
                ):
                    self.fail("changed lock identity must not acquire the lock")
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_publish_no_replace_maps_idempotent_publication_faults(self) -> None:
        real_stat = os.stat
        cases = (
            (
                "zero-write",
                lambda: patch.object(_evidence_storage.os, "write", return_value=0),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "temporary-stat",
                lambda temporary_name: patch.object(
                    _evidence_storage.os,
                    "stat",
                    side_effect=lambda path, *args, **kwargs: _raise_for_name(
                        path,
                        temporary_name,
                        *args,
                        **kwargs,
                    ),
                ),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "temporary-identity",
                lambda temporary_name: patch.object(
                    _evidence_storage.os,
                    "stat",
                    side_effect=lambda path, *args, **kwargs: _change_for_name(
                        path,
                        temporary_name,
                        *args,
                        **kwargs,
                    ),
                ),
                evidence.EvidenceErrorCode.UNSAFE_PATH,
            ),
            (
                "rename",
                lambda: patch.object(
                    _evidence_storage,
                    "_rename_entry_no_replace",
                    side_effect=OSError(errno.EIO, "publish"),
                ),
                evidence.EvidenceErrorCode.UNAVAILABLE,
            ),
            (
                "published-identity",
                lambda final_name: patch.object(
                    _evidence_storage.os,
                    "stat",
                    side_effect=lambda path, *args, **kwargs: _change_for_name(
                        path,
                        final_name,
                        *args,
                        **kwargs,
                    ),
                ),
                evidence.EvidenceErrorCode.UNSAFE_PATH,
            ),
        )

        def _raise_for_name(
            path: object,
            target: str,
            *args: object,
            **kwargs: object,
        ) -> object:
            if path == target and kwargs.get("dir_fd") is not None:
                raise OSError(errno.EIO, "publish")
            return real_stat(path, *args, **kwargs)  # type: ignore[arg-type]

        def _change_for_name(
            path: object,
            target: str,
            *args: object,
            **kwargs: object,
        ) -> object:
            result = real_stat(path, *args, **kwargs)  # type: ignore[arg-type]
            if path == target and kwargs.get("dir_fd") is not None:
                return SimpleNamespace(
                    st_mode=result.st_mode,
                    st_dev=result.st_dev,
                    st_ino=result.st_ino + 1,
                )
            return result

        for index, (case, fault_factory, expected) in enumerate(cases):
            with self.subTest(case=case):
                directory = self.root / f"publish-{index}"
                _evidence_storage._ensure_private_directory(
                    directory,
                    create=True,
                    root=self.root,
                )
                temporary_name = ".record.tmp"
                final_name = "record.json"
                target = temporary_name if "temporary" in case else final_name
                fault = fault_factory(target) if case != "zero-write" and case != "rename" else fault_factory()
                with fault:
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        _evidence_storage._publish_no_replace(
                            directory,
                            temporary_name,
                            final_name,
                            b"{}",
                            root=self.root,
                        )
                self.assertEqual(caught.exception.code, expected)

    def test_no_replace_rename_maps_platform_and_syscall_failures(self) -> None:
        with patch.object(_evidence_storage.sys, "platform", "unsupported"):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._rename_entry_no_replace(-1, "source", "target")
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with (
            patch.object(_evidence_storage.sys, "platform", "darwin"),
            patch.object(_evidence_storage.ctypes, "CDLL", return_value=object()),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._rename_entry_no_replace(-1, "source", "target")
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        def fail_rename(*args: object) -> int:
            _evidence_storage.ctypes.set_errno(errno.EIO)
            return -1

        with (
            patch.object(_evidence_storage.sys, "platform", "darwin"),
            patch.object(
                _evidence_storage.ctypes,
                "CDLL",
                return_value=SimpleNamespace(renameatx_np=fail_rename),
            ),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._rename_entry_no_replace(-1, "source", "target")
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        calls: list[tuple[object, ...]] = []

        def succeed_rename(*args: object) -> int:
            calls.append(args)
            return 0

        with (
            patch.object(_evidence_storage.sys, "platform", "linux"),
            patch.object(
                _evidence_storage.ctypes,
                "CDLL",
                return_value=SimpleNamespace(renameat2=succeed_rename),
            ),
        ):
            _evidence_storage._rename_entry_no_replace(-1, "source", "target")
        self.assertEqual(calls[0][-1], 1)

    def test_lost_record_acknowledgement_never_duplicates_observation(self) -> None:
        for stage in ("after_publish_before_parent_sync", "after_parent_sync"):
            with self.subTest(stage=stage):
                with tempfile.TemporaryDirectory() as temporary_name:
                    root = Path(temporary_name) / "evidence"
                    writer = evidence.EvidenceStore(root).execution_writer()
                    opened = writer.open_session(
                        self._session_spec(),
                        evidence.WriteRequest(
                            operation_id=_operation("open-session-synthetic"),
                            occurred_at="2026-10-23T01:00:00Z",
                        ),
                    )
                    observation = evidence.AssertionObservation(
                        assertion_ref=_alias("assertion", "synthetic"),
                        rules_ref=_alias("rules", "synthetic"),
                        rules_version="1.0.0",
                        rules_sha256="6" * 64,
                        observed_at="2026-10-23T01:00:01Z",
                        expected_outcome=evidence.AssertionOutcome.PASSED,
                        actual_outcome=evidence.AssertionOutcome.PASSED,
                        evidence_refs=(_alias("evidence", "synthetic"),),
                        measurements=(),
                    )
                    request = evidence.WriteRequest(
                        operation_id=_operation("assertion-synthetic"),
                        occurred_at="2026-10-23T01:00:02Z",
                        expected_head_sha256=opened.head_sha256,
                    )

                    def crash(current: str) -> None:
                        if current == stage:
                            raise _PublicationCrash

                    with patch.object(
                        _evidence_storage,
                        "_transition",
                        side_effect=crash,
                    ):
                        with self.assertRaises(_PublicationCrash):
                            writer.append_assertion("1" * 32, observation, request)

                    retry = writer.append_assertion("1" * 32, observation, request)
                    self.assertTrue(retry.idempotent)
                    self.assertEqual(writer.snapshot("1" * 32).record_count, 2)

    def test_lost_ack_retries_complete_required_parent_syncs(self) -> None:
        spec = self._session_spec()

        def crash_at(target: str):
            def crash(stage: str) -> None:
                if stage == target:
                    raise _PublicationCrash

            return patch.object(_evidence_storage, "_transition", side_effect=crash)

        with self.subTest(lost_ack="session"):
            with tempfile.TemporaryDirectory() as temporary_name:
                root = Path(temporary_name) / "evidence"
                writer = evidence.EvidenceStore(root).execution_writer()
                request = evidence.WriteRequest(
                    operation_id=_operation("open-session-synthetic"),
                    occurred_at="2026-10-23T01:00:00Z",
                )
                with crash_at("after_publish_before_parent_sync"):
                    with self.assertRaises(_PublicationCrash):
                        writer.open_session(spec, request)
                session_directory = root / "executions" / ("1" * 32)
                with self._failing_directory_sync(session_directory):
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        writer.open_session(spec, request)
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with self.subTest(lost_ack="record"):
            with tempfile.TemporaryDirectory() as temporary_name:
                root = Path(temporary_name) / "evidence"
                writer = evidence.EvidenceStore(root).execution_writer()
                opened = writer.open_session(
                    spec,
                    evidence.WriteRequest(
                        operation_id=_operation("open-session-synthetic"),
                        occurred_at="2026-10-23T01:00:00Z",
                    ),
                )
                observation = evidence.AssertionObservation(
                    assertion_ref=_alias("assertion", "synthetic"),
                    rules_ref=_alias("rules", "synthetic"),
                    rules_version="1.0.0",
                    rules_sha256="6" * 64,
                    observed_at="2026-10-23T01:00:01Z",
                    expected_outcome=evidence.AssertionOutcome.PASSED,
                    actual_outcome=evidence.AssertionOutcome.PASSED,
                    evidence_refs=(_alias("evidence", "synthetic"),),
                    measurements=(),
                )
                request = evidence.WriteRequest(
                    operation_id=_operation("assertion-synthetic"),
                    occurred_at="2026-10-23T01:00:02Z",
                    expected_head_sha256=opened.head_sha256,
                )
                with crash_at("after_publish_before_parent_sync"):
                    with self.assertRaises(_PublicationCrash):
                        writer.append_assertion("1" * 32, observation, request)
                session_directory = root / "executions" / ("1" * 32)
                with self._failing_directory_sync(session_directory):
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        writer.append_assertion("1" * 32, observation, request)
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

        with self.subTest(lost_ack="manifest"):
            with tempfile.TemporaryDirectory() as temporary_name:
                root = Path(temporary_name) / "evidence"
                writer = evidence.EvidenceStore(root).execution_writer()
                opened = writer.open_session(
                    spec,
                    evidence.WriteRequest(
                        operation_id=_operation("open-session-synthetic"),
                        occurred_at="2026-10-23T01:00:00Z",
                    ),
                )
                with crash_at("manifest_after_publish_before_parent_sync"):
                    with self.assertRaises(_PublicationCrash):
                        writer.append_terminal(
                            "1" * 32,
                            evidence.TerminalObservation(
                                outcome=evidence.TerminalOutcome.COMPLETED,
                                reason=evidence.TerminalReason.PLAN_COMPLETE,
                                ended_at="2026-10-23T01:00:01Z",
                                evidence_refs=(),
                            ),
                            evidence.WriteRequest(
                                operation_id=_operation("terminal-synthetic"),
                                occurred_at="2026-10-23T01:00:02Z",
                                expected_head_sha256=opened.head_sha256,
                            ),
                        )
                session_directory = root / "executions" / ("1" * 32)
                with self._failing_directory_sync(session_directory):
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        writer.recover("1" * 32)
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_terminal_record_precedes_manifest_and_recovery_handles_each_manifest_fault(self) -> None:
        stage_names = (
            "manifest_before_publication",
            "manifest_after_temp_sync",
            "manifest_before_publish",
            "manifest_after_publish_before_parent_sync",
            "manifest_after_parent_sync",
            "manifest_before_ack",
        )
        for stage in stage_names:
            with self.subTest(stage=stage):
                with tempfile.TemporaryDirectory() as temporary_name:
                    root = Path(temporary_name) / "evidence"
                    writer = evidence.EvidenceStore(root).execution_writer()
                    opened = writer.open_session(
                        self._session_spec(),
                        evidence.WriteRequest(
                            operation_id=_operation("open-session-synthetic"),
                            occurred_at="2026-10-23T01:00:00Z",
                        ),
                    )

                    def crash(current: str) -> None:
                        if current == stage:
                            raise _PublicationCrash

                    with patch.object(
                        _evidence_storage,
                        "_transition",
                        side_effect=crash,
                    ):
                        with self.assertRaises(_PublicationCrash):
                            writer.append_terminal(
                                "1" * 32,
                                evidence.TerminalObservation(
                                    outcome=evidence.TerminalOutcome.COMPLETED,
                                    reason=evidence.TerminalReason.PLAN_COMPLETE,
                                    ended_at="2026-10-23T01:00:01Z",
                                    evidence_refs=(),
                                ),
                                evidence.WriteRequest(
                                    operation_id=_operation("terminal-synthetic"),
                                    occurred_at="2026-10-23T01:00:02Z",
                                    expected_head_sha256=opened.head_sha256,
                                ),
                            )

                    recovered = writer.recover("1" * 32)
                    self.assertEqual(recovered.state, evidence.RecoveryState.FINALIZED)
                    self.assertEqual(writer.verify_execution("1" * 32).record_count, 2)

    def test_final_no_replace_publication_is_the_conflict_authority(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        final_path = session_directory / "record-00000002.json"
        sentinel = b"existing-entry-must-not-be-replaced"

        def publish_competitor(stage: str) -> None:
            if stage == "before_publish":
                final_path.write_bytes(sentinel)
                os.chmod(final_path, 0o600)

        with patch.object(
            _evidence_storage,
            "_transition",
            side_effect=publish_competitor,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.append_lifecycle(
                    "1" * 32,
                    evidence.LifecycleObservation(
                        lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                        evidence_refs=(),
                    ),
                    evidence.WriteRequest(
                        operation_id=_operation("raced-publication"),
                        occurred_at="2026-10-23T01:00:01Z",
                        expected_head_sha256=opened.head_sha256,
                    ),
                )

        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT,
        )
        self.assertEqual(final_path.read_bytes(), sentinel)
        self.assertEqual(len(list(session_directory.glob(".record-00000002.tmp-*"))), 1)

    def test_unknown_execution_directory_entry_fails_closed(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        (session_directory / "unexpected-entry").write_text("unsafe", encoding="utf-8")

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)

    def test_open_session_rejects_every_malformed_spec_component(self) -> None:
        base = self._session_spec()
        cases = (
            ("spec", object()),
            ("artifact", replace(base, artifact=object())),
            (
                "artifact-class",
                replace(
                    base,
                    artifact=replace(base.artifact, artifact_class="variant"),
                ),
            ),
            ("authorization", replace(base, authorization=object())),
            ("fixtures", replace(base, fixtures=object())),
            ("plan", replace(base, plan=object())),
            ("rules-type", replace(base, rules=object())),
            ("environment-type", replace(base, environment=object())),
            (
                "platform",
                replace(
                    base,
                    environment=replace(base.environment, platform="android"),
                ),
            ),
            (
                "review-requirements",
                replace(base, review_requirements=object()),
            ),
            (
                "required-refs-container",
                replace(
                    base,
                    review_requirements=replace(
                        base.review_requirements,
                        required_evidence_refs=[
                            _alias("evidence", "synthetic")
                        ],
                    ),
                ),
            ),
            (
                "required-refs-duplicate",
                replace(
                    base,
                    review_requirements=replace(
                        base.review_requirements,
                        required_evidence_refs=(
                            _alias("evidence", "synthetic"),
                            _alias("evidence", "synthetic"),
                        ),
                    ),
                ),
            ),
            (
                "review-flag",
                replace(
                    base,
                    review_requirements=replace(
                        base.review_requirements,
                        objective_review_allowed=1,
                    ),
                ),
            ),
            ("session-id", replace(base, session_id="short")),
            (
                "rules-version",
                replace(base, rules=replace(base.rules, rules_version="v1")),
            ),
            (
                "manifest-version",
                replace(
                    base,
                    authorization=replace(
                        base.authorization, manifest_version=0
                    ),
                ),
            ),
        )
        for case, spec in cases:
            with self.subTest(case=case):
                with tempfile.TemporaryDirectory() as temporary_name:
                    writer = evidence.EvidenceStore(
                        Path(temporary_name) / "evidence"
                    ).execution_writer()
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        writer.open_session(
                            spec,
                            evidence.WriteRequest(
                                operation_id=_operation(f"invalid-spec-{case}"),
                                occurred_at="2026-10-23T01:00:00Z",
                            ),
                        )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )

    def test_append_methods_reject_malformed_observations_and_aliases(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-observation-validation"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        measurement = evidence.Measurement(
            name=_alias("measurement", "synthetic"),
            value=1,
            unit=evidence.MeasurementUnit.MILLISECONDS,
        )
        assertion = evidence.AssertionObservation(
            assertion_ref=_alias("assertion", "synthetic"),
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            observed_at="2026-10-23T01:00:01Z",
            expected_outcome=evidence.AssertionOutcome.PASSED,
            actual_outcome=evidence.AssertionOutcome.PASSED,
            evidence_refs=(_alias("evidence", "synthetic"),),
            measurements=(measurement,),
        )
        evidence_ref = _alias("evidence", "synthetic")
        assertion_cases = (
            ("observation", object()),
            (
                "expected-outcome",
                replace(assertion, expected_outcome="passed"),
            ),
            ("actual-outcome", replace(assertion, actual_outcome="passed")),
            ("evidence-container", replace(assertion, evidence_refs=[evidence_ref])),
            (
                "evidence-duplicate",
                replace(assertion, evidence_refs=(evidence_ref, evidence_ref)),
            ),
            ("measurement-container", replace(assertion, measurements=[])),
            ("measurement-item", replace(assertion, measurements=(object(),))),
            (
                "measurement-duplicate",
                replace(assertion, measurements=(measurement, measurement)),
            ),
            (
                "measurement-rule",
                replace(
                    assertion,
                    measurements=(replace(measurement, unit="milliseconds"),),
                ),
            ),
            (
                "measurement-value",
                replace(
                    assertion,
                    measurements=(replace(measurement, value=True),),
                ),
            ),
            (
                "measurement-range",
                replace(
                    assertion,
                    measurements=(replace(measurement, value=10**15 + 1),),
                ),
            ),
        )
        for case, observation in assertion_cases:
            with self.subTest(append="assertion", case=case):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.append_assertion(
                        "1" * 32,
                        observation,
                        evidence.WriteRequest(
                            operation_id=_operation(
                                f"invalid-assertion-{case}"
                            ),
                            occurred_at="2026-10-23T01:00:02Z",
                            expected_head_sha256=opened.head_sha256,
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )

        lifecycle = evidence.LifecycleObservation(
            lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
            evidence_refs=(evidence_ref,),
        )
        lifecycle_cases = (
            ("observation", object()),
            (
                "lifecycle",
                replace(lifecycle, lifecycle="execution_started"),
            ),
            ("evidence-container", replace(lifecycle, evidence_refs=[evidence_ref])),
            (
                "evidence-duplicate",
                replace(lifecycle, evidence_refs=(evidence_ref, evidence_ref)),
            ),
        )
        for case, observation in lifecycle_cases:
            with self.subTest(append="lifecycle", case=case):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.append_lifecycle(
                        "1" * 32,
                        observation,
                        evidence.WriteRequest(
                            operation_id=_operation(
                                f"invalid-lifecycle-{case}"
                            ),
                            occurred_at="2026-10-23T01:00:02Z",
                            expected_head_sha256=opened.head_sha256,
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )

        terminal = evidence.TerminalObservation(
            outcome=evidence.TerminalOutcome.COMPLETED,
            reason=evidence.TerminalReason.PLAN_COMPLETE,
            ended_at="2026-10-23T01:00:02Z",
            evidence_refs=(evidence_ref,),
        )
        terminal_cases = (
            ("request", terminal, None),
            ("observation", object(), terminal),
            ("outcome", replace(terminal, outcome="completed"), terminal),
            ("reason", replace(terminal, reason="plan_complete"), terminal),
            (
                "ended-after-occurrence",
                replace(terminal, ended_at="2026-10-23T01:00:03Z"),
                terminal,
            ),
        )
        for case, observation, request in terminal_cases:
            with self.subTest(append="terminal", case=case):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.append_terminal(
                        "1" * 32,
                        observation,
                        request
                        if request is None
                        else evidence.WriteRequest(
                            operation_id=_operation(
                                f"invalid-terminal-{case}"
                            ),
                            occurred_at="2026-10-23T01:00:02Z",
                            expected_head_sha256=opened.head_sha256,
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )
        self.assertEqual(writer.snapshot("1" * 32).record_count, 1)

    def test_persisted_provenance_rejects_each_nested_shape_fault(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-provenance-corruption"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        path = session_directory / "record-00000001.json"
        original = path.read_bytes()
        cases = {
            "provenance": lambda event: event.__setitem__("provenance", []),
            "authorization": lambda event: event["provenance"].__setitem__(
                "authorization", []
            ),
            "fixtures": lambda event: event["provenance"].__setitem__(
                "fixtures", []
            ),
            "plan": lambda event: event["provenance"].__setitem__("plan", []),
            "rules": lambda event: event["provenance"].__setitem__("rules", []),
            "environment": lambda event: event["provenance"].__setitem__(
                "environment", []
            ),
            "requirements": lambda event: event["provenance"].__setitem__(
                "review_requirements", []
            ),
            "review-flag": lambda event: event["provenance"][
                "review_requirements"
            ].__setitem__("objective_review_allowed", 1),
            "required-container": lambda event: event["provenance"][
                "review_requirements"
            ].__setitem__("required_evidence_refs", {}),
            "required-duplicate": lambda event: event["provenance"][
                "review_requirements"
            ].__setitem__(
                "required_evidence_refs",
                [
                    _alias("evidence", "synthetic"),
                    _alias("evidence", "synthetic"),
                ],
            ),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                record = json.loads(original)
                mutate(record["event"])
                self._rewrite_record(session_directory, 1, record)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.CORRUPT,
                )
                path.write_bytes(original)
                path.chmod(0o600)

    def test_persisted_assertion_rejects_event_and_chain_corruption(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-persisted-assertion"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        measurement = evidence.Measurement(
            name=_alias("measurement", "synthetic"),
            value=1,
            unit=evidence.MeasurementUnit.MILLISECONDS,
        )
        writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(measurement,),
            ),
            evidence.WriteRequest(
                operation_id=_operation("assertion-persisted"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        first_path = session_directory / "record-00000001.json"
        second_path = session_directory / "record-00000002.json"
        first = json.loads(first_path.read_text())
        original = json.loads(second_path.read_text())
        first_operation = first["event"]["operation_id"]
        evidence_ref = _alias("evidence", "synthetic")
        measurement_document = {
            "name": measurement.name,
            "unit": measurement.unit.value,
            "value": measurement.value,
        }
        cases = {
            "unknown-event": lambda event: event.__setitem__(
                "event_type", "unknown"
            ),
            "evidence-container": lambda event: event.__setitem__(
                "evidence_refs", {}
            ),
            "evidence-duplicate": lambda event: event.__setitem__(
                "evidence_refs", [evidence_ref, evidence_ref]
            ),
            "measurement-container": lambda event: event.__setitem__(
                "measurements", {}
            ),
            "measurement-item": lambda event: event.__setitem__(
                "measurements", [1]
            ),
            "measurement-shape": lambda event: event.__setitem__(
                "measurements", [{"name": measurement.name}]
            ),
            "measurement-duplicate": lambda event: event.__setitem__(
                "measurements",
                [measurement_document, measurement_document],
            ),
            "measurement-value": lambda event: event["measurements"][0].__setitem__(
                "value", True
            ),
            "operation-duplicate": lambda event: event.__setitem__(
                "operation_id", first_operation
            ),
            "occurrence-regression": lambda event: event.__setitem__(
                "occurred_at", "2026-10-22T01:00:02Z"
            ),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                record = json.loads(
                    _evidence_storage._canonical_bytes(original)
                )
                mutate(record["event"])
                self._rewrite_record(session_directory, 2, record)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.CORRUPT,
                )
                second_path.write_bytes(_evidence_storage._canonical_bytes(original))
                second_path.chmod(0o600)

        record = json.loads(_evidence_storage._canonical_bytes(original))
        record["previous_record_sha256"] = "0" * 64
        self._rewrite_record(session_directory, 2, record)
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.CORRUPT,
        )

    def test_persisted_terminal_rejects_timestamp_and_recovery_marker_faults(
        self,
    ) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-terminal-corruption"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:01Z",
                evidence_refs=(_alias("evidence", "synthetic"),),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-corruption"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        path = session_directory / "record-00000002.json"
        original = json.loads(path.read_bytes())
        cases = {
            "ended-after-occurrence": lambda event: event.__setitem__(
                "ended_at", "2026-10-23T01:00:03Z"
            ),
            "evidence-container": lambda event: event.__setitem__(
                "evidence_refs", {}
            ),
            "recovery-marker": lambda event: event.__setitem__(
                "operation_id", _evidence_storage._RECOVERY_OPERATION_ID
            ),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                record = json.loads(
                    _evidence_storage._canonical_bytes(original)
                )
                mutate(record["event"])
                self._rewrite_record(session_directory, 2, record)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.CORRUPT,
                )
                path.write_bytes(_evidence_storage._canonical_bytes(original))
                path.chmod(0o600)

    def test_manifest_parser_maps_json_shape_and_digest_faults(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        self._finalize_session(writer)
        session_directory = self.root / "executions" / ("1" * 32)
        path = session_directory / "manifest.json"
        original = path.read_bytes()
        original_document = json.loads(original)

        def canonical_document(mutator) -> bytes:
            document = json.loads(
                _evidence_storage._canonical_bytes(original_document)
            )
            mutator(document)
            digest_document = dict(document)
            digest_document.pop("manifest_sha256", None)
            document["manifest_sha256"] = _evidence_storage._canonical_sha256(
                digest_document
            )
            return _evidence_storage._canonical_bytes(document)

        digest_type = json.loads(
            _evidence_storage._canonical_bytes(original_document)
        )
        digest_type["manifest_sha256"] = 1
        digest_value = json.loads(
            _evidence_storage._canonical_bytes(original_document)
        )
        digest_value["manifest_sha256"] = "0" * 64

        cases = (
            (
                "duplicate-key",
                original.replace(
                    b'{"head_sha256":',
                    b'{"schema_version":1,"head_sha256":',
                    1,
                ),
                evidence.EvidenceErrorCode.DUPLICATE_KEY,
            ),
            (
                "float",
                original.replace(b'"record_count":2', b'"record_count":2.0', 1),
                evidence.EvidenceErrorCode.FLOAT_REJECTED,
            ),
            (
                "non-finite",
                original.replace(b'"record_count":2', b'"record_count":NaN', 1),
                evidence.EvidenceErrorCode.NON_FINITE_NUMBER,
            ),
            (
                "malformed",
                b"{",
                evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
            ),
            (
                "noncanonical",
                json.dumps(original_document, indent=2).encode("utf-8"),
                evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
            ),
            (
                "extra-key",
                canonical_document(lambda document: document.__setitem__("extra", True)),
                evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
            ),
            (
                "unsupported-schema",
                canonical_document(
                    lambda document: document.__setitem__(
                        "schema_version", _evidence_storage.SCHEMA_VERSION + 1
                    )
                ),
                evidence.EvidenceErrorCode.UNSUPPORTED_SCHEMA,
            ),
            (
                "record-count-type",
                canonical_document(
                    lambda document: document.__setitem__("record_count", True)
                ),
                evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
            ),
            (
                "digest-type",
                _evidence_storage._canonical_bytes(digest_type),
                evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
            ),
            (
                "digest-value",
                _evidence_storage._canonical_bytes(digest_value),
                evidence.EvidenceErrorCode.MANIFEST_MISMATCH,
            ),
        )
        for case, raw, expected in cases:
            with self.subTest(case=case):
                path.write_bytes(raw)
                path.chmod(0o600)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.verify_execution("1" * 32)
                self.assertEqual(caught.exception.code, expected)
                path.write_bytes(original)
                path.chmod(0o600)

    def test_session_open_replay_and_publication_conflicts(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        spec = self._session_spec()
        request = evidence.WriteRequest(
            operation_id=_operation("open-session-replay"),
            occurred_at="2026-10-23T01:00:00Z",
        )
        opened = writer.open_session(spec, request)
        replayed = writer.open_session(spec, request)
        self.assertTrue(replayed.idempotent)
        self.assertEqual(replayed.record_sha256, opened.record_sha256)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.open_session(
                replace(spec, scenario_id=_alias("scenario", "other")),
                replace(request, operation_id=_operation("open-session-conflict")),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.OPERATION_CONFLICT,
        )

        with tempfile.TemporaryDirectory() as temporary_name:
            raced_writer = evidence.EvidenceStore(
                Path(temporary_name) / "evidence"
            ).execution_writer()
            with patch.object(
                _evidence_storage,
                "_publish_no_replace",
                side_effect=FileExistsError,
            ):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    raced_writer.open_session(
                        spec,
                        replace(
                            request,
                            operation_id=_operation("open-session-raced"),
                        ),
                    )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT,
        )

    def test_session_open_replay_after_later_append_returns_original_receipt(
        self,
    ) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        spec = self._session_spec()
        request = evidence.WriteRequest(
            operation_id=_operation("open-session-replay-after-append"),
            occurred_at="2026-10-23T01:00:00Z",
        )
        opened = writer.open_session(spec, request)
        appended = writer.append_lifecycle(
            "1" * 32,
            evidence.LifecycleObservation(
                lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                evidence_refs=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("execution-started-after-open-replay"),
                occurred_at="2026-10-23T01:00:01Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        self.assertNotEqual(appended.head_sha256, opened.head_sha256)

        replayed = writer.open_session(spec, request)

        self.assertTrue(replayed.idempotent)
        self.assertEqual(replace(replayed, idempotent=False), opened)

    def test_session_open_retry_rejects_later_record_with_broken_backlink(
        self,
    ) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        spec = self._session_spec()
        request = evidence.WriteRequest(
            operation_id=_operation("open-session-corrupt-later-record"),
            occurred_at="2026-10-23T01:00:00Z",
        )
        opened = writer.open_session(spec, request)
        writer.append_lifecycle(
            "1" * 32,
            evidence.LifecycleObservation(
                lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                evidence_refs=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("execution-started-before-corruption"),
                occurred_at="2026-10-23T01:00:01Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        second = json.loads((session_directory / "record-00000002.json").read_bytes())
        second["previous_record_sha256"] = "0" * 64
        self._rewrite_record(session_directory, 2, second)

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.open_session(spec, request)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_manifest_finalization_accepts_competing_winner(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-manifest-race"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        real_publish = _evidence_storage._publish_no_replace

        def publish_competitor(
            directory: Path,
            temporary_name: str,
            final_name: str,
            content: bytes,
            **kwargs: object,
        ) -> None:
            if final_name == "manifest.json":
                final_path = directory / final_name
                final_path.write_bytes(content)
                final_path.chmod(0o600)
                raise FileExistsError
            real_publish(
                directory,
                temporary_name,
                final_name,
                content,
                **kwargs,
            )

        with patch.object(
            _evidence_storage,
            "_publish_no_replace",
            side_effect=publish_competitor,
        ):
            receipt = writer.append_terminal(
                "1" * 32,
                evidence.TerminalObservation(
                    outcome=evidence.TerminalOutcome.COMPLETED,
                    reason=evidence.TerminalReason.PLAN_COMPLETE,
                    ended_at="2026-10-23T01:00:01Z",
                    evidence_refs=(_alias("evidence", "synthetic"),),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("terminal-manifest-race"),
                    occurred_at="2026-10-23T01:00:02Z",
                    expected_head_sha256=opened.head_sha256,
                ),
            )
        self.assertEqual(receipt.sequence, 2)
        self.assertIsNotNone(writer.verify_execution("1" * 32))

    def test_descriptor_error_paths_close_opened_descriptors(self) -> None:
        target = self.root / "canonical"
        target.mkdir(parents=True)
        child = target / "child"
        child.mkdir(mode=0o700)
        real_stat = _evidence_storage.os.stat
        real_close = _evidence_storage.os.close
        closed: list[int] = []

        def fail_named_stat(path: object, *args: object, **kwargs: object):
            if path == "canonical" and kwargs.get("dir_fd") is not None:
                raise OSError(errno.EIO, "canonical")
            return real_stat(path, *args, **kwargs)

        def record_close(descriptor: int) -> None:
            closed.append(descriptor)
            real_close(descriptor)

        with patch.object(
            _evidence_storage.os,
            "stat",
            side_effect=fail_named_stat,
        ), patch.object(
            _evidence_storage.os,
            "close",
            side_effect=record_close,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                _evidence_storage._open_canonical_directory(target)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH)
        self.assertGreaterEqual(len(closed), 2)

        parent = _evidence_storage._open_canonical_directory(target)
        try:
            closed.clear()
            with patch.object(
                _evidence_storage.os,
                "fstat",
                side_effect=OSError(errno.EIO, "private child"),
            ), patch.object(
                _evidence_storage.os,
                "close",
                side_effect=record_close,
            ):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    _evidence_storage._open_private_child(parent, child.name)
            self.assertEqual(
                caught.exception.code,
                evidence.EvidenceErrorCode.UNSAFE_PATH,
            )
            self.assertEqual(len(closed), 1)
        finally:
            real_close(parent)

    def test_missing_root_ancestor_faults_map_to_stable_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_name:
            base = Path(temporary_name)
            regular = base / "regular"
            regular.write_text("not a directory", encoding="utf-8")
            real_lstat = Path.lstat

            def non_directory_ancestor(path: Path):
                if path == base / "missing" / "child":
                    raise FileNotFoundError(path)
                if path == base / "missing":
                    return real_lstat(regular)
                return real_lstat(path)

            with patch.object(
                Path,
                "lstat",
                autospec=True,
                side_effect=non_directory_ancestor,
            ):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    _evidence_storage._ensure_private_directory(
                        base / "missing" / "child",
                        create=True,
                        root=base / "missing" / "child",
                    )
            self.assertEqual(
                caught.exception.code,
                evidence.EvidenceErrorCode.UNAVAILABLE,
            )

            io_target = base / "other" / "child"

            def inaccessible_ancestor(path: Path):
                if path == io_target:
                    raise FileNotFoundError(path)
                if path == io_target.parent:
                    raise OSError(errno.EIO, "ancestor")
                return real_lstat(path)

            with patch.object(
                Path,
                "lstat",
                autospec=True,
                side_effect=inaccessible_ancestor,
            ):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    _evidence_storage._ensure_private_directory(
                        io_target,
                        create=True,
                        root=io_target,
                    )
            self.assertEqual(
                caught.exception.code,
                evidence.EvidenceErrorCode.UNAVAILABLE,
            )

    def test_chain_scan_and_record_disappearance_map_to_unavailable(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-chain-read-faults"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        with patch.object(
            _evidence_storage.os,
            "listdir",
            side_effect=OSError(errno.EIO, "session"),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.snapshot("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.UNAVAILABLE,
        )

        real_read = _evidence_storage._read_private_file

        def disappear(
            directory: Path,
            name: str,
            *,
            root: Path | None = None,
        ) -> bytes:
            if name == "record-00000001.json":
                raise _evidence_storage._MissingPrivateFile
            return real_read(directory, name, root=root)

        with patch.object(
            _evidence_storage,
            "_read_private_file",
            side_effect=disappear,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                writer.snapshot("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.UNAVAILABLE,
        )

        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_lifecycle(
                "1" * 32,
                evidence.LifecycleObservation(
                    lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                    evidence_refs=(),
                ),
                None,
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.INVALID_INPUT,
        )

    def test_public_aliases_and_calendar_timestamps_reject_boundaries(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        for case, value in (
            ("empty", ""),
            ("whitespace", " "),
            ("control", "\x00"),
        ):
            with self.subTest(case=case):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.open_session(
                        self._session_spec(),
                        evidence.WriteRequest(
                            operation_id=value,
                            occurred_at="2026-10-23T01:00:00Z",
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )

        with tempfile.TemporaryDirectory() as temporary_name:
            timestamp_writer = evidence.EvidenceStore(
                Path(temporary_name) / "evidence"
            ).execution_writer()
            with self.assertRaises(evidence.EvidenceError) as caught:
                timestamp_writer.open_session(
                    self._session_spec(),
                    evidence.WriteRequest(
                        operation_id=_operation("invalid-calendar-timestamp"),
                        occurred_at="2026-02-30T01:00:00Z",
                    ),
                )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.INVALID_INPUT,
        )

    def test_verify_execution_requires_terminal_and_published_manifest(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-without-terminal"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.verify_execution("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.MANIFEST_MISSING,
        )

        writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:01Z",
                evidence_refs=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-before-manifest-removal"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        manifest_path = self.root / "executions" / ("1" * 32) / "manifest.json"
        manifest_path.unlink()
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.verify_execution("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.MANIFEST_MISSING,
        )

    def test_persisted_session_rejects_digest_marker_and_primitive_faults(
        self,
    ) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-persisted-primitives"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("assertion-persisted-primitives"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        session_directory = self.root / "executions" / ("1" * 32)
        first_path = session_directory / "record-00000001.json"
        second_path = session_directory / "record-00000002.json"
        first = json.loads(first_path.read_bytes())
        second = json.loads(second_path.read_bytes())
        cases = {
            "internal-operation": lambda event: event.__setitem__(
                "operation_id",
                _evidence_storage._INTERNAL_OPERATION_PREFIX + "bad",
            ),
            "rules-version": lambda event: event["provenance"]["rules"].__setitem__(
                "rules_version", "v1"
            ),
            "manifest-version": lambda event: event["provenance"][
                "authorization"
            ].__setitem__("manifest_version", True),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                record = json.loads(_evidence_storage._canonical_bytes(first))
                mutate(record["event"])
                self._rewrite_record(session_directory, 1, record)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    writer.snapshot("1" * 32)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.CORRUPT,
                )
                first_path.write_bytes(_evidence_storage._canonical_bytes(first))
                first_path.chmod(0o600)

        bad_event_digest = json.loads(
            _evidence_storage._canonical_bytes(first)
        )
        bad_event_digest["event_sha256"] = "0" * 64
        digest_document = dict(bad_event_digest)
        digest_document.pop("record_sha256", None)
        bad_event_digest["record_sha256"] = _evidence_storage._canonical_sha256(
            digest_document
        )
        first_path.write_bytes(_evidence_storage._canonical_bytes(bad_event_digest))
        first_path.chmod(0o600)
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.CORRUPT,
        )
        first_path.write_bytes(_evidence_storage._canonical_bytes(first))
        first_path.chmod(0o600)

        opened_again = json.loads(_evidence_storage._canonical_bytes(first))
        regressed = json.loads(_evidence_storage._canonical_bytes(second))
        regressed["event"]["occurred_at"] = "2026-10-22T01:00:02Z"
        self._rewrite_record(session_directory, 2, regressed)
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.CORRUPT,
        )
        second_path.write_bytes(_evidence_storage._canonical_bytes(second))
        second_path.chmod(0o600)

        replaced_first = json.loads(_evidence_storage._canonical_bytes(first))
        replaced_first["event"] = json.loads(
            _evidence_storage._canonical_bytes(second)
        )["event"]
        self._rewrite_record(session_directory, 1, replaced_first)
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.snapshot("1" * 32)
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.CORRUPT,
        )
        first_path.write_bytes(_evidence_storage._canonical_bytes(first))
        first_path.chmod(0o600)
        self.assertIsNotNone(opened_again)

    def test_append_rejects_occurrence_before_latest_record(self) -> None:
        writer = evidence.EvidenceStore(self.root).execution_writer()
        opened = writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-backward-append"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            writer.append_lifecycle(
                "1" * 32,
                evidence.LifecycleObservation(
                    lifecycle=evidence.Lifecycle.EXECUTION_STARTED,
                    evidence_refs=(),
                ),
                evidence.WriteRequest(
                    operation_id=_operation("backward-lifecycle"),
                    occurred_at="2026-10-22T01:00:00Z",
                    expected_head_sha256=opened.head_sha256,
                ),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.INVALID_INPUT,
        )


if __name__ == "__main__":
    unittest.main()
