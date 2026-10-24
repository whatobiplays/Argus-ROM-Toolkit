"""Regression-check the public Issue #24 fail-closed fixture boundary."""

from __future__ import annotations

import unittest

from scripts.android_qualification import fixture_staging


class EvidenceIssue24BoundaryTests(unittest.TestCase):
    def test_public_staging_and_cleanup_still_fail_closed_before_argument_access(self) -> None:
        result = fixture_staging.stage_fixtures(
            object(),
            source_roots={},
            destination=object(),
        )
        cleanup = fixture_staging.cleanup_fixture_staging(
            object(),
            destination=object(),
            session_id="0" * 32,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            fixture_staging.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertFalse(result.device_admitted)
        self.assertEqual(cleanup.status, "BLOCKED")
        self.assertEqual(
            cleanup.blocker_code,
            fixture_staging.FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertFalse(cleanup.removed)


if __name__ == "__main__":
    unittest.main()
