"""Keep fixture byte validation separate from identity qualification."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from scripts.android_qualification import fixture_staging


class Issue24EvidenceBoundaryTests(unittest.TestCase):
    def test_verified_synthetic_bytes_do_not_qualify_fixture_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            data = b"synthetic qualification bytes"
            (source / "game.rom").write_bytes(data)
            manifest = {
                "schema_version": 2,
                "coverage": {
                    "mode": "mandatory_full_plan",
                    "required_fixture_ids": ["fixture-synthetic"],
                    "mandatory_fixture_ids": ["fixture-synthetic"],
                },
                "fixtures": [
                    {
                        "fixture_id": "fixture-synthetic",
                        "group_id": "group-synthetic",
                        "order": 0,
                        "platform": "Synthetic Platform",
                        "representation": "raw-file",
                        "entrypoint": "game.rom",
                        "expected_identity": {"title": "Synthetic Example"},
                        "structural_expectations": {"entrypoint_kind": "raw-file"},
                        "files": [
                            {
                                "path": "game.rom",
                                "role": "content",
                                "size": len(data),
                                "sha256": hashlib.sha256(data).hexdigest(),
                            }
                        ],
                        "companions": [],
                        "identity_evidence": {
                            "schema_version": 1,
                            "tier": "synthetic",
                            "provenance": "Generated for the unit test",
                        },
                    }
                ],
            }

            result = fixture_staging.stage_fixtures(
                manifest,
                {"fixture-synthetic": source},
                selected_fixture_ids=("fixture-synthetic",),
                owner_approved=True,
                staging_root=root / "staging",
                minimum_free_bytes=0,
            )

            self.assertEqual("verified", result.status)
            self.assertEqual("synthetic_only", result.assessments[0].identity_support)
            self.assertEqual("not_qualified", result.assessments[0].qualification_status)


if __name__ == "__main__":
    unittest.main()
