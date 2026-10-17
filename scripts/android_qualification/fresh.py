"""Fresh-state qualification entrypoint adapter."""

from __future__ import annotations

import sys
from pathlib import Path


if __package__ in (None, ""):
    repository_root = Path(__file__).resolve().parents[2]
    if str(repository_root) not in sys.path:
        sys.path.insert(0, str(repository_root))


def _main() -> int:
    from scripts.android_qualification.cli import main
    from scripts.android_qualification.manifest import StateMode

    return main(StateMode.FRESH)


if __name__ == "__main__":
    raise SystemExit(_main())
