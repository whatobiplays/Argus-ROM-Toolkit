"""Bounded, read-only host fixture inspection for black-box qualification.

Use ``inspect_fixtures(root, max_bytes=limit).summary()`` for JSON-safe evidence.
Use ``inspect_fixtures(root, max_bytes=limit).stage(new_external_directory, limit)`` to copy one
small representative per eligible format class. Both return aggregate counts,
never collection names, paths, hashes, or payloads. ``inventory`` and
``select_fixtures`` are convenience wrappers with the same report contract.

Candidate classification uses extensions; it is not positive game identity.
NES sizes, ZIP CRCs, and companion graph containment are structurally checked.
Optical and compressed image checks establish header evidence only, not complete
image integrity. Provider matching and Android behavior remain unverified.
7z tooling presence is reported but no tool is run and no 7z is staged.

The source must remain quiescent while inspecting and staging. File descriptors
use no-follow traversal and snapshots reject changed source files. Read access
may update filesystem access times; this module never writes to the source.
Staging requires a NEW directory outside the source and creates it mode 0700.
Companion names exist only inside private copies and private in-memory state;
never publish the staging tree or private inventory attributes as evidence.
Limits bound per-file inspection, archive expansion, descriptor text, graph
size, and scan size. Partial scans are explicitly reported as scan_limit.
Inspection defaults to 512 MiB per file, companion bundle, and archive's total
expanded bytes. Explicit positive integer limits permit larger owned fixtures.
Staging has an independent 512 MiB default and caps the entire copied set;
pass the capacity-based limit to both inspection and staging for larger sets.
Descriptor text and archive metadata limits do not grow with the byte limit.
"""

from dataclasses import dataclass, field
import copy
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import stat
import struct
import sys
import zipfile
import zlib

MAX_INSPECTION_BYTES = 536870912
MAX_TEXT_BYTES = 1048576
MAX_FILES = 10000
MAX_GRAPH_FILES = 256
MAX_DEPTH = 16
MAX_ZIP_MEMBERS = 4096
MAX_ZIP_DIRECTORY_BYTES = 4194304
_CLASSES = ('nes', 'iso', 'cue', 'm3u', 'zip', 'seven_zip', 'chd', 'rvz', 'cso', 'wbfs', 'unknown')
_SUFFIXES = {'.' + name: name for name in _CLASSES if name not in ('seven_zip', 'unknown')}
_SUFFIXES['.7z'] = 'seven_zip'


def _snapshot(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _raise_cleanup_error(_function, _path, error_info):
    """Propagate deletion failures for sanitized reporting by the caller.

    InterruptedError retains its identity so a signal cancellation cannot be
    converted into an ordinary cleanup failure or a partial success report.
    """
    raise error_info[1]


def _report_staging_cleanup_failure(interruption):
    """Record a sanitized cleanup failure without masking cancellation."""
    diagnostic = 'cleanup_failed: private staging cleanup could not complete.'
    try:
        add_note = getattr(interruption, 'add_note', None)
        if callable(add_note):
            add_note(diagnostic)
            return
    except BaseException:
        pass
    try:
        sys.stderr.write(diagnostic + '\n')
    except BaseException:
        pass


def _open_directory(path):
    """Open every absolute path component without following a symbolic link."""
    path = Path(os.path.abspath(path))
    descriptor = os.open(path.anchor, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _open_file(root, relative):
    """Return a read-only stream after rejecting links in every component."""
    descriptor = _open_directory(root)
    try:
        for part in relative.parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        file_descriptor = os.open(relative.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
        try:
            if not stat.S_ISREG(os.fstat(file_descriptor).st_mode):
                raise ValueError('unsafe_source')
            return os.fdopen(file_descriptor, 'rb')
        except BaseException:
            os.close(file_descriptor)
            raise
    finally:
        os.close(descriptor)


def _safe_reference(text):
    """Accept portable relative references, rejecting traversal and drive paths."""
    if not text or '\x00' in text or '\\' in text or ':' in text:
        raise ValueError('unsafe_reference')
    posix, windows = PurePosixPath(text), PureWindowsPath(text)
    if posix.is_absolute() or windows.is_absolute() or windows.drive or '..' in posix.parts:
        raise ValueError('unsafe_reference')
    if not posix.parts:
        raise ValueError('unsafe_reference')
    return Path(*posix.parts)


@dataclass(repr=False)
class _Bundle:
    kind: str
    entry: Path
    files: dict = field(default_factory=dict)
    level: str = 'structural'

    @property
    def size(self):
        return sum(snapshot[2] for snapshot in self.files.values())


class Inventory:
    """Private source state with sanitized summary and staging boundaries.

    ``summary`` returns a fresh dictionary. Class counts distinguish candidates,
    structural validation, header validation, invalid, oversized, unsupported,
    and readiness. Ready means eligible for host staging at the recorded level;
    it does not establish provider identity or a passing device qualification.
    """

    def __init__(self, root, report, bundles):
        self._root = root
        self._report = report
        self._bundles = bundles

    def __repr__(self):
        return 'Inventory(' + repr(self.summary()) + ')'

    def summary(self):
        """Return aggregate evidence without identifiers or payload bytes."""
        return copy.deepcopy(self._report)

    def stage(self, destination: Path, max_bytes: int = MAX_INSPECTION_BYTES) -> dict:
        """Copy minimal bundles into a new private external host directory.

        ``max_bytes`` caps each whole companion bundle AND all copied bundles
        combined. No archive is extracted. No source is changed. Standalone
        files get neutral names; descriptor graphs retain relative names so
        references still resolve. Failed copies are removed, and errors are
        reduced to fixed statuses. Existing destinations are never reused.
        The caller owns cleanup and must keep the staging tree private.
        InterruptedError and KeyboardInterrupt propagate after removing the
        entire destination created by this call; completed bundles are also
        discarded. Cancellation is never converted into a partial success.
        A failed deletion stops staging with status ``cleanup_failed``. Private
        output may remain for the caller to remove. If deletion fails during
        cancellation, the original interruption propagates with a sanitized
        ``cleanup_failed`` note rather than being replaced by a filesystem error.
        """
        result = {'status': 'ok', 'provider_match': 'unverified', 'staged_bundles': 0,
                  'staged_bytes': 0, 'failed_bundles': 0, 'skipped_bundles': 0,
                  'classes': {kind: {'staged': 0, 'structural': 0, 'header_only': 0} for kind in _CLASSES}}
        if not isinstance(max_bytes, int) or isinstance(max_bytes, bool) or max_bytes <= 0:
            result['status'] = 'invalid_limit'
            return result
        if self._report['status'] not in ('ok', 'scan_limit'):
            result['status'] = 'source_unavailable'
            return result
        if '..' in Path(destination).parts:
            result['status'] = 'unsafe_destination'
            return result
        destination = Path(os.path.abspath(destination))
        created = False
        try:
            try:
                if destination == self._root or self._root in destination.parents or destination in self._root.parents:
                    raise ValueError('unsafe_destination')
                parent = _open_directory(destination.parent)
                try:
                    os.mkdir(destination.name, mode=0o700, dir_fd=parent)
                    created = True
                finally:
                    os.close(parent)
            except InterruptedError:
                raise
            except (OSError, ValueError):
                result['status'] = 'unsafe_destination'
                return result
            # The newly created tree has no attacker-provided entries. The caller
            # must exclusively own it for the duration of staging.
            chosen = set()
            for bundle in sorted(self._bundles, key=lambda item: (item.size, item.kind, str(item.entry))):
                if bundle.kind in chosen:
                    continue
                if bundle.size > max_bytes or bundle.size + result['staged_bytes'] > max_bytes:
                    result['skipped_bundles'] += 1
                    continue
                target = destination / ('fixture-' + str(result['staged_bundles'] + 1).zfill(3))
                try:
                    target.mkdir(mode=0o700)
                    copied = 0
                    neutral = Path('sample' + bundle.entry.suffix.lower())
                    if bundle.kind in ('cue', 'm3u'):
                        referenced = {p.relative_to(bundle.entry.parent) for p in bundle.files if p != bundle.entry}
                        referenced.update(parent for p in tuple(referenced) for parent in p.parents)
                        index = 0
                        while neutral in referenced:
                            index += 1
                            neutral = Path('sample-' + str(index) + bundle.entry.suffix.lower())
                    for relative, snapshot in bundle.files.items():
                        # Only names referenced inside descriptors are retained.
                        # The top-level entry always receives a neutral name.
                        name = relative.relative_to(bundle.entry.parent) if bundle.kind in ('cue', 'm3u') else relative
                        if relative == bundle.entry:
                            name = neutral
                        output = target / name
                        output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                        with _open_file(self._root, relative) as source:
                            if _snapshot(os.fstat(source.fileno())) != snapshot:
                                raise ValueError('source_changed')
                            with output.open('xb') as sink:
                                os.chmod(output, 0o600)
                                remaining = snapshot[2]
                                while remaining:
                                    chunk = source.read(min(1048576, remaining))
                                    if not chunk:
                                        raise ValueError('source_changed')
                                    sink.write(chunk)
                                    copied += len(chunk)
                                    remaining -= len(chunk)
                                if source.read(1) or _snapshot(os.fstat(source.fileno())) != snapshot:
                                    raise ValueError('source_changed')
                    if copied != bundle.size:
                        raise ValueError('source_changed')
                except InterruptedError:
                    raise
                except (OSError, ValueError):
                    result['failed_bundles'] += 1
                    try:
                        shutil.rmtree(target, onerror=_raise_cleanup_error)
                    except InterruptedError:
                        raise
                    except OSError:
                        result['status'] = 'cleanup_failed'
                        return result
                    continue
                chosen.add(bundle.kind)
                result['staged_bundles'] += 1
                result['staged_bytes'] += copied
                result['classes'][bundle.kind]['staged'] += 1
                result['classes'][bundle.kind]['structural' if bundle.level == 'structural' else 'header_only'] += 1
            return result
        except (InterruptedError, KeyboardInterrupt) as interruption:
            # Cancellation invalidates the entire private set, including any
            # bundles completed before the interrupted copy. Never return a
            # partially successful report after a signal handler raises.
            if created:
                try:
                    shutil.rmtree(destination)
                except (InterruptedError, KeyboardInterrupt):
                    raise
                except OSError:
                    _report_staging_cleanup_failure(interruption)
            raise interruption from None


def _nes_valid(header, size):
    if len(header) < 16 or header[:4] != b'NES\x1a':
        return False
    def length(low, high, unit):
        return (1 << (low >> 2)) * (2 * (low & 3) + 1) if high == 15 else ((high << 8) | low) * unit
    if header[7] & 12 == 8:
        prg = length(header[4], header[9] & 15, 16384)
        chr_size = length(header[5], header[9] >> 4, 8192)
        # Miscellaneous ROMs are not bounded by PRG/CHR fields alone.
        if header[14] & 3:
            return False
    elif header[7] & 12 == 0:
        prg, chr_size = header[4] * 16384, header[5] * 8192
    else:
        return False
    return prg > 0 and size == 16 + (512 if header[6] & 4 else 0) + prg + chr_size


def _zip_valid(stream, size, max_bytes):
    """Bound metadata before ZipFile parsing, then stream every member for CRC."""
    stream.seek(max(0, size - 65557))
    tail = stream.read(65557)
    index = tail.rfind(b'PK\x05\x06')
    if index < 0 or len(tail) - index < 22:
        raise ValueError('invalid')
    disk, central_disk, disk_count, count, directory_size, offset, comment = struct.unpack('<4H2IH', tail[index + 4:index + 22])
    if disk or central_disk or disk_count != count or len(tail) - index != 22 + comment:
        raise ValueError('invalid')
    if count == 65535 or offset == 0xffffffff or directory_size == 0xffffffff:
        raise ValueError('unsupported')
    if count > MAX_ZIP_MEMBERS or directory_size > MAX_ZIP_DIRECTORY_BYTES:
        raise ValueError('oversized')
    stream.seek(0)
    with zipfile.ZipFile(stream) as archive:
        members = archive.infolist()
        if not members or len(members) != count:
            raise ValueError('invalid')
        if sum(item.file_size for item in members) > max_bytes:
            raise ValueError('oversized')
        seen = set()
        for item in members:
            name = _safe_reference(item.filename)
            if name in seen or stat.S_ISLNK(item.external_attr >> 16) or item.flag_bits & 1:
                raise ValueError('invalid')
            seen.add(name)
            if item.is_dir():
                continue
            if item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise ValueError('unsupported')
            with archive.open(item) as member:
                remaining = item.file_size
                while remaining:
                    chunk = member.read(min(1048576, remaining))
                    if not chunk:
                        raise ValueError('invalid')
                    remaining -= len(chunk)
                if member.read(1):
                    raise ValueError('invalid')


def _header_valid(kind, header, size, stream):
    """Recognize bounded header evidence; never infer image/game identity."""
    if kind == 'iso':
        if size >= 32776:
            stream.seek(32768)
            pvd = stream.read(7)
            if pvd == b'\x01CD001\x01':
                return True
        # Nintendo optical headers use distinct magic fields at fixed offsets.
        return (len(header) >= 32 and header[28:32] == b'\xc2\x33\x9f\x3d') or (len(header) >= 28 and header[24:28] == b'\x5d\x1c\x9e\xa3')
    if kind == 'chd':
        if len(header) < 16 or header[:8] != b'MComprHD':
            return False
        length, version = struct.unpack('>II', header[8:16])
        return length == {1: 76, 2: 80, 3: 120, 4: 108, 5: 124}.get(version) and size >= length
    if kind == 'rvz':
        return size >= 72 and header[:4] == b'RVZ\x01'
    if kind == 'cso':
        if len(header) < 24 or header[:4] != b'CISO':
            return False
        length, total, block, version, alignment = struct.unpack('<IQIBB', header[4:22])
        return length >= 24 and total > 0 and block > 0 and version in (1, 2) and alignment <= 31 and size >= length + 4 * ((total + block - 1) // block + 1)
    if kind == 'wbfs':
        if len(header) < 12 or header[:4] != b'WBFS':
            return False
        sectors = int.from_bytes(header[4:8], 'big')
        hd_shift, wbfs_shift = header[8:10]
        return 9 <= hd_shift <= 16 and hd_shift <= wbfs_shift <= 31 and sectors > 0 and size >= sectors * (1 << hd_shift)
    return False


def _validate(root, entry, max_bytes, active=(), companion=False, cache=None):
    """Build a contained bundle; errors carry only fixed category strings."""
    if entry in active or len(active) >= MAX_DEPTH:
        raise ValueError('invalid')
    if cache is None:
        cache = {}
    key = (entry, companion)
    if key in cache:
        return cache[key]
    if len(cache) >= MAX_GRAPH_FILES:
        raise ValueError('oversized')
    kind = _SUFFIXES.get(entry.suffix.lower(), 'unknown')
    with _open_file(root, entry) as stream:
        snapshot = _snapshot(os.fstat(stream.fileno()))
        size = snapshot[2]
        if size > max_bytes:
            raise ValueError('oversized')
        if not size:
            raise ValueError('invalid')
        header = stream.read(128)
        bundle = _Bundle(kind, entry, {entry: snapshot})
        if kind == 'nes':
            if not _nes_valid(header, size):
                raise ValueError('invalid')
        elif kind == 'zip':
            _zip_valid(stream, size, max_bytes)
        elif kind in ('cue', 'm3u'):
            if size > MAX_TEXT_BYTES:
                raise ValueError('oversized')
            stream.seek(0)
            text = stream.read(MAX_TEXT_BYTES + 1).decode('utf-8-sig')
            references = []
            for line in text.splitlines():
                line = line.strip()
                if not line or (kind == 'm3u' and line.startswith('#')):
                    continue
                if kind == 'm3u':
                    references.append(line)
                elif re.match(r'^FILE\b', line, re.I):
                    match = re.fullmatch(r'FILE\s+(?:"([^"]+)"|(\S+))\s+BINARY', line, re.I)
                    if not match:
                        raise ValueError('invalid')
                    references.append(match[1] or match[2])
            if not references:
                raise ValueError('invalid')
            if len(references) > MAX_GRAPH_FILES:
                raise ValueError('oversized')
            for reference in references:
                child = entry.parent / _safe_reference(reference)
                # A raw track has no universal header; only a CUE may use it,
                # and its evidence is existence/containment, not track integrity.
                try:
                    nested = _validate(root, child, max_bytes, active + (entry,), companion=kind == 'cue', cache=cache)
                except ValueError as error:
                    raise ValueError('oversized' if str(error) == 'oversized' else 'invalid') from None
                bundle.files.update(nested.files)
                if len(bundle.files) > MAX_GRAPH_FILES or bundle.size > max_bytes:
                    raise ValueError('oversized')
                if nested.level == 'header_only':
                    bundle.level = 'header_only'
        elif companion and entry.suffix.lower() == '.bin':
            pass
        elif kind == 'seven_zip':
            if size < 32 or header[:6] != b'7z\xbc\xaf\x27\x1c':
                raise ValueError('invalid')
            raise ValueError('unsupported')
        elif kind in ('iso', 'chd', 'rvz', 'cso', 'wbfs'):
            if not _header_valid(kind, header, size, stream):
                raise ValueError('invalid')
            bundle.level = 'header_only'
        else:
            raise ValueError('unsupported')
        if _snapshot(os.fstat(stream.fileno())) != snapshot:
            raise ValueError('invalid')
        cache[key] = bundle
        return bundle


def inspect_fixtures(root: Path, max_bytes: int = MAX_INSPECTION_BYTES) -> Inventory:
    """Inspect only bounded regular files beneath an owner-designated root.

    No tools are executed, archives extracted, or source files written. Unknown
    extensions remain unsupported. Scan failures and missing roots use sanitized
    fixed statuses. Collection paths remain private to the returned object.
    InterruptedError and KeyboardInterrupt propagate rather than becoming
    sanitized failure or partial-scan reports.
    ``max_bytes`` bounds each source file, each complete companion graph, and
    each ZIP's total expanded bytes. The default is 512 MiB. Invalid limits
    return status ``invalid_limit`` without reading the source. Optical and
    compressed images use bounded header reads; ZIP CRC verification streams
    members. Increasing this cap does not change the stage method's default.
    """
    supplied_root = Path(root)
    root = Path(os.path.abspath(root))
    report = {'status': 'ok', 'provider_match': 'unverified', 'selected_ready': False,
              'rejected_symlinks': 0, 'scan_errors': 0,
              'seven_zip_tool_available': any(shutil.which(tool) is not None for tool in ('7zz', '7z', '7za')),
              'classes': {kind: {key: 0 for key in ('candidates', 'structurally_validated', 'header_validated', 'invalid', 'oversized', 'unsupported', 'ready')} for kind in _CLASSES}}
    bundles = []
    if not isinstance(max_bytes, int) or isinstance(max_bytes, bool) or max_bytes <= 0:
        report['status'] = 'invalid_limit'
        return Inventory(root, report, bundles)
    if '..' in supplied_root.parts:
        report['status'] = 'unsafe_root'
        return Inventory(root, report, bundles)
    try:
        root_descriptor = _open_directory(root)
        os.close(root_descriptor)
    except InterruptedError:
        raise
    except OSError:
        report['status'] = 'unsafe_root' if any(p.is_symlink() for p in (root, *root.parents)) else ('invalid_root' if root.exists() else 'missing_root')
        return Inventory(root, report, bundles)
    pending = [Path('.')]
    scanned = 0
    while pending and report['status'] == 'ok':
        directory = pending.pop()
        try:
            descriptor = _open_directory(root / directory)
            try:
                with os.scandir(descriptor) as entries:
                    for item in entries:
                        scanned += 1
                        if scanned > MAX_FILES:
                            report['status'] = 'scan_limit'
                            break
                        relative = directory / item.name
                        if item.is_symlink():
                            report['rejected_symlinks'] += 1
                        elif item.is_dir(follow_symlinks=False):
                            if len(relative.parts) <= MAX_DEPTH:
                                pending.append(relative)
                            else:
                                report['status'] = 'scan_limit'
                        elif item.is_file(follow_symlinks=False):
                            kind = _SUFFIXES.get(relative.suffix.lower(), 'unknown')
                            counts = report['classes'][kind]
                            counts['candidates'] += 1
                            try:
                                bundle = _validate(root, relative, max_bytes)
                            except InterruptedError:
                                raise
                            except (OSError, ValueError, UnicodeError, zipfile.BadZipFile, RuntimeError, NotImplementedError, zlib.error, EOFError) as error:
                                category = str(error) if isinstance(error, ValueError) else 'invalid'
                                counts[category if category in ('unsupported', 'oversized') else 'invalid'] += 1
                                continue
                            counts['structurally_validated' if bundle.level == 'structural' else 'header_validated'] += 1
                            counts['ready'] += 1
                            bundles.append(bundle)
            finally:
                os.close(descriptor)
        except InterruptedError:
            raise
        except OSError:
            report['scan_errors'] += 1
    if report['scan_errors'] and report['status'] == 'ok':
        report['status'] = 'partial_scan'
    report['selected_ready'] = bool(bundles)
    return Inventory(root, report, bundles)


def inventory(root: Path, max_bytes: int = MAX_INSPECTION_BYTES) -> dict:
    """Convenience wrapper returning only sanitized inventory evidence."""
    return inspect_fixtures(root, max_bytes).summary()


def select_fixtures(root: Path, destination: Path, max_bytes: int = MAX_INSPECTION_BYTES) -> dict:
    """Inspect then stage with the same cap, returning sanitized copy evidence."""
    return inspect_fixtures(root, max_bytes).stage(destination, max_bytes)
