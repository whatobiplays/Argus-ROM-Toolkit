"""Capacity preflight tests; these tests allocate no transfer or VM payloads."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from .staging_resources import ResourceBlocked, check_capacity


class StagingResourceTests(unittest.TestCase):
    def test_cli_does_not_disclose_filesystem_identity_or_path(self):
        with tempfile.TemporaryDirectory() as root:
            result = subprocess.run(
                [sys.executable, '-m', 'scripts.android_qualification.staging_resources',
                 root, '--reserve-bytes', '1', '--estimated-bytes', '1'],
                capture_output=True, text=True, check=True)
            record = json.loads(result.stdout)
            self.assertEqual(record['status'], 'CAPACITY_OBSERVED')
            self.assertNotIn('device', record)
            self.assertNotIn(root, result.stdout)

    def test_reserve_and_estimate_must_both_fit(self):
        with tempfile.TemporaryDirectory() as root:
            observation = SimpleNamespace(f_bavail=10, f_frsize=1024)
            with patch('os.statvfs', return_value=observation):
                self.assertEqual(check_capacity(Path(root), 8192, 2048).available_bytes, 10240)
                with self.assertRaises(ResourceBlocked):
                    check_capacity(Path(root), 8192, 2049)

    def test_uncreated_artifact_directory_is_not_created_by_preflight(self):
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / 'build' / 'objects'
            result = check_capacity(target, 1, 1)
            self.assertGreater(result.available_bytes, 1)
            self.assertFalse(target.parent.exists())

    def test_unresolvable_symlink_ancestry_does_not_borrow_parent_capacity(self):
        with tempfile.TemporaryDirectory() as root:
            for name, target in [('dangling', 'absent'), ('cycle', 'cycle')]:
                link = Path(root) / name
                link.symlink_to(target)
                with self.subTest(name=name):
                    with self.assertRaisesRegex(ResourceBlocked, '^BUILD_CAPACITY_UNPROVEN$'):
                        check_capacity(link / 'objects', 1, 1)

    def test_unknown_capacity_and_invalid_budgets_fail_closed(self):
        with tempfile.TemporaryDirectory() as root:
            for reserve, expected in [(True, 1), (1, False), (-1, 1), (1, -1), (0, 1), (1.0, 1)]:
                with self.subTest(reserve=reserve, expected=expected):
                    with self.assertRaises(ResourceBlocked):
                        check_capacity(Path(root), reserve, expected)
            with patch('os.statvfs', side_effect=OSError('private path')):
                with self.assertRaisesRegex(ResourceBlocked, '^BUILD_CAPACITY_UNPROVEN$'):
                    check_capacity(Path(root), 1, 1)

    def test_large_logical_budget_requires_capacity_without_allocating_it(self):
        with tempfile.TemporaryDirectory() as root:
            with patch('os.statvfs', return_value=SimpleNamespace(f_bavail=1, f_frsize=4096)):
                with self.assertRaisesRegex(ResourceBlocked, '^BUILD_CAPACITY_INSUFFICIENT$'):
                    check_capacity(Path(root), 4096, 5 * 1024**3)
            self.assertEqual(list(Path(root).iterdir()), [])
