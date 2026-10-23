"""Exercise safe fixture publication, capacity checks, and post-publication integrity."""

from __future__ import annotations

from contextlib import ExitStack
from scripts.android_qualification._fixture_staging_test_support import _sync_oracle
from scripts.android_qualification._fixture_staging_test_support import _cleanup_fixture_staging_for_synthetic_mechanics, _stage_fixtures_for_synthetic_mechanics
from scripts.android_qualification.test_manifest import NOW
from scripts.android_qualification.test_manifest import approval_document
from scripts.android_qualification.test_manifest import write_private_json
import copy
import contextvars
import gc
from datetime import timedelta
import inspect
import os
import pickle
import stat
import threading
from types import SimpleNamespace
from unittest.mock import patch
import weakref
from typing import Literal, cast
from scripts.android_qualification._fixture_staging_test_support import (
    FixtureStagingTestCase,
    _SyntheticFilesystemFixtureDestination,
)
from scripts.android_qualification import _fixture_staging_destination as staging_destination
from scripts.android_qualification import _fixture_staging_orchestration
from scripts.android_qualification import _fixture_staging_ownership as staging_ownership
from scripts.android_qualification import _fixture_staging_transfer
import threading


class _PublicationCrash(BaseException):
    """Stop a test exactly at a modeled process-crash boundary."""


class FixtureStagingDestinationTests(FixtureStagingTestCase):
    def test_approval_change_after_publication_fails_closed_with_recovery_state(self) -> None:
        api = self._require_staging_module()

        class ApprovalChangingDestination(api.FilesystemFixtureDestination):
            def _publish(self, session_id, token, *, grant, **kwargs):
                super()._publish(session_id, token, grant=grant, **kwargs)
                write_private_json(
                    self_test.directory,
                    "approval.json",
                    approval_document("0" * 64),
                )

        self_test = self
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=ApprovalChangingDestination
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.INVALID_AUTHORITY.value,
        )
        self.assertTrue(destination._synthetic_final_path(result.session_id).exists())
        self.assertIsNone(destination.eligible_root(result.session_id, grant=grant))
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_expiry_after_publication_does_not_make_fixture_eligible(self) -> None:
        api = self._require_staging_module()

        class ExpiringDestination(api.FilesystemFixtureDestination):
            def _publish(self, session_id, token, *, grant, **kwargs):
                super()._publish(session_id, token, grant=grant, **kwargs)
                self_test.staging_now[0] = grant._approval.valid_until + timedelta(
                    seconds=1
                )

        self_test = self
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=ExpiringDestination
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertTrue(destination._synthetic_final_path(result.session_id).exists())
        self.assertFalse(
            destination._synthetic_temporary_path(result.session_id).exists()
        )
        self.assertIsNone(destination.eligible_root(result.session_id, grant=grant))
        state = destination._ownership._load_state(result.session_id)
        self.assertEqual(state["state"], "blocked")
        self.assertEqual(
            state["publication_intent"],
            {
                "temporary_name": state["temporary_name"],
                "final_name": state["final_name"],
                "root_device": state["root_device"],
                "root_inode": state["root_inode"],
            },
        )
        self.assertEqual(
            state["blocker_code"],
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertEqual(
            obligation.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertTrue(obligation.ownership_proven)

    def test_publication_remains_preparing_until_durable_intent(self) -> None:
        api = self._require_staging_module()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-publication-before-intent",
        )
        observed: list[tuple[str, object]] = []

        def crash_before_publication(session_id, _token, **_kwargs):
            record = destination._ownership._load_state(session_id)
            observed.append((record["state"], record["publication_intent"]))
            self.assertFalse(destination._synthetic_final_path(session_id).exists())
            self.assertTrue(destination._synthetic_temporary_path(session_id).exists())
            raise _PublicationCrash

        with patch.object(
            destination,
            "_publish_and_confirm",
            side_effect=crash_before_publication,
        ):
            with self.assertRaises(_PublicationCrash):
                _stage_fixtures_for_synthetic_mechanics(
                    self.synthetic_capability,
                    grant,
                    source_roots={"fixture-synthetic": source_root},
                    destination=destination,
                    now=NOW,
                )

        self.assertEqual(observed, [("preparing", None)])
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_crash_after_durable_intent_before_rename_is_unambiguous(self) -> None:
        api = self._require_staging_module()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-publication-intent-crash",
        )
        events: list[str] = []
        replace_state = destination._ownership._replace_state

        def record_durable_intent(record, **kwargs):
            result = replace_state(record, **kwargs)
            if record.get("state") == "publication_pending":
                events.append("intent-durable")
            return result

        def crash_before_rename(*_args, **_kwargs):
            events.append("rename")
            raise _PublicationCrash

        with (
            patch.object(
                destination._ownership,
                "_replace_state",
                side_effect=record_durable_intent,
            ),
            patch.object(
                staging_destination,
                "_rename_entry_exclusive",
                side_effect=crash_before_rename,
            ),
        ):
            with self.assertRaises(_PublicationCrash):
                _stage_fixtures_for_synthetic_mechanics(
                    self.synthetic_capability,
                    grant,
                    source_roots={"fixture-synthetic": source_root},
                    destination=destination,
                    now=NOW,
                )

        self.assertEqual(events, ["intent-durable", "rename"])
        obligation = destination._ownership.recovery_obligations()[0]
        session_id = obligation.session_id
        record = destination._ownership._load_state(session_id)
        self.assertEqual(record["state"], "publication_pending")
        self.assertEqual(
            record["publication_intent"],
            {
                "temporary_name": record["temporary_name"],
                "final_name": record["final_name"],
                "root_device": record["root_device"],
                "root_inode": record["root_inode"],
            },
        )
        self.assertFalse(destination._synthetic_final_path(session_id).exists())
        self.assertTrue(destination._synthetic_temporary_path(session_id).exists())
        self.assertTrue(obligation.ownership_proven)
        self.assertIsNone(destination.eligible_root(session_id, grant=grant))

    def test_crash_after_rename_before_confirmation_is_ineligible(self) -> None:
        api = self._require_staging_module()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-publication-rename-crash",
        )
        events: list[str] = []
        original_rename = staging_destination._rename_entry_exclusive

        def record_rename(*args, **kwargs):
            result = original_rename(*args, **kwargs)
            events.append("rename")
            return result

        def crash_before_confirmation(*_args, **_kwargs):
            events.append("confirmation")
            raise _PublicationCrash

        with (
            patch.object(
                staging_destination,
                "_rename_entry_exclusive",
                side_effect=record_rename,
            ),
            patch.object(
                destination,
                "_confirm_publication",
                side_effect=crash_before_confirmation,
            ),
        ):
            with self.assertRaises(_PublicationCrash):
                _stage_fixtures_for_synthetic_mechanics(
                    self.synthetic_capability,
                    grant,
                    source_roots={"fixture-synthetic": source_root},
                    destination=destination,
                    now=NOW,
                )

        self.assertEqual(events, ["rename", "confirmation"])
        obligation = destination._ownership.recovery_obligations()[0]
        session_id = obligation.session_id
        record = destination._ownership._load_state(session_id)
        self.assertEqual(record["state"], "publication_pending")
        self.assertIsNotNone(record["publication_intent"])
        self.assertTrue(destination._synthetic_final_path(session_id).exists())
        self.assertFalse(destination._synthetic_temporary_path(session_id).exists())
        self.assertTrue(obligation.ownership_proven)
        self.assertIsNone(destination.eligible_root(session_id, grant=grant))

    def test_publication_intent_reaches_final_published_state(self) -> None:
        api = self._require_staging_module()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-publication-confirmed",
        )
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        record = destination._ownership._load_state(staged.session_id)
        self.assertEqual(record["state"], "published")
        self.assertEqual(
            record["publication_intent"],
            {
                "temporary_name": record["temporary_name"],
                "final_name": record["final_name"],
                "root_device": record["root_device"],
                "root_inode": record["root_inode"],
            },
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        self.assertFalse(destination._synthetic_temporary_path(staged.session_id).exists())
        self.assertIsNotNone(
            destination._synthetic_eligible_root(staged.session_id, grant=grant)
        )

    def test_expiry_during_eligibility_state_write_blocks_the_result(self) -> None:
        api = self._require_staging_module()
        grant_holder = [None]

        class ExpiringEligibilityWriteDestination(api.FilesystemFixtureDestination):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                replace_state = self._ownership._replace_state

                def expire_on_publication(record, **kwargs):
                    if record.get("state") == "published":
                        self_test.staging_now[0] = (
                            grant_holder[0]._approval.valid_until
                            + timedelta(seconds=1)
                        )
                    return replace_state(record, **kwargs)

                self._ownership._replace_state = expire_on_publication

        self_test = self
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=ExpiringEligibilityWriteDestination
        )
        grant_holder[0] = grant

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertIsNone(destination.eligible_root(result.session_id, grant=grant))
        self.assertIsNone(
            destination._synthetic_eligible_root(result.session_id, grant=grant)
        )
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_existing_final_destination_is_never_overwritten(self) -> None:
        api = self._require_staging_module()
        session_id = "a" * 32
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            session_id_factory=lambda: session_id
        )
        existing = destination._synthetic_final_path(session_id)
        existing.mkdir(mode=0o700)
        sentinel = existing / "keep.bin"
        sentinel.write_bytes(b"pre-existing")

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        self.assertEqual(sentinel.read_bytes(), b"pre-existing")
        self.assertFalse(destination._synthetic_temporary_path(session_id).exists())
        self.assertFalse(destination._ownership.recovery_obligations()[0].ownership_proven)

    def test_publication_race_after_verification_preserves_foreign_final_bytes(
        self,
    ) -> None:
        api = self._require_staging_module()
        session_id = "b" * 32
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            session_id_factory=lambda: session_id
        )
        foreign_bytes = b"foreign-final-created-during-publication"
        publish_exclusively = staging_destination._rename_entry_exclusive

        def replace_final_before_exclusive_rename(
            source_directory,
            source_name,
            destination_directory,
            destination_name,
            **kwargs,
        ):
            os.mkdir(destination_name, mode=0o700, dir_fd=destination_directory)
            foreign_directory = os.open(
                destination_name,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=destination_directory,
            )
            try:
                descriptor = os.open(
                    "foreign.bin",
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=foreign_directory,
                )
                try:
                    os.write(descriptor, foreign_bytes)
                finally:
                    os.close(descriptor)
            finally:
                os.close(foreign_directory)
            return publish_exclusively(
                source_directory,
                source_name,
                destination_directory,
                destination_name,
                **kwargs,
            )

        with patch.object(
            staging_destination,
            "_rename_entry_exclusive",
            side_effect=replace_final_before_exclusive_rename,
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        self.assertEqual(result.verified_bytes, len(b"synthetic-rom-content-v1"))
        self.assertEqual(
            (destination._synthetic_final_path(session_id) / "foreign.bin").read_bytes(),
            foreign_bytes,
        )

    def test_quarantine_source_swap_after_verification_blocks_and_preserves_both_trees(
        self,
    ) -> None:
        api = self._require_staging_module()
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        session_id = "c" * 32
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            session_id_factory=lambda: session_id
        )
        foreign_bytes = b"foreign-quarantine-replacement"
        preserved_name = ".same-user-verified-source"
        publish_exclusively = staging_destination._rename_entry_exclusive

        def swap_source_before_exclusive_rename(
            source_directory,
            source_name,
            destination_directory,
            destination_name,
            **kwargs,
        ):
            os.rename(
                source_name,
                preserved_name,
                src_dir_fd=source_directory,
                dst_dir_fd=source_directory,
            )
            os.mkdir(source_name, mode=0o700, dir_fd=source_directory)
            foreign_directory = os.open(
                source_name,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=source_directory,
            )
            try:
                descriptor = os.open(
                    "foreign.bin",
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=foreign_directory,
                )
                try:
                    os.write(descriptor, foreign_bytes)
                finally:
                    os.close(descriptor)
            finally:
                os.close(foreign_directory)
            return publish_exclusively(
                source_directory,
                source_name,
                destination_directory,
                destination_name,
                **kwargs,
            )

        with patch.object(
            staging_destination,
            "_rename_entry_exclusive",
            side_effect=swap_source_before_exclusive_rename,
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        final_root = destination._synthetic_final_path(session_id)
        self.assertEqual((final_root / "foreign.bin").read_bytes(), foreign_bytes)
        preserved_root = destination.root / preserved_name
        self.assertEqual(
            (preserved_root / "fixture-synthetic" / "game.rom").read_bytes(),
            b"synthetic-rom-content-v1",
        )
        self.assertIsNone(destination.eligible_root(session_id, grant=grant))

        state = destination._ownership._load_state(session_id)
        self.assertEqual(state["state"], "blocked")
        self.assertEqual(
            state["blocker_code"],
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        obligation = next(
            item
            for item in destination._ownership.recovery_obligations()
            if item.session_id == session_id
        )
        self.assertEqual(obligation.state, "blocked")
        self.assertEqual(
            obligation.blocker_code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        self.assertFalse(obligation.ownership_proven)

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=session_id,
            now=NOW,
        )
        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertFalse(cleanup.removed)
        self.assertEqual((final_root / "foreign.bin").read_bytes(), foreign_bytes)
        self.assertTrue(preserved_root.exists())


    def test_staging_streams_and_readbacks_the_pinned_bytes_before_publication(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        observations = []
        destination._synthetic_capacity_observer = lambda root: (
            observations.append(root) or api.CapacityObservation(10**12, 10**12)
        )
        original = (source_root / "game.rom").read_bytes()

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)
        self.assertEqual(result.result_kind, "HOST_PREPARATION_ONLY")
        self.assertEqual(result.evidence_class, "SYNTHETIC_SIMULATION")
        self.assertEqual(result.identity_evidence, "owner_approved_expectation_match")
        self.assertEqual(result.coverage_mode, "mandatory_full_plan")
        self.assertEqual(result.required_fixture_count, 1)
        self.assertEqual(result.selected_fixture_count, 1)
        self.assertEqual(
            destination._synthetic_eligible_root(result.session_id, grant=grant),
            destination._synthetic_final_path(result.session_id),
        )
        self.assertIsNone(destination.eligible_root(result.session_id, grant=grant))
        self.assertFalse(result.device_admitted)
        self.assertFalse(result.session_authorization_consumed)
        staged = destination._synthetic_final_path(result.session_id) / "fixture-synthetic" / "game.rom"
        self.assertEqual(staged.read_bytes(), original)
        self.assertEqual(
            staged.stat().st_mtime_ns, (source_root / "game.rom").stat().st_mtime_ns
        )
        self.assertEqual(stat.S_IMODE(staged.stat().st_mode), 0o600)
        self.assertEqual((source_root / "game.rom").read_bytes(), original)
        self.assertGreaterEqual(len(observations), 2)

    def test_eligibility_rehashes_published_content_after_stat_identity_is_preserved(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)

        published_root = destination._synthetic_final_path(result.session_id)
        staged = published_root / "fixture-synthetic" / "game.rom"
        self.assertEqual(
            destination._synthetic_eligible_root(result.session_id, grant=grant),
            published_root,
        )
        before = staged.stat()
        changed = bytearray(staged.read_bytes())
        changed[0] ^= 0xFF
        staged.write_bytes(changed)
        os.utime(staged, ns=(before.st_atime_ns, before.st_mtime_ns))
        after = staged.stat()

        self.assertEqual(staged, published_root / "fixture-synthetic" / "game.rom")
        self.assertEqual((after.st_dev, after.st_ino), (before.st_dev, before.st_ino))
        self.assertEqual(after.st_size, before.st_size)
        self.assertEqual(after.st_mtime_ns, before.st_mtime_ns)
        self.assertIsNone(
            destination._synthetic_eligible_root(result.session_id, grant=grant)
        )

    def test_capacity_reserves_block_before_any_staging_root_is_created(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["host_reserve_bytes"] = 5
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=lambda _root: api.CapacityObservation(27, 10**9)
        )
        sentinel = destination.root / "existing-fixture.bin"
        sentinel.write_bytes(b"preserve")

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.CAPACITY_INSUFFICIENT.value,
        )
        self.assertEqual(sentinel.read_bytes(), b"preserve")

    def test_capacity_observer_failure_blocks_before_reserving_a_session(self) -> None:
        api = self._require_staging_module()

        def unavailable(_root):
            raise OSError("synthetic capacity probe failure")

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=unavailable
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.CAPACITY_UNPROVEN.value,
        )
        self.assertEqual(destination._ownership.recovery_obligations(), ())

    def test_short_cleanup_reserve_does_not_expire_staging_before_operation_deadline(
        self,
    ) -> None:
        api = self._require_staging_module()
        self.authorization_document["operations"][0]["restoration"]["timeout_seconds"] = 10
        self.authorization_document["reserves"]["cleanup_seconds"] = 10
        self._rebind_inputs()
        self.staging_monotonic[0] = 11.0
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)
        timing = destination._ownership._load_state(
            result.session_id
        )["operation_timing"]
        self.assertEqual(
            timing["operation_deadline_monotonic_ns"],
            timing["monotonic_start_ns"] + 30 * 1_000_000_000,
        )
        self.assertEqual(
            timing["cleanup_reserve_deadline_monotonic_ns"],
            timing["operation_deadline_monotonic_ns"] - 10 * 1_000_000_000,
        )

    def test_operation_timeout_is_bound_and_enforced_monotonically(self) -> None:
        api = self._require_staging_module()

        def slow_observer(_root):
            self.staging_monotonic[0] += 31.0
            return api.CapacityObservation(10**12, 10**12)

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=slow_observer
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.OPERATION_TIMEOUT.value,
        )
        self.assertEqual(destination._ownership.recovery_obligations(), ())

    def test_invalid_monotonic_clock_fails_closed(self) -> None:
        api = self._require_staging_module()

        def unavailable_clock():
            raise OSError("synthetic monotonic clock failure")

        for index, clock in enumerate((lambda: float("nan"), unavailable_clock)):
            capability = staging_ownership._issue_synthetic_namespace_capability(
                owner=self.synthetic_owner,
                monotonic_clock=clock
            )
            api, source_root, destination, grant = self._make_staging_inputs(
                capability=capability,
                suffix=f"-clock-{index}"
            )
            result = _stage_fixtures_for_synthetic_mechanics(capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
            )
            self.assertEqual(result.status, "BLOCKED")
            self.assertEqual(
                result.blocker_code,
                api.FixtureStagingErrorCode.OPERATION_TIMEOUT.value,
            )
            self.assertEqual(destination._ownership.recovery_obligations(), ())

    def test_timeout_during_stream_keeps_only_owned_quarantine_for_recovery(self) -> None:
        api = self._require_staging_module()
        observations = [0]

        def slow_transfer_observer(_root):
            observations[0] += 1
            if observations[0] == 3:
                self.staging_monotonic[0] += 31.0
            return api.CapacityObservation(10**12, 10**12)

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=slow_transfer_observer
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.OPERATION_TIMEOUT.value,
        )
        self.assertTrue(destination._synthetic_temporary_path(result.session_id).exists())
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertTrue(destination._ownership.recovery_obligations()[0].ownership_proven)

    def test_destination_publisher_refuses_an_incomplete_verification_ledger(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination._create_quarantine(session_id, token, grant, capability=self.synthetic_capability)

        with self.assertRaises(api.FixtureStagingError) as caught:
            destination._publish(session_id, token, grant=grant, capability=self.synthetic_capability)

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.COPY_INVALID)
        self.assertFalse(destination._synthetic_final_path(session_id).exists())
        self.assertTrue(destination._synthetic_temporary_path(session_id).exists())
        self.assertFalse(any(destination.root.glob("fixture-*")))

    def test_interruption_leaves_owned_quarantine_for_explicit_recovery(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)

        def interrupt():
            raise KeyboardInterrupt

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
            cancellation=interrupt,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertTrue(destination._synthetic_temporary_path(result.session_id).exists())
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_partial_transfer_failure_is_not_retried_or_published(self) -> None:
        api = self._require_staging_module()
        write_attempts = []

        class PartialDestination(api.FilesystemFixtureDestination):
            def _write_file(
                self,
                session_id,
                fixture_id,
                relative_path,
                chunks,
                *,
                ownership_token,
                source_mtime_ns,
                grant,
                capability=None,
            ):
                write_attempts.append(relative_path)
                iterator = iter(chunks)

                def partial():
                    yield next(iterator)
                    raise OSError("synthetic interrupted write")

                return super()._write_file(
                    session_id,
                    fixture_id,
                    relative_path,
                    partial(),
                    ownership_token=ownership_token,
                    source_mtime_ns=source_mtime_ns,
                    grant=grant,
                    capability=capability,
                )

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=PartialDestination
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.COPY_INVALID.value,
        )
        self.assertEqual(write_attempts, ["game.rom"])
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertIsNone(destination.eligible_root(result.session_id, grant=grant))
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertEqual(
            obligation.blocker_code,
            api.FixtureStagingErrorCode.COPY_INVALID.value,
        )
        self.assertTrue(obligation.ownership_proven)

    def test_publication_state_write_failure_retains_blocked_evidence(self) -> None:
        api = self._require_staging_module()

        class FailingPublicationStateDestination(api.FilesystemFixtureDestination):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.failed_once = False
                replace_state = self._ownership._replace_state

                def fail_publication_pending(record, **kwargs):
                    if (
                        record.get("state") == "publication_pending"
                        and not self.failed_once
                    ):
                        self.failed_once = True
                        raise api.FixtureStagingError(
                            api.FixtureStagingErrorCode.DESTINATION_UNSAFE
                        )
                    return replace_state(record, **kwargs)

                self._ownership._replace_state = fail_publication_pending

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=FailingPublicationStateDestination,
        )
        result = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertTrue(destination.failed_once)
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertTrue(
            destination._synthetic_temporary_path(result.session_id).exists()
        )
        self.assertIsNone(destination.eligible_root(result.session_id, grant=grant))
        state = destination._ownership._load_state(result.session_id)
        self.assertEqual(state["state"], "blocked")
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_recovery_state_write_failure_leaves_a_proven_blocked_obligation(self) -> None:
        api = self._require_staging_module()

        class FailingStateWriteDestination(api.FilesystemFixtureDestination):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.failed_once = False
                replace_state = self._ownership._replace_state

                def fail_once(record, **kwargs):
                    if record.get("verified_files") and not self.failed_once:
                        self.failed_once = True
                        raise api.FixtureStagingError(
                            api.FixtureStagingErrorCode.DESTINATION_UNSAFE
                        )
                    return replace_state(record, **kwargs)

                self._ownership._replace_state = fail_once

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=FailingStateWriteDestination
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertTrue(destination.failed_once)
        self.assertEqual(result.status, "BLOCKED")
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        obligation = destination._ownership.recovery_obligations()[0]
        self.assertEqual(obligation.state, "blocked")
        self.assertTrue(obligation.ownership_proven)

    def test_destination_readback_mismatch_blocks_publication(self) -> None:
        api = self._require_staging_module()

        class CorruptReadbackDestination(api.FilesystemFixtureDestination):
            def _read_file_chunks_for_staging(
                self,
                session_id,
                fixture_id,
                relative_path,
                *,
                grant,
                capability,
            ):
                self._require_admitted_capability(capability)
                if relative_path == "game.rom":
                    yield b"different-readback-bytes"
                    return
                yield from super()._read_file_chunks_for_staging(
                    session_id,
                    fixture_id,
                    relative_path,
                    grant=grant,
                    capability=capability,
                )

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=CorruptReadbackDestination
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.COPY_INVALID.value,
        )
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())

    def test_sparse_file_larger_than_legacy_limit_is_capacity_blocked_not_size_capped(self) -> None:
        api = self._require_staging_module()
        size = 512 * 1024 * 1024 + 1
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture["files"][0]["size"] = size
        fixture["files"][0]["sha256"] = "0" * 64
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)
        source_root = self.directory / "source"
        source_root.mkdir(mode=0o700)
        with (source_root / "game.rom").open("wb") as stream:
            stream.truncate(size)
        destination_root = self.directory / "destination"
        destination_root.mkdir(mode=0o700)
        destination = _SyntheticFilesystemFixtureDestination(
            destination_root,
            capability=self.synthetic_capability,
            capacity_observer=lambda _root: api.CapacityObservation(
                2 * 1024 * 1024 * 1024,
                1024 * 1024 * 1024 + size - 1,
            ),
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            self._authorize(),
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.CAPACITY_INSUFFICIENT.value,
        )

    def test_publish_blocker_persistence_failure_reports_destination_unsafe(
        self,
    ) -> None:
        api = self._require_staging_module()
        publish_errors = []

        class FailingPublishDestination(api.FilesystemFixtureDestination):
            def _publish(self, session_id, token, *, grant, **kwargs):
                replace_state = self._ownership._replace_state

                def fail_publication_pending(record, **kwargs):
                    if record.get("state") == "publication_pending":
                        raise api.FixtureStagingError(
                            api.FixtureStagingErrorCode.COPY_INVALID
                        )
                    replace_state(record, **kwargs)

                with patch.object(
                    self._ownership,
                    "_replace_state",
                    side_effect=fail_publication_pending,
                ):
                    try:
                        return super()._publish(
                            session_id, token, grant=grant, **kwargs
                        )
                    except api.FixtureStagingError as error:
                        publish_errors.append(error)
                        raise

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=FailingPublishDestination
        )
        with patch.object(destination._ownership, "mark_blocked", return_value=False):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(
            publish_errors[0].code,
            api.FixtureStagingErrorCode.COPY_INVALID,
        )
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertTrue(
            destination._synthetic_temporary_path(result.session_id).exists()
        )
        self.assertNotEqual(
            destination._ownership._load_state(result.session_id)["state"],
            "blocked",
        )

    def test_destination_root_device_and_inode_must_match(self) -> None:
        api = self._require_staging_module()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        actual = destination.root.stat(follow_symlinks=False)

        with patch(
            "scripts.android_qualification._fixture_staging_destination._validate_private_directory",
            return_value=SimpleNamespace(
                st_dev=actual.st_dev + 1,
                st_ino=actual.st_ino,
            ),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
        )

    def test_authorized_synthetic_cleanup_removes_only_owned_session(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-cleanup-complete",
        )
        sentinel = destination.root / "existing-fixture.bin"
        sentinel.write_bytes(b"preserve")
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        final_root = destination._synthetic_final_path(staged.session_id)
        self.assertTrue(final_root.exists())

        with patch.object(
            destination._ownership,
            "_exclusive_namespace_authority_available",
            return_value=True,
        ):
            cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(
                self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertEqual(cleanup.status, "CLEANUP_COMPLETE")
        self.assertIsNone(cleanup.blocker_code)
        self.assertTrue(cleanup.removed)
        self.assertFalse(final_root.exists())
        self.assertEqual(sentinel.read_bytes(), b"preserve")
        record = destination._ownership._load_state(staged.session_id)
        self.assertEqual(record["state"], "cleanup_complete")
        self.assertIsNone(record["root_device"])
        self.assertIsNone(record["root_inode"])
        self.assertEqual(record["owned_entries"], [])

    def test_explicit_cleanup_blocks_and_retains_only_the_owned_session(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        sentinel = destination.root / "existing-fixture.bin"
        sentinel.write_bytes(b"preserve")
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertFalse(cleanup.removed)
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        self.assertEqual(sentinel.read_bytes(), b"preserve")
        self.assertEqual(
            (destination._synthetic_final_path(staged.session_id) / "fixture-synthetic" / "game.rom").read_bytes(),
            b"synthetic-rom-content-v1",
        )
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["blocker_code"], cleanup.blocker_code)

    def test_cleanup_never_walks_the_tree_without_exclusive_authority(self) -> None:
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
        remove_tree = staging_ownership._remove_tree_contents
        with patch.object(
            staging_ownership,
            "_remove_tree_contents",
            wraps=remove_tree,
        ) as remove_tree_mock:
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
        remove_tree_mock.assert_not_called()
        fixture = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        self.assertEqual(fixture.read_bytes(), b"synthetic-rom-content-v1")

    def test_cleanup_blocks_when_same_user_replaces_proven_path(self) -> None:
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
        path_checked = threading.Barrier(2)
        original_proof = destination._ownership._ownership_is_proven
        proof_paused = [False]
        preserved_root = destination.root / ".same-user-original-session"
        replacement = destination._synthetic_final_path(staged.session_id)

        def prove_then_pause(record, session_id):
            proven = original_proof(record, session_id)
            if proven and not proof_paused[0]:
                proof_paused[0] = True
                path_checked.wait(timeout=5)
                path_checked.wait(timeout=5)
            return proven

        def replace_proven_path():
            path_checked.wait(timeout=5)
            os.rename(replacement, preserved_root)
            replacement.mkdir(mode=0o700)
            (replacement / "foreign.txt").write_bytes(b"same-user replacement")
            path_checked.wait(timeout=5)

        replacer = threading.Thread(target=replace_proven_path)
        with patch.object(
            destination._ownership,
            "_ownership_is_proven",
            side_effect=prove_then_pause,
        ), patch.object(
            staging_ownership,
            "_remove_tree_contents",
            wraps=staging_ownership._remove_tree_contents,
        ) as remove_tree:
            replacer.start()
            cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )
            replacer.join(timeout=5)

        self.assertFalse(replacer.is_alive(), "the replacement barrier did not finish")
        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            "BLOCKED_UNSUPPORTED_EXCLUSIVITY",
        )
        self.assertTrue(preserved_root.exists())
        self.assertTrue(replacement.exists())
        self.assertEqual(
            (replacement / "foreign.txt").read_bytes(), b"same-user replacement"
        )
        self.assertTrue(
            any(preserved_root.rglob("game.rom")),
            "the original fixture tree must remain recoverable",
        )
        remove_tree.assert_not_called()
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["blocker_code"], cleanup.blocker_code)

    def test_cleanup_preserves_untracked_regular_files(self) -> None:
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

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        self.assertEqual(unexpected.read_bytes(), b"preserve")
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_cleanup_refuses_unowned_symlink_without_deleting_it(self) -> None:
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
        outside = self.directory / "outside-do-not-delete.txt"
        outside.write_text("preserve", encoding="utf-8")
        suspicious = destination._synthetic_final_path(staged.session_id) / "foreign-link"
        suspicious.symlink_to(outside)

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
        )
        self.assertEqual(outside.read_text(encoding="utf-8"), "preserve")
        self.assertTrue(suspicious.is_symlink())
        self.assertEqual(destination._ownership.recovery_obligations()[0].state, "blocked")

    def test_public_staging_rejects_caller_monotonic_time_without_mutation(
        self,
    ) -> None:
        self.assertNotIn(
            "monotonic_clock",
            inspect.signature(self.production_stage_fixtures).parameters,
        )
        _, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-caller-clock"
        )
        fixture_path = source_root / "game.rom"
        fixture_bytes = fixture_path.read_bytes()
        before_destination = sorted(
            path.relative_to(destination.root).as_posix()
            for path in destination.root.rglob("*")
        )

        for label, supplied_time in (
            ("historical", 0.0),
            ("future", 10**18),
        ):
            with self.subTest(label=label):
                with self.assertRaisesRegex(TypeError, "monotonic_clock"):
                    self.production_stage_fixtures(
                        grant,
                        source_roots={"fixture-synthetic": source_root},
                        destination=destination,
                        now=NOW,
                        monotonic_clock=lambda value=supplied_time: value,
                    )
                self.assertEqual(fixture_path.read_bytes(), fixture_bytes)
                self.assertEqual(
                    sorted(
                        path.relative_to(destination.root).as_posix()
                        for path in destination.root.rglob("*")
                    ),
                    before_destination,
                )
                self.assertEqual(destination._ownership.recovery_obligations(), ())
                self.assertFalse(
                    (destination.root / destination._STATE_DIRECTORY).exists()
                )

    def test_public_capacity_and_publication_reject_caller_control_without_mutation(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-caller-api-controls"
        )
        fixture_path = source_root / "game.rom"
        fixture_bytes = fixture_path.read_bytes()
        session_id = "0" * 32
        token = "0" * 64
        callback_calls = []

        def callback(_root):
            callback_calls.append("called")
            return api.CapacityObservation(10**12, 10**12)

        self.assertNotIn(
            "capacity_observer",
            inspect.signature(api.FilesystemFixtureDestination).parameters,
        )
        self.assertNotIn(
            "capacity_observer",
            inspect.signature(destination.capacity_observation).parameters,
        )
        self.assertNotIn(
            "now", inspect.signature(destination.publish).parameters
        )
        self.assertNotIn(
            "check_deadline",
            inspect.signature(destination.publish).parameters,
        )
        self.assertNotIn(
            "check_deadline",
            inspect.signature(destination.confirm_publication).parameters,
        )

        with self.assertRaisesRegex(TypeError, "capacity_observer"):
            api.FilesystemFixtureDestination(
                destination.root, capacity_observer=callback
            )
        with self.assertRaisesRegex(TypeError, "capacity_observer"):
            destination.capacity_observation(capacity_observer=callback)
        with self.assertRaisesRegex(TypeError, "now"):
            destination.publish(
                session_id,
                token,
                grant=grant,
                now=NOW,
        )
        with self.assertRaisesRegex(TypeError, "check_deadline"):
            destination.confirm_publication(
                session_id,
                token,
                grant=grant,
                check_deadline=lambda: None,
        )

        public_destination = api.FilesystemFixtureDestination(destination.root)
        with self.assertRaises(api.FixtureStagingError) as raised:
            public_destination.capacity_observation()
        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )
        self.assertEqual(callback_calls, [])
        self.assertEqual(fixture_path.read_bytes(), fixture_bytes)
        self.assertEqual(list(destination.root.iterdir()), [])
        self.assertEqual(destination._ownership.recovery_obligations(), ())

    def test_destination_namespace_race_blocks_before_capacity_or_any_mutation(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-namespace-race"
        )
        fixture_path = source_root / "game.rom"
        fixture_bytes = fixture_path.read_bytes()
        fixture_stat = fixture_path.stat()
        fixture_identity = (
            fixture_stat.st_dev,
            fixture_stat.st_ino,
            fixture_stat.st_size,
            fixture_stat.st_mtime_ns,
        )
        moved_destination = source_root / "redirected-destination" / "root"
        original_preflight = _fixture_staging_transfer._preflight_sources
        original_ensure_capacity = _fixture_staging_transfer._ensure_capacity
        original_admission = (
            _fixture_staging_orchestration._admit_production_staging_namespace
        )
        events: list[str] = []
        capacity_observations: list[object] = []
        def preflight_then_move_namespace(*args, **kwargs):
            result = original_preflight(*args, **kwargs)
            events.append("preflight")
            moved_destination.parent.mkdir(mode=0o700)
            os.rename(destination.root, moved_destination)
            destination.root.symlink_to(moved_destination, target_is_directory=True)
            events.append("destination-ancestor-moved")
            return result

        def admission_before_capacity(*args, **kwargs):
            events.append("admission")
            original_admission()
            return original_ensure_capacity(*args, **kwargs)

        with (
            patch.object(
                _fixture_staging_transfer,
                "_preflight_sources",
                side_effect=preflight_then_move_namespace,
            ),
            patch.object(
                _fixture_staging_orchestration,
                "_ensure_capacity",
                side_effect=admission_before_capacity,
            ),
            patch.object(
                staging_ownership.FixtureStagingOwnership,
                "reserve_session",
                autospec=True,
            ) as reserve_session,
            patch.object(
                staging_ownership.FixtureStagingOwnership,
                "coordination_lock",
                autospec=True,
            ) as coordination_lock,
            patch.object(
                api.FilesystemFixtureDestination,
                "_create_quarantine",
                autospec=True,
            ) as create_quarantine,
            patch.object(
                api.FilesystemFixtureDestination,
                "_write_file",
                autospec=True,
            ) as write_file,
            patch.object(
                api.FilesystemFixtureDestination,
                "_publish_and_confirm",
                autospec=True,
            ) as publish_and_confirm,
            patch.object(
                staging_destination.shutil,
                "disk_usage",
                side_effect=lambda root: capacity_observations.append(root),
            ),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(
                self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(
            events,
            ["preflight", "destination-ancestor-moved", "admission"],
        )
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertEqual(result.session_id, "")
        self.assertEqual(capacity_observations, [])
        reserve_session.assert_not_called()
        coordination_lock.assert_not_called()
        create_quarantine.assert_not_called()
        write_file.assert_not_called()
        publish_and_confirm.assert_not_called()
        self.assertEqual(fixture_path.read_bytes(), fixture_bytes)
        after_stat = fixture_path.stat()
        self.assertEqual(
            (
                after_stat.st_dev,
                after_stat.st_ino,
                after_stat.st_size,
                after_stat.st_mtime_ns,
            ),
            fixture_identity,
        )
        self.assertEqual(list(moved_destination.iterdir()), [])
        self.assertFalse((moved_destination / destination._STATE_DIRECTORY).exists())

    def test_direct_staging_impl_cannot_disable_exclusive_admission(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-direct-stage-admission"
        )
        production_destination = api.FilesystemFixtureDestination(destination.root)
        parameters = inspect.signature(
            _fixture_staging_orchestration._stage_fixtures_impl
        ).parameters
        self.assertNotIn("require_exclusive_namespace", parameters)

        capacity_observations: list[object] = []
        with ExitStack() as stack:
            reserve_session = stack.enter_context(
                patch.object(
                    staging_ownership.FixtureStagingOwnership,
                    "reserve_session",
                    autospec=True,
                )
            )
            coordination_lock = stack.enter_context(
                patch.object(
                    staging_ownership.FixtureStagingOwnership,
                    "coordination_lock",
                    autospec=True,
                )
            )
            replace_state = stack.enter_context(
                patch.object(
                    staging_ownership.FixtureStagingOwnership,
                    "_replace_state",
                    autospec=True,
                )
            )
            create_quarantine = stack.enter_context(
                patch.object(
                    api.FilesystemFixtureDestination,
                    "_create_quarantine",
                    autospec=True,
                )
            )
            write_file = stack.enter_context(
                patch.object(
                    api.FilesystemFixtureDestination,
                    "_write_file",
                    autospec=True,
                )
            )
            publish_and_confirm = stack.enter_context(
                patch.object(
                    api.FilesystemFixtureDestination,
                    "_publish_and_confirm",
                    autospec=True,
                )
            )

            with patch.object(
                staging_destination.shutil,
                "disk_usage",
                side_effect=lambda root: capacity_observations.append(root),
            ):
                result = _fixture_staging_orchestration._stage_fixtures_impl(
                    grant,
                    source_roots={"fixture-synthetic": source_root},
                    destination=production_destination,
                )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertEqual(capacity_observations, [])
        reserve_session.assert_not_called()
        coordination_lock.assert_not_called()
        replace_state.assert_not_called()
        create_quarantine.assert_not_called()
        write_file.assert_not_called()
        publish_and_confirm.assert_not_called()
        self.assertFalse((destination.root / destination._STATE_DIRECTORY).exists())

    def test_direct_publish_and_confirm_blocks_before_state_or_mutation(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-direct-publication-admission"
        )
        session_id = "0" * 32
        token = "0" * 64

        with ExitStack() as stack:
            coordination_lock = stack.enter_context(
                patch.object(
                    destination._ownership,
                    "coordination_lock",
                    wraps=destination._ownership.coordination_lock,
                )
            )
            load_state = stack.enter_context(
                patch.object(
                    destination._ownership,
                    "_load_state",
                    wraps=destination._ownership._load_state,
                )
            )
            replace_state = stack.enter_context(
                patch.object(
                    destination._ownership,
                    "_replace_state",
                    wraps=destination._ownership._replace_state,
                )
            )
            publish = stack.enter_context(
                patch.object(destination, "_publish", wraps=destination._publish)
            )
            confirm_publication = stack.enter_context(
                patch.object(
                    destination,
                    "_confirm_publication",
                    wraps=destination._confirm_publication,
                )
            )

            with self.assertRaises(api.FixtureStagingError) as raised:
                destination._publish_and_confirm(
                    session_id,
                    token,
                    grant=grant,
                )

        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )
        coordination_lock.assert_not_called()
        load_state.assert_not_called()
        replace_state.assert_not_called()
        publish.assert_not_called()
        confirm_publication.assert_not_called()
        self.assertFalse((destination.root / destination._STATE_DIRECTORY).exists())

    def test_exported_destination_mutations_fail_closed_before_mutation(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-exported-mutations"
        )
        session_id = "0" * 32
        token = "0" * 64
        source_path = source_root / "game.rom"
        source_bytes = source_path.read_bytes()

        def tree_state() -> object:
            root_info = destination.root.lstat()
            entries: dict[str, object] = {
                ".": (
                    "directory",
                    root_info.st_dev,
                    root_info.st_ino,
                    root_info.st_mode,
                    root_info.st_mtime_ns,
                )
            }
            for path in sorted(destination.root.rglob("*")):
                relative = path.relative_to(destination.root).as_posix()
                info = path.lstat()
                common = (
                    info.st_dev,
                    info.st_ino,
                    info.st_mode,
                    info.st_size,
                    info.st_mtime_ns,
                )
                if stat.S_ISLNK(info.st_mode):
                    entries[relative] = ("symlink", os.readlink(path), *common)
                elif stat.S_ISDIR(info.st_mode):
                    entries[relative] = ("directory", *common)
                elif stat.S_ISREG(info.st_mode):
                    entries[relative] = ("file", path.read_bytes(), *common)
                else:
                    entries[relative] = ("other", *common)
            return entries

        calls = (
            (
                "create_quarantine",
            lambda: destination.create_quarantine(session_id, token, grant),
            ),
            (
                "write_file",
                lambda: destination.write_file(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    iter(()),
                    ownership_token=token,
                    source_mtime_ns=0,
                ),
            ),
            (
                "publish",
            lambda: destination.publish(session_id, token, grant=grant),
            ),
            (
                "confirm_publication",
            lambda: destination.confirm_publication(session_id, token, grant=grant),
            ),
        )
        before_tree = tree_state()
        with ExitStack() as stack:
            create_quarantine = stack.enter_context(
                patch.object(destination, "_create_quarantine")
            )
            write_file = stack.enter_context(
                patch.object(destination, "_write_file")
            )
            publish = stack.enter_context(
                patch.object(destination, "_publish")
            )
            confirm_publication = stack.enter_context(
                patch.object(destination, "_confirm_publication")
            )
            coordination_lock = stack.enter_context(
                patch.object(destination._ownership, "coordination_lock")
            )
            reserve_session = stack.enter_context(
                patch.object(destination._ownership, "reserve_session")
            )
            load_state = stack.enter_context(
                patch.object(destination._ownership, "_load_state")
            )
            replace_state = stack.enter_context(
                patch.object(destination._ownership, "_replace_state")
            )
            write_state = stack.enter_context(
                patch.object(destination._ownership, "_write_private_json_exclusive")
            )
            record_owned_entry = stack.enter_context(
                patch.object(destination._ownership, "_record_owned_entry")
            )
            open_owned_root = stack.enter_context(
                patch.object(destination._ownership, "_open_owned_root")
            )
            remove_owned_session = stack.enter_context(
                patch.object(destination._ownership, "remove_owned_session")
            )
            mark_blocked = stack.enter_context(
                patch.object(destination._ownership, "mark_blocked")
            )
            mark_blocked_or_destination_unsafe = stack.enter_context(
                patch.object(destination._ownership, "mark_blocked_or_destination_unsafe")
            )
            os_open = stack.enter_context(
                patch.object(staging_destination.os, "open")
            )
            os_mkdir = stack.enter_context(
                patch.object(staging_destination.os, "mkdir")
            )
            os_rename = stack.enter_context(
                patch.object(staging_destination.os, "rename")
            )
            os_replace = stack.enter_context(
                patch.object(staging_destination.os, "replace")
            )
            os_unlink = stack.enter_context(
                patch.object(staging_destination.os, "unlink")
            )
            os_remove = stack.enter_context(
                patch.object(staging_destination.os, "remove")
            )
            os_rmdir = stack.enter_context(
                patch.object(staging_destination.os, "rmdir")
            )
            os_write = stack.enter_context(
                patch.object(staging_destination.os, "write")
            )
            os_ftruncate = stack.enter_context(
                patch.object(staging_destination.os, "ftruncate")
            )
            os_fsync = stack.enter_context(
                patch.object(staging_destination.os, "fsync")
            )
            for surface, invoke in calls:
                with self.subTest(surface=surface):
                    with self.assertRaises(api.FixtureStagingError) as caught:
                        invoke()
                    self.assertEqual(
                        caught.exception.code,
                        api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                    )

            self.assertEqual(tree_state(), before_tree)
            self.assertEqual(source_path.read_bytes(), source_bytes)

            for operation in (
                create_quarantine,
                write_file,
                publish,
                confirm_publication,
                coordination_lock,
                reserve_session,
                load_state,
                replace_state,
                write_state,
                record_owned_entry,
                open_owned_root,
                remove_owned_session,
                mark_blocked,
                mark_blocked_or_destination_unsafe,
                os_open,
                os_mkdir,
                os_rename,
                os_replace,
                os_unlink,
                os_remove,
                os_rmdir,
                os_write,
                os_ftruncate,
                os_fsync,
            ):
                operation.assert_not_called()

    def test_private_stage_impl_rejects_caller_clock_before_callback(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-private-clock"
        )
        fixture = source_root / "game.rom"
        fixture_bytes = fixture.read_bytes()
        callback_calls = []

        with self.assertRaisesRegex(TypeError, "monotonic_clock"):
            _fixture_staging_orchestration._stage_fixtures_impl(
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                monotonic_clock=lambda: callback_calls.append("called"),
            )

        self.assertEqual(callback_calls, [])
        self.assertEqual(fixture.read_bytes(), fixture_bytes)
        self.assertEqual(list(destination.root.iterdir()), [])
        self.assertFalse(
            (destination.root / destination._STATE_DIRECTORY).exists()
        )
        self.assertNotIn("now", inspect.signature(destination._publish).parameters)
        self.assertNotIn(
            "check_deadline",
            inspect.signature(destination._publish).parameters,
        )
        self.assertNotIn(
            "check_deadline",
            inspect.signature(destination._confirm_publication).parameters,
        )
        self.assertNotIn(
            "check_deadline",
            inspect.signature(destination._publish_and_confirm).parameters,
        )

    def test_private_mutation_helpers_require_capability_before_state(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-private-capability"
        )
        fixture = source_root / "game.rom"
        fixture_bytes = fixture.read_bytes()
        before_paths = sorted(path.name for path in destination.root.iterdir())
        session_id = "0" * 32
        token = "0" * 64
        operations = (
            lambda: destination._ownership.reserve_session(grant),
            lambda: destination._ownership._replace_state({}),
            lambda: destination._ownership._write_private_json_exclusive(
                destination.root / "state.json", {}
            ),
            lambda: destination._create_quarantine(session_id, token, grant),
            lambda: destination._write_file(
                session_id,
                "fixture-synthetic",
                "game.rom",
                iter(()),
                ownership_token=token,
                source_mtime_ns=0,
                grant=grant,
            ),
            lambda: destination._publish(session_id, token, grant=grant),
            lambda: destination._confirm_publication(
                session_id, token, grant=grant
            ),
            lambda: destination._publish_and_confirm(
                session_id, token, grant=grant
            ),
            lambda: destination._ownership.remove_owned_session(
                session_id, token, grant=grant
            ),
            lambda: staging_ownership._rename_entry_exclusive(-1, "a", -1, "b"),
            lambda: staging_ownership._publish_json_exclusive(
                destination.root / "a", destination.root / "b", b"{}"
            ),
        )

        for operation in operations:
            with self.subTest(operation=operation):
                with self.assertRaises(api.FixtureStagingError) as raised:
                    operation()
                self.assertEqual(
                    raised.exception.code,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )

        self.assertEqual(fixture.read_bytes(), fixture_bytes)
        self.assertEqual(
            sorted(path.name for path in destination.root.iterdir()),
            before_paths,
        )
        self.assertFalse(
            (destination.root / destination._STATE_DIRECTORY).exists()
        )

    def test_private_mutations_reject_cross_owner_and_wrong_thread_before_lock(
        self,
    ) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-private-mutation-authority",
        )
        ownership = destination._ownership
        session_id, token = ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        before_paths = sorted(
            path.relative_to(destination.root)
            for path in destination.root.rglob("*")
        )
        cross_owner_capability = staging_ownership._issue_synthetic_namespace_capability(
            owner=object(),
        )
        chunk_iterations = []

        class Chunks:
            def __iter__(self):
                chunk_iterations.append(True)
                yield b"synthetic-rom-content-v1"

        def operations(capability):
            return (
                lambda: destination._create_quarantine(
                    session_id,
                    token,
                    grant,
                    capability=capability,
                ),
                lambda: destination._write_file(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    Chunks(),
                    ownership_token=token,
                    source_mtime_ns=0,
                    grant=grant,
                    capability=capability,
                ),
                lambda: destination._publish(
                    session_id,
                    token,
                    grant=grant,
                    capability=capability,
                ),
                lambda: destination._confirm_publication(
                    session_id,
                    token,
                    grant=grant,
                    capability=capability,
                ),
                lambda: destination._publish_and_confirm(
                    session_id,
                    token,
                    grant=grant,
                    capability=capability,
                ),
            )

        with (
            patch.object(ownership, "coordination_lock") as coordination_lock,
            patch.object(ownership, "_load_state") as load_state,
            patch.object(ownership, "_open_owned_root") as open_owned_root,
            patch.object(ownership, "_replace_state") as replace_state,
            patch.object(ownership, "_record_owned_entry") as record_entry,
        ):
            for invalid_capability in (object(), cross_owner_capability):
                for operation in operations(invalid_capability):
                    with self.subTest(
                        capability=type(invalid_capability).__name__,
                        operation=operation,
                    ):
                        with self.assertRaises(api.FixtureStagingError) as raised:
                            operation()
                        self.assertEqual(
                            raised.exception.code,
                            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                        )

            thread_errors = []

            def invoke_from_wrong_thread() -> None:
                try:
                    destination._publish(
                        session_id,
                        token,
                        grant=grant,
                        capability=self.synthetic_capability,
                    )
                except api.FixtureStagingError as error:
                    thread_errors.append(error.code)

            worker = threading.Thread(target=invoke_from_wrong_thread)
            worker.start()
            worker.join(timeout=5)
            self.assertFalse(worker.is_alive())
            self.assertEqual(
                thread_errors,
                [api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY],
            )
            coordination_lock.assert_not_called()
            load_state.assert_not_called()
            open_owned_root.assert_not_called()
            replace_state.assert_not_called()
            record_entry.assert_not_called()

        self.assertEqual(chunk_iterations, [])
        self.assertEqual(
            sorted(
                path.relative_to(destination.root)
                for path in destination.root.rglob("*")
            ),
            before_paths,
        )

    def test_transfer_helpers_validate_exact_capability_before_source_or_callbacks(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-transfer-capability-ordering",
        )
        snapshots, total_bytes = _fixture_staging_transfer._preflight_sources(
            grant._fixture_expectations,
            {"fixture-synthetic": source_root},
            destination.root,
        )
        source_path = source_root / "game.rom"
        source_bytes = source_path.read_bytes()
        cross_owner_capability = staging_ownership._issue_synthetic_namespace_capability(
            owner=object(),
        )

        def assert_rejected(capability) -> None:
            callbacks = []
            with (
                patch.object(
                    _fixture_staging_transfer,
                    "_open_source_member",
                ) as open_source,
                patch.object(
                    _fixture_staging_transfer,
                    "_ensure_capacity",
                ) as ensure_capacity,
                patch.object(
                    destination,
                    "_write_file",
                ) as write_file,
                patch.object(
                    destination._ownership,
                    "_load_state",
                ) as load_state,
                patch.object(
                    destination._ownership,
                    "_open_owned_root",
                ) as open_owned_root,
            ):
                with self.assertRaises(api.FixtureStagingError) as stream_error:
                    next(
                        _fixture_staging_transfer._stream_source(
                            snapshots[0],
                            destination=destination,
                            grant=grant,
                            total_bytes=total_bytes,
                            copied_bytes=[0],
                            check_deadline=lambda: callbacks.append("deadline"),
                            cancellation=lambda: callbacks.append("cancellation")
                            or False,
                            capability=capability,
                        )
                    )
                with self.assertRaises(api.FixtureStagingError) as transfer_error:
                    _fixture_staging_transfer._transfer_and_verify_fixture_set(
                        snapshots,
                        destination=destination,
                        grant=grant,
                        session_id="0" * 32,
                        ownership_token="0" * 64,
                        total_bytes=total_bytes,
                        copied_bytes=[0],
                        verified_bytes=[0],
                        check_deadline=lambda: callbacks.append("deadline"),
                        cancellation=lambda: callbacks.append("cancellation")
                        or False,
                        capability=capability,
                    )

                self.assertEqual(
                    stream_error.exception.code,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )
                self.assertEqual(
                    transfer_error.exception.code,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )
                open_source.assert_not_called()
                ensure_capacity.assert_not_called()
                write_file.assert_not_called()
                load_state.assert_not_called()
                open_owned_root.assert_not_called()
                self.assertEqual(callbacks, [])

        assert_rejected(None)
        assert_rejected(object())
        assert_rejected(cross_owner_capability)

        thread_errors = []
        callbacks = []
        with patch.object(
            _fixture_staging_transfer,
            "_open_source_member",
        ) as open_source:

            def invoke_from_wrong_thread() -> None:
                try:
                    _fixture_staging_transfer._transfer_and_verify_fixture_set(
                        snapshots,
                        destination=destination,
                        grant=grant,
                        session_id="0" * 32,
                        ownership_token="0" * 64,
                        total_bytes=total_bytes,
                        copied_bytes=[0],
                        verified_bytes=[0],
                        check_deadline=lambda: callbacks.append("deadline"),
                        capability=self.synthetic_capability,
                    )
                except api.FixtureStagingError as error:
                    thread_errors.append(error.code)

            worker = threading.Thread(target=invoke_from_wrong_thread)
            worker.start()
            worker.join(timeout=5)
            self.assertFalse(worker.is_alive())
            self.assertEqual(
                thread_errors,
                [api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY],
            )
            open_source.assert_not_called()
            self.assertEqual(callbacks, [])
        self.assertEqual(source_path.read_bytes(), source_bytes)

    def test_transfer_helpers_reject_expiry_before_source_or_callbacks(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-transfer-expiry-ordering",
        )
        snapshots, total_bytes = _fixture_staging_transfer._preflight_sources(
            grant._fixture_expectations,
            {"fixture-synthetic": source_root},
            destination.root,
        )
        self.staging_now[0] = grant._authorization.session_deadline
        callbacks = []
        with (
            patch.object(
                _fixture_staging_transfer,
                "_open_source_member",
            ) as open_source,
            patch.object(
                _fixture_staging_transfer,
                "_ensure_capacity",
            ) as ensure_capacity,
            patch.object(destination, "_write_file") as write_file,
        ):
            with self.assertRaises(api.FixtureStagingError) as stream_error:
                next(
                    _fixture_staging_transfer._stream_source(
                        snapshots[0],
                        destination=destination,
                        grant=grant,
                        total_bytes=total_bytes,
                        copied_bytes=[0],
                        check_deadline=lambda: callbacks.append("deadline"),
                        cancellation=lambda: callbacks.append("cancellation")
                        or False,
                        capability=self.synthetic_capability,
                    )
                )
            with self.assertRaises(api.FixtureStagingError) as transfer_error:
                _fixture_staging_transfer._transfer_and_verify_fixture_set(
                    snapshots,
                    destination=destination,
                    grant=grant,
                    session_id="0" * 32,
                    ownership_token="0" * 64,
                    total_bytes=total_bytes,
                    copied_bytes=[0],
                    verified_bytes=[0],
                    check_deadline=lambda: callbacks.append("deadline"),
                    capability=self.synthetic_capability,
                )
            self.assertEqual(
                stream_error.exception.code,
                api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
            )
            self.assertEqual(
                transfer_error.exception.code,
                api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
            )
            open_source.assert_not_called()
            ensure_capacity.assert_not_called()
            write_file.assert_not_called()
            self.assertEqual(callbacks, [])

    def test_private_read_and_path_helpers_reject_capability_before_filesystem(
        self,
    ) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-private-read-capability",
        )
        invalid_capability = object()
        callbacks = []
        with (
            patch.object(
                destination._ownership,
                "_load_state",
            ) as load_state,
            patch.object(
                destination._ownership,
                "_open_owned_root",
            ) as open_owned_root,
            patch.object(
                staging_destination,
                "_open_destination_parent",
            ) as open_destination_parent,
            patch.object(
                destination,
                "capacity_observation",
            ) as capacity_observation,
        ):
            private_calls = (
                lambda: destination._final_path(
                    "0" * 32,
                    grant=grant,
                    capability=invalid_capability,
                ),
                lambda: destination._temporary_path(
                    "0" * 32,
                    grant=grant,
                    capability=invalid_capability,
                ),
                lambda: destination._file_mtime_ns(
                    "0" * 32,
                    "fixture-synthetic",
                    "game.rom",
                    grant=grant,
                    capability=invalid_capability,
                ),
                lambda: next(
                    destination._read_file_chunks(
                        "0" * 32,
                        "fixture-synthetic",
                        "game.rom",
                        grant=grant,
                        capability=invalid_capability,
                    )
                ),
            )
            for private_call in private_calls:
                with self.assertRaises(api.FixtureStagingError) as raised:
                    private_call()
                self.assertEqual(
                    raised.exception.code,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )

            with self.assertRaises(api.FixtureStagingError) as capacity_error:
                _fixture_staging_transfer._ensure_capacity(
                    destination,
                    grant,
                    1,
                    check_deadline=lambda: callbacks.append("deadline"),
                    capability=invalid_capability,
                )
            self.assertEqual(
                capacity_error.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )
            load_state.assert_not_called()
            open_owned_root.assert_not_called()
            open_destination_parent.assert_not_called()
            capacity_observation.assert_not_called()
            self.assertEqual(callbacks, [])

            load_state.reset_mock()
            open_owned_root.reset_mock()
            open_destination_parent.reset_mock()
            unsupported_access = cast(
                Literal["published", "staging"],
                "unsupported",
            )
            for helper_call in (
                lambda: next(
                    destination._read_file_chunks_from_owned_root(
                        "0" * 32,
                        "fixture-synthetic",
                        "game.rom",
                        grant=grant,
                        capability=self.synthetic_capability,
                        access=unsupported_access,
                    )
                ),
                lambda: destination._file_mtime_ns_from_owned_root(
                    "0" * 32,
                    "fixture-synthetic",
                    "game.rom",
                    grant=grant,
                    capability=self.synthetic_capability,
                    access=unsupported_access,
                ),
            ):
                with self.assertRaises(api.FixtureStagingError) as raised:
                    helper_call()
                self.assertEqual(
                    raised.exception.code,
                    api.FixtureStagingErrorCode.INVALID_AUTHORITY,
                )
            load_state.assert_not_called()
            open_owned_root.assert_not_called()
            open_destination_parent.assert_not_called()

    def test_synthetic_capability_cannot_cross_threads_or_admit_production(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-thread-capability"
        )
        failures = []
        production_destination = api.FilesystemFixtureDestination(destination.root)
        copied_context = contextvars.copy_context()
        capacity_types = []

        def observe_capacity_with_copied_context():
            calls = (
                ("capacity", production_destination.capacity_observation),
                (
                    "eligible_root",
                    lambda: destination._eligible_root_impl(
                        "0" * 32,
                        grant=grant,
                        capability=destination._synthetic_capability,
                    ),
                ),
            )
            for name, invoke in calls:
                try:
                    capacity_types.append(type(invoke()))
                except api.FixtureStagingError as error:
                    failures.append((name, error.code))

        thread = threading.Thread(
            target=copied_context.run,
            args=(observe_capacity_with_copied_context,),
        )
        thread.start()
        thread.join(timeout=5)
        self.assertFalse(thread.is_alive())

        self.assertEqual(
            failures,
            [
                (
                    "capacity",
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                ),
                (
                    "eligible_root",
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                ),
            ],
        )
        self.assertEqual(capacity_types, [])
        with self.assertRaises(TypeError):
            destination.capacity_observation(capability=self.synthetic_capability)
        with self.assertRaises(api.FixtureStagingError) as raised:
            production_destination._require_admitted_capability(
                self.synthetic_capability
            )
        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )
        self.assertFalse(
            (destination.root / destination._STATE_DIRECTORY).exists()
        )

    def test_capability_rejects_new_thread_with_reused_numeric_identifier(self) -> None:
        api = self._require_staging_module()
        owner = object()
        reused_identifier = threading.get_ident() + 10_000
        original_thread = threading.Thread(name="capability-original")
        replacement_thread = threading.Thread(name="capability-replacement")
        original_thread._ident = reused_identifier
        replacement_thread._ident = reused_identifier

        with (
            patch.object(
                staging_ownership.threading,
                "get_ident",
                return_value=reused_identifier,
            ),
            patch.object(
                staging_ownership.threading,
                "current_thread",
                return_value=original_thread,
            ),
        ):
            capability = (
                staging_ownership._issue_synthetic_namespace_capability(owner=owner)
            )

        with (
            patch.object(
                staging_ownership.threading,
                "get_ident",
                return_value=reused_identifier,
            ),
            patch.object(
                staging_ownership.threading,
                "current_thread",
                return_value=replacement_thread,
            ),
        ):
            with self.assertRaises(api.FixtureStagingError) as raised:
                staging_ownership._require_namespace_capability(
                    capability,
                    origin="synthetic",
                    owner=owner,
                )

        self.assertEqual(original_thread.ident, replacement_thread.ident)
        self.assertIs(capability._thread_identity(), original_thread)
        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )

    def test_capability_is_immutable_owner_bound_and_inert_for_production(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-capability-ownership",
        )
        capability = destination._synthetic_capability
        production_root = self.directory / "production-capability-root"
        production_root.mkdir(mode=0o700)
        factory_calls = []
        production_ownership = staging_ownership.FixtureStagingOwnership(
            production_root,
            session_id_factory=lambda: factory_calls.append(True) or "a" * 32,
        )

        self.assertFalse(
            hasattr(staging_ownership, "_CAPABILITY_CONSTRUCTION_KEY")
        )
        with self.assertRaises(AttributeError):
            capability._capability_owner = object()
        with self.assertRaises(AttributeError):
            del capability.origin
        with self.assertRaises(TypeError):
            class ForgedCapability(type(capability)):
                pass
        with self.assertRaises(TypeError):
            type(capability)(
                owner=object(),
                monotonic_clock=None,
                construction_key=object(),
            )

        other_owner = object()
        cross_owner = staging_ownership._issue_synthetic_namespace_capability(
            owner=other_owner,
            monotonic_clock=capability.monotonic_clock,
        )
        forged_capabilities = (capability, cross_owner, object())

        with (
            patch.object(production_ownership, "coordination_lock") as lock,
            patch.object(production_ownership, "_load_state") as load_state,
            patch.object(production_ownership, "_replace_state") as replace_state,
            patch.object(
                staging_ownership,
                "_validate_private_directory",
            ) as validate_directory,
        ):
            for forged in forged_capabilities:
                with self.subTest(capability=type(forged).__name__):
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        production_ownership.reserve_session(
                            grant,
                            capability=forged,
                        )
                    self.assertEqual(
                        raised.exception.code,
                        api.FixtureStagingErrorCode
                        .BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                    )
            lock.assert_not_called()
            load_state.assert_not_called()
            replace_state.assert_not_called()
            validate_directory.assert_not_called()

        with self.assertRaises(api.FixtureStagingError) as raised:
            destination._ownership.reserve_session(
                grant,
                capability=cross_owner,
            )
        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )
        self.assertEqual(factory_calls, [])
        self.assertEqual(list(production_root.iterdir()), [])
        self.assertFalse(
            (destination.root / destination._STATE_DIRECTORY).exists()
        )

    def test_capability_rewrite_attempts_cannot_retarget_authority(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-capability-rewrite",
        )
        capability = destination._synthetic_capability
        original_owner = capability._owner_identity()
        original_clock = capability.monotonic_clock
        wrong_owner = object()
        rewrite_attempts = (
            ("_owner", wrong_owner),
            ("_thread", threading.current_thread()),
            ("_capability_owner", wrong_owner),
            ("_capability_thread_ident", threading.get_ident() + 1),
            ("_capability_monotonic_clock", lambda: 0.0),
            ("_owner_identity", wrong_owner),
            ("_thread_identity", threading.get_ident() + 1),
        )

        with (
            patch.object(destination._ownership, "coordination_lock") as lock,
            patch.object(destination._ownership, "_load_state") as load_state,
            patch.object(destination._ownership, "_replace_state") as replace_state,
            patch.object(
                staging_ownership,
                "_validate_private_directory",
            ) as validate_directory,
        ):
            for attribute, replacement in rewrite_attempts:
                with self.subTest(attribute=attribute):
                    with self.assertRaises(AttributeError):
                        object.__setattr__(capability, attribute, replacement)

            staging_ownership._require_namespace_capability(
                capability,
                origin="synthetic",
                owner=original_owner,
            )
            with self.assertRaises(api.FixtureStagingError) as raised:
                staging_ownership._require_namespace_capability(
                    capability,
                    origin="production",
                )
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )
            with self.assertRaises(api.FixtureStagingError) as raised:
                staging_ownership._require_namespace_capability(
                    capability,
                    origin="synthetic",
                    owner=wrong_owner,
                )
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )
            cross_owner = staging_ownership._issue_synthetic_namespace_capability(
                owner=wrong_owner,
            )
            with self.assertRaises(api.FixtureStagingError) as raised:
                destination._ownership.reserve_session(
                    grant,
                    capability=cross_owner,
                )
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )

            lock.assert_not_called()
            load_state.assert_not_called()
            replace_state.assert_not_called()
            validate_directory.assert_not_called()

        self.assertIs(capability.monotonic_clock, original_clock)
        self.assertIs(capability._owner_identity(), original_owner)
        self.assertIs(capability._thread_identity(), threading.current_thread())
        self.assertFalse(
            (destination.root / destination._STATE_DIRECTORY).exists()
        )

    def test_capability_rejects_forged_copy_pickle_and_new_instances(self) -> None:
        _api, _source_root, destination, _grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-capability-forgery",
        )
        capability = destination._synthetic_capability
        owner = capability._owner_identity()

        with self.assertRaises(TypeError):
            staging_ownership._issue_synthetic_namespace_capability(owner=None)
        with self.assertRaises(TypeError):
            staging_ownership._issue_synthetic_namespace_capability(
                owner=object(),
                monotonic_clock=object(),
            )

        copied = copy.copy(capability)
        deep_copied = copy.deepcopy(capability)
        with self.assertRaises((pickle.PicklingError, AttributeError)):
            pickle.dumps(capability)
        unregistered = object.__new__(type(capability))
        for forged in (object(), unregistered, copied, deep_copied):
            with self.subTest(forged=type(forged).__name__):
                if type(forged) is type(capability):
                    with self.assertRaises(AttributeError):
                        object.__setattr__(
                            forged,
                            "_capability_owner",
                            object(),
                        )
                with self.assertRaises(staging_ownership.FixtureStagingError) as raised:
                    staging_ownership._require_namespace_capability(
                        forged,
                        origin="synthetic",
                        owner=owner,
                    )
                self.assertEqual(
                    raised.exception.code,
                    staging_ownership.FixtureStagingErrorCode
                    .BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )

        with self.assertRaises(TypeError):
            class SubclassCapability(type(capability)):
                pass

    def test_public_eligibility_and_raw_readback_require_public_admission(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-eligibility-states",
        )
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
        )
        self.assertEqual(staged.status, "VERIFIED_FIXTURE")
        self.assertFalse(hasattr(destination, "read_file_chunks"))
        self.assertIsNone(destination.eligible_root(staged.session_id, grant=grant))

        private_surface_names = (
            "final_root",
            "temporary_root",
            "file_mtime_ns",
        )

        def assert_raw_paths_are_private() -> None:
            for surface_name in private_surface_names:
                self.assertFalse(
                    hasattr(api.FilesystemFixtureDestination, surface_name)
                )
                self.assertFalse(hasattr(destination, surface_name))

        assert_raw_paths_are_private()
        self.assertEqual(
            destination._synthetic_eligible_root(staged.session_id, grant=grant),
            destination._synthetic_final_path(staged.session_id),
        )

        for state in ("publication_pending", "blocked"):
            record = destination._ownership._load_state(staged.session_id)
            record["state"] = state
            destination._ownership._replace_state(
                record,
                capability=self.synthetic_capability,
            )
            self.assertIsNone(
                destination._synthetic_eligible_root(
                    staged.session_id,
                    grant=grant,
                )
            )
            assert_raw_paths_are_private()

        record = destination._ownership._load_state(staged.session_id)
        record["state"] = "published"
        destination._ownership._replace_state(
            record,
            capability=self.synthetic_capability,
        )
        wrong_grant = copy.copy(grant)
        object.__setattr__(wrong_grant, "authorization_sha256", "0" * 64)
        self.assertIsNone(
            destination._synthetic_eligible_root(
                staged.session_id,
                grant=wrong_grant,
            )
        )
        assert_raw_paths_are_private()

        self.staging_now[0] = grant._approval.valid_until
        self.assertIsNone(
            destination._synthetic_eligible_root(
                staged.session_id,
                grant=grant,
            )
        )
        assert_raw_paths_are_private()
        self.assertIsNone(destination.eligible_root(staged.session_id, grant=grant))

    def test_private_eligibility_readback_is_gated_by_current_publication(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-eligibility-readback",
        )
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
        )
        self.assertEqual(staged.status, "VERIFIED_FIXTURE")

        with patch.object(
            destination,
            "_read_file_chunks",
            wraps=destination._read_file_chunks,
        ) as read_file_chunks:
            self.assertEqual(
                destination._synthetic_eligible_root(
                    staged.session_id,
                    grant=grant,
                ),
                destination._synthetic_final_path(staged.session_id),
            )
            self.assertGreaterEqual(read_file_chunks.call_count, 1)

            for state in ("publication_pending", "blocked"):
                record = destination._ownership._load_state(staged.session_id)
                record["state"] = state
                destination._ownership._replace_state(
                    record,
                    capability=self.synthetic_capability,
                )
                read_file_chunks.reset_mock()
                self.assertIsNone(
                    destination._synthetic_eligible_root(
                        staged.session_id,
                        grant=grant,
                    )
                )
                read_file_chunks.assert_not_called()

            record = destination._ownership._load_state(staged.session_id)
            record["state"] = "published"
            destination._ownership._replace_state(
                record,
                capability=self.synthetic_capability,
            )
            wrong_grant = copy.copy(grant)
            object.__setattr__(wrong_grant, "authorization_sha256", "0" * 64)
            read_file_chunks.reset_mock()
            self.assertIsNone(
                destination._synthetic_eligible_root(
                    staged.session_id,
                    grant=wrong_grant,
                )
            )
            read_file_chunks.assert_not_called()

            self.staging_now[0] = grant._approval.valid_until
            read_file_chunks.reset_mock()
            self.assertIsNone(
                destination._synthetic_eligible_root(
                    staged.session_id,
                    grant=grant,
                )
            )
            read_file_chunks.assert_not_called()

    def test_private_readback_rejects_mode_change_before_yielding_bytes(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-readback-mode",
        )
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
        )
        published_file = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        published_file.chmod(0o644)
        try:
            with self.assertRaises(api.FixtureStagingError) as raised:
                tuple(
                    destination._read_file_chunks(
                        staged.session_id,
                        "fixture-synthetic",
                        "game.rom",
                        grant=grant,
                        capability=self.synthetic_capability,
                    )
                )
            self.assertIsNone(
                destination._synthetic_eligible_root(
                    staged.session_id,
                    grant=grant,
                )
            )
        finally:
            published_file.chmod(0o600)

        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN,
        )

    def test_published_readback_detects_byte_mutation(self) -> None:
        _api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-published-byte-mutation",
        )
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
        )
        published_file = (
            destination._synthetic_final_path(staged.session_id)
            / "fixture-synthetic"
            / "game.rom"
        )
        changed = bytearray(published_file.read_bytes())
        changed[-1] ^= 1
        published_file.write_bytes(changed)

        self.assertIsNone(
            destination._synthetic_eligible_root(
                staged.session_id,
                grant=grant,
            )
        )
        self.assertEqual(
            destination._ownership._load_state(staged.session_id)["state"],
            "published",
        )

    def test_publish_refuses_a_quarantine_not_in_preparing_state(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-publish-state",
        )
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination._create_quarantine(
            session_id,
            token,
            grant,
            capability=self.synthetic_capability,
        )
        record = destination._ownership._load_state(session_id)
        record["state"] = "blocked"
        destination._ownership._replace_state(
            record,
            capability=self.synthetic_capability,
        )

        with self.assertRaises(api.FixtureStagingError) as raised:
            destination._publish(
                session_id,
                token,
                grant=grant,
                capability=self.synthetic_capability,
            )

        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN,
        )
        self.assertTrue(destination._synthetic_temporary_path(session_id).exists())
        self.assertFalse(destination._synthetic_final_path(session_id).exists())
        self.assertIsNone(
            destination._synthetic_eligible_root(session_id, grant=grant)
        )

    def test_quarantine_creation_failure_leaves_no_eligible_state(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-quarantine-failure",
        )
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=self.synthetic_capability,
        )
        destination.root.chmod(0o500)
        try:
            with self.assertRaises(api.FixtureStagingError) as raised:
                destination._create_quarantine(
                    session_id,
                    token,
                    grant,
                    capability=self.synthetic_capability,
                )
        finally:
            destination.root.chmod(0o700)

        self.assertEqual(
            raised.exception.code,
            api.FixtureStagingErrorCode.DESTINATION_UNSAFE,
        )
        self.assertFalse(destination._synthetic_temporary_path(session_id).exists())
        self.assertFalse(destination._synthetic_final_path(session_id).exists())
        self.assertIsNone(
            destination._synthetic_eligible_root(session_id, grant=grant)
        )
        record = destination._ownership._load_state(session_id)
        self.assertEqual(record["state"], "reserved")
        self.assertIsNone(record["root_device"])
        self.assertIsNone(record["root_inode"])

    def test_capacity_requires_admitted_capability_and_live_grant_before_inspection(
        self,
    ) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-capacity-authority",
        )
        other_owner_capability = (
            staging_ownership._issue_synthetic_namespace_capability(owner=object())
        )
        wrong_grant = copy.copy(grant)
        object.__setattr__(wrong_grant, "authorization_sha256", "0" * 64)

        with patch.object(
            destination,
            "_read_capacity_observation",
            side_effect=AssertionError("capacity inspection requires authority"),
        ) as read_capacity, patch.object(
            destination._ownership,
            "_load_state",
            side_effect=AssertionError("capacity must not inspect durable state"),
        ) as load_state, patch.object(
            staging_destination.shutil,
            "disk_usage",
            side_effect=AssertionError("public capacity inspection is not admitted"),
        ) as disk_usage:
            for capability, authority, expected_code in (
                (None, grant, api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY),
                (object(), grant, api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY),
                (
                    other_owner_capability,
                    grant,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                ),
                (self.synthetic_capability, object(), api.FixtureStagingErrorCode.INVALID_AUTHORITY),
                (
                    self.synthetic_capability,
                    wrong_grant,
                    api.FixtureStagingErrorCode.INVALID_AUTHORITY,
                ),
            ):
                with self.subTest(capability=type(capability).__name__, authority=type(authority).__name__):
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        destination._capacity_observation_for_staging(
                            grant=authority,
                            capability=capability,
                        )
                    self.assertEqual(raised.exception.code, expected_code)

            self.staging_now[0] = grant._approval.valid_until
            with self.assertRaises(api.FixtureStagingError) as raised:
                destination._capacity_observation_for_staging(
                    grant=grant,
                    capability=self.synthetic_capability,
                )
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
            )

            production_destination = api.FilesystemFixtureDestination(destination.root)
            with self.assertRaises(api.FixtureStagingError) as raised:
                production_destination.capacity_observation()
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )
            with self.assertRaises(api.FixtureStagingError) as raised:
                destination.capacity_observation()
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )

            thread_failures = []

            def invoke_from_wrong_thread() -> None:
                try:
                    destination._capacity_observation_for_staging(
                        grant=grant,
                        capability=self.synthetic_capability,
                    )
                except api.FixtureStagingError as error:
                    thread_failures.append(error.code)

            thread = threading.Thread(target=invoke_from_wrong_thread)
            thread.start()
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(
                thread_failures,
                [api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY],
            )

            read_capacity.assert_not_called()
            load_state.assert_not_called()
            disk_usage.assert_not_called()

        self.staging_now[0] = NOW
        observation = destination._capacity_observation_for_staging(
            grant=grant,
            capability=self.synthetic_capability,
        )
        self.assertIs(type(observation), api.CapacityObservation)

    def test_published_and_owned_root_helpers_require_exact_authority_before_contact(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-published-helper-authority",
        )
        staged = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            grant=grant,
        )
        self.assertEqual(staged.status, "VERIFIED_FIXTURE")
        session_id = staged.session_id
        record = destination._ownership._load_state(session_id)
        other_owner_capability = (
            staging_ownership._issue_synthetic_namespace_capability(owner=object())
        )
        wrong_grant = copy.copy(grant)
        object.__setattr__(wrong_grant, "authorization_sha256", "0" * 64)

        def helper_calls(capability, authority, target=destination):
            return {
                "final_path": lambda: target._final_path(
                    session_id,
                    grant=authority,
                    capability=capability,
                ),
                "temporary_path": lambda: target._temporary_path(
                    session_id,
                    grant=authority,
                    capability=capability,
                ),
                "read_file_chunks": lambda: next(
                    target._read_file_chunks(
                        session_id,
                        "fixture-synthetic",
                        "game.rom",
                        grant=authority,
                        capability=capability,
                    )
                ),
                "file_mtime_ns": lambda: target._file_mtime_ns(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    grant=authority,
                    capability=capability,
                ),
                "read_file_chunks_from_owned_root": lambda: next(
                    target._read_file_chunks_from_owned_root(
                        session_id,
                        "fixture-synthetic",
                        "game.rom",
                        grant=authority,
                        capability=capability,
                        access="published",
                    )
                ),
                "file_mtime_ns_from_owned_root": lambda: target._file_mtime_ns_from_owned_root(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    grant=authority,
                    capability=capability,
                    access="published",
                ),
            }

        for capability, authority, expected_code in (
            (None, grant, api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY),
            (object(), grant, api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY),
            (
                other_owner_capability,
                grant,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            ),
            (self.synthetic_capability, object(), api.FixtureStagingErrorCode.INVALID_AUTHORITY),
            (
                self.synthetic_capability,
                wrong_grant,
                api.FixtureStagingErrorCode.INVALID_AUTHORITY,
            ),
        ):
            for name, invoke in helper_calls(capability, authority).items():
                with (
                    self.subTest(name=name, capability=type(capability).__name__),
                    patch.object(
                        destination._ownership,
                        "_load_state",
                        side_effect=AssertionError("invalid authority reached durable state"),
                    ) as load_state,
                    patch.object(
                        destination._ownership,
                        "_ownership_is_proven",
                        side_effect=AssertionError("invalid authority reached destination stat"),
                    ) as ownership_proven,
                    patch.object(
                        destination._ownership,
                        "_open_owned_root",
                        side_effect=AssertionError("invalid authority opened owned root"),
                    ) as open_owned_root,
                    patch.object(
                        destination._ownership,
                        "temporary_root",
                        side_effect=AssertionError("invalid authority resolved temporary root"),
                    ) as temporary_root,
                    patch.object(
                        staging_destination,
                        "_open_destination_parent",
                        side_effect=AssertionError("invalid authority opened destination member"),
                    ) as open_destination_parent,
                ):
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        invoke()
                    self.assertEqual(raised.exception.code, expected_code)
                load_state.assert_not_called()
                ownership_proven.assert_not_called()
                open_owned_root.assert_not_called()
                temporary_root.assert_not_called()
                open_destination_parent.assert_not_called()

        self.staging_now[0] = grant._approval.valid_until
        for name, invoke in helper_calls(self.synthetic_capability, grant).items():
            with (
                self.subTest(name=name, authority="expired"),
                patch.object(
                    destination._ownership,
                    "_load_state",
                    side_effect=AssertionError("expired authority reached durable state"),
                ) as load_state,
                patch.object(
                    destination._ownership,
                    "_open_owned_root",
                    side_effect=AssertionError("expired authority opened owned root"),
                ) as open_owned_root,
                patch.object(
                    staging_destination,
                    "_open_destination_parent",
                    side_effect=AssertionError("expired authority opened destination member"),
                ) as open_destination_parent,
            ):
                with self.assertRaises(api.FixtureStagingError) as raised:
                    invoke()
                self.assertEqual(
                    raised.exception.code,
                    api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
                )
                load_state.assert_not_called()
                open_owned_root.assert_not_called()
                open_destination_parent.assert_not_called()
        self.staging_now[0] = NOW

        production_destination = api.FilesystemFixtureDestination(destination.root)
        for name, invoke in helper_calls(
            self.synthetic_capability,
            grant,
            production_destination,
        ).items():
            with self.subTest(name=name, authority="production"):
                with patch.object(
                    production_destination._ownership,
                    "_load_state",
                    side_effect=AssertionError("production reached durable state"),
                ) as load_state:
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        invoke()
                self.assertEqual(
                    raised.exception.code,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )
                load_state.assert_not_called()

        thread_failures = []

        def invoke_from_wrong_thread() -> None:
            for name, invoke in helper_calls(
                self.synthetic_capability,
                grant,
            ).items():
                try:
                    invoke()
                except api.FixtureStagingError as error:
                    thread_failures.append((name, error.code))

        with (
            patch.object(
                destination._ownership,
                "_load_state",
                side_effect=AssertionError("wrong thread reached durable state"),
            ) as load_state,
            patch.object(
                destination._ownership,
                "_ownership_is_proven",
                side_effect=AssertionError("wrong thread reached destination stat"),
            ) as ownership_proven,
            patch.object(
                destination._ownership,
                "_open_owned_root",
                side_effect=AssertionError("wrong thread opened owned root"),
            ) as open_owned_root,
            patch.object(
                destination._ownership,
                "temporary_root",
                side_effect=AssertionError("wrong thread resolved temporary root"),
            ) as temporary_root,
            patch.object(
                staging_destination,
                "_open_destination_parent",
                side_effect=AssertionError("wrong thread opened destination member"),
            ) as open_destination_parent,
        ):
            thread = threading.Thread(target=invoke_from_wrong_thread)
            thread.start()
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            load_state.assert_not_called()
            ownership_proven.assert_not_called()
            open_owned_root.assert_not_called()
            temporary_root.assert_not_called()
            open_destination_parent.assert_not_called()
        self.assertEqual(
            thread_failures,
            [
                (
                    name,
                    api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )
                for name in (
                    "final_path",
                    "temporary_path",
                    "read_file_chunks",
                    "file_mtime_ns",
                    "read_file_chunks_from_owned_root",
                    "file_mtime_ns_from_owned_root",
                )
            ],
        )

        for state in ("reserved", "blocked", "publication_pending"):
            unpublished_record = copy.deepcopy(record)
            unpublished_record["state"] = state
            for name, invoke in helper_calls(
                self.synthetic_capability,
                grant,
            ).items():
                with (
                    self.subTest(name=name, state=state),
                    patch.object(
                        destination._ownership,
                        "_load_state",
                        return_value=unpublished_record,
                    ) as load_state,
                    patch.object(
                        destination._ownership,
                        "_ownership_is_proven",
                        side_effect=AssertionError("unpublished helper reached destination stat"),
                    ) as ownership_proven,
                    patch.object(
                        destination._ownership,
                        "_open_owned_root",
                        side_effect=AssertionError("unpublished helper opened owned root"),
                    ) as open_owned_root,
                    patch.object(
                        destination._ownership,
                        "temporary_root",
                        side_effect=AssertionError("unpublished helper resolved temporary root"),
                    ) as temporary_root,
                    patch.object(
                        staging_destination,
                        "_open_destination_parent",
                        side_effect=AssertionError("unpublished helper opened destination member"),
                    ) as open_destination_parent,
                ):
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        invoke()
                    self.assertEqual(
                        raised.exception.code,
                        api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN,
                    )
                    load_state.assert_called_once_with(session_id)
                    ownership_proven.assert_not_called()
                    open_owned_root.assert_not_called()
                    temporary_root.assert_not_called()
                    open_destination_parent.assert_not_called()

        self.assertEqual(
            destination._final_path(
                session_id,
                grant=grant,
                capability=self.synthetic_capability,
            ),
            destination.root / f"fixture-{session_id}",
        )
        self.assertEqual(
            destination._temporary_path(
                session_id,
                grant=grant,
                capability=self.synthetic_capability,
            ),
            destination._ownership.temporary_root(session_id),
        )
        self.assertEqual(
            b"".join(
                destination._read_file_chunks(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    grant=grant,
                    capability=self.synthetic_capability,
                )
            ),
            b"synthetic-rom-content-v1",
        )
        self.assertIsInstance(
            destination._file_mtime_ns(
                session_id,
                "fixture-synthetic",
                "game.rom",
                grant=grant,
                capability=self.synthetic_capability,
            ),
            int,
        )

    def test_source_preflight_requires_capability_and_live_grant_before_inspection(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-source-preflight-authority",
        )
        source_roots = {"fixture-synthetic": source_root}
        other_owner_capability = (
            staging_ownership._issue_synthetic_namespace_capability(owner=object())
        )
        wrong_grant = copy.copy(grant)
        object.__setattr__(wrong_grant, "authorization_sha256", "0" * 64)
        callback_calls = []

        def admit():
            callback_calls.append("called")
            return self.synthetic_capability

        def invoke(capability, authority):
            return _fixture_staging_transfer._preflight_staging_sources(
                destination,
                authority,
                source_roots,
                capability=capability,
                capacity_access_admission=admit,
            )

        for capability, authority, expected_code in (
            (None, grant, api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY),
            (object(), grant, api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY),
            (
                other_owner_capability,
                grant,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            ),
            (self.synthetic_capability, object(), api.FixtureStagingErrorCode.INVALID_AUTHORITY),
            (
                self.synthetic_capability,
                wrong_grant,
                api.FixtureStagingErrorCode.INVALID_AUTHORITY,
            ),
        ):
            with (
                patch.object(
                    destination,
                    "_validate_root_identity",
                    side_effect=AssertionError("preflight inspected destination root"),
                ) as validate_root,
                patch.object(
                    _fixture_staging_transfer,
                    "_preflight_sources",
                    side_effect=AssertionError("preflight inspected source roots"),
                ) as preflight_sources,
            ):
                with self.subTest(capability=type(capability).__name__):
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        invoke(capability, authority)
                    self.assertEqual(raised.exception.code, expected_code)
                validate_root.assert_not_called()
                preflight_sources.assert_not_called()

        self.staging_now[0] = grant._approval.valid_until
        with (
            patch.object(
                destination,
                "_validate_root_identity",
                side_effect=AssertionError("expired preflight inspected destination root"),
            ) as validate_root,
            patch.object(
                _fixture_staging_transfer,
                "_preflight_sources",
                side_effect=AssertionError("expired preflight inspected source roots"),
            ) as preflight_sources,
        ):
            with self.assertRaises(api.FixtureStagingError) as raised:
                invoke(self.synthetic_capability, grant)
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
            )
            validate_root.assert_not_called()
            preflight_sources.assert_not_called()
        self.staging_now[0] = NOW

        production_destination = api.FilesystemFixtureDestination(destination.root)
        with (
            patch.object(
                production_destination,
                "_validate_root_identity",
                side_effect=AssertionError("production preflight inspected destination root"),
            ) as validate_root,
            patch.object(
                _fixture_staging_transfer,
                "_preflight_sources",
                side_effect=AssertionError("production preflight inspected source roots"),
            ) as preflight_sources,
        ):
            with self.assertRaises(api.FixtureStagingError) as raised:
                _fixture_staging_transfer._preflight_staging_sources(
                    production_destination,
                    grant,
                    source_roots,
                    capability=self.synthetic_capability,
                    capacity_access_admission=admit,
                )
            self.assertEqual(
                raised.exception.code,
                api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
            )
            validate_root.assert_not_called()
            preflight_sources.assert_not_called()

        thread_failures = []

        def invoke_from_wrong_thread() -> None:
            try:
                invoke(self.synthetic_capability, grant)
            except api.FixtureStagingError as error:
                thread_failures.append(error.code)

        with (
            patch.object(
                destination,
                "_validate_root_identity",
                side_effect=AssertionError("wrong thread inspected destination root"),
            ) as validate_root,
            patch.object(
                _fixture_staging_transfer,
                "_preflight_sources",
                side_effect=AssertionError("wrong thread inspected source roots"),
            ) as preflight_sources,
        ):
            thread = threading.Thread(target=invoke_from_wrong_thread)
            thread.start()
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            validate_root.assert_not_called()
            preflight_sources.assert_not_called()
        self.assertEqual(
            thread_failures,
            [api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY],
        )
        self.assertEqual(callback_calls, [])

        snapshots, total_bytes, capability = (
            _fixture_staging_transfer._preflight_staging_sources(
                destination,
                grant,
                source_roots,
                capability=self.synthetic_capability,
                capacity_access_admission=admit,
            )
        )
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(total_bytes, len(b"synthetic-rom-content-v1"))
        self.assertIs(capability, self.synthetic_capability)
        self.assertEqual(callback_calls, ["called"])
