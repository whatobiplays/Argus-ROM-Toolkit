"""Qualify the Gradle download observer against an isolated local Maven fixture."""

from __future__ import annotations

import functools
import http.server
import json
import os
import subprocess
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "android-readiness-probe" / "gradlew"
OBSERVER = Path(__file__).with_name("observer.init.gradle")


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    request_paths: list[str] = []

    def do_GET(self) -> None:
        self.request_paths.append(self.path)
        super().do_GET()

    def log_message(self, format: str, *args: object) -> None:
        return


class ObserverFixtureTests(unittest.TestCase):
    def test_observer_reports_local_maven_artifact_body_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gradle-observer-fixture-") as temporary:
            temp = Path(temporary)
            repo = temp / "maven"
            module = repo / "org" / "fixture" / "sample" / "1.0"
            module.mkdir(parents=True)
            (module / "sample-1.0.pom").write_text(
                """<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.fixture</groupId><artifactId>sample</artifactId><version>1.0</version>
</project>
""",
                encoding="utf-8",
            )
            with zipfile.ZipFile(module / "sample-1.0.jar", "w") as archive:
                archive.writestr("fixture.txt", "local cache observer qualification\n")

            handler = functools.partial(QuietHandler, directory=str(temp))
            QuietHandler.request_paths.clear()
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            server_thread = threading.Thread(target=server.serve_forever, daemon=True)
            server_thread.start()
            try:
                port = server.server_address[1]
                project = temp / "project"
                project.mkdir()
                (project / "settings.gradle").write_text("rootProject.name = 'observer-fixture'\n", encoding="utf-8")
                (project / "build.gradle").write_text(
                    f"""repositories {{
    maven {{ url = uri('http://127.0.0.1:{port}/maven'); allowInsecureProtocol = true }}
}}
configurations {{ probe }}
dependencies {{ probe 'org.fixture:sample:1.0' }}
tasks.register('resolveFixture') {{
    doLast {{
        def files = configurations.probe.resolve()
        if (files.size() != 1) throw new GradleException("expected one fixture artifact")
    }}
}}
""",
                    encoding="utf-8",
                )
                gradle_home = temp / "isolated-gradle-home"
                init_script = gradle_home / "init.d" / OBSERVER.name
                init_script.parent.mkdir(parents=True)
                init_script.write_bytes(OBSERVER.read_bytes())
                observer_output = temp / "observer.jsonl"
                environment = dict(os.environ)
                environment.update({
                    "RUNNER_TEMP": str(temp),
                    "GRADLE_USER_HOME": str(gradle_home),
                    "GRADLE_OBSERVER_OUTPUT": str(observer_output),
                    "ROBOLECTRIC_MAVEN_REPO_LOCAL": str(temp / "robolectric-m2"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                })
                command = [
                    str(WRAPPER), "-p", str(project), "--no-daemon", "--no-build-cache",
                    "--no-configuration-cache", "--console=plain", "resolveFixture",
                ]
                version_command = [str(WRAPPER), "-p", str(project), "--version"]
                version_result = subprocess.run(
                    version_command,
                    cwd=ROOT,
                    env=environment,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                    timeout=600,
                )
                self.assertEqual(version_result.returncode, 0, version_result.stdout[-5000:])
                self.assertFalse(observer_output.exists())
                self.assertEqual(QuietHandler.request_paths, [])
                result = subprocess.run(
                    command,
                    cwd=ROOT,
                    env=environment,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                    timeout=600,
                )
                self.assertEqual(result.returncode, 0, result.stdout[-5000:])
                records = [json.loads(line) for line in observer_output.read_text(encoding="utf-8").splitlines()]
                self.assertEqual(sum(record.get("event") == "observer_ready" for record in records), 1)
                body_reads = [
                    record for record in records
                    if record.get("event") == "external_resource_read" and record.get("artifact_body") is True
                ]
                self.assertEqual(len(body_reads), 1, body_reads)
                self.assertEqual(
                    body_reads[0].get("details_type"),
                    "ProgressLoggingExternalResourceAccessor$ReadOperationDetails",
                )
                self.assertTrue(body_reads, {
                    "events": [record.get("event") for record in records],
                    "details_types": [record.get("details_type") for record in records if record.get("event") == "external_resource_start"],
                    "loopback_get_count": len(QuietHandler.request_paths),
                })
                self.assertTrue(any(record.get("bytes_read", 0) > 0 for record in body_reads), body_reads)
                self.assertTrue(all("resource_sha256" in record for record in body_reads), body_reads)
                self.assertNotIn("127.0.0.1", observer_output.read_text(encoding="utf-8"))
                self.assertNotIn("sample-1.0.jar", observer_output.read_text(encoding="utf-8"))
            finally:
                server.shutdown()
                server.server_close()
                server_thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
