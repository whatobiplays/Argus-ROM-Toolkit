"""Public workflow tests for normal-user fixture staging."""

from __future__ import annotations

import json
import copy
import hashlib
import os
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from scripts.android_qualification import (
    fixture_staging,
    fixture_staging_contract,
    fixture_staging_files,
    fixture_staging_manifest,
    fixture_staging_orchestration,
    fixture_staging_runs,
)


class SimpleFixtureStagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.source_root = self.root / "selected-fixture"
        self.source_root.mkdir()
        self.staging_root = self.root / "staging"
        self.data = b"synthetic fixture bytes"
        (self.source_root / "game.rom").write_bytes(self.data)
        self.manifest = self._manifest(self.data)

    @staticmethod
    def _manifest(data: bytes) -> dict[str, object]:
        return {
            "schema_version": 2,
            "coverage": {
                "mode": "mandatory_full_plan",
                "required_fixture_ids": ["fixture-demo"],
                "mandatory_fixture_ids": ["fixture-demo"],
            },
            "fixtures": [
                {
                    "fixture_id": "fixture-demo",
                    "group_id": "group-demo",
                    "order": 0,
                    "platform": "Synthetic Platform",
                    "representation": "raw-file",
                    "entrypoint": "game.rom",
                    "expected_identity": {"title": "Synthetic Game"},
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
                    "identity_evidence": None,
                }
            ],
        }

    def _stage(self, **overrides: object) -> fixture_staging.StagingResult:
        arguments: dict[str, object] = {
            "manifest": self.manifest,
            "sources": {"fixture-demo": self.source_root},
            "selected_fixture_ids": ("fixture-demo",),
            "owner_approved": True,
            "staging_root": self.staging_root,
            "minimum_free_bytes": 0,
        }
        arguments.update(overrides)
        return fixture_staging.stage_fixtures(**arguments)

    def test_manifest_parser_returns_an_immutable_typed_plan(self) -> None:
        plan = fixture_staging_manifest._parse_manifest(self.manifest)

        self.assertIsInstance(plan, fixture_staging_contract.FixturePlan)
        with self.assertRaises(TypeError):
            plan.fixtures["another-fixture"] = plan.fixtures["fixture-demo"]
        fixture = plan.fixtures["fixture-demo"]
        self.assertIsInstance(fixture, fixture_staging_contract.FixtureSpec)
        with self.assertRaises(TypeError):
            fixture.expected_identity["title"] = "Changed title"
        self.assertIsInstance(fixture.files[0], fixture_staging_contract.FixtureFile)
        with self.assertRaises(AttributeError):
            fixture.files[0].path = "changed.rom"

        manifest, _, _ = self._multidisc_input(
            b"disc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )
        ordered_plan = fixture_staging_manifest._parse_manifest(manifest)
        ordered_fixture = ordered_plan.fixtures["fixture-demo"]
        self.assertIsInstance(ordered_fixture.companions[0], fixture_staging_contract.FixtureCompanion)

    def _multidisc_input(
        self,
        playlist: bytes,
        first_cue: bytes,
        *,
        nested: bool = False,
        playlist_at_root: bool = False,
    ) -> tuple[dict[str, object], Path, dict[str, bytes]]:
        source_root = self.root / "multidisc-source"
        source_root.mkdir()
        source_contents = {
            "playlist.m3u": playlist,
            "disc1.cue": first_cue,
            "disc1.bin": b"disc one bytes",
            "disc2.cue": b'FILE "disc2.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
            "disc2.bin": b"disc two bytes",
        }
        path_map = {
            path: (
                path
                if not nested or (playlist_at_root and path == "playlist.m3u")
                else f"games/{path}"
            )
            for path in source_contents
        }
        contents = {path_map[path]: data for path, data in source_contents.items()}
        for relative, data in contents.items():
            destination = source_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        fixture = dict(self.manifest["fixtures"][0])
        fixture.update(
            {
                "group_id": "disc-set-demo",
                "representation": "m3u-cue-bin",
                "entrypoint": path_map["playlist.m3u"],
                "structural_expectations": {"entrypoint_kind": "m3u", "disc_count": 2},
                "files": [
                    {
                        "path": relative,
                        "role": "playlist" if relative.endswith(".m3u") else "descriptor" if relative.endswith(".cue") else "track",
                        "size": len(data),
                        "sha256": hashlib.sha256(data).hexdigest(),
                    }
                    for relative, data in contents.items()
                ],
                "companions": [
                    {"source": path_map["playlist.m3u"], "target": path_map["disc1.cue"]},
                    {"source": path_map["playlist.m3u"], "target": path_map["disc2.cue"]},
                    {"source": path_map["disc1.cue"], "target": path_map["disc1.bin"]},
                    {"source": path_map["disc2.cue"], "target": path_map["disc2.bin"]},
                ],
            }
        )
        manifest = dict(self.manifest)
        manifest["fixtures"] = [fixture]
        return manifest, source_root, contents

    def _cue_input(self) -> tuple[dict[str, object], Path, dict[str, bytes]]:
        contents = {
            "disc/disc.cue": b'FILE "track.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
            "disc/track.bin": b"cue track bytes",
        }
        source_root = self.root / "cue-source"
        for relative, data in contents.items():
            destination = source_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        manifest = copy.deepcopy(self.manifest)
        fixture = manifest["fixtures"][0]
        fixture.update(
            {
                "representation": "cue-bin",
                "entrypoint": "disc/disc.cue",
                "structural_expectations": {"entrypoint_kind": "cue"},
                "files": [
                    {
                        "path": relative,
                        "role": "descriptor" if relative.endswith(".cue") else "track",
                        "size": len(data),
                        "sha256": hashlib.sha256(data).hexdigest(),
                    }
                    for relative, data in contents.items()
                ],
                "companions": [{"source": "disc/disc.cue", "target": "disc/track.bin"}],
            }
        )
        return manifest, source_root, contents

    def test_stages_and_publishes_an_explicitly_approved_fixture(self) -> None:
        original = (self.source_root / "game.rom").read_bytes()
        result = self._stage()

        self.assertEqual("verified", result.status)
        self.assertEqual(("fixture-demo",), result.fixture_ids)
        self.assertEqual(len(self.data), result.byte_count)
        self.assertEqual(self.data, (result.published_path / "fixture-demo/game.rom").read_bytes())
        assessment = result.assessments[0]
        self.assertEqual("verified", assessment.byte_integrity)
        self.assertEqual("not_independently_verified", assessment.identity_support)
        self.assertEqual("not_qualified", assessment.qualification_status)
        self.assertEqual(original, (self.source_root / "game.rom").read_bytes())

    def test_raw_file_fixture_rejects_unverifiable_companion_edges(self) -> None:
        companion = b"unlinked companion"
        (self.source_root / "companion.bin").write_bytes(companion)
        manifest = copy.deepcopy(self.manifest)
        fixture = manifest["fixtures"][0]
        fixture["files"].append({
            "path": "companion.bin",
            "role": "content",
            "size": len(companion),
            "sha256": hashlib.sha256(companion).hexdigest(),
        })
        fixture["companions"] = [{"source": "game.rom", "target": "companion.bin"}]

        result = self._stage(manifest=manifest)

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_explicit_owner_approval_is_required_before_any_destination_is_created(self) -> None:
        result = self._stage(owner_approved=False)

        self.assertEqual("failed", result.status)
        self.assertEqual("OWNER_APPROVAL_REQUIRED", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_default_staging_root_uses_override_platform_and_xdg_location(self) -> None:
        with mock.patch.dict(os.environ, {"ARGUS_FIXTURE_STAGING_ROOT": "~/custom-stage"}, clear=True):
            self.assertEqual(Path.home() / "custom-stage", fixture_staging.default_staging_root())
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(fixture_staging_contract.sys, "platform", "darwin"):
            self.assertEqual(
                Path.home() / "Library/Application Support/ArgusROMToolkit/FixtureStaging",
                fixture_staging.default_staging_root(),
            )
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state")}, clear=True), mock.patch.object(fixture_staging_contract.sys, "platform", "linux"):
            self.assertEqual(
                self.root / "state/argus-rom-toolkit/fixture-staging",
                fixture_staging.default_staging_root(),
            )

    def test_unsupported_manifest_schema_is_reported_without_creating_a_run(self) -> None:
        manifest = dict(self.manifest)
        manifest["schema_version"] = 1

        result = self._stage(manifest=manifest)

        self.assertEqual("failed", result.status)
        self.assertEqual("SCHEMA_UNSUPPORTED", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_duplicate_json_keys_and_traversal_paths_are_rejected(self) -> None:
        encoded = json.dumps(self.manifest)
        duplicated = encoded.replace('"schema_version": 2', '"schema_version": 2, "schema_version": 2', 1)
        duplicate_result = self._stage(manifest=duplicated.encode("utf-8"))
        self.assertEqual("MANIFEST_INVALID", duplicate_result.error_code)
        self.assertFalse(self.staging_root.exists())

        traversal = dict(self.manifest)
        fixture = dict(traversal["fixtures"][0])
        fixture["files"] = [dict(fixture["files"][0], path="../outside.rom")]
        fixture["entrypoint"] = "../outside.rom"
        traversal["fixtures"] = [fixture]
        traversal_result = self._stage(manifest=traversal)
        self.assertEqual("MANIFEST_INVALID", traversal_result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_manifest_file_input_is_bounded_and_symlinks_are_not_followed(self) -> None:
        manifest_file = self.root / "manifest.json"
        manifest_file.write_bytes(fixture_staging_manifest._canonical_json(self.manifest))
        staged = self._stage(manifest=manifest_file)
        self.assertEqual("verified", staged.status)

        string_path_result = self._stage(
            manifest=str(manifest_file),
            staging_root=self.root / "string-path-stage",
        )
        self.assertEqual("verified", string_path_result.status)

        link = self.root / "manifest-link.json"
        link.symlink_to(manifest_file)
        link_result = self._stage(manifest=link, staging_root=self.root / "link-stage")
        self.assertEqual("MANIFEST_UNAVAILABLE", link_result.error_code)
        self.assertFalse((self.root / "link-stage").exists())

        with mock.patch.object(fixture_staging_manifest, "MAX_MANIFEST_BYTES", 1):
            large_result = self._stage(
                manifest=fixture_staging_manifest._canonical_json(self.manifest),
                staging_root=self.root / "large-stage",
            )
        self.assertEqual("MANIFEST_TOO_LARGE", large_result.error_code)
        self.assertFalse((self.root / "large-stage").exists())

    def test_manifest_shape_and_ordering_errors_fail_before_creating_a_run(self) -> None:
        second = copy.deepcopy(self.manifest["fixtures"][0])
        second["fixture_id"] = "fixture-second"
        second["group_id"] = "group-demo"
        second["order"] = 1
        cases = [
            ("unknown root field", lambda doc: doc.update(extra=True)),
            ("boolean schema version", lambda doc: doc.update(schema_version=True)),
            ("invalid coverage object", lambda doc: doc.update(coverage=[])),
            ("unsupported coverage mode", lambda doc: doc["coverage"].update(mode="unknown")),
            ("empty required list", lambda doc: doc["coverage"].update(required_fixture_ids=[])),
            ("duplicate required id", lambda doc: doc["coverage"].update(required_fixture_ids=["fixture-demo", "fixture-demo"])),
            ("nonrequired mandatory id", lambda doc: doc["coverage"].update(mandatory_fixture_ids=["missing"])),
            ("empty fixture list", lambda doc: doc.update(fixtures=[])),
            ("unknown fixture field", lambda doc: doc["fixtures"][0].update(extra=True)),
            ("unsafe fixture id", lambda doc: doc["fixtures"][0].update(fixture_id="../fixture")),
            ("boolean group order", lambda doc: doc["fixtures"][0].update(order=True)),
            ("invalid platform text", lambda doc: doc["fixtures"][0].update(platform=" platform ")),
            ("empty identity", lambda doc: doc["fixtures"][0].update(expected_identity={})),
            ("unsupported identity value", lambda doc: doc["fixtures"][0].update(expected_identity={"title": 1.5})),
            ("empty structural expectations", lambda doc: doc["fixtures"][0].update(structural_expectations={})),
            ("unsupported structural value", lambda doc: doc["fixtures"][0].update(structural_expectations={"entrypoint_kind": []})),
            ("empty file list", lambda doc: doc["fixtures"][0].update(files=[])),
            ("unknown file field", lambda doc: doc["fixtures"][0]["files"][0].update(extra=True)),
            ("boolean file size", lambda doc: doc["fixtures"][0]["files"][0].update(size=True)),
            ("negative file size", lambda doc: doc["fixtures"][0]["files"][0].update(size=-1)),
            ("invalid file digest", lambda doc: doc["fixtures"][0]["files"][0].update(sha256="bad")),
            ("entrypoint absent", lambda doc: doc["fixtures"][0].update(entrypoint="missing.rom")),
            ("invalid companion list", lambda doc: doc["fixtures"][0].update(companions={})),
            ("duplicate fixture", lambda doc: doc["fixtures"].append(copy.deepcopy(doc["fixtures"][0]))),
            ("fixture order mismatch", lambda doc: (doc["fixtures"].append(copy.deepcopy(second)), doc["coverage"].update(required_fixture_ids=["fixture-second", "fixture-demo"]))),
            ("group order gap", lambda doc: (doc["fixtures"].append({**copy.deepcopy(second), "order": 2}), doc["coverage"].update(required_fixture_ids=["fixture-demo", "fixture-second"]))),
            ("conflicting evidence", lambda doc: doc["fixtures"][0].update(identity_evidence={"schema_version": 1, "tier": "unknown"})),
        ]

        for name, mutate in cases:
            with self.subTest(name=name):
                manifest = copy.deepcopy(self.manifest)
                mutate(manifest)
                result = self._stage(manifest=manifest)
                self.assertEqual("MANIFEST_INVALID", result.error_code)

        self.assertFalse(self.staging_root.exists())

    def test_full_coverage_cannot_silently_stage_a_subset(self) -> None:
        manifest = dict(self.manifest)
        manifest["coverage"] = {
            "mode": "mandatory_full_plan",
            "required_fixture_ids": ["fixture-demo", "fixture-second"],
            "mandatory_fixture_ids": ["fixture-demo"],
        }
        second = dict(manifest["fixtures"][0])
        second["fixture_id"] = "fixture-second"
        second["order"] = 1
        manifest["fixtures"] = [manifest["fixtures"][0], second]

        result = self._stage(manifest=manifest)

        self.assertEqual("failed", result.status)
        self.assertEqual("COVERAGE_INCOMPLETE", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_unexpected_source_file_blocks_before_destination_creation(self) -> None:
        (self.source_root / "unlisted.bin").write_bytes(b"unlisted")

        result = self._stage()

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_LAYOUT_MISMATCH", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_source_tree_scan_errors_are_not_ignored(self) -> None:
        def failing_walk(_root, **options):
            onerror = options.get("onerror")
            if onerror is not None:
                onerror(PermissionError("synthetic inaccessible directory"))
            return iter(())

        with mock.patch.object(fixture_staging_files.os, "walk", side_effect=failing_walk):
            result = self._stage()

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_UNAVAILABLE", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_source_and_destination_overlap_is_rejected(self) -> None:
        result = self._stage(staging_root=self.source_root / "staging")

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_DESTINATION_OVERLAP", result.error_code)
        self.assertFalse((self.source_root / "staging").exists())

    def test_unsafe_destination_alias_is_rejected_before_source_overlap(self) -> None:
        linked_parent = self.root / "destination-alias"
        linked_parent.symlink_to(self.source_root, target_is_directory=True)
        destination = linked_parent / "staging"

        result = self._stage(staging_root=destination)

        self.assertEqual("failed", result.status)
        self.assertEqual("DESTINATION_UNSAFE", result.error_code)
        self.assertFalse((self.source_root / "staging").exists())

    def test_destination_root_rejects_group_or_other_writable_ancestors(self) -> None:
        shared_parent = self.root / "shared-parent"
        shared_parent.mkdir(mode=0o700)
        shared_parent.chmod(0o777)
        destination = shared_parent / "staging"

        result = self._stage(staging_root=destination)

        self.assertEqual("failed", result.status)
        self.assertEqual("DESTINATION_UNSAFE", result.error_code)
        self.assertFalse(destination.exists())

    def test_destination_root_rejects_symlinked_ancestors(self) -> None:
        actual_parent = self.root / "actual-parent"
        actual_parent.mkdir(mode=0o700)
        actual_root = actual_parent / "staging"
        actual_root.mkdir(mode=0o700)
        linked_parent = self.root / "linked-parent"
        linked_parent.symlink_to(actual_parent, target_is_directory=True)
        destination = linked_parent / "staging"

        result = self._stage(staging_root=destination)

        self.assertEqual("failed", result.status)
        self.assertEqual("DESTINATION_UNSAFE", result.error_code)

    def test_source_symlink_is_rejected_without_reading_its_target(self) -> None:
        target = self.root / "outside.rom"
        target.write_bytes(self.data)
        source = self.source_root / "game.rom"
        source.unlink()
        source.symlink_to(target)

        result = self._stage()

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_UNSAFE", result.error_code)
        self.assertEqual(self.data, target.read_bytes())

    def test_source_directory_symlink_is_rejected(self) -> None:
        real_directory = self.root / "real-source"
        real_directory.mkdir()
        (real_directory / "game.rom").write_bytes(self.data)
        linked_directory = self.root / "linked-source"
        linked_directory.symlink_to(real_directory, target_is_directory=True)

        result = self._stage(sources={"fixture-demo": linked_directory})

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_UNSAFE", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_source_digest_mismatch_never_publishes_a_fixture(self) -> None:
        (self.source_root / "game.rom").write_bytes(b"x" * len(self.data))

        result = self._stage()

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_DIGEST_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_source_is_read_only_and_transfer_reads_are_bounded(self) -> None:
        source_path = self.source_root / "game.rom"
        data = b"fixture data beyond one bounded chunk"
        source_path.write_bytes(data)
        resolved_source = source_path.resolve(strict=True)
        source_flags: list[int] = []
        read_sizes: list[int] = []
        system_open = fixture_staging_files.os.open
        system_fdopen = fixture_staging_files.os.fdopen

        class RecordingReader:
            def __init__(self, reader):
                self.reader = reader

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                self.reader.close()

            def read(self, size: int = -1) -> bytes:
                read_sizes.append(size)
                return self.reader.read(size)

        def observing_open(path, flags: int, *args, **kwargs):
            if Path(path) == resolved_source:
                source_flags.append(flags)
            return system_open(path, flags, *args, **kwargs)

        def recording_fdopen(descriptor: int, mode: str = "r", *args, **kwargs):
            reader = system_fdopen(descriptor, mode, *args, **kwargs)
            if mode == "rb":
                return RecordingReader(reader)
            return reader

        with (
            mock.patch.object(fixture_staging_files, "COPY_CHUNK_BYTES", 8),
            mock.patch.object(fixture_staging_files.os, "open", side_effect=observing_open),
            mock.patch.object(fixture_staging_files.os, "fdopen", side_effect=recording_fdopen),
        ):
            result = self._stage(manifest=self._manifest(data))

        self.assertEqual("verified", result.status)
        self.assertEqual(1, len(source_flags))
        self.assertEqual(os.O_RDONLY, source_flags[0] & os.O_ACCMODE)
        self.assertGreater(len(read_sizes), 1)
        self.assertTrue(all(size == 8 for size in read_sizes))
        self.assertEqual(data, (result.published_path / "fixture-demo/game.rom").read_bytes())

    def test_source_content_change_during_copy_fails_digest_verification(self) -> None:
        source_path = self.source_root / "game.rom"
        original = self.data + b"x" * 65536
        source_path.write_bytes(original)
        changed = bytes(byte ^ 0xFF for byte in original)
        system_fdopen = fixture_staging_files.os.fdopen
        changed_source = False

        class MutatingReader:
            def __init__(self, reader):
                self.reader = reader

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                self.reader.close()

            def read(self, size: int = -1) -> bytes:
                nonlocal changed_source
                chunk = self.reader.read(size)
                if chunk and not changed_source:
                    source_path.write_bytes(changed)
                    changed_source = True
                return chunk

        def fdopen_with_source_change(descriptor: int, mode: str = "r", *args, **kwargs):
            reader = system_fdopen(descriptor, mode, *args, **kwargs)
            if mode == "rb":
                return MutatingReader(reader)
            return reader

        with (
            mock.patch.object(fixture_staging_files, "COPY_CHUNK_BYTES", 32768),
            mock.patch.object(fixture_staging_files.os, "fdopen", side_effect=fdopen_with_source_change),
        ):
            result = self._stage(manifest=self._manifest(original))

        self.assertEqual("failed", result.status)
        self.assertEqual("SOURCE_DIGEST_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)
        self.assertEqual(changed, source_path.read_bytes())

    def test_destination_write_failure_never_publishes_partial_data(self) -> None:
        system_open = fixture_staging_files.os.open
        system_fdopen = fixture_staging_files.os.fdopen
        staged_descriptors: set[int] = set()

        class FailingWriter:
            def __init__(self, writer):
                self.writer = writer

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                self.writer.close()

            def write(self, _data: bytes) -> int:
                raise OSError("synthetic destination failure")

            def flush(self) -> None:
                self.writer.flush()

            def fileno(self) -> int:
                return self.writer.fileno()

        def identify_staged_file(path, flags: int, *args, **kwargs):
            descriptor = system_open(path, flags, *args, **kwargs)
            if Path(path).name == "game.rom" and flags & os.O_CREAT:
                staged_descriptors.add(descriptor)
            return descriptor

        def fail_destination_write(descriptor: int, mode: str = "r", *args, **kwargs):
            writer = system_fdopen(descriptor, mode, *args, **kwargs)
            if descriptor in staged_descriptors:
                return FailingWriter(writer)
            return writer

        with (
            mock.patch.object(fixture_staging_files.os, "open", side_effect=identify_staged_file),
            mock.patch.object(fixture_staging_files.os, "fdopen", side_effect=fail_destination_write),
        ):
            result = self._stage()

        self.assertEqual("failed", result.status)
        self.assertEqual("TRANSFER_FAILED", result.error_code)
        self.assertIsNone(result.published_path)
        self.assertTrue((result.run_directory / "incomplete/fixture-demo/game.rom").exists())

    def test_initial_capacity_reserve_is_checked_before_destination_creation(self) -> None:
        with mock.patch.object(fixture_staging_files.shutil, "disk_usage", return_value=mock.Mock(free=1)):
            result = self._stage(minimum_free_bytes=2)

        self.assertEqual("failed", result.status)
        self.assertEqual("INSUFFICIENT_SPACE", result.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_cue_bin_playlist_relationships_are_preserved(self) -> None:
        playlist = b"#EXTM3U\ndisc1.cue\ndisc2.cue\n"
        cue = b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n'
        manifest, source_root, contents = self._multidisc_input(playlist, cue)

        result = self._stage(
            manifest=manifest,
            sources={"fixture-demo": source_root},
        )

        self.assertEqual("verified", result.status)
        self.assertEqual(5, result.file_count)
        for relative, data in contents.items():
            self.assertEqual(data, (result.published_path / "fixture-demo" / relative).read_bytes())

    def test_nested_playlist_and_cue_references_resolve_from_descriptor_directory(self) -> None:
        manifest, source_root, contents = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
            nested=True,
        )

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("verified", result.status)
        self.assertEqual(5, result.file_count)
        for relative, data in contents.items():
            self.assertEqual(data, (result.published_path / "fixture-demo" / relative).read_bytes())

    def test_root_playlist_resolves_nested_discs_once_and_preserves_order(self) -> None:
        manifest, source_root, contents = self._multidisc_input(
            b"#EXTM3U\ngames/disc2.cue\ngames/disc1.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
            nested=True,
            playlist_at_root=True,
        )
        fixture = manifest["fixtures"][0]
        fixture["companions"][:2] = reversed(fixture["companions"][:2])

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("verified", result.status)
        self.assertEqual(5, result.file_count)
        self.assertEqual(
            b"#EXTM3U\ngames/disc2.cue\ngames/disc1.cue\n",
            (result.published_path / "fixture-demo/playlist.m3u").read_bytes(),
        )
        for relative, data in contents.items():
            self.assertEqual(data, (result.published_path / "fixture-demo" / relative).read_bytes())

    def test_cue_entrypoint_expectation_is_supported(self) -> None:
        manifest, source_root, contents = self._cue_input()

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("verified", result.status)
        for relative, data in contents.items():
            self.assertEqual(data, (result.published_path / "fixture-demo" / relative).read_bytes())

    def test_wrong_manifest_companion_target_blocks_publication(self) -> None:
        manifest, source_root, _ = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
            nested=True,
        )
        fixture = manifest["fixtures"][0]
        fixture["companions"][:2] = reversed(fixture["companions"][:2])

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_missing_playlist_companion_blocks_publication(self) -> None:
        manifest, source_root, _ = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\nmissing.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_unsafe_playlist_reference_cannot_escape_fixture_root(self) -> None:
        manifest, source_root, _ = self._multidisc_input(
            b"#EXTM3U\n../outside.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_manifest_rejects_unsupported_structural_expectations_before_destination_creation(self) -> None:
        cases = [
            ("unknown key", {"entrypoint_kind": "raw-file", "unvalidated": True}),
            ("unsupported kind", {"entrypoint_kind": "archive"}),
            ("invalid kind type", {"entrypoint_kind": True}),
            ("playlist count on raw file", {"entrypoint_kind": "raw-file", "disc_count": 1}),
            ("cue kind on raw entrypoint", {"entrypoint_kind": "cue"}),
        ]
        for name, expectations in cases:
            with self.subTest(name=name):
                manifest = copy.deepcopy(self.manifest)
                manifest["fixtures"][0]["structural_expectations"] = expectations
                case_root = self.root / f"staging-{name.replace(' ', '-')}"
                result = self._stage(manifest=manifest, staging_root=case_root)
                self.assertEqual("failed", result.status)
                self.assertEqual("MANIFEST_INVALID", result.error_code)
                self.assertFalse(case_root.exists())

        manifest, source_root, _ = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )
        manifest["fixtures"][0]["structural_expectations"]["disc_count"] = True
        invalid_root = self.root / "staging-boolean-disc-count"
        result = self._stage(
            manifest=manifest,
            sources={"fixture-demo": source_root},
            staging_root=invalid_root,
        )
        self.assertEqual("failed", result.status)
        self.assertEqual("MANIFEST_INVALID", result.error_code)
        self.assertFalse(invalid_root.exists())

    def test_incorrect_playlist_disc_count_blocks_publication(self) -> None:
        manifest, source_root, _ = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )
        manifest["fixtures"][0]["structural_expectations"]["disc_count"] = 1

        result = self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_playlist_order_mismatch_blocks_publication(self) -> None:
        playlist = b"#EXTM3U\ndisc2.cue\ndisc1.cue\n"
        cue = b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n'
        manifest, source_root, _ = self._multidisc_input(playlist, cue)

        result = self._stage(
            manifest=manifest,
            sources={"fixture-demo": source_root},
        )

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)
        self.assertIsNone(result.published_path)

    def test_cue_reference_must_match_a_declared_companion(self) -> None:
        playlist = b"#EXTM3U\ndisc1.cue\ndisc2.cue\n"
        cue = b'FILE "missing.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n'
        manifest, source_root, _ = self._multidisc_input(playlist, cue)

        result = self._stage(
            manifest=manifest,
            sources={"fixture-demo": source_root},
        )

        self.assertEqual("failed", result.status)
        self.assertEqual("STRUCTURE_MISMATCH", result.error_code)

    def test_inspection_rechecks_published_bytes(self) -> None:
        staged = self._stage()
        inspected = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("verified", inspected.status)
        self.assertEqual(staged.manifest_sha256, inspected.manifest_sha256)
        self.assertEqual(self.data, (inspected.published_path / "fixture-demo/game.rom").read_bytes())

        (inspected.published_path / "fixture-demo/game.rom").write_bytes(b"tampered")
        altered = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)
        self.assertEqual("failed", altered.status)
        self.assertEqual("PUBLISHED_DIGEST_MISMATCH", altered.error_code)

    def test_published_copy_remains_valid_after_source_is_removed(self) -> None:
        staged = self._stage()
        (self.source_root / "game.rom").unlink()

        inspected = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("verified", inspected.status)
        self.assertEqual(
            self.data,
            (inspected.published_path / "fixture-demo/game.rom").read_bytes(),
        )

    def test_interrupted_copy_is_inspectable_and_retry_starts_a_new_run(self) -> None:
        def interrupt_after_partial_copy(source, destination, _expected, _root, _remaining, _reserve):
            destination.write_bytes(b"partial")
            raise KeyboardInterrupt

        with mock.patch.object(
            fixture_staging_orchestration,
            "_copy_file",
            side_effect=interrupt_after_partial_copy,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage()

        incomplete_run = next(self.staging_root.iterdir())
        partial = incomplete_run / "incomplete/fixture-demo/game.rom"
        inspected = fixture_staging.inspect_staging(incomplete_run.name, staging_root=self.staging_root)

        self.assertEqual("incomplete", inspected.status)
        self.assertEqual("STAGING_INTERRUPTED", inspected.error_code)
        self.assertIsNone(inspected.published_path)
        self.assertEqual(b"partial", partial.read_bytes())

        retry = self._stage()

        self.assertEqual("verified", retry.status)
        self.assertNotEqual(incomplete_run.name, retry.run_id)
        self.assertEqual(b"partial", partial.read_bytes())
        self.assertLess(partial.stat().st_size, len(self.data))

        cleanup = fixture_staging.cleanup_staging(incomplete_run.name, staging_root=self.staging_root)
        self.assertEqual("cleaned", cleanup.status)
        self.assertEqual(1, cleanup.removed_files)
        self.assertFalse(partial.exists())
        self.assertEqual(self.data, (self.source_root / "game.rom").read_bytes())
        repeated = fixture_staging.cleanup_staging(incomplete_run.name, staging_root=self.staging_root)
        self.assertEqual("cleaned", repeated.status)
        self.assertEqual(0, repeated.removed_files)

    def test_cleanup_reclaims_completed_and_partial_files_from_incomplete_tree(self) -> None:
        manifest, source_root, contents = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )
        copy_file = fixture_staging_orchestration._copy_file

        def interrupt_last_file(source, destination, expected, root, remaining, reserve):
            if expected.path == "disc2.bin":
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(b"partial track")
                raise KeyboardInterrupt
            return copy_file(source, destination, expected, root, remaining, reserve)

        with mock.patch.object(
            fixture_staging_orchestration,
            "_copy_file",
            side_effect=interrupt_last_file,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        run_directory = next(self.staging_root.iterdir())
        partial = run_directory / "incomplete/fixture-demo/disc2.bin"
        self.assertEqual(b"partial track", partial.read_bytes())
        for relative, data in contents.items():
            self.assertEqual(data, (source_root / relative).read_bytes())

        cleanup = fixture_staging.cleanup_staging(run_directory.name, staging_root=self.staging_root)

        self.assertEqual("cleaned", cleanup.status)
        self.assertEqual(5, cleanup.removed_files)
        self.assertFalse((run_directory / "incomplete").exists())
        self.assertTrue((run_directory / fixture_staging_runs.RUN_RECORD_NAME).is_file())
        for relative, data in contents.items():
            self.assertEqual(data, (source_root / relative).read_bytes())

    def test_crash_after_publish_rename_preserves_counts_as_incomplete(self) -> None:
        path_type = type(self.source_root)
        path_rename = path_type.rename

        def interrupt_after_publish(path: Path, target: Path) -> Path:
            renamed = path_rename(path, target)
            if path.name == "incomplete":
                raise KeyboardInterrupt
            return renamed

        with mock.patch.object(
            path_type, "rename", autospec=True, side_effect=interrupt_after_publish,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage()

        run_directory = next(self.staging_root.iterdir())
        record = json.loads(
            (run_directory / fixture_staging_runs.RUN_RECORD_NAME).read_text(encoding="utf-8")
        )
        self.assertEqual("staging", record["status"])
        self.assertEqual(1, record["file_count"])
        self.assertEqual(len(self.data), record["byte_count"])

        inspected = fixture_staging.inspect_staging(run_directory.name, staging_root=self.staging_root)

        self.assertEqual("incomplete", inspected.status)
        self.assertEqual("FINALIZATION_INTERRUPTED", inspected.error_code)
        self.assertIsNone(inspected.published_path)

    def test_final_record_write_failure_keeps_run_failed(self) -> None:
        write_record = fixture_staging_orchestration._write_record
        calls = 0

        def fail_final_write(run_directory: Path, record: dict[str, object]) -> None:
            nonlocal calls
            calls += 1
            if calls == 3:
                raise fixture_staging_contract._StagingFailure("RUN_RECORD_WRITE_FAILED")
            write_record(run_directory, record)

        with mock.patch.object(
            fixture_staging_orchestration,
            "_write_record",
            side_effect=fail_final_write,
        ):
            staged = self._stage()

        self.assertEqual("failed", staged.status)
        self.assertEqual("RUN_RECORD_WRITE_FAILED", staged.error_code)
        self.assertTrue((staged.run_directory / "published/fixture-demo/game.rom").is_file())

        inspected = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("failed", inspected.status)
        self.assertEqual("RUN_RECORD_WRITE_FAILED", inspected.error_code)
        self.assertIsNone(inspected.published_path)

        published_file = staged.run_directory / "published/fixture-demo/game.rom"
        published_file.write_bytes(b"modified after interrupted finalization")
        cleanup = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)
        self.assertEqual("cleanup_pending", cleanup.status)
        self.assertEqual("UNRECOGNIZED_CONTENT", cleanup.error_code)
        self.assertEqual(b"modified after interrupted finalization", published_file.read_bytes())

    def test_cleanup_removes_only_manifest_listed_content_and_keeps_tombstone(self) -> None:
        staged = self._stage()
        result = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("cleaned", result.status)
        self.assertEqual(1, result.removed_files)
        self.assertFalse((staged.run_directory / "published").exists())
        record = json.loads(
            (staged.run_directory / fixture_staging_runs.RUN_RECORD_NAME).read_text(encoding="utf-8")
        )
        self.assertEqual("cleaned", record["status"])

    def test_cleanup_reports_filesystem_failure_and_allows_retry(self) -> None:
        manifest, source_root, contents = self._multidisc_input(
            b"#EXTM3U\ndisc1.cue\ndisc2.cue\n",
            b'FILE "disc1.bin" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\n',
        )
        copy_file = fixture_staging_orchestration._copy_file

        def interrupt_last_file(source, destination, expected, root, remaining, reserve):
            if expected.path == "disc2.bin":
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(b"partial track")
                raise KeyboardInterrupt
            return copy_file(source, destination, expected, root, remaining, reserve)

        with mock.patch.object(
            fixture_staging_orchestration,
            "_copy_file",
            side_effect=interrupt_last_file,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage(manifest=manifest, sources={"fixture-demo": source_root})

        run_directory = next(self.staging_root.iterdir())
        partial = run_directory / "incomplete/fixture-demo/disc2.bin"
        original_unlink = Path.unlink

        def fail_partial_unlink(path, *args, **kwargs):
            if path == partial:
                raise PermissionError("synthetic unlink failure")
            return original_unlink(path, *args, **kwargs)

        with mock.patch.object(Path, "unlink", autospec=True, side_effect=fail_partial_unlink):
            cleanup = fixture_staging.cleanup_staging(run_directory.name, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", cleanup.status)
        self.assertEqual("CLEANUP_FAILED", cleanup.error_code)
        self.assertTrue(partial.is_file())
        self.assertEqual(4, cleanup.removed_files)
        record = json.loads(
            (run_directory / fixture_staging_runs.RUN_RECORD_NAME).read_text(encoding="utf-8")
        )
        self.assertEqual("cleanup_pending", record["status"])

        retried = fixture_staging.cleanup_staging(run_directory.name, staging_root=self.staging_root)
        self.assertEqual("cleaned", retried.status)
        self.assertEqual(1, retried.removed_files)
        self.assertFalse(partial.exists())
        for relative, data in contents.items():
            self.assertEqual(data, (source_root / relative).read_bytes())

    def test_cleanup_preserves_unknown_content_in_incomplete_tree(self) -> None:
        def interrupt_after_partial_copy(source, destination, _expected, _root, _remaining, _reserve):
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b"partial")
            raise KeyboardInterrupt

        with mock.patch.object(
            fixture_staging_orchestration,
            "_copy_file",
            side_effect=interrupt_after_partial_copy,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage()

        run_directory = next(self.staging_root.iterdir())
        partial_root = run_directory / "incomplete/fixture-demo"
        partial = partial_root / "game.rom"
        note = partial_root / "owner-note.txt"
        note.write_text("keep", encoding="utf-8")

        cleanup = fixture_staging.cleanup_staging(run_directory.name, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", cleanup.status)
        self.assertEqual("UNRECOGNIZED_CONTENT", cleanup.error_code)
        self.assertFalse(partial.exists())
        self.assertEqual("keep", note.read_text(encoding="utf-8"))

    def test_cleanup_preserves_unexpected_directory_in_incomplete_tree(self) -> None:
        def interrupt_after_partial_copy(source, destination, _expected, _root, _remaining, _reserve):
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b"partial")
            raise KeyboardInterrupt

        with mock.patch.object(
            fixture_staging_orchestration,
            "_copy_file",
            side_effect=interrupt_after_partial_copy,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage()

        run_directory = next(self.staging_root.iterdir())
        fixture_directory = run_directory / "incomplete/fixture-demo"
        unknown = fixture_directory / "owner-data"
        unknown.mkdir()
        (unknown / "keep.txt").write_text("keep", encoding="utf-8")

        cleanup = fixture_staging.cleanup_staging(run_directory.name, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", cleanup.status)
        self.assertEqual("UNRECOGNIZED_CONTENT", cleanup.error_code)
        self.assertFalse((fixture_directory / "game.rom").exists())
        self.assertTrue(unknown.is_dir())
        self.assertEqual("keep", (unknown / "keep.txt").read_text(encoding="utf-8"))

    def test_cleanup_does_not_follow_incomplete_tree_symlink(self) -> None:
        def interrupt_after_partial_copy(source, destination, _expected, _root, _remaining, _reserve):
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b"partial")
            raise KeyboardInterrupt

        with mock.patch.object(
            fixture_staging_orchestration,
            "_copy_file",
            side_effect=interrupt_after_partial_copy,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self._stage()

        run_directory = next(self.staging_root.iterdir())
        target = self.root / "owner-file.txt"
        target.write_text("keep", encoding="utf-8")
        partial = run_directory / "incomplete/fixture-demo/game.rom"
        partial.unlink()
        partial.symlink_to(target)

        cleanup = fixture_staging.cleanup_staging(run_directory.name, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", cleanup.status)
        self.assertTrue(partial.is_symlink())
        self.assertEqual("keep", target.read_text(encoding="utf-8"))

    def test_cleanup_preserves_unrecognized_files(self) -> None:
        staged = self._stage()
        foreign = staged.published_path / "fixture-demo/owner-note.txt"
        foreign.write_text("keep", encoding="utf-8")

        result = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", result.status)
        self.assertEqual("UNRECOGNIZED_CONTENT", result.error_code)
        self.assertTrue(foreign.exists())
        self.assertFalse((staged.published_path / "fixture-demo/game.rom").exists())

    def test_cleanup_does_not_follow_or_remove_symlink_targets(self) -> None:
        staged = self._stage()
        target = self.root / "owner-file.txt"
        target.write_text("keep", encoding="utf-8")
        staged_file = staged.published_path / "fixture-demo/game.rom"
        staged_file.unlink()
        staged_file.symlink_to(target)

        result = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", result.status)
        self.assertTrue(staged_file.is_symlink())
        self.assertEqual("keep", target.read_text(encoding="utf-8"))

    def test_cleanup_preserves_a_replacement_file_with_unexpected_bytes(self) -> None:
        staged = self._stage()
        replacement = b"owner data at a reused path"
        staged_file = staged.published_path / "fixture-demo/game.rom"
        staged_file.write_bytes(replacement)

        result = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("cleanup_pending", result.status)
        self.assertEqual("UNRECOGNIZED_CONTENT", result.error_code)
        self.assertEqual(replacement, staged_file.read_bytes())

    def test_corrupt_run_record_blocks_inspection_and_cleanup(self) -> None:
        staged = self._stage()
        marker = staged.run_directory / fixture_staging_runs.RUN_RECORD_NAME
        marker.write_text('{"status":"verified","status":"cleaned"}', encoding="utf-8")

        inspected = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)
        cleaned = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("failed", inspected.status)
        self.assertEqual("RUN_RECORD_INVALID", inspected.error_code)
        self.assertEqual("failed", cleaned.status)
        self.assertEqual("RUN_RECORD_INVALID", cleaned.error_code)
        self.assertTrue((staged.published_path / "fixture-demo/game.rom").exists())

    def test_missing_run_record_blocks_cleanup(self) -> None:
        staged = self._stage()
        (staged.run_directory / fixture_staging_runs.RUN_RECORD_NAME).unlink()

        cleaned = fixture_staging.cleanup_staging(staged.run_id, staging_root=self.staging_root)

        self.assertEqual("failed", cleaned.status)
        self.assertEqual("RUN_RECORD_INVALID", cleaned.error_code)
        self.assertTrue((staged.published_path / "fixture-demo/game.rom").exists())

    def test_inspection_rejects_malformed_run_record_fields(self) -> None:
        staged = self._stage()
        marker = staged.run_directory / fixture_staging_runs.RUN_RECORD_NAME
        original = json.loads(marker.read_text(encoding="utf-8"))
        cases = [
            ("missing required field", lambda record: record.pop("status")),
            ("unknown run field", lambda record: record.update(extra=True)),
            ("unsupported run schema", lambda record: record.update(schema_version=True)),
            ("run id mismatch", lambda record: record.update(run_id="0" * 32)),
            ("invalid status type", lambda record: record.update(status=[])),
            ("owner approval missing", lambda record: record.update(owner_approved=False)),
            ("invalid timestamp", lambda record: record.update(created_at=" ")),
            ("invalid manifest digest", lambda record: record.update(manifest_sha256="bad")),
            ("negative capacity reserve", lambda record: record.update(minimum_free_bytes=-1)),
            ("boolean file count", lambda record: record.update(file_count=True)),
            ("negative byte count", lambda record: record.update(byte_count=-1)),
            ("invalid selected ids", lambda record: record.update(selected_fixture_ids="fixture-demo")),
            ("empty fixtures", lambda record: record.update(fixtures=[])),
            ("unknown fixture field", lambda record: record["fixtures"][0].update(extra=True)),
            ("invalid entrypoint", lambda record: record["fixtures"][0].update(entrypoint="../outside")),
            ("empty structure", lambda record: record["fixtures"][0].update(structural_expectations={})),
            ("unknown structural expectation", lambda record: record["fixtures"][0]["structural_expectations"].update(unvalidated=True)),
            ("inapplicable playlist count", lambda record: record["fixtures"][0]["structural_expectations"].update(disc_count=1)),
            ("invalid identity support", lambda record: record["fixtures"][0].update(identity_support=[])),
            ("unknown identity support", lambda record: record["fixtures"][0].update(identity_support="independently_verified")),
            ("identity support does not match evidence", lambda record: record["fixtures"][0].update(identity_support="synthetic_only")),
            ("false qualification", lambda record: record["fixtures"][0].update(qualification_status="qualified")),
            ("empty file inventory", lambda record: record["fixtures"][0].update(files=[])),
            ("unknown file field", lambda record: record["fixtures"][0]["files"][0].update(extra=True)),
            ("invalid file path", lambda record: record["fixtures"][0]["files"][0].update(path="../outside")),
            ("invalid file role", lambda record: record["fixtures"][0]["files"][0].update(role=" role ")),
            ("boolean file size", lambda record: record["fixtures"][0]["files"][0].update(size=True)),
            ("invalid file digest", lambda record: record["fixtures"][0]["files"][0].update(sha256="bad")),
            ("invalid companion list", lambda record: record["fixtures"][0].update(companions={})),
            ("unknown companion field", lambda record: record["fixtures"][0].update(companions=[{"source": "game.rom", "target": "game.rom", "extra": 1}])),
            ("entrypoint absent from files", lambda record: record["fixtures"][0].update(entrypoint="other.rom")),
            ("unreachable file", lambda record: record["fixtures"][0]["files"].append({"path": "other.rom", "role": "content", "size": 1, "sha256": hashlib.sha256(b"x").hexdigest()})),
            ("self-referential companion", lambda record: record["fixtures"][0].update(companions=[{"source": "game.rom", "target": "game.rom"}])),
        ]

        for name, mutate in cases:
            with self.subTest(name=name):
                record = copy.deepcopy(original)
                mutate(record)
                marker.write_text(json.dumps(record), encoding="utf-8")
                inspected = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)
                self.assertEqual("RUN_RECORD_INVALID", inspected.error_code)

        marker.write_text(json.dumps(original), encoding="utf-8")
        self.assertEqual("verified", fixture_staging.inspect_staging(
            staged.run_id, staging_root=self.staging_root
        ).status)

    def test_invalid_run_ids_do_not_access_the_staging_root(self) -> None:
        inspected = fixture_staging.inspect_staging("../outside", staging_root=self.staging_root)
        cleaned = fixture_staging.cleanup_staging("../outside", staging_root=self.staging_root)

        self.assertEqual("RUN_ID_INVALID", inspected.error_code)
        self.assertEqual("RUN_ID_INVALID", cleaned.error_code)
        self.assertFalse(self.staging_root.exists())

    def test_manifest_rejects_case_collisions_and_file_directory_conflicts(self) -> None:
        collision_data = b"other"
        collision = dict(self.manifest)
        fixture = dict(collision["fixtures"][0])
        fixture["files"] = [
            *fixture["files"],
            {
                "path": "GAME.rom",
                "role": "content",
                "size": len(collision_data),
                "sha256": hashlib.sha256(collision_data).hexdigest(),
            },
        ]
        fixture["companions"] = [{"source": "game.rom", "target": "GAME.rom"}]
        collision["fixtures"] = [fixture]

        result = self._stage(manifest=collision)
        self.assertEqual("MANIFEST_INVALID", result.error_code)
        self.assertFalse(self.staging_root.exists())

        conflict = dict(self.manifest)
        conflict_fixture = dict(conflict["fixtures"][0])
        child_data = b"child"
        conflict_fixture["files"] = [
            *conflict_fixture["files"],
            {
                "path": "game.rom/child.bin",
                "role": "content",
                "size": len(child_data),
                "sha256": hashlib.sha256(child_data).hexdigest(),
            },
        ]
        conflict_fixture["companions"] = [{"source": "game.rom", "target": "game.rom/child.bin"}]
        conflict["fixtures"] = [conflict_fixture]
        nested = self._stage(manifest=conflict)
        self.assertEqual("MANIFEST_INVALID", nested.error_code)

    def test_inspection_rejects_unlisted_files_and_empty_directories(self) -> None:
        staged = self._stage()
        (staged.published_path / "unexpected.txt").write_text("extra", encoding="utf-8")
        extra_root_file = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)
        self.assertEqual("failed", extra_root_file.status)
        self.assertEqual("PUBLISHED_SET_INCOMPLETE", extra_root_file.error_code)
        (staged.published_path / "unexpected.txt").unlink()

        (staged.published_path / "fixture-demo/empty-dir").mkdir()
        extra_directory = fixture_staging.inspect_staging(staged.run_id, staging_root=self.staging_root)
        self.assertEqual("failed", extra_directory.status)
        self.assertEqual("PUBLISHED_SET_INCOMPLETE", extra_directory.error_code)

    def test_partial_plan_requires_explicit_authorized_coverage(self) -> None:
        manifest = dict(self.manifest)
        second = dict(manifest["fixtures"][0])
        second["fixture_id"] = "fixture-second"
        second["group_id"] = "group-second"
        manifest["fixtures"] = [manifest["fixtures"][0], second]
        manifest["coverage"] = {
            "mode": "authorized_partial_plan",
            "required_fixture_ids": ["fixture-demo", "fixture-second"],
            "mandatory_fixture_ids": ["fixture-demo"],
        }
        selected = self._stage(manifest=manifest)
        self.assertEqual("verified", selected.status)
        self.assertEqual(("fixture-demo",), selected.fixture_ids)

        omitted_mandatory = self._stage(
            manifest=manifest,
            selected_fixture_ids=("fixture-second",),
            sources={"fixture-second": self.source_root},
        )
        self.assertEqual("COVERAGE_INCOMPLETE", omitted_mandatory.error_code)

    def test_capacity_loss_after_run_creation_leaves_recognizable_cleanup(self) -> None:
        with mock.patch.object(
            fixture_staging_orchestration,
            "_check_capacity",
            side_effect=[None, fixture_staging_contract._StagingFailure("INSUFFICIENT_SPACE")],
        ):
            interrupted = self._stage()

        self.assertEqual("failed", interrupted.status)
        self.assertEqual("INSUFFICIENT_SPACE", interrupted.error_code)
        cleanup = fixture_staging.cleanup_staging(interrupted.run_id, staging_root=self.staging_root)
        self.assertEqual("cleaned", cleanup.status)
        self.assertEqual(1, cleanup.removed_files)


if __name__ == "__main__":
    unittest.main()
