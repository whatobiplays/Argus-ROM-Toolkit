"""Focused host-only tests for source membership and descriptor identity enforcement."""

from __future__ import annotations

from scripts.android_qualification import _fixture_staging_content as staging_content
from scripts.android_qualification import _fixture_staging_destination as staging_destination
from scripts.android_qualification import _fixture_staging_manifest as staging_manifest
from scripts.android_qualification import _fixture_staging_model as staging_model
from scripts.android_qualification import _fixture_staging_ownership as staging_ownership
from scripts.android_qualification._fixture_staging_test_support import _sync_oracle
from scripts.android_qualification._fixture_staging_test_support import _cleanup_fixture_staging_for_synthetic_mechanics, _stage_fixtures_for_synthetic_mechanics
from scripts.android_qualification._fixture_staging_test_support import _SyntheticFilesystemFixtureDestination
from scripts.android_qualification.test_manifest import NOW
import copy
import hashlib
import os
from pathlib import Path
from types import SimpleNamespace
from typing import get_type_hints
from unittest.mock import patch
from scripts.android_qualification._fixture_staging_test_support import FixtureStagingTestCase


class FixtureStagingContentTests(FixtureStagingTestCase):
    def test_documented_annotations_resolve_to_concrete_types(self) -> None:
        content_hints = get_type_hints(
            staging_content._destination_companion_edges,
            localns={
                "FilesystemFixtureDestination": staging_destination.FilesystemFixtureDestination,
            },
        )
        self.assertIs(
            content_hints["destination"],
            staging_destination.FilesystemFixtureDestination,
        )
        self.assertIs(content_hints["grant"], staging_model.FixtureStagingGrant)

        ownership_hints = get_type_hints(
            staging_ownership.FixtureStagingOwnership.record_verified_file,
        )
        self.assertIs(
            ownership_hints["expectation"],
            staging_model.FixtureFileExpectation,
        )

    def _use_nested_source_fixture(self, content: bytes) -> None:
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        expected = fixture["files"][0]
        fixture["entrypoint"] = "assets/game.rom"
        expected.update(
            {
                "path": "assets/game.rom",
                "size": len(content),
                "sha256": hashlib.sha256(content).hexdigest(),
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)

    def test_1200_path_companion_chain_is_validated_without_recursion(self) -> None:
        count = 1200
        paths = tuple(f"parts/part-{index:04}.rom" for index in range(count))
        files = tuple(
            staging_model.FixtureFileExpectation(path, "rom", 1, "a" * 64)
            for path in paths
        )
        edges = tuple(
            staging_model.CompanionEdge(paths[index], paths[index + 1])
            for index in range(count - 1)
        )
        fixture = staging_model.FixtureExpectation(
            "fixture-long-chain",
            "synthetic-platform",
            "synthetic-representation",
            "synthetic-identity",
            "synthetic-group",
            0,
            paths[0],
            files,
            edges,
            staging_model.IdentityEvidenceKind.OWNER_APPROVED_EXPECTATION_MATCH,
        )
        snapshots = tuple(SimpleNamespace(expectation=item) for item in files)

        staging_manifest._validate_declared_companion_graph(fixture)
        with patch.object(staging_content, "_descriptor_edges", return_value=edges):
            staging_content._validate_companion_graph(
                fixture, self.directory, snapshots
            )
        self.assertTrue(staging_content._graph_reaches_all(fixture, edges))

    def test_source_hash_mismatch_is_blocked_without_publishing_partial_bytes(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"game.rom": b"x" * len(b"synthetic-rom-content-v1")}
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_CHANGED.value
        )
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertTrue(destination.recovery_state_path(result.session_id).is_file())

    def test_unlisted_source_member_blocks_staging(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        (source_root / "unlisted.bin").write_bytes(b"synthetic extra member")

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.SOURCE_INVALID.value,
        )
        self.assertFalse(any(destination.root.glob(".fixture-*.partial")))

    def test_cue_graph_requires_every_referenced_track_and_preserves_relative_layout(self) -> None:
        api = self._require_staging_module()
        cue = b'FILE "track 01.bin" BINARY\n TRACK 01 MODE1/2352\n INDEX 01 00:00:00\n'
        track = b"synthetic-track-data"
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture.update(
            {
                "entrypoint": "disc.cue",
                "files": [
                    {
                        "path": "disc.cue",
                        "role": "cue",
                        "size": len(cue),
                        "sha256": hashlib.sha256(cue).hexdigest(),
                    },
                    {
                        "path": "track 01.bin",
                        "role": "track",
                        "size": len(track),
                        "sha256": hashlib.sha256(track).hexdigest(),
                    },
                ],
                "companions": [
                    {"source": "disc.cue", "target": "track 01.bin"}
                ],
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"disc.cue": cue, "track 01.bin": track}
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)
        staged = destination._synthetic_final_path(result.session_id) / "fixture-synthetic"
        self.assertEqual((staged / "disc.cue").read_bytes(), cue)
        self.assertEqual((staged / "track 01.bin").read_bytes(), track)

    def test_missing_cue_companion_is_blocked(self) -> None:
        api = self._require_staging_module()
        cue = b'FILE "missing.bin" BINARY\n TRACK 01 MODE1/2352\n'
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture.update(
            {
                "entrypoint": "disc.cue",
                "files": [
                    {
                        "path": "disc.cue",
                        "role": "cue",
                        "size": len(cue),
                        "sha256": hashlib.sha256(cue).hexdigest(),
                    }
                ],
                "companions": [],
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"disc.cue": cue}
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_INVALID.value
        )
        self.assertFalse(any(destination.root.glob("fixture-*")))

    def test_playlist_graph_requires_every_track_and_rejects_cycles(self) -> None:
        api = self._require_staging_module()
        playlist = b"#EXTM3U\ntracks/track01.rom\n"
        track = b"synthetic-playlist-track"
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture.update(
            {
                "entrypoint": "game.m3u",
                "files": [
                    {
                        "path": "game.m3u",
                        "role": "playlist",
                        "size": len(playlist),
                        "sha256": hashlib.sha256(playlist).hexdigest(),
                    },
                    {
                        "path": "tracks/track01.rom",
                        "role": "track",
                        "size": len(track),
                        "sha256": hashlib.sha256(track).hexdigest(),
                    },
                ],
                "companions": [
                    {"source": "game.m3u", "target": "tracks/track01.rom"}
                ],
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"game.m3u": playlist, "tracks/track01.rom": track},
            suffix="-playlist-valid",
        )
        valid = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(valid.status, "VERIFIED_FIXTURE", valid.blocker_code)

        missing_fixture_document = copy.deepcopy(fixture_document)
        self._rebind_inputs(fixture_manifest=missing_fixture_document)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"game.m3u": playlist}, suffix="-playlist-missing"
        )
        missing = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(missing.status, "BLOCKED")
        self.assertEqual(
            missing.blocker_code,
            api.FixtureStagingErrorCode.SOURCE_INVALID.value,
        )

        cyclic_playlist = b"#EXTM3U\ngame.m3u\n"
        fixture_document = copy.deepcopy(self.fixture_document)
        fixture = fixture_document["fixtures"][0]
        fixture.update(
            {
                "entrypoint": "game.m3u",
                "files": [
                    {
                        "path": "game.m3u",
                        "role": "playlist",
                        "size": len(cyclic_playlist),
                        "sha256": hashlib.sha256(cyclic_playlist).hexdigest(),
                    }
                ],
                "companions": [
                    {"source": "game.m3u", "target": "game.m3u"}
                ],
            }
        )
        _sync_oracle(fixture)
        self._rebind_inputs(fixture_manifest=fixture_document)
        with self.assertRaises(api.FixtureStagingError) as cycle:
            self._authorize()
        self.assertEqual(
            cycle.exception.code,
            api.FixtureStagingErrorCode.MANIFEST_INVALID,
        )

    def test_symlink_and_hardlink_source_aliases_are_rejected(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        root_identity = staging_content._source_root_identity(source_root)
        identities = staging_content._validate_source_membership(
            source_root,
            ("game.rom",),
            root_identity,
        )
        with self.assertRaises(api.FixtureStagingError) as traversal:
            staging_content._open_source_member(
                source_root,
                "../outside.rom",
                identities,
            )
        self.assertEqual(
            traversal.exception.code, api.FixtureStagingErrorCode.INPUT_INVALID
        )
        source = source_root / "game.rom"
        outside = self.directory / "outside.rom"
        outside.write_bytes(source.read_bytes())
        source.unlink()
        source.symlink_to(outside)

        symlink_result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(symlink_result.status, "BLOCKED")
        self.assertEqual(
            symlink_result.blocker_code,
            api.FixtureStagingErrorCode.SOURCE_INVALID.value,
        )

        source.unlink()
        source.write_bytes(b"synthetic-rom-content-v1")
        outside.unlink()
        outside.hardlink_to(source)
        hardlink_result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )
        self.assertEqual(hardlink_result.status, "BLOCKED")
        self.assertEqual(
            hardlink_result.blocker_code,
            api.FixtureStagingErrorCode.SOURCE_INVALID.value,
        )

    def test_source_mutation_during_stream_is_blocked_without_publication(self) -> None:
        api = self._require_staging_module()
        source_path = self.directory / "source" / "game.rom"
        calls = 0

        def observe(_root):
            nonlocal calls
            calls += 1
            if calls == 3:
                source_path.write_bytes(b"y" * len(b"synthetic-rom-content-v1"))
            return api.CapacityObservation(10**12, 10**12)

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=observe
        )
        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            api.FixtureStagingErrorCode.SOURCE_CHANGED.value,
        )
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())
        self.assertEqual(destination._ownership.recovery_obligations()[0].state, "blocked")

    def test_source_and_readback_descriptor_parsers_share_line_limits(self) -> None:
        api = self._require_staging_module()
        source_root = self.directory / "descriptor-source"
        source_root.mkdir(mode=0o700)
        reference = "a" * 4084
        encoded_line = f"FILE {reference} BINARY\n".encode("utf-8")
        self.assertEqual(len(encoded_line), staging_content._MAX_DESCRIPTOR_LINE_BYTES + 1)
        descriptor_path = source_root / "game.cue"
        descriptor_path.write_bytes(encoded_line)
        info = descriptor_path.stat()
        canonical_root, (root_device, root_inode), root_hierarchy = (
            staging_content._discover_source_root(source_root)
        )
        directory_identities = staging_content._DirectoryIdentityTable(
            (("", (root_device, root_inode)),),
            root_hierarchy,
        )
        expected = staging_model.FixtureFileExpectation(
            "game.cue",
            "descriptor",
            len(encoded_line),
            hashlib.sha256(encoded_line).hexdigest(),
        )
        fixture = staging_model.FixtureExpectation(
            "fixture-synthetic",
            "Synthetic Platform",
            "disc-image",
            "Synthetic Game",
            "group-synthetic",
            0,
            "game.cue",
            (expected,),
            (),
            staging_model.IdentityEvidenceKind.OWNER_APPROVED_EXPECTATION_MATCH,
        )
        snapshot = staging_content._SourceSnapshot(
            fixture.fixture_id,
            expected,
            canonical_root,
            root_device,
            root_inode,
            staging_content._file_identity(info),
            directory_identities,
            root_hierarchy,
        )

        with patch.object(
            staging_content,
            "_parse_companion_lines",
            wraps=staging_content._parse_companion_lines,
        ) as parse_companion_lines:
            with self.assertRaises(api.FixtureStagingError) as source_error:
                staging_content._descriptor_edges(fixture, canonical_root, (snapshot,))
        parse_companion_lines.assert_called_once()
        with self.assertRaises(api.FixtureStagingError) as readback_error:
            staging_content._parse_companion_lines(
                "game.cue",
                staging_content._iter_lines(
                    (encoded_line,), error_code=api.FixtureStagingErrorCode.COPY_INVALID
                ),
                error_code=api.FixtureStagingErrorCode.COPY_INVALID,
            )

        self.assertEqual(
            source_error.exception.code, api.FixtureStagingErrorCode.SOURCE_INVALID
        )
        self.assertEqual(
            readback_error.exception.code, api.FixtureStagingErrorCode.COPY_INVALID
        )

    def test_case_insensitive_source_destination_alias_blocks_before_any_write(self) -> None:
        api, source_root, _destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,)
        destination_alias = source_root.with_name(source_root.name.swapcase())
        try:
            same_directory = os.path.samefile(source_root, destination_alias)
        except OSError:
            same_directory = False
        if not same_directory:
            self.skipTest("temporary volume is case-sensitive")
        before = {
            path.relative_to(source_root).as_posix(): path.read_bytes()
            for path in source_root.rglob("*")
            if path.is_file()
        }
        destination = _SyntheticFilesystemFixtureDestination(
            destination_alias, capability=self.synthetic_capability
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_INVALID.value
        )
        after = {
            path.relative_to(source_root).as_posix(): path.read_bytes()
            for path in source_root.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)
        self.assertFalse((source_root / destination._STATE_DIRECTORY).exists())

    def test_unsupported_descriptor_primitives_fail_closed(self) -> None:
        api = self._require_staging_module()
        source_root = self.directory / "unsupported-source"
        source_root.mkdir(mode=0o700)

        with patch.object(staging_content.os, "supports_dir_fd", set()):
            with self.assertRaises(api.FixtureStagingError) as captured:
                staging_content._source_root_identity(source_root)

        self.assertEqual(
            captured.exception.code, api.FixtureStagingErrorCode.SOURCE_INVALID
        )

    def test_unchanged_nested_directory_identity_chain_is_staged(self) -> None:
        content = b"synthetic-nested-content"
        self._use_nested_source_fixture(content)
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"assets/game.rom": content},
            suffix="-nested-valid",
        )
        root_identity = staging_content._source_root_identity(source_root)
        identities = dict(
            staging_content._validate_source_membership(
                source_root,
                ("assets/game.rom",),
                root_identity,
            )
        )
        assets_info = (source_root / "assets").stat(follow_symlinks=False)
        self.assertEqual(
            identities,
            {
                "": root_identity,
                "assets": (assets_info.st_dev, assets_info.st_ino),
            },
        )

        result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)
        staged = destination._synthetic_final_path(result.session_id) / "fixture-synthetic"
        self.assertEqual((staged / "assets/game.rom").read_bytes(), content)

    def test_directory_identity_mismatch_is_rejected_for_normal_pathname(self) -> None:
        api = self._require_staging_module()
        content = b"synthetic-nested-content"
        self._use_nested_source_fixture(content)
        _api, source_root, _destination, _grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"assets/game.rom": content},
            suffix="-identity-mismatch",
        )
        root_identity = staging_content._source_root_identity(source_root)
        identities = staging_content._validate_source_membership(
            source_root,
            ("assets/game.rom",),
            root_identity,
        )
        asset_identity = dict(identities)["assets"]
        mismatched = tuple(
            (path, (identity[0], identity[1] + 1) if path == "assets" else identity)
            for path, identity in identities
        )

        with self.assertRaises(api.FixtureStagingError) as captured:
            descriptor, parent_descriptor, _basename, _opened, _identity = (
                staging_content._open_source_member(
                    source_root,
                    "assets/game.rom",
                    mismatched,
                    root_hierarchy=identities.root_hierarchy,
                )
            )
        self.assertEqual(
            captured.exception.code, api.FixtureStagingErrorCode.SOURCE_CHANGED
        )
        self.assertFalse((source_root / "assets").is_symlink())
        self.assertNotEqual(asset_identity, mismatched[1][1])

    def test_root_replacement_after_discovery_is_rejected_without_source_read(self) -> None:
        api = self._require_staging_module()
        suffix = "-root-replacement"
        source_root = self.directory / f"source{suffix}"
        replacement_root = self.directory / "replacement-root"
        replacement_root.mkdir(mode=0o700)
        replacement_file = replacement_root / "game.rom"
        replacement_file.write_bytes(b"z" * len(b"synthetic-rom-content-v1"))
        replacement_info = replacement_file.stat(follow_symlinks=False)
        replacement_identity = (replacement_info.st_dev, replacement_info.st_ino)
        replaced = False

        def observe(_root):
            nonlocal replaced
            if not replaced:
                source_root.rename(self.directory / "original-root")
                replacement_root.rename(source_root)
                replaced = True
            return api.CapacityObservation(10**12, 10**12)

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=observe,
            suffix=suffix,
        )
        substituted_reads: list[tuple[int, int]] = []
        discovery_calls = 0
        real_discover = staging_content._discover_source_root
        real_read = os.read

        def count_discovery(root: Path):
            nonlocal discovery_calls
            discovery_calls += 1
            return real_discover(root)

        def observe_read(descriptor: int, size: int) -> bytes:
            opened = os.fstat(descriptor)
            identity = (opened.st_dev, opened.st_ino)
            if identity == replacement_identity:
                substituted_reads.append(identity)
            return real_read(descriptor, size)

        with (
            patch.object(
                staging_content, "_discover_source_root", side_effect=count_discovery
            ),
            patch.object(staging_content.os, "read", side_effect=observe_read),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertTrue(replaced)
        self.assertEqual(discovery_calls, 1)
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_CHANGED.value
        )
        self.assertEqual(substituted_reads, [])
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())

    def test_regular_member_swapped_to_fifo_is_rejected_without_blocking_or_read(
        self,
    ) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-fifo-race"
        )
        source_path = source_root / "game.rom"
        substituted = b"F" * len(b"synthetic-rom-content-v1")
        real_open = os.open
        real_close = os.close
        real_read = os.read
        fifo_descriptor = -1
        fifo_reads: list[int] = []

        def racing_open(path, flags, *args, **kwargs):
            nonlocal fifo_descriptor
            if os.fspath(path) == "game.rom" and not flags & os.O_DIRECTORY:
                self.assertTrue(flags & os.O_NONBLOCK)
                source_path.unlink()
                os.mkfifo(source_path)
                fifo_descriptor = real_open(path, flags, *args, **kwargs)
                writer = real_open(source_path, os.O_WRONLY | os.O_NONBLOCK)
                try:
                    self.assertEqual(os.write(writer, substituted), len(substituted))
                finally:
                    real_close(writer)
                return fifo_descriptor
            return real_open(path, flags, *args, **kwargs)

        def observing_close(descriptor: int) -> None:
            nonlocal fifo_descriptor
            real_close(descriptor)
            if descriptor == fifo_descriptor:
                fifo_descriptor = -1

        def observing_read(descriptor: int, size: int) -> bytes:
            if descriptor == fifo_descriptor:
                fifo_reads.append(descriptor)
            return real_read(descriptor, size)

        patched_open_support = set(os.supports_dir_fd)
        patched_open_support.add(racing_open)
        # The open double injects the race at the scanner boundary; the scanner
        # must request nonblocking mode before this substituted descriptor exists.
        with (
            patch.object(
                staging_content.os, "supports_dir_fd", patched_open_support
            ),
            patch.object(staging_content.os, "open", new=racing_open),
            patch.object(staging_content.os, "close", side_effect=observing_close),
            patch.object(staging_content.os, "read", side_effect=observing_read),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_CHANGED.value
        )
        self.assertEqual(fifo_reads, [])
        self.assertFalse(any(destination.root.glob("fixture-*")))

    def test_replaced_symlink_ancestor_is_rejected_without_source_read(self) -> None:
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            suffix="-ancestor-race"
        )
        race_parent = self.directory / "race-parent"
        race_parent.mkdir(mode=0o700)
        source_root.rename(race_parent / "source")
        raced_root = race_parent / "source"
        substituted = b"z" * len(b"synthetic-rom-content-v1")
        real_discover = staging_content._discover_source_root
        real_read = os.read
        replaced = False
        discovery_calls = 0
        observed = bytearray()

        def discover_then_replace(root: Path):
            nonlocal discovery_calls, replaced
            discovery_calls += 1
            discovered = real_discover(root)
            if not replaced:
                moved_parent = self.directory / "moved-parent"
                race_parent.rename(moved_parent)
                (moved_parent / "source" / "game.rom").write_bytes(substituted)
                race_parent.symlink_to(moved_parent, target_is_directory=True)
                replaced = True
            return discovered

        def observe_read(descriptor: int, size: int) -> bytes:
            chunk = real_read(descriptor, size)
            observed.extend(chunk)
            return chunk

        with (
            patch.object(
                staging_content, "_discover_source_root", side_effect=discover_then_replace
            ),
            patch.object(staging_content.os, "read", side_effect=observe_read),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": raced_root},
                destination=destination,
                now=NOW,
            )

        self.assertTrue(replaced)
        self.assertEqual(discovery_calls, 1)
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_CHANGED.value
        )
        self.assertNotIn(substituted, observed)
        self.assertFalse(any(destination.root.glob("fixture-*")))

    def test_intermediate_replacement_after_discovery_is_rejected_without_source_read(
        self,
    ) -> None:
        api = self._require_staging_module()
        content = b"synthetic-nested-content"
        self._use_nested_source_fixture(content)
        suffix = "-intermediate-replacement"
        source_root = self.directory / f"source{suffix}"
        replacement_assets = self.directory / "replacement-assets"
        replacement_assets.mkdir(mode=0o700)
        replacement_file = replacement_assets / "game.rom"
        replacement_file.write_bytes(b"q" * len(content))
        replacement_info = replacement_file.stat(follow_symlinks=False)
        replacement_identity = (replacement_info.st_dev, replacement_info.st_ino)
        replaced = False

        def observe(_root):
            nonlocal replaced
            if not replaced:
                assets = source_root / "assets"
                assets.rename(self.directory / "original-assets")
                replacement_assets.rename(assets)
                replaced = True
            return api.CapacityObservation(10**12, 10**12)

        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            capacity_observer=observe,
            source_entries={"assets/game.rom": content},
            suffix=suffix,
        )
        substituted_reads: list[tuple[int, int]] = []
        discovery_calls = 0
        real_discover = staging_content._discover_source_root
        real_read = os.read

        def count_discovery(root: Path):
            nonlocal discovery_calls
            discovery_calls += 1
            return real_discover(root)

        def observe_read(descriptor: int, size: int) -> bytes:
            opened = os.fstat(descriptor)
            identity = (opened.st_dev, opened.st_ino)
            if identity == replacement_identity:
                substituted_reads.append(identity)
            return real_read(descriptor, size)

        with (
            patch.object(
                staging_content, "_discover_source_root", side_effect=count_discovery
            ),
            patch.object(staging_content.os, "read", side_effect=observe_read),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertTrue(replaced)
        self.assertEqual(discovery_calls, 1)
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_CHANGED.value
        )
        self.assertEqual(substituted_reads, [])
        self.assertFalse(destination._synthetic_final_path(result.session_id).exists())

    def test_early_ancestor_replacement_stops_before_opening_later_components(
        self,
    ) -> None:
        api = self._require_staging_module()
        content = b"synthetic-ancestor-content"
        api, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            source_entries={"game.rom": content},
            suffix="-early-ancestor-replacement",
        )
        outer_root = self.directory / "outer"
        outer_root.mkdir(mode=0o700)
        source_root.rename(outer_root / "source")
        source_root = outer_root / "source"

        replacement_outer = self.directory / "replacement-outer"
        replacement_root = replacement_outer / "source"
        replacement_root.mkdir(parents=True, mode=0o700)
        replacement_file = replacement_root / "game.rom"
        replacement_file.write_bytes(b"q" * len(content))
        replacement_info = replacement_file.stat(follow_symlinks=False)
        replacement_identity = (replacement_info.st_dev, replacement_info.st_ino)

        real_discover = staging_content._discover_source_root
        real_open = os.open
        real_read = os.read
        replaced = False
        race_armed = False
        discovery_calls = 0
        opened_after_replacement: list[str] = []
        substituted_reads: list[tuple[int, int]] = []

        def discover_then_replace(root: Path):
            nonlocal discovery_calls, race_armed, replaced
            discovery_calls += 1
            discovered = real_discover(root)
            if not replaced:
                outer_root.rename(self.directory / "original-outer")
                replacement_outer.rename(outer_root)
                replaced = True
                race_armed = True
            return discovered

        def observe_open(path, flags, *args, **kwargs):
            if race_armed and kwargs.get("dir_fd") is not None:
                opened_after_replacement.append(os.fspath(path))
            return real_open(path, flags, *args, **kwargs)

        def observe_read(descriptor: int, size: int) -> bytes:
            opened = os.fstat(descriptor)
            identity = (opened.st_dev, opened.st_ino)
            if identity == replacement_identity:
                substituted_reads.append(identity)
            return real_read(descriptor, size)

        patched_open_support = set(os.supports_dir_fd)
        patched_open_support.add(observe_open)

        with (
            patch.object(
                staging_content,
                "_discover_source_root",
                side_effect=discover_then_replace,
            ),
            patch.object(staging_content.os, "open", new=observe_open),
            patch.object(
                staging_content.os,
                "supports_dir_fd",
                patched_open_support,
            ),
            patch.object(staging_content.os, "read", side_effect=observe_read),
        ):
            result = _stage_fixtures_for_synthetic_mechanics(self.synthetic_capability,
                grant,
                source_roots={"fixture-synthetic": source_root},
                destination=destination,
                now=NOW,
            )

        self.assertTrue(
            replaced,
            f"status={result.status} blocker={result.blocker_code} discoveries={discovery_calls}",
        )
        self.assertEqual(discovery_calls, 1)
        self.assertIn("outer", opened_after_replacement)
        self.assertNotIn("source", opened_after_replacement)
        self.assertEqual(substituted_reads, [])
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, api.FixtureStagingErrorCode.SOURCE_CHANGED.value
        )
        self.assertFalse(any(destination.root.glob("fixture-*")))
