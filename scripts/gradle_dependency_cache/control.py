"""Guard the pilot's cache paths and write redacted evidence.

All experiment state lives under ``RUNNER_TEMP``. Only ``caches/modules-2`` is
eligible for the dependency cache; wrapper distributions, Robolectric artifacts,
build outputs, and bounded control fixtures stay in separate paths.
"""

from __future__ import annotations

import argparse
import base64
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
ROBOLECTRIC_TARGET_COORDINATE = "org.robolectric:nativeruntime-dist-compat:1.0.18"
QUALIFIED_GRADLE_INVOCATION_LABELS = frozenset({"task_inventory", "dry_run", "probe_build"})
OBSERVER_FIXTURE_INVOCATION_LABELS = frozenset({"fixture_cold"})
CORRELATABLE_GRADLE_INVOCATION_LABELS = (
    QUALIFIED_GRADLE_INVOCATION_LABELS | OBSERVER_FIXTURE_INVOCATION_LABELS
)
ROBOLECTRIC_TARGET_PATH = Path("files-2.1/org.robolectric/nativeruntime-dist-compat/1.0.18")
ROBOLECTRIC_TARGET_FILENAME = "nativeruntime-dist-compat-1.0.18.jar"
REQUIRED_GRADLE_TASKS = ("testProbeUnitTest", "lintProbe", "assembleProbe")


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
    """Validate the complete archive path while separately selecting digest inputs."""
    if root.is_symlink():
        raise SafetyError("archive root is a symbolic link")
    try:
        root_metadata = root.lstat()
    except FileNotFoundError:
        root_metadata = None
    if root_metadata is not None and not stat.S_ISDIR(root_metadata.st_mode):
        raise SafetyError("archive root is not a directory")

    entries: list[dict[str, Any]] = []
    expanded_bytes = 0
    if root_metadata is not None:
        resolved_root = root.resolve(strict=True)

        def fail_on_walk_error(error: OSError) -> None:
            raise SafetyError("cache archive could not be fully inspected") from error

        for directory, names, filenames in os.walk(
            resolved_root, topdown=True, followlinks=False, onerror=fail_on_walk_error,
        ):
            current = Path(directory)
            safe_names = []
            for name in sorted(names):
                child = current / name
                metadata = child.lstat()
                if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                    raise SafetyError("cache archive contains a symbolic link or non-directory entry")
                safe_names.append(name)
            names[:] = safe_names
            for name in sorted(filenames):
                path = current / name
                metadata = path.lstat()
                if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                    raise SafetyError("cache archive contains a symbolic link or non-regular file")
                expanded_bytes += metadata.st_size
                if expanded_bytes > maximum_bytes:
                    raise SafetyError("expanded cache archive exceeds its configured byte limit")
                relative = path.relative_to(resolved_root)
                if _excluded(relative):
                    continue
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
        "expanded_bytes": expanded_bytes,
        "entries": entries,
    }


def _stable_manifest(root: Path, maximum_bytes: int) -> dict[str, Any]:
    first = canonical_manifest(root, maximum_bytes)
    time.sleep(2)
    second = canonical_manifest(root, maximum_bytes)
    if first["sha256"] != second["sha256"] or first["expanded_bytes"] != second["expanded_bytes"]:
        raise SafetyError("cache contents or archive size changed while the stable manifest was being checked")
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
        f"expanded_bytes={manifest['expanded_bytes']}",
    ])
    _write_evidence({
        "modules_manifest_sha256": manifest["sha256"],
        "modules_manifest_files": manifest["files"],
        "modules_manifest_bytes": manifest["bytes"],
        "modules_archive_expanded_bytes": manifest["expanded_bytes"],
        "modules_manifest_stable": bool(args.stable),
    })
    print(json.dumps({key: manifest[key] for key in ("sha256", "files", "bytes", "expanded_bytes")}, sort_keys=True))


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


def command_write_seed_record(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve(strict=True)
    task_root = _task_root(create=True).resolve(strict=True)
    if not _inside(manifest_path, task_root) or _inside(manifest_path, _modules_path()):
        raise SafetyError("trusted seed manifest must remain in isolated evidence storage")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    cache_key = args.cache_key
    source_sha = os.environ.get("GITHUB_SHA", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "")
    branch = os.environ.get("GITHUB_REF", "")
    campaign_id = os.environ.get("EXPERIMENT_CAMPAIGN_ID", "")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise SafetyError("trusted seed source commit is invalid")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id) or run_attempt != "1":
        raise SafetyError("trusted seed run identity is invalid")
    if branch != "refs/heads/codex/issue-93-gradle-cache-pilot":
        raise SafetyError("trusted seed must come from the exact pilot branch")
    if campaign_id != "gradle-dependency-cache-pilot-v1":
        raise SafetyError("trusted seed campaign identity is invalid")
    if not re.fullmatch(r"[A-Za-z0-9_.+-]{1,512}", cache_key):
        raise SafetyError("trusted seed cache key is invalid")
    files = manifest.get("files")
    digest_bytes = manifest.get("bytes")
    expanded_bytes = manifest.get("expanded_bytes")
    if manifest.get("format") != 1:
        raise SafetyError("trusted seed manifest format is invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("sha256", ""))):
        raise SafetyError("trusted seed manifest digest is invalid")
    if (
        not isinstance(files, int) or isinstance(files, bool) or files < 0
        or not isinstance(digest_bytes, int) or isinstance(digest_bytes, bool) or digest_bytes < 0
        or not isinstance(expanded_bytes, int) or isinstance(expanded_bytes, bool)
        or expanded_bytes < digest_bytes or expanded_bytes > MODULE_CACHE_LIMIT
    ):
        raise SafetyError("trusted seed archive exceeded the expanded-size limit")

    record = {
        "schema": 1,
        "campaign_id": campaign_id,
        "seed_run_id": run_id,
        "seed_run_attempt": int(run_attempt),
        "seed_source_sha": source_sha,
        "seed_branch": branch,
        "cache_key": cache_key,
        "manifest_sha256": manifest["sha256"],
        "manifest_files": files,
        "manifest_bytes": digest_bytes,
        "archive_expanded_bytes": expanded_bytes,
    }
    destination = Path(args.output).resolve(strict=False)
    if not _inside(destination, task_root) or _inside(destination, _modules_path()):
        raise SafetyError("trusted seed record must remain outside the cache archive path")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(record, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    _write_evidence({"trusted_seed_record_sha256": hashlib.sha256(destination.read_bytes()).hexdigest()})
    print(json.dumps({"seed_record_written": True, "manifest_sha256": record["manifest_sha256"]}, sort_keys=True))


def command_verify_seed_record(args: argparse.Namespace) -> None:
    path = Path(args.path).resolve(strict=True)
    record = json.loads(path.read_text(encoding="utf-8"))
    expected_source = args.expected_source_sha
    expected_key = args.expected_cache_key
    if record.get("schema") != 1 or record.get("campaign_id") != "gradle-dependency-cache-pilot-v1":
        raise SafetyError("downloaded trusted seed record has an unexpected schema or campaign")
    if record.get("seed_branch") != "refs/heads/codex/issue-93-gradle-cache-pilot":
        raise SafetyError("downloaded trusted seed record came from another branch")
    if record.get("seed_source_sha") != expected_source or not re.fullmatch(r"[0-9a-f]{40}", expected_source):
        raise SafetyError("downloaded trusted seed record does not match the PR head")
    if record.get("cache_key") != expected_key:
        raise SafetyError("PR dependency-input key differs from the trusted seed key")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", str(record.get("seed_run_id", ""))) or record.get("seed_run_attempt") != 1:
        raise SafetyError("downloaded trusted seed record has an invalid run identity")
    if record.get("seed_run_id") != args.expected_run_id:
        raise SafetyError("downloaded trusted seed record does not belong to the resolved seed run")
    if not re.fullmatch(r"[0-9a-f]{64}", str(record.get("manifest_sha256", ""))):
        raise SafetyError("downloaded trusted seed record has an invalid manifest digest")
    expanded_bytes = record.get("archive_expanded_bytes")
    if (
        not isinstance(expanded_bytes, int) or isinstance(expanded_bytes, bool)
        or expanded_bytes < 0 or expanded_bytes > MODULE_CACHE_LIMIT
    ):
        raise SafetyError("downloaded trusted seed record exceeds the archive limit")
    manifest_files = record.get("manifest_files")
    manifest_bytes = record.get("manifest_bytes")
    if (
        not isinstance(manifest_files, int) or isinstance(manifest_files, bool) or manifest_files < 0
        or not isinstance(manifest_bytes, int) or isinstance(manifest_bytes, bool)
        or manifest_bytes < 0 or manifest_bytes > expanded_bytes
    ):
        raise SafetyError("downloaded trusted seed record has invalid manifest counts")
    _write_evidence({
        "trusted_seed_run_id": record["seed_run_id"],
        "trusted_seed_run_attempt": record["seed_run_attempt"],
        "trusted_seed_source_sha": record["seed_source_sha"],
        "trusted_seed_cache_key": record["cache_key"],
        "trusted_seed_manifest_sha256": record["manifest_sha256"],
    })
    _append_github_file(_github_file("GITHUB_OUTPUT"), [
        f"seed_run_id={record['seed_run_id']}",
        f"seed_source_sha={record['seed_source_sha']}",
        f"manifest_sha256={record['manifest_sha256']}",
    ])
    print(json.dumps({"trusted_seed_record_verified": True, "manifest_sha256": record["manifest_sha256"]}, sort_keys=True))


def _workflow_runs_from_pages(pages: Any) -> list[dict[str, Any]]:
    if not isinstance(pages, list):
        raise SafetyError("workflow history pagination has an unexpected shape")
    runs: list[dict[str, Any]] = []
    for page in pages:
        if not isinstance(page, dict) or not isinstance(page.get("workflow_runs"), list):
            raise SafetyError("workflow history page is missing its workflow runs")
        if any(not isinstance(run, dict) for run in page["workflow_runs"]):
            raise SafetyError("workflow history contains a malformed run")
        runs.extend(page["workflow_runs"])
    return runs


def resolve_seed_campaign(
    seed_pages: Any,
    pr_pages: Any,
    *,
    head_sha: str,
    pr_number: str,
    current_run_id: str,
) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", head_sha):
        raise SafetyError("PR head SHA is invalid for seed-campaign selection")
    if not re.fullmatch(r"[0-9]+", pr_number):
        raise SafetyError("PR number is invalid for seed-campaign selection")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", current_run_id):
        raise SafetyError("current workflow run ID is invalid")

    prior_consumers = []
    for run in _workflow_runs_from_pages(pr_pages):
        if run.get("event") != "pull_request" or str(run.get("id", "")) == current_run_id:
            continue
        pull_requests = run.get("pull_requests")
        if not isinstance(pull_requests, list):
            raise SafetyError("PR workflow history has no pull-request association list")
        matched = False
        for pull_request in pull_requests:
            if not isinstance(pull_request, dict):
                raise SafetyError("PR workflow history contains a malformed pull-request association")
            head = pull_request.get("head", {})
            if not isinstance(head, dict):
                raise SafetyError("PR workflow history contains a malformed head identity")
            if (
                str(pull_request.get("number", "")) == pr_number
                or head.get("sha") == head_sha
            ):
                matched = True
                break
        if not pull_requests and run.get("head_branch") == "codex/issue-93-gradle-cache-pilot":
            matched = True
        if matched:
            prior_consumers.append(run)
    if prior_consumers:
        raise SafetyError("a PR consumer campaign already exists for this PR or head")

    seed_campaigns = [
        run for run in _workflow_runs_from_pages(seed_pages)
        if run.get("event") == "push"
        and run.get("head_branch") == "codex/issue-93-gradle-cache-pilot"
        and run.get("head_sha") == head_sha
    ]
    if len(seed_campaigns) != 1:
        raise SafetyError("expected exactly one seed campaign for this PR head")
    campaign = seed_campaigns[0]
    if (
        campaign.get("run_attempt") != 1
        or campaign.get("status") != "completed"
        or campaign.get("conclusion") != "success"
    ):
        raise SafetyError("the one seed campaign did not succeed on its first attempt")
    run_id = str(campaign.get("id", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
        raise SafetyError("the trusted seed workflow run ID is invalid")
    return run_id


def command_select_seed_run(args: argparse.Namespace) -> None:
    seed_pages = json.loads(Path(args.seed_runs).read_text(encoding="utf-8"))
    pr_pages = json.loads(Path(args.pr_runs).read_text(encoding="utf-8"))
    run_id = resolve_seed_campaign(
        seed_pages,
        pr_pages,
        head_sha=args.head_sha,
        pr_number=args.pr_number,
        current_run_id=args.current_run_id,
    )
    _append_github_file(_github_file("GITHUB_OUTPUT"), [f"run_id={run_id}"])
    print(json.dumps({"seed_run_id": run_id, "seed_run_attempt": 1}, sort_keys=True))


def command_record_pr_identities(args: argparse.Namespace) -> None:
    checkout = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=Path(__file__).resolve().parents[2],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    checked_out_sha = checkout.stdout.strip()
    identities = {
        "pr_head_sha": args.head_sha,
        "pr_base_sha": args.base_sha,
        "pr_merge_sha": args.merge_sha,
        "pr_github_sha": args.github_sha,
        "checked_out_source_sha": checked_out_sha,
        "trusted_seed_source_sha": args.seed_source_sha,
        "trusted_seed_run_id": args.seed_run_id,
    }
    if checkout.returncode or not re.fullmatch(r"[0-9a-f]{40}", checked_out_sha):
        raise SafetyError("checked-out PR source identity could not be read")
    if identities["pr_head_sha"] != checked_out_sha or identities["trusted_seed_source_sha"] != args.head_sha:
        raise SafetyError("PR checkout, head, and trusted seed source do not identify the same commit")
    for field in ("pr_head_sha", "pr_base_sha", "pr_github_sha"):
        if not re.fullmatch(r"[0-9a-f]{40}", identities[field]):
            raise SafetyError(f"{field} is unavailable or malformed")
    if identities["pr_merge_sha"] and not re.fullmatch(r"[0-9a-f]{40}", identities["pr_merge_sha"]):
        raise SafetyError("PR merge identity is malformed")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", identities["trusted_seed_run_id"]):
        raise SafetyError("trusted seed run identity is malformed")
    identities["pr_merge_sha_available"] = bool(identities["pr_merge_sha"])
    _write_evidence(identities)
    print(json.dumps(identities, sort_keys=True))


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
        f"argus-gradle-dependency-cache-pilot-v1-linux-{architecture}-temurin-{vendor_key}-"
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


def _decode_effective_cache_mode(available: str, value_base64: str) -> tuple[bool, str | None]:
    if available not in ("true", "false"):
        raise SafetyError("effective ACTIONS_CACHE_MODE availability flag is invalid")
    try:
        value = base64.b64decode(value_base64, validate=True).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as error:
        raise SafetyError("effective ACTIONS_CACHE_MODE capture is malformed") from error
    if available == "false":
        if value:
            raise SafetyError("unavailable ACTIONS_CACHE_MODE capture unexpectedly contains a value")
        return False, None
    return True, value


def command_classify_read_only_canary(args: argparse.Namespace) -> None:
    if args.cache_mode != "read":
        raise SafetyError("read-only canary did not run with cache-mode read")
    mode_available, effective_mode = _decode_effective_cache_mode(
        args.effective_cache_mode_available,
        args.effective_cache_mode_value_base64,
    )
    readback = {
        "restore_step_outcome": args.readback_outcome,
        "check_step_outcome": args.readback_check_outcome,
        "cache_hit": args.cache_hit,
        "matched_key": args.matched_key,
        "primary_key": args.primary_key,
        "matched_primary_key": bool(args.matched_key) and args.matched_key == args.primary_key,
    }
    run_id = os.environ.get("GITHUB_RUN_ID")
    run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT")
    server_url = os.environ.get("GITHUB_SERVER_URL")
    repository = os.environ.get("GITHUB_REPOSITORY")
    run_attempt_url = None
    if server_url and repository and run_id and run_attempt:
        run_attempt_url = (
            f"{server_url.rstrip('/')}/{repository}/actions/runs/{run_id}/attempts/{run_attempt}"
        )
    common_evidence = {
        "read_only_canary_configured_cache_mode": args.cache_mode,
        "read_only_canary_effective_actions_cache_mode_available": mode_available,
        "read_only_canary_effective_actions_cache_mode": effective_mode,
        "read_only_canary_save_step_id": "canary_save",
        "read_only_canary_save_step_outcome": args.save_outcome,
        "read_only_canary_readback_evidence": readback,
        "read_only_canary_action_log_identity": {
            "server_url": server_url,
            "repository": repository,
            "workflow_ref": os.environ.get("GITHUB_WORKFLOW_REF"),
            "workflow_sha": os.environ.get("GITHUB_WORKFLOW_SHA"),
            "run_id": run_id,
            "run_attempt": run_attempt,
            "job": os.environ.get("GITHUB_JOB"),
            "step_id": "canary_save",
            "step_name": "Attempt a save under explicit read-only cache access",
            "run_attempt_url": run_attempt_url,
        },
        "read_only_canary_run_identity": {
            "run_id": run_id,
            "run_attempt": run_attempt,
            "job": os.environ.get("GITHUB_JOB"),
        },
        "cache_service_denial_claimed": False,
        "action_level_skip_claimed": False,
    }

    def record(classification: str, *, resolved: bool, inspect_action_log: bool = False) -> None:
        _write_evidence({
            **common_evidence,
            "read_only_canary_classification": classification,
            "read_only_canary_outcome_resolved": resolved,
            "read_only_canary_action_log_inspection_required": inspect_action_log,
        })

    def fail(classification: str, message: str) -> None:
        record(classification, resolved=False)
        raise SafetyError(message)

    if args.readback_outcome != "success":
        fail("readback_failed_unclassified", "read-only cache canary readback action failed")
    if args.readback_check_outcome != "success":
        fail("readback_check_failed", "read-only cache canary readback check failed")
    if not args.primary_key:
        fail("readback_non_exact_unclassified", "read-only cache canary readback omitted its primary key")
    if args.cache_hit == "true":
        if args.matched_key == args.primary_key:
            fail("unexpected_readable_write", "read-only cache canary became readable after the save attempt")
        fail("readback_non_exact_unclassified", "read-only cache canary reported a hit with a contradictory matched key")
    if args.cache_hit != "false" or args.matched_key:
        fail("readback_non_exact_unclassified", "read-only cache canary readback was not a confirmed miss")
    if mode_available and effective_mode != args.cache_mode:
        fail("effective_cache_mode_mismatch", "effective ACTIONS_CACHE_MODE did not match the configured read mode")

    if args.save_outcome == "success":
        classification = "save_succeeded_readback_miss_unresolved"
        record(classification, resolved=False, inspect_action_log=True)
    elif args.save_outcome == "skipped":
        classification = "save_step_skipped_readback_miss"
        record(classification, resolved=True)
    elif args.save_outcome == "failure":
        fail("save_step_failed_readback_miss", "read-only canary save step failed")
    else:
        fail("save_step_outcome_unavailable", "read-only canary save step outcome was unavailable")
    print(json.dumps({
        "classification": classification,
        "action_log_inspection_required": args.save_outcome == "success",
        "cache_service_denial_claimed": False,
        "action_level_skip_claimed": False,
    }, sort_keys=True))


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


def command_partial_cleanup_failure(_: argparse.Namespace) -> None:
    modules = _modules_path()
    protected_directory = modules / "files"
    if not protected_directory.is_dir() or protected_directory.is_symlink():
        raise SafetyError("partial cleanup fixture is missing its expected directory")
    original_mode = stat.S_IMODE(protected_directory.stat(follow_symlinks=False).st_mode)
    protected_directory.chmod(0o500)
    failure: OSError | None = None
    try:
        _clean_modules()
    except OSError as error:
        failure = error
    finally:
        protected_directory.chmod(original_mode)
    if failure is None:
        raise SafetyError("partial cleanup unexpectedly succeeded; the failure control was not exercised")
    if not modules.is_dir():
        raise SafetyError("failed cleanup did not leave the partial cache available for the gate check")
    _write_evidence({
        "partial_cleanup_outcome": "expected_failure",
        "partial_cleanup_error_kind": type(failure).__name__,
        "partial_cache_retained_after_failure": True,
    })
    raise SafetyError("controlled partial-cache cleanup failed; fallback must remain blocked")


def command_verify_partial_sentinel(args: argparse.Namespace) -> None:
    marker = Path(args.marker).resolve(strict=False)
    task_root = _task_root(create=True).resolve(strict=True)
    if not _inside(marker, task_root) or marker.is_symlink():
        raise SafetyError("Gradle sentinel marker escaped isolated evidence storage")
    prior = json.loads(_evidence_path().read_text(encoding="utf-8"))
    if (
        prior.get("partial_cleanup_outcome") != "expected_failure"
        or prior.get("partial_cache_retained_after_failure") is not True
        or args.cleanup_outcome != "failure"
        or args.sentinel_outcome != "skipped"
        or marker.exists()
    ):
        _write_evidence({
            "partial_cleanup_outcome": args.cleanup_outcome,
            "gradle_sentinel_outcome": args.sentinel_outcome,
            "gradle_sentinel_blocked": False,
        })
        raise SafetyError("Gradle fallback sentinel was not proven blocked after cleanup failure")
    _write_evidence({
        "gradle_sentinel_outcome": args.sentinel_outcome,
        "gradle_sentinel_marker_absent": True,
        "gradle_sentinel_blocked": True,
    })
    print(json.dumps({"cleanup_failure_gated_gradle_sentinel": True}, sort_keys=True))


def read_observer_records(output: Path) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    parse_errors = 0
    if output.exists():
        for line in output.read_text(encoding="utf-8").splitlines():
            try:
                value = json.loads(line)
                if not isinstance(value, dict):
                    parse_errors += 1
                    continue
                records.append(value)
            except json.JSONDecodeError:
                parse_errors += 1
    return records, parse_errors


def validate_observer_invocation(
    records: list[dict[str, Any]], invocation_id: str, label: str = "",
) -> dict[str, Any]:
    if not invocation_id:
        raise SafetyError("measured Gradle invocation has no identity")
    selected = [record for record in records if record.get("invocation_id") == invocation_id]
    starts = [record for record in selected if record.get("event") == "runner_invocation_start"]
    finishes = [record for record in selected if record.get("event") == "runner_invocation_finish"]
    ready = [record for record in selected if record.get("event") == "observer_ready"]
    errors = [record for record in selected if record.get("event") == "observer_error"]
    if len(starts) != 1 or len(finishes) != 1 or len(ready) != 1:
        raise SafetyError("measured Gradle invocation lacks one-to-one start, readiness, or finish evidence")
    if label and any(
        record.get("label", record.get("invocation_label", "")) != label
        for record in (starts[0], finishes[0], ready[0])
    ):
        raise SafetyError("observer readiness or runner markers do not match the invocation label")
    if finishes[0].get("exit_code") != 0:
        raise SafetyError("measured Gradle invocation did not finish successfully")
    if errors:
        raise SafetyError("Gradle observer reported an invocation-scoped error")
    if label and any(
        record.get("invocation_label") != label
        for record in selected
        if record.get("event") in ("external_resource_start", "external_resource_read", "observer_error")
    ):
        raise SafetyError("observer transfer record is bound to the wrong invocation label")
    if any(record.get("event") == "external_resource_read" and not record.get("invocation_id") for record in records):
        raise SafetyError("an external-resource transfer is not bound to a Gradle invocation")
    return {
        "invocation_id": invocation_id,
        "observer_ready": True,
        "external_resource_reads": sum(record.get("event") == "external_resource_read" for record in selected),
        "observer_errors": len(errors),
    }


def validate_required_task_outcomes(outcomes: list[dict[str, Any]]) -> dict[str, str]:
    result: dict[str, str] = {}
    for task in REQUIRED_GRADLE_TASKS:
        matches = [item for item in outcomes if item.get("task") == task]
        if len(matches) != 1:
            raise SafetyError(f"required Gradle task {task} did not have exactly one recorded outcome")
        outcome = matches[0].get("outcome")
        if outcome != "SUCCESS":
            raise SafetyError(f"required Gradle task {task} was skipped, reused, or failed ({outcome})")
        result[task] = str(outcome)
    return result


def correlate_target_artifact(
    records: list[dict[str, Any]], modules: Path, invocation_labels: dict[str, str],
) -> dict[str, Any]:
    filename_hash = hashlib.sha256(ROBOLECTRIC_TARGET_FILENAME.encode("utf-8")).hexdigest()
    target_events = [
        record for record in records
        if record.get("event") == "external_resource_read"
        and record.get("artifact_coordinate") == ROBOLECTRIC_TARGET_COORDINATE
        and record.get("artifact_body") is True
    ]
    if not target_events:
        raise SafetyError("target Robolectric artifact was not transferred by a qualified Gradle invocation")
    for record in target_events:
        invocation_id = str(record.get("invocation_id", ""))
        phase = invocation_labels.get(invocation_id)
        if phase not in CORRELATABLE_GRADLE_INVOCATION_LABELS or record.get("invocation_label") != phase:
            raise SafetyError("target Robolectric transfer is not bound to a qualified Gradle invocation")
    completed = [
        record for record in target_events
        if record.get("result_state") == "completed"
        and record.get("bytes_read_known") is True
        and type(record.get("bytes_read")) is int
        and record.get("bytes_read", 0) > 0
        and record.get("artifact_filename_sha256") == filename_hash
    ]
    if not target_events or len(completed) != len(target_events):
        raise SafetyError("target Robolectric artifact lacks complete positive body-transfer evidence")

    target_directory = modules / ROBOLECTRIC_TARGET_PATH
    if target_directory.is_symlink() or not target_directory.is_dir():
        raise SafetyError("target Robolectric artifact is absent from the Gradle file cache")
    matches: list[dict[str, Any]] = []
    for digest_directory in sorted(target_directory.iterdir()):
        if digest_directory.is_symlink() or not digest_directory.is_dir():
            raise SafetyError("target Gradle artifact cache has an invalid digest directory")
        path = digest_directory / ROBOLECTRIC_TARGET_FILENAME
        if not path.exists():
            continue
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise SafetyError("target Gradle artifact cache entry is not a regular file")
        relative = path.relative_to(modules)
        matches.append({
            "relative_path_sha256": hashlib.sha256(relative.as_posix().encode("utf-8")).hexdigest(),
            "filename_sha256": filename_hash,
            "bytes": metadata.st_size,
            "sha256": _sha256_file(path),
        })
    if not matches:
        raise SafetyError("target Robolectric artifact has no resulting Gradle-cached file")
    sizes = {item["bytes"] for item in matches}
    digests = {item["sha256"] for item in matches}
    if len(sizes) != 1 or len(digests) != 1:
        raise SafetyError("target Gradle cache contains conflicting copies of the artifact")
    cached_size = next(iter(sizes))
    if any(item["bytes_read"] != cached_size for item in completed):
        raise SafetyError("completed target transfer byte count did not match the cached artifact size")
    resource_hashes = sorted({str(item.get("resource_sha256", "")) for item in completed})
    if any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in resource_hashes):
        raise SafetyError("target artifact transfer evidence is missing its redacted resource digest")
    return {
        "coordinate": ROBOLECTRIC_TARGET_COORDINATE,
        "transfer_count": len(completed),
        "transfer_bytes": sum(item["bytes_read"] for item in completed),
        "transfer_phases": sorted({invocation_labels[str(item["invocation_id"])] for item in completed}),
        "transfers": [
            {
                "invocation_id": item["invocation_id"],
                "phase": invocation_labels[str(item["invocation_id"])],
                "bytes_read": item["bytes_read"],
                "resource_sha256": item["resource_sha256"],
            }
            for item in completed
        ],
        "transfer_resource_sha256": resource_hashes,
        "correlation_basis": "coordinate-and-hashed-filename; transfer-size-matches-cached-file",
        "cached_files": matches,
    }


def command_verify_observer(args: argparse.Namespace) -> None:
    output = Path(os.environ["GRADLE_OBSERVER_OUTPUT"])
    records, parse_errors = read_observer_records(output)
    if parse_errors:
        raise SafetyError("Gradle observer output contains malformed events")
    evidence_path = _evidence_path()
    evidence = json.loads(evidence_path.read_text(encoding="utf-8")) if evidence_path.exists() else {}
    invocations = evidence.get("gradle_invocations")
    expected_labels = ["task_inventory", "dry_run", "probe_build"]
    if not isinstance(invocations, list) or [item.get("label") for item in invocations if isinstance(item, dict)] != expected_labels:
        raise SafetyError("measured Gradle invocation evidence is incomplete or out of order")

    invocation_ids: set[str] = set()
    coverage: list[dict[str, Any]] = []
    for item in invocations:
        if not isinstance(item, dict):
            raise SafetyError("measured Gradle invocation record is malformed")
        invocation_id = str(item.get("invocation_id", ""))
        if invocation_id in invocation_ids:
            raise SafetyError("measured Gradle invocation identity is duplicated")
        invocation_ids.add(invocation_id)
        if item.get("exit_code") != 0:
            raise SafetyError("a measured Gradle invocation did not complete successfully")
        coverage.append(validate_observer_invocation(records, invocation_id, str(item.get("label", ""))))
    unexpected_ids = {
        str(record.get("invocation_id")) for record in records
        if record.get("event") in {
            "runner_invocation_start", "runner_invocation_finish", "observer_ready",
            "observer_error", "external_resource_start", "external_resource_read",
        } and str(record.get("invocation_id", "")) not in invocation_ids
    }
    if unexpected_ids:
        raise SafetyError("observer records exist outside the measured Gradle invocation set")
    task_outcomes = invocations[-1].get("task_outcomes", [])
    required_tasks = validate_required_task_outcomes(task_outcomes)

    reads = [record for record in records if record.get("event") == "external_resource_read"]
    body_reads = [record for record in reads if record.get("artifact_body") is True]
    completed_body_bytes = sum(
        record.get("bytes_read", 0)
        for record in body_reads
        if record.get("bytes_read_known") is True and record.get("result_state") == "completed"
    )
    target_body_reads = [
        record for record in body_reads
        if record.get("artifact_coordinate") == ROBOLECTRIC_TARGET_COORDINATE
    ]
    correlation: dict[str, Any] | None = None
    if args.mode == "cold":
        invocation_labels = {
            str(item["invocation_id"]): str(item["label"])
            for item in invocations
            if item.get("label") in QUALIFIED_GRADLE_INVOCATION_LABELS
        }
        correlation = correlate_target_artifact(records, _modules_path(), invocation_labels)
    elif args.mode == "warm" and body_reads:
        raise SafetyError("warm observation could not prove the absence of artifact-body transfers")
    elif args.mode == "fixture":
        if completed_body_bytes <= 0:
            raise SafetyError("observer fixture did not prove a completed artifact-body transfer")

    summary = {
        "observer_ready_count": len(coverage),
        "observer_invocation_coverage": coverage,
        "external_resource_reads": len(reads),
        "artifact_body_events": len(body_reads),
        "artifact_body_bytes": completed_body_bytes,
        "target_artifact_body_events": len(target_body_reads),
        "observer_errors": 0,
        "observer_mode": args.mode,
        "required_task_outcomes": required_tasks,
    }
    if correlation is not None:
        summary["target_artifact_correlation"] = correlation
    _write_evidence(summary)
    _append_github_file(_github_file("GITHUB_OUTPUT"), [
        f"artifact_body_bytes={completed_body_bytes}",
        f"artifact_body_events={len(body_reads)}",
        f"target_artifact_body_events={len(target_body_reads)}",
        "observer_errors=0",
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

    seed_record = sub.add_parser("write-seed-record")
    seed_record.add_argument("--manifest", required=True)
    seed_record.add_argument("--cache-key", required=True)
    seed_record.add_argument("--output", required=True)
    seed_record.set_defaults(func=command_write_seed_record)

    verify_seed = sub.add_parser("verify-seed-record")
    verify_seed.add_argument("--path", required=True)
    verify_seed.add_argument("--expected-source-sha", required=True)
    verify_seed.add_argument("--expected-cache-key", required=True)
    verify_seed.add_argument("--expected-run-id", required=True)
    verify_seed.set_defaults(func=command_verify_seed_record)

    select_seed = sub.add_parser("select-seed-run")
    select_seed.add_argument("--seed-runs", required=True)
    select_seed.add_argument("--pr-runs", required=True)
    select_seed.add_argument("--head-sha", required=True)
    select_seed.add_argument("--pr-number", required=True)
    select_seed.add_argument("--current-run-id", required=True)
    select_seed.set_defaults(func=command_select_seed_run)

    pr_identities = sub.add_parser("record-pr-identities")
    pr_identities.add_argument("--head-sha", required=True)
    pr_identities.add_argument("--base-sha", required=True)
    pr_identities.add_argument("--merge-sha", default="")
    pr_identities.add_argument("--github-sha", required=True)
    pr_identities.add_argument("--seed-source-sha", required=True)
    pr_identities.add_argument("--seed-run-id", required=True)
    pr_identities.set_defaults(func=command_record_pr_identities)

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
    canary.add_argument("--readback-check-outcome", required=True)
    canary.add_argument("--effective-cache-mode-available", required=True)
    canary.add_argument("--effective-cache-mode-value-base64", required=True)
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
    sub.add_parser("partial-cleanup-failure").set_defaults(func=command_partial_cleanup_failure)
    partial_sentinel = sub.add_parser("verify-partial-sentinel")
    partial_sentinel.add_argument("--cleanup-outcome", required=True)
    partial_sentinel.add_argument("--sentinel-outcome", required=True)
    partial_sentinel.add_argument("--marker", required=True)
    partial_sentinel.set_defaults(func=command_verify_partial_sentinel)
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
