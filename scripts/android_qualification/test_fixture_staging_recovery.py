"""Exercise durable ownership records and restart recovery after interrupted cleanup."""

from __future__ import annotations

from contextlib import contextmanager
from scripts.android_qualification import _fixture_staging_destination as staging_destination
from scripts.android_qualification import _fixture_staging_ownership as staging_ownership
from scripts.android_qualification._fixture_staging_test_support import _cleanup_fixture_staging_for_synthetic_mechanics, _stage_fixtures_for_synthetic_mechanics
from scripts.android_qualification.test_manifest import NOW
from datetime import timedelta
from unittest.mock import patch
import copy
import hashlib
import json
import os
import threading
from scripts.android_qualification._fixture_staging_test_support import (
    FixtureStagingTestCase,
)


class FixtureStagingRecoveryTests(FixtureStagingTestCase):

    def test_cleanup_in_progress_blocker_survives_recovery_restart(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)
        record = destination._ownership._load_state(session_id)
        record["state"] = "cleanup_in_progress"
        destination._ownership._replace_state(record,
            capability=self.synthetic_capability,
        )

        blocker = api.FixtureStagingErrorCode.CLEANUP_BLOCKED
        self.assertTrue(
            destination._ownership.mark_blocked(
                session_id,
                token,
                blocker,
                capability=self.synthetic_capability,
            )
        )

        restarted_ownership = staging_ownership.FixtureStagingOwnership(destination.root)
        persisted = restarted_ownership._load_state(session_id)
        obligation = next(
            item
            for item in restarted_ownership.recovery_obligations()
            if item.session_id == session_id
        )

        self.assertEqual(persisted["state"], "cleanup_in_progress")
        self.assertEqual(persisted["blocker_code"], blocker.value)
        self.assertEqual(obligation.blocker_code, blocker.value)
        self.assertTrue(obligation.ownership_proven)

    def test_concurrent_cleanup_calls_retain_interrupted_session(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        record = destination._ownership._load_state(staged.session_id)
        record["state"] = "cleanup_in_progress"
        destination._ownership._replace_state(record,
            capability=self.synthetic_capability,
        )

        results = []
        failures = []
        first_start = threading.Barrier(2)
        second_start = threading.Barrier(2)
        first_mark_entered = threading.Event()
        release_first_mark = threading.Event()
        second_lock_attempted = threading.Event()
        second_lock_acquired = threading.Event()
        second_thread_id = [None]
        first_mark = [True]
        original_mark_blocked = destination._ownership.mark_blocked
        original_coordination_lock = destination._ownership.coordination_lock
        mark_guard = threading.Lock()

        def hold_first_blocker_write(session_id, token, code, **kwargs):
            with mark_guard:
                hold = first_mark[0]
                first_mark[0] = False
            if hold:
                first_mark_entered.set()
                if not release_first_mark.wait(timeout=5):
                    raise TimeoutError("timed out waiting to release blocked-state write")
            return original_mark_blocked(session_id, token, code, **kwargs)

        @contextmanager
        def observe_second_lock(*, create_state_directory=False, capability=None):
            is_second = threading.get_ident() == second_thread_id[0]
            if is_second:
                second_lock_attempted.set()
            with original_coordination_lock(
                create_state_directory=create_state_directory,
                capability=capability,
            ):
                if is_second:
                    second_lock_acquired.set()
                yield

        def clean_first():
            try:
                first_start.wait(timeout=5)
                worker_capability = (
                    staging_ownership._issue_synthetic_namespace_capability(
                        owner=destination._ownership._synthetic_owner
                    )
                )
                results.append(
                    _cleanup_fixture_staging_for_synthetic_mechanics(worker_capability,
                        grant,
                        destination=destination,
                        session_id=staged.session_id,
                        now=NOW,
                    )
                )
            except BaseException as error:
                failures.append(error)

        def clean_second():
            try:
                second_thread_id[0] = threading.get_ident()
                second_start.wait(timeout=5)
                worker_capability = (
                    staging_ownership._issue_synthetic_namespace_capability(
                        owner=destination._ownership._synthetic_owner
                    )
                )
                results.append(
                    _cleanup_fixture_staging_for_synthetic_mechanics(worker_capability,
                        grant,
                        destination=destination,
                        session_id=staged.session_id,
                        now=NOW,
                    )
                )
            except BaseException as error:
                failures.append(error)

        first = threading.Thread(target=clean_first)
        second = threading.Thread(target=clean_second)
        with (
            patch.object(
                destination._ownership,
                "mark_blocked",
                side_effect=hold_first_blocker_write,
            ),
            patch.object(
                destination._ownership,
                "coordination_lock",
                side_effect=observe_second_lock,
            ),
        ):
            first.start()
            first_start.wait(timeout=5)
            self.assertTrue(first_mark_entered.wait(timeout=5))
            second.start()
            second_start.wait(timeout=5)
            self.assertTrue(second_lock_attempted.wait(timeout=5))
            try:
                self.assertFalse(second_lock_acquired.wait(timeout=0.05))
            finally:
                release_first_mark.set()
            first.join(timeout=5)
            second.join(timeout=5)

        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertTrue(second_lock_acquired.is_set())
        self.assertEqual(failures, [])
        self.assertEqual(len(results), 2)
        for result in results:
            self.assertEqual(result.status, "BLOCKED")
            self.assertEqual(
                result.blocker_code,
                "BLOCKED_UNSUPPORTED_EXCLUSIVITY",
            )
        fixture_path = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        self.assertEqual(fixture_path.read_bytes(), b"synthetic-rom-content-v1")
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["state"], "cleanup_in_progress")
        self.assertEqual(
            state["blocker_code"], "BLOCKED_UNSUPPORTED_EXCLUSIVITY"
        )
        obligation = next(
            item
            for item in destination._ownership.recovery_obligations()
            if item.session_id == staged.session_id
        )
        self.assertEqual(obligation.state, "blocked")
        self.assertEqual(
            obligation.blocker_code, "BLOCKED_UNSUPPORTED_EXCLUSIVITY"
        )
        self.assertTrue(obligation.ownership_proven)

    def test_cleanup_retains_quarantine_without_a_persisted_root_identity(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, _token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination._synthetic_temporary_path(session_id).mkdir(mode=0o700)
        staging_ownership._fsync_directory(destination.root)

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertTrue(destination._synthetic_temporary_path(session_id).is_dir())
        state = destination._ownership._load_state(session_id)
        self.assertIsNone(state["root_inode"])

    def test_root_identity_publication_failure_retains_ambiguous_quarantine(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )

        def fail_root_identity(_record, **kwargs):
            raise api.FixtureStagingError(
                api.FixtureStagingErrorCode.DESTINATION_UNSAFE
            )

        with patch.object(
            destination._ownership, "_replace_state", side_effect=fail_root_identity
        ):
            with self.assertRaises(api.FixtureStagingError):
                destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )
        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertTrue(destination._synthetic_temporary_path(session_id).is_dir())
        state = destination._ownership._load_state(session_id)
        self.assertEqual(state["state"], "blocked")
        self.assertIsNone(state["root_inode"])

    def test_cleanup_refuses_unowned_directory_in_reserved_quarantine_name(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, _token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        foreign_root = destination._synthetic_temporary_path(session_id)
        foreign_root.mkdir(mode=0o700)
        sentinel = foreign_root / "foreign.txt"
        sentinel.write_bytes(b"preserve")

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(sentinel.read_bytes(), b"preserve")

    def test_cleanup_retains_file_created_before_ledger_publication(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)
        record_owned_entry = destination._ownership._record_owned_entry

        def fail_file_ledger(
            session, ownership_token, kind, relative_path, info, *, created, **kwargs
        ):
            if kind == "file" and relative_path == "fixture-synthetic/game.rom":
                raise api.FixtureStagingError(api.FixtureStagingErrorCode.DESTINATION_UNSAFE)
            return record_owned_entry(
                session,
                ownership_token,
                kind,
                relative_path,
                info,
                created=created,
                **kwargs,
            )

        with patch.object(
            destination._ownership, "_record_owned_entry", side_effect=fail_file_ledger
        ):
            with self.assertRaises(api.FixtureStagingError):
                destination._write_file(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    [b"synthetic-rom-content-v1"],
                    ownership_token=token,
                    source_mtime_ns=0,
                    grant=grant,
                    capability=self.synthetic_capability,
                )

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        partial = (
            destination._synthetic_temporary_path(session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        self.assertEqual(
            partial.read_bytes(),
            staging_destination._creation_stamp(
                session_id, token, "fixture-synthetic/game.rom"
            ),
        )

    def test_cleanup_retains_directory_created_before_ledger_publication(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)
        record_owned_entry = destination._ownership._record_owned_entry

        def fail_directory_ledger(
            session, ownership_token, kind, relative_path, info, *, created, **kwargs
        ):
            if kind == "directory" and relative_path == "fixture-synthetic":
                raise api.FixtureStagingError(api.FixtureStagingErrorCode.DESTINATION_UNSAFE)
            return record_owned_entry(
                session,
                ownership_token,
                kind,
                relative_path,
                info,
                created=created,
                **kwargs,
            )

        with patch.object(
            destination._ownership, "_record_owned_entry", side_effect=fail_directory_ledger
        ):
            with self.assertRaises(api.FixtureStagingError):
                destination._write_file(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    [b"synthetic-rom-content-v1"],
                    ownership_token=token,
                    source_mtime_ns=0,
                    grant=grant,
                    capability=self.synthetic_capability,
                )

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        partial = destination._synthetic_temporary_path(session_id) / "fixture-synthetic"
        self.assertTrue(partial.is_dir())
        self.assertEqual(list(partial.iterdir()), [])

    def test_initial_state_publication_never_leaves_a_partial_authoritative_record(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        ownership = self._make_synthetic_ownership(
            destination.root, session_id_factory=lambda: "a" * 32
        )
        original_fdopen = os.fdopen

        def fail_after_partial_write(descriptor, mode):
            stream = original_fdopen(descriptor, mode)

            class PartialStream:
                def __enter__(self):
                    return self

                def __exit__(self, _kind, _value, _traceback):
                    stream.close()
                    return False

                def write(self, value):
                    stream.write(value[:8])
                    stream.flush()
                    raise OSError("injected short state publication")

                def flush(self):
                    stream.flush()

                def fileno(self):
                    return stream.fileno()

            return PartialStream()

        with patch.object(
            staging_ownership.os, "fdopen", side_effect=fail_after_partial_write
        ):
            with self.assertRaises(api.FixtureStagingError):
                ownership.reserve_session(grant,
                    capability=self.synthetic_capability,
                )

        state_directory = destination.root / staging_ownership._STATE_DIRECTORY
        self.assertFalse(ownership.recovery_state_path("a" * 32).exists())
        sidecars = list(state_directory.glob("*.tmp"))
        self.assertEqual(len(sidecars), 1)
        self.assertTrue(sidecars[0].name.startswith(f".{ 'a' * 32 }."))
        self.assertTrue(sidecars[0].name.endswith(".tmp"))
        self.assertEqual(sidecars[0].stat().st_size, 8)
        self.assertTrue((state_directory / ".coordination.lock").exists())

    def test_state_generation_sidecar_swap_after_verification_is_retained_and_blocked(
        self,
    ) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id = "d" * 32
        ownership = self._make_synthetic_ownership(
            destination.root,
            session_id_factory=lambda: session_id,
        )
        session_id, token = ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        foreign_bytes = b'{"foreign":"state generation replacement"}'
        rename_entry = staging_ownership._rename_entry_exclusive

        def replace_generation_after_verification(
            source_directory,
            source_name,
            destination_directory,
            destination_name,
            *,
            capability=None,
        ):
            if destination_name == f"{session_id}.00000001.json":
                os.unlink(source_name, dir_fd=source_directory)
                descriptor = os.open(
                    source_name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=source_directory,
                )
                try:
                    os.write(descriptor, foreign_bytes)
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
            return rename_entry(
                source_directory,
                source_name,
                destination_directory,
                destination_name,
                capability=capability,
            )

        record = ownership._load_state(session_id)
        record["blocker_code"] = api.FixtureStagingErrorCode.COPY_INVALID.value
        with patch.object(
            staging_ownership,
            "_rename_entry_exclusive",
            side_effect=replace_generation_after_verification,
        ):
            with self.assertRaises(api.FixtureStagingError) as caught:
                ownership._replace_state(record,
                    capability=self.synthetic_capability,
                )

        self.assertEqual(
            caught.exception.code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN,
        )
        generation_path = (
            destination.root
            / staging_ownership._STATE_DIRECTORY
            / f"{session_id}.00000001.json"
        )
        self.assertEqual(generation_path.read_bytes(), foreign_bytes)
        obligation = next(
            item
            for item in ownership.recovery_obligations()
            if item.session_id == session_id
        )
        self.assertEqual(obligation.state, "BLOCKED")
        self.assertEqual(
            obligation.blocker_code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        self.assertFalse(obligation.ownership_proven)

    def test_replaced_state_sidecar_after_rename_is_retained(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id = "e" * 32
        ownership = self._make_synthetic_ownership(
            destination.root,
            session_id_factory=lambda: session_id,
        )
        session_id, _token = ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        foreign_bytes = b'{"foreign":"post-rename sidecar replacement"}'
        rename_entry = staging_ownership._rename_entry_exclusive
        temporary_path = None

        def replace_temporary_after_rename(
            source_directory,
            source_name,
            destination_directory,
            destination_name,
            *,
            capability=None,
        ):
            nonlocal temporary_path
            rename_entry(
                source_directory,
                source_name,
                destination_directory,
                destination_name,
                capability=capability,
            )
            if destination_name == f"{session_id}.00000001.json":
                temporary_path = (
                    destination.root
                    / staging_ownership._STATE_DIRECTORY
                    / source_name
                )
                descriptor = os.open(
                    source_name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=source_directory,
                )
                try:
                    os.write(descriptor, foreign_bytes)
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)

        record = ownership._load_state(session_id)
        record["state"] = "blocked"
        record["blocker_code"] = api.FixtureStagingErrorCode.COPY_INVALID.value
        with patch.object(
            staging_ownership,
            "_rename_entry_exclusive",
            side_effect=replace_temporary_after_rename,
        ):
            ownership._replace_state(record,
                capability=self.synthetic_capability,
            )

        self.assertIsNotNone(temporary_path)
        self.assertEqual(temporary_path.read_bytes(), foreign_bytes)
        persisted = ownership._load_state(session_id)
        self.assertEqual(persisted["state"], "blocked")
        self.assertEqual(
            persisted["blocker_code"],
            api.FixtureStagingErrorCode.COPY_INVALID.value,
        )
        obligation = next(
            item
            for item in ownership.recovery_obligations()
            if item.session_id == session_id
        )
        self.assertEqual(obligation.state, "blocked")
        self.assertEqual(
            obligation.blocker_code,
            api.FixtureStagingErrorCode.COPY_INVALID.value,
        )

    def test_marker_publication_is_atomic_and_ambiguous_partial_is_retained(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        publish_json = staging_ownership._publish_json_exclusive

        def fail_marker_publication(path, temporary, encoded, *, capability):
            if path.name == ".owner.json":
                descriptor = os.open(
                    temporary,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                )
                try:
                    os.write(descriptor, encoded[:8])
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
                raise OSError("injected short marker publication")
            return publish_json(
                path,
                temporary,
                encoded,
                capability=capability,
            )

        with patch.object(
            staging_ownership,
            "_publish_json_exclusive",
            side_effect=fail_marker_publication,
        ):
            with self.assertRaises(api.FixtureStagingError):
                destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)

        marker = destination._synthetic_temporary_path(session_id) / ".owner.json"
        self.assertFalse(marker.exists(), "partial marker bytes reached the final pathname")
        marker_sidecar = destination._synthetic_temporary_path(session_id) / f".owner.json.{token}.tmp"
        self.assertEqual(marker_sidecar.stat().st_size, 8)
        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertTrue(marker_sidecar.exists())
        self.assertTrue(destination._synthetic_temporary_path(session_id).is_dir())

    def test_marker_to_ledger_failure_retains_unproven_marker(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        replace_state = destination._ownership._replace_state

        def fail_marker_ledger(record, **kwargs):
            if any(
                type(item) is dict and item.get("path") == ".owner.json"
                for item in record.get("owned_entries", [])
            ):
                raise api.FixtureStagingError(
                    api.FixtureStagingErrorCode.DESTINATION_UNSAFE
                )
            return replace_state(record, **kwargs)

        with patch.object(
            destination._ownership, "_replace_state", side_effect=fail_marker_ledger
        ):
            with self.assertRaises(api.FixtureStagingError):
                destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        marker = destination._synthetic_temporary_path(session_id) / ".owner.json"
        self.assertTrue(marker.exists())
        self.assertTrue(destination._synthetic_temporary_path(session_id).is_dir())

    def test_cleanup_recovers_a_durable_pending_publication(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        record = destination._ownership._load_state(staged.session_id)
        record["state"] = "publication_pending"
        destination._ownership._replace_state(record,
            capability=self.synthetic_capability,
        )

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        self.assertEqual(
            destination._ownership._load_state(staged.session_id)["blocker_code"],
            cleanup.blocker_code,
        )

    def test_explicit_cleanup_recovers_a_tracked_interrupted_partial(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)

        def interrupt():
            raise KeyboardInterrupt

        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
            cancellation=interrupt,
        )
        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )

        self.assertEqual(staged.status, "BLOCKED")
        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertTrue(destination._synthetic_temporary_path(staged.session_id).exists())
        obligation = next(
            item
            for item in destination._ownership.recovery_obligations()
            if item.session_id == staged.session_id
        )
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_interrupted_cleanup_retains_partial_tree_without_retrying_deletion(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        record = destination._ownership._load_state(staged.session_id)
        record["state"] = "cleanup_in_progress"
        destination._ownership._replace_state(record,
            capability=self.synthetic_capability,
        )
        fixture = destination._synthetic_final_path(staged.session_id) / "fixture-synthetic"
        (fixture / "game.rom").unlink()

        with patch.object(
            staging_ownership,
            "_remove_tree_contents",
            side_effect=OSError("cleanup must not enter the deletion walk"),
        ) as remove_tree:
            interrupted = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertEqual(interrupted.status, "BLOCKED")
        self.assertEqual(
            interrupted.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        remove_tree.assert_not_called()
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        self.assertFalse((fixture / "game.rom").exists())
        self.assertTrue((fixture).is_dir())

    def test_cleanup_never_retries_or_removes_root_without_exclusivity(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        original_rmdir = os.rmdir
        failed = [False]

        def fail_session_root_once(path, *args, **kwargs):
            if path == destination._synthetic_final_path(staged.session_id).name and not failed[0]:
                failed[0] = True
                raise OSError("simulated failure removing owned root")
            return original_rmdir(path, *args, **kwargs)

        with patch.object(staging_destination.os, "rmdir", side_effect=fail_session_root_once):
            interrupted = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertFalse(failed[0])
        self.assertEqual(interrupted.status, "BLOCKED")
        self.assertEqual(
            interrupted.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        fixture = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        self.assertEqual(fixture.read_bytes(), b"synthetic-rom-content-v1")
        recovered = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )
        self.assertEqual(recovered.status, "BLOCKED")
        self.assertEqual(recovered.blocker_code, interrupted.blocker_code)
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_public_cleanup_fails_closed_before_destination_mutation(self) -> None:
        """The blocker leaves existing source and ownership state untouched."""
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-cleanup-admission"
        )
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(staged.status, "VERIFIED_FIXTURE")
        source_fixture = source_root / "game.rom"
        source_bytes = source_fixture.read_bytes()

        state_directory = destination.root / destination._STATE_DIRECTORY
        lock_path = state_directory / ".coordination.lock"
        lock_path.unlink()

        def snapshot_tree() -> dict[str, tuple[object, ...]]:
            snapshot: dict[str, tuple[object, ...]] = {}
            for path in sorted(
                destination.root.rglob("*"),
                key=lambda item: item.relative_to(destination.root).as_posix(),
            ):
                relative = path.relative_to(destination.root).as_posix()
                if path.is_symlink():
                    snapshot[relative] = ("symlink", os.readlink(path))
                elif path.is_dir():
                    snapshot[relative] = ("directory",)
                else:
                    snapshot[relative] = (
                        "file",
                        hashlib.sha256(path.read_bytes()).hexdigest(),
                    )
            return snapshot

        before_tree = snapshot_tree()
        before_state = copy.deepcopy(
            destination._ownership._load_state(staged.session_id)
        )
        before_obligations = destination._ownership.recovery_obligations()

        with (
            patch.object(
                destination._ownership,
                "coordination_lock",
                wraps=destination._ownership.coordination_lock,
            ) as coordination_lock,
            patch.object(
                destination._ownership,
                "_load_state",
                wraps=destination._ownership._load_state,
            ) as load_state,
            patch.object(
                destination._ownership,
                "remove_owned_session",
                wraps=destination._ownership.remove_owned_session,
            ) as remove_owned_session,
            patch.object(
                destination._ownership,
                "mark_blocked_or_destination_unsafe",
                wraps=destination._ownership.mark_blocked_or_destination_unsafe,
            ) as mark_blocked,
        ):
            cleanup = self.production_cleanup_fixture_staging(
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertEqual(cleanup.session_id, staged.session_id)
        self.assertFalse(cleanup.removed)
        coordination_lock.assert_not_called()
        load_state.assert_not_called()
        remove_owned_session.assert_not_called()
        mark_blocked.assert_not_called()
        self.assertEqual(snapshot_tree(), before_tree)
        self.assertFalse(lock_path.exists())
        self.assertEqual(
            destination._ownership._load_state(staged.session_id), before_state
        )
        self.assertEqual(
            destination._ownership.recovery_obligations(), before_obligations
        )
        fixture = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        self.assertEqual(fixture.read_bytes(), b"synthetic-rom-content-v1")
        self.assertEqual(source_fixture.read_bytes(), source_bytes)

    def test_cleanup_never_marks_complete_without_exclusivity(self) -> None:
        api = self._require_staging_module()

        class FailingCleanupCompleteWrite(api.FilesystemFixtureDestination):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.failed_once = False
                replace_state = self._ownership._replace_state

                def fail_once(record, **kwargs):
                    if record.get("state") == "cleanup_complete" and not self.failed_once:
                        self.failed_once = True
                        raise api.FixtureStagingError(
                            api.FixtureStagingErrorCode.DESTINATION_UNSAFE
                        )
                    return replace_state(record, **kwargs)

                self._ownership._replace_state = fail_once

        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=FailingCleanupCompleteWrite
        )
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        interrupted = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertFalse(destination.failed_once)
        self.assertEqual(interrupted.status, "BLOCKED")
        self.assertEqual(
            interrupted.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        recovered = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )
        self.assertEqual(recovered.status, "BLOCKED")
        self.assertEqual(recovered.blocker_code, interrupted.blocker_code)

    def test_cleanup_state_fsync_failure_does_not_claim_durable_blocker(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        original_fsync_directory = staging_ownership._fsync_directory
        fsync_failed_after_block = [False]

        def fail_complete_record_directory_fsync(directory):
            record = destination._ownership._load_state(staged.session_id)
            if (
                record.get("state") == "blocked"
                and record.get("blocker_code")
                == api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value
                and not fsync_failed_after_block[0]
            ):
                fsync_failed_after_block[0] = True
                raise OSError("synthetic directory fsync failure after state replacement")
            return original_fsync_directory(directory)

        with patch.object(
            staging_ownership,
            "_fsync_directory",
            side_effect=fail_complete_record_directory_fsync,
        ):
            interrupted = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertTrue(fsync_failed_after_block[0])
        self.assertEqual(interrupted.status, "BLOCKED")
        self.assertEqual(
            interrupted.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["state"], "blocked")
        self.assertTrue(
            destination._ownership._ownership_is_proven(state, staged.session_id)
        )

    def test_cleanup_refuses_state_ownership_token_mismatch(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        state_path = destination.recovery_state_path(staged.session_id)
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["ownership_token"] = "0" * 64
        state_path.write_text(json.dumps(state), encoding="utf-8")

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_blocker_state_directory_failure_is_reported_without_a_blocked_claim(
        self,
    ) -> None:
        api = self._require_staging_module()

        class BlockerStateDirectoryFailureDestination(
            api.FilesystemFixtureDestination
        ):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.failed_verified_write = False
                self.failed_blocker_directory = False
                self.fail_blocker_directory = False
                replace_state = self._ownership._replace_state
                state_directory = self._ownership._state_directory

                def fail_verified_write(record, **kwargs):
                    if record.get("verified_files") and not self.failed_verified_write:
                        self.failed_verified_write = True
                        self.fail_blocker_directory = True
                        raise api.FixtureStagingError(
                            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                        )
                    return replace_state(record, **kwargs)

                def fail_blocker_state_directory(*, create=False, capability=None):
                    if self.fail_blocker_directory and create:
                        self.failed_blocker_directory = True
                        raise api.FixtureStagingError(
                            api.FixtureStagingErrorCode.DESTINATION_UNSAFE
                        )
                    return state_directory(create=create, capability=capability)

                self._ownership._replace_state = fail_verified_write
                self._ownership._state_directory = fail_blocker_state_directory

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=BlockerStateDirectoryFailureDestination
        )

        try:
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )
        except api.FixtureStagingError as error:
            self.fail(f"blocker persistence failure escaped to the caller: {error}")

        self.assertTrue(destination.failed_verified_write)
        self.assertTrue(destination.failed_blocker_directory)
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        state = destination._ownership._load_state(result.session_id)
        self.assertNotEqual(state["state"], "blocked")
        self.assertIsNone(state["blocker_code"])

    def test_cleanup_reports_state_write_failure_and_retains_resources(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        unexpected = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "foreign.bin"
        )
        unexpected.write_bytes(b"preserve")

        with patch.object(destination._ownership, "mark_blocked", return_value=False):
            cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        self.assertEqual(unexpected.read_bytes(), b"preserve")
        fixture = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        self.assertEqual(fixture.read_bytes(), b"synthetic-rom-content-v1")
