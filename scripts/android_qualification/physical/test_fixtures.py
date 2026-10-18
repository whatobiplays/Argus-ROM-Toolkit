"""Exercise read-only inspection and staging using generated temporary data only."""

import io
import json
import os
from contextlib import redirect_stderr
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from scripts.android_qualification.physical.fixtures import inspect_fixtures, inventory, select_fixtures


class NoAddNoteMixin:
    def __getattribute__(self, name):
        if name == 'add_note':
            raise AttributeError(name)
        return super().__getattribute__(name)


class LegacyInterruptedError(NoAddNoteMixin, InterruptedError):
    pass


class LegacyKeyboardInterrupt(NoAddNoteMixin, KeyboardInterrupt):
    pass


def nes(trainer=False):
    header = bytearray(b'NES\x1a' + bytes(12))
    header[4] = 1
    header[6] = 4 if trainer else 0
    return bytes(header) + bytes(512 if trainer else 0) + bytes(16384)


def iso():
    data = bytearray(18 * 2048)
    data[16 * 2048:16 * 2048 + 7] = b'\x01CD001\x01'
    return data


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        # macOS exposes its temporary directory through a system symlink.
        # Resolve that test-owned location before exercising link rejection.
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'collection-secret'
        self.root.mkdir()
        self.dest = self.base / 'private-stage'

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def counts(self, kind):
        return inspect_fixtures(self.root).summary()['classes'][kind]

    def test_summary_is_sanitized_and_nes_size_is_checked(self):
        self.put('secret-title.nes', nes())
        self.put('truncated.nes', b'NES\x1a' + bytes(12))
        self.put('unsupported.rom', b'private-game-data')
        inventory = inspect_fixtures(self.root)
        summary = inventory.summary()
        self.assertEqual(summary['classes']['nes']['candidates'], 2)
        self.assertEqual(summary['classes']['nes']['structurally_validated'], 1)
        self.assertEqual(summary['classes']['nes']['invalid'], 1)
        self.assertEqual(summary['classes']['unknown']['unsupported'], 1)
        self.assertEqual(summary['provider_match'], 'unverified')
        for forbidden in ('secret-title', 'collection-secret', str(self.base), 'private-game-data'):
            self.assertNotIn(forbidden, json.dumps(summary) + repr(inventory))
        summary['classes']['nes']['candidates'] = 99
        self.assertEqual(inventory.summary()['classes']['nes']['candidates'], 2)

    def test_missing_root_is_safe_and_not_ready(self):
        summary = inspect_fixtures(self.root / 'absent').summary()
        self.assertEqual(summary['status'], 'missing_root')
        self.assertFalse(summary['selected_ready'])

    def test_root_file_and_symlink_are_rejected(self):
        path = self.put('ordinary.nes', nes())
        self.assertEqual(inspect_fixtures(path).summary()['status'], 'invalid_root')
        link = self.base / 'linked-root'
        link.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(inspect_fixtures(link).summary()['status'], 'unsafe_root')

    def test_source_symlinks_and_symlink_directories_are_not_followed(self):
        self.put('valid.nes', nes())
        (self.root / 'link.nes').symlink_to(self.root / 'valid.nes')
        (self.root / 'linked-dir').symlink_to(self.root, target_is_directory=True)
        summary = inspect_fixtures(self.root).summary()
        self.assertEqual(summary['rejected_symlinks'], 2)
        self.assertEqual(summary['classes']['nes']['candidates'], 1)

    def test_nes_trainer_and_nes2_linear_and_exponent_sizes(self):
        self.put('trainer.nes', nes(True))
        data = bytearray(nes())
        data[7] = 8
        self.put('nes2.nes', data)
        data[4] = 56  # 2**14 bytes, multiplier 1
        data[9] = 15
        self.put('exponent.nes', data)
        self.assertEqual(self.counts('nes')['structurally_validated'], 3)

    def test_iso_signature_is_header_evidence_only(self):
        self.put('optical.iso', iso())
        self.put('invalid.iso', bytes(4096))
        counts = self.counts('iso')
        self.assertEqual(counts['header_validated'], 1)
        self.assertEqual(counts['structurally_validated'], 0)
        self.assertEqual(counts['invalid'], 1)
        self.assertEqual(counts['ready'], 1)

    def test_cue_and_playlist_copy_companion_graph_without_rewriting(self):
        self.put('disc/track.bin', bytes(2352))
        cue = self.put('disc/private-disc.cue', b'FILE "track.bin" BINARY\n TRACK 01 MODE1/2352\n INDEX 01 00:00:00\n')
        self.put('private-playlist.m3u', b'#EXTM3U\ndisc/private-disc.cue\n')
        inventory = inspect_fixtures(self.root)
        self.assertEqual(inventory.summary()['classes']['cue']['structurally_validated'], 1)
        self.assertEqual(inventory.summary()['classes']['m3u']['structurally_validated'], 1)
        result = inventory.stage(self.dest)
        self.assertEqual(result['staged_bundles'], 2)
        self.assertEqual(len(list(self.dest.rglob('*.bin'))), 2)
        self.assertTrue(all(p.read_bytes() == cue.read_bytes() for p in self.dest.rglob('*.cue')))
        self.assertEqual(self.dest.stat().st_mode & 0o777, 0o700)
        self.assertNotIn('private-disc', json.dumps(result))
        self.assertNotIn(str(self.dest), json.dumps(result))

    def test_companion_escape_absolute_windows_and_missing_are_rejected(self):
        self.put('track.bin', bytes(2352))
        for index, reference in enumerate(('../track.bin', '/track.bin', 'C:\\track.bin', 'missing.bin', '\\\\host\\track.bin')):
            with self.subTest(index=index):
                self.put(f'bad{index}.cue', f'FILE "{reference}" BINARY\n'.encode())
                self.put(f'bad{index}.m3u', (reference + '\n').encode())
        self.assertEqual(self.counts('cue')['invalid'], 5)
        self.assertEqual(self.counts('m3u')['invalid'], 5)

    def test_companion_symlink_and_cycle_are_rejected(self):
        self.put('data.bin', bytes(2352))
        (self.root / 'linked.bin').symlink_to(self.root / 'data.bin')
        self.put('bad.cue', b'FILE "linked.bin" BINARY\n')
        self.put('first.m3u', b'second.m3u\n')
        self.put('second.m3u', b'first.m3u\n')
        self.assertEqual(self.counts('cue')['invalid'], 1)
        self.assertEqual(self.counts('m3u')['invalid'], 2)

    def test_zip_crc_and_unsafe_members(self):
        with zipfile.ZipFile(self.root / 'valid.zip', 'w') as archive:
            archive.writestr('generated.nes', nes())
        with zipfile.ZipFile(self.root / 'corrupt.zip', 'w') as archive:
            archive.writestr('payload.bin', b'abcdefgh')
        path = self.root / 'corrupt.zip'
        path.write_bytes(path.read_bytes().replace(b'abcdefgh', b'abcdefgX'))
        with zipfile.ZipFile(self.root / 'escape.zip', 'w') as archive:
            archive.writestr('../escape.nes', nes())
        self.put('invalid.zip', b'not-an-archive')
        counts = self.counts('zip')
        self.assertEqual(counts['structurally_validated'], 1)
        self.assertEqual(counts['invalid'], 3)

    def test_zip_declared_expansion_is_bounded(self):
        with zipfile.ZipFile(self.root / 'large.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('payload.bin', bytes(2048))
        self.assertEqual(inspect_fixtures(self.root, max_bytes=1024).summary()['classes']['zip']['oversized'], 1)

    def test_container_headers_are_not_claimed_structurally_validated(self):
        chd = bytearray(124)
        chd[:16] = b'MComprHD' + struct.pack('>II', 124, 5)
        self.put('container.chd', chd)
        rvz = bytearray(72)
        rvz[:4] = b'RVZ\x01'
        self.put('container.rvz', rvz)
        cso = struct.pack('<4sIQIBB2s', b'CISO', 24, 2048, 2048, 1, 0, b'\0\0') + bytes(8)
        self.put('container.cso', cso)
        wbfs = bytearray(512)
        wbfs[:12] = b'WBFS' + struct.pack('>I', 1) + bytes((9, 15, 0, 0))
        self.put('container.wbfs', wbfs)
        for kind in ('chd', 'rvz', 'cso', 'wbfs'):
            with self.subTest(kind=kind):
                counts = self.counts(kind)
                self.assertEqual(counts['header_validated'], 1)
                self.assertEqual(counts['structurally_validated'], 0)
                self.put(f'bad.{kind}', b'invalid')
                self.assertEqual(self.counts(kind)['invalid'], 1)

    def test_7z_tool_presence_is_reported_without_validation_claim(self):
        self.put('archive.7z', b'7z\xbc\xaf\x27\x1c' + bytes(26))
        with patch('scripts.android_qualification.physical.fixtures.shutil.which', return_value=None):
            summary = inspect_fixtures(self.root).summary()
        self.assertFalse(summary['seven_zip_tool_available'])
        self.assertEqual(summary['classes']['seven_zip']['unsupported'], 1)
        self.assertEqual(summary['classes']['seven_zip']['ready'], 0)
        with patch('scripts.android_qualification.physical.fixtures.shutil.which', return_value='/private/tool'):
            summary = inspect_fixtures(self.root).summary()
        self.assertTrue(summary['seven_zip_tool_available'])
        self.assertEqual(summary['classes']['seven_zip']['structurally_validated'], 0)
        self.assertNotIn('/private/tool', json.dumps(summary))

    def test_selection_is_minimal_and_total_and_bundle_caps_apply(self):
        self.put('first.nes', nes())
        self.put('second.nes', nes(True))
        self.put('disc.iso', iso())
        result = inspect_fixtures(self.root).stage(self.dest, max_bytes=20000)
        self.assertEqual(result['staged_bundles'], 1)
        self.assertEqual(result['staged_bytes'], 16400)
        self.assertEqual(len(list(self.dest.rglob('*.nes'))), 1)
        self.assertLessEqual(result['staged_bytes'], 20000)
        other = self.base / 'small-stage'
        result = inspect_fixtures(self.root).stage(other, max_bytes=100)
        self.assertEqual(result['staged_bundles'], 0)

    def test_original_content_mode_and_modification_time_are_preserved(self):
        path = self.put('read-only.nes', nes())
        path.chmod(0o444)
        before = (path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode)
        inspect_fixtures(self.root).stage(self.dest)
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode), before)

    def test_destination_must_be_new_external_and_without_symlink_ancestors(self):
        self.put('valid.nes', nes())
        inventory = inspect_fixtures(self.root)
        for destination in (self.root / 'stage', self.root, self.base):
            with self.subTest(index=0):
                self.assertEqual(inventory.stage(destination)['status'], 'unsafe_destination')
        link = self.base / 'alias'
        link.symlink_to(self.base, target_is_directory=True)
        self.assertEqual(inventory.stage(link / 'stage')['status'], 'unsafe_destination')
        self.assertFalse((self.root / 'stage').exists())

    def test_changed_or_replaced_source_is_not_staged(self):
        source = self.put('valid.nes', nes())
        inventory = inspect_fixtures(self.root)
        source.write_bytes(b'changed')
        result = inventory.stage(self.dest)
        self.assertEqual(result['staged_bundles'], 0)
        self.assertEqual(result['failed_bundles'], 1)
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_wrappers_return_only_sanitized_reports(self):
        self.put('private.nes', nes())
        self.assertEqual(inventory(self.root)['classes']['nes']['ready'], 1)
        result = select_fixtures(self.root, self.dest)
        self.assertEqual(result['staged_bundles'], 1)
        self.assertNotIn('private.nes', json.dumps(result))

    def test_graph_staging_retains_only_required_relative_ancestors(self):
        self.put('unrelated-private-folder/disc/track.bin', bytes(2352))
        self.put('unrelated-private-folder/disc/title.cue', b'FILE "track.bin" BINARY\n')
        result = inspect_fixtures(self.root).stage(self.dest)
        self.assertEqual(result['staged_bundles'], 1)
        self.assertFalse(any(p.name == 'unrelated-private-folder' for p in self.dest.rglob('*')))
        self.assertEqual(len(list(self.dest.rglob('sample.cue'))), 1)

    def test_deflate_corruption_is_sanitized(self):
        with zipfile.ZipFile(self.root / 'bad.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('data.bin', bytes(500))
        path = self.root / 'bad.zip'
        data = bytearray(path.read_bytes())
        name_length, extra_length = struct.unpack('<HH', data[26:30])
        data[30 + name_length + extra_length] = 0xff
        path.write_bytes(data)
        self.assertEqual(self.counts('zip')['invalid'], 1)

    def test_scan_limit_is_visible(self):
        self.put('one.nes', nes())
        self.put('two.nes', nes())
        with patch('scripts.android_qualification.physical.fixtures.MAX_FILES', 1):
            summary = inspect_fixtures(self.root).summary()
        self.assertEqual(summary['status'], 'scan_limit')
        self.assertEqual(summary['classes']['nes']['candidates'], 1)

    def test_graph_and_text_limits_reject_before_staging(self):
        self.put('track.bin', bytes(2352))
        self.put('disc.cue', b'FILE "track.bin" BINARY\n')
        with patch('scripts.android_qualification.physical.fixtures.MAX_GRAPH_FILES', 1):
            self.assertEqual(self.counts('cue')['oversized'], 1)
        with patch('scripts.android_qualification.physical.fixtures.MAX_TEXT_BYTES', 5):
            self.assertEqual(self.counts('cue')['oversized'], 1)
        self.put('repeated.m3u', b'disc.cue\n' * 10)
        with patch('scripts.android_qualification.physical.fixtures.MAX_GRAPH_FILES', 5):
            self.assertEqual(self.counts('m3u')['oversized'], 1)

    def test_source_replaced_by_symlink_is_not_copied(self):
        source = self.put('original.nes', nes())
        self.put('other.nes', nes(True))
        obj = inspect_fixtures(self.root)
        source.unlink()
        source.symlink_to(self.root / 'other.nes')
        result = obj.stage(self.dest)
        self.assertEqual(result['failed_bundles'], 1)
        self.assertEqual(result['staged_bundles'], 1)

    def test_empty_text_unknown_companion_and_non_utf8_are_rejected(self):
        self.put('empty.cue', b'REM no references\n')
        self.put('bad.m3u', b'unknown.rom\n')
        self.put('unknown.rom', bytes(8))
        self.put('encoding.cue', b'\xff\xfe')
        self.assertEqual(self.counts('cue')['invalid'], 2)
        self.assertEqual(self.counts('m3u')['invalid'], 1)

    def test_source_unavailable_does_not_create_destination(self):
        result = inspect_fixtures(self.root / 'missing').stage(self.dest)
        self.assertEqual(result['status'], 'source_unavailable')
        self.assertFalse(self.dest.exists())

    def test_root_traversal_is_rejected(self):
        self.assertEqual(inspect_fixtures(self.root / '..' / self.root.name).summary()['status'], 'unsafe_root')

    def test_destination_traversal_is_rejected(self):
        self.put('valid.nes', nes())
        result = inspect_fixtures(self.root).stage(self.base / 'child' / '..' / 'stage')
        self.assertEqual(result['status'], 'unsafe_destination')
        self.assertFalse((self.base / 'stage').exists())

    def test_neutral_entry_name_does_not_collide_with_referenced_directory(self):
        self.put('sample.m3u/track.bin', bytes(2352))
        self.put('sample.m3u/disc.cue', b'FILE "track.bin" BINARY\n')
        self.put('main.m3u', b'sample.m3u/disc.cue\n')
        result = inspect_fixtures(self.root).stage(self.dest)
        self.assertEqual(result['staged_bundles'], 2)
        self.assertEqual(result['failed_bundles'], 0)
        playlists = [p for p in self.dest.rglob('*.m3u') if p.is_file()]
        self.assertEqual(len(playlists), 1)
        self.assertEqual(playlists[0].read_bytes(), b'sample.m3u/disc.cue\n')

    def test_total_cap_excludes_second_individually_small_bundle(self):
        self.put('valid.nes', nes())
        self.put('valid.iso', iso())
        report = inspect_fixtures(self.root).stage(self.dest, max_bytes=40000)
        self.assertEqual(report['staged_bundles'], 1)
        self.assertEqual(report['staged_bytes'], 16400)
        self.assertEqual(report['skipped_bundles'], 1)

    def test_zip_directory_symlink_duplicates_and_unsupported_compression(self):
        with zipfile.ZipFile(self.root / 'directory.zip', 'w') as archive:
            archive.writestr('folder/', b'')
            archive.writestr('folder/data', b'generated')
        with zipfile.ZipFile(self.root / 'symlink.zip', 'w') as archive:
            item = zipfile.ZipInfo('link')
            item.create_system = 3
            item.external_attr = 0o120777 << 16
            archive.writestr(item, b'target')
        with zipfile.ZipFile(self.root / 'unsupported.zip', 'w') as archive:
            archive.writestr('payload', b'generated')
        path = self.root / 'unsupported.zip'
        data = bytearray(path.read_bytes())
        data[8:10] = struct.pack('<H', 99)
        central = data.index(b'PK\x01\x02')
        data[central + 10:central + 12] = struct.pack('<H', 99)
        path.write_bytes(data)
        counts = self.counts('zip')
        self.assertEqual(counts['structurally_validated'], 1)
        self.assertEqual(counts['invalid'], 1)
        self.assertEqual(counts['unsupported'], 1)

    def test_zip_metadata_caps_and_zip64_are_reported(self):
        with zipfile.ZipFile(self.root / 'meta.zip', 'w') as archive:
            archive.writestr('payload', b'generated')
        path = self.root / 'meta.zip'
        original = path.read_bytes()
        with patch('scripts.android_qualification.physical.fixtures.MAX_ZIP_MEMBERS', 0):
            self.assertEqual(self.counts('zip')['oversized'], 1)
        for change, wanted in ((4, 'invalid'), (10, 'unsupported')):
            data = bytearray(original)
            start = data.rindex(b'PK\x05\x06')
            data[start + change:start + change + 2] = struct.pack('<H', 1 if change == 4 else 65535)
            if change == 10:
                data[start + 8:start + 10] = struct.pack('<H', 65535)
            path.write_bytes(data)
            self.assertEqual(self.counts('zip')[wanted], 1)

    def test_bad_nes_headers_empty_data_and_bad_descriptors_are_invalid(self):
        self.put('empty.nes', b'')
        self.put('wrong.nes', b'BAD!' + bytes(16396))
        reserved = bytearray(nes())
        reserved[7] = 4
        self.put('reserved.nes', reserved)
        reserved[7] = 8
        reserved[14] = 1
        self.put('misc.nes', reserved)
        self.put('bad.cue', b'FILE "track.bin" WAVE\n')
        self.put('dot.cue', b'FILE "." BINARY\n')
        self.put('empty-reference.cue', b'FILE "" BINARY\n')
        self.put('invalid.7z', b'not seven zip')
        self.assertEqual(self.counts('nes')['invalid'], 4)
        self.assertEqual(self.counts('cue')['invalid'], 3)
        self.assertEqual(self.counts('seven_zip')['invalid'], 1)

    def test_playlist_of_header_only_format_does_not_claim_structural_validation(self):
        self.put('optical.iso', iso())
        self.put('playlist.m3u', b'optical.iso\n')
        self.assertEqual(self.counts('m3u')['header_validated'], 1)
        self.assertEqual(self.counts('m3u')['structurally_validated'], 0)

    def test_repeated_graph_references_are_cached_and_preserved(self):
        self.put('track.bin', bytes(2352))
        self.put('disc.cue', b'FILE "track.bin" BINARY\n')
        self.put('playlist.m3u', b'disc.cue\ndisc.cue\n')
        self.assertEqual(self.counts('m3u')['structurally_validated'], 1)
        self.assertEqual(inspect_fixtures(self.root).stage(self.dest)['staged_bundles'], 2)

    def test_directory_depth_and_io_errors_are_visible(self):
        self.put('nested/deeper/valid.nes', nes())
        with patch('scripts.android_qualification.physical.fixtures.MAX_DEPTH', 1):
            self.assertEqual(inspect_fixtures(self.root).summary()['status'], 'scan_limit')
        with patch('scripts.android_qualification.physical.fixtures.os.scandir', side_effect=PermissionError('private name')):
            summary = inspect_fixtures(self.root).summary()
        self.assertEqual(summary['status'], 'partial_scan')
        self.assertEqual(summary['scan_errors'], 1)
        self.assertNotIn('private name', json.dumps(summary))

    def test_explicit_cap_allows_large_sparse_optical_header_without_full_read(self):
        path = self.put('large.iso', iso())
        large_size = 536870913
        with path.open('r+b') as stream:
            stream.truncate(large_size)
        before = (path.stat().st_size, path.stat().st_mtime_ns)
        self.assertEqual(self.counts('iso')['oversized'], 1)
        obj = inspect_fixtures(self.root, max_bytes=8 * 1024**3)
        report = obj.summary()
        self.assertEqual(report['classes']['iso']['header_validated'], 1)
        self.assertEqual(report['classes']['iso']['structurally_validated'], 0)
        self.assertEqual((path.stat().st_size, path.stat().st_mtime_ns), before)
        self.assertNotIn('large.iso', json.dumps(report))
        # Inspection's larger cap must not silently raise staging's default.
        staged = obj.stage(self.dest)
        self.assertEqual(staged['staged_bundles'], 0)
        self.assertEqual(staged['skipped_bundles'], 1)

    def test_explicit_cap_reaches_compressed_header_checks(self):
        self.put('compressed.rvz', b'RVZ\x01' + bytes(68))
        self.put('compressed.chd', b'MComprHD' + struct.pack('>II', 124, 5) + bytes(108))
        lower = inspect_fixtures(self.root, max_bytes=64).summary()
        upper = inspect_fixtures(self.root, max_bytes=124).summary()
        for kind in ('rvz', 'chd'):
            self.assertEqual(lower['classes'][kind]['oversized'], 1)
            self.assertEqual(upper['classes'][kind]['header_validated'], 1)
            self.assertEqual(upper['classes'][kind]['structurally_validated'], 0)

    def test_explicit_cap_bounds_entire_nested_companion_bundle(self):
        self.put('first.bin', bytes(1024))
        self.put('second.bin', bytes(1024))
        self.put('disc.cue', b'FILE "first.bin" BINARY\nFILE "second.bin" BINARY\n')
        self.put('playlist.m3u', b'disc.cue\n')
        lower = inspect_fixtures(self.root, max_bytes=2048).summary()
        self.assertEqual(lower['classes']['cue']['oversized'], 1)
        self.assertEqual(lower['classes']['m3u']['oversized'], 1)
        obj = inspect_fixtures(self.root, max_bytes=4096)
        self.assertEqual(obj.summary()['classes']['m3u']['structurally_validated'], 1)
        staged = obj.stage(self.dest, max_bytes=3000)
        self.assertEqual(staged['staged_bundles'], 1)
        self.assertLessEqual(staged['staged_bytes'], 3000)
        self.assertEqual(staged['skipped_bundles'], 1)

    def test_explicit_archive_cap_bounds_total_expansion(self):
        with zipfile.ZipFile(self.root / 'expanded.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('first', bytes(2048))
            archive.writestr('second', bytes(2048))
        lower = inspect_fixtures(self.root, max_bytes=3000).summary()
        self.assertEqual(lower['classes']['zip']['oversized'], 1)
        upper = inspect_fixtures(self.root, max_bytes=4096).summary()
        self.assertEqual(upper['classes']['zip']['structurally_validated'], 1)

    def test_larger_cap_keeps_descriptor_traversal_and_symlink_rejection(self):
        self.put('track.bin', bytes(1024))
        (self.root / 'linked.bin').symlink_to(self.root / 'track.bin')
        self.put('escape.cue', b'FILE "../track.bin" BINARY\n')
        self.put('link.cue', b'FILE "linked.bin" BINARY\n')
        report = inspect_fixtures(self.root, max_bytes=8 * 1024**3).summary()
        self.assertEqual(report['classes']['cue']['invalid'], 2)
        self.assertEqual(report['rejected_symlinks'], 1)

    def test_invalid_inspection_cap_does_not_access_source(self):
        for cap in (0, -1, True, 1.5, None):
            with self.subTest(cap=cap), patch('scripts.android_qualification.physical.fixtures._open_directory', side_effect=AssertionError('source accessed')):
                obj = inspect_fixtures(self.root, max_bytes=cap)
                self.assertEqual(obj.summary()['status'], 'invalid_limit')
                self.assertFalse(obj.summary()['selected_ready'])
                self.assertEqual(obj.stage(self.dest)['status'], 'source_unavailable')
        self.assertFalse(self.dest.exists())

    def test_wrappers_forward_inspection_limit_and_stage_keeps_its_default(self):
        self.put('small.nes', nes())
        self.assertEqual(inventory(self.root, max_bytes=100)['classes']['nes']['oversized'], 1)
        report = select_fixtures(self.root, self.dest, max_bytes=100)
        self.assertEqual(report['staged_bundles'], 0)
        self.assertEqual(select_fixtures(self.root, self.base / 'large-stage', max_bytes=8 * 1024**3)['staged_bundles'], 1)

    def test_stage_interruption_removes_completed_and_partial_bundles_and_propagates(self):
        self.put('first.nes', nes())
        self.put('second.iso', iso())
        sources = [(p, p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_mode) for p in self.root.iterdir()]
        obj = inspect_fixtures(self.root)
        for exception_type in (InterruptedError, KeyboardInterrupt):
            destination = self.base / exception_type.__name__
            from scripts.android_qualification.physical import fixtures
            original_open = fixtures._open_file

            def interrupted_open(root, relative):
                if relative.suffix == '.iso':
                    # A completed first bundle and a begun second bundle exist
                    # when cancellation arrives; neither may survive it.
                    self.assertEqual(len(list(destination.rglob('*.nes'))), 1)
                    self.assertEqual(len(list(destination.iterdir())), 2)
                    raise exception_type('generated interruption')
                return original_open(root, relative)

            with self.subTest(exception=exception_type.__name__):
                with patch('scripts.android_qualification.physical.fixtures._open_file', side_effect=interrupted_open):
                    with self.assertRaises(exception_type):
                        obj.stage(destination)
                self.assertFalse(destination.exists())
                for source, content, modified, mode in sources:
                    self.assertEqual((source.read_bytes(), source.stat().st_mtime_ns, source.stat().st_mode), (content, modified, mode))

    def test_inspection_interruptions_propagate_at_root_scan_and_validation(self):
        self.put('valid.nes', nes())
        for boundary in ('_open_directory', 'os.scandir', '_open_file'):
            with self.subTest(boundary=boundary):
                with patch('scripts.android_qualification.physical.fixtures.' + boundary, side_effect=InterruptedError('generated interruption')):
                    with self.assertRaises(InterruptedError):
                        inspect_fixtures(self.root)

    def test_destination_setup_interruption_propagates_without_output(self):
        self.put('valid.nes', nes())
        obj = inspect_fixtures(self.root)
        with patch('scripts.android_qualification.physical.fixtures._open_directory', side_effect=InterruptedError('generated interruption')):
            with self.assertRaises(InterruptedError):
                obj.stage(self.dest)
        self.assertFalse(self.dest.exists())

    def test_interruption_during_failed_bundle_cleanup_is_not_suppressed(self):
        source = self.put('valid.nes', nes())
        obj = inspect_fixtures(self.root)
        source.write_bytes(b'changed before staging')
        original_rmdir = os.rmdir
        interrupted = False

        def interrupt_once(path, *args, **kwargs):
            nonlocal interrupted
            if not interrupted and Path(path).name == 'fixture-001':
                interrupted = True
                raise InterruptedError('generated cleanup interruption')
            return original_rmdir(path, *args, **kwargs)

        with patch('scripts.android_qualification.physical.fixtures.os.rmdir', side_effect=interrupt_once):
            with self.assertRaises(InterruptedError):
                obj.stage(self.dest)
        self.assertFalse(self.dest.exists())
        self.assertEqual(source.read_bytes(), b'changed before staging')

    def test_failed_bundle_cleanup_reports_sanitized_failure_and_stops_staging(self):
        source = self.put('first.nes', nes())
        self.put('second.iso', iso())
        obj = inspect_fixtures(self.root)
        source.write_bytes(b'changed before staging')
        originals = [(p, p.read_bytes(), p.stat().st_mtime_ns, p.stat().st_mode) for p in self.root.iterdir()]
        original_rmdir = os.rmdir

        def denied_cleanup(path, *args, **kwargs):
            if Path(path).name == 'fixture-001':
                raise PermissionError('private-cleanup-name-and-path')
            return original_rmdir(path, *args, **kwargs)

        with patch('scripts.android_qualification.physical.fixtures.os.rmdir', side_effect=denied_cleanup):
            report = obj.stage(self.dest)
        self.assertEqual(report['status'], 'cleanup_failed')
        self.assertEqual(report['failed_bundles'], 1)
        self.assertEqual(report['staged_bundles'], 0)
        self.assertEqual(len(list(self.dest.iterdir())), 1)
        self.assertEqual(list(self.dest.rglob('*.iso')), [])
        self.assertNotIn('private-cleanup-name-and-path', json.dumps(report))
        self.assertNotIn(str(self.dest), json.dumps(report))
        for path, data, modified, mode in originals:
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode), (data, modified, mode))

    def test_cancellation_cleanup_failure_preserves_interruption_with_sanitized_note(self):
        source = self.put('valid.nes', nes())
        obj = inspect_fixtures(self.root)
        original = (source.read_bytes(), source.stat().st_mtime_ns, source.stat().st_mode)
        for exception_type in (InterruptedError, KeyboardInterrupt):
            destination = self.base / exception_type.__name__
            cancellation = exception_type('generated cancellation')
            diagnostic = io.StringIO()
            with self.subTest(exception=exception_type.__name__):
                with redirect_stderr(diagnostic):
                    with patch('scripts.android_qualification.physical.fixtures._open_file', side_effect=cancellation), patch('scripts.android_qualification.physical.fixtures.os.rmdir', side_effect=PermissionError('private-cleanup-name-and-path')):
                        with self.assertRaises(exception_type) as caught:
                            obj.stage(destination)
                self.assertIs(caught.exception, cancellation)
                notes = '\n'.join(getattr(caught.exception, '__notes__', ()))
                observed = notes + '\n' + diagnostic.getvalue()
                self.assertIn('cleanup_failed', observed)
                self.assertNotIn('private-cleanup-name-and-path', observed)
                self.assertNotIn(str(destination), observed)
                self.assertEqual((source.read_bytes(), source.stat().st_mtime_ns, source.stat().st_mode), original)

    def test_cancellation_cleanup_failure_preserves_interruption_when_add_note_is_unavailable(self):
        source = self.put('valid.nes', nes())
        obj = inspect_fixtures(self.root)
        original = (source.read_bytes(), source.stat().st_mtime_ns, source.stat().st_mode)
        for exception_type in (LegacyInterruptedError, LegacyKeyboardInterrupt):
            destination = self.base / exception_type.__name__
            cancellation = exception_type('generated cancellation')
            diagnostic = io.StringIO()
            with self.subTest(exception=exception_type.__name__):
                with redirect_stderr(diagnostic):
                    with patch('scripts.android_qualification.physical.fixtures._open_file', side_effect=cancellation), patch('scripts.android_qualification.physical.fixtures.os.rmdir', side_effect=PermissionError('private-cleanup-name-and-path')):
                        with self.assertRaises(exception_type) as caught:
                            obj.stage(destination)
                self.assertIs(caught.exception, cancellation)
                self.assertIn('cleanup_failed: private staging cleanup could not complete.', diagnostic.getvalue())
                self.assertNotIn('private-cleanup-name-and-path', diagnostic.getvalue())
                self.assertNotIn(str(destination), diagnostic.getvalue())
                self.assertEqual((source.read_bytes(), source.stat().st_mtime_ns, source.stat().st_mode), original)

    def test_invalid_cap_returns_sanitized_status(self):
        inventory = inspect_fixtures(self.root)
        for cap in (0, -1, True, 1.5):
            self.assertEqual(inventory.stage(self.dest, max_bytes=cap)['status'], 'invalid_limit')


if __name__ == '__main__':
    unittest.main()
