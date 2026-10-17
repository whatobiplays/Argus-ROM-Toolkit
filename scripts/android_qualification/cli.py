"""Sanitized command-line handling for structural qualification host checks."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence, TextIO

from .admission import LiveExecutionBlocked, admit_host_only, request_live_execution
from .manifest import ManifestError, StateMode


class _CliArgumentsInvalid(Exception):
    pass


class _SanitizedArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise _CliArgumentsInvalid from None


def _emit(payload: dict[str, object], stream: TextIO) -> None:
    stream.write(json.dumps(payload, separators=(",", ":")) + "\n")


def _emit_blocked(code: str, message: str, stream: TextIO) -> None:
    _emit(
        {
            "status": "BLOCKED",
            "error": {"code": code, "message": message},
        },
        stream,
    )


def _parser() -> argparse.ArgumentParser:
    parser = _SanitizedArgumentParser(
        description=(
            "Perform structural host validation of a private Android "
            "qualification manifest. This is not SPEC-X-003 session admission "
            "and does not access a device."
        ),
        epilog=(
            "HOST_VALIDATED means only that the manifest passed structural "
            "host checks. Without --dry-run or --preflight, live execution is "
            "blocked until live authorization and device admission exist."
        ),
        allow_abbrev=False,
    )
    parser.add_argument(
        "--manifest",
        required=True,
        metavar="PATH",
        help="owner-private qualification manifest",
    )
    host_only = parser.add_mutually_exclusive_group()
    host_only.add_argument(
        "--dry-run",
        action="store_true",
        help="perform structural host validation only; never access a device",
    )
    host_only.add_argument(
        "--preflight",
        action="store_true",
        help="perform structural host validation only; never access a device",
    )
    return parser


def main(
    state_mode: StateMode,
    argv: Sequence[str] | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
) -> int:
    """Run one fixed state-mode adapter and return its documented exit code."""

    output = sys.stdout if stdout is None else stdout
    _error_output = sys.stderr if stderr is None else stderr

    try:
        arguments = _parser().parse_args(argv)
    except _CliArgumentsInvalid:
        _emit_blocked(
            "CLI_ARGUMENTS_INVALID",
            "Qualification command arguments are invalid",
            output,
        )
        return 2

    try:
        validation = admit_host_only(Path(arguments.manifest), state_mode)
        if arguments.dry_run or arguments.preflight:
            _emit(
                {
                    "status": "HOST_VALIDATED",
                    "state_mode": validation.manifest.state_mode.value,
                },
                output,
            )
            return 0
        request_live_execution(validation)
    except ManifestError as error:
        _emit_blocked(error.code.value, str(error), output)
        return 2
    except LiveExecutionBlocked as error:
        _emit_blocked("LIVE_ADMISSION_NOT_IMPLEMENTED", str(error), output)
        return 3
    except Exception:
        _emit_blocked(
            "HOST_VALIDATION_INTERNAL_ERROR",
            "Qualification host validation failed",
            output,
        )
        return 2

    raise AssertionError("live execution unexpectedly continued")
