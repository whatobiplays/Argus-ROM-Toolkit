"""Guard the pilot's cache paths and write redacted evidence.

All experiment state lives under ``RUNNER_TEMP``. Only ``caches/modules-2`` is
eligible for the dependency cache; wrapper distributions, Robolectric artifacts,
build outputs, and bounded control fixtures stay in separate paths.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


MODULE_CACHE_LIMIT = 1_073_741_824
FIXTURE_LIMIT = 1_048_576
TRANSIENT_NAMES = {"gc.properties"}
TRANSIENT_SUFFIXES = (".lock", ".lck")


class SafetyError(RuntimeError):
    """Raised when a path or cache state falls outside the experiment boundary."""


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _reject_symlink_components(path: Path, stop: Path) -> None:
    current = stop
    for part in path.relative_to(stop).parts:
        current = current / part
        if current.is_symlink():
            raise SafetyError("experiment path contains a symbolic link")


def _runner_temp() -> Path:
    raw = os.environ.get("RUNNER_TEMP")
    if not raw:
        raise SafetyError("RUNNER_TEMP is not set")
    temp = Path(raw).resolve(strict=True)
    if not temp.is_dir():
        raise SafetyError("RUNNER_TEMP is not a directory")
    return temp


def _task_root(create: bool = False) -> Path:
    temp = _runner_temp()
    run_id = os.environ.get("GITHUB_RUN_ID", "local-run")
    job = os.environ.get("GITHUB_JOB", "local-job")
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
        raise SafetyError("run identifier has unexpected characters")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", job):
        raise SafetyError("job identifier has unexpected characters")
    if not re.fullmatch(r"[0-9]+", attempt):
        raise SafetyError("run attempt is not numeric")
    root = temp / "gradle-dependency-cache-experiment" / "state"
    _reject_symlink_components(root, temp)
    if create:
        root.mkdir(parents=True, exist_ok=True)
    resolved = root.resolve(strict=False)
    if not _inside(resolved, temp):
        raise SafetyError("experiment state escaped RUNNER_TEMP")
    return resolved


def _home(create: bool = False) -> Path:
    task_root = _task_root(create=create)
    home = task_root / "gradle-home"
    _reject_symlink_components(home, _runner_temp())
    if create:
        home.mkdir(parents=True, exist_ok=True)
    resolved = home.resolve(strict=False)
    if not _inside(resolved, task_root.resolve(strict=False)):
        raise SafetyError("Gradle user home escaped the isolated job directory")
    return resolved


def _modules_path() -> Path:
    home = _home(create=False)
    modules = home / "caches" / "modules-2"
    _reject_symlink_components(modules, _runner_temp())
    if not _inside(modules.resolve(strict=False), home):
        raise SafetyError("module cache escaped the isolated Gradle user home")
    return modules


def _evidence_path() -> Path:
    root = _task_root(create=True)
    path = root / "evidence.json"
    if path.is_symlink() or not _inside(path.resolve(strict=False), root):
        raise SafetyError("evidence path is outside the isolated job directory")
    return path


def _github_file(name: str) -> Path | None:
    raw = os.environ.get(name)
    return Path(raw) if raw else None


def _append_github_file(path: Path | None, lines: list[str]) -> None:
    if path is None:
        return
    with path.open("a", encoding="utf-8") as stream:
        stream.write("".join(f"{line}\n" for line in lines))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def java_runtime_identity(environment: dict[str, str] | None = None) -> dict[str, str]:
    """Return the installed Temurin 17 runtime identity used by the cache key."""
    result = subprocess.run(
        ["java", "-XshowSettings:properties", "-version"],
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode:
        raise SafetyError("Java runtime identity query failed")
    properties = {}
    for line in result.stdout.splitlines():
        match = re.match(r"\s*([a-zA-Z0-9_.]+)\s*=\s*(.*?)\s*$", line)
        if match:
            properties[match.group(1)] = match.group(2)
    runtime = properties.get("java.runtime.version", "")
    vendor = properties.get("java.vendor", "")
    if not runtime.startswith("17.") or vendor != "Eclipse Adoptium":
        raise SafetyError("cache pilot requires a Temurin Java 17 runtime")
    return {"java_runtime_version": runtime, "java_vendor": vendor}


def _excluded(relative: Path) -> bool:
    name = relative.name
    return name in TRANSIENT_NAMES or name.endswith(TRANSIENT_SUFFIXES)


def canonical_manifest(root: Path, maximum_bytes: int) -> dict[str, Any]:
    """Hash regular files by relative path and contents, excluding transient metadata."""
    if root.is_symlink():
        raise SafetyError("manifest root is a symbolic link")
    if not root.exists():
        entries: list[dict[str, Any]] = []
    elif not root.is_dir():
        raise SafetyError("manifest root is not a directory")
    else:
        resolved_root = root.resolve(strict=True)
        entries = []
        total = 0
        for directory, names, filenames in os.walk(resolved_root, topdown=True, followlinks=False):
            current = Path(directory)
            safe_names = []
            for name in sorted(names):
                child = current / name
                if child.is_symlink():
                    raise SafetyError("cache contains a symbolic link")
                safe_names.append(name)
            names[:] = safe_names
            for name in sorted(filenames):
                path = current / name
                relative = path.relative_to(resolved_root)
                if _excluded(relative):
                    continue
                if path.is_symlink():
                    raise SafetyError("cache contains a symbolic link")
                metadata = path.stat(follow_symlinks=False)
                if not stat.S_ISREG(metadata.st_mode):
                    raise SafetyError("cache contains a non-regular file")
                total += metadata.st_size
                if total > maximum_bytes:
                    raise SafetyError("expanded cache exceeds its configured byte limit")
                entries.append({
                    "path": relative.as_posix(),
                    "bytes": metadata.st_size,
                    "sha256": _sha256_file(path),
                })
    entries.sort(key=lambda item: item["path"])
    total_bytes = sum(item["bytes"] for item in entries)
    payload = {"format": 1, "files": entries}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "format": 1,
        "sha256": hashlib.sha256(canonical).hexdigest(),
        "files": len(entries),
        "bytes": total_bytes,
        "entries": entries,
    }


def _stable_manifest(root: Path, maximum_bytes: int) -> dict[str, Any]:
    first = canonical_manifest(root, maximum_bytes)
    time.sleep(2)
    second = canonical_manifest(root, maximum_bytes)
    if first["sha256"] != second["sha256"]:
        raise SafetyError("cache contents changed while the stable manifest was being checked")
    return second


def _write_evidence(fields: dict[str, Any]) -> None:
    path = _evidence_path()
    current: dict[str, Any] = {}
    if path.exists():
        current = json.loads(path.read_text(encoding="utf-8"))
    current.update(fields)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(current, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _clean_modules() -> None:
    modules = _modules_path()
    home = _home(create=False)
    if not _inside(modules.resolve(strict=False), home):
        raise SafetyError("refusing to clean a cache outside the isolated Gradle user home")
    if modules.is_symlink():
        raise SafetyError("refusing to follow a module cache symbolic link")
    if modules.exists():
        if modules.is_dir():
            shutil.rmtree(modules)
        else:
            modules.unlink()
    if modules.exists() and any(modules.iterdir()):
        raise SafetyError("module cache is not empty after cleanup")


def command_init_environment(_: argparse.Namespace) -> None:
    root = _task_root(create=True)
    home = root / "gradle-home"
    home.mkdir(parents=True, exist_ok=True)
    fixture_root = root / "fixtures"
    fixture_root.mkdir(parents=True, exist_ok=True)
    values = {
        "GRADLE_USER_HOME": str(home),
        "ROBOLECTRIC_MAVEN_REPO_LOCAL": str(root / "robolectric-m2"),
        "GRADLE_OBSERVER_OUTPUT": str(root / "observer.jsonl"),
        "GRADLE_OBSERVER_SCRIPT": str(home / "init.d" / "gradle-dependency-cache-observer.init.gradle"),
        "GRADLE_FIXTURE_ROOT": str(fixture_root),
        "GRADLE_EVIDENCE_PATH": str(root / "evidence.json"),
        "GRADLE_REDACTED_LOG_PATH": str(root / "runner-log-redacted.txt"),
    }
    os.environ.update(values)
    _append_github_file(_github_file("GITHUB_ENV"), [f"{key}={value}" for key, value in values.items()])
    _write_evidence({
        "schema": 1,
        "campaign_id": os.environ.get("EXPERIMENT_CAMPAIGN_ID", "gradle-dependency-cache-pilot-v1"),
        "run_id": os.environ.get("GITHUB_RUN_ID"),
        "job": os.environ.get("GITHUB_JOB"),
    })
    print(json.dumps({"isolated_home": True, "evidence_initialized": True}, sort_keys=True))


def command_install_observer(args: argparse.Namespace) -> None:
    home = _home(create=True)
    script_source = Path(args.script).resolve(strict=True)
    destination = Path(os.environ["GRADLE_OBSERVER_SCRIPT"])
    _reject_symlink_components(destination, _runner_temp())
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise SafetyError("observer destination already exists")
    shutil.copyfile(script_source, destination)
    output = Path(os.environ["GRADLE_OBSERVER_OUTPUT"])
    if output.exists():
        raise SafetyError("observer output already exists")
    output.touch(mode=0o600)
    robolectric_repo = Path(os.environ["ROBOLECTRIC_MAVEN_REPO_LOCAL"])
    robolectric_repo.mkdir(parents=True, exist_ok=True)
    _write_evidence({"observer_installed_before_gradle": True, "robolectric_repo_isolated": True})
    print(json.dumps({"observer_installed": True}, sort_keys=True))


def command_prepare_empty(_: argparse.Namespace) -> None:
    modules = _modules_path()
    if modules.is_symlink():
        raise SafetyError("module cache is a symbolic link")
    if modules.exists() and (not modules.is_dir() or any(modules.iterdir())):
        raise SafetyError("module cache was not empty before the trial")
    modules.mkdir(parents=True, exist_ok=True)
    print(json.dumps({"modules_2_empty": True}, sort_keys=True))


def command_manifest(args: argparse.Namespace) -> None:
    modules = _modules_path()
    manifest = _stable_manifest(modules, args.maximum_bytes) if args.stable else canonical_manifest(modules, args.maximum_bytes)
    if args.output:
        output_path = Path(args.output).resolve(strict=False)
        if _inside(output_path, modules.resolve(strict=False)):
            raise SafetyError("manifest output must remain outside the cached directory")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    _append_github_file(_github_file("GITHUB_OUTPUT"), [
        f"sha256={manifest['sha256']}",
        f"files={manifest['files']}",
        f"bytes={manifest['bytes']}",
    ])
    _write_evidence({
        "modules_manifest_sha256": manifest["sha256"],
        "modules_manifest_files": manifest["files"],
        "modules_manifest_bytes": manifest["bytes"],
        "modules_manifest_stable": bool(args.stable),
    })
    print(json.dumps({key: manifest[key] for key in ("sha256", "files", "bytes")}, sort_keys=True))


def _restore_is_exact(args: argparse.Namespace) -> bool:
    return (
        args.action_outcome == "success"
        and args.cache_hit == "true"
        and bool(args.primary_key)
        and args.matched_key == args.primary_key
    )


def command_restore_check(args: argparse.Namespace) -> None:
    exact = _restore_is_exact(args)
    if not exact:
        _clean_modules()
        _write_evidence({
            "restore_state": "non_exact_cleaned",
            "restore_action_outcome": args.action_outcome,
            "restore_cache_hit": args.cache_hit,
            "restore_matched_key_present": bool(args.matched_key),
        })
        if args.action_outcome != "success":
            raise SafetyError("restore action failed; the result cannot be classified as a cache miss")
        if args.expected == "exact":
            raise SafetyError("exact cache restore was required but the result was non-exact")
        print(json.dumps({"restore_state": "miss", "modules_2_empty": True}, sort_keys=True))
        return
    if args.expected == "miss":
        _clean_modules()
        raise SafetyError("cache entry unexpectedly existed for a required miss")
    if args.manifest_sha256:
        observed = canonical_manifest(_modules_path(), MODULE_CACHE_LIMIT)
        if observed["sha256"] != args.manifest_sha256:
            _clean_modules()
            _write_evidence({"restore_state": "exact_but_manifest_mismatch", "restored_manifest_sha256": observed["sha256"]})
            raise SafetyError("restored module cache did not match the trusted seed manifest")
    observed = canonical_manifest(_modules_path(), MODULE_CACHE_LIMIT)
    _write_evidence({
        "restore_state": "exact",
        "restore_action_outcome": args.action_outcome,
        "restored_manifest_sha256": observed["sha256"],
        "restored_manifest_files": observed["files"],
        "restored_manifest_bytes": observed["bytes"],
    })
    _append_github_file(_github_file("GITHUB_OUTPUT"), [f"manifest_sha256={observed['sha256']}"])
    print(json.dumps({"restore_state": "exact", "modules_manifest_sha256": observed["sha256"]}, sort_keys=True))


def _snapshot_tree(root: Path) -> dict[str, Any]:
    return canonical_manifest(root, 2 * 1024 * 1024 * 1024)


def command_wrapper_snapshot(args: argparse.Namespace) -> None:
    home = _home(create=False)
    distribution_root = home / "wrapper" / "dists"
    snapshot = _snapshot_tree(distribution_root)
    destination = Path(args.output).resolve(strict=False)
    if _inside(destination, home):
        raise SafetyError("wrapper snapshot must be written outside Gradle user home")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(snapshot, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    _append_github_file(_github_file("GITHUB_OUTPUT"), [
        f"sha256={snapshot['sha256']}",
        f"files={snapshot['files']}",
        f"bytes={snapshot['bytes']}",
    ])
    print(json.dumps({key: snapshot[key] for key in ("sha256", "files", "bytes")}, sort_keys=True))


def command_compare_manifest(args: argparse.Namespace) -> None:
    expected = json.loads(Path(args.expected).read_text(encoding="utf-8"))
    actual = canonical_manifest(_modules_path(), MODULE_CACHE_LIMIT)
    if actual["sha256"] != expected["sha256"]:
        raise SafetyError("canonical module-cache comparison did not match the seed")
    _write_evidence({"seed_manifest_match": True, "seed_manifest_sha256": actual["sha256"]})
    print(json.dumps({"seed_manifest_match": True, "sha256": actual["sha256"]}, sort_keys=True))


def dependency_input_digest(root: Path, mutation: bool = False) -> str:
    selected: list[Path] = []
    ignored = {".git", ".codegraph", ".tokensave", "build", "node_modules"}
    names = {
        "gradle.properties", "gradle-wrapper.properties", "gradle-wrapper.jar",
        "gradle.lockfile", "verification-metadata.xml", "libs.versions.toml",
        "gradlew", "gradlew.bat",
    }
    for directory, subdirectories, filenames in os.walk(root, topdown=True, followlinks=False):
        current = Path(directory)
        subdirectories[:] = [name for name in sorted(subdirectories) if name not in ignored and not (current / name).is_symlink()]
        for filename in filenames:
            path = current / filename
            if path.is_symlink():
                continue
            relative = path.relative_to(root).as_posix()
            if (
                filename in names
                or filename.endswith((".gradle", ".gradle.kts"))
                or relative.endswith("gradle/wrapper/gradle-wrapper.jar")
            ):
                selected.append(path)
    selected.sort(key=lambda path: path.relative_to(root).as_posix())
    if not selected:
        raise SafetyError("no tracked Gradle dependency inputs were found")
    digest = hashlib.sha256()
    mutation_path = root / "android-readiness-probe" / "build.gradle.kts"
    if mutation and mutation_path not in selected:
        raise SafetyError("expected Gradle input for invalidation control is missing")
    for path in selected:
        relative = path.relative_to(root).as_posix()
        content = path.read_bytes()
        if mutation and path == mutation_path:
            content += b"\n// temporary dependency-input invalidation control\n"
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(content)
        digest.update(b"\0")
    return digest.hexdigest()


def command_cache_key(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve(strict=True)
    digest = dependency_input_digest(root, mutation=args.mutate_dependency_input)
    java_identity = java_runtime_identity()
    sdk_root = Path(os.environ.get("ANDROID_HOME", os.environ.get("ANDROID_SDK_ROOT", "")))
    package_files = {
        "platform": sdk_root / "platforms" / "android-36" / "source.properties",
        "build_tools": sdk_root / "build-tools" / "36.0.0" / "source.properties",
    }
    revisions: dict[str, str] = {}
    for name, path in package_files.items():
        if not path.is_file():
            raise SafetyError("cache key cannot be computed before the pinned Android SDK packages are installed")
        revisions[name] = next(
            (line.split("=", 1)[1].strip() for line in path.read_text(encoding="utf-8", errors="replace").splitlines() if line.startswith("Pkg.Revision")),
            "",
        )
        if not revisions[name]:
            raise SafetyError("Android SDK package revision is missing from the cache key")
    architecture = os.environ.get("RUNNER_ARCH", "X64").lower()
    architecture = {"x64": "x64", "arm64": "arm64"}.get(architecture, architecture)
    if architecture not in ("x64", "arm64"):
        raise SafetyError("runner architecture is not recognized")
    vendor_key = java_identity["java_vendor"].lower().replace(" ", "-")
    key = (
        f"argus-gradle-issue93-pilot-v1-linux-{architecture}-temurin-{vendor_key}-"
        f"{java_identity['java_runtime_version']}-gradle-9.1.0-"
        f"cmdline-12266719-sdk36r{revisions['platform']}-bt36.0.0r{revisions['build_tools']}-{digest}"
    )
    if len(key) > 512:
        raise SafetyError("generated cache key exceeds the GitHub key length limit")
    _append_github_file(_github_file("GITHUB_OUTPUT"), [
        f"key={key}",
        f"input_sha256={digest}",
        f"java_runtime_version={java_identity['java_runtime_version']}",
        f"java_vendor={java_identity['java_vendor']}",
    ])
    print(json.dumps({"key": key, "input_sha256": digest, **java_identity}, sort_keys=True))


def command_create_fixture(args: argparse.Namespace) -> None:
    if args.bytes < 1 or args.bytes > FIXTURE_LIMIT:
        raise SafetyError("fixture size must be between one byte and one mebibyte")
    root = Path(os.environ["GRADLE_FIXTURE_ROOT"]).resolve(strict=False)
    destination = root / args.name
    if destination.is_symlink() or not _inside(destination.resolve(strict=False), root):
        raise SafetyError("fixture directory escaped its isolated path")
    destination.mkdir(parents=True, exist_ok=False)
    value = ord(args.value)
    data = bytes([value]) * args.bytes
    (destination / "fixture.bin").write_bytes(data)
    manifest = canonical_manifest(destination, FIXTURE_LIMIT)
    _write_evidence({f"fixture_{args.name}_sha256": manifest["sha256"], f"fixture_{args.name}_bytes": manifest["bytes"]})
    print(json.dumps({"name": args.name, "sha256": manifest["sha256"], "bytes": manifest["bytes"]}, sort_keys=True))


def command_verify_fixture(args: argparse.Namespace) -> None:
    _, source = _fixture_path(args.path)
    manifest = canonical_manifest(source, FIXTURE_LIMIT)
    expected_digest = hashlib.sha256(bytes([ord(args.value)]) * args.bytes).hexdigest()
    entries = manifest["entries"]
    if len(entries) != 1 or entries[0]["path"] != "fixture.bin" or entries[0]["bytes"] != args.bytes:
        raise SafetyError("fixture content did not match its declared shape")
    if _sha256_file(source / "fixture.bin") != expected_digest:
        raise SafetyError("fixture content did not match its expected value")
    print(json.dumps({"fixture_match": True, "sha256": manifest["sha256"]}, sort_keys=True))


def _fixture_path(raw: str) -> tuple[Path, Path]:
    root = Path(os.environ["GRADLE_FIXTURE_ROOT"]).resolve(strict=True)
    candidate = Path(raw)
    if not candidate.is_absolute():
        candidate = root / candidate
    path = Path(os.path.abspath(candidate))
    if not _inside(path, root) or path == root:
        raise SafetyError("fixture path escaped its isolated namespace")
    _reject_symlink_components(path, root)
    return root, path


def _clean_fixture(raw: str) -> None:
    _, path = _fixture_path(raw)
    if path.is_symlink():
        raise SafetyError("refusing to clean a fixture symbolic link")
    if path.exists():
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    if path.exists():
        raise SafetyError("fixture directory remains after cleanup")


def command_fixture_restore_check(args: argparse.Namespace) -> None:
    exact = (
        args.action_outcome == "success"
        and args.cache_hit == "true"
        and bool(args.primary_key)
        and args.matched_key == args.primary_key
    )
    if not exact:
        _clean_fixture(args.path)
        _write_evidence({"fixture_restore_state": "non_exact_cleaned", "fixture_restore_expected": args.expected})
        if args.action_outcome != "success":
            raise SafetyError("fixture restore action failed; the result cannot be classified as a cache miss")
        if args.expected == "exact":
            raise SafetyError("fixture cache restore was not an exact hit")
        print(json.dumps({"fixture_restore_state": "miss", "fixture_path_empty": True}, sort_keys=True))
        return
    if args.expected == "miss":
        _clean_fixture(args.path)
        raise SafetyError("fixture cache entry unexpectedly existed for a required miss")
    _write_evidence({"fixture_restore_state": "exact"})
    print(json.dumps({"fixture_restore_state": "exact"}, sort_keys=True))


def command_fixture_recovery(args: argparse.Namespace) -> None:
    _, path = _fixture_path(args.path)
    artifact = path / "fixture.bin"
    if not artifact.is_file() or artifact.is_symlink():
        raise SafetyError("restored fixture artifact is missing")
    before = _sha256_file(artifact)
    artifact.write_bytes(b"unusable isolated fixture")
    after = _sha256_file(artifact)
    if before == after:
        raise SafetyError("local fixture corruption control did not change content")
    _clean_fixture(args.path)
    _write_evidence({"fixture_corruption_recovery": "local_path_removed", "trusted_cache_modified": False})
    print(json.dumps({"local_fixture_removed": True, "trusted_cache_modified": False}, sort_keys=True))


def command_clean_fixture(args: argparse.Namespace) -> None:
    _clean_fixture(args.path)
    print(json.dumps({"fixture_path_empty": True}, sort_keys=True))


def command_classify_read_only_canary(args: argparse.Namespace) -> None:
    if args.cache_mode != "read":
        raise SafetyError("read-only canary did not run with cache-mode read")
    exact = (
        args.readback_outcome == "success"
        and args.cache_hit == "true"
        and bool(args.primary_key)
        and args.matched_key == args.primary_key
    )
    if args.readback_outcome != "success":
        classification = "readback_failed_unclassified"
        _write_evidence({"read_only_canary_classification": classification, "cache_service_denial_claimed": False})
        raise SafetyError("read-only cache canary readback action failed")
    if exact:
        classification = "unexpected_readable_write"
        _write_evidence({"read_only_canary_classification": classification, "cache_service_denial_claimed": False})
        raise SafetyError("read-only cache canary became readable after the save attempt")
    if args.save_outcome == "failure":
        classification = "save_action_failure_unclassified"
    elif args.save_outcome in ("success", "skipped"):
        classification = "action_level_skip_read_mode"
    else:
        classification = "unclassified"
    _write_evidence({
        "read_only_canary_classification": classification,
        "read_only_canary_save_step_outcome": args.save_outcome,
        "read_only_canary_readback": "miss",
        "cache_service_denial_claimed": False,
    })
    if classification != "action_level_skip_read_mode":
        raise SafetyError("read-only canary result did not match the documented action-level skip")
    print(json.dumps({"classification": classification, "cache_service_denial_claimed": False}, sort_keys=True))


def command_validate_failed_writer(args: argparse.Namespace) -> None:
    expected = {
        "restore": args.restore_outcome == "success",
        "fixture": args.fixture_outcome == "success",
        "intentional_failure": args.failure_outcome == "failure",
        "save_skipped": args.save_outcome == "skipped",
    }
    _write_evidence({
        "failed_writer_expected_failure": all(expected.values()),
        "failed_writer_setup_outcomes": expected,
        "failed_writer_key_saved": False,
    })
    if not all(expected.values()):
        raise SafetyError("failed-writer controls did not produce the expected isolated failure")
    _append_github_file(_github_file("GITHUB_OUTPUT"), ["expected_failure=true"])
    print(json.dumps({"expected_failure": True, "failed_writer_key_saved": False}, sort_keys=True))


def command_record_fault_unsupported(_: argparse.Namespace) -> None:
    _write_evidence({"cache_service_fault_test": "not_safely_demonstrable", "trusted_cache_corrupted": False})
    print(json.dumps({"cache_service_fault_test": "not_safely_demonstrable"}, sort_keys=True))


def command_record_collision(args: argparse.Namespace) -> None:
    evidence: dict[str, Any] = {"collision_save_action_outcome": args.save_outcome}
    if args.readback_outcome:
        if args.readback_outcome != "success":
            raise SafetyError("collision cache readback action failed")
        root = Path(os.environ["GRADLE_FIXTURE_ROOT"]).resolve(strict=True)
        artifact = root / "collision" / "fixture.bin"
        expected = hashlib.sha256(b"A" * 65536).hexdigest()
        if not artifact.is_file() or artifact.is_symlink() or _sha256_file(artifact) != expected:
            raise SafetyError("collision readback did not preserve fixture A")
        evidence["collision_readback_fixture_a_survived"] = True
        evidence["collision_readback_sha256"] = expected
    _write_evidence(evidence)
    print(json.dumps(evidence, sort_keys=True))


def command_clean_modules(_: argparse.Namespace) -> None:
    _clean_modules()
    _write_evidence({"modules_2_cleanup_verified": True})
    print(json.dumps({"modules_2_empty": True}, sort_keys=True))


def command_simulate_partial(_: argparse.Namespace) -> None:
    modules = _modules_path()
    if modules.exists():
        raise SafetyError("partial extraction fixture requires a fresh module-cache path")
    partial = modules / "files" / "partial-entry.bin"
    partial.parent.mkdir(parents=True)
    partial.write_bytes(b"partial archive extraction")
    _write_evidence({"partial_cache_fixture_created": True})
    print(json.dumps({"partial_fixture_created": True}, sort_keys=True))


def command_verify_observer(args: argparse.Namespace) -> None:
    output = Path(os.environ["GRADLE_OBSERVER_OUTPUT"])
    records: list[dict[str, Any]] = []
    parse_errors = 0
    if output.exists():
        for line in output.read_text(encoding="utf-8").splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                parse_errors += 1
    ready = sum(record.get("event") == "observer_ready" for record in records)
    observer_errors = sum(record.get("event") == "observer_error" for record in records) + parse_errors
    reads = [record for record in records if record.get("event") == "external_resource_read"]
    body_reads = [record for record in reads if record.get("artifact_body") is True]
    completed_body_bytes = sum(
        record.get("bytes_read", 0)
        for record in body_reads
        if record.get("bytes_read_known") is True and record.get("result_state") == "completed"
    )
    unknown_body_reads = sum(record.get("bytes_read_known") is not True for record in body_reads)
    errored_body_reads = sum(record.get("result_state") in ("error", "incomplete") for record in body_reads)
    if ready < 1:
        raise SafetyError("Gradle observer did not report that it was armed")
    if observer_errors:
        raise SafetyError("Gradle observer reported malformed or undecodable events")
    if args.mode in ("cold", "fixture") and completed_body_bytes <= 0:
        raise SafetyError("cold observation did not prove a completed artifact-body transfer")
    if args.mode == "warm" and body_reads:
        raise SafetyError("warm observation could not prove the absence of artifact-body transfers")
    summary = {
        "observer_ready_count": ready,
        "external_resource_reads": len(reads),
        "artifact_body_events": len(body_reads),
        "artifact_body_bytes": completed_body_bytes,
        "artifact_body_unknown_events": unknown_body_reads,
        "artifact_body_error_events": errored_body_reads,
        "observer_errors": observer_errors,
        "observer_mode": args.mode,
    }
    _write_evidence(summary)
    _append_github_file(_github_file("GITHUB_OUTPUT"), [
        f"artifact_body_bytes={completed_body_bytes}",
        f"artifact_body_events={len(body_reads)}",
        f"observer_errors={observer_errors}",
    ])
    print(json.dumps(summary, sort_keys=True))


def command_robolectric_snapshot(args: argparse.Namespace) -> None:
    root = _task_root(create=False)
    repo = Path(os.environ["ROBOLECTRIC_MAVEN_REPO_LOCAL"]).resolve(strict=False)
    if not _inside(repo, root) or _inside(repo, _modules_path()):
        raise SafetyError("Robolectric repository is not isolated from the Gradle module cache")
    snapshot = canonical_manifest(repo, MODULE_CACHE_LIMIT)
    output = root / f"robolectric-{args.phase}.json"
    output.write_text(json.dumps(snapshot, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    if args.phase == "before":
        if snapshot["files"]:
            raise SafetyError("isolated Robolectric repository was not empty before the trial")
        _write_evidence({"robolectric_repo_initial_files": snapshot["files"], "robolectric_repo_initial_bytes": snapshot["bytes"]})
        print(json.dumps({"files": snapshot["files"], "bytes": snapshot["bytes"]}, sort_keys=True))
        return

    before_path = root / "robolectric-before.json"
    if not before_path.exists():
        raise SafetyError("initial Robolectric repository snapshot is missing")
    before = json.loads(before_path.read_text(encoding="utf-8"))
    prior = {entry["path"]: entry for entry in before["entries"]}
    now = {entry["path"]: entry for entry in snapshot["entries"]}
    added = [entry for name, entry in now.items() if name not in prior]
    changed = [entry for name, entry in now.items() if name in prior and entry["sha256"] != prior[name]["sha256"]]
    persisted = []
    for entry in added + changed:
        relative = entry["path"]
        persisted.append({
            "path_sha256": hashlib.sha256(relative.encode("utf-8")).hexdigest(),
            "suffix": Path(relative).suffix.lower(),
            "bytes": entry["bytes"],
            "content_sha256": entry["sha256"],
            "robolectric_runtime_group": relative.startswith("org/robolectric/"),
            "robolectric_sdk_group": relative.startswith("org/robolectric/android-all-instrumented/"),
            "target_native_runtime_1_0_18": relative.startswith("org/robolectric/nativeruntime-dist-compat/1.0.18/"),
        })
    redacted = root / "robolectric-artifacts-redacted.json"
    redacted.write_text(json.dumps({"source": "isolated_maven_repo_file_delta", "files": persisted}, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    target_count = sum(item["target_native_runtime_1_0_18"] for item in persisted)
    _write_evidence({
        "robolectric_repo_final_files": snapshot["files"],
        "robolectric_repo_final_bytes": snapshot["bytes"],
        "robolectric_new_persisted_files": len(added),
        "robolectric_changed_persisted_files": len(changed),
        "robolectric_new_persisted_bytes": sum(entry["bytes"] for entry in added),
        "robolectric_observation_kind": "isolated_repository_file_delta",
        "robolectric_target_native_runtime_1_0_18_files": target_count,
        "robolectric_artifact_manifest_redacted": True,
        "robolectric_no_persisted_files_is_not_zero_transfer_claim": True,
    })
    print(json.dumps({
        "final_files": snapshot["files"],
        "new_files": len(added),
        "changed_files": len(changed),
        "new_bytes": sum(entry["bytes"] for entry in added),
    }, sort_keys=True))


def command_capture_evidence(_: argparse.Namespace) -> None:
    path = _evidence_path()
    if not path.exists():
        path.write_text("{}\n", encoding="utf-8")
    print(path.read_text(encoding="utf-8"), end="")


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Guard the isolated Gradle dependency-cache experiment.")
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init-environment")
    init.set_defaults(func=command_init_environment)

    install = sub.add_parser("install-observer")
    install.add_argument("--script", required=True)
    install.set_defaults(func=command_install_observer)

    sub.add_parser("prepare-empty").set_defaults(func=command_prepare_empty)

    manifest = sub.add_parser("manifest")
    manifest.add_argument("--stable", action="store_true")
    manifest.add_argument("--maximum-bytes", type=int, default=MODULE_CACHE_LIMIT)
    manifest.add_argument("--output")
    manifest.set_defaults(func=command_manifest)

    restore = sub.add_parser("restore-check")
    restore.add_argument("--expected", choices=("exact", "miss"), required=True)
    restore.add_argument("--action-outcome", required=True)
    restore.add_argument("--cache-hit", default="")
    restore.add_argument("--matched-key", default="")
    restore.add_argument("--primary-key", default="")
    restore.add_argument("--manifest-sha256", default="")
    restore.set_defaults(func=command_restore_check)

    wrapper = sub.add_parser("wrapper-snapshot")
    wrapper.add_argument("--output", required=True)
    wrapper.set_defaults(func=command_wrapper_snapshot)

    compare = sub.add_parser("compare-manifest")
    compare.add_argument("--expected", required=True)
    compare.set_defaults(func=command_compare_manifest)

    key = sub.add_parser("cache-key")
    key.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    key.add_argument("--mutate-dependency-input", action="store_true")
    key.set_defaults(func=command_cache_key)

    fixture = sub.add_parser("create-fixture")
    fixture.add_argument("--name", required=True)
    fixture.add_argument("--value", choices=("A", "B", "C"), required=True)
    fixture.add_argument("--bytes", type=int, default=65536)
    fixture.set_defaults(func=command_create_fixture)

    verify = sub.add_parser("verify-fixture")
    verify.add_argument("--path", required=True)
    verify.add_argument("--value", choices=("A", "B", "C"), required=True)
    verify.add_argument("--bytes", type=int, default=65536)
    verify.set_defaults(func=command_verify_fixture)

    fixture_restore = sub.add_parser("fixture-restore-check")
    fixture_restore.add_argument("--path", required=True)
    fixture_restore.add_argument("--expected", choices=("exact", "miss"), required=True)
    fixture_restore.add_argument("--action-outcome", required=True)
    fixture_restore.add_argument("--cache-hit", default="")
    fixture_restore.add_argument("--matched-key", default="")
    fixture_restore.add_argument("--primary-key", default="")
    fixture_restore.set_defaults(func=command_fixture_restore_check)

    recovery = sub.add_parser("fixture-recovery")
    recovery.add_argument("--path", required=True)
    recovery.set_defaults(func=command_fixture_recovery)

    clean_fixture = sub.add_parser("clean-fixture")
    clean_fixture.add_argument("--path", required=True)
    clean_fixture.set_defaults(func=command_clean_fixture)

    canary = sub.add_parser("classify-read-only-canary")
    canary.add_argument("--cache-mode", required=True)
    canary.add_argument("--save-outcome", required=True)
    canary.add_argument("--readback-outcome", required=True)
    canary.add_argument("--cache-hit", default="")
    canary.add_argument("--matched-key", default="")
    canary.add_argument("--primary-key", default="")
    canary.set_defaults(func=command_classify_read_only_canary)

    failed = sub.add_parser("validate-failed-writer")
    failed.add_argument("--restore-outcome", required=True)
    failed.add_argument("--fixture-outcome", required=True)
    failed.add_argument("--failure-outcome", required=True)
    failed.add_argument("--save-outcome", required=True)
    failed.set_defaults(func=command_validate_failed_writer)

    sub.add_parser("record-fault-unsupported").set_defaults(func=command_record_fault_unsupported)

    collision = sub.add_parser("record-collision")
    collision.add_argument("--save-outcome", required=True)
    collision.add_argument("--readback-outcome", default="")
    collision.set_defaults(func=command_record_collision)

    sub.add_parser("clean-modules").set_defaults(func=command_clean_modules)
    sub.add_parser("simulate-partial").set_defaults(func=command_simulate_partial)
    observer = sub.add_parser("verify-observer")
    observer.add_argument("--mode", choices=("cold", "warm", "fixture"), required=True)
    observer.set_defaults(func=command_verify_observer)
    robolectric = sub.add_parser("robolectric-snapshot")
    robolectric.add_argument("--phase", choices=("before", "after"), required=True)
    robolectric.set_defaults(func=command_robolectric_snapshot)
    sub.add_parser("capture-evidence").set_defaults(func=command_capture_evidence)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except (OSError, ValueError, SafetyError, KeyError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
