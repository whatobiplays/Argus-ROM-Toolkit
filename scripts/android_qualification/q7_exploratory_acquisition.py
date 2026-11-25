"""Capture only sanitized structure from the fixed Q7 activity dump."""

from __future__ import annotations

import hashlib
import hmac
import json
import math
import os
import re
import secrets
import stat
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, Optional

from . import _evidence_storage
from .adb_forward import (
    _BUILD_PATTERN,
    Q7CommandResult,
    _AdbCommandRunner,
    _valid_target,
    _MAX_Q7_LINE_LENGTH,
    _MAX_Q7_OUTPUT_BYTES,
    _Q7_HOST_DEADLINE_SECONDS,
)
from .readiness_probe import ProbeError
from .packaging import QUALIFICATION_APPLICATION_ID as _TARGET_PACKAGE
from .readiness_probe_artifact import PACKAGE as _READINESS_PROBE_PACKAGE


TARGET_REFERENCE = "i74-tgt-7f6cd8181514b822"
APPROVED_BASELINE_COMMIT = "ff9ce374b50b360195026404270025dfe54edd5a"
_TARGET_REFERENCE_PATTERN = re.compile(r"i74-tgt-[a-f0-9]{16}\Z")
_HEX_COMMIT_PATTERN = re.compile(r"[a-f0-9]{40}\Z")
_HEX_SHA256_PATTERN = re.compile(r"[a-f0-9]{64}\Z")
_Q7_SUBJECT_PACKAGES = frozenset({_TARGET_PACKAGE, _READINESS_PROBE_PACKAGE})
_Q7_EXPLORATORY_SCHEMA = "argus-q7-exploratory-v2"
_WINDOW_DISPLAY_EXPLORATORY_SCHEMA = "argus-q7-window-displays-exploratory-v1"
_SOURCE_FILE_NAMES = (
    "adb_forward.py",
    "readiness_probe_session.py",
    "readiness_probe_artifact.py",
    "packaging.py",
    "q7_window_display_projection.py",
    "q7_exploratory_acquisition.py",
)
_MAX_Q7_STRUCTURAL_RECORDS = 4096
_MAX_Q7_STRUCTURAL_FIELDS = 16384
_MAX_Q7_STRUCTURAL_RELATIONSHIPS = 16384
_Q7_PARSER_ERROR_SUBTYPES = frozenset(
    {
        "alias_limit_exceeded",
        "empty_normalized_alias_value",
        "field_limit_exceeded",
        "forbidden_control_character",
        "invalid_utf8",
        "line_length_exceeded",
        "parser_rejection",
        "record_limit_exceeded",
        "relationship_limit_exceeded",
    }
)
_Q7_PARSER_ERROR_STAGES = frozenset(
    {
        "control_validation",
        "field_scan",
        "finish",
        "input_validation",
        "line_accumulation",
        "record_scan",
        "target_projection",
        "utf8_decode",
    }
)
_Q7_PARSER_ERROR_CODES = frozenset(
    {"IncompleteEvidence", "MalformedRequest", "ResourceLimitExceeded"}
)
_Q7_PROCESS_CLASSIFICATIONS = frozenset(
    {
        "cleanup_unverified",
        "exit_zero",
        "host_timeout",
        "incomplete",
        "launch_failed",
        "process_nonzero",
        "resource_limit",
    }
)
_Q7_PARSER_STATE_FIELDS = frozenset(
    {
        "completed_lines",
        "empty_field_values",
        "fields_seen",
        "record_stack_depth",
        "records_seen",
        "relationships_seen",
        "sensitive_tails_truncated",
        "unclassified_lines",
        "unrecognized_fields",
    }
)
_Q7_DEVICE_TIMEOUT_SECONDS = 3
_RECORDED_LIMITS = {
    "device_timeout_seconds": _Q7_DEVICE_TIMEOUT_SECONDS,
    "host_deadline_seconds": _Q7_HOST_DEADLINE_SECONDS,
    "maximum_output_bytes": _MAX_Q7_OUTPUT_BYTES,
    "maximum_line_bytes": _MAX_Q7_LINE_LENGTH,
}
_COMPONENT_FIELD_NAMES = {
    "component",
    "mactivitycomponent",
    "cmp",
    "realactivity",
    "baseactivity",
    "topactivity",
    "componentname",
}

_FIELD_PATTERNS = {
    "activity_records": re.compile(r"\b(?:ACTIVITY|ActivityRecord|Hist #)\b", re.I),
    "component_fields": re.compile(
        r"\b(?:cmp=|ComponentInfo\{|mActivityComponent=|component=)", re.I
    ),
    "android_user_fields": re.compile(
        r"\b(?:userId|mUserId|UserHandle)\s*[=:]|\buser\s*[=:]|\bu[0-9]+a[0-9]+\b",
        re.I,
    ),
    "task_membership_fields": re.compile(
        r"\b(?:taskId|mTaskId|Task\{|TaskRecord|task=)", re.I
    ),
    "resumed_state_fields": re.compile(
        r"\b(?:mResumed|mResumedActivity|resumedActivity)\b", re.I
    ),
    "top_resumed_fields": re.compile(
        r"\b(?:topResumedActivity|mTopResumedActivity|top-resumed)\b", re.I
    ),
    "display_fields": re.compile(
        r"\b(?:displayId|mDisplayId|rootTaskCount|DisplayContent|display=)", re.I
    ),
    "windowing_fields": re.compile(
        r"\b(?:windowingMode|mWindowingMode|windowing|window mode)\b", re.I
    ),
    "task_continuity_markers": re.compile(
        r"\b(?:lastActiveTime|mLastTimeMoved|lastTimeMoved|taskAffinity)\b", re.I
    ),
    "process_fields": re.compile(
        r"\b(?:ProcessRecord|processName|pid=|mProcessName|topApp)\b", re.I
    ),
}
_TIMEOUT_PATTERN = re.compile(r"\b(?:timeout|timed\s+out)\b", re.I)
_COMPLETION_PATTERN = re.compile(
    r"\b(?:dump\s+complete|activities\s+dumped|dump\s+finished)\b", re.I
)
_RECORD_TYPES = {
    "ActivityRecord": "activity_record",
    "ActivityStack": "activity_stack",
    "DisplayContent": "display_content",
    "ProcessRecord": "process_record",
    "RootTask": "root_task",
    "RootWindowContainer": "root_window_container",
    "Task": "task",
    "TaskFragment": "task_fragment",
    "TaskRecord": "task_record",
    "WindowToken": "window_token",
}
_RECORD_CONTEXT_TYPES = {
    "activity_task": {"task", "task_record", "root_task", "task_fragment"},
    "record_display": {"display_content"},
    "record_process": {"process_record"},
}
_LAYOUT_PARENT_TYPES = {
    "activity_stack",
    "display_content",
    "root_task",
    "root_window_container",
    "task",
    "task_fragment",
    "task_record",
}
_RESUMED_SOURCE_TYPES = _LAYOUT_PARENT_TYPES | {"window_token"}
_RESUMED_RELATIONSHIPS = {"resumed_activity", "top_resumed_activity"}
_RECORD_PATTERN = re.compile(
    r"\b(?P<name>ActivityRecord|ActivityStack|DisplayContent|ProcessRecord|"
    r"RootTask|RootWindowContainer|TaskFragment|TaskRecord|Task|WindowToken)\s*"
    r"\{(?P<body>[^}\r\n]*)",
)
# Keep repeated display sections separate while linking their display ID.
_DISPLAY_HEADER_PATTERN = re.compile(
    r"(?:(?:Display[ \t]+#(?P<activity_display_id>[0-9]+)[ \t]+"
    r"\([^\r\n)]*\):)|(?:Display:[ \t]+mDisplayId="
    r"(?P<window_display_id>[0-9]+)[ \t]+rootTasks="
    r"(?P<root_task_count>[0-9]+)))[ \t]*\Z"
)
_FIELD_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_.])(?P<name>[A-Za-z][A-Za-z0-9_]{0,63})\s*[=:]\s*"
    r"(?P<value>[^,\s}]+)"
)
_FIELD_CANDIDATE_PATTERN = re.compile(
    r"(?<![^\s,{])(?P<name>[^\s=:,{}]{1,128})[ \t]*[=:]"
)
_SENSITIVE_FIELD_PATTERN = re.compile(
    r"\b(?P<name>m?Intent|sourceDir|dataDir|codePath|nativeLibraryDir|"
    r"privateDir|publicDir|path|uri|dataString)\s*[=:]",
    re.I,
)
_COMPONENT_PATTERN = re.compile(
    r"(?P<package>[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)/"
    r"(?P<class>[A-Za-z0-9_.$]+)\Z"
)
_EMPTY_STRUCTURED_VALUE_PATTERN = re.compile(
    r"[A-Za-z][A-Za-z0-9_]*\{\}?\Z",
    re.I,
)
_PACKAGE_PATTERN = re.compile(
    r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+(?:\:[A-Za-z0-9_]+)?\Z"
)
_SAFE_FIELD_NAME_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9_]{0,63}\Z")
_SAFE_ENUMS = {
    "destroyed",
    "fullscreen",
    "freeform",
    "home",
    "multi-window",
    "paused",
    "pausing",
    "pinned",
    "resumed",
    "split-screen-primary",
    "split-screen-secondary",
    "standard",
    "started",
    "stopped",
    "stopping",
    "undefined",
}
_LIMITATIONS = (
    "exploratory_only_no_qualification_assertion",
    "output_completion_not_qualified_by_a_build_specific_marker",
    "single_snapshot_cannot_establish_task_continuity",
    "field_presence_does_not_bind_records_to_the_selected_target",
    "absent_fields_are_not_evidence_of_unsupported_semantics",
    "anonymized_references_preserve_only_within_capture_equality",
)
def derive_available_field_categories(record_types, field_names):
    categories = set()
    if "activity_record" in record_types:
        categories.add("activity_records")
    for category, pattern in _FIELD_PATTERNS.items():
        if category == "activity_records":
            continue
        if any(pattern.search(f"{name}=") for name in field_names):
            categories.add(category)
    if "process_record" in record_types:
        categories.add("process_fields")
    return sorted(categories)


class Q7StructuralFilter:
    """Summarize one fixed qualification package from a bounded activity dump.

    Identifier references use a random per-capture key. The saved result keeps
    target-related field associations and hierarchy while hiding the values
    used to link them. Other app records are dropped before the result leaves
    the filter. A component match identifies a target record; affinity and
    process names provide context but do not establish app ownership.
    """

    def __init__(
        self,
        *,
        target_package=_TARGET_PACKAGE,
        maximum_line_bytes=_MAX_Q7_LINE_LENGTH,
        maximum_records=_MAX_Q7_STRUCTURAL_RECORDS,
        maximum_fields=_MAX_Q7_STRUCTURAL_FIELDS,
        maximum_relationships=_MAX_Q7_STRUCTURAL_RELATIONSHIPS,
    ):
        if type(target_package) is not str or target_package not in _Q7_SUBJECT_PACKAGES:
            raise ProbeError("MalformedRequest", "Transport")
        limits = (maximum_line_bytes, maximum_records, maximum_fields, maximum_relationships)
        if any(type(value) is not int or value <= 0 for value in limits):
            raise ProbeError("MalformedRequest", "Transport")
        self._maximum_line_bytes = maximum_line_bytes
        self._target_package = target_package
        self._maximum_records = maximum_records
        self._maximum_fields = maximum_fields
        self._maximum_relationships = maximum_relationships
        self._line = bytearray()
        self._lines_observed = 0
        self._max_line_bytes = 0
        self._categories = set()
        self._timeout_indicator = False
        self._timeout_indicator_count = 0
        self._completion_indicator = False
        self._completion_indicator_count = 0
        self._intent_content_observed = False
        self._redacted_field_names = set()
        self._field_names = set()
        self._record_type_names = set()
        self._records = []
        self._records_by_ref = {}
        self._fields = []
        self._relationships = {}
        self._record_stack = []
        self._target_record_refs = set()
        self._target_package_refs = set()
        self._target_component_refs = set()
        self._line_target_relevant = False
        self._unclassified_line_count = 0
        self._unrecognized_field_count = 0
        self._empty_field_value_count = 0
        self._sensitive_tail_truncated_count = 0
        self._alias_key = secrets.token_bytes(32)
        self._aliases = {}
        self._alias_counts = {}
        self._line_sequence = 0
        self._total_bytes_fed = 0
        self._line_start_byte_offset = 0
        self._active_line_number = None
        self._active_line_byte_offset = None
        self._parser_stage = "input_validation"
        self._failure_diagnostic = None
        self._finished = False

    @property
    def retained_bytes(self):
        return len(self._line)

    @property
    def failure_diagnostic(self):
        """Return error labels, byte positions, and counts without captured input."""
        if self._failure_diagnostic is None:
            return None
        return {
            **self._failure_diagnostic,
            "parser_state": dict(self._failure_diagnostic["parser_state"]),
        }

    def _record_failure(
        self,
        subtype,
        stage,
        error_code,
        *,
        line_number=None,
        line_byte_offset=None,
        absolute_byte_offset=None,
    ):
        """Snapshot the first failure before cleanup clears transient parser state."""
        if self._failure_diagnostic is not None:
            return
        if subtype not in _Q7_PARSER_ERROR_SUBTYPES:
            subtype = "parser_rejection"
        if stage not in _Q7_PARSER_ERROR_STAGES:
            stage = "finish"
        if error_code not in _Q7_PARSER_ERROR_CODES:
            error_code = "IncompleteEvidence"
        if line_number is None:
            line_number = self._active_line_number
        if line_byte_offset is None:
            line_byte_offset = self._active_line_byte_offset
        if (
            absolute_byte_offset is None
            and line_number is not None
            and line_byte_offset is not None
        ):
            absolute_byte_offset = self._line_start_byte_offset + line_byte_offset
        self._failure_diagnostic = {
            "subtype": subtype,
            "stage": stage,
            "error_code": error_code,
            "line_number": line_number,
            "line_byte_offset": line_byte_offset,
            "absolute_byte_offset": absolute_byte_offset,
            "parser_state": {
                "completed_lines": self._lines_observed,
                "records_seen": len(self._records),
                "fields_seen": len(self._fields),
                "relationships_seen": len(self._relationships),
                "record_stack_depth": len(self._record_stack),
                "empty_field_values": self._empty_field_value_count,
                "unrecognized_fields": self._unrecognized_field_count,
                "unclassified_lines": self._unclassified_line_count,
                "sensitive_tails_truncated": self._sensitive_tail_truncated_count,
            },
        }

    @staticmethod
    def _line_byte_offset(line, character_offset):
        return len(line[:character_offset].encode("utf-8"))

    @staticmethod
    def _sensitive_value_present(line, match):
        """Tell redacted content from an empty value followed by another field."""
        tail = line[match.end() :].lstrip(" \t,;")
        empty_wrapper = re.match(
            r"(?:[A-Za-z][A-Za-z0-9_.$]*[ \t\r]*)?\{[ \t\r]*\}", tail
        )
        if empty_wrapper is not None:
            tail = tail[empty_wrapper.end() :].lstrip(" \t,;")
        if not tail or not tail.strip("{}(),; \t\r"):
            return False
        return _FIELD_PATTERN.match(tail) is None

    def _alias(self, prefix, value, *, namespace=None):
        if not value:
            self._record_failure(
                "empty_normalized_alias_value",
                self._parser_stage,
                "IncompleteEvidence",
            )
            raise ProbeError("IncompleteEvidence", "Transport")
        domain = prefix if namespace is None else namespace
        digest = hmac.new(
            self._alias_key,
            domain.encode("ascii") + b"\0" + value.encode("utf-8"),
            hashlib.sha256,
        ).digest()
        key = (domain, digest)
        reference = self._aliases.get(key)
        if reference is not None:
            return reference
        if len(self._aliases) >= self._maximum_fields:
            self._record_failure(
                "alias_limit_exceeded", self._parser_stage, "ResourceLimitExceeded"
            )
            raise ProbeError("ResourceLimitExceeded", "Transport")
        sequence = self._alias_counts.get(prefix, 0) + 1
        if sequence > self._maximum_fields:
            self._record_failure(
                "alias_limit_exceeded", self._parser_stage, "ResourceLimitExceeded"
            )
            raise ProbeError("ResourceLimitExceeded", "Transport")
        self._alias_counts[prefix] = sequence
        reference = f"{prefix}-{sequence:04d}"
        self._aliases[key] = reference
        return reference

    def _add_relationship(self, kind, source_ref, target_ref):
        if not source_ref or not target_ref:
            return
        if len(self._relationships) >= self._maximum_relationships and (
            kind,
            source_ref,
            target_ref,
        ) not in self._relationships:
            self._record_failure(
                "relationship_limit_exceeded",
                self._parser_stage,
                "ResourceLimitExceeded",
            )
            raise ProbeError("ResourceLimitExceeded", "Transport")
        self._relationships[(kind, source_ref, target_ref)] = {
            "kind": kind,
            "source_ref": source_ref,
            "target_ref": target_ref,
        }

    def _ensure_record(self, record_ref, record_type, indentation, *, defined=False):
        record = self._records_by_ref.get(record_ref)
        if record is None:
            if len(self._records) >= self._maximum_records:
                self._record_failure(
                    "record_limit_exceeded",
                    self._parser_stage,
                    "ResourceLimitExceeded",
                )
                raise ProbeError("ResourceLimitExceeded", "Transport")
            record = {
                "record_ref": record_ref,
                "record_type": record_type,
                "indentation_depth": indentation,
                "occurrences": 0,
                "definition_observed": False,
            }
            self._records_by_ref[record_ref] = record
            self._records.append(record)
        if defined:
            record["definition_observed"] = True
            record["occurrences"] += 1
        self._record_type_names.add(record_type)
        return record

    def _new_record_ref(self, record_type, body):
        tokens = body.strip().split()
        token = None
        shorthand = tokens and re.fullmatch(
            r"(?:#[0-9]+|t[0-9]+|u[0-9]+(?:a[0-9]+)?)", tokens[0], re.I
        )
        if tokens and "=" not in tokens[0] and shorthand is None:
            token = tokens[0].strip(",;{}")
        if not token:
            token = f"line-{self._line_sequence:06d}-{len(self._records) + 1:04d}"
        return self._alias(
            "record",
            token,
            namespace=f"record:{record_type}",
        )

    def _record_reference_from_value(self, value):
        match = re.match(
            r"(?P<name>ActivityRecord|ActivityStack|DisplayContent|ProcessRecord|"
            r"RootTask|RootWindowContainer|TaskFragment|TaskRecord|Task|WindowToken)"
            r"\{(?P<body>[^}\s,]+)",
            value,
        )
        if match is None:
            return None
        record_type = _RECORD_TYPES[match.group("name")]
        token = match.group("body").split()[0].strip(",;{}")
        if not token:
            return None
        record_ref = self._alias(
            "record",
            token,
            namespace=f"record:{record_type}",
        )
        self._ensure_record(record_ref, record_type, 0)
        return record_ref

    @staticmethod
    def _component_parts(value):
        normalized = value.strip()
        for wrapper in ("ComponentInfo{", "ComponentName{"):
            if normalized.startswith(wrapper):
                normalized = normalized[len(wrapper) :]
                if normalized.endswith("}"):
                    normalized = normalized[:-1]
                break
        match = _COMPONENT_PATTERN.fullmatch(normalized)
        if match is None:
            return None
        return match.group("package"), normalized

    def _line_has_target_component(self, line, headers):
        for field_match in _FIELD_PATTERN.finditer(line):
            if field_match.group("name").casefold() not in _COMPONENT_FIELD_NAMES:
                continue
            component = self._component_parts(field_match.group("value"))
            if component is not None and component[0] == self._target_package:
                return True

        for header in headers:
            for token in header.group("body").split():
                component = self._component_parts(token.strip(",;{}"))
                if component is not None and component[0] == self._target_package:
                    return True

        activity_prefix = line.lstrip().upper().startswith("ACTIVITY ")
        if activity_prefix:
            for token in line.lstrip().split()[1:]:
                component = self._component_parts(token.strip(",;{}"))
                if component is not None and component[0] == self._target_package:
                    return True
        return False

    @staticmethod
    def _identity_value(kind, value):
        normalized = value.strip("{}(),;")
        if kind == "task":
            match = re.fullmatch(r"(?:#|t)?([0-9]+)", normalized)
            return match.group(1) if match else normalized
        if kind == "user":
            handle = re.fullmatch(r"UserHandle\{([^}]+)\}", normalized, re.I)
            if handle:
                normalized = handle.group(1)
            match = re.fullmatch(r"u?([0-9]+)(?:a[0-9]+)?", normalized, re.I)
            return match.group(1) if match else normalized
        if kind == "process":
            match = re.fullmatch(r"([0-9]+):([^/]+)(?:/[^/]+)?", normalized)
            if match:
                normalized = match.group(2)
            normalized = normalized.split("/", 1)[0]
        return normalized

    def _add_field(self, record_ref, name, raw_value, *, association, value_present=None):
        if not _SAFE_FIELD_NAME_PATTERN.fullmatch(name):
            self._unrecognized_field_count += 1
            return
        if value_present is False or (
            value_present is None
            and (
                not raw_value.strip("{}(),;")
                or _EMPTY_STRUCTURED_VALUE_PATTERN.fullmatch(raw_value)
            )
        ):
            self._empty_field_value_count += 1
            return
        lower_name = name.casefold()
        field = {
            "record_ref": record_ref,
            "association": association,
            "name": name,
        }
        if record_ref is None and self._line_target_relevant:
            field["_target_line_relevant"] = True

        if lower_name in {
            "intent",
            "mintent",
            "sourcedir",
            "datadir",
            "codepath",
            "nativelibrarydir",
            "privatedir",
            "publicdir",
            "path",
            "uri",
            "datastring",
            "affinity",
            "taskaffinity",
            "rootaffinity",
        }:
            field["value_kind"] = "redacted"
            self._redacted_field_names.add(name)
        elif lower_name in {"mresumed", "resumed", "mtopresumed", "topresumed"} and raw_value.casefold() in {"true", "false"}:
            field["value_kind"] = "boolean"
            field["value"] = raw_value.casefold() == "true"
        else:
            identity_kind = None
            if lower_name in {"packagename", "mpackagename", "package", "pkg"}:
                identity_kind = "package"
            elif lower_name in _COMPONENT_FIELD_NAMES:
                identity_kind = "component"
            elif lower_name in {"userid", "muserid", "user", "u", "userhandle", "muser"}:
                identity_kind = "user"
            elif lower_name in {"taskid", "mtaskid", "task", "taskref"}:
                self._ensure_field_capacity()
                task_target = self._record_reference_from_value(raw_value)
                if task_target is not None:
                    field["value_kind"] = "record_ref"
                    field["value_ref"] = task_target
                    if record_ref is not None:
                        self._add_relationship("activity_task", record_ref, task_target)
                    self._retain_field(field)
                    return
                identity_kind = "task"
            elif lower_name in {"displayid", "mdisplayid", "display"}:
                self._ensure_field_capacity()
                display_target = self._record_reference_from_value(raw_value)
                if display_target is not None:
                    field["value_kind"] = "record_ref"
                    field["value_ref"] = display_target
                    if record_ref is not None:
                        self._add_relationship("record_display", record_ref, display_target)
                    self._retain_field(field)
                    return
                identity_kind = "display"
            elif lower_name in {"windowingmode", "mwindowingmode", "windowmode", "mode"}:
                identity_kind = "mode"
            elif lower_name in {"processname", "mprocessname", "process"}:
                identity_kind = "process"
            elif lower_name in {"pid", "processid"}:
                identity_kind = "pid"
            elif lower_name in {"uid", "launchedfromuid"}:
                identity_kind = "uid"
            elif lower_name in {"app", "processrecord"}:
                self._ensure_field_capacity()
                process_target = self._record_reference_from_value(raw_value)
                if process_target is not None:
                    field["value_kind"] = "record_ref"
                    field["value_ref"] = process_target
                    if record_ref is not None:
                        self._add_relationship("record_process", record_ref, process_target)
                    self._retain_field(field)
                    return
                identity_kind = "process"
            elif lower_name in {"mresumedactivity", "resumedactivity", "topresumedactivity", "mtopresumedactivity"}:
                self._ensure_field_capacity()
                record_target = self._record_reference_from_value(raw_value)
                if record_target is not None:
                    field["value_kind"] = "record_ref"
                    field["value_ref"] = record_target
                    if record_ref is not None:
                        relation = (
                            "top_resumed_activity"
                            if "top" in lower_name
                            else "resumed_activity"
                        )
                        self._add_relationship(relation, record_ref, record_target)
                    self._retain_field(field)
                    return
                identity_kind = "component"

            if identity_kind == "component":
                component = self._component_parts(raw_value)
                component_value = raw_value.strip("{}(),;")
                if not component_value:
                    self._empty_field_value_count += 1
                    return
                self._ensure_field_capacity()
                component_ref = self._alias("component", component_value)
                field["value_kind"] = "component_ref"
                field["value_ref"] = component_ref
                if component is not None:
                    package_ref = self._alias("package", component[0])
                    self._add_relationship("component_package", component_ref, package_ref)
                    if component[0] == self._target_package:
                        self._target_component_refs.add(component_ref)
                        self._target_package_refs.add(package_ref)
                        if record_ref is not None:
                            self._target_record_refs.add(record_ref)
                        self._line_target_relevant = True
                if record_ref is not None:
                    self._add_relationship("record_component", record_ref, component_ref)
            elif identity_kind is not None:
                if identity_kind == "mode" and raw_value.casefold() in _SAFE_ENUMS:
                    field["value_kind"] = "enum"
                    field["value"] = raw_value.casefold()
                    self._retain_field(field)
                    return
                normalized_value = self._identity_value(identity_kind, raw_value)
                prefix = {
                    "package": "package",
                    "user": "user",
                    "task": "task",
                    "display": "display",
                    "mode": "mode",
                    "process": "process",
                    "pid": "pid",
                    "uid": "uid",
                }[identity_kind]
                if not normalized_value:
                    self._empty_field_value_count += 1
                    return
                self._ensure_field_capacity()
                value_ref = self._alias(prefix, normalized_value)
                field["value_kind"] = f"{prefix}_ref"
                field["value_ref"] = value_ref
                if identity_kind == "process":
                    process_value = self._identity_value("process", raw_value)
                    package_value = process_value.split(":", 1)[0]
                    if _PACKAGE_PATTERN.fullmatch(package_value):
                        package_ref = self._alias("package", package_value)
                        self._add_relationship("process_package", value_ref, package_ref)
                if record_ref is not None:
                    record_type = self._records_by_ref.get(record_ref, {}).get("record_type")
                    relation = {
                        "user": "record_user",
                        "task": (
                            "task_identifier"
                            if record_type in {"task", "task_record"}
                            else "activity_task"
                        ),
                        "display": "record_display",
                        "mode": "record_windowing_mode",
                        "package": "record_package",
                        "process": "record_process",
                        "pid": "record_pid",
                        "uid": "record_uid",
                    }[identity_kind]
                    self._add_relationship(relation, record_ref, value_ref)
            elif raw_value.casefold() in {"true", "false"}:
                field["value_kind"] = "boolean"
                field["value"] = raw_value.casefold() == "true"
            elif raw_value.casefold() in _SAFE_ENUMS:
                field["value_kind"] = "enum"
                field["value"] = raw_value.casefold()
            else:
                # Keep equality only; arbitrary text values never enter evidence.
                normalized_value = raw_value.strip("{}(),;")
                if not normalized_value:
                    self._empty_field_value_count += 1
                    return
                self._ensure_field_capacity()
                value_ref = self._alias("value", normalized_value)
                field["value_kind"] = "value_ref"
                field["value_ref"] = value_ref

        self._retain_field(field)

    def _ensure_field_capacity(self):
        """Reject fields that would exceed the retained-field limit."""
        if len(self._fields) >= self._maximum_fields:
            self._record_failure(
                "field_limit_exceeded", self._parser_stage, "ResourceLimitExceeded"
            )
            raise ProbeError("ResourceLimitExceeded", "Transport")

    def _retain_field(self, field):
        """Keep a field label only when its value can be represented safely."""
        self._ensure_field_capacity()
        self._field_names.add(field["name"])
        self._fields.append(field)

    def _capture_shorthand_tokens(
        self, body, record_ref, record_type, *, body_line_byte_offset
    ):
        tokens = list(re.finditer(r"\S+", body))
        shorthand = tokens and re.fullmatch(
            r"(?:#[0-9]+|t[0-9]+|u[0-9]+(?:a[0-9]+)?)",
            tokens[0].group(),
            re.I,
        )
        if tokens and "=" not in tokens[0].group() and shorthand is None:
            tokens = tokens[1:]
        self._parser_stage = "field_scan"
        for token_match in tokens:
            self._active_line_byte_offset = (
                body_line_byte_offset
                + self._line_byte_offset(body, token_match.start())
            )
            token = token_match.group()
            token = token.strip(",;{}")
            if not token or "=" in token:
                continue
            if re.fullmatch(r"u[0-9]+(?:a[0-9]+)?", token, re.I):
                self._add_field(record_ref, "user", token[1:], association="attached")
            elif re.fullmatch(r"(?:#|t)[0-9]+", token, re.I):
                self._add_field(record_ref, "task", token, association="attached")
            elif self._component_parts(token) is not None:
                self._add_field(record_ref, "component", token, association="attached")
            elif record_type == "process_record":
                process_match = re.fullmatch(r"([0-9]+):(.+)", token)
                if process_match:
                    self._add_field(record_ref, "pid", process_match.group(1), association="attached")
                    self._add_field(record_ref, "processName", process_match.group(2), association="attached")

    def _consume_line(self, raw_line, *, line_start_byte_offset):
        self._active_line_number = self._lines_observed + 1
        self._line_start_byte_offset = line_start_byte_offset
        self._active_line_byte_offset = 0
        line_length = len(raw_line)
        self._max_line_bytes = max(self._max_line_bytes, line_length)
        self._parser_stage = "utf8_decode"
        try:
            line = raw_line.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            self._record_failure(
                "invalid_utf8",
                "utf8_decode",
                "IncompleteEvidence",
                line_byte_offset=exc.start,
            )
            raise ProbeError("IncompleteEvidence", "Transport") from None
        self._parser_stage = "control_validation"
        for character_offset, character in enumerate(line):
            if (ord(character) < 32 and character not in "\t\r") or ord(character) == 127:
                self._record_failure(
                    "forbidden_control_character",
                    "control_validation",
                    "IncompleteEvidence",
                    line_byte_offset=self._line_byte_offset(line, character_offset),
                )
                raise ProbeError("IncompleteEvidence", "Transport")
        self._parser_stage = "record_scan"
        for category, pattern in _FIELD_PATTERNS.items():
            if pattern.search(line):
                self._categories.add(category)
        if _TIMEOUT_PATTERN.search(line):
            self._timeout_indicator = True
            self._timeout_indicator_count += 1
        if _COMPLETION_PATTERN.search(line):
            self._completion_indicator = True
            self._completion_indicator_count += 1

        self._line_sequence += 1
        sensitive = _SENSITIVE_FIELD_PATTERN.search(line)
        structure_line = line if sensitive is None else line[: sensitive.start()]
        self._line_target_relevant = False
        sensitive_value_present = False
        if sensitive is not None:
            field_name = sensitive.group("name")
            sensitive_value_present = self._sensitive_value_present(line, sensitive)
            self._intent_content_observed |= (
                field_name.casefold() in {"intent", "mintent"}
                and sensitive_value_present
            )
            if sensitive_value_present:
                self._sensitive_tail_truncated_count += 1

        indentation = len(structure_line) - len(structure_line.lstrip(" \t"))
        headers = list(_RECORD_PATTERN.finditer(structure_line))
        display_header = _DISPLAY_HEADER_PATTERN.fullmatch(
            structure_line[indentation:]
        )
        self._line_target_relevant = self._line_has_target_component(
            structure_line, headers
        )
        record_refs = []
        if display_header is not None:
            self._parser_stage = "record_scan"
            self._active_line_byte_offset = self._line_byte_offset(
                structure_line, indentation
            )
            while self._record_stack and self._record_stack[-1][0] >= indentation:
                self._record_stack.pop()
            display_id = (
                display_header.group("activity_display_id")
                or display_header.group("window_display_id")
            )
            record_ref = self._alias(
                "record",
                f"{display_id}:{self._line_sequence}",
                namespace="record:display_content",
            )
            if self._record_stack:
                self._add_relationship(
                    "layout_parent", self._record_stack[-1][1], record_ref
                )
            self._ensure_record(
                record_ref, "display_content", indentation, defined=True
            )
            self._record_stack.append((indentation, record_ref))
            record_refs.append((record_ref, "display_content"))
            self._add_field(
                record_ref,
                "displayId",
                display_id,
                association="attached",
            )
            root_task_count = display_header.group("root_task_count")
            if root_task_count is not None:
                self._add_field(
                    record_ref,
                    "rootTaskCount",
                    root_task_count,
                    association="attached",
                )
        for header in headers:
            self._parser_stage = "record_scan"
            self._active_line_byte_offset = self._line_byte_offset(
                structure_line, header.start()
            )
            before_header = structure_line[: header.start()]
            if re.search(
                r"(?:mResumedActivity|resumedActivity|topResumedActivity|"
                r"mTopResumedActivity|app|processRecord|taskId|mTaskId|task|"
                r"taskRef|displayId|mDisplayId|display)\s*[=:]\s*\Z",
                before_header,
                re.I,
            ):
                continue
            record_type = _RECORD_TYPES[header.group("name")]
            record_ref = self._new_record_ref(record_type, header.group("body"))
            while self._record_stack and self._record_stack[-1][0] >= indentation:
                self._record_stack.pop()
            if self._record_stack:
                self._add_relationship(
                    "layout_parent", self._record_stack[-1][1], record_ref
                )
            self._ensure_record(record_ref, record_type, indentation, defined=True)
            self._record_stack.append((indentation, record_ref))
            record_refs.append((record_ref, record_type))
            self._capture_shorthand_tokens(
                header.group("body"),
                record_ref,
                record_type,
                body_line_byte_offset=self._line_byte_offset(
                    structure_line, header.start("body")
                ),
            )

        if not record_refs:
            self._parser_stage = "field_scan"
            for token_match in re.finditer(r"\S+", structure_line):
                self._active_line_byte_offset = self._line_byte_offset(
                    structure_line, token_match.start()
                )
                token = token_match.group()
                component = self._component_parts(token.strip(",;{}"))
                if component is not None and component[0] == self._target_package:
                    self._add_field(
                        None,
                        "component",
                        token.strip(",;{}"),
                        association="unscoped",
                    )
                    break

        field_matches = list(_FIELD_PATTERN.finditer(structure_line))
        self._parser_stage = "field_scan"
        parsed_field_spans = {
            (item.start("name"), item.end("name")) for item in field_matches
        }
        for candidate in _FIELD_CANDIDATE_PATTERN.finditer(structure_line):
            self._active_line_byte_offset = self._line_byte_offset(
                structure_line, candidate.start()
            )
            span = (candidate.start("name"), candidate.end("name"))
            if (
                span not in parsed_field_spans
                or not _SAFE_FIELD_NAME_PATTERN.fullmatch(candidate.group("name"))
            ):
                self._unrecognized_field_count += 1
        if len(record_refs) == 1:
            associated_record, association = record_refs[0][0], "attached"
        elif len(record_refs) > 1:
            associated_record, association = None, "ambiguous"
        elif self._record_stack and indentation > self._record_stack[-1][0]:
            associated_record, association = self._record_stack[-1][1], "attached"
        else:
            associated_record, association = None, "unscoped"
        for field_match in field_matches:
            self._active_line_byte_offset = self._line_byte_offset(
                structure_line, field_match.start()
            )
            self._add_field(
                associated_record,
                field_match.group("name"),
                field_match.group("value"),
                association=association,
            )
        if sensitive is not None:
            self._active_line_byte_offset = self._line_byte_offset(
                structure_line, sensitive.start()
            )
            self._add_field(
                associated_record,
                sensitive.group("name"),
                "",
                association=association,
                value_present=sensitive_value_present,
            )
        if not headers and not field_matches and sensitive is None and not (
            _TIMEOUT_PATTERN.search(line) or _COMPLETION_PATTERN.search(line)
        ):
            self._unclassified_line_count += 1
        self._lines_observed += 1

    def projection_candidates(self, *, record_types, field_names, relationship_kinds):
        """Return copied parser records that match a projection's allowlists."""
        record_types = set(record_types)
        field_names = set(field_names)
        relationship_kinds = set(relationship_kinds)
        records = [
            dict(item)
            for item in self._records
            if item["record_type"] in record_types
        ]
        record_refs = {item["record_ref"] for item in records}
        fields = [
            {
                key: value
                for key, value in item.items()
                if key != "_target_line_relevant"
            }
            for item in self._fields
            if item.get("record_ref") in record_refs
            and item.get("name") in field_names
        ]
        relationships = [
            dict(item)
            for item in self._relationships.values()
            if item["kind"] in relationship_kinds
            and item["source_ref"] in record_refs
            and item["target_ref"] in record_refs
        ]
        return records, fields, relationships

    def _target_structure(self):
        records_by_ref = {item["record_ref"]: item for item in self._records}
        related_records = self._target_record_refs.intersection(records_by_ref)
        changed = True
        while changed:
            changed = False
            for relation in self._relationships.values():
                source = relation["source_ref"]
                target = relation["target_ref"]
                if relation["kind"] == "layout_parent" and target in related_records:
                    if (
                        source in records_by_ref
                        and records_by_ref[source]["record_type"] in _LAYOUT_PARENT_TYPES
                        and source not in related_records
                    ):
                        related_records.add(source)
                        changed = True
                elif relation["kind"] in _RECORD_CONTEXT_TYPES:
                    expected_types = _RECORD_CONTEXT_TYPES[relation["kind"]]
                    if (
                        source in related_records
                        and target in records_by_ref
                        and records_by_ref[target]["record_type"] in expected_types
                    ):
                        if target not in related_records:
                            related_records.add(target)
                            changed = True
                elif relation["kind"] in _RESUMED_RELATIONSHIPS:
                    if (
                        target in self._target_record_refs
                        and source in records_by_ref
                        and records_by_ref[source]["record_type"] in _RESUMED_SOURCE_TYPES
                    ):
                        if source not in related_records:
                            related_records.add(source)
                            changed = True
            for field in self._fields:
                if (
                    field.get("record_ref") in related_records
                    and field.get("value_kind") == "record_ref"
                    and field.get("value_ref") in self._target_record_refs
                    and field.get("value_ref") in records_by_ref
                    and field["value_ref"] not in related_records
                ):
                    related_records.add(field["value_ref"])
                    changed = True

        records = [
            dict(item) for item in self._records if item["record_ref"] in related_records
        ]
        fields = []
        for item in self._fields:
            record_ref = item.get("record_ref")
            target_record_reference = (
                item.get("value_kind") == "record_ref"
                and item.get("value_ref") in self._target_record_refs
                and item.get("value_ref") in records_by_ref
            )
            target_line = item.get("_target_line_relevant") is True
            if record_ref not in related_records and not target_record_reference and not target_line:
                continue
            kind = item["value_kind"]
            value_ref = item.get("value_ref")
            if kind == "value_ref":
                safe_value_field = (
                    record_ref in related_records
                    and any(
                        category != "activity_records"
                        and pattern.search(f"{item['name']}=")
                        for category, pattern in _FIELD_PATTERNS.items()
                    )
                )
                if not safe_value_field:
                    continue
            if kind == "package_ref" and value_ref not in self._target_package_refs:
                continue
            if kind == "component_ref" and value_ref not in self._target_component_refs:
                continue
            if kind == "record_ref" and value_ref not in related_records:
                continue
            if record_ref is not None and record_ref not in related_records:
                continue
            if record_ref is None and not target_record_reference:
                if not target_line:
                    continue
                if not (
                    kind == "component_ref"
                    and value_ref in self._target_component_refs
                ) and kind != "redacted":
                    fields.append(
                        {
                            "record_ref": None,
                            "association": item["association"],
                            "name": item["name"],
                            "value_kind": "redacted",
                        }
                    )
                    continue
            fields.append(
                {key: value for key, value in item.items() if key != "_target_line_relevant"}
            )

        retained_component_refs = {
            item["value_ref"]
            for item in fields
            if item["value_kind"] == "component_ref"
        }
        used_references = set(related_records)
        for item in fields:
            if item.get("record_ref") is not None:
                used_references.add(item["record_ref"])
            if item.get("value_ref") is not None:
                used_references.add(item["value_ref"])
        used_references.update(self._target_package_refs)
        relationships = []
        for item in self._relationships.values():
            if item["kind"] == "component_package":
                allowed = (
                    item["source_ref"] in retained_component_refs
                    and item["target_ref"] in self._target_package_refs
                )
            elif item["kind"] == "record_component":
                allowed = (
                    item["source_ref"] in related_records
                    and item["target_ref"] in retained_component_refs
                )
            elif item["kind"] == "record_package":
                allowed = (
                    item["source_ref"] in related_records
                    and item["target_ref"] in self._target_package_refs
                )
            elif item["kind"] == "process_package":
                allowed = (
                    item["source_ref"] in used_references
                    and item["target_ref"] in self._target_package_refs
                )
            elif item["kind"] == "layout_parent":
                allowed = (
                    item["source_ref"] in related_records
                    and item["target_ref"] in related_records
                )
            else:
                allowed = (
                    item["source_ref"] in used_references
                    and item["target_ref"] in used_references
                )
            if allowed:
                relationships.append(dict(item))

        aliases = {}
        alias_counts = {}

        def remap(reference):
            if reference not in aliases:
                prefix = reference.split("-", 1)[0]
                alias_counts[prefix] = alias_counts.get(prefix, 0) + 1
                aliases[reference] = f"{prefix}-{alias_counts[prefix]:04d}"
            return aliases[reference]

        for item in records:
            item["record_ref"] = remap(item["record_ref"])
        for item in fields:
            if item["record_ref"] is not None:
                item["record_ref"] = remap(item["record_ref"])
            if item.get("value_ref") is not None:
                item["value_ref"] = remap(item["value_ref"])
        for item in relationships:
            item["source_ref"] = remap(item["source_ref"])
            item["target_ref"] = remap(item["target_ref"])

        records.sort(key=lambda item: item["record_ref"])
        fields.sort(
            key=lambda item: (
                item["record_ref"] or "",
                item["name"],
                item["association"],
                item["value_kind"],
                item.get("value_ref", str(item.get("value", ""))),
            )
        )
        relationships.sort(
            key=lambda item: (item["kind"], item["source_ref"], item["target_ref"])
        )
        record_types = sorted({item["record_type"] for item in records})
        field_names = sorted({item["name"] for item in fields})
        redacted_names = sorted(
            {item["name"] for item in fields if item["value_kind"] == "redacted"}
        )
        categories = derive_available_field_categories(record_types, field_names)
        structure = {
            "record_type_names": record_types,
            "field_names": field_names,
            "records": records,
            "fields": fields,
            "relationships": relationships,
            "unclassified_line_count": self._unclassified_line_count,
            "unrecognized_field_count": self._unrecognized_field_count,
            # Count empty values without retaining their names or contents.
            "empty_field_value_count": self._empty_field_value_count,
            "sensitive_tail_truncated_count": self._sensitive_tail_truncated_count,
        }
        intent_observed = any(
            name.casefold() in {"intent", "mintent"} for name in redacted_names
        )
        target_component_observed = bool(self._target_component_refs)
        return (
            structure,
            categories,
            redacted_names,
            intent_observed,
            target_component_observed,
        )

    def _clear_structure_state(self):
        self._categories.clear()
        self._redacted_field_names.clear()
        self._field_names.clear()
        self._record_type_names.clear()
        self._records.clear()
        self._records_by_ref.clear()
        self._fields.clear()
        self._relationships.clear()
        self._record_stack.clear()
        self._target_record_refs.clear()
        self._target_package_refs.clear()
        self._target_component_refs.clear()
        self._line_target_relevant = False
        self._clear_aliases()

    def _consume_buffered_line(self):
        """Parse one buffered line and clear parser state if it fails."""
        raw_line = bytes(self._line)
        self._line.clear()
        if raw_line.endswith(b"\r"):
            raw_line = raw_line[:-1]
        try:
            self._consume_line(
                raw_line,
                line_start_byte_offset=self._line_start_byte_offset,
            )
        except ProbeError as exc:
            self._record_failure("parser_rejection", self._parser_stage, exc.code)
            self.discard()
            raise

    def feed(self, chunk):
        if self._finished or type(chunk) is not bytes:
            self._parser_stage = "input_validation"
            self._active_line_number = None
            self._active_line_byte_offset = None
            self._record_failure(
                "parser_rejection",
                "input_validation",
                "IncompleteEvidence",
            )
            self.discard()
            raise ProbeError("IncompleteEvidence", "Transport")
        chunk_start_byte_offset = self._total_bytes_fed
        self._total_bytes_fed += len(chunk)
        offset = 0
        while offset < len(chunk):
            newline = chunk.find(b"\n", offset)
            end = len(chunk) if newline < 0 else newline
            piece = chunk[offset:end]
            if len(self._line) + len(piece) > self._maximum_line_bytes:
                self._parser_stage = "line_accumulation"
                self._active_line_number = self._lines_observed + 1
                self._active_line_byte_offset = self._maximum_line_bytes
                self._record_failure(
                    "line_length_exceeded",
                    "line_accumulation",
                    "ResourceLimitExceeded",
                    line_byte_offset=self._maximum_line_bytes,
                    absolute_byte_offset=(
                        self._line_start_byte_offset + self._maximum_line_bytes
                    ),
                )
                self.discard()
                raise ProbeError("ResourceLimitExceeded", "Transport")
            self._line.extend(piece)
            if newline < 0:
                return
            self._consume_buffered_line()
            offset = newline + 1
            self._line_start_byte_offset = chunk_start_byte_offset + offset

    def finish(self, *, preserve_structure=False):
        """Finish parsing and retain fields only while a caller builds a projection."""
        if self._finished:
            self._parser_stage = "finish"
            self._active_line_number = None
            self._active_line_byte_offset = None
            self._record_failure("parser_rejection", "finish", "IncompleteEvidence")
            raise ProbeError("IncompleteEvidence", "Transport")
        if len(self._line) > self._maximum_line_bytes:
            self._parser_stage = "line_accumulation"
            self._active_line_number = self._lines_observed + 1
            self._active_line_byte_offset = self._maximum_line_bytes
            self._record_failure(
                "line_length_exceeded",
                "line_accumulation",
                "ResourceLimitExceeded",
                line_byte_offset=self._maximum_line_bytes,
                absolute_byte_offset=self._line_start_byte_offset + self._maximum_line_bytes,
            )
            self.discard()
            raise ProbeError("ResourceLimitExceeded", "Transport")
        if self._line:
            self._consume_buffered_line()
        self._parser_stage = "target_projection"
        self._active_line_number = None
        self._active_line_byte_offset = None
        try:
            (
                structure,
                categories,
                redacted_names,
                intent_observed,
                target_component_observed,
            ) = self._target_structure()
        except ProbeError as exc:
            self._record_failure(
                "parser_rejection", "target_projection", exc.code
            )
            self.discard()
            raise
        self._finished = True
        result = {
            "lines_observed": self._lines_observed,
            "max_line_bytes": self._max_line_bytes,
            "available_field_categories": categories,
            "timeout_indicator_observed": self._timeout_indicator,
            "timeout_indicator_count": self._timeout_indicator_count,
            "completion_indicator_observed": self._completion_indicator,
            "completion_indicator_count": self._completion_indicator_count,
            "intent_content_observed": intent_observed,
            "redacted_field_names": redacted_names,
            "target_component_observed": target_component_observed,
            "eof_observed": True,
            "completion_verified": False,
            "target_binding_established": False,
            "task_continuity_established": False,
            "structure": structure,
        }
        if not preserve_structure:
            self._clear_structure_state()
        return result

    def _clear_aliases(self):
        self._aliases.clear()
        self._alias_counts.clear()
        self._alias_key = b""

    def discard(self):
        self._line.clear()
        self._lines_observed = 0
        self._max_line_bytes = 0
        self._timeout_indicator = False
        self._timeout_indicator_count = 0
        self._completion_indicator = False
        self._completion_indicator_count = 0
        self._intent_content_observed = False
        self._unclassified_line_count = 0
        self._unrecognized_field_count = 0
        self._empty_field_value_count = 0
        self._sensitive_tail_truncated_count = 0
        self._clear_structure_state()
        self._total_bytes_fed = 0
        self._line_start_byte_offset = 0
        self._active_line_number = None
        self._active_line_byte_offset = None
        self._parser_stage = "input_validation"
        self._finished = True
        return None


def _utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _source_file_hashes():
    hashes = {}
    for name in _SOURCE_FILE_NAMES:
        path = Path(__file__).with_name(name)
        try:
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError:
            hashes[name] = None
    return hashes


def _repository_head_commit():
    repository_root = Path(__file__).resolve().parents[2]
    try:
        completed = subprocess.run(
            ["git", "-C", str(repository_root), "rev-parse", "HEAD"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            shell=False,
            close_fds=True,
            timeout=1.0,
            check=False,
        )
        commit = completed.stdout.decode("ascii", errors="strict").strip()
        if completed.returncode != 0 or _HEX_COMMIT_PATTERN.fullmatch(commit) is None:
            commit = None
    except Exception:
        commit = None
    return commit


def _source_identity():
    return {
        "approved_baseline_commit": APPROVED_BASELINE_COMMIT,
        "source_commit": _repository_head_commit(),
        "source_snapshot": "working_tree",
        "source_file_sha256": _source_file_hashes(),
    }


def _valid_source_identity(source_identity):
    if not _valid_recorded_source_identity(source_identity):
        return False
    source_commit = source_identity.get("source_commit")
    current_commit = _repository_head_commit()
    return (
        type(source_commit) is str
        and _HEX_COMMIT_PATTERN.fullmatch(source_commit) is not None
        and current_commit is not None
        and source_commit == current_commit
        and dict(source_identity["source_file_sha256"]) == _source_file_hashes()
    )


def _valid_recorded_source_identity(source_identity):
    if not isinstance(source_identity, Mapping):
        return False
    common = {"approved_baseline_commit", "source_snapshot", "source_file_sha256"}
    allowed = common | {"source_commit"}
    if set(source_identity) not in (common, allowed):
        return False
    if (
        source_identity.get("approved_baseline_commit") != APPROVED_BASELINE_COMMIT
        or source_identity.get("source_snapshot") != "working_tree"
    ):
        return False
    if "source_commit" in source_identity and (
        type(source_identity["source_commit"]) is not str
        or _HEX_COMMIT_PATTERN.fullmatch(source_identity["source_commit"]) is None
    ):
        return False
    hashes = source_identity.get("source_file_sha256")
    previous_source_files = {
        "adb_forward.py",
        "readiness_probe_session.py",
        "q7_exploratory_acquisition.py",
    }
    intermediate_source_files = previous_source_files | {"packaging.py"}
    pre_window_source_files = intermediate_source_files | {"readiness_probe_artifact.py"}
    current_source_files = set(_SOURCE_FILE_NAMES)
    if not isinstance(hashes, Mapping) or set(hashes) not in (
        previous_source_files,
        intermediate_source_files,
        pre_window_source_files,
        current_source_files,
    ):
        return False
    return all(
        type(name) is str
        and type(digest) is str
        and _HEX_SHA256_PATTERN.fullmatch(digest) is not None
        for name, digest in hashes.items()
    )


def _run_q7_observation_for_serial(
    target,
    *,
    target_ref=TARGET_REFERENCE,
    source_identity=None,
    runner=None,
    utc_clock=None,
    subject_package=_TARGET_PACKAGE,
    source_command="activity_activities",
):
    """Run once and return sanitized metadata; parser rejection leaves the input source unresolved."""
    if type(target_ref) is not str or _TARGET_REFERENCE_PATTERN.fullmatch(target_ref) is None:
        raise ProbeError("MalformedRequest", "Transport")
    if type(subject_package) is not str or subject_package not in _Q7_SUBJECT_PACKAGES:
        raise ProbeError("MalformedRequest", "Transport")
    if type(source_command) is not str or source_command not in (
        "activity_activities",
        "window_displays",
    ):
        raise ProbeError("MalformedRequest", "Transport")
    source_identity = _source_identity() if source_identity is None else source_identity
    if not _valid_source_identity(source_identity):
        raise ProbeError("IncompleteEvidence", "Transport")
    runner = _AdbCommandRunner() if runner is None else runner
    utc_clock = _utc_now if utc_clock is None else utc_clock
    try:
        acquired_at = utc_clock()
        if type(acquired_at) is not str or not acquired_at.endswith("Z"):
            raise ValueError
    except Exception:
        raise ProbeError("IncompleteEvidence", "Transport") from None

    if source_command == "window_displays":
        from .q7_window_display_projection import Q7WindowDisplayStructuralFilter

        parser = Q7WindowDisplayStructuralFilter(
            parser=Q7StructuralFilter(target_package=subject_package),
            category_deriver=derive_available_field_categories,
        )
        run_command = runner.run_window_displays
        schema = _WINDOW_DISPLAY_EXPLORATORY_SCHEMA
    else:
        parser = Q7StructuralFilter(target_package=subject_package)
        run_command = runner.run_q7
        schema = _Q7_EXPLORATORY_SCHEMA
    filter_error_code = None

    def consume_output(chunk):
        nonlocal filter_error_code
        try:
            parser.feed(chunk)
        except ProbeError as exc:
            filter_error_code = exc.code
            parser.discard()
            raise

    try:
        execution = run_command(target, consume_output)
    except Exception:
        parser.discard()
        raise ProbeError("IncompleteEvidence", "Transport") from None
    try:
        finished_at = utc_clock()
        if type(finished_at) is not str or not finished_at.endswith("Z"):
            raise ValueError
    except Exception:
        parser.discard()
        finished_at = None

    record = {
        "schema": schema,
        "target_ref": target_ref,
        "subject_package": subject_package,
        "acquisition_started_at_utc": acquired_at,
        "acquisition_finished_at_utc": finished_at,
            "duration_seconds": execution.finished_monotonic - execution.started_monotonic,
            "acquisition_limits": dict(_RECORDED_LIMITS),
        "command_count": execution.command_count,
        "started_monotonic": execution.started_monotonic,
        "finished_monotonic": execution.finished_monotonic,
        "stdout_bytes": execution.stdout_bytes,
        "total_output_bytes": execution.total_output_bytes,
        "exit_code": execution.exit_code,
        "cleanup_complete": execution.cleanup_complete,
        "process_classification": execution.classification,
        "qualification_assertions_passed": False,
        "source_identity": {
            "approved_baseline_commit": source_identity["approved_baseline_commit"],
            "source_commit": source_identity["source_commit"],
            "source_snapshot": source_identity["source_snapshot"],
            "source_file_sha256": dict(source_identity["source_file_sha256"]),
        },
        "limitations": list(_LIMITATIONS),
    }
    parser_error = parser.failure_diagnostic
    if parser_error is not None:
        record["parser_error"] = parser_error
    if not execution.cleanup_complete:
        record["classification"] = "cleanup_unverified"
        record["usable_exploratory_observation"] = False
        parser.discard()
        return record
    if filter_error_code is not None:
        record["classification"] = (
            "resource_limit"
            if filter_error_code == "ResourceLimitExceeded"
            else "parser_rejection"
        )
        record["usable_exploratory_observation"] = False
        parser.discard()
        return record
    if execution.classification != "exit_zero":
        record["classification"] = execution.classification
        record["usable_exploratory_observation"] = False
        parser.discard()
        return record

    try:
        observation = parser.finish()
    except ProbeError as exc:
        parser_error = parser.failure_diagnostic
        if parser_error is not None:
            record["parser_error"] = parser_error
        parser.discard()
        record["classification"] = (
            "resource_limit" if exc.code == "ResourceLimitExceeded" else "parser_rejection"
        )
        record["usable_exploratory_observation"] = False
        return record
    record["observation"] = observation
    if observation["timeout_indicator_observed"]:
        record["classification"] = "device_timeout_indicator"
        record["usable_exploratory_observation"] = False
    else:
        record["classification"] = "exploratory_only"
        record["usable_exploratory_observation"] = True
    if finished_at is None:
        record["classification"] = "time_record_unavailable"
        record["usable_exploratory_observation"] = False
    return record


def _open_verified_directory(directory):
    path = Path(directory)
    if not path.is_absolute() or ".." in path.parts:
        raise ProbeError("UnauthorizedPeer", "Transport")
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    current_fd = os.open(path.anchor, directory_flags)
    try:
        for component in path.parts[1:]:
            next_fd = os.open(
                component,
                directory_flags | nofollow,
                dir_fd=current_fd,
            )
            os.close(current_fd)
            current_fd = next_fd
        metadata = os.fstat(current_fd)
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or stat.S_IMODE(metadata.st_mode) != 0o700
        ):
            raise ProbeError("UnauthorizedPeer", "Transport")
        return current_fd
    except Exception:
        os.close(current_fd)
        raise


def _valid_identity_preflight(record):
    if not isinstance(record, Mapping):
        return False
    if (
        record.get("schema") != "argus-issue-74-identity-preflight-outcome-v1"
        or record.get("target_reference") != TARGET_REFERENCE
        or record.get("target_model") != "KONKR Pocket Advance"
        or record.get("classification") != "PASS"
        or record.get("scope")
        != "bounded read-only identity preflight only; no B1 authority"
        or record.get("retention_days_per_attempt") != 180
        or record.get("storage_budget_mb") != 100
        or record.get("external_receipt_required_for_this_attempt") is not False
        or record.get("outcome_receipt_created") is not False
    ):
        return False
    serial = record.get("selected_serial_private")
    if not _valid_target(serial):
        return False
    acquisition = record.get("acquisition")
    if not isinstance(acquisition, Mapping):
        return False
    commands = acquisition.get("commands")
    if (
        not isinstance(commands, Mapping)
        or dict(commands) != {"fingerprint": 1, "get_state": 1, "unexpected": 0}
        or acquisition.get("validated_get_state") != "device"
        or acquisition.get("returned_target_binding_matches") is not True
        or acquisition.get("deadline_met") is not True
        or acquisition.get("failure_code") is not None
        or acquisition.get("retries") != 0
        or acquisition.get("raw_stdout_retained") is not False
        or acquisition.get("stderr_retained") is not False
        or type(acquisition.get("fingerprint_observed_private")) is not str
        or _BUILD_PATTERN.fullmatch(acquisition["fingerprint_observed_private"]) is None
    ):
        return False
    source = record.get("source")
    if not isinstance(source, Mapping):
        return False
    if (
        source.get("repository") != "whatobiplays/Argus-ROM-Toolkit"
        or source.get("reviewed_merge_commit") != APPROVED_BASELINE_COMMIT
        or source.get("working_tree_clean") is not True
        or source.get("adapter_path") != "scripts/android_qualification/adb_forward.py"
        or source.get("procedure_path") != "docs/qualification/android-readiness-probe.md"
        or _HEX_COMMIT_PATTERN.fullmatch(source.get("executed_revision", "")) is None
        or _HEX_SHA256_PATTERN.fullmatch(source.get("adapter_sha256", "")) is None
        or _HEX_SHA256_PATTERN.fullmatch(source.get("procedure_sha256", "")) is None
    ):
        return False
    return True


def _private_identity_serial(outcomes_directory):
    """Read one matching, owner-private identity record without exposing it."""
    try:
        directory_fd = _open_verified_directory(outcomes_directory)
    except ProbeError:
        raise
    except Exception:
        raise ProbeError("UnauthorizedPeer", "Transport") from None
    candidates = []
    try:
        names = os.listdir(directory_fd)
        if len(names) > _evidence_storage.MAX_OUTCOMES_ENTRIES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        for name in names:
            try:
                metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except OSError:
                raise ProbeError("IncompleteEvidence", "Transport") from None
            if stat.S_ISLNK(metadata.st_mode):
                raise ProbeError("UnauthorizedPeer", "Transport")
            if not stat.S_ISREG(metadata.st_mode) or not name.lower().endswith(".json"):
                continue
            if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) != 0o600:
                raise ProbeError("UnauthorizedPeer", "Transport")
            if metadata.st_size < 0 or metadata.st_size > 64 * 1024:
                continue
            try:
                file_fd = os.open(
                    name,
                    os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                    dir_fd=directory_fd,
                )
            except OSError:
                raise ProbeError("IncompleteEvidence", "Transport") from None
            try:
                opened = os.fstat(file_fd)
                if (
                    not stat.S_ISREG(opened.st_mode)
                    or opened.st_uid != os.geteuid()
                    or stat.S_IMODE(opened.st_mode) != 0o600
                    or opened.st_size != metadata.st_size
                ):
                    raise ProbeError("UnauthorizedPeer", "Transport")
                raw = bytearray()
                while len(raw) <= 64 * 1024:
                    chunk = os.read(file_fd, min(4096, 64 * 1024 + 1 - len(raw)))
                    if not chunk:
                        break
                    raw.extend(chunk)
                if len(raw) > 64 * 1024:
                    continue
            finally:
                os.close(file_fd)
            try:
                record = json.loads(raw.decode("utf-8", errors="strict"))
            except Exception:
                if TARGET_REFERENCE.encode("ascii") in raw:
                    raise ProbeError("IncompleteEvidence", "Transport") from None
                continue
            if (
                isinstance(record, Mapping)
                and record.get("schema") == "argus-issue-74-identity-preflight-outcome-v1"
                and record.get("target_reference") == TARGET_REFERENCE
            ):
                candidates.append(record)
    except ProbeError:
        raise
    except Exception:
        raise ProbeError("IncompleteEvidence", "Transport") from None
    finally:
        os.close(directory_fd)
    if len(candidates) != 1 or not _valid_identity_preflight(candidates[0]):
        raise ProbeError("IntegrityConflict", "Transport")
    return candidates[0]["selected_serial_private"]


def _run_q7_from_identity_outcome(
    outcomes_directory,
    *,
    source_identity,
    runner,
    utc_clock,
    subject_package=_TARGET_PACKAGE,
    source_command="activity_activities",
):
    """Run one observation using values validated by the public entry point."""
    serial = _private_identity_serial(outcomes_directory)
    record = _run_q7_observation_for_serial(
        serial,
        target_ref=TARGET_REFERENCE,
        source_identity=source_identity,
        runner=runner,
        utc_clock=utc_clock,
        subject_package=subject_package,
        source_command=source_command,
    )
    record["identity_preflight_record_bound"] = True
    _write_sanitized_outcome(outcomes_directory, record)
    return record


def run_q7_from_identity_outcome(outcomes_directory):
    """Run once from the pinned source with the serial in its private outcome."""
    source_identity = _source_identity()
    if not _valid_source_identity(source_identity):
        raise ProbeError("IncompleteEvidence", "Transport")
    return _run_q7_from_identity_outcome(
        outcomes_directory,
        source_identity=source_identity,
        runner=_AdbCommandRunner(),
        utc_clock=_utc_now,
    )


def run_readiness_activity_snapshot_from_identity_outcome(outcomes_directory):
    """Capture a private exploratory snapshot for the installed Readiness app."""
    return _run_q7_from_identity_outcome(
        outcomes_directory,
        source_identity=_source_identity(),
        runner=_AdbCommandRunner(),
        utc_clock=_utc_now,
        subject_package=_READINESS_PROBE_PACKAGE,
    )


def run_readiness_window_display_snapshot_from_identity_outcome(outcomes_directory):
    """Capture only the Readiness package's display and task structure."""
    return _run_q7_from_identity_outcome(
        outcomes_directory,
        source_identity=_source_identity(),
        runner=_AdbCommandRunner(),
        utc_clock=_utc_now,
        subject_package=_READINESS_PROBE_PACKAGE,
        source_command="window_displays",
    )


def _valid_reference(value):
    return type(value) is str and re.fullmatch(
        r"(?:record|package|component|task|user|display|process|pid|uid|value|mode)-[0-9]{4,5}",
        value,
    ) is not None


def _validate_structure(structure):
    expected = {
        "record_type_names",
        "field_names",
        "records",
        "fields",
        "relationships",
        "unclassified_line_count",
        "unrecognized_field_count",
        "empty_field_value_count",
        "sensitive_tail_truncated_count",
    }
    if not isinstance(structure, Mapping) or set(structure) != expected:
        raise ProbeError("MalformedRequest", "Transport")
    record_types = structure["record_type_names"]
    valid_record_types = set(_RECORD_TYPES.values())
    if (
        type(record_types) is not list
        or len(record_types) > len(valid_record_types)
        or any(type(item) is not str or item not in valid_record_types for item in record_types)
        or record_types != sorted(set(record_types))
    ):
        raise ProbeError("MalformedRequest", "Transport")
    field_names = structure["field_names"]
    if (
        type(field_names) is not list
        or len(field_names) > _MAX_Q7_STRUCTURAL_FIELDS
        or any(
            type(item) is not str or not _SAFE_FIELD_NAME_PATTERN.fullmatch(item)
            for item in field_names
        )
        or field_names != sorted(set(field_names))
    ):
        raise ProbeError("MalformedRequest", "Transport")
    records = structure["records"]
    if type(records) is not list or len(records) > _MAX_Q7_STRUCTURAL_RECORDS:
        raise ProbeError("MalformedRequest", "Transport")
    record_refs = set()
    for item in records:
        if not isinstance(item, Mapping) or set(item) != {
            "record_ref",
            "record_type",
            "indentation_depth",
            "occurrences",
            "definition_observed",
        }:
            raise ProbeError("MalformedRequest", "Transport")
        if (
            not _valid_reference(item["record_ref"])
            or item["record_ref"].split("-", 1)[0] != "record"
            or item["record_type"] not in valid_record_types
            or type(item["indentation_depth"]) is not int
            or not 0 <= item["indentation_depth"] <= _MAX_Q7_LINE_LENGTH
            or type(item["occurrences"]) is not int
            or item["occurrences"] < 0
            or type(item["definition_observed"]) is not bool
            or item["definition_observed"] != (item["occurrences"] > 0)
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if item["record_ref"] in record_refs:
            raise ProbeError("MalformedRequest", "Transport")
        record_refs.add(item["record_ref"])

    fields = structure["fields"]
    if type(fields) is not list or len(fields) > _MAX_Q7_STRUCTURAL_FIELDS:
        raise ProbeError("MalformedRequest", "Transport")
    reference_kinds = {
        "package_ref",
        "component_ref",
        "user_ref",
        "task_ref",
        "display_ref",
        "process_ref",
        "pid_ref",
        "uid_ref",
        "record_ref",
        "value_ref",
        "mode_ref",
    }
    allowed_value_kinds = reference_kinds | {"boolean", "enum", "redacted"}
    for item in fields:
        if not isinstance(item, Mapping):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            item.get("record_ref") is not None
            and (not _valid_reference(item["record_ref"]) or item["record_ref"] not in record_refs)
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            item.get("association") not in {"attached", "unscoped", "ambiguous"}
            or type(item.get("name")) is not str
            or not _SAFE_FIELD_NAME_PATTERN.fullmatch(item["name"])
            or item["name"] not in field_names
            or item.get("value_kind") not in allowed_value_kinds
        ):
            raise ProbeError("MalformedRequest", "Transport")
        kind = item["value_kind"]
        if kind in reference_kinds:
            if set(item) != {"record_ref", "association", "name", "value_kind", "value_ref"}:
                raise ProbeError("MalformedRequest", "Transport")
            if not _valid_reference(item["value_ref"]):
                raise ProbeError("MalformedRequest", "Transport")
        elif kind == "boolean":
            if set(item) != {"record_ref", "association", "name", "value_kind", "value"}:
                raise ProbeError("MalformedRequest", "Transport")
            if type(item["value"]) is not bool:
                raise ProbeError("MalformedRequest", "Transport")
        elif kind == "enum":
            if set(item) != {"record_ref", "association", "name", "value_kind", "value"}:
                raise ProbeError("MalformedRequest", "Transport")
            if type(item["value"]) is not str or item["value"] not in _SAFE_ENUMS:
                raise ProbeError("MalformedRequest", "Transport")
        elif set(item) != {"record_ref", "association", "name", "value_kind"}:
            raise ProbeError("MalformedRequest", "Transport")

    relationships = structure["relationships"]
    allowed_relationships = {
        "layout_parent",
        "component_package",
        "record_component",
        "record_user",
        "activity_task",
        "record_display",
        "record_package",
        "record_process",
        "record_pid",
        "record_uid",
        "process_package",
        "record_windowing_mode",
        "task_identifier",
        "top_resumed_activity",
        "resumed_activity",
    }
    if type(relationships) is not list or len(relationships) > _MAX_Q7_STRUCTURAL_RELATIONSHIPS:
        raise ProbeError("MalformedRequest", "Transport")
    relationship_keys = []
    for item in relationships:
        if (
            not isinstance(item, Mapping)
            or set(item) != {"kind", "source_ref", "target_ref"}
            or item["kind"] not in allowed_relationships
            or not _valid_reference(item["source_ref"])
            or not _valid_reference(item["target_ref"])
        ):
            raise ProbeError("MalformedRequest", "Transport")
        relationship_keys.append((item["kind"], item["source_ref"], item["target_ref"]))
    if relationship_keys != sorted(set(relationship_keys)):
        raise ProbeError("MalformedRequest", "Transport")

    for key in (
        "unclassified_line_count",
        "unrecognized_field_count",
        "empty_field_value_count",
        "sensitive_tail_truncated_count",
    ):
        if (
            type(structure[key]) is not int
            or not 0 <= structure[key] <= _MAX_Q7_OUTPUT_BYTES
        ):
            raise ProbeError("MalformedRequest", "Transport")


def _validate_projection_metadata(
    structure,
    *,
    available_field_categories,
    redacted_field_names,
    intent_content_observed,
):
    records_by_ref = {item["record_ref"]: item for item in structure["records"]}
    fields = structure["fields"]
    relationships = structure["relationships"]
    target_component_refs = {
        item["value_ref"]
        for item in fields
        if item["value_kind"] == "component_ref"
    }
    if structure["field_names"] != sorted({item["name"] for item in fields}):
        raise ProbeError("MalformedRequest", "Transport")
    if structure["record_type_names"] != sorted(
        {item["record_type"] for item in records_by_ref.values()}
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if available_field_categories != derive_available_field_categories(
        structure["record_type_names"], structure["field_names"]
    ):
        raise ProbeError("MalformedRequest", "Transport")
    expected_redacted_names = sorted(
        {item["name"] for item in fields if item["value_kind"] == "redacted"}
    )
    if redacted_field_names != expected_redacted_names:
        raise ProbeError("MalformedRequest", "Transport")
    if intent_content_observed != any(
        name.casefold() in {"intent", "mintent"} for name in expected_redacted_names
    ):
        raise ProbeError("MalformedRequest", "Transport")
    return records_by_ref, fields, relationships, target_component_refs


def _validate_target_projection(
    structure,
    *,
    target_component_observed,
    available_field_categories,
    redacted_field_names,
    intent_content_observed,
):
    records_by_ref, fields, relationships, target_component_refs = (
        _validate_projection_metadata(
            structure,
            available_field_categories=available_field_categories,
            redacted_field_names=redacted_field_names,
            intent_content_observed=intent_content_observed,
        )
    )
    if not target_component_observed:
        if (
            target_component_refs
            or records_by_ref
            or fields
            or relationships
            or structure["record_type_names"]
            or structure["field_names"]
            or available_field_categories
            or redacted_field_names
            or intent_content_observed
        ):
            raise ProbeError("MalformedRequest", "Transport")
        return

    if not target_component_refs:
        raise ProbeError("MalformedRequest", "Transport")
    component_package_refs = {
        item["target_ref"]
        for item in relationships
        if item["kind"] == "component_package"
        and item["source_ref"] in target_component_refs
    }
    component_package_sources = {
        item["source_ref"]
        for item in relationships
        if item["kind"] == "component_package"
    }
    if not component_package_refs or target_component_refs - component_package_sources:
        raise ProbeError("MalformedRequest", "Transport")

    target_record_refs = {
        item["source_ref"]
        for item in relationships
        if item["kind"] == "record_component"
        and item["target_ref"] in target_component_refs
    }
    related_records = target_record_refs.intersection(records_by_ref)
    changed = True
    while changed:
        changed = False
        for item in relationships:
            source = item["source_ref"]
            target = item["target_ref"]
            if item["kind"] == "layout_parent" and target in related_records:
                if (
                    source in records_by_ref
                    and records_by_ref[source]["record_type"] in _LAYOUT_PARENT_TYPES
                    and source not in related_records
                ):
                    related_records.add(source)
                    changed = True
            elif item["kind"] in _RECORD_CONTEXT_TYPES:
                expected = _RECORD_CONTEXT_TYPES[item["kind"]]
                if (
                    source in related_records
                    and target in records_by_ref
                    and records_by_ref[target]["record_type"] in expected
                    and target not in related_records
                ):
                    related_records.add(target)
                    changed = True
            elif item["kind"] in _RESUMED_RELATIONSHIPS:
                if (
                    target in target_record_refs
                    and source in records_by_ref
                    and records_by_ref[source]["record_type"] in _RESUMED_SOURCE_TYPES
                    and source not in related_records
                ):
                    related_records.add(source)
                    changed = True
        for item in fields:
            if (
                item.get("record_ref") in related_records
                and item.get("value_kind") == "record_ref"
                and item.get("value_ref") in target_record_refs
                and item.get("value_ref") in records_by_ref
                and item["value_ref"] not in related_records
            ):
                related_records.add(item["value_ref"])
                changed = True

    if set(records_by_ref) != related_records:
        raise ProbeError("MalformedRequest", "Transport")
    for item in fields:
        kind = item["value_kind"]
        value_ref = item.get("value_ref")
        if kind == "component_ref" and value_ref not in target_component_refs:
            raise ProbeError("MalformedRequest", "Transport")
        if kind == "package_ref" and value_ref not in component_package_refs:
            raise ProbeError("MalformedRequest", "Transport")
        if kind == "record_ref" and value_ref not in related_records:
            raise ProbeError("MalformedRequest", "Transport")
        if kind == "value_ref" and not any(
            category != "activity_records"
            and pattern.search(f"{item['name']}=")
            for category, pattern in _FIELD_PATTERNS.items()
        ):
            raise ProbeError("MalformedRequest", "Transport")
        record_ref = item["record_ref"]
        if record_ref is not None:
            if record_ref not in related_records:
                raise ProbeError("MalformedRequest", "Transport")
            continue
        if item["association"] not in {"unscoped", "ambiguous"}:
            raise ProbeError("MalformedRequest", "Transport")
        if kind == "component_ref":
            if value_ref not in target_component_refs:
                raise ProbeError("MalformedRequest", "Transport")
        elif kind == "record_ref":
            if (
                value_ref not in related_records
                or item["name"].casefold()
                not in {
                    "mresumedactivity",
                    "resumedactivity",
                    "topresumedactivity",
                    "mtopresumedactivity",
                }
            ):
                raise ProbeError("MalformedRequest", "Transport")
        elif item["value_kind"] != "redacted":
            raise ProbeError("MalformedRequest", "Transport")

    used_references = set(related_records) | target_component_refs | component_package_refs
    for item in fields:
        if item.get("record_ref") is not None:
            used_references.add(item["record_ref"])
        if item.get("value_ref") is not None:
            used_references.add(item["value_ref"])
    for item in relationships:
        if item["kind"] == "component_package":
            if (
                item["source_ref"] not in target_component_refs
                or item["target_ref"] not in component_package_refs
            ):
                raise ProbeError("MalformedRequest", "Transport")
        elif item["kind"] == "record_component":
            if (
                item["source_ref"] not in related_records
                or item["target_ref"] not in target_component_refs
            ):
                raise ProbeError("MalformedRequest", "Transport")
        elif item["kind"] == "layout_parent":
            if item["source_ref"] not in related_records or item["target_ref"] not in related_records:
                raise ProbeError("MalformedRequest", "Transport")
        elif item["kind"] == "record_package":
            if (
                item["source_ref"] not in related_records
                or item["target_ref"] not in component_package_refs
            ):
                raise ProbeError("MalformedRequest", "Transport")
        elif item["kind"] == "process_package":
            if (
                item["source_ref"] not in used_references
                or item["target_ref"] not in component_package_refs
            ):
                raise ProbeError("MalformedRequest", "Transport")
        elif (
            item["source_ref"] not in used_references
            or item["target_ref"] not in used_references
            or not (
                item["source_ref"] in related_records
                or item["target_ref"] in related_records
            )
        ):
            raise ProbeError("MalformedRequest", "Transport")


def _validate_window_display_projection(
    structure,
    *,
    target_component_observed,
    available_field_categories,
    redacted_field_names,
    intent_content_observed,
):
    if target_component_observed:
        _validate_target_projection(
            structure,
            target_component_observed=True,
            available_field_categories=available_field_categories,
            redacted_field_names=redacted_field_names,
            intent_content_observed=intent_content_observed,
        )
        for item in structure["fields"]:
            if item["name"] == "displayId" and item["value_kind"] != "display_ref":
                raise ProbeError("MalformedRequest", "Transport")
            if item["name"] == "rootTaskCount" and item["value_kind"] != "redacted":
                raise ProbeError("MalformedRequest", "Transport")
            if item["value_kind"] == "display_ref" and re.fullmatch(
                r"display-[0-9]{5}", item["value_ref"]
            ) is None:
                raise ProbeError("MalformedRequest", "Transport")
        for item in structure["relationships"]:
            for reference in (item["source_ref"], item["target_ref"]):
                if reference.startswith("display-") and re.fullmatch(
                    r"display-[0-9]{5}", reference
                ) is None:
                    raise ProbeError("MalformedRequest", "Transport")
        return

    records_by_ref, fields, relationships, target_component_refs = (
        _validate_projection_metadata(
            structure,
            available_field_categories=available_field_categories,
            redacted_field_names=redacted_field_names,
            intent_content_observed=intent_content_observed,
        )
    )
    if target_component_refs or intent_content_observed:
        raise ProbeError("MalformedRequest", "Transport")
    if not records_by_ref:
        if (
            fields
            or relationships
            or structure["record_type_names"]
            or structure["field_names"]
            or available_field_categories
            or redacted_field_names
        ):
            raise ProbeError("MalformedRequest", "Transport")
        return

    display_refs = set(records_by_ref)
    if structure["record_type_names"] != ["display_content"] or any(
        item["record_type"] != "display_content" for item in records_by_ref.values()
    ):
        raise ProbeError("MalformedRequest", "Transport")
    display_id_record_refs = {
        item["record_ref"] for item in fields if item["name"] == "displayId"
    }
    if display_id_record_refs != display_refs:
        raise ProbeError("MalformedRequest", "Transport")
    allowed_field_names = {"displayId", "rootTaskCount"}
    if any(
        item["record_ref"] not in display_refs
        or item["association"] != "attached"
        or item["name"] not in allowed_field_names
        or item["value_kind"] != "redacted"
        for item in fields
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if any(
        item["kind"] != "layout_parent"
        or item["source_ref"] not in display_refs
        or item["target_ref"] not in display_refs
        for item in relationships
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if not set(redacted_field_names).issubset(allowed_field_names):
        raise ProbeError("MalformedRequest", "Transport")


def _validate_record(record):
    required = {
        "schema",
        "target_ref",
        "identity_preflight_record_bound",
        "acquisition_started_at_utc",
        "acquisition_finished_at_utc",
        "duration_seconds",
        "acquisition_limits",
        "command_count",
        "started_monotonic",
        "finished_monotonic",
        "stdout_bytes",
        "total_output_bytes",
        "exit_code",
        "cleanup_complete",
        "qualification_assertions_passed",
        "source_identity",
        "limitations",
        "classification",
        "usable_exploratory_observation",
    }
    allowed = required | {
        "observation", "parser_error", "process_classification", "subject_package"
    }
    if not isinstance(record, Mapping) or not required.issubset(record) or set(record) - allowed:
        raise ProbeError("MalformedRequest", "Transport")
    if record.get("schema") not in (
        _Q7_EXPLORATORY_SCHEMA,
        _WINDOW_DISPLAY_EXPLORATORY_SCHEMA,
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if record.get("target_ref") != TARGET_REFERENCE:
        raise ProbeError("MalformedRequest", "Transport")
    if (
        "subject_package" in record
        and (
            type(record["subject_package"]) is not str
            or record["subject_package"] not in _Q7_SUBJECT_PACKAGES
        )
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if (
        record["schema"] == _WINDOW_DISPLAY_EXPLORATORY_SCHEMA
        and record.get("subject_package") != _READINESS_PROBE_PACKAGE
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if record.get("identity_preflight_record_bound") is not True:
        raise ProbeError("MalformedRequest", "Transport")
    if type(record.get("command_count")) is not int or record["command_count"] not in (0, 1):
        raise ProbeError("MalformedRequest", "Transport")
    if record.get("qualification_assertions_passed") is not False:
        raise ProbeError("MalformedRequest", "Transport")
    if type(record.get("usable_exploratory_observation")) is not bool:
        raise ProbeError("MalformedRequest", "Transport")
    if type(record.get("cleanup_complete")) is not bool:
        raise ProbeError("MalformedRequest", "Transport")
    if type(record.get("stdout_bytes")) is not int or record["stdout_bytes"] < 0:
        raise ProbeError("MalformedRequest", "Transport")
    if (
        type(record.get("total_output_bytes")) is not int
        or not record["stdout_bytes"] <= record["total_output_bytes"] <= _MAX_Q7_OUTPUT_BYTES
    ):
        raise ProbeError("MalformedRequest", "Transport")
    for key in ("started_monotonic", "finished_monotonic", "duration_seconds"):
        value = record.get(key)
        if type(value) not in (int, float) or not math.isfinite(value):
            raise ProbeError("MalformedRequest", "Transport")
    if (
        record["finished_monotonic"] < record["started_monotonic"]
        or record["duration_seconds"] < 0
        or abs(
            record["duration_seconds"]
            - (record["finished_monotonic"] - record["started_monotonic"])
        ) > 0.000001
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if record.get("acquisition_limits") != _RECORDED_LIMITS:
        raise ProbeError("MalformedRequest", "Transport")
    if record.get("exit_code") is not None and type(record["exit_code"]) is not int:
        raise ProbeError("MalformedRequest", "Transport")
    if "process_classification" in record and (
        type(record["process_classification"]) is not str
        or record["process_classification"] not in _Q7_PROCESS_CLASSIFICATIONS
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if record["classification"] not in {
        "exploratory_only",
        "device_timeout_indicator",
        "host_timeout",
        "resource_limit",
        "process_nonzero",
        "incomplete",
        "launch_failed",
        "cleanup_unverified",
        "malformed_output",
        "parser_rejection",
        "time_record_unavailable",
    }:
        raise ProbeError("MalformedRequest", "Transport")
    if "parser_error" in record and record["parser_error"] is None:
        raise ProbeError("MalformedRequest", "Transport")
    parser_error = record.get("parser_error")
    if parser_error is not None:
        expected_parser_error_fields = {
            "subtype",
            "stage",
            "error_code",
            "line_number",
            "line_byte_offset",
            "absolute_byte_offset",
            "parser_state",
        }
        if (
            not isinstance(parser_error, Mapping)
            or set(parser_error) != expected_parser_error_fields
            or type(parser_error["subtype"]) is not str
            or parser_error["subtype"] not in _Q7_PARSER_ERROR_SUBTYPES
            or type(parser_error["stage"]) is not str
            or parser_error["stage"] not in _Q7_PARSER_ERROR_STAGES
            or type(parser_error["error_code"]) is not str
            or parser_error["error_code"] not in _Q7_PARSER_ERROR_CODES
        ):
            raise ProbeError("MalformedRequest", "Transport")
        line_number = parser_error["line_number"]
        line_byte_offset = parser_error["line_byte_offset"]
        absolute_byte_offset = parser_error["absolute_byte_offset"]
        if (
            line_number is not None
            and (
                type(line_number) is not int
                or not 1 <= line_number <= record["stdout_bytes"] + 1
            )
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            line_byte_offset is not None
            and (
                type(line_byte_offset) is not int
                or not 0 <= line_byte_offset <= _MAX_Q7_LINE_LENGTH
            )
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            absolute_byte_offset is not None
            and (
                type(absolute_byte_offset) is not int
                or not 0 <= absolute_byte_offset <= record["stdout_bytes"]
            )
        ):
            raise ProbeError("MalformedRequest", "Transport")
        parser_state = parser_error["parser_state"]
        if (
            not isinstance(parser_state, Mapping)
            or set(parser_state) != _Q7_PARSER_STATE_FIELDS
            or any(
                type(parser_state[field]) is not int or parser_state[field] < 0
                for field in _Q7_PARSER_STATE_FIELDS
            )
            or parser_state["completed_lines"] > record["stdout_bytes"]
            or parser_state["records_seen"] > _MAX_Q7_STRUCTURAL_RECORDS
            or parser_state["fields_seen"] > _MAX_Q7_STRUCTURAL_FIELDS
            or parser_state["relationships_seen"] > _MAX_Q7_STRUCTURAL_RELATIONSHIPS
            or parser_state["record_stack_depth"] > _MAX_Q7_STRUCTURAL_RECORDS
            or parser_state["empty_field_values"] > record["stdout_bytes"]
            or parser_state["sensitive_tails_truncated"] > record["stdout_bytes"]
            or parser_state["unclassified_lines"] > record["stdout_bytes"]
            or parser_state["unrecognized_fields"] > _MAX_Q7_OUTPUT_BYTES
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            "process_classification" not in record
            or record["usable_exploratory_observation"]
            or record.get("observation") is not None
            or record["classification"]
            not in {"malformed_output", "parser_rejection", "resource_limit", "cleanup_unverified"}
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if record["classification"] == "parser_rejection" and parser_error is None:
            raise ProbeError("MalformedRequest", "Transport")
    for key in ("acquisition_started_at_utc", "acquisition_finished_at_utc"):
        value = record[key]
        if value is not None and (
            type(value) is not str
            or re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z", value) is None
        ):
            raise ProbeError("MalformedRequest", "Transport")
    identity = record.get("source_identity")
    if not _valid_recorded_source_identity(identity):
        raise ProbeError("MalformedRequest", "Transport")
    if (
        record["schema"] == _WINDOW_DISPLAY_EXPLORATORY_SCHEMA
        and set(identity["source_file_sha256"]) != set(_SOURCE_FILE_NAMES)
    ):
        raise ProbeError("MalformedRequest", "Transport")
    if list(record.get("limitations", ())) != list(_LIMITATIONS):
        raise ProbeError("MalformedRequest", "Transport")
    observation = record.get("observation")
    if observation is not None:
        expected_observation_fields = {
            "lines_observed",
            "max_line_bytes",
            "available_field_categories",
            "timeout_indicator_observed",
            "timeout_indicator_count",
            "completion_indicator_observed",
            "completion_indicator_count",
            "intent_content_observed",
            "redacted_field_names",
            "target_component_observed",
            "eof_observed",
            "completion_verified",
            "target_binding_established",
            "task_continuity_established",
            "structure",
        }
        if not isinstance(observation, Mapping) or set(observation) != expected_observation_fields:
            raise ProbeError("MalformedRequest", "Transport")
        if (
            type(observation["lines_observed"]) is not int
            or not 0 <= observation["lines_observed"] <= _MAX_Q7_OUTPUT_BYTES
            or observation["lines_observed"] > record["stdout_bytes"]
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            type(observation["max_line_bytes"]) is not int
            or not 0 <= observation["max_line_bytes"] <= _MAX_Q7_LINE_LENGTH
        ):
            raise ProbeError("MalformedRequest", "Transport")
        categories = observation["available_field_categories"]
        if (
            type(categories) is not list
            or categories != sorted(set(categories))
            or any(category not in _FIELD_PATTERNS for category in categories)
        ):
            raise ProbeError("MalformedRequest", "Transport")
        boolean_fields = {
            "timeout_indicator_observed",
            "completion_indicator_observed",
            "intent_content_observed",
            "target_component_observed",
            "eof_observed",
            "completion_verified",
            "target_binding_established",
            "task_continuity_established",
        }
        if any(type(observation[field]) is not bool for field in boolean_fields):
            raise ProbeError("MalformedRequest", "Transport")
        for key in ("timeout_indicator_count", "completion_indicator_count"):
            if type(observation[key]) is not int or not 0 <= observation[key] <= observation["lines_observed"]:
                raise ProbeError("MalformedRequest", "Transport")
        if observation["timeout_indicator_observed"] != (observation["timeout_indicator_count"] > 0):
            raise ProbeError("MalformedRequest", "Transport")
        if observation["completion_indicator_observed"] != (observation["completion_indicator_count"] > 0):
            raise ProbeError("MalformedRequest", "Transport")
        redacted_names = observation["redacted_field_names"]
        if (
            type(redacted_names) is not list
            or len(redacted_names) > _MAX_Q7_STRUCTURAL_FIELDS
            or any(
                type(name) is not str or not _SAFE_FIELD_NAME_PATTERN.fullmatch(name)
                for name in redacted_names
            )
            or redacted_names != sorted(set(redacted_names))
        ):
            raise ProbeError("MalformedRequest", "Transport")
        if (
            observation["eof_observed"] is not True
            or observation["completion_verified"] is not False
            or observation["target_binding_established"] is not False
            or observation["task_continuity_established"] is not False
        ):
            raise ProbeError("MalformedRequest", "Transport")
        _validate_structure(observation["structure"])
        if record["schema"] == _WINDOW_DISPLAY_EXPLORATORY_SCHEMA:
            _validate_window_display_projection(
                observation["structure"],
                target_component_observed=observation["target_component_observed"],
                available_field_categories=categories,
                redacted_field_names=redacted_names,
                intent_content_observed=observation["intent_content_observed"],
            )
        else:
            _validate_target_projection(
                observation["structure"],
                target_component_observed=observation["target_component_observed"],
                available_field_categories=categories,
                redacted_field_names=redacted_names,
                intent_content_observed=observation["intent_content_observed"],
            )
    if record["usable_exploratory_observation"]:
        if (
            record["classification"] != "exploratory_only"
            or record.get("observation") is None
            or record["command_count"] != 1
            or record["exit_code"] != 0
            or not record["cleanup_complete"]
            or record["observation"]["timeout_indicator_observed"]
        ):
            raise ProbeError("MalformedRequest", "Transport")
    elif record["classification"] == "exploratory_only":
        raise ProbeError("MalformedRequest", "Transport")
    try:
        json.dumps(record, allow_nan=False, sort_keys=True)
    except Exception:
        raise ProbeError("MalformedRequest", "Transport") from None


def _write_sanitized_outcome(outcomes_directory, record):
    """Create one owner-only result file for an internally acquired record."""
    _validate_record(record)
    try:
        directory_fd = _open_verified_directory(outcomes_directory)
    except ProbeError:
        raise
    except Exception:
        raise ProbeError("UnauthorizedPeer", "Transport") from None
    previous_umask = os.umask(0o077)
    created_name = None
    file_fd = None
    try:
        for _attempt in range(5):
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            candidate = f"q7-exploratory-{timestamp}-{secrets.token_hex(4)}.json"
            try:
                file_fd = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                    0o600,
                    dir_fd=directory_fd,
                )
                created_name = candidate
                break
            except FileExistsError:
                continue
        if file_fd is None or created_name is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        metadata = os.fstat(file_fd)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or stat.S_IMODE(metadata.st_mode) != 0o600
        ):
            raise ProbeError("UnauthorizedPeer", "Transport")
        payload = (json.dumps(record, allow_nan=False, sort_keys=True) + "\n").encode(
            "utf-8"
        )
        view = memoryview(payload)
        while view:
            written = os.write(file_fd, view)
            if written <= 0:
                raise ProbeError("IncompleteEvidence", "Transport")
            view = view[written:]
        os.fsync(file_fd)
        os.fsync(directory_fd)
        return created_name
    except ProbeError:
        if created_name is not None:
            try:
                os.unlink(created_name, dir_fd=directory_fd)
            except OSError:
                pass
        raise
    except Exception:
        if created_name is not None:
            try:
                os.unlink(created_name, dir_fd=directory_fd)
            except OSError:
                pass
        raise ProbeError("IncompleteEvidence", "Transport") from None
    finally:
        if file_fd is not None:
            os.close(file_fd)
        os.umask(previous_umask)
        os.close(directory_fd)
