"""Exercise plan and manifest binding, grant issuance, and device-admission boundaries."""

from __future__ import annotations

from scripts.android_qualification import _fixture_staging_manifest as staging_manifest
from scripts.android_qualification import _fixture_staging_model as staging_model
from scripts.android_qualification import _fixture_staging_orchestration
from scripts.android_qualification import _fixture_staging_transfer
from scripts.android_qualification import manifest
from scripts.android_qualification._fixture_staging_test_support import _sync_oracle
from scripts.android_qualification._fixture_staging_test_support import _cleanup_fixture_staging_for_synthetic_mechanics, _stage_fixtures_for_synthetic_mechanics
from scripts.android_qualification.test_manifest import NOW
from scripts.android_qualification.test_manifest import approval_document
from scripts.android_qualification.test_manifest import write_private_json
from unittest.mock import patch
import copy
import hashlib
import os
from scripts.android_qualification._fixture_staging_test_support import (
    FixtureStagingTestCase,
)
from scripts.android_qualification import _fixture_staging_ownership as staging_ownership
from datetime import timedelta
import threading

class FixtureStagingAuthorizationTests(FixtureStagingTestCase):
    def test_integer_clock_preserves_nanosecond_deadline_boundaries(self) -> None:
        """Integer clock readings must not move the original expiry boundary."""
        grant = self._authorize()
        timing = staging_model._new_operation_timing(
            grant, NOW, lambda: 17_052_823_080_000
        )
        self.assertEqual(timing["monotonic_start_ns"], 17_052_823_080_000)
        self.assertEqual(timing["operation_deadline_monotonic_ns"], 17_082_823_080_000)
        original = copy.deepcopy(timing)
        for current, expired in (
            (17_082_823_079_999, False),
            (17_082_823_080_000, True),
            (17_082_823_080_001, True),
        ):
            with self.subTest(current=current):
                if expired:
                    with self.assertRaises(staging_model.FixtureStagingError) as caught:
                        staging_model._check_operation_timing(
                            timing, clock=lambda: current, mode="cleanup"
                        )
                    self.assertEqual(
                        caught.exception.code, staging_model.FixtureStagingErrorCode.OPERATION_TIMEOUT
                    )
                else:
                    staging_model._check_operation_timing(
                        timing, clock=lambda: current, mode="cleanup"
                    )
                self.assertEqual(timing, original)

    def test_production_clock_reads_integer_nanoseconds_without_float_seconds(self) -> None:
        """Production timing must retain a one-nanosecond expiry distinction."""
        grant = self._authorize()
        with (
            patch.object(staging_ownership.time, "monotonic_ns", return_value=17_052_823_080_000),
            patch.object(staging_ownership.time, "monotonic", side_effect=AssertionError("float clock used")),
        ):
            timing = staging_model._new_operation_timing(
                grant, NOW, staging_ownership._monotonic_now
            )
        self.assertEqual(timing["operation_deadline_monotonic_ns"], 17_082_823_080_000)
        for current, expired in (
            (17_082_823_079_999, False),
            (17_082_823_080_000, True),
            (17_082_823_080_001, True),
        ):
            with self.subTest(current=current), patch.object(
                staging_ownership.time, "monotonic_ns", return_value=current
            ):
                if expired:
                    with self.assertRaises(staging_model.FixtureStagingError) as caught:
                        staging_model._check_operation_timing(
                            timing, clock=staging_ownership._monotonic_now, mode="cleanup"
                        )
                    self.assertEqual(caught.exception.code, staging_model.FixtureStagingErrorCode.OPERATION_TIMEOUT)
                else:
                    staging_model._check_operation_timing(
                        timing, clock=staging_ownership._monotonic_now, mode="cleanup"
                    )

    def test_nanosecond_clock_rejects_seconds_and_invalid_readings(self) -> None:
        """A clock with ambiguous units cannot authorize fixture mutations."""
        for value in (True, False, -1, 1.0, float("nan"), float("inf"), "1", None):
            with self.subTest(value=value):
                with self.assertRaises(staging_model.FixtureStagingError) as caught:
                    staging_model._read_monotonic_ns(lambda: value)
                self.assertEqual(caught.exception.code, staging_model.FixtureStagingErrorCode.OPERATION_TIMEOUT)

    def test_persisted_nanosecond_authorization_boundaries_are_not_rebased(self) -> None:
        """Loaded timing records expire at their original authorization boundary."""
        timing = staging_model._new_operation_timing(
            self._authorize(), NOW, lambda: 17_052_823_080_000
        )
        # Schema 1 already stores integer nanoseconds, including values rounded
        # by older float-based writers. Never round or regenerate those values.
        timing["staging_authorization_deadline_monotonic_ns"] = 17_052_823_080_099
        timing["cleanup_authorization_deadline_monotonic_ns"] = 17_052_823_080_199
        original = copy.deepcopy(timing)
        for mode, boundary in (("staging", 17_052_823_080_099), ("cleanup", 17_052_823_080_199)):
            for offset in (-1, 0, 1):
                with self.subTest(mode=mode, offset=offset):
                    if offset < 0:
                        staging_model._check_operation_timing(
                            timing, clock=lambda: boundary + offset, mode=mode
                        )
                    else:
                        with self.assertRaises(staging_model.FixtureStagingError) as caught:
                            staging_model._check_operation_timing(
                                timing, clock=lambda: boundary + offset, mode=mode
                            )
                        self.assertEqual(caught.exception.code, staging_model.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED)
                    self.assertEqual(timing, original)

    def test_uptime_timing_does_not_silently_acquire_sleep_inclusive_semantics(self) -> None:
        """A UTC jump cannot reinterpret existing uptime-domain timing records."""
        timing = staging_model._new_operation_timing(
            self._authorize(), NOW, lambda: 17_052_823_080_000
        )
        original = copy.deepcopy(timing)
        # Model a suspended host: UTC advances while the uptime clock is held.
        # The separate grant validator still checks UTC; this persisted-clock
        # check alone must preserve schema 1's existing sleep exclusion.
        with patch.object(staging_manifest, "_utc_now", return_value=NOW + timedelta(hours=1)):
            staging_model._check_operation_timing(
                timing, clock=lambda: 17_052_823_080_001, mode="cleanup"
            )
        self.assertEqual(timing, original)

    def test_public_staging_gate_precedes_uninitialized_grant_and_filesystem_work(
        self,
    ) -> None:
        api = self._require_staging_module()
        forged_grant = object.__new__(api.FixtureStagingGrant)
        source_root = self.directory / "source-uninitialized-grant-stage"
        source_root.mkdir(mode=0o700)
        source_path = source_root / "game.rom"
        source_path.write_bytes(b"synthetic-rom-content-v1")
        source_bytes = source_path.read_bytes()
        destination_root = self.directory / "destination-uninitialized-grant-stage"
        destination_root.mkdir(mode=0o700)
        destination = api.FilesystemFixtureDestination(destination_root)

        with (
            patch.object(
                manifest,
                "_owner_approval_source_matches",
            ) as approval_source_matches,
            patch.object(
                manifest,
                "_loaded_owner_approval_source_details",
            ) as approval_source_details,
            patch.object(
                api.FilesystemFixtureDestination,
                "__init__",
                side_effect=AssertionError(
                    "destination constructed before authority"
                ),
            ) as destination_constructor,
            patch.object(destination, "_validate_root_identity") as root_identity,
            patch.object(
                _fixture_staging_orchestration, "_preflight_staging_sources"
            ) as preflight,
            patch.object(
                _fixture_staging_orchestration,
                "_transfer_and_verify_fixture_set",
            ) as transfer,
            patch.object(destination, "_read_capacity_observation") as capacity,
            patch.object(destination._ownership, "reserve_session") as reserve,
            patch.object(destination, "_create_quarantine") as quarantine,
            patch.object(destination, "_write_file") as write_file,
            patch.object(destination, "_publish_and_confirm") as publish,
        ):
            result = self.production_stage_fixtures(
                forged_grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(result.fixture_count, 0)
        self.assertEqual(result.file_count, 0)
        self.assertEqual(result.coverage_mode, "")
        approval_source_matches.assert_not_called()
        approval_source_details.assert_not_called()
        destination_constructor.assert_not_called()
        root_identity.assert_not_called()
        preflight.assert_not_called()
        transfer.assert_not_called()
        capacity.assert_not_called()
        reserve.assert_not_called()
        quarantine.assert_not_called()
        write_file.assert_not_called()
        publish.assert_not_called()
        self.assertEqual(source_path.read_bytes(), source_bytes)
        self.assertEqual(list(destination.root.iterdir()), [])
        self.assertFalse((destination.root / destination._STATE_DIRECTORY).exists())

    def test_public_cleanup_gate_precedes_uninitialized_grant_and_destination_work(
        self,
    ) -> None:
        api = self._require_staging_module()
        forged_grant = object.__new__(api.FixtureStagingGrant)
        source_root = self.directory / "source-uninitialized-grant-cleanup"
        source_root.mkdir(mode=0o700)
        source_path = source_root / "game.rom"
        source_path.write_bytes(b"synthetic-rom-content-v1")
        source_bytes = source_path.read_bytes()
        destination_root = self.directory / "destination-uninitialized-grant-cleanup"
        destination_root.mkdir(mode=0o700)
        destination = api.FilesystemFixtureDestination(destination_root)

        with (
            patch.object(destination, "_read_capacity_observation") as capacity,
            patch.object(
                destination._ownership, "coordination_lock"
            ) as coordination_lock,
            patch.object(destination._ownership, "_load_state") as load_state,
            patch.object(
                destination._ownership, "remove_owned_session"
            ) as remove_owned_session,
            patch.object(
                destination._ownership, "mark_blocked_or_destination_unsafe"
            ) as mark_blocked,
            patch.object(destination, "_write_file") as write_file,
            patch.object(destination, "_publish_and_confirm") as publish,
        ):
            result = self.production_cleanup_fixture_staging(
                forged_grant,
                destination=destination,
                session_id="0" * 32,
                now=NOW,
            )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertFalse(result.removed)
        capacity.assert_not_called()
        coordination_lock.assert_not_called()
        load_state.assert_not_called()
        remove_owned_session.assert_not_called()
        mark_blocked.assert_not_called()
        write_file.assert_not_called()
        publish.assert_not_called()
        self.assertEqual(source_path.read_bytes(), source_bytes)
        self.assertEqual(list(destination.root.iterdir()), [])
        self.assertFalse((destination.root / destination._STATE_DIRECTORY).exists())

    def test_public_production_gates_are_first_and_ignore_hostile_arguments(
        self,
    ) -> None:
        api = self._require_staging_module()
        events: list[str] = []

        class HostileArgument:
            def __getattribute__(self, name):
                events.append(f"caller-attribute:{name}")
                raise AssertionError("caller argument inspected before gate")

            def __fspath__(self):
                events.append("caller-fspath")
                raise AssertionError("caller path converted before gate")

        sentinel_root = self.directory / "gate-first-sentinel"
        sentinel_root.mkdir(mode=0o700)
        sentinel = sentinel_root / "unchanged.rom"
        sentinel.write_bytes(b"synthetic-sentinel")
        before_entries = tuple(sorted(path.name for path in sentinel_root.iterdir()))
        before_bytes = sentinel.read_bytes()
        original_admission = (
            _fixture_staging_orchestration._admit_production_staging_namespace
        )

        def record_admission() -> None:
            events.append("admission")
            original_admission()

        with (
            patch.object(
                _fixture_staging_orchestration,
                "_admit_production_staging_namespace",
                side_effect=record_admission,
            ),
            patch.object(
                _fixture_staging_orchestration,
                "_validate_grant_for_use",
                side_effect=AssertionError("grant inspected before gate"),
            ) as validate_grant,
            patch.object(
                _fixture_staging_orchestration,
                "_preflight_staging_sources",
                side_effect=AssertionError("source inspected before gate"),
            ) as preflight_sources,
            patch.object(
                _fixture_staging_transfer,
                "_ensure_capacity",
                side_effect=AssertionError("capacity inspected before gate"),
            ) as ensure_capacity,
            patch.object(
                api.FilesystemFixtureDestination,
                "__init__",
                side_effect=AssertionError("destination inspected before gate"),
            ) as destination_constructor,
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
        ):
            staging_result = self.production_stage_fixtures(
                HostileArgument(),
                source_roots={"fixture-synthetic": HostileArgument()},
                destination=HostileArgument(),
                now=NOW,
            )
            cleanup_result = self.production_cleanup_fixture_staging(
                HostileArgument(),
                destination=HostileArgument(),
                session_id="0" * 32,
                now=NOW,
            )

        self.assertEqual(events, ["admission", "admission"])
        self.assertEqual(
            staging_result.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertEqual(
            cleanup_result.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        validate_grant.assert_not_called()
        preflight_sources.assert_not_called()
        ensure_capacity.assert_not_called()
        destination_constructor.assert_not_called()
        reserve_session.assert_not_called()
        coordination_lock.assert_not_called()
        self.assertEqual(
            tuple(sorted(path.name for path in sentinel_root.iterdir())),
            before_entries,
        )
        self.assertEqual(sentinel.read_bytes(), before_bytes)

    def test_expired_authority_fails_before_approval_source_reads(self) -> None:
        api = self._require_staging_module()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-expired-stage",
        )
        expired_at = min(
            self.authorization.session_deadline,
            self.approval.valid_until,
        )
        self.staging_now[0] = expired_at

        with (
            patch.object(
                manifest,
                "_owner_approval_source_matches",
                wraps=manifest._owner_approval_source_matches,
            ) as source_matches,
            patch.object(
                manifest,
                "_loaded_owner_approval_source_details",
                wraps=manifest._loaded_owner_approval_source_details,
            ) as source_details,
        ):
            with self.assertRaises(api.FixtureStagingError) as authorization_error:
                self._authorize()
            with self.assertRaises(api.FixtureStagingError) as grant_error:
                staging_manifest._validate_grant_for_use(grant, expired_at)
            with (
                patch.object(
                    api.FilesystemFixtureDestination,
                    "__init__",
                    side_effect=AssertionError(
                        "expired staging inspected its destination"
                    ),
                ) as destination_constructor,
                patch.object(
                    _fixture_staging_orchestration,
                    "_preflight_staging_sources",
                ) as preflight,
                patch.object(destination, "_validate_root_identity") as root_identity,
            ):
                with self.assertRaises(api.FixtureStagingError) as staging_error:
                    _stage_fixtures_for_synthetic_mechanics(
                        self.synthetic_capability,
                        grant,
                        source_roots={"fixture-synthetic": source_root},
                        destination=destination,
                    )

        self.assertEqual(
            authorization_error.exception.code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
        )
        self.assertEqual(
            grant_error.exception.code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
        )
        self.assertEqual(
            staging_error.exception.code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
        )
        destination_constructor.assert_not_called()
        preflight.assert_not_called()
        root_identity.assert_not_called()
        source_matches.assert_not_called()
        source_details.assert_not_called()

    def test_expired_direct_helpers_reject_before_callbacks_lock_or_state(self) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-expired-direct",
        )
        expected_fixture = grant._fixture_expectations[0]
        expected = expected_fixture.files[0]
        ownership = destination._ownership
        self.staging_now[0] = grant._authorization.session_deadline

        def assert_no_side_effects() -> None:
            coordination_lock.assert_not_called()
            load_state.assert_not_called()
            validate_directory.assert_not_called()
            replace_state.assert_not_called()
            session_factory.assert_not_called()
            self.assertFalse((destination.root / destination._STATE_DIRECTORY).exists())

        with (
            patch.object(ownership, "coordination_lock") as coordination_lock,
            patch.object(ownership, "_load_state") as load_state,
            patch.object(
                staging_ownership,
                "_validate_private_directory",
            ) as validate_directory,
            patch.object(ownership, "_replace_state") as replace_state,
            patch.object(ownership, "_session_id_factory") as session_factory,
        ):
            with self.assertRaises(api.FixtureStagingError) as reserve_error:
                ownership.reserve_session(
                    grant,
                    capability=self.synthetic_capability,
                )
            self.assertEqual(
                reserve_error.exception.code,
                api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
            )
            assert_no_side_effects()

            with self.assertRaises(api.FixtureStagingError) as verified_error:
                ownership.record_verified_file(
                    "0" * 32,
                    "0" * 64,
                    expected_fixture.fixture_id,
                    expected,
                    0,
                    grant=grant,
                    capability=self.synthetic_capability,
                )
            self.assertEqual(
                verified_error.exception.code,
                api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
            )
            assert_no_side_effects()

            with self.assertRaises(api.FixtureStagingError) as timing_error:
                ownership.reserve_session(
                    grant,
                    operation_timing={},
                    capability=self.synthetic_capability,
                )
            self.assertEqual(
                timing_error.exception.code,
                api.FixtureStagingErrorCode.TIMING_UNVERIFIED,
            )
            assert_no_side_effects()

        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        self.staging_now[0] = NOW
        cleanup_grant = self._authorize()
        cleanup_api, _root, cleanup_destination, _grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            grant=cleanup_grant,
            suffix="-expired-cleanup-direct",
        )
        cleanup_ownership = cleanup_destination._ownership
        self.staging_now[0] = cleanup_grant._authorization.cleanup_deadline
        with (
            patch.object(cleanup_ownership, "coordination_lock") as coordination_lock,
            patch.object(cleanup_ownership, "_load_state") as load_state,
            patch.object(
                staging_ownership,
                "_validate_private_directory",
            ) as validate_directory,
            patch.object(cleanup_ownership, "_open_owned_root") as open_owned_root,
            patch.object(cleanup_ownership, "_replace_state") as replace_state,
            patch.object(staging_ownership, "_validate_tree_for_removal") as validate_tree,
            patch.object(staging_ownership, "_remove_tree_contents") as remove_tree,
            patch.object(cleanup_ownership, "_session_id_factory") as session_factory,
        ):
            with self.assertRaises(cleanup_api.FixtureStagingError) as cleanup_error:
                cleanup_ownership.remove_owned_session(
                    "0" * 32,
                    "0" * 64,
                    grant=cleanup_grant,
                    capability=self.synthetic_capability,
                )
        self.assertEqual(
            cleanup_error.exception.code,
            cleanup_api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
        )
        coordination_lock.assert_not_called()
        load_state.assert_not_called()
        validate_directory.assert_not_called()
        open_owned_root.assert_not_called()
        replace_state.assert_not_called()
        validate_tree.assert_not_called()
        remove_tree.assert_not_called()
        session_factory.assert_not_called()
        self.assertFalse(
            (cleanup_destination.root / cleanup_destination._STATE_DIRECTORY).exists()
        )

    def test_expired_destination_helpers_reject_before_lock_state_or_filesystem(
        self,
    ) -> None:
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-expired-destination-direct",
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
        self.staging_now[0] = grant._authorization.session_deadline
        chunk_iterations = []

        class Chunks:
            def __iter__(self):
                chunk_iterations.append(True)
                yield b"synthetic-rom-content-v1"

        with (
            patch.object(ownership, "coordination_lock") as coordination_lock,
            patch.object(ownership, "_load_state") as load_state,
            patch.object(ownership, "_open_owned_root") as open_owned_root,
            patch.object(ownership, "_write_private_json_exclusive") as write_json,
            patch.object(ownership, "_record_owned_entry") as record_entry,
            patch.object(staging_ownership, "_rename_entry_exclusive") as rename,
            patch.object(
                manifest,
                "_loaded_owner_approval_source_details",
            ) as approval_details,
            patch.object(manifest, "_owner_approval_source_matches") as approval_match,
        ):
            operations = (
                lambda: destination._create_quarantine(
                    session_id,
                    token,
                    grant,
                    capability=self.synthetic_capability,
                ),
                lambda: destination._write_file(
                    session_id,
                    "fixture-synthetic",
                    "game.rom",
                    Chunks(),
                    ownership_token=token,
                    source_mtime_ns=0,
                    grant=grant,
                    capability=self.synthetic_capability,
                ),
                lambda: destination._publish(
                    session_id,
                    token,
                    grant=grant,
                    capability=self.synthetic_capability,
                ),
                lambda: destination._confirm_publication(
                    session_id,
                    token,
                    grant=grant,
                    capability=self.synthetic_capability,
                ),
                lambda: destination._publish_and_confirm(
                    session_id,
                    token,
                    grant=grant,
                    capability=self.synthetic_capability,
                ),
            )
            for operation in operations:
                with self.subTest(operation=operation):
                    with self.assertRaises(api.FixtureStagingError) as raised:
                        operation()
                    self.assertEqual(
                        raised.exception.code,
                        api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED,
                    )

        coordination_lock.assert_not_called()
        load_state.assert_not_called()
        open_owned_root.assert_not_called()
        write_json.assert_not_called()
        record_entry.assert_not_called()
        rename.assert_not_called()
        approval_details.assert_not_called()
        approval_match.assert_not_called()
        self.assertEqual(chunk_iterations, [])
        self.assertEqual(
            sorted(
                path.relative_to(destination.root)
                for path in destination.root.rglob("*")
            ),
            before_paths,
        )

    def test_grant_requires_loaded_approval_and_pins_plan_and_fixture_inputs(self) -> None:
        api = self._require_staging_module()

        grant = self._authorize()

        self.assertIsInstance(grant, api.FixtureStagingGrant)
        self.assertEqual(grant.authorization_sha256, self.authorization.canonical_sha256)
        self.assertEqual(
            grant.approval_sha256,
            hashlib.sha256(self.approval_path.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            grant.approval_authorization_sha256,
            self.authorization.canonical_sha256,
        )
        self.assertEqual(grant.fixture_manifest_sha256, self.authorization.fixture_manifest_sha256)
        self.assertEqual(grant.plan_sha256, self.authorization.plan_sha256)
        self.assertEqual(grant.operation_id, "fixture-stage-synthetic")
        self.assertEqual(grant.fixture_ids, ("fixture-synthetic",))
        self.assertEqual(grant.coverage_mode, "mandatory_full_plan")
        self.assertEqual(grant.required_fixture_count, 1)
        self.assertEqual(grant.operation_timeout_seconds, 30)

    def test_constructed_authorization_and_approval_cannot_issue_a_grant(self) -> None:
        api = self._require_staging_module()

        with self.assertRaises(api.FixtureStagingError):
            self._authorize(authorization=manifest.SessionAuthorization(**{
                name: getattr(self.authorization, name)
                for name in self.authorization.__dataclass_fields__
            }))
        with self.assertRaises(api.FixtureStagingError):
            self._authorize(approval=manifest.OwnerApproval(
                self.approval.authorization_sha256,
                self.approval.owner_identity,
                self.approval.valid_from,
                self.approval.valid_until,
            ))

    def test_missing_or_wrong_fixture_staging_operation_is_denied(self) -> None:
        api = self._require_staging_module()

        with self.assertRaises(api.FixtureStagingError):
            self._authorize(operation_id="permission-loss-synthetic")
        with self.assertRaises(api.FixtureStagingError):
            self._authorize(operation_id="unknown-operation")

    def test_changed_plan_or_fixture_manifest_breaks_authorized_digest_binding(self) -> None:
        api = self._require_staging_module()
        changed_plan = dict(self.plan_document)
        changed_plan["host_reserve_bytes"] = 1
        write_private_json(self.directory, "plan.json", changed_plan)

        with self.assertRaises(api.FixtureStagingError):
            self._authorize()

        self.plan_path = write_private_json(
            self.directory, "plan.json", self.plan_document
        )
        changed_manifest = dict(self.fixture_document)
        changed_manifest["coverage_mode"] = "authorized_partial_plan"
        self.fixture_path = write_private_json(
            self.directory, "fixtures.json", changed_manifest
        )
        with self.assertRaises(api.FixtureStagingError):
            self._authorize()

    def test_grant_does_not_claim_or_consume_device_admission(self) -> None:
        api = self._require_staging_module()

        grant = self._authorize()

        self.assertFalse(grant.device_admitted)
        self.assertFalse(grant.session_authorization_consumed)
        self.assertEqual(grant.result_kind, "HOST_PREPARATION_ONLY")

    def test_self_declared_oracle_record_is_rejected(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["fixtures"][0]["oracle"] = {
            "source": "independent synthetic reference",
            "record_id": "self-declared-record",
            "record_sha256": "1" * 64,
        }
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(
            caught.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID
        )

    def test_structural_only_evidence_is_distinguished_and_cannot_issue_a_grant(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["fixtures"][0]["identity_evidence"] = "structural_only"
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.STRUCTURAL_ONLY)

    def test_full_plan_cannot_omit_a_required_fixture_from_the_manifest(self) -> None:
        api = self._require_staging_module()
        plan = copy.deepcopy(self.plan_document)
        plan["fixture_coverage"]["required_fixture_ids"].append("fixture-required")
        plan["fixture_coverage"]["selected_fixture_ids"].append("fixture-required")
        plan["fixture_coverage"]["mandatory_fixture_ids"].append("fixture-required")
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["selected_fixture_ids"].append("fixture-required")
        self._rebind_inputs(plan=plan, fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(
            caught.exception.code, api.FixtureStagingErrorCode.EXPECTATION_UNVERIFIED
        )

    def test_partial_coverage_requires_a_pinned_explicit_partial_plan(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        coverage = plan["fixture_coverage"]
        coverage["mode"] = "authorized_partial_plan"
        coverage["required_fixture_ids"].append("fixture-not-selected")
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["coverage_mode"] = "authorized_partial_plan"
        self._rebind_inputs(plan=plan, fixture_manifest=fixture_document)

        grant = self._authorize()

        self.assertEqual(grant.coverage_mode, "authorized_partial_plan")
        self.assertEqual(grant.fixture_ids, ("fixture-synthetic",))
        self.assertEqual(grant.required_fixture_count, 2)
        api, source_root, destination, _grant = self._make_staging_inputs(
            capability=self.synthetic_capability,grant=grant)
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)
        self.assertEqual(result.coverage_mode, "authorized_partial_plan")
        self.assertEqual(result.required_fixture_count, 2)
        self.assertEqual(result.selected_fixture_count, 1)

    def test_partial_selection_must_preserve_required_plan_order(self) -> None:
        api = self._require_staging_module()
        plan = copy.deepcopy(self.plan_document)
        plan["fixture_coverage"] = {
            "mode": "authorized_partial_plan",
            "required_fixture_ids": ["fixture-a", "fixture-b", "fixture-c"],
            "selected_fixture_ids": ["fixture-b", "fixture-a"],
            "mandatory_fixture_ids": ["fixture-a"],
        }
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["coverage_mode"] = "authorized_partial_plan"
        fixture_document["selected_fixture_ids"] = ["fixture-b", "fixture-a"]
        self._rebind_inputs(plan=plan, fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.PLAN_INVALID)

    def test_case_folded_directory_aliases_are_rejected(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture.update(
            {
                "entrypoint": "disc/track-a.bin",
                "files": [
                    {
                        "path": "disc/track-a.bin",
                        "role": "track",
                        "size": 1,
                        "sha256": "1" * 64,
                    },
                    {
                        "path": "Disc/track-b.bin",
                        "role": "track",
                        "size": 1,
                        "sha256": "2" * 64,
                    },
                ],
                "companions": [],
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID)

    def test_fixture_ids_with_destination_equivalent_spellings_are_rejected(self) -> None:
        api = self._require_staging_module()
        equivalent_pairs = (
            ("fixture-synthetic", "FIXTURE-SYNTHETIC"),
            ("café", "cafe\u0301"),
        )
        for first_id, second_id in equivalent_pairs:
            with self.subTest(first_id=first_id, second_id=second_id):
                plan = copy.deepcopy(self.plan_document)
                plan["fixture_coverage"] = {
                    "mode": "mandatory_full_plan",
                    "required_fixture_ids": [first_id, second_id],
                    "selected_fixture_ids": [first_id, second_id],
                    "mandatory_fixture_ids": [first_id, second_id],
                }
                fixture_document = copy.deepcopy(self.fixture_document)
                fixture_document["selected_fixture_ids"] = [first_id, second_id]
                first_fixture = copy.deepcopy(fixture_document["fixtures"][0])
                first_fixture["fixture_id"] = first_id
                second_fixture = copy.deepcopy(first_fixture)
                second_fixture["fixture_id"] = second_id
                second_fixture["order"] = 1
                fixture_document["fixtures"] = [first_fixture, second_fixture]
                self._rebind_inputs(plan=plan, fixture_manifest=fixture_document)

                with self.assertRaises(api.FixtureStagingError) as caught:
                    self._authorize()

                self.assertEqual(
                    caught.exception.code,
                    api.FixtureStagingErrorCode.MANIFEST_INVALID,
                )

    def test_duplicate_manifest_keys_and_traversing_member_paths_are_rejected(self) -> None:
        api = self._require_staging_module()
        self.fixture_path.write_text(
            '{"schema_version":1,"schema_version":1}', encoding="utf-8"
        )
        with self.assertRaises(api.FixtureStagingError) as duplicate:
            self._authorize()
        self.assertEqual(
            duplicate.exception.code, api.FixtureStagingErrorCode.INPUT_INVALID
        )

        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture["entrypoint"] = "../game.rom"
        fixture["files"][0]["path"] = "../game.rom"
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)
        with self.assertRaises(api.FixtureStagingError) as traversal:
            self._authorize()
        self.assertEqual(
            traversal.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID
        )

    def test_self_declared_independent_identity_label_is_rejected(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["fixtures"][0]["identity_evidence"] = "independent_oracle"
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID)

    def test_identity_evidence_must_use_the_sanitized_expectation_label(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["fixtures"][0]["identity_evidence"] = True
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID)

    def test_companion_cycles_are_rejected_while_loading_the_manifest(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture_document["fixtures"][0]["companions"] = [
            {"source": "game.rom", "target": "game.rom"}
        ]
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID)

    def test_unreachable_declared_companion_members_are_rejected_before_grant(self) -> None:
        api = self._require_staging_module()
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture["files"].append(
            {
                "path": "orphan.rom",
                "role": "companion",
                "size": 1,
                "sha256": hashlib.sha256(b"x").hexdigest(),
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)

        with self.assertRaises(api.FixtureStagingError) as caught:
            self._authorize()

        self.assertEqual(caught.exception.code, api.FixtureStagingErrorCode.MANIFEST_INVALID)

    def test_grant_is_invalidated_when_pinned_inputs_or_approval_change(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        changed_plan = copy.deepcopy(self.plan_document)
        changed_plan["host_reserve_bytes"] = 1
        write_private_json(self.directory, "plan.json", changed_plan)
        with self.assertRaises(api.FixtureStagingError) as plan_change:
            _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )
        self.assertEqual(
            plan_change.exception.code, api.FixtureStagingErrorCode.DIGEST_MISMATCH
        )

        self._rebind_inputs()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-approval-change"
        )
        write_private_json(
            self.directory,
            "approval.json",
            approval_document("0" * 64),
        )
        with self.assertRaises(api.FixtureStagingError) as approval_change:
            _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )
        self.assertEqual(
            approval_change.exception.code,
            api.FixtureStagingErrorCode.INVALID_AUTHORITY,
        )

    def test_approval_expiry_during_copy_ignores_the_supplied_start_time(self) -> None:
        api = self._require_staging_module()
        grant_holder = [None]
        observations = [0]

        def expire_during_copy(_root):
            observations[0] += 1
            if observations[0] == 2:
                self.staging_now[0] = grant_holder[0]._approval.valid_until
                self.staging_monotonic_ns[0] += (
                    staging_model._datetime_ns(grant_holder[0]._approval.valid_until)
                    - staging_model._datetime_ns(NOW)
                )
            return api.CapacityObservation(10**12, 10**12)

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=expire_during_copy
        )
        grant_holder[0] = grant

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
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())

    def test_monotonic_time_cannot_outlive_authorization_and_approval(self) -> None:
        api = self._require_staging_module()
        self.authorization_document["session_deadline_utc"] = (
            "2030-01-01T00:01:10Z"
        )
        self.authorization_path = write_private_json(
            self.directory, "authorization.json", self.authorization_document
        )
        self.authorization = manifest.load_authorization(self.authorization_path)
        approval = approval_document(self.authorization.canonical_sha256)
        approval["valid_until_utc"] = "2030-01-01T00:01:10Z"
        self.approval_path = write_private_json(
            self.directory, "approval.json", approval
        )
        self.approval = manifest.load_owner_approval(
            self.approval_path, self.authorization, now=NOW
        )
        elapsed = [0]

        class SlowDestination(api.FilesystemFixtureDestination):
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
                def delayed_chunks():
                    for chunk in chunks:
                        elapsed[0] = 11_000_000_000
                        yield chunk

                return super()._write_file(
                    session_id,
                    fixture_id,
                    relative_path,
                    delayed_chunks(),
                    ownership_token=ownership_token,
                    source_mtime_ns=source_mtime_ns,
                    grant=grant,
                    capability=capability,
                )

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            destination_type=SlowDestination
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
            monotonic_clock=lambda: elapsed[0],
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())

    def test_plan_parent_identity_change_invalidates_an_unchanged_pinned_file(self) -> None:
        api = self._require_staging_module()
        original_parent = self.directory / "private-plan"
        original_parent.mkdir(mode=0o700)
        plan_path = write_private_json(
            original_parent, "plan.json", self.plan_document
        )
        grant = api.authorize_fixture_staging(
            self.authorization,
            self.approval,
            plan_path=plan_path,
            fixture_manifest_path=self.fixture_path,
            operation_id="fixture-stage-synthetic",
        )
        original_file_identity = plan_path.stat(follow_symlinks=False)
        self.assertEqual(
            getattr(grant._plan_pin, "parent_inode", None),
            original_parent.stat(follow_symlinks=False).st_ino,
        )
        displaced_parent = self.directory / "displaced-plan"
        original_parent.rename(displaced_parent)
        original_parent.mkdir(mode=0o700)
        os.rename(displaced_parent / "plan.json", plan_path)
        displaced_parent.rmdir()
        self.assertEqual(
            plan_path.stat(follow_symlinks=False).st_ino,
            original_file_identity.st_ino,
        )
        changed_parent_pin = copy.copy(grant._plan_pin)
        object.__setattr__(changed_parent_pin, "parent_device", plan_path.parent.stat().st_dev)
        object.__setattr__(changed_parent_pin, "parent_inode", plan_path.parent.stat().st_ino)
        with patch.object(staging_manifest, "_private_document",
            return_value=({}, b"same-document", changed_parent_pin),
        ):
            self.assertFalse(staging_manifest._private_pin_matches(grant._plan_pin))

        api, source_root, destination, _grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            grant=grant
        )
        with self.assertRaises(api.FixtureStagingError) as caught:
            _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(
            caught.exception.code, api.FixtureStagingErrorCode.DIGEST_MISMATCH
        )
        self.assertEqual(destination._ownership.recovery_obligations(), ())

    def test_cleanup_requires_pinned_explicit_authorization_and_proves_tree_ownership(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        blocked = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )
        self.assertEqual(blocked.status, "BLOCKED")
        self.assertEqual(
            blocked.blocker_code,
            api.FixtureStagingErrorCode.CLEANUP_UNAUTHORIZED.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_destination_delete_api_enforces_cleanup_authority_itself(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        state = destination._ownership._load_state(staged.session_id)

        with self.assertRaises(api.FixtureStagingError) as caught:
            destination._ownership.remove_owned_session(
                staged.session_id,
                state["ownership_token"],
                grant=grant,
                now=NOW,
            capability=self.synthetic_capability, )

        self.assertEqual(
            caught.exception.code,
            api.FixtureStagingErrorCode.CLEANUP_UNAUTHORIZED,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_cleanup_cannot_replace_the_original_operation_deadline(self) -> None:
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
        self.staging_now[0] = grant._approval.valid_until
        self.staging_monotonic_ns[0] += (
            staging_model._datetime_ns(grant._approval.valid_until)
            - staging_model._datetime_ns(NOW)
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
            api.FixtureStagingErrorCode.OPERATION_TIMEOUT.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        self.assertEqual(
            destination._ownership._load_state(staged.session_id)["state"],
            "blocked",
        )

    def test_owned_session_removal_uses_cleanup_authority_after_approval_expiry(self) -> None:
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
        state = destination._ownership._load_state(staged.session_id)
        self.staging_now[0] = grant._approval.valid_until

        with self.assertRaises(api.FixtureStagingError) as caught:
            destination._ownership.remove_owned_session(
                staged.session_id,
                state["ownership_token"],
                grant=grant,
                now=NOW,
            capability=self.synthetic_capability, )
        self.assertEqual(
            caught.exception.code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
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
        self.assertEqual(
            destination._ownership._load_state(staged.session_id)["state"],
            "blocked",
        )

    def test_same_boot_restart_retains_the_original_monotonic_timeline(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        self.staging_monotonic_ns[0] = 100_000_000_000
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        restarted_destination = api.FilesystemFixtureDestination(destination.root)
        self.staging_monotonic_ns[0] = 101_000_000_000

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=restarted_destination,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_boot_or_monotonic_discontinuity_fails_closed(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        self.staging_monotonic_ns[0] = 100_000_000_000
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.staging_monotonic_ns[0] = 99_000_000_000

        rewound = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )
        self.staging_boot = (
            "fedcba98-7654-3210-fedc-ba9876543210",
            "linux-boot-id",
        )
        restarted_boot = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertEqual(rewound.status, "BLOCKED")
        self.assertEqual(
            rewound.blocker_code,
            api.FixtureStagingErrorCode.TIMING_UNVERIFIED.value,
        )
        self.assertEqual(restarted_boot.status, "BLOCKED")
        self.assertEqual(
            restarted_boot.blocker_code,
            api.FixtureStagingErrorCode.TIMING_UNVERIFIED.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_missing_operation_timing_fails_closed(self) -> None:
        api = self._require_staging_module()

        with self.assertRaises(api.FixtureStagingError) as caught:
            staging_model._check_operation_timing(
                None,
                clock=lambda: 0.0,
                mode="cleanup",
            )

        self.assertEqual(
            caught.exception.code,
            staging_model.FixtureStagingErrorCode.TIMING_UNVERIFIED,
        )

    def test_cleanup_rechecks_authority_before_blocking_and_retains_data(self) -> None:
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
        original_proof = destination._ownership._ownership_is_proven
        expired = [False]

        def expire_during_proof(record, session_id):
            if not expired[0]:
                expired[0] = True
                self.staging_now[0] = grant._authorization.cleanup_deadline
            return original_proof(record, session_id)

        with patch.object(
            destination._ownership,
            "_ownership_is_proven",
            side_effect=expire_during_proof,
        ):
            interrupted = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertEqual(interrupted.status, "BLOCKED")
        self.assertEqual(
            interrupted.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["state"], "blocked")
        self.assertEqual(state["blocker_code"], interrupted.blocker_code)
        self.assertTrue(destination._ownership._ownership_is_proven(state, staged.session_id))

        denied_resume = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )
        self.assertEqual(denied_resume.status, "BLOCKED")
        self.assertEqual(
            denied_resume.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

        self.staging_now[0] = NOW
        recovered = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )
        self.assertEqual(recovered.status, "BLOCKED")
        self.assertEqual(
            recovered.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_cleanup_expiry_uses_monotonic_time_after_wall_clock_moves_back(self) -> None:
        self.authorization_document["operations"][-1]["timeout_seconds"] = 600
        self.authorization_document["reserves"]["cleanup_seconds"] = 600
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
        expiry = grant._authorization.cleanup_deadline
        self.staging_now[0] = expiry - timedelta(seconds=1)
        elapsed = [
            self.staging_monotonic_ns[0]
            + staging_model._datetime_ns(expiry) - staging_model._datetime_ns(NOW)
            - 1_000_000_000
        ]
        original_proof = destination._ownership._ownership_is_proven

        def pass_expiry_and_move_wall_clock_back(record, session_id):
            elapsed[0] += 2_000_000_000
            self.staging_monotonic_ns[0] = elapsed[0]
            self.staging_now[0] = NOW
            return original_proof(record, session_id)

        with (
            patch.object(
                staging_ownership,
                "_monotonic_now",
                side_effect=lambda: elapsed[0],
            ),
            patch.object(
                destination._ownership,
                "_ownership_is_proven",
                side_effect=pass_expiry_and_move_wall_clock_back,
            ),
        ):
            interrupted = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                destination=destination,
                session_id=staged.session_id,
                now=NOW,
            )

        self.assertEqual(interrupted.status, "BLOCKED")
        self.assertEqual(
            interrupted.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["state"], "blocked")
        self.assertEqual(state["blocker_code"], interrupted.blocker_code)
        self.assertTrue(destination._ownership._ownership_is_proven(state, staged.session_id))

    def test_cleanup_uses_the_post_session_authorized_window(self) -> None:
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
        self.staging_now[0] = grant._authorization.session_deadline + timedelta(seconds=1)
        self.staging_monotonic_ns[0] += (
            staging_model._datetime_ns(grant._authorization.session_deadline + timedelta(seconds=1))
            - staging_model._datetime_ns(NOW)
        )

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.OPERATION_TIMEOUT.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_cleanup_rejects_the_cleanup_deadline_despite_historical_now_override(self) -> None:
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
        self.staging_now[0] = grant._authorization.cleanup_deadline

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant, destination=destination, session_id=staged.session_id, now=NOW
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.AUTHORIZATION_EXPIRED.value,
        )
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())
        self.assertEqual(
            destination._ownership._load_state(staged.session_id)["state"], "published"
        )

    def test_cleanup_reserve_is_anchored_inside_the_original_operation_timeline(self) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        self.authorization_document["operations"][0]["restoration"]["timeout_seconds"] = 10
        self.authorization_document["reserves"]["cleanup_seconds"] = 10
        self._rebind_inputs()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        state = destination._ownership._load_state(staged.session_id)
        timing = state["operation_timing"]
        operation_deadline = timing["operation_deadline_monotonic_ns"]
        self.assertEqual(
            timing["cleanup_reserve_deadline_monotonic_ns"],
            operation_deadline - 10 * 1_000_000_000,
        )

        restarted = api.FilesystemFixtureDestination(destination.root)
        self.staging_monotonic_ns[0] = (
            timing["monotonic_start_ns"] + 25 * 1_000_000_000
        )
        recovery = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=restarted,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertEqual(recovery.status, "BLOCKED")
        self.assertEqual(
            recovery.blocker_code,
            api.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        state = destination._ownership._load_state(staged.session_id)
        self.assertEqual(state["state"], "published")
        self.assertIsNone(state["blocker_code"])
        self.assertTrue(destination._ownership._ownership_is_proven(state, staged.session_id))
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_expired_original_operation_blocks_cleanup_despite_history_override(
        self,
    ) -> None:
        plan = copy.deepcopy(self.plan_document)
        plan["cleanup_authorized"] = True
        self._rebind_inputs(plan=plan)
        self.authorization_document["operations"][0]["restoration"]["timeout_seconds"] = 10
        self.authorization_document["reserves"]["cleanup_seconds"] = 10
        self._rebind_inputs()
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        staged = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        timing = destination._ownership._load_state(
            staged.session_id
        )["operation_timing"]
        self.staging_monotonic_ns[0] = timing["operation_deadline_monotonic_ns"]

        cleanup = _cleanup_fixture_staging_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            destination=destination,
            session_id=staged.session_id,
            now=NOW,
        )

        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            api.FixtureStagingErrorCode.OPERATION_TIMEOUT.value,
        )
        self.assertFalse(cleanup.removed)
        self.assertTrue(destination._synthetic_final_path(staged.session_id).exists())

    def test_concurrent_fixed_session_reservation_leaves_one_durable_record(self) -> None:
        fixed_session_id = "a" * 32
        api, _source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            session_id_factory=lambda: fixed_session_id
        )
        start = threading.Barrier(3)
        reservations = []
        failures = []

        def reserve_concurrently():
            try:
                start.wait(timeout=5)
                worker_capability = (
                    staging_ownership._issue_synthetic_namespace_capability(
                        owner=destination._ownership._synthetic_owner
                    )
                )
                reservations.append(
                destination._ownership.reserve_session(
                    grant,
                        capability=worker_capability,
                )
                    )
            except api.FixtureStagingError as error:
                failures.append(error.code)
            except BaseException as error:
                failures.append(error)

        callers = [threading.Thread(target=reserve_concurrently) for _ in range(2)]
        for caller in callers:
            caller.start()
        start.wait(timeout=5)
        for caller in callers:
            caller.join(timeout=5)

        self.assertFalse(any(caller.is_alive() for caller in callers))
        self.assertEqual(len(reservations), 1)
        self.assertEqual(failures, [api.FixtureStagingErrorCode.OWNERSHIP_UNPROVEN])
        state_directory = destination.root / destination._ownership._STATE_DIRECTORY
        self.assertEqual(
            sorted(path.name for path in state_directory.glob("*.json")),
            [f"{fixed_session_id}.00000000.json"],
        )
        self.assertFalse(tuple(state_directory.glob("*.tmp")))
