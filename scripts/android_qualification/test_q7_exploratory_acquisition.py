"""Host-only tests for bounded, redacted Q7 exploratory acquisition."""

import inspect
import json
import os
import selectors
import stat
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

from . import readiness_probe as probe
from . import readiness_probe_artifact
from . import packaging
from . import q7_exploratory_acquisition as q7_module
from .q7_exploratory_acquisition import (
    APPROVED_BASELINE_COMMIT,
    Q7CommandResult,
    Q7StructuralFilter,
    _run_q7_observation_for_serial as run_q7_observation,
    run_q7_from_identity_outcome,
    run_readiness_activity_snapshot_from_identity_outcome,
)
from .adb_forward import _AdbCommandRunner, _MAX_Q7_OUTPUT_BYTES


TARGET = "SERIAL-TEST"
TARGET_REF = "i74-tgt-7f6cd8181514b822"
TARGET_PACKAGE = q7_module._TARGET_PACKAGE
SOURCE_IDENTITY = q7_module._source_identity()


def identity_preflight_record(target_reference=TARGET_REF, serial=TARGET):
    return {
        "schema": "argus-issue-74-identity-preflight-outcome-v1",
        "target_reference": target_reference,
        "target_model": "KONKR Pocket Advance",
        "classification": "PASS",
        "scope": "bounded read-only identity preflight only; no B1 authority",
        "retention_days_per_attempt": 180,
        "storage_budget_mb": 100,
        "external_receipt_required_for_this_attempt": False,
        "outcome_receipt_created": False,
        "selected_serial_private": serial,
        "acquisition": {
            "commands": {"fingerprint": 1, "get_state": 1, "unexpected": 0},
            "validated_get_state": "device",
            "returned_target_binding_matches": True,
            "deadline_met": True,
            "failure_code": None,
            "retries": 0,
            "raw_stdout_retained": False,
            "stderr_retained": False,
            "fingerprint_observed_private": (
                "brand/device:version/id/incremental:user/release-keys"
            ),
        },
        "source": {
            "repository": "whatobiplays/Argus-ROM-Toolkit",
            "reviewed_merge_commit": APPROVED_BASELINE_COMMIT,
            "executed_revision": APPROVED_BASELINE_COMMIT,
            "working_tree_clean": True,
            "adapter_path": "scripts/android_qualification/adb_forward.py",
            "adapter_sha256": "d" * 64,
            "procedure_path": "docs/qualification/android-readiness-probe.md",
            "procedure_sha256": "e" * 64,
        },
    }


def write_identity_fixture(directory, *, target_reference=TARGET_REF, serial=TARGET):
    path = Path(directory) / "identity-preflight.json"
    path.write_text(json.dumps(identity_preflight_record(target_reference, serial)))
    os.chmod(path, 0o600)
    return path


def call_public_q7(outcomes, runner, utc_clock):
    with patch.object(q7_module, "_AdbCommandRunner", return_value=runner):
        with patch.object(q7_module, "_utc_now", side_effect=utc_clock):
            return run_q7_from_identity_outcome(outcomes)


def call_public_readiness_snapshot(outcomes, runner, utc_clock):
    with patch.object(q7_module, "_AdbCommandRunner", return_value=runner):
        with patch.object(q7_module, "_utc_now", side_effect=utc_clock):
            return run_readiness_activity_snapshot_from_identity_outcome(outcomes)


class FakeClock:
    def __init__(self, value=100.0):
        self.value = value

    def __call__(self):
        return self.value


class LateDeadlineClock:
    def __init__(self):
        self.values = iter((100.0, 100.0, 106.0, 106.0))
        self.last = 106.0

    def __call__(self):
        self.last = next(self.values, self.last)
        return self.last


class FakePipe:
    def __init__(self, fd):
        self.fd = fd
        self.closed = False

    def fileno(self):
        return self.fd

    def close(self):
        self.closed = True


class FakeSelector:
    def __init__(self, *, clock, expire=False):
        self.clock = clock
        self.expire = expire
        self.keys = {}
        self.closed = False

    def register(self, fileobj, _events):
        self.keys[fileobj.fileno()] = SimpleNamespace(
            fileobj=fileobj, fd=fileobj.fileno()
        )

    def unregister(self, fileobj):
        self.keys.pop(fileobj.fileno())

    def get_map(self):
        return self.keys

    def select(self, timeout):
        if self.expire:
            self.clock.value += timeout
            return []
        return [(key, selectors.EVENT_READ) for key in self.keys.values()]

    def close(self):
        self.closed = True


class FakeProcess:
    def __init__(self, returncode=0):
        self.pid = 7123
        self.stdout = FakePipe(10)
        self.stderr = FakePipe(11)
        self.returncode = returncode
        self.killed = False
        self.wait_timeouts = []

    def wait(self, timeout=None):
        self.wait_timeouts.append(timeout)
        return -9 if self.killed else self.returncode

    def kill(self):
        self.killed = True


class RealQ7RunnerHarness:
    def __init__(self, chunks, *, expire=False, returncode=0):
        self.clock = FakeClock()
        self.selector = FakeSelector(clock=self.clock, expire=expire)
        self.process = FakeProcess(returncode=returncode)
        self.remaining = {10: bytearray(chunks[0]), 11: bytearray(chunks[1])}
        self.popen_calls = []
        self.kill_groups = []
        self.read_request_sizes = []

        def popen(argv, **options):
            self.popen_calls.append((tuple(argv), options))
            return self.process

        def reader(fd, count):
            self.read_request_sizes.append(count)
            pending = self.remaining[fd]
            if not pending:
                return b""
            result = bytes(pending[:count])
            del pending[:count]
            return result

        def waitid(_idtype, pid, _options):
            if self.process.returncode is None and not self.process.killed:
                return None
            return SimpleNamespace(si_pid=pid)

        def kill_group(pid, signum):
            self.kill_groups.append((pid, signum))
            if self.process.returncode is None:
                self.process.kill()
                return
            raise ProcessLookupError

        def sleep_for(timeout):
            self.clock.value += timeout

        self.runner = _AdbCommandRunner(
            clock=self.clock,
            popen=popen,
            selector_factory=lambda: self.selector,
            reader=reader,
            kill_group=kill_group,
            process_group_is_quiescent=lambda *_args, **_kwargs: False,
            waitid=waitid,
            sleep=sleep_for,
        )


class FakeQ7Runner:
    def __init__(self, result=None, chunks=()):
        self.result = result
        self.chunks = tuple(chunks)
        self.targets = []

    def run_q7(self, target, stdout_consumer):
        self.targets.append(target)
        for chunk in self.chunks:
            stdout_consumer(chunk)
        if self.result is not None:
            return self.result
        stdout_bytes = sum(len(chunk) for chunk in self.chunks)
        return Q7CommandResult(
            command_count=1,
            started_monotonic=10.0,
            finished_monotonic=10.4,
            stdout_bytes=stdout_bytes,
            total_output_bytes=stdout_bytes,
            exit_code=0,
            classification="exit_zero",
            cleanup_complete=True,
        )


class Q7StructuralFilterTests(unittest.TestCase):
    def test_q7_target_package_matches_qualification_artifact_identity(self):
        self.assertEqual(
            q7_module._TARGET_PACKAGE, packaging.QUALIFICATION_APPLICATION_ID
        )
        self.assertNotEqual(
            q7_module._TARGET_PACKAGE, readiness_probe_artifact.PACKAGE
        )

    def test_filter_can_project_only_the_allowlisted_readiness_package(self):
        readiness_package = readiness_probe_artifact.PACKAGE
        raw = (
            f"ActivityRecord{{qualification-activity u0 {TARGET_PACKAGE}/.Main t3}}\n"
            f"Task{{readiness-task #7 A={readiness_package} U=0 displayId=0}}\n"
            f"  ActivityRecord{{readiness-activity u0 {readiness_package}/.LauncherActivity t7}}\n"
            "    mResumed=true\n"
            f"ActivityRecord{{unrelated-activity u0 unrelated.app/.Home t8}}\n"
        ).encode("ascii")
        parser = Q7StructuralFilter(target_package=readiness_package)
        parser.feed(raw)

        result = parser.finish()

        self.assertTrue(result["target_component_observed"])
        self.assertIn("component", result["structure"]["field_names"])
        rendered = json.dumps(result, sort_keys=True)
        for package in (TARGET_PACKAGE, readiness_package, "unrelated.app"):
            self.assertNotIn(package, rendered)
        self.assertEqual(
            [item["record_type"] for item in result["structure"]["records"]],
            ["task", "activity_record"],
        )

    def test_filter_rejects_a_package_outside_the_two_fixed_targets(self):
        with self.assertRaises(probe.ProbeError) as raised:
            Q7StructuralFilter(target_package="unrelated.app")

        self.assertEqual(raised.exception.code, "MalformedRequest")

    def test_readiness_snapshot_entrypoint_uses_private_identity_and_persists_projection(self):
        package = readiness_probe_artifact.PACKAGE
        raw = (
            f"Task{{task-object #42 A={package} U=0 displayId=0}}\n"
            f"  ActivityRecord{{activity-object u0 {package}/.LauncherActivity t42}}\n"
            "    mResumed=true\n"
        ).encode("ascii")
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            record = call_public_readiness_snapshot(
                outcomes,
                FakeQ7Runner(chunks=(raw,)),
                lambda: "2026-11-21T12:00:00.000Z",
            )

            persisted = next(outcomes.glob("q7-exploratory-*.json"))
            stored = json.loads(persisted.read_text())

        self.assertEqual(record["subject_package"], package)
        self.assertEqual(stored["subject_package"], package)
        self.assertTrue(record["observation"]["target_component_observed"])
        self.assertFalse(record["qualification_assertions_passed"])
        rendered = json.dumps(stored, sort_keys=True)
        self.assertNotIn(TARGET_PACKAGE, rendered)
        self.assertNotIn("unrelated.app", rendered)

    def test_record_validator_rejects_unapproved_subject_package(self):
        raw = f"ActivityRecord{{target-object u0 {TARGET_PACKAGE}/.Main}}\n".encode()
        record = run_q7_observation(TARGET, runner=FakeQ7Runner(chunks=(raw,)))
        record["subject_package"] = "unrelated.app"

        with self.assertRaises(probe.ProbeError) as raised:
            q7_module._validate_record(record)

        self.assertEqual(raised.exception.code, "MalformedRequest")

    def test_affinity_values_cannot_select_a_record_as_the_target_app(self):
        for raw in (
            f"ActivityRecord{{foreign-activity u0 unrelated.app/.Home "
            f"taskAffinity={TARGET_PACKAGE}}}\n".encode(),
            f"ActivityRecord{{foreign-activity u0 unrelated.app/.Home "
            f"affinity={TARGET_PACKAGE}}}\n".encode(),
            f"ActivityRecord{{foreign-activity u0 unrelated.app/.Home "
            f"rootAffinity={TARGET_PACKAGE}}}\n".encode(),
            f"Task{{foreign-task A={TARGET_PACKAGE}}}\n".encode(),
            f"ProcessRecord{{foreign-process 123:{TARGET_PACKAGE}/u0a123}}\n".encode(),
            f"taskAffinity={TARGET_PACKAGE} displayId=4 mResumed=true "
            "windowingMode=fullscreen\n".encode(),
        ):
            with self.subTest(record=raw.split(b"{")[0]):
                parser = Q7StructuralFilter()
                parser.feed(raw)

                structure = parser.finish()["structure"]

                self.assertEqual(structure["records"], [])
                self.assertEqual(structure["fields"], [])

    def test_wrong_record_type_is_not_added_as_task_display_or_process_context(self):
        raw = (
            f"ActivityRecord{{target-activity u0 {TARGET_PACKAGE}/.Main}}\n"
            "  taskId=ActivityRecord{foreign-activity}\n"
            "  displayId=ActivityRecord{foreign-display}\n"
            "  app=ActivityRecord{foreign-process}\n"
            "ActivityRecord{foreign-activity u0 unrelated.app/.Other}\n"
            "ActivityRecord{foreign-display u0 unrelated.app/.Display}\n"
            "ActivityRecord{foreign-process u0 unrelated.app/.Process}\n"
        ).encode()
        parser = Q7StructuralFilter()
        parser.feed(raw)

        structure = parser.finish()["structure"]

        self.assertEqual(
            [item["record_type"] for item in structure["records"]],
            ["activity_record"],
        )
        self.assertNotIn("foreign-activity", json.dumps(structure, sort_keys=True))

    def test_keeps_a_target_component_from_an_unscoped_activity_line(self):
        parser = Q7StructuralFilter()
        parser.feed(f"ACTIVITY {TARGET_PACKAGE}/.Main t42 userId=0\n".encode())

        result = parser.finish()

        self.assertEqual(result["structure"]["records"], [])
        self.assertIn("component", result["structure"]["field_names"])
        self.assertIn("android_user_fields", result["available_field_categories"])
        self.assertNotIn(TARGET_PACKAGE, json.dumps(result, sort_keys=True))

    def test_collects_only_structural_categories_and_never_keeps_identifiers(self):
        raw = (
            f"ACTIVITY {TARGET_PACKAGE}/.Secret t481 userId=10917\n"
            f"Task{{TASK-91 #481 type=standard A={TARGET_PACKAGE} "
            "displayId=7 windowingMode=fullscreen}\n".encode()
            + f"  ActivityRecord{{PID-771 u0 {TARGET_PACKAGE}/.Secret t481}}\n".encode()
            + f"    mResumedActivity: ActivityRecord{{PID-771 "
            f"cmp={TARGET_PACKAGE}/.Secret}}\n".encode()
            + f"    topResumedActivity=ActivityRecord{{PID-771 "
            f"cmp={TARGET_PACKAGE}/.Secret}}\n".encode()
            + b"    app=ProcessRecord{PROCESS-82}\n"
            + f"  ProcessRecord{{PROCESS-82 771:{TARGET_PACKAGE}/u0a123}}\n".encode()
            + b"    lastActiveTime=123456\n"
        )
        parser = Q7StructuralFilter()

        for offset in range(0, len(raw), 13):
            parser.feed(raw[offset : offset + 13])
        result = parser.finish()
        rendered = json.dumps(result, sort_keys=True)

        self.assertEqual(result["available_field_categories"], [
            "activity_records",
            "android_user_fields",
            "component_fields",
            "display_fields",
            "process_fields",
            "resumed_state_fields",
            "task_continuity_markers",
            "task_membership_fields",
            "top_resumed_fields",
            "windowing_fields",
        ])
        self.assertIn("component", result["structure"]["field_names"])
        for private_value in (
            "com.private.app",
            ".Secret",
            "PID-771",
            "TASK-91",
            "PROCESS-82",
            "10917",
            "123456",
        ):
            self.assertNotIn(private_value, rendered)
        self.assertEqual(parser._records, [])
        self.assertEqual(parser._fields, [])
        self.assertEqual(parser._relationships, {})
        self.assertFalse(result["task_continuity_established"])
        self.assertFalse(result["target_binding_established"])
        self.assertFalse(result["completion_verified"])

    def test_preserves_structural_associations_with_anonymized_identifiers(self):
        raw = (
            b"RootWindowContainer{root-object}\n"
            + f"  Task{{task-object #42 type=standard A={TARGET_PACKAGE} U=0 "
            "displayId=0 mode=fullscreen}\n".encode()
            + f"    ActivityRecord{{activity-object u0 "
            f"{TARGET_PACKAGE}/.MainActivity t42}}\n".encode()
            + f"      mActivityComponent={TARGET_PACKAGE}/.MainActivity\n".encode()
            + b"      userId=0\n"
            + b"      taskId=42\n"
            + b"      displayId=0\n"
            + b"      windowingMode=fullscreen\n"
            + b"      mResumed=true\n"
            + b"      topResumedActivity=ActivityRecord{activity-object}\n"
            + b"      mResumedActivity=ActivityRecord{other-object}\n"
            + b"      app=ProcessRecord{process-object}\n"
            + f"      processName={TARGET_PACKAGE}\n".encode()
            + b"      pid=31415\n"
            + f"    ProcessRecord{{process-object 31415:{TARGET_PACKAGE}/u0a123}}\n".encode()
            + f"      mIntent=Intent{{cmp={TARGET_PACKAGE}/.Secret "
            "data=file:///private/owner/application data}\n".encode()
            + b"    ActivityRecord{other-object u0 "
            + b"com.unrelated.secret/.Home t42}\n"
            + b"      unrelatedOnly=do-not-retain\n"
            + b"      mResumed=true\n"
        )
        parser = Q7StructuralFilter()
        parser.feed(raw)

        result = parser.finish()
        structure = result["structure"]
        activity_records = [
            item for item in structure["records"]
            if item["record_type"] == "activity_record"
        ]
        activity_fields = [
            item for item in structure["fields"]
            if item["record_ref"] == activity_records[0]["record_ref"]
        ]
        fields_by_name = {item["name"]: item for item in activity_fields}
        rendered = json.dumps(result, sort_keys=True)

        self.assertEqual(len(activity_records), 1)
        self.assertEqual(
            structure["record_type_names"],
            ["activity_record", "process_record", "root_window_container", "task"],
        )
        self.assertIn("mActivityComponent", structure["field_names"])
        self.assertIn("topResumedActivity", structure["field_names"])
        self.assertNotIn("mResumedActivity", structure["field_names"])
        self.assertEqual(fields_by_name["mResumed"]["value"], True)
        self.assertEqual(fields_by_name["windowingMode"]["value"], "fullscreen")
        self.assertIn(
            "mIntent",
            result["redacted_field_names"],
        )
        self.assertEqual(
            fields_by_name["topResumedActivity"]["value_ref"],
            activity_records[0]["record_ref"],
        )
        self.assertEqual(
            fields_by_name["userId"]["value_ref"],
            next(
                item["value_ref"] for item in activity_fields
                if item["name"] == "user"
            ),
        )
        self.assertTrue(
            any(item["kind"] == "layout_parent" for item in structure["relationships"])
        )
        self.assertTrue(
            any(item["kind"] == "activity_task" for item in structure["relationships"])
        )
        self.assertTrue(
            any(item["kind"] == "component_package" for item in structure["relationships"])
        )
        self.assertTrue(
            any(item["kind"] == "process_package" for item in structure["relationships"])
        )
        self.assertTrue(
            any(item["kind"] == "record_display" for item in structure["relationships"])
        )
        self.assertTrue(
            any(item["kind"] == "record_process" for item in structure["relationships"])
        )
        self.assertTrue(result["intent_content_observed"])
        for private_value in (
            "root-object",
            "task-object",
            "activity-object",
            "process-object",
            "other-object",
            TARGET_PACKAGE,
            ".MainActivity",
            "com.unrelated.secret",
            ".Home",
            ".Secret",
            "31415",
            "file:///private/owner",
            "unrelatedOnly",
            "do-not-retain",
        ):
            self.assertNotIn(private_value, rendered)

    def test_duplicate_component_records_remain_distinct_and_ambiguous(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{record-one u0 {TARGET_PACKAGE}/.Same t8}}\n"
            f"ActivityRecord{{record-two u0 {TARGET_PACKAGE}/.Same t8}}\n".encode()
        )

        structure = parser.finish()["structure"]
        records = [
            item for item in structure["records"]
            if item["record_type"] == "activity_record"
        ]
        component_refs = [
            item["value_ref"] for item in structure["fields"]
            if item["name"] == "component"
        ]

        self.assertEqual(len(records), 2)
        self.assertNotEqual(records[0]["record_ref"], records[1]["record_ref"])
        self.assertEqual(component_refs[0], component_refs[1])

    def test_field_on_line_with_multiple_records_has_ambiguous_association(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{first-record u0 {TARGET_PACKAGE}/.Main}} "
            "Task{second-task #9} displayId=0\n".encode()
        )

        structure = parser.finish()["structure"]
        display_field = next(
            item for item in structure["fields"] if item["name"] == "displayId"
        )

        self.assertIsNone(display_field["record_ref"])
        self.assertEqual(display_field["association"], "ambiguous")
        self.assertEqual(
            {item["record_type"] for item in structure["records"]},
            {"activity_record"},
        )

    def test_unrecognized_field_label_is_counted_without_retaining_its_text(self):
        parser = Q7StructuralFilter()
        parser.feed(b"com.private.app=unexpected-value\n")

        result = parser.finish()
        rendered = json.dumps(result, sort_keys=True)

        self.assertEqual(result["structure"]["unrecognized_field_count"], 1)
        self.assertNotIn("com.private.app", rendered)
        self.assertNotIn("unexpected-value", rendered)

    def test_structural_record_limit_discards_partial_structure(self):
        parser = Q7StructuralFilter(maximum_records=1)

        with self.assertRaises(probe.ProbeError) as raised:
            parser.feed(
                b"Task{first-task #1}\n"
                b"ActivityRecord{second-record u0 pkg/.Screen t1}\n"
            )

        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")
        self.assertEqual(parser.retained_bytes, 0)
        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "record_limit_exceeded")
        self.assertEqual(diagnostic["stage"], "record_scan")
        self.assertEqual(diagnostic["line_number"], 2)
        self.assertEqual(diagnostic["line_byte_offset"], 0)
        self.assertEqual(diagnostic["parser_state"]["records_seen"], 1)
        with self.assertRaises(probe.ProbeError):
            parser.finish()

    def test_timeout_and_completion_indicators_are_only_boolean_findings(self):
        parser = Q7StructuralFilter()
        parser.feed(b"Service timeout: activity dump timed out\nDump complete\n")

        result = parser.finish()

        self.assertTrue(result["timeout_indicator_observed"])
        self.assertTrue(result["completion_indicator_observed"])
        self.assertTrue(result["eof_observed"])
        self.assertFalse(result["completion_verified"])

    def test_accepts_a_line_at_the_limit_and_rejects_one_byte_over(self):
        parser = Q7StructuralFilter()
        parser.feed(b"x" * 16384 + b"\n")
        self.assertEqual(parser.finish()["max_line_bytes"], 16384)

        parser = Q7StructuralFilter()
        parser.feed(b"x" * 16384)
        with self.assertRaises(probe.ProbeError) as raised:
            parser.feed(b"x")
        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")
        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "line_length_exceeded")
        self.assertEqual(diagnostic["line_number"], 1)
        self.assertEqual(diagnostic["line_byte_offset"], 16384)
        self.assertEqual(diagnostic["absolute_byte_offset"], 16384)
        self.assertEqual(parser.discard(), None)

    def test_rejects_invalid_utf8_without_returning_partial_findings(self):
        parser = Q7StructuralFilter()
        first_line = (
            b"mResumedActivity: ActivityRecord{record-object u0 "
            b"private.pkg/.Secret t1}\n"
        )
        parser.feed(first_line)
        parser.feed(b"bad")

        with self.assertRaises(probe.ProbeError):
            parser.feed(b"\xff\n")
        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "invalid_utf8")
        self.assertEqual(diagnostic["stage"], "utf8_decode")
        self.assertEqual(diagnostic["line_number"], 2)
        self.assertEqual(diagnostic["line_byte_offset"], len(b"bad"))
        self.assertEqual(
            diagnostic["absolute_byte_offset"], len(first_line) + len(b"bad")
        )
        self.assertEqual(diagnostic["parser_state"]["completed_lines"], 1)
        self.assertEqual(diagnostic["parser_state"]["records_seen"], 1)
        self.assertNotIn("private.pkg", json.dumps(diagnostic))
        self.assertNotIn("record-object", json.dumps(diagnostic))
        parser.discard()
        self.assertEqual(parser.failure_diagnostic, diagnostic)
        self.assertEqual(parser.retained_bytes, 0)

    def test_invalid_utf8_on_the_final_line_is_classified_at_eof(self):
        parser = Q7StructuralFilter()
        first_line = b"resumed=true\n"
        parser.feed(first_line)
        parser.feed(b"\xff")

        with self.assertRaises(probe.ProbeError):
            parser.finish()

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "invalid_utf8")
        self.assertEqual(diagnostic["stage"], "utf8_decode")
        self.assertEqual(diagnostic["line_number"], 2)
        self.assertEqual(diagnostic["absolute_byte_offset"], len(first_line))
        self.assertEqual(parser.retained_bytes, 0)

    def test_classifies_control_bytes_without_retaining_the_line(self):
        parser = Q7StructuralFilter()
        first_line = b"ActivityRecord{record-object u0 private.pkg/.Secret t1}\n"
        parser.feed(first_line)

        with self.assertRaises(probe.ProbeError):
            parser.feed(b"failure\xc3\xa9\x01private-marker\n")

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "forbidden_control_character")
        self.assertEqual(diagnostic["stage"], "control_validation")
        self.assertEqual(diagnostic["line_number"], 2)
        self.assertEqual(
            diagnostic["line_byte_offset"], len(b"failure\xc3\xa9")
        )
        self.assertEqual(
            diagnostic["absolute_byte_offset"],
            len(first_line) + len(b"failure\xc3\xa9"),
        )
        serialized = json.dumps(diagnostic)
        self.assertNotIn("private.pkg", serialized)
        self.assertNotIn("private-marker", serialized)

    def test_invalid_chunk_type_discards_a_buffered_partial_line(self):
        parser = Q7StructuralFilter()
        parser.feed(b"private-partial-line")

        with self.assertRaises(probe.ProbeError):
            parser.feed("not-bytes")

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "parser_rejection")
        self.assertEqual(diagnostic["stage"], "input_validation")
        self.assertEqual(diagnostic["error_code"], "IncompleteEvidence")
        self.assertEqual(parser.retained_bytes, 0)
        self.assertNotIn("private-partial-line", json.dumps(diagnostic))
        with self.assertRaises(probe.ProbeError):
            parser.feed(b"later-output\n")

    def test_classifies_structural_limits_at_the_line_that_reached_them(self):
        cases = (
            (
                "field_limit_exceeded",
                Q7StructuralFilter(maximum_fields=1),
                b"first=1 second=2\n",
                1,
                len(b"first=1 "),
            ),
            (
                "alias_limit_exceeded",
                Q7StructuralFilter(maximum_fields=1),
                b"ActivityRecord{first-record}\nActivityRecord{second-record}\n",
                2,
                0,
            ),
            (
                "relationship_limit_exceeded",
                Q7StructuralFilter(maximum_relationships=1),
                b"RootWindowContainer{root}\n"
                b"  DisplayContent{first}\n"
                b"  DisplayContent{second}\n",
                3,
                2,
            ),
        )
        for subtype, parser, raw, line_number, line_byte_offset in cases:
            with self.subTest(subtype=subtype):
                with self.assertRaises(probe.ProbeError):
                    parser.feed(raw)
                diagnostic = parser.failure_diagnostic
                self.assertEqual(diagnostic["subtype"], subtype)
                self.assertEqual(diagnostic["line_number"], line_number)
                self.assertEqual(diagnostic["line_byte_offset"], line_byte_offset)
                self.assertEqual(diagnostic["error_code"], "ResourceLimitExceeded")
                self.assertNotIn("first-record", json.dumps(diagnostic))
                self.assertNotIn("second-record", json.dumps(diagnostic))

    def test_unscoped_component_limit_reports_the_component_offset(self):
        parser = Q7StructuralFilter(maximum_fields=1)
        parser.feed(b"first=1\n")
        component_line = f"    {TARGET_PACKAGE}/.Main\n".encode()

        with self.assertRaises(probe.ProbeError):
            parser.feed(component_line)

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "field_limit_exceeded")
        self.assertEqual(diagnostic["line_number"], 2)
        self.assertEqual(diagnostic["line_byte_offset"], 4)
        self.assertEqual(
            diagnostic["absolute_byte_offset"], len(b"first=1\n") + 4
        )

    def test_shorthand_field_limit_reports_the_field_token_offset(self):
        parser = Q7StructuralFilter(maximum_fields=1)
        parser.feed(b"resumed=true\n")
        record_line = (
            f"ActivityRecord{{record-object u0 {TARGET_PACKAGE}/.Main t1}}\n".encode()
        )

        with self.assertRaises(probe.ProbeError):
            parser.feed(record_line)

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "field_limit_exceeded")
        self.assertEqual(diagnostic["stage"], "field_scan")
        self.assertEqual(diagnostic["line_number"], 2)
        self.assertEqual(diagnostic["line_byte_offset"], record_line.index(b"u0"))
        self.assertEqual(
            diagnostic["absolute_byte_offset"],
            len(b"resumed=true\n") + record_line.index(b"u0"),
        )

    def test_later_record_limit_keeps_the_record_scan_stage(self):
        parser = Q7StructuralFilter(maximum_records=1)
        raw_line = b"RootTask{root} ActivityRecord{activity}\n"

        with self.assertRaises(probe.ProbeError):
            parser.feed(raw_line)

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "record_limit_exceeded")
        self.assertEqual(diagnostic["stage"], "record_scan")
        self.assertEqual(diagnostic["line_number"], 1)
        self.assertEqual(
            diagnostic["line_byte_offset"], raw_line.index(b"ActivityRecord")
        )

    def test_empty_generic_value_is_omitted_and_parsing_continues(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{activity u0 {TARGET_PACKAGE}/.Main diagnostic={{}} mResumed=true}}\n".encode()
        )

        result = parser.finish()
        structure = result["structure"]
        empty_fields = [item for item in structure["fields"] if item["name"] == "diagnostic"]

        self.assertEqual(empty_fields, [])
        self.assertNotIn("diagnostic", structure["field_names"])
        self.assertEqual(structure["empty_field_value_count"], 1)
        self.assertTrue(result["target_component_observed"])
        self.assertIn("mResumed", structure["field_names"])
        self.assertNotIn("diagnostic={}", json.dumps(structure))

    def test_empty_identity_value_does_not_create_package_fact(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{activity u0 {TARGET_PACKAGE}/.Main package={{}}}}\n".encode()
        )

        result = parser.finish()
        structure = result["structure"]
        package_fields = [item for item in structure["fields"] if item["name"] == "package"]

        self.assertEqual(package_fields, [])
        self.assertEqual(structure["empty_field_value_count"], 1)
        self.assertTrue(result["target_component_observed"])
        self.assertNotIn(
            "record_package",
            {item["kind"] for item in structure["relationships"]},
        )

    def test_empty_component_value_is_not_anonymized_as_a_component(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{activity u0 {TARGET_PACKAGE}/.Main component={{}}}}\n".encode()
        )

        structure = parser.finish()["structure"]
        component_fields = [item for item in structure["fields"] if item["name"] == "component"]

        self.assertEqual(len(component_fields), 1)
        self.assertNotEqual(component_fields[0]["value_kind"], "empty")
        self.assertEqual(structure["empty_field_value_count"], 1)
        self.assertNotIn("component={}", json.dumps(structure))

    def test_structure_validator_rejects_the_unemitted_empty_field_kind(self):
        parser = Q7StructuralFilter()
        parser.feed(f"ActivityRecord{{activity u0 {TARGET_PACKAGE}/.Main}}\n".encode())
        structure = parser.finish()["structure"]
        self.assertTrue(structure["fields"])

        invalid_field = dict(structure["fields"][0])
        invalid_field.pop("value_ref", None)
        invalid_field.pop("value", None)
        invalid_field["value_kind"] = "empty"
        structure["fields"].append(invalid_field)

        with self.assertRaises(probe.ProbeError):
            q7_module._validate_structure(structure)

    def test_empty_sensitive_fields_are_omitted_without_claiming_intent_content(self):
        cases = (
            ("mIntent", ""),
            ("path", ""),
            ("path", "{}"),
            ("mIntent", " resumed=true"),
            ("mIntent", "; resumed=true"),
            ("mIntent", "Intent{}"),
            ("mIntent", "Intent{ }"),
            ("mIntent", "Intent { }"),
            ("mIntent", "Intent{}; resumed=true"),
            ("path", " resumed=true"),
            ("path", "; resumed=true"),
            ("path", "PathValue{}"),
            ("path", "PathValue{ }"),
            ("path", "PathValue { }"),
            ("path", "{} resumed=true"),
        )
        for field_name, following_text in cases:
            with self.subTest(field_name=field_name, following_text=following_text):
                parser = Q7StructuralFilter()
                parser.feed(
                    f"ActivityRecord{{activity {TARGET_PACKAGE}/.Main "
                    f"{field_name}={following_text}}}\n".encode()
                )

                result = parser.finish()
                structure = result["structure"]

                self.assertEqual(structure["empty_field_value_count"], 1)
                self.assertNotIn(field_name, structure["field_names"])
                self.assertNotIn(field_name, result["redacted_field_names"])
                self.assertFalse(result["intent_content_observed"])

    def test_nonempty_sensitive_intent_is_redacted_but_content_presence_is_recorded(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{activity {TARGET_PACKAGE}/.Main "
            "mIntent=PrivateIntentValue}}\n".encode()
        )

        result = parser.finish()

        self.assertTrue(result["intent_content_observed"])
        self.assertIn("mIntent", result["redacted_field_names"])
        self.assertNotIn("PrivateIntentValue", json.dumps(result))

    def test_empty_record_wrappers_never_become_identity_aliases(self):
        parser = Q7StructuralFilter()
        parser.feed(
            f"ActivityRecord{{activity {TARGET_PACKAGE}/.Main "
            "taskId=Task{ } mResumedActivity=ActivityRecord{ } app=ProcessRecord{ } "
            "userId=UserHandle{ } component=ComponentName{ }}\n".encode()
        )

        structure = parser.finish()["structure"]

        self.assertEqual(structure["empty_field_value_count"], 5)
        self.assertFalse(
            {item["kind"] for item in structure["relationships"]}
            & {"activity_task", "resumed_activity", "record_process", "record_user"}
        )
        self.assertFalse(
            {item["name"] for item in structure["fields"]}
            & {"taskId", "mResumedActivity", "app", "userId"}
        )
        self.assertNotIn("Task{ }", json.dumps(structure))
        self.assertNotIn("ActivityRecord{ }", json.dumps(structure))
        self.assertNotIn("ProcessRecord{ }", json.dumps(structure))
        self.assertNotIn("UserHandle{ }", json.dumps(structure))
        self.assertNotIn("ComponentName{ }", json.dumps(structure))

    def test_empty_alias_error_diagnostic_contains_only_safe_metadata(self):
        parser = Q7StructuralFilter()

        with self.assertRaises(probe.ProbeError):
            parser._alias("value", "")

        diagnostic = parser.failure_diagnostic
        self.assertEqual(diagnostic["subtype"], "empty_normalized_alias_value")
        self.assertEqual(diagnostic["stage"], "input_validation")
        self.assertFalse({"value", "raw_value", "line", "raw_line"} & diagnostic.keys())

    def test_parser_diagnostic_survives_discard_with_absolute_offset(self):
        parser = Q7StructuralFilter()
        prefix = b"resumed=true\ndiagnostic={}\n"

        with self.assertRaises(probe.ProbeError):
            parser.feed(prefix + b"\xff\n")

        diagnostic = parser.failure_diagnostic
        parser.discard()

        self.assertEqual(diagnostic["subtype"], "invalid_utf8")
        self.assertEqual(diagnostic["line_number"], 3)
        self.assertEqual(diagnostic["line_byte_offset"], 0)
        self.assertEqual(diagnostic["absolute_byte_offset"], len(prefix))
        self.assertEqual(diagnostic["parser_state"]["empty_field_values"], 1)
        self.assertEqual(parser.failure_diagnostic, diagnostic)

    def test_omitted_empty_value_does_not_trigger_retained_field_limit(self):
        parser = Q7StructuralFilter(maximum_fields=1)
        parser.feed(b"resumed=true\n")

        parser.feed(b"diagnostic={}\n")

        structure = parser.finish()["structure"]
        self.assertEqual(structure["empty_field_value_count"], 1)

    def test_empty_record_reference_does_not_trigger_retained_field_limit(self):
        parser = Q7StructuralFilter(maximum_fields=1)
        parser.feed(b"resumed=true\n")

        parser.feed(b"taskId=Task{ }\n")

        structure = parser.finish()["structure"]
        self.assertEqual(structure["empty_field_value_count"], 1)
        self.assertNotIn("taskId", structure["field_names"])

    def test_final_line_without_newline_is_processed_only_at_eof(self):
        parser = Q7StructuralFilter()
        partial = f"Task{{#17 baseActivity={TARGET_PACKAGE}/.Main displayId=4".encode()
        parser.feed(partial)
        self.assertEqual(parser.retained_bytes, len(partial))

        result = parser.finish()

        self.assertEqual(parser.retained_bytes, 0)
        self.assertIn("task_membership_fields", result["available_field_categories"])
        self.assertIn("display_fields", result["available_field_categories"])


class Q7AcquisitionTests(unittest.TestCase):
    def test_runs_one_fixed_observation_and_returns_only_sanitized_metadata(self):
        raw = (
            b"ACTIVITY com.private.app/.Secret userId=10917 Task{TASK-91}\n"
            b"mResumedActivity: cmp=com.private.app/.Secret\n"
        )
        runner = FakeQ7Runner(chunks=(raw[:22], raw[22:]))

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=runner,
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        serialized = json.dumps(record, sort_keys=True)
        self.assertEqual(runner.targets, [TARGET])
        self.assertEqual(record["command_count"], 1)
        self.assertEqual(record["classification"], "exploratory_only")
        self.assertTrue(record["usable_exploratory_observation"])
        self.assertFalse(record["qualification_assertions_passed"])
        self.assertEqual(record["target_ref"], TARGET_REF)
        self.assertNotIn(TARGET, serialized)
        self.assertNotIn("com.private.app", serialized)
        self.assertNotIn(".Secret", serialized)
        self.assertNotIn("TASK-91", serialized)
        self.assertNotIn("10917", serialized)
        self.assertNotIn(raw.decode(), serialized)

    def test_unapproved_source_identity_blocks_before_runner_call(self):
        invalid_identities = [
            {**SOURCE_IDENTITY, "approved_baseline_commit": "f" * 40},
            {**SOURCE_IDENTITY, "source_commit": "f" * 40},
            {
                key: value
                for key, value in SOURCE_IDENTITY.items()
                if key != "source_commit"
            },
            {
                **SOURCE_IDENTITY,
                "source_file_sha256": {
                    **SOURCE_IDENTITY["source_file_sha256"],
                    "q7_exploratory_acquisition.py": "f" * 64,
                },
            },
        ]
        for source_identity in invalid_identities:
            with self.subTest(commit=source_identity["approved_baseline_commit"]):
                runner = FakeQ7Runner()
                with self.assertRaises(probe.ProbeError):
                    run_q7_observation(
                        TARGET,
                        target_ref=TARGET_REF,
                        source_identity=source_identity,
                        runner=runner,
                        utc_clock=lambda: "2026-11-20T12:00:00.000Z",
                    )
                self.assertEqual(runner.targets, [])

    def test_legacy_source_identity_is_rejected_when_repository_head_is_unavailable(self):
        legacy_identity = {
            key: value
            for key, value in SOURCE_IDENTITY.items()
            if key != "source_commit"
        }
        with patch.object(q7_module, "_repository_head_commit", return_value=None):
            self.assertFalse(q7_module._valid_source_identity(SOURCE_IDENTITY))
            self.assertFalse(q7_module._valid_source_identity(legacy_identity))

    def test_legacy_recorded_source_identity_remains_valid_for_saved_outcomes(self):
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            record = call_public_q7(
                outcomes,
                FakeQ7Runner(chunks=(b"",)),
                lambda: "2026-11-20T12:00:00.000Z",
            )
            legacy_record = json.loads(json.dumps(record))
            del legacy_record["source_identity"]["source_commit"]

            q7_module._validate_record(legacy_record)

    def test_parser_failure_is_persistable_when_process_is_incomplete(self):
        raw = b"\xff\n"

        class IncompleteRunner:
            def run_q7(self, _target, stdout_consumer):
                try:
                    stdout_consumer(raw)
                except probe.ProbeError:
                    pass
                return Q7CommandResult(
                    command_count=1,
                    started_monotonic=10.0,
                    finished_monotonic=10.4,
                    stdout_bytes=len(raw),
                    total_output_bytes=len(raw),
                    exit_code=None,
                    classification="incomplete",
                    cleanup_complete=True,
                )

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=IncompleteRunner(),
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        self.assertEqual(record["classification"], "parser_rejection")
        self.assertEqual(record["process_classification"], "incomplete")
        self.assertEqual(record["parser_error"]["subtype"], "invalid_utf8")
        self.assertFalse(record["usable_exploratory_observation"])
        record["identity_preflight_record_bound"] = True
        q7_module._validate_record(record)

    def test_empty_sensitive_target_observation_passes_record_validation(self):
        raw = (
            f"ActivityRecord{{activity {TARGET_PACKAGE}/.Main mIntent=}}\n".encode()
        )
        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=FakeQ7Runner(chunks=(raw,)),
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )
        record["identity_preflight_record_bound"] = True

        q7_module._validate_record(record)

        observation = record["observation"]
        self.assertEqual(record["classification"], "exploratory_only")
        self.assertFalse(observation["intent_content_observed"])
        self.assertNotIn("mIntent", observation["redacted_field_names"])
        self.assertEqual(
            observation["structure"]["empty_field_value_count"], 1
        )

    def test_failed_or_timed_out_run_exposes_no_observation_categories(self):
        runner = FakeQ7Runner(
            result=Q7CommandResult(
                command_count=1,
                started_monotonic=10.0,
                finished_monotonic=15.0,
                stdout_bytes=20,
                total_output_bytes=30,
                exit_code=None,
                classification="host_timeout",
                cleanup_complete=True,
            ),
            chunks=(b"mResumedActivity: cmp=private.pkg/.Secret\n",),
        )

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=runner,
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        self.assertEqual(record["classification"], "host_timeout")
        self.assertFalse(record["usable_exploratory_observation"])
        self.assertNotIn("observation", record)
        self.assertFalse(record["qualification_assertions_passed"])


class Q7ProcessRunnerTests(unittest.TestCase):
    def test_executes_one_exact_shell_free_command_and_returns_no_output(self):
        raw = b"ACTIVITY private.pkg/.Secret mResumedActivity\n"
        harness = RealQ7RunnerHarness((raw, b"stderr private detail"))
        parser = Q7StructuralFilter()

        result = harness.runner.run_q7(TARGET, parser.feed)

        argv, options = harness.popen_calls[0]
        self.assertEqual(
            argv,
            (
                "adb",
                "-s",
                TARGET,
                "shell",
                "dumpsys",
                "-t",
                "3",
                "activity",
                "activities",
            ),
        )
        self.assertFalse(options["shell"])
        self.assertTrue(options["start_new_session"])
        self.assertEqual(options["stdin"], subprocess.DEVNULL)
        self.assertEqual(result.command_count, 1)
        self.assertEqual(result.classification, "exit_zero")
        self.assertTrue(result.cleanup_complete)
        self.assertEqual(result.total_output_bytes, len(raw) + len(b"stderr private detail"))
        self.assertNotIn("private.pkg", json.dumps(result.__dict__))
        self.assertNotIn("private detail", json.dumps(result.__dict__))
        self.assertNotIn("private.pkg", json.dumps(parser.finish()))
        self.assertTrue(harness.selector.closed)

    def test_q7_vector_is_not_admitted_by_the_general_runner(self):
        harness = RealQ7RunnerHarness((b"", b""))

        with self.assertRaises(probe.ProbeError):
            harness.runner.run(
                ("adb", "-s", TARGET, "shell", "dumpsys", "-t", "3", "activity", "activities"),
                deadline=105.0,
            )

        self.assertEqual(harness.popen_calls, [])

    def test_host_deadline_kills_and_reaps_the_child(self):
        harness = RealQ7RunnerHarness((b"", b""), expire=True, returncode=None)

        result = harness.runner.run_q7(TARGET, lambda _chunk: None)

        self.assertEqual(result.classification, "host_timeout")
        self.assertEqual(result.command_count, 1)
        self.assertTrue(result.cleanup_complete)
        self.assertTrue(harness.process.killed)
        self.assertEqual(harness.process.wait_timeouts, [0.0])

    def test_deadline_before_spawn_is_host_timeout_with_zero_commands(self):
        harness = RealQ7RunnerHarness((b"", b""))
        harness.runner._clock = LateDeadlineClock()

        result = harness.runner.run_q7(TARGET, lambda _chunk: None)

        self.assertEqual(result.classification, "host_timeout")
        self.assertEqual(result.command_count, 0)
        self.assertEqual(harness.popen_calls, [])

    def test_combined_output_limit_kills_and_reaps_the_child(self):
        line = b"x" * 16000 + b"\n"
        output = line * 33
        harness = RealQ7RunnerHarness((output, output), returncode=None)

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=harness.runner,
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        self.assertEqual(record["classification"], "resource_limit")
        self.assertEqual(record["command_count"], 1)
        self.assertTrue(record["cleanup_complete"])
        self.assertTrue(harness.process.killed)
        self.assertLessEqual(record["total_output_bytes"], _MAX_Q7_OUTPUT_BYTES)
        self.assertTrue(all(size <= 4096 for size in harness.read_request_sizes))
        self.assertNotIn("observation", record)

    def test_stderr_line_limit_is_enforced_while_stderr_is_discarded(self):
        stderr = b"s" * 16385
        harness = RealQ7RunnerHarness((b"", stderr), returncode=None)

        result = harness.runner.run_q7(TARGET, lambda _chunk: None)

        self.assertEqual(result.classification, "resource_limit")
        self.assertEqual(result.command_count, 1)
        self.assertTrue(result.cleanup_complete)
        self.assertTrue(harness.process.killed)

    def test_stdout_line_limit_is_enforced_before_any_record_is_usable(self):
        harness = RealQ7RunnerHarness((b"x" * 16385, b""), returncode=None)
        parser = Q7StructuralFilter()

        result = harness.runner.run_q7(TARGET, parser.feed)

        self.assertEqual(result.classification, "resource_limit")
        self.assertTrue(result.cleanup_complete)
        self.assertTrue(harness.process.killed)
        self.assertEqual(parser.retained_bytes, 0)

    def test_zero_spawn_count_is_not_reported_as_an_executed_command(self):
        runner = FakeQ7Runner(
            result=Q7CommandResult(
                command_count=0,
                started_monotonic=10.0,
                finished_monotonic=10.0,
                stdout_bytes=0,
                total_output_bytes=0,
                exit_code=None,
                classification="launch_failed",
                cleanup_complete=True,
            )
        )

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=runner,
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        self.assertEqual(record["command_count"], 0)
        self.assertFalse(record["usable_exploratory_observation"])

    def test_device_timeout_indicator_keeps_notes_exploratory_and_unusable(self):
        runner = FakeQ7Runner(chunks=(b"Service timed out while dumping\n",))

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=runner,
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        self.assertEqual(record["classification"], "device_timeout_indicator")
        self.assertFalse(record["usable_exploratory_observation"])
        self.assertTrue(record["observation"]["timeout_indicator_observed"])
        self.assertFalse(record["qualification_assertions_passed"])

    def test_malformed_utf8_discards_all_partial_structural_findings(self):
        malformed = b"mResumedActivity: cmp=private.pkg/.Secret\n\xff\n"
        harness = RealQ7RunnerHarness((malformed, b""), returncode=None)

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=harness.runner,
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )

        self.assertEqual(record["classification"], "parser_rejection")
        self.assertEqual(record["parser_error"]["subtype"], "invalid_utf8")
        self.assertEqual(record["parser_error"]["line_number"], 2)
        self.assertIn(
            record["process_classification"],
            {"cleanup_unverified", "incomplete", "process_nonzero"},
        )
        self.assertFalse(record["usable_exploratory_observation"])
        self.assertNotIn("observation", record)
        serialized = json.dumps(record)
        self.assertNotIn("private.pkg", serialized)
        self.assertNotIn(".Secret", serialized)
        self.assertTrue(harness.process.killed)


class IdentityBindingTests(unittest.TestCase):
    def make_outcomes_directory(self, temporary):
        outcomes = Path(temporary).resolve() / "outcomes"
        outcomes.mkdir(mode=0o700)
        os.chmod(outcomes, 0o700)
        return outcomes

    def test_uses_serial_only_from_one_matching_private_pass_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = self.make_outcomes_directory(temporary)
            write_identity_fixture(outcomes)
            runner = FakeQ7Runner(chunks=(b"Task{task=3}\n",))

            record = call_public_q7(
                outcomes,
                runner,
                lambda: "2026-11-20T12:00:00.000Z",
            )

            self.assertEqual(runner.targets, [TARGET])
            self.assertTrue(record["identity_preflight_record_bound"])
            self.assertNotIn(TARGET, json.dumps(record, sort_keys=True))

    def test_public_entrypoint_has_no_runner_source_or_clock_overrides(self):
        with self.assertRaises(TypeError):
            run_q7_from_identity_outcome(
                "unused",
                source_identity=SOURCE_IDENTITY,
                runner=FakeQ7Runner(),
                utc_clock=lambda: "2026-11-20T12:00:00.000Z",
            )

    def test_source_identity_pins_baseline_and_command_defining_source(self):
        source_identity = q7_module._source_identity()

        self.assertEqual(
            source_identity["approved_baseline_commit"], APPROVED_BASELINE_COMMIT
        )
        self.assertEqual(
            source_identity["source_commit"],
            q7_module._repository_head_commit(),
        )
        self.assertEqual(source_identity["source_snapshot"], "working_tree")
        self.assertEqual(
            set(source_identity["source_file_sha256"]),
            {
                "adb_forward.py",
                "packaging.py",
                "readiness_probe_artifact.py",
                "readiness_probe_session.py",
                "q7_exploratory_acquisition.py",
            },
        )
        self.assertTrue(q7_module._valid_source_identity(source_identity))
        source_identity["source_file_sha256"]["packaging.py"] = "f" * 64
        self.assertFalse(q7_module._valid_source_identity(source_identity))

        source_identity = q7_module._source_identity()
        source_identity["source_file_sha256"]["readiness_probe_artifact.py"] = "f" * 64
        self.assertFalse(q7_module._valid_source_identity(source_identity))

    def test_recorded_source_identity_accepts_legacy_hash_set_only(self):
        legacy_identity = q7_module._source_identity()
        legacy_identity["source_file_sha256"].pop("packaging.py")
        legacy_identity["source_file_sha256"].pop("readiness_probe_artifact.py")

        self.assertTrue(q7_module._valid_recorded_source_identity(legacy_identity))
        self.assertFalse(q7_module._valid_source_identity(legacy_identity))

        record = run_q7_observation(
            TARGET,
            target_ref=TARGET_REF,
            source_identity=SOURCE_IDENTITY,
            runner=FakeQ7Runner(),
            utc_clock=lambda: "2026-11-20T12:00:00.000Z",
        )
        record["identity_preflight_record_bound"] = True
        record["source_identity"]["source_file_sha256"].pop("packaging.py")
        record["source_identity"]["source_file_sha256"].pop(
            "readiness_probe_artifact.py"
        )
        q7_module._validate_record(record)

        intermediate_identity = q7_module._source_identity()
        intermediate_identity["source_file_sha256"].pop("readiness_probe_artifact.py")
        self.assertTrue(q7_module._valid_recorded_source_identity(intermediate_identity))
        self.assertFalse(q7_module._valid_source_identity(intermediate_identity))

    def test_mismatched_or_failed_preflight_blocks_before_runner_call(self):
        mismatched = identity_preflight_record(
            target_reference="i74-tgt-0000000000000000"
        )
        failed = identity_preflight_record()
        failed["classification"] = "BLOCKED"
        for invalid_record in (mismatched, failed):
            with self.subTest(classification=invalid_record["classification"]):
                with tempfile.TemporaryDirectory() as temporary:
                    outcomes = self.make_outcomes_directory(temporary)
                    path = outcomes / "identity-preflight.json"
                    path.write_text(json.dumps(invalid_record))
                    os.chmod(path, 0o600)
                    runner = FakeQ7Runner()

                    with self.assertRaises(probe.ProbeError):
                        call_public_q7(
                            outcomes,
                            runner,
                            lambda: "2026-11-20T12:00:00.000Z",
                        )
                    self.assertEqual(runner.targets, [])


class PrivateOutcomeWriterTests(unittest.TestCase):
    def test_writes_only_private_file_with_mode_0600(self):
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            runner = FakeQ7Runner()
            record = call_public_q7(
                outcomes,
                runner,
                lambda: "2026-11-20T12:00:00.000Z",
            )

            written = next(outcomes.glob("q7-exploratory-*.json"))
            self.assertEqual(written.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(written.read_text()), record)
            self.assertEqual(outcomes.stat().st_mode & 0o777, 0o700)

    def test_persists_structure_without_raw_values_or_process_output(self):
        raw = (
            b"Task{task-object #42 type=standard A=com.private.app}\n"
            + f"  ActivityRecord{{activity-object u0 {TARGET_PACKAGE}/.Main t42}}\n".encode()
            + f"    mIntent=Intent{{cmp={TARGET_PACKAGE}/.Secret "
            "data=file:///private/owner/data}\n".encode()
            + b"  ActivityRecord{unrelated-object u0 unrelated.private/.Home t81}\n"
            + b"    unrelatedOnly=discard-this\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            stdout = StringIO()
            stderr = StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                record = call_public_q7(
                    outcomes,
                    FakeQ7Runner(chunks=(raw,)),
                    lambda: "2026-11-20T12:00:00.000Z",
                )
            written = next(outcomes.glob("q7-exploratory-*.json"))
            serialized = written.read_text()
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")
            for private_value in (
                "com.private.app",
                ".Main",
                ".Secret",
                "task-object",
                "activity-object",
                "file:///private/owner/data",
            ):
                self.assertNotIn(private_value, serialized)
            self.assertIn('"structure"', serialized)

    def test_persists_parser_failure_metadata_without_raw_output(self):
        raw = b"mResumedActivity: cmp=private.pkg/.Secret\n\xff\n"
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            harness = RealQ7RunnerHarness((raw, b""), returncode=None)
            record = call_public_q7(
                outcomes,
                harness.runner,
                lambda: "2026-11-20T12:00:00.000Z",
            )

            written = next(outcomes.glob("q7-exploratory-*.json"))
            serialized = written.read_text()
            persisted = json.loads(serialized)
            self.assertEqual(persisted["parser_error"]["subtype"], "invalid_utf8")
            self.assertIn(
                persisted["process_classification"],
                {"cleanup_unverified", "incomplete", "process_nonzero"},
            )
            self.assertEqual(stat.S_IMODE(written.stat().st_mode), 0o600)
            self.assertNotIn("private.pkg", serialized)
            self.assertNotIn(".Secret", serialized)
            self.assertNotIn(raw.decode("utf-8", errors="replace"), serialized)

    def test_refuses_record_shapes_that_could_contain_raw_diagnostic_text(self):
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            unsafe = call_public_q7(
                outcomes,
                FakeQ7Runner(
                    chunks=(
                        f"ActivityRecord{{record-object u0 {TARGET_PACKAGE}/.Secret}}\n".encode(),
                    )
                ),
                lambda: "2026-11-20T12:00:00.000Z",
            )
            persisted = next(outcomes.glob("q7-exploratory-*.json"))
            original_payload = persisted.read_text()
            unsafe["parser_error"] = None

            with self.assertRaises(probe.ProbeError):
                q7_module._validate_record(unsafe)

            del unsafe["parser_error"]
            unsafe["parser_error"] = {
                "subtype": "invalid_utf8",
                "stage": "utf8_decode",
                "error_code": "IncompleteEvidence",
                "line_number": 1,
                "line_byte_offset": 0,
                "absolute_byte_offset": 0,
                "parser_state": {
                    "completed_lines": 0,
                    "records_seen": 0,
                    "fields_seen": 0,
                    "relationships_seen": 0,
                    "record_stack_depth": 0,
                    "empty_field_values": 0,
                    "unrecognized_fields": 0,
                    "unclassified_lines": 0,
                },
                "raw_line": "private.pkg/.Secret",
            }

            with self.assertRaises(probe.ProbeError):
                q7_module._validate_record(unsafe)

            del unsafe["parser_error"]
            unsafe["raw_output"] = "private.pkg/.Secret"

            with self.assertRaises(probe.ProbeError):
                q7_module._validate_record(unsafe)

            del unsafe["raw_output"]
            unsafe["observation"]["structure"]["fields"][0]["value_ref"] = (
                "private.pkg/.Secret"
            )
            with self.assertRaises(probe.ProbeError):
                q7_module._validate_record(unsafe)
            self.assertEqual(persisted.read_text(), original_payload)

    def test_refuses_a_symlinked_or_non_private_outcomes_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary).resolve()
            real = base / "real"
            real.mkdir(mode=0o700)
            os.chmod(real, 0o700)
            write_identity_fixture(real)
            link = base / "link"
            link.symlink_to(real, target_is_directory=True)
            linked_runner = FakeQ7Runner(chunks=(b"",))
            with self.assertRaises(probe.ProbeError) as raised:
                call_public_q7(
                    link,
                    linked_runner,
                    lambda: "2026-11-20T12:00:01.000Z",
                )
            self.assertEqual(raised.exception.code, "UnauthorizedPeer")
            self.assertEqual(linked_runner.targets, [])

            permissive = base / "permissive"
            permissive.mkdir(mode=0o755)
            os.chmod(permissive, 0o755)
            write_identity_fixture(permissive)
            permissive_runner = FakeQ7Runner(chunks=(b"",))
            with self.assertRaises(probe.ProbeError) as raised:
                call_public_q7(
                    permissive,
                    permissive_runner,
                    lambda: "2026-11-20T12:00:02.000Z",
                )
            self.assertEqual(raised.exception.code, "UnauthorizedPeer")
            self.assertEqual(permissive_runner.targets, [])

    def test_rejects_observation_metadata_beyond_acquisition_and_structure_limits(self):
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            valid_record = call_public_q7(
                outcomes,
                FakeQ7Runner(chunks=(b"",)),
                utc_clock=lambda: "2026-11-20T12:00:00.000Z",
            )
            observations = (
                ("lines_observed", 1024 * 1024 + 1),
                (
                    "field_names",
                    sorted(f"field{index}" for index in range(16385)),
                ),
                (
                    "redacted_field_names",
                    sorted(f"path{index}" for index in range(16385)),
                ),
            )
            for key, value in observations:
                with self.subTest(key=key):
                    candidate = json.loads(json.dumps(valid_record))
                    observation = candidate.setdefault(
                        "observation",
                        {
                            "lines_observed": 0,
                            "max_line_bytes": 0,
                            "available_field_categories": [],
                            "timeout_indicator_observed": False,
                            "timeout_indicator_count": 0,
                            "completion_indicator_observed": False,
                            "completion_indicator_count": 0,
                            "intent_content_observed": False,
                            "redacted_field_names": [],
                            "eof_observed": True,
                            "completion_verified": False,
                            "target_binding_established": False,
                            "task_continuity_established": False,
                            "structure": {
                                "record_type_names": [],
                                "field_names": [],
                                "records": [],
                                "fields": [],
                                "relationships": [],
                                "unclassified_line_count": 0,
                                "unrecognized_field_count": 0,
                                "sensitive_tail_truncated_count": 0,
                            },
                        },
                    )
                    if key == "lines_observed":
                        candidate["stdout_bytes"] = 1024 * 1024
                        candidate["total_output_bytes"] = 1024 * 1024
                        observation[key] = value
                    else:
                        observation["structure"][key] = value
                    with self.assertRaises(probe.ProbeError):
                        q7_module._validate_record(candidate)

    def test_record_validator_rejects_unscoped_structure_without_target_component_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            record = run_q7_observation(
                TARGET,
                target_ref=TARGET_REF,
                source_identity=SOURCE_IDENTITY,
                runner=FakeQ7Runner(chunks=(b"",)),
                utc_clock=lambda: "2026-11-20T12:00:00.000Z",
            )
            record["identity_preflight_record_bound"] = True
            observation = record["observation"]
            observation["structure"]["field_names"] = ["mResumed"]
            observation["structure"]["fields"] = [
                {
                    "record_ref": None,
                    "association": "unscoped",
                    "name": "mResumed",
                    "value_kind": "boolean",
                    "value": True,
                }
            ]

            with self.assertRaises(probe.ProbeError):
                q7_module._validate_record(record)

    def test_public_entrypoint_persists_before_return_and_accepts_no_record_input(self):
        raw = f"ActivityRecord{{target-object u0 {TARGET_PACKAGE}/.Main}}\n".encode()
        with tempfile.TemporaryDirectory() as temporary:
            outcomes = Path(temporary).resolve() / "outcomes"
            outcomes.mkdir(mode=0o700)
            os.chmod(outcomes, 0o700)
            write_identity_fixture(outcomes)
            record = call_public_q7(
                outcomes,
                FakeQ7Runner(chunks=(raw,)),
                lambda: "2026-11-20T12:00:00.000Z",
            )

            persisted = next(outcomes.glob("q7-exploratory-*.json"))
            original_payload = persisted.read_text()
            record["observation"]["structure"]["fields"].clear()

            self.assertEqual(persisted.read_text(), original_payload)
            self.assertNotIn("record", inspect.signature(run_q7_from_identity_outcome).parameters)
            self.assertFalse(hasattr(q7_module, "write_sanitized_outcome"))
            self.assertNotIn(
                "package",
                inspect.signature(run_readiness_activity_snapshot_from_identity_outcome).parameters,
            )


if __name__ == "__main__":
    unittest.main()
