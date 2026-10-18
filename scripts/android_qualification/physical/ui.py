"""Bounded black-box observations of the unmodified Android Release UI.

The caller supplies a device whose shell/run methods validate the exact target
before each command. This module never invokes adb directly or app test APIs.
Only the fixed test-owned XML file is written on device; XML is read into memory
and removed through the same guarded boundary. Public evidence contains stable
check identifiers and literal descriptions, never arbitrary accessibility text.

Selectors follow the presentation-owned onboarding, filesystem browser, Library,
and Settings Dart widgets. Android uses Argus's browser over native filesystem
access, rather than Android DocumentsUI. Missing Release semantics are blockers;
coordinates are derived only from unique enabled clickable accessibility nodes.
Partial assertions never constitute complete physical owner qualification.
"""

from dataclasses import dataclass
import re
import time
import xml.etree.ElementTree as ET

PACKAGE = "com.argusromtoolkit.argus"
DEVICE_ROOT = "/sdcard/ArgusQualification"
UI_XML = DEVICE_ROOT + "/ui.xml"
COMPONENT = PACKAGE + "/.MainActivity"

# Keep this vocabulary synchronized with the presentation widgets named above.
# Values are internal tokens; captured text is discarded before returning nodes.
_LABELS = {
    "Set up your Library": "onboarding",
    "Accept current terms": "accept_terms",
    "Decline and exit": "decline_exit",
    "Use current preferences": "preferences",
    "Skip SteamGridDB": "skip_provider",
    "Add a Library folder": "add_root",
    "Add Library root?": "confirm_root",
    "Add folder": "commit_root",
    "Choose a storage volume": "volumes",
    "Select this folder": "select_folder",
    "ArgusQualification": "owned_folder",
    DEVICE_ROOT: "owned_path",
    "/storage/emulated/0/ArgusQualification": "owned_path",
    "/storage/self/primary/ArgusQualification": "owned_path",
    "/storage/emulated/0": "storage_root",
    "/storage/self/primary": "storage_root",
    "/sdcard": "storage_root",
    "Internal shared storage": "storage_root",
    "Internal shared storage / ArgusQualification": "owned_path",
    "Library": "library_navigation",
    "Settings": "settings_navigation",
    "Jobs": "jobs_navigation",
    "Search Library": "search",
    "Refresh Library": "refresh",
    "Grid": "grid",
    "List": "list",
    "Ascending": "ascending",
    "Descending": "descending",
    "Force refresh this Game": "game_action",
    "No games match this query": "empty_query",
    "Add a library root to begin": "empty_roots",
    "Providers": "providers",
    "SteamGridDB API key": "credential_field",
    "Replace SteamGridDB API key": "credential_field",
    "Retry Library setup": "product_failure",
    "That onboarding step could not be saved": "product_failure",
    "The Library root picker could not open": "product_failure",
    "The Library root could not be added": "product_failure",
    "Library setup was saved but could not be completed": "product_failure",
    "Could not load mounted storage": "product_failure",
    "Could not load this folder": "product_failure",
}

_ACTION_KEYS = {
    "accept_terms", "decline_exit", "preferences", "skip_provider", "add_root",
    "commit_root", "select_folder", "owned_folder", "storage_root",
    "library_navigation", "settings_navigation", "jobs_navigation", "search",
    "refresh", "grid", "list", "ascending", "descending", "game_action",
    "credential_field",
}


class UIBlocked(Exception):
    """A literal, sanitized observation limitation (never raw device output)."""


class UIFailed(Exception):
    """An explicitly observed product failure, distinct from missing semantics."""


class UICleanupBlocked(Exception):
    """A transient accessibility file could not be removed safely."""

    def __init__(self, *, product_failure_observed=False):
        self.product_failure_observed = bool(product_failure_observed)
        self.scenario = None
        super().__init__("Guarded UI capture cleanup failed; owner follow-up is required.")


@dataclass(frozen=True)
class Node:
    """Allowlisted identity and geometry; no arbitrary text or resource IDs."""

    key: str
    bounds: tuple[int, int, int, int]
    enabled: bool
    clickable: bool
    selected: bool


def parse_ui(xml: str) -> list[Node]:
    """Parse bounded XML in memory and discard all non-allowlisted labels.

    Reject malformed bounds on recognized nodes, foreign app surfaces, and XML
    entity declarations. System status/navigation nodes are ignored. Exact
    newline-separated labels accommodate Flutter's merged accessibility nodes.
    """
    if (not isinstance(xml, str) or len(xml) > 2 * 1024 * 1024
            or "<!DOCTYPE" in xml.upper() or "<!ENTITY" in xml.upper()):
        raise UIBlocked("Accessibility capture is invalid or exceeds its bound.")
    try:
        root = ET.fromstring(xml)
    except (ET.ParseError, ValueError):
        raise UIBlocked("Accessibility XML could not be parsed.") from None
    if root.tag != "hierarchy":
        raise UIBlocked("Accessibility hierarchy is missing.")
    elements = []
    for index, element in enumerate(root.iter("node")):
        if index >= 10000:
            raise UIBlocked("Accessibility node limit exceeded.")
        package = element.get("package", "")
        if package == "com.android.systemui":
            continue
        if package != PACKAGE:
            raise UIBlocked("A foreign or unidentified UI surface prevents selection.")
        if element.get("visible-to-user", "true") == "false":
            continue
        keys = {_LABELS[line] for attribute in ("text", "content-desc")
                for line in element.get(attribute, "").splitlines()
                if line in _LABELS}
        if element.get("scrollable") == "true":
            keys.add("scroll_surface")
        elements.append((element, keys))

    # An explicit failure is stronger evidence than unrelated geometry in the
    # same frame. Validate every surface first, then return only its safe token.
    if any("product_failure" in keys for _, keys in elements):
        return [Node("product_failure", (0, 0, 0, 0), False, False, False)]

    result = []
    for element, keys in elements:
        if not keys:
            continue
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
                             element.get("bounds", ""))
        if not match:
            raise UIBlocked("Recognized control has invalid geometry.")
        bounds = tuple(map(int, match.groups()))
        left, top, right, bottom = bounds
        if right <= left or bottom <= top or max(bounds) > 32768:
            raise UIBlocked("Recognized control has invalid geometry.")
        for key in sorted(keys):
            result.append(Node(key, bounds, element.get("enabled") == "true",
                               element.get("clickable") == "true"
                               and len(keys & _ACTION_KEYS) <= 1,
                               element.get("selected") == "true"))
    return result


def select_unique(nodes: list[Node], key: str, *, actionable=False) -> Node:
    """Refuse absent or ambiguous labels, and non-actionable tap targets."""
    matches = [node for node in nodes if node.key == key]
    if len(matches) != 1:
        raise UIBlocked("Required accessibility target is missing or ambiguous.")
    node = matches[0]
    if actionable and (not node.enabled or not node.clickable):
        raise UIBlocked("Required accessibility target is not actionable.")
    return node


class UIDriver:
    """One monotonic deadline bounds all waits, launches, captures and inputs."""

    def __init__(self, device, *, clock=time.monotonic, sleep=time.sleep, budget=120):
        self.device = device
        self.clock = clock
        self.sleep = sleep
        self.deadline = clock() + budget

    def command(self, *args, mutating=False, until=None):
        """Forward through the caller's guard and replace unsafe error messages."""
        deadline = self.deadline if until is None else min(self.deadline, until)
        remaining = deadline - self.clock()
        if remaining <= 0:
            raise UIBlocked("UI observation deadline expired.")
        try:
            result = self.device.shell(*args, mutating=mutating,
                                       timeout=min(30, remaining))
        except (KeyboardInterrupt, InterruptedError):
            raise
        except Exception:
            raise UIBlocked("Guarded device command failed; output was discarded.") from None
        if self.clock() >= deadline:
            raise UIBlocked("UI observation deadline expired during a device command.")
        return result

    def capture(self, *, until=None) -> list[Node]:
        """Dump only the fixed owned file, read in memory, and always remove it."""
        deadline = self.deadline if until is None else min(self.deadline, until)
        if self.clock() >= deadline:
            raise UIBlocked("UI observation deadline expired.")
        primary_error = None
        nodes = None
        try:
            self.command("uiautomator", "dump", UI_XML, mutating=True, until=deadline)
            xml = self.command("cat", UI_XML, until=deadline)
            nodes = parse_ui(xml)
        except BaseException as error:
            primary_error = error
        product_failure = bool(nodes and any(node.key == "product_failure" for node in nodes))

        # Cleanup gets its own small bound, even after an observation timeout.
        # The supplied Device still validates the target before this command.
        try:
            self.device.shell("rm", "-f", UI_XML, mutating=True,
                              timeout=min(5, max(.1, self.deadline - self.clock())))
        except (KeyboardInterrupt, InterruptedError) as error:
            error.ui_cleanup_blocker = 'Guarded UI capture cleanup was interrupted.'
            error.ui_product_failure_observed = product_failure
            raise
        except Exception:
            if isinstance(primary_error, (KeyboardInterrupt, InterruptedError)):
                primary_error.ui_cleanup_blocker = 'Guarded UI capture cleanup failed.'
                primary_error.ui_product_failure_observed = product_failure
                raise primary_error.with_traceback(primary_error.__traceback__)
            raise UICleanupBlocked(product_failure_observed=product_failure) from None

        if primary_error is not None:
            raise primary_error.with_traceback(primary_error.__traceback__)
        return nodes

    def wait(self, *keys, seconds=10, until=None) -> list[Node]:
        """Wait for at least one unique target; ambiguity never triggers a tap."""
        deadline = min(self.deadline, self.clock() + seconds,
                       self.deadline if until is None else until)
        while self.clock() < deadline:
            nodes = self.capture(until=deadline)
            if self.clock() >= deadline:
                raise UIBlocked("Required Release accessibility target was not observed in time.")
            if any(node.key == "product_failure" for node in nodes):
                raise UIFailed("The Release UI reports a product operation failure.")
            for key in keys:
                if any(node.key == key for node in nodes):
                    select_unique(nodes, key)
                    return nodes
            remaining = deadline - self.clock()
            if remaining > 0:
                self.sleep(min(.25, remaining))
        raise UIBlocked("Required Release accessibility target was not observed in time.")

    def wait_selected(self, key, *, selected=True, seconds=5, until=None) -> Node:
        """Poll one exact control until its accessibility selected state settles."""
        deadline = min(self.deadline, self.clock() + seconds,
                       self.deadline if until is None else until)
        while self.clock() < deadline:
            nodes = self.capture(until=deadline)
            if self.clock() >= deadline:
                raise UIBlocked("View-mode selection was not observed before its deadline.")
            if any(node.key == "product_failure" for node in nodes):
                raise UIFailed("The Release UI reports a product operation failure.")
            matches = [node for node in nodes if node.key == key]
            if len(matches) > 1:
                raise UIBlocked("Required accessibility target is missing or ambiguous.")
            if matches and matches[0].selected is selected:
                return matches[0]
            remaining = deadline - self.clock()
            if remaining > 0:
                self.sleep(min(.25, remaining))
        raise UIBlocked("Requested view-mode selection was not observed in time.")

    def tap(self, key):
        """Re-capture immediately before each tap; never reuse stale geometry."""
        nodes = self.capture()
        if any(node.key == "product_failure" for node in nodes):
            raise UIFailed("The Release UI reports a product operation failure.")
        node = select_unique(nodes, key, actionable=True)
        left, top, right, bottom = node.bounds
        self.command("input", "tap", str((left + right) // 2),
                     str((top + bottom) // 2), mutating=True)

    def reveal(self, *keys):
        """Scroll at most four times using one exposed scrollable surface.

        This accommodates short physical displays without guessing a screen
        region. Every gesture derives geometry from a fresh unique container;
        subsequent selection still requires a visible exact labeled target.
        """
        for attempt in range(5):
            nodes = self.capture()
            if any(node.key == "product_failure" for node in nodes):
                raise UIFailed("The Release UI reports a product operation failure.")
            if any(node.key in keys for node in nodes):
                return self.wait(*keys, seconds=2)
            if attempt == 4:
                break
            node = select_unique(nodes, "scroll_surface")
            if not node.enabled:
                raise UIBlocked("The exposed scroll surface is disabled.")
            left, top, right, bottom = node.bounds
            x = (left + right) // 2
            self.command("input", "swipe", str(x), str(top + (bottom-top)*4//5),
                         str(x), str(top + (bottom-top)//5), "300", mutating=True)
        raise UIBlocked("Required Release target was not exposed by bounded scrolling.")


def _row(rows, scenario):
    """Accept ledger IDs with or without hyphens without creating new rows."""
    return next((row for key, row in rows.items()
                 if key.replace("-", "") == scenario.replace("-", "")), None)


def _assert(rows, scenario, check, status, detail):
    row = _row(rows, scenario)
    if row is not None:
        row.setdefault("assertions", []).append(
            {"check": check, "status": status, "detail": detail})


def _status(rows, scenario, status, reason):
    row = _row(rows, scenario)
    if row is not None:
        # Preserve failed evidence across subsequent partial observations.
        if row.get("automation_status") == "FAIL" and status != "FAIL":
            return
        row["automation_status"] = status
        row["reason"] = reason


def _onboard(driver, nodes, rows):
    """Follow only exposed steps and prove the owned path before admission."""
    steps = (
        ("accept_terms", ("preferences", "skip_provider", "add_root")),
        ("preferences", ("skip_provider", "add_root")),
        ("skip_provider", ("add_root",)),
    )
    for key, next_keys in steps:
        if any(node.key == key for node in nodes):
            driver.tap(key)
            _assert(rows, "AND-01", key, "PASS",
                    "An exposed onboarding choice was invoked through the product UI.")
            nodes = driver.wait(*next_keys) if key != "skip_provider" else driver.reveal(*next_keys)
    select_unique(nodes, "add_root", actionable=True)
    driver.tap("add_root")
    nodes = driver.wait("volumes")
    # Only the primary storage mount is eligible. No arbitrary volume names,
    # injected paths, scrolling guesses, or DocumentsUI shortcuts are used.
    if any(set(line.split()) & {"mounted", "mounted_ro"} for line in
           driver.command("sm", "list-volumes", "public").splitlines()):
        raise UIBlocked("Mounted removable storage prevents the fixed primary-storage selector proof.")
    select_unique(nodes, "storage_root", actionable=True)
    driver.tap("storage_root")
    driver.reveal("owned_folder")
    driver.tap("owned_folder")
    nodes = driver.wait("select_folder")
    select_unique(nodes, "owned_path")
    driver.tap("select_folder")
    nodes = driver.wait("confirm_root")
    select_unique(nodes, "owned_path")
    driver.tap("commit_root")
    _assert(rows, "AND-01", "owned_root_selection", "PASS",
            "The exact owned primary-storage folder was selected and the confirmation action was invoked.")
    nodes = driver.wait("search", "library_navigation")
    if not any(node.key == "search" for node in nodes):
        driver.tap("library_navigation")
        nodes = driver.wait("search")
    _assert(rows, "AND-01", "owned_root_admitted", "BLOCKED",
            "The returned Library surface exposes no explicit root-admission confirmation.")
    return nodes


def _established(nodes):
    """Game action controls prove only an observable populated Library surface."""
    return (any(node.key == "game_action" for node in nodes)
            and any(node.key == "search" for node in nodes)
            and any(node.key == "refresh" for node in nodes)
            and not any(node.key in ("empty_query", "empty_roots") for node in nodes))


def _returned_library(driver):
    nodes = driver.wait("search")
    if any(node.key in ("empty_roots", "empty_query") for node in nodes):
        raise UIFailed("Previously populated Library now explicitly reports an empty state.")
    if not _established(nodes):
        raise UIBlocked("Populated Library controls are not observable after the transition.")
    return nodes


def _lifecycle(driver, rows, scenario):
    """Probe foreground return or process loss, without asserting job truth."""
    if scenario == "AND-04":
        driver.command("input", "keyevent", "KEYCODE_HOME", mutating=True)
        check = "background_return"
    else:
        driver.command("am", "force-stop", PACKAGE, mutating=True)
        check = "process_relaunch"
    driver.command("am", "start", "-W", "-n", COMPONENT, mutating=True)
    _returned_library(driver)
    _assert(rows, scenario, check, "PASS",
            "Recognized populated Library controls are observable after the lifecycle transition.")
    _status(rows, scenario, "BLOCKED",
            "UI surface return does not prove authoritative runtime/job state, active-work interruption, persistence, or explicit retry.")


def _library_controls(driver, rows):
    """Exercise view and sort-direction controls without claiming record correctness."""
    nodes = driver.capture()
    if any(node.key == "product_failure" for node in nodes):
        raise UIFailed("The Release UI reports a product operation failure.")
    select_unique(nodes, "refresh")
    _assert(rows, "AND-02", "library_controls", "PASS",
            "A unique Library refresh control is observable; view and sort controls are evaluated separately.")
    for key in ("list", "grid"):
        driver.tap(key)
        driver.wait_selected(key, selected=True, seconds=5)
        _assert(rows, "AND-02", "view_" + key, "PASS",
                "The requested view-mode control exposes selected state.")
    nodes = driver.capture()
    current = "ascending" if any(node.key == "ascending" for node in nodes) else "descending"
    opposite = "descending" if current == "ascending" else "ascending"
    driver.tap(current)
    driver.wait(opposite)
    driver.tap(opposite)
    driver.wait(current)
    _assert(rows, "AND-02", "sort_direction_toggle", "PASS",
            "The sort-direction control changed and returned to its original label.")
    _status(rows, "AND-02", "BLOCKED",
            "Control transitions do not prove search/filter results, ordering, paging, stable selection, or game-detail correctness.")


def library_controls_probe(device, rows: dict[str, dict]) -> None:
    """Exercise exposed view/sort controls within 30 seconds without population proof.

    The current surface must expose a unique refresh control. View selection and
    direction changes establish only control behavior, never query correctness,
    content identity, game population, or owner qualification.
    """
    _status(rows, "AND-02", "BLOCKED",
            "Library control observations do not prove correct records or complete critical-flow coverage.")
    try:
        _library_controls(UIDriver(device, budget=30), rows)
    except UICleanupBlocked as error:
        error.scenario = "AND-02"
        raise
    except (KeyboardInterrupt, InterruptedError) as error:
        if getattr(error, "ui_cleanup_blocker", None):
            error.ui_cleanup_scenario = "AND-02"
        raise
    except (UIBlocked, UIFailed) as error:
        status = "FAIL" if isinstance(error, UIFailed) else "BLOCKED"
        _assert(rows, "AND-02", "library_controls_probe", status, str(error))
        _status(rows, "AND-02", status, str(error))


def _fixed_library_surface(nodes):
    """Require unique enabled fixed controls, without interpreting any game labels."""
    if any(node.key == "product_failure" for node in nodes):
        raise UIFailed("The Release UI reports a product operation failure.")
    for key in ("refresh", "grid", "list"):
        if not select_unique(nodes, key).enabled:
            raise UIBlocked("A fixed Library surface control is disabled.")


def surface_lifecycle_probe(device, rows: dict[str, dict], scenario: str) -> None:
    """Probe HOME return or process relaunch against fixed controls within 30 seconds.

    Only AND-04 and AND-05 are eligible. A unique enabled refresh, Grid and List
    surface is required before any lifecycle action and again after relaunch.
    Returning controls cannot prove job authority, committed records, active-work
    interruption, absence of automatic resume, or explicit recovery/retry.
    Owner statuses and checkpoint text are never changed.
    """
    driver = UIDriver(device, budget=30)
    try:
        if scenario not in ("AND-04", "AND-05"):
            raise UIBlocked("Surface lifecycle probe requires an eligible lifecycle scenario.")
        _fixed_library_surface(driver.capture())
        if scenario == "AND-04":
            driver.command("input", "keyevent", "KEYCODE_HOME", mutating=True)
        else:
            driver.command("am", "force-stop", PACKAGE, mutating=True)
        driver.command("am", "start", "-W", "-n", COMPONENT, mutating=True)
        _fixed_library_surface(driver.wait("refresh"))
        _assert(rows, scenario, "surface_return", "PASS",
                "Unique enabled refresh, Grid and List controls are observable after the lifecycle transition.")
        _status(rows, scenario, "BLOCKED",
                "Fixed surface return does not prove jobs, records, active-work interruption, automatic-resume policy, or explicit retry.")
    except (UIBlocked, UIFailed) as error:
        status = "FAIL" if isinstance(error, UIFailed) else "BLOCKED"
        _assert(rows, scenario, "surface_return", status, str(error))
        _status(rows, scenario, status, str(error))
    except UICleanupBlocked as error:
        error.scenario = scenario
        raise
    except (KeyboardInterrupt, InterruptedError) as error:
        if getattr(error, "ui_cleanup_blocker", None):
            error.ui_cleanup_scenario = scenario
        raise


def _providers(driver, rows):
    """Observe the credential-entry boundary without entering or retaining secrets."""
    driver.tap("settings_navigation")
    nodes = driver.wait("providers", "credential_field")
    select_unique(nodes, "credential_field")
    _assert(rows, "AND-03", "provider_entry", "PASS",
            "The product UI exposes a SteamGridDB credential-entry control; no credential was supplied.")
    _status(rows, "AND-03", "BLOCKED",
            "No credentials are available; entry-control observation does not prove secure storage, provider readiness, hydration, or artwork.")
    driver.tap("library_navigation")
    driver.wait("search")


def _geometry(nodes, rows, scenario, check):
    """Record geometry only when the captured frame has no product error."""
    if any(node.key == "product_failure" for node in nodes):
        raise UIFailed("The Release UI reports a product operation failure.")
    controls = [node for node in nodes if node.enabled and node.clickable]
    if not controls:
        raise UIBlocked("No recognized actionable geometry is exposed by Release accessibility.")
    _assert(rows, scenario, check, "PASS",
            "Recognized actionable controls expose positive pixel bounds; physical usability and clipping remain owner checks.")


def scaling_probe(device, rows: dict[str, dict]) -> None:
    """Observe current UI geometry after caller-owned font/display changes.

    The caller snapshots, changes, and restores settings separately. This probe
    does not launch the app, change settings, tap controls, or claim readability,
    overlap, reachability, supported-scale coverage, or owner qualification.
    An explicit product-failure label in the frame is recorded as failure and
    cannot be treated as geometry success.
    """
    _status(rows, "UX-A03", "BLOCKED",
            "Scaling geometry is partial; readable critical flows and clipping require owner observation.")
    try:
        _geometry(UIDriver(device, budget=15).capture(), rows, "UX-A03", "scaled_geometry")
    except UICleanupBlocked as error:
        error.scenario = "UX-A03"
        raise
    except (KeyboardInterrupt, InterruptedError) as error:
        if getattr(error, "ui_cleanup_blocker", None):
            error.ui_cleanup_scenario = "UX-A03"
        raise
    except (UIBlocked, UIFailed) as error:
        status = "FAIL" if isinstance(error, UIFailed) else "BLOCKED"
        _assert(rows, "UX-A03", "scaled_geometry", status, str(error))
        _status(rows, "UX-A03", status, str(error))


def run_ui_scenarios(device, rows: dict[str, dict], fixture_summary: dict) -> None:
    """Append sanitized observations, preserving owner status/checkpoint fields.

    A startup observation cannot prove scan/identification correctness. Content
    inventory is supplied for integration but cannot substitute for UI results.
    The caller owns fresh-state provenance, signing, installation, settings,
    and fixture upload. This function never clears data or changes settings.
    """
    for key in rows:
        if key.replace("-", "").startswith(("AND", "CNT", "UXA")):
            _status(rows, key, "NOT RUN", "UI scenario has not been evaluated.")
    for scenario in ("AND-06", "CNT-11"):
        _status(rows, scenario, "BLOCKED",
                "Owner media-unavailability checkpoint required; volumes are not unmounted.")
    for scenario in ("UX-A01", "UX-A02", "UX-A03"):
        _status(rows, scenario, "BLOCKED",
                "TalkBack announcements, physical touch usability, and scaling require owner critical-flow checks.")
    driver = UIDriver(device)
    scenario = "AND-01"
    try:
        driver.command("am", "start", "-W", "-n", COMPONENT, mutating=True)
        nodes = driver.wait("onboarding", "search", "accept_terms", "preferences",
                            "skip_provider", "add_root")
        _assert(rows, "AND-01", "startup_surface", "PASS",
                "A recognized Release Library or onboarding surface is observable.")
        if not any(node.key == "search" for node in nodes):
            nodes = _onboard(driver, nodes, rows)
        _status(rows, "AND-01", "BLOCKED",
                "Observable UI steps do not prove fresh-state provenance, successful scan/identification, or populated Library correctness.")
        if not _established(nodes):
            _assert(rows, "AND-01", "populated_library", "BLOCKED",
                    "A populated Library is not established; lifecycle and Library actions were not run.")
            return
        for content_key in rows:
            if content_key.replace("-", "").startswith("CNT") and content_key.replace("-", "") != "CNT11":
                _status(rows, content_key, "BLOCKED",
                        "Fixture inventory cannot prove per-content identification, grouping, action, metadata, or artwork results through this UI capture.")
        _geometry(nodes, rows, "UX-A02", "touch_geometry")
        for lifecycle_scenario in ("AND-04", "AND-05"):
            # Keep failure attribution aligned with the lifecycle being probed.
            scenario = lifecycle_scenario
            _lifecycle(driver, rows, scenario)
        scenario = "AND-02"
        _library_controls(driver, rows)
        scenario = "AND-03"
        _providers(driver, rows)
    except UICleanupBlocked as error:
        error.scenario = scenario
        raise
    except (KeyboardInterrupt, InterruptedError) as error:
        if getattr(error, "ui_cleanup_blocker", None):
            error.ui_cleanup_scenario = scenario
        raise
    except (UIBlocked, UIFailed) as error:
        status = "FAIL" if isinstance(error, UIFailed) else "BLOCKED"
        _assert(rows, scenario, "ui_observation", status, str(error))
        _status(rows, scenario, status, str(error))
