"""Release UI driver tests use synthetic XML and never contact a device."""

import copy
import importlib.util
import json
import sys
import unittest
from unittest.mock import patch
from pathlib import Path

MODULE = Path(__file__).with_name("ui.py")
ui = None
if MODULE.exists():
    spec = importlib.util.spec_from_file_location("qualification_ui", MODULE)
    ui = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = ui
    spec.loader.exec_module(ui)

PACKAGE = "com.argusromtoolkit.argus"
OWNED = "/sdcard/ArgusPhase003Qualification/ui.xml"


def xml(*labels, clickable=True, package=PACKAGE, bounds="[10,20][110,80]"):
    """Build controlled accessibility nodes, including Android attributes."""
    from xml.sax.saxutils import escape
    nodes = "".join(
        f'<node package="{package}" text="{escape(label, {chr(34): "&quot;"})}" '
        f'content-desc="" enabled="true" clickable="{str(clickable).lower()}" '
        f'visible-to-user="true" bounds="{bounds}" />' for label in labels
    )
    return '<hierarchy rotation="0">' + nodes + '</hierarchy>'


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class Device:
    """Simulate only the documented command boundary, recording mutations."""
    def __init__(self, frames=(), failure=None):
        self.frames = list(frames) or [xml()]
        self.calls = []
        self.failure = failure

    def shell(self, *args, mutating=False, timeout=30):
        self.calls.append((args, mutating, timeout))
        if self.failure and args[0] == self.failure:
            raise RuntimeError("SECRET game /private/owner key=credential")
        if args[0] == "cat":
            return self.frames.pop(0) if len(self.frames) > 1 else self.frames[0]
        return ""

    def run(self, *args, mutating=False, timeout=30):
        raise AssertionError("No raw adb or app API bypass is permitted")


def rows():
    return {key: {"automation_status": "BLOCKED",
                  "owner_qualification_status": "NOT RUN", "assertions": [],
                  "reason": "", "owner_checkpoint": "Owner checkpoint literal"}
            for key in ["AND-01", "AND-02", "AND-03", "AND-04", "AND-05",
                        "AND-06", "CNT-01", "CNT-10", "CNT-11", "UX-A01",
                        "UX-A02", "UX-A03"]}


class ReleaseUI(Device):
    """Synthetic Release screens with a deterministic, visible action path."""
    def __init__(self, state="terms", unsafe_root=False, sparse=False):
        super().__init__()
        self.state = state
        self.direction = "Ascending"
        self.view = "Grid"
        self.unsafe_root = unsafe_root
        self.sparse = sparse
        self.positions = {}
        self.foreground_launches = 0

    def frame(self):
        screens = {
            "terms": ["Set up your Library", "Accept current terms"],
            "preferences": ["Set up your Library", "Use current preferences"],
            "provider": ["Skip SteamGridDB", "SteamGridDB API key"],
            "add": ["Add a Library folder"],
            "volumes": ["Choose a storage volume", "/storage/emulated/0"],
            "folders": ["ArgusPhase003Qualification"],
            "owned": ["Select this folder", "/storage/emulated/0/ArgusPhase003Qualification"],
            "confirm": ["Add Library root?", "Add folder", "/storage/emulated/0/ArgusPhase003Qualification"],
            "library": ["Search Library", "Refresh Library", "Grid", "List",
                        self.direction, "Force refresh this Game", "Settings", "Library"],
            "settings": ["Providers", "SteamGridDB API key", "Library"],
        }
        labels = screens[self.state]
        if self.sparse and self.state == "library":
            labels = ["Search Library", "Refresh Library", "No games match this query"]
        if self.unsafe_root and self.state in ("owned", "confirm"):
            labels = [x.replace("/storage/emulated/0/ArgusPhase003Qualification", "/private/owner")
                      for x in labels]
        self.positions = {}
        fragments = []
        for i, label in enumerate(labels):
            top = i * 100 + 10
            self.positions[("60", str(top + 30))] = label
            fragment = xml(label, bounds=f"[10,{top}][110,{top + 60}]")
            if label == self.view:
                fragment = fragment.replace('enabled="true"', 'selected="true" enabled="true"')
            fragments.append(fragment.split('rotation="0">')[1].split('</hierarchy>')[0])
        return '<hierarchy>' + ''.join(fragments) + '</hierarchy>'

    def shell(self, *args, mutating=False, timeout=30):
        self.calls.append((args, mutating, timeout))
        if args[0] == "cat":
            return self.frame()
        if args[:2] == ("am", "start"):
            self.foreground_launches += 1
        if args[:2] == ("input", "tap"):
            label = self.positions[args[2:]]
            transitions = {"Accept current terms": "preferences", "Use current preferences": "provider",
                           "Skip SteamGridDB": "add", "Add a Library folder": "volumes",
                           "/storage/emulated/0": "folders", "ArgusPhase003Qualification": "owned",
                           "Select this folder": "confirm", "Add folder": "library",
                           "Settings": "settings", "Library": "library"}
            if label in transitions:
                self.state = transitions[label]
            elif label in ("Ascending", "Descending"):
                self.direction = "Descending" if self.direction == "Ascending" else "Ascending"
            elif label in ("Grid", "List"):
                self.view = label
            else:
                raise AssertionError("Unexpected input")
        return ""


class DriverTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(ui, "UI driver has not been implemented")

    def test_parser_retains_only_allowlisted_keys_and_geometry(self):
        nodes = ui.parse_ui(xml("Search Library", "SECRET game /private/owner"))
        self.assertEqual([n.key for n in nodes], ["search"])
        self.assertEqual(nodes[0].bounds, (10, 20, 110, 80))
        self.assertNotIn("SECRET", repr(nodes))
        self.assertNotIn("/private", repr(nodes))

    def test_text_and_description_same_node_do_not_duplicate_target(self):
        frame = xml("Grid").replace('content-desc=""', 'content-desc="Grid"')
        self.assertEqual(ui.select_unique(ui.parse_ui(frame), "grid").bounds,
                         (10, 20, 110, 80))

    def test_safe_primary_storage_label_deduplicates_repeated_merged_title_and_subtitle(self):
        frame = xml("Internal shared storage").replace(
            'content-desc=""', 'content-desc="Internal shared storage&#10;Internal shared storage"')
        nodes = ui.parse_ui(frame)
        self.assertEqual([node.key for node in nodes], ["storage_root"])
        selected = ui.select_unique(nodes, "storage_root", actionable=True)
        self.assertEqual(selected.bounds, (10, 20, 110, 80))

    def test_safe_owned_folder_display_is_matched_exactly_without_retaining_paths(self):
        nodes = ui.parse_ui(xml("Internal shared storage / ArgusPhase003Qualification"))
        self.assertEqual([node.key for node in nodes], ["owned_path"])
        self.assertEqual(ui.select_unique(nodes, "owned_path").bounds, (10, 20, 110, 80))
        self.assertNotIn("Internal shared storage", repr(nodes))
        for label in ("Internal shared storage / PRIVATE owner folder",
                      "Internal shared storage / ArgusPhase003Qualification/PRIVATE",
                      "/storage/emulated/0/PRIVATE owner folder",
                      "PRIVATE /sdcard/ArgusPhase003Qualification"):
            with self.subTest(label=label):
                self.assertEqual(ui.parse_ui(xml(label)), [])

    def test_mounted_removable_volume_blocks_primary_storage_proof_before_folder_actions(self):
        class MountedStorage(ReleaseUI):
            volume_state = "mounted"

            def shell(self, *args, **kwargs):
                result = super().shell(*args, **kwargs)
                if args == ("sm", "list-volumes", "public"):
                    return "public:PRIVATE " + self.volume_state + " PRIVATE-owner-id\n"
                return result
        for state in ("mounted", "mounted_ro"):
            with self.subTest(state=state):
                device = MountedStorage()
                device.volume_state = state
                report = rows()
                ui.run_ui_scenarios(device, report, {})
                self.assertEqual(device.state, "volumes")
                self.assertEqual(report["AND-01"]["automation_status"], "BLOCKED")
                self.assertNotIn("PRIVATE", json.dumps(report))
                self.assertNotIn("owned_root_admitted", [entry["check"] for entry in report["AND-01"]["assertions"]])
                query_index = next(index for index, call in enumerate(device.calls)
                                   if call[0] == ("sm", "list-volumes", "public"))
                self.assertFalse(device.calls[query_index][1])
                self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls[query_index + 1:]))

    def test_duplicate_and_missing_targets_are_sanitized_blockers(self):
        for frame, key in [(xml("Grid", "Grid"), "grid"),
                           (xml(), "SECRET owner")]:
            with self.assertRaises(ui.UIBlocked) as caught:
                ui.select_unique(ui.parse_ui(frame), key)
            self.assertNotIn("SECRET", str(caught.exception))

    def test_invalid_xml_entities_size_and_bounds_are_refused(self):
        for frame in ["SECRET malformed", '<!DOCTYPE x><hierarchy/>',
                      "x" * (2 * 1024 * 1024 + 1),
                      xml("Grid", bounds="[9,9][1,1]"),
                      xml("Grid", bounds="[-1,0][10,10]")]:
            with self.subTest(frame=frame[:20]):
                with self.assertRaises(ui.UIBlocked) as caught:
                    ui.parse_ui(frame)
                self.assertNotIn("SECRET", str(caught.exception))

    def test_explicit_product_failure_precedes_unrelated_geometry_rejection(self):
        malformed = xml("Grid", bounds="[10,10][10,20]")
        failed = xml("Retry Library setup")
        frame = ('<hierarchy>' + malformed.split('rotation="0">')[1].split('</hierarchy>')[0]
                 + failed.split('rotation="0">')[1].split('</hierarchy>')[0] + '</hierarchy>')

        self.assertEqual([node.key for node in ui.parse_ui(frame)], ["product_failure"])

        report = rows()
        device = Device([frame])
        ui.run_ui_scenarios(device, report, {})
        self.assertEqual(report["AND-01"]["automation_status"], "FAIL")
        self.assertEqual(report["AND-01"]["assertions"][-1]["status"], "FAIL")
        self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))

    def test_other_application_is_refused_even_with_matching_labels(self):
        with self.assertRaises(ui.UIBlocked):
            ui.parse_ui(xml("Grid", package="owner.application"))

    def test_capture_reads_in_memory_and_always_uses_guarded_cleanup(self):
        device = Device([xml("Grid")])
        driver = ui.UIDriver(device)
        self.assertEqual(driver.capture()[0].key, "grid")
        self.assertEqual([(args, mutation) for args, mutation, _ in device.calls],
                         [(('uiautomator', 'dump', OWNED), True),
                          (('cat', OWNED), False), (('rm', '-f', OWNED), True)])

    def test_capture_errors_do_not_leak_command_output_and_cleanup_runs(self):
        for failure in ["uiautomator", "cat"]:
            device = Device(failure=failure)
            with self.assertRaises(ui.UIBlocked) as caught:
                ui.UIDriver(device).capture()
            self.assertNotIn("SECRET", str(caught.exception))
            self.assertEqual(device.calls[-1][0], ('rm', '-f', OWNED))
            self.assertTrue(device.calls[-1][1])

    def test_capture_cleanup_failure_is_reported_after_observation_failure(self):
        class FailedObservationAndCleanup(Device):
            def shell(self, *args, **kwargs):
                self.calls.append((args, kwargs.get("mutating", False), kwargs.get("timeout", 30)))
                if args[0] == "cat":
                    raise RuntimeError("SECRET observation output")
                if args[0] == "rm":
                    raise RuntimeError("SECRET cleanup output")
                return ""

        device = FailedObservationAndCleanup()
        with self.assertRaises(ui.UICleanupBlocked) as caught:
            ui.UIDriver(device).capture()
        self.assertIn("cleanup failed", str(caught.exception).lower())
        self.assertFalse(caught.exception.product_failure_observed)
        self.assertNotIn("SECRET", str(caught.exception))
        self.assertEqual(device.calls[-1][0], ("rm", "-f", OWNED))

    def test_capture_cleanup_failure_after_success_is_distinct_and_stops_capture(self):
        device = Device([xml("Grid")], failure="rm")

        with self.assertRaises(ui.UICleanupBlocked) as caught:
            ui.UIDriver(device).capture()

        self.assertFalse(caught.exception.product_failure_observed)
        self.assertEqual([call[0][0] for call in device.calls], ["uiautomator", "cat", "rm"])
        self.assertNotIn("SECRET", str(caught.exception))

    def test_product_failure_survives_capture_cleanup_failure(self):
        device = Device([xml("Retry Library setup")], failure="rm")

        with self.assertRaises(ui.UICleanupBlocked) as caught:
            ui.UIDriver(device).capture()

        self.assertTrue(caught.exception.product_failure_observed)
        self.assertEqual([call[0][0] for call in device.calls], ["uiautomator", "cat", "rm"])

    def test_primary_flow_propagates_cleanup_failure_with_product_failure_context(self):
        device = Device([xml("Retry Library setup")], failure="rm")
        report = rows()

        with self.assertRaises(ui.UICleanupBlocked) as caught:
            ui.run_ui_scenarios(device, report, {})

        self.assertEqual(caught.exception.scenario, "AND-01")
        self.assertTrue(caught.exception.product_failure_observed)
        self.assertFalse(any(call[0][0] == "input" for call in device.calls))

    def test_product_failure_survives_interrupted_capture_cleanup(self):
        class InterruptedCleanup(Device):
            def shell(self, *args, **kwargs):
                self.calls.append((args, kwargs.get("mutating", False), kwargs.get("timeout", 30)))
                if args[0] == "cat":
                    return xml("Retry Library setup")
                if args[0] == "rm":
                    raise InterruptedError()
                return ""

        device = InterruptedCleanup()
        report = rows()

        with self.assertRaises(InterruptedError) as caught:
            ui.run_ui_scenarios(device, report, {})

        self.assertTrue(caught.exception.ui_product_failure_observed)
        self.assertEqual(caught.exception.ui_cleanup_scenario, "AND-01")
        self.assertFalse(any(call[0][0] == "input" for call in device.calls))

    def test_partial_probe_wrappers_propagate_cleanup_failure_with_scenario_context(self):
        probes = (
            ('AND-02', lambda device, report: ui.library_controls_probe(device, report)),
            ('AND-04', lambda device, report: ui.surface_lifecycle_probe(device, report, 'AND-04')),
            ('UX-A03', lambda device, report: ui.scaling_probe(device, report)),
        )
        for scenario, probe in probes:
            with self.subTest(scenario=scenario):
                device = Device([xml("Retry Library setup")], failure="rm")
                report = rows()

                with self.assertRaises(ui.UICleanupBlocked) as caught:
                    probe(device, report)

                self.assertEqual(caught.exception.scenario, scenario)
                self.assertTrue(caught.exception.product_failure_observed)
                self.assertFalse(any(call[0][0] == "input" for call in device.calls))

    def test_capture_cleanup_interruption_keeps_precedence_over_observation_error(self):
        class InterruptedCleanupAfterFailedObservation(Device):
            def shell(self, *args, **kwargs):
                self.calls.append((args, kwargs.get("mutating", False), kwargs.get("timeout", 30)))
                if args[0] == "cat":
                    raise RuntimeError("SECRET observation output")
                if args[0] == "rm":
                    raise InterruptedError("cancelled")
                return ""

        device = InterruptedCleanupAfterFailedObservation()
        with self.assertRaises(InterruptedError) as caught:
            ui.UIDriver(device).capture()
        self.assertEqual(caught.exception.ui_cleanup_blocker,
                         'Guarded UI capture cleanup was interrupted.')
        self.assertEqual(device.calls[-1][0], ("rm", "-f", OWNED))

    def test_capture_preserves_interruption_even_when_cleanup_also_fails(self):
        class InterruptedDump(Device):
            def shell(self, *args, **kwargs):
                self.calls.append((args, kwargs.get("mutating", False), kwargs.get("timeout", 30)))
                if args[0] == "uiautomator":
                    raise InterruptedError()
                if args[0] == "rm":
                    raise RuntimeError("SECRET cleanup detail")
                return ""

        device = InterruptedDump()
        with self.assertRaises(InterruptedError) as caught:
            ui.UIDriver(device).capture()
        self.assertEqual(caught.exception.ui_cleanup_blocker,
                         'Guarded UI capture cleanup failed.')
        self.assertEqual(device.calls[-1][0], ("rm", "-f", OWNED))

    def test_capture_cleanup_interruption_is_not_converted_to_ui_block(self):
        class InterruptedCleanup(Device):
            def shell(self, *args, **kwargs):
                self.calls.append((args, kwargs.get("mutating", False), kwargs.get("timeout", 30)))
                if args[0] == "cat":
                    return xml("Grid")
                if args[0] == "rm":
                    raise InterruptedError()
                return ""

        with self.assertRaises(InterruptedError) as caught:
            ui.UIDriver(InterruptedCleanup()).capture()
        self.assertEqual(caught.exception.ui_cleanup_blocker,
                         'Guarded UI capture cleanup was interrupted.')

    def test_wait_polls_until_observed_and_limits_command_timeouts(self):
        clock = FakeClock()
        device = Device([xml(), xml("Grid")])
        driver = ui.UIDriver(device, clock=clock, sleep=clock.sleep, budget=2)
        self.assertEqual(driver.wait("grid")[0].key, "grid")
        self.assertGreater(clock.now, 0)
        self.assertTrue(all(0 < timeout <= 2 for _, _, timeout in device.calls))

    def test_wait_rejects_a_matching_capture_that_returns_after_its_deadline(self):
        clock = FakeClock()

        class LateCapture(Device):
            def shell(self, *args, **kwargs):
                result = super().shell(*args, **kwargs)
                if args[0] == "cat":
                    clock.now = 1.1
                return result

        device = LateCapture([xml("Grid")])
        with self.assertRaises(ui.UIBlocked):
            ui.UIDriver(device, clock=clock, sleep=clock.sleep, budget=5).wait(
                "grid", seconds=1)
        self.assertEqual(device.calls[-1][0], ("rm", "-f", OWNED))

    def test_wait_selected_polls_until_asynchronous_selection_is_observed(self):
        clock = FakeClock()
        selected = xml("List").replace('enabled="true"', 'selected="true" enabled="true"')
        device = Device([xml("List"), selected])
        driver = ui.UIDriver(device, clock=clock, sleep=clock.sleep, budget=3)

        observed = driver.wait_selected("list", seconds=2)

        self.assertTrue(observed.selected)
        self.assertGreater(clock.now, 0)
        self.assertEqual(len([call for call in device.calls if call[0][0] == "uiautomator"]), 2)

    def test_deadline_does_not_spin_or_issue_late_commands(self):
        clock = FakeClock()
        device = Device()
        driver = ui.UIDriver(device, clock=clock, sleep=clock.sleep, budget=1)
        with self.assertRaises(ui.UIBlocked):
            driver.wait("grid")
        count = len(device.calls)
        with self.assertRaises(ui.UIBlocked):
            driver.tap("grid")
        self.assertEqual(len(device.calls), count)
        self.assertLessEqual(clock.now, 1)

    def test_tap_requires_unique_enabled_clickable_current_node(self):
        for frame in [xml("Grid", "Grid"), xml("Grid", clickable=False),
                      xml("Grid").replace('enabled="true"', 'enabled="false"')]:
            device = Device([frame])
            with self.assertRaises(ui.UIBlocked):
                ui.UIDriver(device).tap("grid")
            self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))
        device = Device([xml("Grid")])
        ui.UIDriver(device).tap("grid")
        self.assertEqual(device.calls[-1][:2], (('input', 'tap', '60', '50'), True))

    def test_partial_startup_is_not_scenario_pass_and_owner_is_untouched(self):
        report = rows()
        before = copy.deepcopy(report)
        ui.run_ui_scenarios(Device([xml("Set up your Library")]), report, {})
        self.assertEqual(report["AND-01"]["automation_status"], "BLOCKED")
        self.assertTrue(report["AND-01"]["assertions"])
        self.assertNotIn("PASS", [row["automation_status"] for row in report.values()])
        for key, row in report.items():
            self.assertEqual(row["owner_qualification_status"], before[key]["owner_qualification_status"])
            self.assertEqual(row["owner_checkpoint"], before[key]["owner_checkpoint"])
        self.assertEqual(report["AND-04"]["automation_status"], "NOT RUN")
        self.assertEqual(report["AND-06"]["automation_status"], "BLOCKED")
        self.assertEqual(report["CNT-11"]["automation_status"], "BLOCKED")

    def test_command_failure_report_is_sanitized_and_stops_actions(self):
        report = rows()
        device = Device(failure="am")
        ui.run_ui_scenarios(device, report, {"secret": "SECRET owner"})
        self.assertNotIn("SECRET", json.dumps(report))
        self.assertEqual(report["AND-01"]["automation_status"], "BLOCKED")
        self.assertEqual(len(device.calls), 1)

    def test_observed_product_onboarding_failure_is_fail(self):
        report = rows()
        ui.run_ui_scenarios(Device([xml("Retry Library setup")]), report, {})
        self.assertEqual(report["AND-01"]["automation_status"], "FAIL")
        self.assertEqual(report["AND-01"]["assertions"][-1]["status"], "FAIL")

    def test_fresh_flow_admits_only_owned_root_then_runs_partial_lifecycle(self):
        report = rows()
        device = ReleaseUI()
        ui.run_ui_scenarios(device, report, {})
        checks = {entry["check"] for row in report.values() for entry in row["assertions"]}
        self.assertTrue({"owned_root_admitted", "library_controls", "background_return",
                         "process_relaunch", "provider_entry"}.issubset(checks))
        self.assertIn((("input", "keyevent", "KEYCODE_HOME"), True),
                      [(args, mutation) for args, mutation, _ in device.calls])
        self.assertIn((("am", "force-stop", PACKAGE), True),
                      [(args, mutation) for args, mutation, _ in device.calls])
        self.assertNotIn("PASS", [row["automation_status"] for row in report.values()])
        self.assertTrue(all(mutation for args, mutation, _ in device.calls
                            if args[0] in ("am", "input", "uiautomator", "rm")))
        self.assertTrue(all(row["owner_qualification_status"] == "NOT RUN" for row in report.values()))
        root_checks = [entry for entry in report["AND-01"]["assertions"]
                       if entry["check"] == "owned_root_admitted"]
        self.assertEqual(len(root_checks), 1)
        self.assertEqual(root_checks[0]["status"], "BLOCKED")
        self.assertIn("explicit root-admission", root_checks[0]["detail"])

    def test_unproven_root_never_selects_folder_or_commits(self):
        device = ReleaseUI(unsafe_root=True)
        report = rows()
        ui.run_ui_scenarios(device, report, {})
        self.assertEqual(device.state, "owned")
        self.assertEqual(report["AND-01"]["automation_status"], "BLOCKED")
        self.assertNotIn("/private", json.dumps(report))
        self.assertFalse(any(args[:2] == ("am", "force-stop") for args, _, _ in device.calls))

    def test_empty_library_never_runs_home_or_force_stop(self):
        device = ReleaseUI(state="library", sparse=True)
        report = rows()
        ui.run_ui_scenarios(device, report, {})
        self.assertFalse(any(args[:2] in (("input", "keyevent"), ("am", "force-stop"))
                             for args, _, _ in device.calls))
        self.assertEqual(report["AND-04"]["automation_status"], "NOT RUN")

    def test_scaling_probe_collects_only_partial_geometry_and_changes_no_settings(self):
        device = Device([xml("Search Library", "Grid")])
        report = rows()
        ui.scaling_probe(device, report)
        self.assertEqual(report["UX-A03"]["automation_status"], "BLOCKED")
        self.assertTrue(report["UX-A03"]["assertions"])
        self.assertEqual(report["UX-A03"]["owner_checkpoint"], "Owner checkpoint literal")
        self.assertFalse(any(args[0] in ("settings", "input", "am") for args, _, _ in device.calls))

    def test_scaling_probe_absent_semantics_blocks_without_raw_output(self):
        report = rows()
        ui.scaling_probe(Device([xml("SECRET owner game")]), report)
        self.assertEqual(report["UX-A03"]["automation_status"], "BLOCKED")
        self.assertNotIn("SECRET", json.dumps(report))

    def test_scaling_failure_frame_cannot_pass_geometry(self):
        report = rows()
        ui.scaling_probe(Device([xml("Grid", "Retry Library setup")]), report)
        self.assertEqual(report["UX-A03"]["automation_status"], "FAIL")
        self.assertEqual(report["UX-A03"]["assertions"][-1]["status"], "FAIL")
        self.assertNotIn("PASS", [entry["status"] for entry in report["UX-A03"]["assertions"]])

    def test_merged_distinct_action_labels_are_not_tap_targets(self):
        frame = xml("Accept current terms\nDecline and exit\nUse current preferences").replace("\n", "&#10;")
        device = Device([frame])
        with self.assertRaises(ui.UIBlocked):
            ui.UIDriver(device).tap("accept_terms")
        self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))

    def test_return_to_explicit_empty_library_is_failed_expectation(self):
        class LostLibrary(ReleaseUI):
            def frame(self):
                if self.foreground_launches > 1:
                    return xml("Search Library", "Refresh Library", "Add a library root to begin")
                return super().frame()
        report = rows()
        device = LostLibrary(state="library")
        ui.run_ui_scenarios(device, report, {})
        self.assertEqual(report["AND-04"]["automation_status"], "FAIL")
        self.assertEqual(report["AND-05"]["automation_status"], "NOT RUN")
        self.assertFalse(any(args[:2] == ("am", "force-stop") for args, _, _ in device.calls))

    def test_missing_post_lifecycle_nodes_block_within_deadline(self):
        clock = FakeClock()
        driver = ui.UIDriver(Device([xml("Search Library")]), clock=clock,
                             sleep=clock.sleep, budget=1)
        report = rows()
        with self.assertRaises(ui.UIBlocked):
            ui._lifecycle(driver, report, "AND-04")
        self.assertNotIn("PASS", [item["status"] for item in report["AND-04"]["assertions"]])

    def test_unselected_view_semantics_do_not_claim_success(self):
        class Unselected(ReleaseUI):
            def frame(self):
                return super().frame().replace('selected="true" ', '')
        report = rows()
        ui.run_ui_scenarios(Unselected(state="library"), report, {})
        self.assertEqual(report["AND-02"]["automation_status"], "BLOCKED")
        self.assertEqual(report["AND-03"]["automation_status"], "NOT RUN")
        self.assertNotIn("view_list", [entry["check"] for entry in report["AND-02"]["assertions"]])

    def test_minimal_row_subset_is_supported_without_new_rows(self):
        report = {"AND01": rows()["AND-01"]}
        ui.run_ui_scenarios(Device(failure="am"), report, {})
        self.assertEqual(list(report), ["AND01"])
        self.assertEqual(report["AND01"]["automation_status"], "BLOCKED")

    def test_parser_refuses_missing_hierarchy_and_node_limit(self):
        for frame in ['<node/>', '<hierarchy>' + f'<node package="{PACKAGE}"/>' * 10001 + '</hierarchy>']:
            with self.assertRaises(ui.UIBlocked):
                ui.parse_ui(frame)

    def test_parser_ignores_systemui_invisible_and_unrecognized_private_data(self):
        frame = '<hierarchy>' + (
            '<node package="com.android.systemui" text="SECRET"/>'
            '<node package="com.argusromtoolkit.argus" text="Grid" visible-to-user="false"/>'
            '<node package="com.argusromtoolkit.argus" text="SECRET" resource-id="/owner/private"/>'
            '</hierarchy>')
        self.assertEqual(ui.parse_ui(frame), [])

    def test_wait_does_not_retry_ambiguous_target_or_raw_command_error(self):
        for device in (Device([xml("Grid", "Grid")]), Device(failure="cat")):
            clock = FakeClock()
            with self.assertRaises(ui.UIBlocked):
                ui.UIDriver(device, clock=clock, sleep=clock.sleep).wait("grid")
            self.assertEqual(clock.now, 0)
            self.assertEqual(len([c for c in device.calls if c[0][0] == "cat"]), 1)

    def test_expired_command_never_reaches_device(self):
        clock = FakeClock()
        device = Device()
        driver = ui.UIDriver(device, clock=clock, sleep=clock.sleep, budget=0)
        with self.assertRaises(ui.UIBlocked):
            driver.command("am", "start", mutating=True)
        self.assertEqual(device.calls, [])

    def test_onboarding_job_route_returns_through_visible_library_navigation(self):
        class JobRoute(ReleaseUI):
            waiting_for_library = False

            def frame(self):
                if self.waiting_for_library:
                    self.positions = {("60", "50"): "Library"}
                    return xml("Library")
                return super().frame()

            def shell(self, *args, **kwargs):
                label = self.positions.get(args[2:]) if args[:2] == ("input", "tap") else None
                result = super().shell(*args, **kwargs)
                if label == "Add folder":
                    self.waiting_for_library = True
                elif label == "Library":
                    self.waiting_for_library = False
                return result
        report = rows()
        ui.run_ui_scenarios(JobRoute(), report, {})
        self.assertIn("library_controls", [entry["check"] for entry in report["AND-02"]["assertions"]])

    def test_tap_refuses_product_failure_observed_between_wait_and_action(self):
        device = Device([xml("Grid", "Retry Library setup")])
        with self.assertRaises(ui.UIFailed):
            ui.UIDriver(device).tap("grid")
        self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))

    def test_prior_failed_evidence_is_never_downgraded_by_partial_observation(self):
        report = rows()
        report["AND-01"]["automation_status"] = "FAIL"
        report["AND-01"]["reason"] = "Prior failed expectation."
        ui.run_ui_scenarios(Device(failure="am"), report, {})
        self.assertEqual(report["AND-01"]["automation_status"], "FAIL")
        self.assertEqual(report["AND-01"]["reason"], "Prior failed expectation.")

    def test_reveal_uses_fresh_unique_scroll_geometry_for_each_guarded_swipe(self):
        first = xml("PRIVATE container", bounds="[10,20][110,220]").replace(
            'enabled="true"', 'scrollable="true" enabled="true"')
        second = xml("PRIVATE replacement", bounds="[20,40][220,440]").replace(
            'enabled="true"', 'scrollable="true" enabled="true"')
        device = Device([first, second, xml("Grid")])
        nodes = ui.UIDriver(device).reveal("grid")
        self.assertEqual(ui.select_unique(nodes, "grid").bounds, (10, 20, 110, 80))
        gestures = [(args, mutation) for args, mutation, _ in device.calls if args[0] == "input"]
        self.assertEqual(gestures, [
            (("input", "swipe", "60", "180", "60", "60", "300"), True),
            (("input", "swipe", "120", "360", "120", "120", "300"), True)])

    def test_reveal_refuses_ambiguous_or_missing_scroll_surface_without_gesture(self):
        ambiguous = xml("PRIVATE first", "PRIVATE second").replace(
            'enabled="true"', 'scrollable="true" enabled="true"')
        for frame in (ambiguous, xml(), xml("Grid", "Grid")):
            with self.subTest(frame=frame):
                device = Device([frame])
                with self.assertRaises(ui.UIBlocked):
                    ui.UIDriver(device).reveal("grid")
                self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))

    def test_reveal_refuses_disabled_scroll_surface_without_input(self):
        frame = xml("PRIVATE scroll container", bounds="[10,20][110,220]").replace(
            'enabled="true"', 'scrollable="true" enabled="false"')
        device = Device([frame])
        with self.assertRaises(ui.UIBlocked) as error:
            ui.UIDriver(device).reveal("grid")
        self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))
        self.assertNotIn("PRIVATE", str(error.exception))

    def test_reveal_missing_target_stops_after_four_swipes_and_respects_deadline(self):
        frame = xml("PRIVATE container", bounds="[10,20][110,220]").replace(
            'enabled="true"', 'scrollable="true" enabled="true"')
        device = Device([frame])
        clock = FakeClock()
        with self.assertRaises(ui.UIBlocked) as error:
            ui.UIDriver(device, clock=clock, sleep=clock.sleep, budget=2).reveal("grid")
        self.assertEqual(len([args for args, _, _ in device.calls if args[:2] == ("input", "swipe")]), 4)
        self.assertEqual(len([args for args, _, _ in device.calls if args[0] == "cat"]), 5)
        self.assertNotIn("PRIVATE", str(error.exception))
        expired = Device([frame])
        with self.assertRaises(ui.UIBlocked):
            ui.UIDriver(expired, clock=clock, sleep=clock.sleep, budget=0).reveal("grid")
        self.assertEqual(expired.calls, [])

    def test_scroll_nodes_expose_only_sanitized_identity_and_geometry(self):
        frame = xml("PRIVATE game /owner/collection", clickable=False).replace(
            'enabled="true"', 'scrollable="true" enabled="true"')
        nodes = ui.parse_ui(frame)
        self.assertEqual([node.key for node in nodes], ["scroll_surface"])
        self.assertEqual(nodes[0].bounds, (10, 20, 110, 80))
        self.assertNotIn("PRIVATE", repr(nodes))
        self.assertNotIn("/owner", repr(nodes))
        failing = frame.replace('</hierarchy>', xml("Retry Library setup").split('rotation="0">')[1])
        device = Device([failing])
        with self.assertRaises(ui.UIFailed):
            ui.UIDriver(device).reveal("grid")
        self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))

    def test_library_controls_probe_runs_without_search_or_game_population_claims(self):
        import xml.etree.ElementTree as ET
        class ControlsOnly(ReleaseUI):
            def frame(self):
                hierarchy = ET.fromstring(super().frame())
                for node in list(hierarchy):
                    if node.get("text") in ("Search Library", "Force refresh this Game"):
                        hierarchy.remove(node)
                return ET.tostring(hierarchy, encoding="unicode")
        report = rows()
        device = ControlsOnly(state="library")
        self.assertTrue(callable(getattr(ui, "library_controls_probe", None)))
        ui.library_controls_probe(device, report)
        checks = [entry["check"] for entry in report["AND-02"]["assertions"] if entry["status"] == "PASS"]
        self.assertEqual(checks, ["library_controls", "view_list", "view_grid", "sort_direction_toggle"])
        self.assertEqual(report["AND-02"]["automation_status"], "BLOCKED")
        self.assertEqual(report["AND-02"]["owner_qualification_status"], "NOT RUN")
        self.assertNotIn("game action", json.dumps(report["AND-02"]["assertions"]))
        self.assertNotIn("search", json.dumps(report["AND-02"]["assertions"]).lower())

    def test_library_controls_probe_classifies_missing_controls_and_product_failure(self):
        self.assertTrue(callable(getattr(ui, "library_controls_probe", None)))
        for frame, status in ((xml("Search Library", "Grid", "List"), "BLOCKED"),
                              (xml("Refresh Library", "Grid", "List", "Retry Library setup"), "FAIL")):
            with self.subTest(status=status):
                report = rows()
                device = Device([frame])
                ui.library_controls_probe(device, report)
                self.assertEqual(report["AND-02"]["automation_status"], status)
                self.assertEqual(report["AND-02"]["assertions"][-1]["status"], status)
                self.assertFalse(any(args[0] == "input" for args, _, _ in device.calls))

    def test_surface_lifecycle_probe_returns_only_fixed_controls_for_both_transitions(self):
        self.assertTrue(callable(getattr(ui, "surface_lifecycle_probe", None)))
        for scenario, transition in (("AND-04", ("input", "keyevent", "KEYCODE_HOME")),
                                     ("AND-05", ("am", "force-stop", PACKAGE))):
            with self.subTest(scenario=scenario):
                report = rows()
                before = copy.deepcopy(report)
                device = Device([xml("Refresh Library", "Grid", "List")])
                ui.surface_lifecycle_probe(device, report, scenario)
                actions = [(args, mutation) for args, mutation, _ in device.calls if args[0] in ("input", "am")]
                self.assertEqual(actions, [(transition, True),
                                 (("am", "start", "-W", "-n", PACKAGE + "/.MainActivity"), True)])
                self.assertEqual(report[scenario]["automation_status"], "BLOCKED")
                self.assertEqual(report[scenario]["assertions"][-1]["check"], "surface_return")
                self.assertEqual(report[scenario]["assertions"][-1]["status"], "PASS")
                for key in report:
                    self.assertEqual(report[key]["owner_qualification_status"], before[key]["owner_qualification_status"])
                    self.assertEqual(report[key]["owner_checkpoint"], before[key]["owner_checkpoint"])
                    if key != scenario:
                        self.assertEqual(report[key], before[key])

    def test_surface_lifecycle_probe_refuses_missing_ambiguous_disabled_or_failed_initial_surface(self):
        self.assertTrue(callable(getattr(ui, "surface_lifecycle_probe", None)))
        for frame, status in ((xml("Refresh Library", "Grid"), "BLOCKED"),
                              (xml("Refresh Library", "Grid", "List", "List"), "BLOCKED"),
                              (xml("Refresh Library", "Grid", "List").replace('enabled="true"', 'enabled="false"'), "BLOCKED"),
                              (xml("Refresh Library", "Grid", "List", "Retry Library setup"), "FAIL")):
            with self.subTest(status=status):
                report = rows()
                device = Device([frame])
                ui.surface_lifecycle_probe(device, report, "AND-04")
                self.assertEqual(report["AND-04"]["automation_status"], status)
                self.assertFalse(any(args[0] in ("am", "input") for args, _, _ in device.calls))

    def test_surface_lifecycle_probe_blocks_invalid_scenario_and_sanitizes_command_failure(self):
        self.assertTrue(callable(getattr(ui, "surface_lifecycle_probe", None)))
        device = Device([xml("Refresh Library", "Grid", "List")])
        report = rows()
        ui.surface_lifecycle_probe(device, report, "AND-06")
        self.assertFalse(any(args[0] in ("am", "input") for args, _, _ in device.calls))
        failing = Device([xml("Refresh Library", "Grid", "List")], failure="am")
        ui.surface_lifecycle_probe(failing, report, "AND-05")
        self.assertEqual(report["AND-05"]["automation_status"], "BLOCKED")
        self.assertNotIn("SECRET", json.dumps(report))

    def test_surface_lifecycle_probe_cannot_pass_when_returned_controls_are_missing(self):
        self.assertTrue(callable(getattr(ui, "surface_lifecycle_probe", None)))
        clock = FakeClock()
        original = ui.UIDriver
        device = Device([xml("Refresh Library", "Grid", "List"), xml()])
        report = rows()
        with patch.object(ui, "UIDriver", side_effect=lambda target, budget: original(
                target, clock=clock, sleep=clock.sleep, budget=budget)):
            ui.surface_lifecycle_probe(device, report, "AND-04")
        self.assertLessEqual(clock.now, 30)
        self.assertTrue(all(0 < timeout <= 30 for _, _, timeout in device.calls))
        self.assertEqual(report["AND-04"]["automation_status"], "BLOCKED")
        self.assertNotIn("PASS", [entry["status"] for entry in report["AND-04"]["assertions"]])


if __name__ == "__main__":
    unittest.main()
