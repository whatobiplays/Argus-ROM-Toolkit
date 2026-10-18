"""Fail-closed checks for physical orchestration entry points."""

import os
import ast
from argparse import Namespace
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from scripts.android_qualification.physical import core, runner
from scripts.android_qualification.physical.test_support import (
    FakeDevice as Device,
    FakeTransport as Transport,
)


_PROCESS_LAUNCHERS = {
    'subprocess': {'Popen', 'run', 'call', 'check_call', 'check_output',
                   'getoutput', 'getstatusoutput'},
    'os': {'system', 'popen', 'fork', 'forkpty', 'posix_spawn', 'posix_spawnp'},
    'asyncio': {'create_subprocess_exec', 'create_subprocess_shell'},
    'multiprocessing': {'Process', 'Pool'},
    'concurrent.futures': {'ProcessPoolExecutor'},
}


def _is_process_launcher(module, name):
    if name in _PROCESS_LAUNCHERS.get(module, set()):
        return True
    return module == 'os' and name.startswith(('exec', 'spawn'))


def _dotted_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = _dotted_name(node.value)
        return f'{prefix}.{node.attr}' if prefix else None
    return None


def _process_launch_calls(tree):
    """Return qualified process-launch calls, resolving imported aliases."""
    module_aliases = {}
    function_aliases = {}
    wildcard_modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split('.', 1)[0]
                if (root in _PROCESS_LAUNCHERS
                        or alias.name in _PROCESS_LAUNCHERS
                        or any(module.startswith(alias.name + '.')
                               for module in _PROCESS_LAUNCHERS)):
                    local_name = alias.asname or root
                    module_aliases[local_name] = alias.name if alias.asname else root
        elif isinstance(node, ast.ImportFrom) and node.module:
            for alias in node.names:
                if alias.name == '*' and node.module in _PROCESS_LAUNCHERS:
                    wildcard_modules.add(node.module)
                if _is_process_launcher(node.module, alias.name):
                    function_aliases[alias.asname or alias.name] = (
                        node.module, alias.name)

    launches = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            resolved = function_aliases.get(node.func.id)
            if resolved:
                launches.append(f'{resolved[0]}.{resolved[1]}')
            else:
                launches.extend(
                    f'{module}.{node.func.id}'
                    for module in wildcard_modules
                    if _is_process_launcher(module, node.func.id)
                )
            continue
        dotted = _dotted_name(node.func)
        if not dotted:
            continue
        for local_module in sorted(module_aliases, key=len, reverse=True):
            if dotted == local_module or dotted.startswith(local_module + '.'):
                suffix = dotted[len(local_module):].lstrip('.')
                qualified = module_aliases[local_module]
                if suffix:
                    qualified = f'{qualified}.{suffix}'
                module, separator, name = qualified.rpartition('.')
                if separator and _is_process_launcher(module, name):
                    launches.append(f'{module}.{name}')
                break
    return sorted(launches)


def _production_package_violations(package):
    """Return unsafe execution and transport composition found in production modules."""
    violations = []
    excluded_directories = {'test', 'tests', 'fixture', 'fixtures'}
    for source_path in sorted(package.rglob('*.py')):
        relative_path = source_path.relative_to(package)
        if source_path.name.startswith('test_') or any(
                part.casefold() in excluded_directories for part in relative_path.parts[:-1]):
            continue
        source = source_path.read_text(encoding='utf-8')
        tree = ast.parse(source, filename=str(source_path))
        violations.extend(
            f'{relative_path.as_posix()}: process launch via {launch}'
            for launch in _process_launch_calls(tree)
        )
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                if any(alias.name == '*' or _is_process_launcher(node.module, alias.name)
                       for alias in node.names):
                    violations.append(f'{relative_path.as_posix()}: imported process launcher')
            if isinstance(node, ast.ClassDef) and node.name == 'Device':
                violations.append(f'{relative_path.as_posix()}: concrete Device class')
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == 'execute':
                violations.append(f'{relative_path.as_posix()}: execute function')
            if (isinstance(node, ast.Attribute) and node.attr in {'Device', 'execute'}
                    and isinstance(node.value, ast.Name) and node.value.id == 'core'):
                violations.append(f'{relative_path.as_posix()}: core.{node.attr} composition')
    return violations


class ExecutionIsolationTests(unittest.TestCase):
    """Ensure production entry points cannot create a device or launch ADB."""

    def test_process_launch_detection_resolves_import_aliases_and_ignores_device_run(self):
        source = ast.parse(
            "import subprocess as process\n"
            "import os as operating_system\n"
            "import asyncio as async_io\n"
            "import multiprocessing as processes\n"
    "import concurrent.futures as futures\n"
            "from subprocess import Popen as start_process, run as run_process\n"
            "from os import system as run_shell\n"
            "from asyncio import create_subprocess_shell as run_shell_async\n"
    "from subprocess import *\n"
            "process.Popen(['tool'])\n"
            "process.run(['tool'])\n"
            "start_process(['tool'])\n"
            "run_process(['tool'])\n"
            "operating_system.system('tool')\n"
            "run_shell('tool')\n"
            "async_io.create_subprocess_exec('tool')\n"
            "run_shell_async('tool')\n"
            "processes.Process(target=work)\n"
    "futures.ProcessPoolExecutor()\n"
    "Popen(['tool'])\n"
            "device.run('install')\n"
        )

        self.assertEqual(
            _process_launch_calls(source),
            [
                'asyncio.create_subprocess_exec',
                'asyncio.create_subprocess_shell',
                'concurrent.futures.ProcessPoolExecutor',
                'multiprocessing.Process',
                'os.system',
                'os.system',
                'subprocess.Popen',
                'subprocess.Popen',
                'subprocess.Popen',
                'subprocess.run',
                'subprocess.run',
            ],
        )

    def test_nested_production_module_is_scanned_but_tests_and_fixtures_are_excluded(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            production = package / 'nested' / 'worker.py'
            production.parent.mkdir()
            production.write_text(
                "import subprocess\nsubprocess.run(['tool'])\n",
                encoding='utf-8',
            )
            test_module = package / 'tests' / 'worker.py'
            test_module.parent.mkdir()
            test_module.write_text(
                "import subprocess\nsubprocess.run(['test-tool'])\n",
                encoding='utf-8',
            )
            fixture_module = package / 'fixtures' / 'worker.py'
            fixture_module.parent.mkdir()
            fixture_module.write_text(
                "import subprocess\nsubprocess.run(['fixture-tool'])\n",
                encoding='utf-8',
            )

            violations = _production_package_violations(package)

        self.assertEqual(
            violations,
            ['nested/worker.py: process launch via subprocess.run'],
        )

    def test_active_package_contains_no_process_or_device_transport_composition(self):
        package = Path(__file__).parent
        violations = _production_package_violations(package)
        self.assertEqual(violations, [])
        self.assertFalse(hasattr(core, 'Device'))
        self.assertFalse(hasattr(core, 'execute'))
        self.assertFalse(hasattr(runner, '_TestRunnerDependencies'))

    def arguments(self, fixtures):
        return Namespace(
            adb="adb",
            device="selected",
            fixtures=Path(fixtures),
            fixture_limit_mib=1,
            signing_env=None,
            source_signing_env=False,
            certificate_sha256=None,
            preflight_only=True,
            build=False,
            apk=None,
            retain_fixtures_for_owner=False,
        )

    def test_default_runner_fails_before_device_construction_or_adb(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture_root = Path(temporary) / "fixtures"
            fixture_root.mkdir()
            with self.assertRaisesRegex(RuntimeError, "LIVE_EXECUTION_NOT_IMPLEMENTED"):
                runner.run(self.arguments(fixture_root))

    def test_public_runner_rejects_injected_orchestration_dependencies(self):
        with self.assertRaises(TypeError):
            runner.run(self.arguments("/unused"), dependencies=object())

    def test_main_function_fails_before_device_construction_or_adb(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture_root = Path(temporary) / "fixtures"
            fixture_root.mkdir()
            argv = [
                "qualification-runner",
                "--device",
                "selected",
                "--fixtures",
                str(fixture_root),
                "--preflight-only",
            ]
            with patch.object(sys, "argv", argv), patch.object(
                sys, "stdout", io.StringIO()
            ), patch.object(sys, "stderr", io.StringIO()):
                code = runner.main()
            self.assertEqual(code, 3)

    def test_default_entrypoints_make_zero_fake_adb_calls(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            adb_log = root / "adb-calls.log"
            fake_adb = fake_bin / "adb"
            fake_adb.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$*" >> "$ARGUS_TEST_ADB_LOG"\n',
                encoding="utf-8",
            )
            fake_adb.chmod(0o755)
            fixtures = root / "fixtures"
            fixtures.mkdir()
            environment = {
                "PATH": str(fake_bin),
                "PYTHONPATH": str(Path(__file__).resolve().parents[3]),
                "ARGUS_TEST_ADB_LOG": str(adb_log),
                "PYTHONDONTWRITEBYTECODE": "1",
            }
            with patch.dict(os.environ, environment, clear=True):
                with self.assertRaisesRegex(RuntimeError, "LIVE_EXECUTION_NOT_IMPLEMENTED"):
                    runner.run(self.arguments(fixtures))
                self.assertFalse(adb_log.exists())

                errors = io.StringIO()
                with patch.object(sys, "argv", [
                    "qualification-runner", "--device", "selected",
                    "--fixtures", str(fixtures), "--preflight-only",
                ]), patch.object(sys, "stderr", errors):
                    self.assertEqual(runner.main(), 3)
                self.assertIn("LIVE_EXECUTION_NOT_IMPLEMENTED", errors.getvalue())
                self.assertFalse(adb_log.exists())

                result = subprocess.run(
                    [
                        sys.executable,
                        "-m",
                        "scripts.android_qualification.physical.runner",
                        "--device",
                        "selected",
                        "--fixtures",
                        str(fixtures),
                        "--preflight-only",
                    ],
                    cwd=root,
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False,
                )
            self.assertFalse(adb_log.exists())
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertIn("LIVE_EXECUTION_NOT_IMPLEMENTED", result.stderr)

    def test_device_requires_an_explicit_transport(self):
        with self.assertRaises(TypeError):
            Device("adb", "selected")

    def test_cleanup_can_target_new_directory_but_never_archived_directory(self):
        repository = Path(__file__).resolve().parents[3]
        manifest_path = (
            repository
            / "docs/archive/qualification/issue-21-v1/archive-manifest-v1.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        historical_directory = manifest["historical_device_owned_directory"]
        self.assertNotEqual(core.DEVICE_ROOT, historical_directory)

        transport = Transport()
        device = Device("fake-adb", "selected", transport)
        device.shell("rm", "-rf", core.DEVICE_ROOT, mutating=True)

        cleanup_commands = [
            command for command in transport.commands if "rm" in command
        ]
        self.assertEqual(len(cleanup_commands), 1)
        self.assertIn(core.DEVICE_ROOT, cleanup_commands[0])
        self.assertNotIn(historical_directory, " ".join(cleanup_commands[0]))

    def test_cleanup_rejects_descendants_and_historical_directory(self):
        repository = Path(__file__).resolve().parents[3]
        manifest_path = (
            repository
            / "docs/archive/qualification/issue-21-v1/archive-manifest-v1.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        historical_directory = manifest["historical_device_owned_directory"]
        transport = Transport()
        device = Device("fake-adb", "selected", transport)

        for target in (core.DEVICE_ROOT + "/fixtures", historical_directory):
            with self.subTest(target=target), self.assertRaises(core.Blocked):
                device.shell("rm", "-rf", target, mutating=True)

        self.assertFalse(any("rm" in command for command in transport.commands))


if __name__ == "__main__":
    unittest.main()
