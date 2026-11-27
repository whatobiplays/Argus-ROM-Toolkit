"""Run the Android readiness probe with a job-local Gradle user home.

Each trial starts with an empty checkout build directory, disables output and
configuration reuse, measures wrapper distributions separately, and records
toolchain and artifact measurements with redacted transfer evidence outside
the cached module path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

from scripts.gradle_dependency_cache import control


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "android-readiness-probe" / "gradlew"
OBSERVER = Path(os.environ.get("GRADLE_OBSERVER_SCRIPT", ""))
RUN_LOG = "gradle-dependency-cache-runner.log"
FAILURE_LINE = re.compile(
    r"(?:^FAILURE:|^\s*What went wrong:|^\s*> Task .* FAILED$|"
    r"Could not resolve|Could not download|Could not get resource|BUILD (?:SUCCESSFUL|FAILED))",
    re.IGNORECASE,
)


class RunnerError(RuntimeError):
    """Raised when the probe or its required evidence does not meet the contract."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def append_output(values: dict[str, Any]) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if not output:
        return
    with Path(output).open("a", encoding="utf-8") as stream:
        for name, value in values.items():
            normalized = str(value).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            stream.write(f"{name}={normalized}\n")


def isolated_log_path() -> Path:
    temp = control._runner_temp()
    path = temp / RUN_LOG
    if path.exists() or path.is_symlink():
        path.unlink()
    return path


def retain_redacted_log(log: Path) -> None:
    if not log.is_file():
        return
    destination = Path(os.environ.get("GRADLE_REDACTED_LOG_PATH", control._task_root() / "runner-log-redacted.txt"))
    redactions = [
        (str(ROOT), "[workspace]"),
        (str(control._home(create=False)), "[gradle-user-home]"),
        (str(control._runner_temp()), "[runner-temp]"),
    ]
    selected = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        if not FAILURE_LINE.search(line):
            continue
        for value, replacement in redactions:
            line = line.replace(value, replacement)
        line = re.sub(r"https?://[^\s\"'<>]+", "https://[redacted]", line)
        selected.append(line[:500])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(selected[-100:]) + ("\n" if selected else ""), encoding="utf-8")


def capture_robolectric_attempts(log: Path) -> None:
    attempts: list[dict[str, str]] = []
    error_lines = 0
    if log.is_file():
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            match = re.search(r"\bTransferring\s+([^\s]+)", line, re.IGNORECASE)
            if match:
                location = match.group(1)
                path = unquote(urlsplit(location).path).casefold()
                segments = [segment for segment in path.split("/") if segment]
                is_robolectric = any(
                    left == "org" and right == "robolectric"
                    for left, right in zip(segments, segments[1:])
                )
                if is_robolectric:
                    attempts.append({
                        "resource_sha256": hashlib.sha256(location.encode("utf-8")).hexdigest(),
                        "suffix": Path(path).suffix.lower(),
                        "state": "attempt_only",
                    })
            if re.search(r"(?:robolectric|MavenArtifactFetcher).*(?:failed|error)|(?:failed|could not).*org\.robolectric", line, re.IGNORECASE):
                error_lines += 1
    root = control._task_root(create=True)
    output = root / "robolectric-attempts-redacted.json"
    payload = {
        "observation": "log_attempts_only",
        "attempt_lines_observed": len(attempts),
        "error_lines_observed": error_lines,
        "no_attempt_lines_is_not_zero_transfer_claim": not attempts,
        "attempts": attempts[:1000],
    }
    output.write_text(json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    control._write_evidence({
        "robolectric_attempt_log_lines": len(attempts),
        "robolectric_error_log_lines": error_lines,
        "robolectric_attempt_observation": "attempt_only" if attempts else "not_observed_not_zero",
    })


def run_command(
    command: list[str],
    label: str,
    log: Path,
    environment: dict[str, str],
    *,
    allow_failure: bool = False,
) -> tuple[int, float]:
    started = time.monotonic()
    with log.open("ab") as output:
        output.write((f"\n--- {label} ---\n").encode("utf-8"))
        process = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            stdout=output,
            stderr=subprocess.STDOUT,
            check=False,
        )
    elapsed = time.monotonic() - started
    if process.returncode and not allow_failure:
        raise RunnerError(f"{label} exited with status {process.returncode}")
    return process.returncode, elapsed


def control_command(name: str, *args: str, log: Path, environment: dict[str, str]) -> dict[str, Any]:
    command = [sys.executable, "-m", "scripts.gradle_dependency_cache.control", name, *args]
    result = subprocess.run(command, cwd=ROOT, env=environment, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RunnerError(f"cache control command {name} failed")
    try:
        return json.loads(result.stdout.strip())
    except json.JSONDecodeError as error:
        raise RunnerError(f"cache control command {name} returned invalid evidence") from error


def toolchain_identity(environment: dict[str, str]) -> dict[str, str]:
    java_identity = control.java_runtime_identity(environment)

    sdk_root = Path(environment.get("ANDROID_HOME", environment.get("ANDROID_SDK_ROOT", "")))
    sdk_files = [
        sdk_root / "platforms" / "android-36" / "source.properties",
        sdk_root / "build-tools" / "36.0.0" / "source.properties",
    ]
    sdk_revisions = []
    for path in sdk_files:
        if not path.is_file():
            raise RunnerError("a required Android SDK package was not installed")
        contents = path.read_text(encoding="utf-8", errors="replace")
        revision = next((line.split("=", 1)[1].strip() for line in contents.splitlines() if line.startswith("Pkg.Revision")), "")
        if not revision:
            raise RunnerError("Android SDK package revision was not recorded")
        sdk_revisions.append(revision)
    image_os = environment.get("ImageOS", environment.get("RUNNER_OS", "unknown"))
    image_version = environment.get("ImageVersion", "unknown")
    if not image_os or image_os == "unknown" or not image_version or image_version == "unknown":
        raise RunnerError("hosted runner image identity was not available")
    return {
        **java_identity,
        "gradle_version": "",
        "runner_os": image_os,
        "runner_image_version": image_version,
        "runner_arch": platform.machine(),
        "runner_temp_path_sha256": hashlib.sha256(environment.get("RUNNER_TEMP", "").encode("utf-8")).hexdigest(),
        "android_platform_revision": sdk_revisions[0],
        "android_build_tools_revision": sdk_revisions[1],
    }


def gradle_version(output: str) -> str:
    match = re.search(r"^Gradle\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s*$", output, re.MULTILINE)
    return match.group(1) if match else ""


def run_version(log: Path, environment: dict[str, str]) -> tuple[str, float]:
    _, elapsed = run_command([str(WRAPPER), "--version"], "Gradle wrapper and version", log, environment)
    content = log.read_text(encoding="utf-8", errors="replace")
    version = gradle_version(content)
    if not version:
        raise RunnerError("Gradle version could not be identified")
    return version, elapsed


def apk_path() -> Path:
    output = ROOT / "android-readiness-probe" / "build" / "outputs" / "apk" / "probe"
    matches = sorted(path for path in output.rglob("*-unsigned.apk") if path.is_file() and not path.is_symlink())
    if len(matches) != 1:
        raise RunnerError("the readiness probe did not produce exactly one unsigned APK")
    return matches[0]


def sign_and_inspect(unsigned_apk: Path, commit: str, environment: dict[str, str], log: Path) -> dict[str, str]:
    sdk = Path(environment.get("ANDROID_HOME", environment.get("ANDROID_SDK_ROOT", "")))
    tools = sdk / "build-tools" / "36.0.0"
    apksigner = tools / "apksigner"
    aapt2 = tools / "aapt2"
    if not apksigner.is_file() or not aapt2.is_file():
        raise RunnerError("the pinned Android artifact tools were not found")

    temp = control._runner_temp()
    with tempfile.TemporaryDirectory(prefix="probe-signing-", dir=temp) as name:
        signing_dir = Path(name)
        os.chmod(signing_dir, 0o700)
        keystore = signing_dir / "test-keystore.p12"
        signed_apk = signing_dir / "test.apk"
        password = secrets.token_hex(32)
        child_environment = dict(environment)
        child_environment["PROBE_TEST_PASSWORD"] = password
        key_command = [
            "keytool", "-genkeypair", "-keystore", str(keystore), "-storetype", "PKCS12",
            "-storepass:env", "PROBE_TEST_PASSWORD", "-keypass:env", "PROBE_TEST_PASSWORD",
            "-alias", "probe", "-keyalg", "RSA", "-keysize", "2048", "-validity", "1",
            "-dname", "CN=Disposable probe CI",
        ]
        run_command(key_command, "create disposable signing key", log, child_environment)
        run_command([
            str(apksigner), "sign", "--ks", str(keystore), "--ks-pass", "env:PROBE_TEST_PASSWORD",
            "--key-pass", "env:PROBE_TEST_PASSWORD", "--out", str(signed_apk), str(unsigned_apk),
        ], "sign disposable APK copy", log, child_environment)
        _, _ = run_command([
            str(apksigner), "verify", "--verbose", "--print-certs", str(signed_apk),
        ], "verify disposable APK copy", log, child_environment)
        cert_output = subprocess.run(
            [str(apksigner), "verify", "--print-certs", str(signed_apk)],
            env=child_environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if cert_output.returncode:
            raise RunnerError("certificate digest query failed for the signed copy")
        match = re.search(r"Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)", cert_output.stdout)
        if not match:
            raise RunnerError("signed APK certificate digest was not reported")
        certificate = match.group(1).replace(":", "").lower()
        inspection = subprocess.run(
            [
                sys.executable, "-m", "scripts.android_qualification.readiness_probe_artifact",
                "--apk", str(signed_apk), "--source-commit", commit,
                "--certificate-sha256", certificate,
                "--aapt2", str(aapt2), "--apksigner", str(apksigner),
            ],
            cwd=ROOT,
            env=child_environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if inspection.returncode:
            raise RunnerError("readiness probe artifact inspection rejected the disposable signed copy")
        return {"certificate_sha256": certificate, "artifact_inspection": "passed"}


def check_identity(actual: dict[str, str], args: argparse.Namespace) -> None:
    expected = {
        "gradle_version": args.expected_gradle,
        "java_runtime_version": args.expected_java,
        "runner_os": args.expected_image_os,
        "runner_image_version": args.expected_image_version,
        "android_platform_revision": args.expected_platform_revision,
        "android_build_tools_revision": args.expected_build_tools_revision,
        "runner_temp_path_sha256": args.expected_runner_temp_sha256,
    }
    differences = [name for name, value in expected.items() if value and actual.get(name) != value]
    if differences:
        raise RunnerError("runner toolchain identity did not match the trusted seed: " + ", ".join(differences))


def execute(args: argparse.Namespace) -> int:
    qualification_started = time.monotonic()
    environment = dict(os.environ)
    home = control._home(create=False)
    runner_temp = control._runner_temp()
    if not control._inside(home.resolve(strict=True), runner_temp):
        raise RunnerError("Gradle user home is outside RUNNER_TEMP")
    if not WRAPPER.is_file() or not os.access(WRAPPER, os.X_OK):
        raise RunnerError("repository Gradle wrapper is missing or not executable")
    if not OBSERVER.is_file():
        raise RunnerError("Gradle observer was not installed before the first invocation")
    commit = environment.get("PROBE_SOURCE_COMMIT", environment.get("GITHUB_SHA", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise RunnerError("invalid source commit")
    project_build = ROOT / "android-readiness-probe" / "build"
    if project_build.exists() or project_build.is_symlink():
        raise RunnerError("probe build output existed before this fresh-checkout trial")

    log = isolated_log_path()
    evidence: dict[str, Any] = {
        "campaign_id": environment.get("EXPERIMENT_CAMPAIGN_ID", "gradle-dependency-cache-pilot-v1"),
        "probe_source_commit": commit,
        "trial_mode": args.mode,
        "fresh_build_directory": True,
        "configuration_cache_disabled": True,
        "build_output_cache_disabled": True,
    }
    _write = control._write_evidence
    _write(evidence)

    wrapper_before_file = control._task_root() / "wrapper-before.json"
    wrapper_after_file = control._task_root() / "wrapper-after.json"
    wrapper_before = control_command("wrapper-snapshot", "--output", str(wrapper_before_file), log=log, environment=environment)
    toolchain = toolchain_identity(environment)
    version, wrapper_elapsed = run_version(log, environment)
    toolchain["gradle_version"] = version
    if version != args.expected_gradle:
        raise RunnerError("Gradle wrapper version did not match the approved version")
    wrapper_after = control_command("wrapper-snapshot", "--output", str(wrapper_after_file), log=log, environment=environment)
    toolchain["wrapper_distribution_files_before"] = str(wrapper_before["files"])
    toolchain["wrapper_distribution_files_after"] = str(wrapper_after["files"])
    toolchain["wrapper_distribution_bytes_before"] = str(wrapper_before["bytes"])
    toolchain["wrapper_distribution_bytes_after"] = str(wrapper_after["bytes"])
    toolchain["wrapper_distribution_new_bytes"] = str(max(0, wrapper_after["bytes"] - wrapper_before["bytes"]))
    check_identity(toolchain, args)

    common = [
        str(WRAPPER), "-p", "android-readiness-probe",
        "--no-daemon", "--no-build-cache", "--no-configuration-cache", "--console=plain",
        f"-PprobeSourceCommit={commit}",
    ]
    times: dict[str, float] = {"wrapper_version_seconds": wrapper_elapsed}
    sequence = [
        ("task_inventory", common + ["tasks", "--all"]),
        ("dry_run", common + ["testProbeUnitTest", "lintProbe", "assembleProbe", "--dry-run"]),
        ("probe_build", common + ["testProbeUnitTest", "lintProbe", "assembleProbe"]),
    ]
    for label, command in sequence:
        _, elapsed = run_command(command, label, log, environment)
        times[f"{label}_seconds"] = round(elapsed, 3)

    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    _, host_tests_elapsed = run_command([
        sys.executable, "-m", "unittest", "discover", "-s", "scripts/android_qualification",
        "-p", "test_*.py", "-t", ".",
    ], "host-only qualification tests", log, environment)
    times["host_tests_seconds"] = round(host_tests_elapsed, 3)

    unsigned = apk_path()
    unsigned_digest = sha256_file(unsigned)
    unsigned_size = unsigned.stat().st_size
    if args.compare_apk and unsigned_digest != args.compare_apk:
        raise RunnerError("unsigned APK SHA-256 did not match its paired trial")
    signed = sign_and_inspect(unsigned, commit, environment, log)

    qualification_elapsed = round(time.monotonic() - qualification_started, 3)
    paired_match = True if args.compare_apk else None
    evidence.update({
        **toolchain,
        **times,
        "gradle_version": version,
        "probe_wall_seconds": round(sum(times.values()), 3),
        "qualification_elapsed_seconds": qualification_elapsed,
        "unsigned_apk_sha256": unsigned_digest,
        "unsigned_apk_bytes": unsigned_size,
        "paired_unsigned_apk_match": paired_match,
        "signed_copy_certificate_sha256": signed["certificate_sha256"],
        "signed_copy_artifact_inspection": signed["artifact_inspection"],
        "signing_key_disposable": True,
        "signed_copy_path_outside_checkout": True,
    })
    _write(evidence)
    capture_robolectric_attempts(log)
    retain_redacted_log(log)
    append_output({
        "unsigned_apk_sha256": unsigned_digest,
        "unsigned_apk_bytes": unsigned_size,
        "gradle_version": version,
        "java_runtime_version": toolchain["java_runtime_version"],
        "java_vendor": toolchain["java_vendor"],
        "image_os": toolchain["runner_os"],
        "image_version": toolchain["runner_image_version"],
        "platform_revision": toolchain["android_platform_revision"],
        "build_tools_revision": toolchain["android_build_tools_revision"],
        "runner_temp_path_sha256": toolchain["runner_temp_path_sha256"],
        "probe_wall_seconds": round(sum(times.values()), 3),
        "qualification_elapsed_seconds": qualification_elapsed,
    })
    print(json.dumps({
        "gradle_version": version,
        "java_runtime_version": toolchain["java_runtime_version"],
        "runner_image_version": toolchain["runner_image_version"],
        "probe_wall_seconds": round(sum(times.values()), 3),
        "unsigned_apk_sha256": unsigned_digest,
        "paired_unsigned_apk_match": evidence["paired_unsigned_apk_match"],
    }, sort_keys=True))
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Execute one isolated readiness-probe trial.")
    parser.add_argument("--mode", choices=("cold", "warm"), required=True)
    parser.add_argument("--expected-gradle", default="9.1.0")
    parser.add_argument("--expected-java", default="")
    parser.add_argument("--expected-image-os", default="")
    parser.add_argument("--expected-image-version", default="")
    parser.add_argument("--expected-platform-revision", default="")
    parser.add_argument("--expected-build-tools-revision", default="")
    parser.add_argument("--expected-runner-temp-sha256", default="")
    parser.add_argument("--compare-apk", default="")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    try:
        return execute(args)
    except (OSError, ValueError, RunnerError, control.SafetyError, KeyError) as error:
        try:
            log = control._runner_temp() / RUN_LOG
            capture_robolectric_attempts(log)
            retain_redacted_log(log)
        except (OSError, control.SafetyError):
            pass
        control._write_evidence({"runner_error_kind": type(error).__name__, "runner_succeeded": False})
        print(f"::error::{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
