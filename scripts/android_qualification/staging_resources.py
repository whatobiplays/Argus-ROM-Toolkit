"""Read-only capacity admission for task-owned native build artifacts.

This preflight neither allocates space nor proves future capacity. Build drivers
repeat it before expensive commands. It is not production fixture admission.
"""

import argparse
import json
import os
import stat
from dataclasses import asdict, dataclass
from pathlib import Path


class ResourceBlocked(Exception):
    """A sanitized prerequisite failure; no private path enters diagnostics."""


@dataclass(frozen=True)
class CapacityBudget:
    """Available bytes and requested reserve, without filesystem identifiers."""

    available_bytes: int
    reserve_bytes: int
    estimated_artifact_bytes: int


def check_capacity(path: Path, reserve_bytes: int, estimated_bytes: int) -> CapacityBudget:
    """Require the estimate plus reserve on the nearest existing ancestor.

    The check deliberately uses the actual filesystem containing the requested
    artifacts. In particular, a temporary directory is not assumed to be another
    volume. Equality is sufficient; an unobservable capacity is a blocker.
    """
    if (type(reserve_bytes) is not int or reserve_bytes <= 0
            or type(estimated_bytes) is not int or estimated_bytes < 0):
        raise ResourceBlocked('BUILD_BUDGET_INVALID')
    try:
        ancestor = Path(path).absolute()
        while True:
            try:
                ancestor.lstat()
            except FileNotFoundError:
                if ancestor == ancestor.parent:
                    raise OSError('no ancestor') from None
                ancestor = ancestor.parent
            else:
                break
        # A real existing symlink may resolve to a directory, but a dangling or
        # cyclic link must not be mistaken for a directory yet to be created.
        if not stat.S_ISDIR(ancestor.stat().st_mode):
            raise OSError('not a directory')
        space = os.statvfs(ancestor)
        available = space.f_bavail * space.f_frsize
        if available < 0 or space.f_frsize <= 0:
            raise OSError('invalid capacity')
    except (OSError, ValueError, TypeError):
        raise ResourceBlocked('BUILD_CAPACITY_UNPROVEN') from None
    if available < reserve_bytes + estimated_bytes:
        raise ResourceBlocked('BUILD_CAPACITY_INSUFFICIENT')
    return CapacityBudget(available, reserve_bytes, estimated_bytes)


def main() -> int:
    """Print a sanitized capacity record without creating the artifact path."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact_directory', type=Path)
    parser.add_argument('--reserve-bytes', type=int, default=2 * 1024**3)
    parser.add_argument('--estimated-bytes', type=int, default=64 * 1024**2)
    args = parser.parse_args()
    try:
        result = check_capacity(args.artifact_directory, args.reserve_bytes, args.estimated_bytes)
    except ResourceBlocked as error:
        print(json.dumps({'status': 'BLOCKED', 'code': str(error)}))
        return 2
    print(json.dumps({'status': 'CAPACITY_OBSERVED', **asdict(result)}, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
