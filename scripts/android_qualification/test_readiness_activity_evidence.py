"""Tests for the fixed Activity Manager evidence reader."""

import unittest
from types import SimpleNamespace
from unittest.mock import Mock

from .adb_forward import AdbForwardAdapter
from .readiness_activity_evidence import ReadinessActivityReader
from .readiness_probe import ProbeError
from .readiness_probe_artifact import PACKAGE


COMPONENT = f"{PACKAGE}/.ProbeControlActivity".encode()
TARGET = b"ActivityRecord{deadbeef u10 " + COMPONENT + b" t14}"
OTHER = b"ActivityRecord{abad1dea u10 com.example.private/.HiddenActivity t15}"
SNAPSHOT = (
    b"ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\n"
    b"Display #0 (activities from top to bottom):\n"
    b"  RootTask #13: type=standard mode=fullscreen\n"
    b"    mResumedActivity: " + TARGET + b"\n"
    b"    * Task{cafef00d #14 type=standard A=unrelated-affinity U=10 rootTaskId=13 "
    b"visible=true mode=fullscreen translucent=false sz=1}\n"
    b"      * Hist  #0: " + TARGET + b"\n"
    b"        state=RESUMED stopped=false\n"
    b"  ResumedActivity: " + TARGET + b"\n"
    b"ActivityTaskSupervisor state:\n"
    b"  private tail data\n"
    b"  NumNonAppVisibleWindowByUid:[]\n"
)


def acquisition(data, **overrides):
    facts = dict(command_count=1, exit_code=0, classification="exit_zero", stderr_empty=True,
                 cleanup_complete=True, stdout_bytes=len(data), total_output_bytes=len(data))
    return SimpleNamespace(**(facts | overrides))


class ReadinessActivityReaderTests(unittest.TestCase):
    def parse(self, data=SNAPSHOT, **overrides):
        reader = ReadinessActivityReader("ProbeControlActivity", 10)
        for i in range(0, len(data), 13):
            reader.feed(data[i:i + 13])
        return reader.finish(acquisition(data, **overrides))

    def test_reads_only_selected_member_and_explicit_relations(self):
        result = self.parse()
        self.assertEqual((result.task_id, result.root_task_id, result.display_id), (14, 13, 0))
        self.assertEqual((result.activity_id, result.task_instance), (b"deadbeef", b"cafef00d"))
        self.assertEqual((result.component, result.user_id), ("ProbeControlActivity", 10))
        self.assertEqual(result.windowing_mode, "fullscreen")
        self.assertTrue(result.resumed)
        self.assertTrue(result.top_resumed)
        self.assertNotIn("deadbeef", repr(result))
        self.assertNotIn("cafef00d", repr(result))
        self.assertNotIn("private tail", repr(result))
        self.assertNotIn("unrelated-affinity", repr(result))

    def test_resumed_is_distinct_from_top_resumed(self):
        result = self.parse(SNAPSHOT.replace(b"  ResumedActivity: " + TARGET, b"  ResumedActivity: " + OTHER))
        self.assertTrue(result.resumed)
        self.assertFalse(result.top_resumed)
        self.assertNotIn("HiddenActivity", repr(result))
        paused = SNAPSHOT.replace(b"    mResumedActivity: " + TARGET, b"    mResumedActivity: " + OTHER).replace(
            b"  ResumedActivity: " + TARGET, b"  ResumedActivity: " + OTHER,
        ).replace(b"state=RESUMED ", b"state=PAUSED ")
        result = self.parse(paused)
        self.assertFalse(result.resumed or result.top_resumed)

    def test_rejects_conflicting_bindings_and_missing_membership(self):
        for data in (
            SNAPSHOT.replace(b"u10 ", b"u11 "),
            SNAPSHOT.replace(b"U=10 ", b"U=11 "),
            SNAPSHOT.replace(b"rootTaskId=13", b"rootTaskId=99"),
            SNAPSHOT.replace(b"* Hist  #0:", b"* Hist  #0: corrupt"),
            SNAPSHOT.replace(b"state=RESUMED ", b"state=PAUSED "),
            SNAPSHOT.replace(b"t14}", b"t15}", 1),
            SNAPSHOT.replace(b"  ResumedActivity: " + TARGET,
                             b"  ResumedActivity: " + TARGET.replace(b"deadbeef", b"abcdef")),
            SNAPSHOT.replace(b"        state=", b"      * Hist  #1: " + TARGET + b"\n        state="),
            SNAPSHOT.replace(b"        state=", b"        unrelated="),
            SNAPSHOT.replace(b"    mResumedActivity: " + TARGET, b"").replace(
                b"  ResumedActivity: " + TARGET, b"  ResumedActivity: " + OTHER,
            ).replace(b"state=RESUMED ", b"state=PAUSED "),
        ):
            with self.subTest(), self.assertRaises(ProbeError):
                self.parse(data)

    def test_requires_boundary_framing_and_transport_completion(self):
        for data in (
            SNAPSHOT.split(b"ActivityTaskSupervisor")[0],
            SNAPSHOT.split(b"  NumNonAppVisibleWindowByUid:")[0],
            SNAPSHOT[:-1],
            SNAPSHOT + b"*** SERVICE 'activity' DUMP TIMEOUT (3000ms) EXPIRED ***\n",
            SNAPSHOT + b"Exception occurred while dumping:\n",
            SNAPSHOT + b"\xff\n",
        ):
            with self.subTest(), self.assertRaises(ProbeError):
                self.parse(data)
        for override in (
            {"exit_code": 1}, {"cleanup_complete": False}, {"stderr_empty": False},
            {"stdout_bytes": 0}, {"command_count": 0}, {"classification": "host_timeout"},
        ):
            with self.subTest(override=override), self.assertRaises(ProbeError):
                self.parse(**override)

    def test_rejects_reused_display_root_and_leaf_rows(self):
        for before, injected in (
            (b"  RootTask #13", b"Display #0 (activities from top to bottom):\n"),
            (b"    * Task{", b"  RootTask #13: type=standard mode=fullscreen\n"),
            (b"      * Hist", b"    * Task{aded #14 type=standard A=unrelated U=10 rootTaskId=13 "
                             b"visible=true mode=fullscreen translucent=false sz=1}\n"),
            (b"      * Hist", b"    mResumedActivity: " + TARGET + b"\n"),
            (b"  ResumedActivity:", b"Display #1 (activities from top to bottom):\n"
                                    b"  RootTask #14: type=standard mode=fullscreen\n"),
            (b"  ResumedActivity:", b"Display #1 (activities from top to bottom):\n"
                                    b"  RootTask #15: type=standard mode=fullscreen\n"
                                    b"    * Task{aded #13 type=standard A=unrelated U=10 rootTaskId=15 "
                                    b"visible=true mode=fullscreen translucent=false sz=1}\n"),
        ):
            with self.subTest(before=before), self.assertRaises(ProbeError):
                self.parse(SNAPSHOT.replace(before, injected + before, 1))

    def test_root_task_may_also_be_its_own_leaf(self):
        result = self.parse(SNAPSHOT.replace(b"RootTask #13:", b"RootTask #14:").replace(
            b" rootTaskId=13", b"",
        ))
        self.assertEqual(result.root_task_id, result.task_id)

    def test_limits_apply_even_to_dropped_data(self):
        reader = ReadinessActivityReader("ProbeControlActivity", 10)
        for chunk in (b"x" * (16 * 1024 + 1), b"\n" * (1024 * 1024 + 1)):
            with self.subTest(size=len(chunk)), self.assertRaises(ProbeError) as error:
                reader.feed(chunk)
            self.assertEqual(error.exception.code, "ResourceLimitExceeded")

    def test_adapter_rebinds_build_user_and_passes_the_deadline(self):
        serial = "SERIAL-1"
        build = "brand/device:version/id/user/release-keys"
        runner = Mock()
        runner.run.side_effect = (b"device\n", build.encode() + b"\n",
                                  b"device\n", build.encode() + b"\n", b"10\n")

        def run_q7(target, consumer, *, deadline):
            self.assertEqual((target, deadline), (serial, 9))
            consumer(SNAPSHOT)
            return acquisition(SNAPSHOT)

        runner.run_q7.side_effect = run_q7
        adapter = AdbForwardAdapter(runner=runner, clock=lambda: 1)
        adapter.identity(serial, deadline=9)
        with self.assertRaises(ProbeError):
            adapter.read_readiness_activity(serial, build="different", component="ProbeControlActivity", deadline=9)
        runner.run_q7.assert_not_called()
        result = adapter.read_readiness_activity(
            serial, build=build, component="ProbeControlActivity", deadline=9,
        )
        self.assertTrue(result.top_resumed)
        self.assertEqual(runner.run.call_count, 5)
