"""Host-only packaging verification for the Android qualification APK.

The qualification artifact is compiled as an Android Release variant but is
signed with the ordinary Android debug identity. This module records the
build-time source state, inspects the packaged APK through the Android build
tools, and writes a sanitized provenance document. It never starts ADB, talks
to a device, or treats a successful build command as proof of package content.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
from typing import Any, Iterable, Sequence
import uuid
import zipfile


SCHEMA_VERSION = 1
ORDINARY_APPLICATION_ID = "com.argusromtoolkit.argus"
QUALIFICATION_APPLICATION_ID_SUFFIX = ".qualification"
QUALIFICATION_APPLICATION_ID = ORDINARY_APPLICATION_ID + QUALIFICATION_APPLICATION_ID_SUFFIX
QUALIFICATION_BUILD_TYPE = "qualification"
FLUTTER_BUILD_MODE = "release"
MINIMUM_SDK = 30
EXPECTED_MAIN_ACTIVITY = "com.argusromtoolkit.argus.MainActivity"
EXPECTED_APPLICATION = "com.argusromtoolkit.argus.ArgusApplication"
EXPECTED_FOREGROUND_SERVICE = "com.argusromtoolkit.argus.ArgusForegroundExecutionService"
EXPECTED_FILE_PROVIDER = "androidx.core.content.FileProvider"
EXPECTED_STARTUP_PROVIDER = "androidx.startup.InitializationProvider"
EXPECTED_PROFILE_RECEIVER = "androidx.profileinstaller.ProfileInstallReceiver"
EXPECTED_FILE_PROVIDER_PATHS = "res/xml/argus_file_paths.xml"
REQUIRED_PERMISSIONS = frozenset(
    {
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
        "android.permission.MANAGE_EXTERNAL_STORAGE",
        "android.permission.POST_NOTIFICATIONS",
    }
)
DYNAMIC_RECEIVER_PERMISSION = (
    QUALIFICATION_APPLICATION_ID + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
)
QUALIFICATION_PERMISSIONS = REQUIRED_PERMISSIONS | {DYNAMIC_RECEIVER_PERMISSION}
REQUIRED_NATIVE_LIBRARIES = (
    "lib/arm64-v8a/libargus_bridge.so",
    "lib/arm64-v8a/libandroid_native_keyring_store.so",
)
BRIDGE_LIBRARY = "lib/arm64-v8a/libargus_bridge.so"
KEYRING_LIBRARY = "lib/arm64-v8a/libandroid_native_keyring_store.so"
FLUTTER_APP_LIBRARY = "lib/arm64-v8a/libapp.so"
FLUTTER_ENGINE_LIBRARY = "lib/arm64-v8a/libflutter.so"
FLUTTER_VMSERVICE_LIBRARY = "lib/arm64-v8a/libvmservice_snapshot.so"
FLUTTER_RUNTIME_LIBRARIES = frozenset({FLUTTER_APP_LIBRARY, FLUTTER_ENGINE_LIBRARY})
BUILD_METADATA_ENTRY = "META-INF/com/android/build/gradle/app-metadata.properties"
UNEXPECTED_DEBUG_SECTIONS = frozenset(
    {".debug_info", ".debug_line", ".debug_str"}
)
DEBUG_SECTION_PREFIXES = (".debug_", ".zdebug_")
NATIVE_OUTPUT_MARKER = ".argus-native-build-output"
NATIVE_OUTPUT_MARKER_CONTENT = "argus-native-build-output v1\n"
APK_MAX_MEMBER_UNCOMPRESSED_BYTES = 128 * 1024 * 1024
APK_MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
SOURCE_FINGERPRINT_VERSION = 2
ELF_MACHINE_AARCH64 = 183
ELF_CLASS_64 = 2
ELF_TYPE_SHARED = 3

EXIT_VALIDATED = 0
EXIT_INVALID_ARTIFACT = 1
EXIT_USAGE = 2
EXIT_TOOLING = 3
EXIT_SOURCE_NOT_ELIGIBLE = 4


class VerificationError(RuntimeError):
    """The APK or its metadata is not the approved qualification artifact."""


class ToolingError(RuntimeError):
    """A required host inspection tool or input is unavailable."""


@dataclass(frozen=True)
class SourceState:
    """Git identity of the exact source tree that built an artifact."""

    revision: str
    dirty: bool
    fingerprint: str
    changed_path_count: int


@dataclass(frozen=True)
class ElfInfo:
    """The small part of an ELF header needed to reject another architecture."""

    elf_class: int
    little_endian: bool
    elf_type: int
    machine: int

    @property
    def architecture(self) -> str:
        if self.machine == ELF_MACHINE_AARCH64:
            return "aarch64"
        if self.machine == 62:
            return "x86_64"
        if self.machine == 40:
            return "arm"
        if self.machine == 3:
            return "x86"
        return f"machine-{self.machine}"


@dataclass(frozen=True)
class BadgingFacts:
    package_id: str
    version_code: int
    version_name: str
    min_sdk: int | None
    target_sdk: int | None
    debuggable_line: bool
    launchable_activity: str | None
    native_codes: tuple[str, ...]


@dataclass(frozen=True)
class XmlNode:
    name: str
    attributes: dict[str, str] = field(default_factory=dict)
    children: list["XmlNode"] = field(default_factory=list)


@dataclass(frozen=True)
class ComponentFacts:
    kind: str
    name: str
    exported: bool | None
    permission: str | None
    grant_uri_permissions: bool | None
    foreground_service_type: int | None
    authorities: tuple[str, ...]
    intent_actions: tuple[str, ...]
    intent_categories: tuple[str, ...]
    meta_data_names: tuple[str, ...]
    meta_data_resources: tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class ManifestFacts:
    application_name: str | None
    debuggable: bool | None
    activities: tuple[ComponentFacts, ...]
    services: tuple[ComponentFacts, ...]
    providers: tuple[ComponentFacts, ...]
    receivers: tuple[ComponentFacts, ...]
    permissions: frozenset[str]

    @property
    def authorities(self) -> tuple[str, ...]:
        found: list[str] = []
        for provider in self.providers:
            found.extend(provider.authorities)
        return tuple(found)


@dataclass(frozen=True)
class SignatureFacts:
    verified: bool
    schemes: tuple[str, ...]
    signer_count: int
    certificate_sha256: str | None


@dataclass(frozen=True)
class NativeLibraryFacts:
    path: str
    sha256: str
    size_bytes: int
    elf: ElfInfo
    debug_sections: tuple[str, ...] = ()


@dataclass(frozen=True)
class DeclaredLibrary:
    """A native library hash recorded by the build script."""

    sha256: str
    size_bytes: int


@dataclass(frozen=True)
class NativeMetadata:
    profile: str
    command: tuple[str, ...]
    features: str
    rust_toolchain: str
    rustc_version: str
    cargo_ndk_version: str
    cargo_ndk_platform: str
    cargo_lock_sha256: str
    source_revision: str
    source_dirty: bool
    source_fingerprint: str
    libraries: dict[str, DeclaredLibrary]
    output_directory: str


@dataclass(frozen=True)
class FlutterReleaseFacts:
    libapp_present: bool
    libflutter_present: bool
    vmservice_snapshot_present: bool
    kernel_blob_present: bool
    isolate_snapshot_present: bool
    vm_snapshot_present: bool

    @property
    def release_payload(self) -> bool:
        return (
            self.libapp_present
            and self.libflutter_present
            and not self.vmservice_snapshot_present
            and not self.kernel_blob_present
            and not self.isolate_snapshot_present
            and not self.vm_snapshot_present
        )


@dataclass(frozen=True)
class ApkFacts:
    path: Path
    sha256: str
    size_bytes: int
    entries: tuple[str, ...]
    badging: BadgingFacts
    manifest: ManifestFacts
    signatures: SignatureFacts
    alignment_ok: bool
    flutter_release: FlutterReleaseFacts
    native_libraries: dict[str, NativeLibraryFacts]
    build_record: dict[str, Any]
    apk_metadata: dict[str, str]
    provider_paths: tuple[tuple[str, str, str], ...]
    provider_paths_resource: str


@dataclass(frozen=True)
class ExpectedArtifact:
    application_id: str
    version_code: int
    version_name: str
    signer_sha256: str


@dataclass(frozen=True)
class ComparisonFacts:
    path: Path
    sha256: str
    size_bytes: int
    package_id: str
    version_code: int
    version_name: str
    debuggable: bool
    signatures: SignatureFacts
    flutter_release: FlutterReleaseFacts
    native_libraries: dict[str, NativeLibraryFacts]
    revision: str


def _run_git(root: Path, *arguments: str) -> bytes:
    try:
        completed = subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise ToolingError("git is required to establish source provenance") from error
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", "replace").strip()
        raise VerificationError(f"git could not read source provenance: {message}")
    return completed.stdout


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _status_paths(raw: bytes) -> tuple[str, ...]:
    parts = raw.split(b"\0")
    paths: list[str] = []
    index = 0
    while index < len(parts):
        entry = parts[index]
        index += 1
        if not entry:
            continue
        text = entry.decode("utf-8", "surrogateescape")
        if len(text) < 4:
            continue
        status = text[:2]
        paths.append(text[3:])
        if status[0] in {"R", "C"} or status[1] in {"R", "C"}:
            if index < len(parts) and parts[index]:
                paths.append(parts[index].decode("utf-8", "surrogateescape"))
            index += 1
    return tuple(sorted(set(paths)))


def compute_source_state(root: Path) -> SourceState:
    """Fingerprint HEAD plus every tracked and untracked source change."""

    root = root.resolve()
    revision = _run_git(root, "rev-parse", "--verify", "HEAD").decode().strip()
    status = _run_git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    # Full object IDs make the fingerprint independent of each checkout's Git
    # `core.abbrev` setting. The same baseline and working-tree bytes therefore
    # produce the same fingerprint in an independent CI checkout.
    diff = _run_git(root, "diff", "--binary", "--full-index", "HEAD", "--")
    untracked = _run_git(root, "ls-files", "--others", "--exclude-standard", "-z")
    untracked_parts: list[bytes] = []
    for raw_name in untracked.split(b"\0"):
        if not raw_name:
            continue
        name = raw_name.decode("utf-8", "surrogateescape")
        candidate = root / name
        if candidate.is_symlink():
            digest = _sha256_bytes(b"symlink\0" + os.readlink(candidate).encode())
            untracked_parts.append(
                name.encode("utf-8", "surrogateescape")
                + b"\0symlink\0"
                + digest.encode()
            )
        else:
            entry_stat = candidate.stat(follow_symlinks=False)
            if stat.S_ISREG(entry_stat.st_mode):
                digest = sha256_file(candidate)
                mode = stat.S_IMODE(entry_stat.st_mode)
                untracked_parts.append(
                    name.encode("utf-8", "surrogateescape")
                    + b"\0file\0"
                    + format(mode, "o").encode()
                    + b"\0"
                    + digest.encode()
                )
            else:
                digest = _sha256_bytes(b"unreadable")
                untracked_parts.append(
                    name.encode("utf-8", "surrogateescape")
                    + b"\0unreadable\0"
                    + digest.encode()
                )
    untracked_parts.sort()
    payload = (
        f"argus-android-qualification-source-v{SOURCE_FINGERPRINT_VERSION}\0".encode()
        + revision.encode()
        + b"\0"
        + diff
        + b"\0"
        + b"\0".join(untracked_parts)
    )
    paths = _status_paths(status)
    return SourceState(
        revision=revision,
        dirty=bool(status),
        fingerprint=_sha256_bytes(payload),
        changed_path_count=len(paths),
    )


def source_state_document(source: SourceState) -> dict[str, Any]:
    """Return the stable JSON shape shared by build records and snapshots."""

    return {
        "revision": source.revision,
        "dirty": source.dirty,
        "changed_path_count": source.changed_path_count,
        "fingerprint_algorithm": "sha256",
        "fingerprint": source.fingerprint,
    }


def parse_source_state(value: Any, description: str) -> SourceState:
    """Parse a source-state document and reject malformed provenance."""

    if not isinstance(value, dict):
        raise VerificationError(f"{description} must be a JSON object")
    revision = value.get("revision")
    dirty = value.get("dirty")
    changed_path_count = value.get("changed_path_count")
    fingerprint = value.get("fingerprint")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise VerificationError(f"{description} has an invalid revision")
    if not isinstance(dirty, bool):
        raise VerificationError(f"{description} has an invalid dirty flag")
    if (
        not isinstance(changed_path_count, int)
        or isinstance(changed_path_count, bool)
        or changed_path_count < 0
    ):
        raise VerificationError(f"{description} has an invalid changed path count")
    if not isinstance(fingerprint, str) or not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise VerificationError(f"{description} has an invalid fingerprint")
    if value.get("fingerprint_algorithm") != "sha256":
        raise VerificationError(f"{description} has an unsupported fingerprint algorithm")
    return SourceState(
        revision=revision,
        dirty=dirty,
        fingerprint=fingerprint,
        changed_path_count=changed_path_count,
    )


def read_pubspec_version(root: Path) -> tuple[str, int]:
    pubspec = (root / "flutter/pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^+\s]+)\+([0-9]+)\s*$", pubspec, re.MULTILINE)
    if match is None:
        raise VerificationError("flutter/pubspec.yaml does not declare name+code version")
    return match.group(1), int(match.group(2))


def read_gradle_identity(root: Path) -> tuple[str, str]:
    build_file = (root / "flutter/android/app/build.gradle.kts").read_text(encoding="utf-8")
    application = re.search(r'applicationId\s*=\s*"([^"]+)"', build_file)
    suffix = re.search(r'applicationIdSuffix\s*=\s*"([^"]+)"', build_file)
    if application is None or suffix is None:
        raise VerificationError("Android Build configuration does not declare the qualification identity")
    return application.group(1), application.group(1) + suffix.group(1)


def read_flutter_version(root: Path) -> str:
    config = json.loads((root / "flutter/.fvmrc").read_text(encoding="utf-8"))
    version = config.get("flutter")
    if not isinstance(version, str) or not version:
        raise VerificationError("flutter/.fvmrc does not pin a Flutter version")
    return version


def read_android_gradle_plugin_version(root: Path) -> str:
    settings = (root / "flutter/android/settings.gradle.kts").read_text(encoding="utf-8")
    match = re.search(
        r'id\("com\.android\.application"\)\s+version\s+"([^"]+)"',
        settings,
    )
    if match is None:
        raise VerificationError("Android settings do not pin the Android Gradle Plugin")
    return match.group(1)


def read_rust_channel(root: Path) -> str:
    toolchain = (root / "rust-toolchain.toml").read_text(encoding="utf-8")
    match = re.search(r'^channel\s*=\s*"([^"]+)"', toolchain, re.MULTILINE)
    if match is None:
        raise VerificationError("rust-toolchain.toml does not pin a channel")
    return match.group(1)


def read_rust_workspace_version(root: Path) -> str:
    """Read the workspace package version that releases Android native code."""

    manifest = (root / "rust/Cargo.toml").read_text(encoding="utf-8")
    section = re.search(
        r"^\[workspace\.package\]\s*$(.*?)(?=^\[|\Z)",
        manifest,
        re.MULTILINE | re.DOTALL,
    )
    if section is None:
        raise VerificationError("rust/Cargo.toml has no workspace.package section")
    match = re.search(r'^version\s*=\s*"([^"]+)"', section.group(1), re.MULTILINE)
    if match is None:
        raise VerificationError("rust/Cargo.toml does not declare a workspace version")
    return match.group(1)


def read_cargo_ndk_version(root: Path) -> str:
    """Read the cargo-ndk version pinned by the native build script."""

    script = (root / "scripts/build_android_bridge.sh").read_text(encoding="utf-8")
    match = re.search(r'^CARGO_NDK_VERSION="([^"]+)"$', script, re.MULTILINE)
    if match is None:
        raise VerificationError("native build script does not pin cargo-ndk")
    return match.group(1)


def build_record(root: Path, prebuild_source: SourceState | None = None) -> dict[str, Any]:
    """Create the source and build-mode record embedded in the qualification APK.

    ``prebuild_source`` is captured before Gradle starts. The record-generation
    task compares it with the source state it observes, so source changes between
    the operator's build command and final packaging fail before an APK is made.
    """

    version_name, version_code = read_pubspec_version(root)
    _, application_id = read_gradle_identity(root)
    source = compute_source_state(root)
    if prebuild_source is not None and prebuild_source != source:
        raise VerificationError(
            "source tree changed after the qualification build started"
        )
    source_document = source_state_document(source)
    return {
        "schema_version": SCHEMA_VERSION,
        "application_id": application_id,
        "version_name": version_name,
        "version_code": version_code,
        "android_build_type": QUALIFICATION_BUILD_TYPE,
        "flutter_build_mode": FLUTTER_BUILD_MODE,
        "source": source_document,
        "prebuild_source": source_document,
        "pinned_build_inputs": {
            "flutter_version": read_flutter_version(root),
            "android_gradle_plugin": read_android_gradle_plugin_version(root),
            "rust_channel": read_rust_channel(root),
            "native_profile": "release",
            "native_features": "default",
            "basis": "repository pins; Flutter version is not recoverable from the APK",
        },
    }


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


_ATTRIBUTE_LINE = re.compile(r"^\s*A:\s+(.*)$")
_ENTITY_LINE = re.compile(r"^(\s*)E:\s+([^\s(]+)")


def _decode_aapt_value(value: str) -> str:
    value = value.strip()
    quoted = re.match(r'^"(?P<text>(?:[^"\\]|\\.)*)"', value)
    if quoted is not None:
        return bytes(quoted.group("text"), "utf-8").decode("unicode_escape")
    return value.split(" ", 1)[0]


def parse_xmltree(text: str) -> XmlNode:
    """Parse the entity and attribute lines emitted by ``aapt2 dump xmltree``."""

    root = XmlNode(name="__root__")
    stack: list[tuple[XmlNode, int]] = [(root, -1)]
    current: XmlNode | None = None
    current_indent = -1
    for line in text.splitlines():
        entity = _ENTITY_LINE.match(line)
        if entity is not None:
            indent = len(entity.group(1))
            while len(stack) > 1 and stack[-1][1] >= indent:
                stack.pop()
            node = XmlNode(name=entity.group(2).strip())
            stack[-1][0].children.append(node)
            stack.append((node, indent))
            current = node
            current_indent = indent
            continue
        attribute = _ATTRIBUTE_LINE.match(line)
        if attribute is None or current is None:
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= current_indent:
            continue
        body = attribute.group(1)
        if "=" not in body:
            continue
        key, value = body.split("=", 1)
        key = re.sub(r"\(0x[0-9a-fA-F]+\)$", "", key.strip())
        name = key.rsplit(":", 1)[-1]
        current.attributes[name] = _decode_aapt_value(value)
    return root


def _first_child(node: XmlNode, name: str) -> XmlNode | None:
    for child in node.children:
        if child.name == name:
            return child
    return None


def _children(node: XmlNode, name: str) -> tuple[XmlNode, ...]:
    return tuple(child for child in node.children if child.name == name)


def _parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    if value == "true":
        return True
    if value == "false":
        return False
    return None


def _parse_int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        if value.startswith("0x"):
            return int(value, 16)
        return int(value, 10)
    except ValueError:
        return None


def _component_children(node: XmlNode, kind: str) -> tuple[ComponentFacts, ...]:
    components: list[ComponentFacts] = []
    for child in _children(node, kind):
        actions: list[str] = []
        categories: list[str] = []
        for intent_filter in _children(child, "intent-filter"):
            for action in _children(intent_filter, "action"):
                name = action.attributes.get("name")
                if name:
                    actions.append(name)
            for category in _children(intent_filter, "category"):
                name = category.attributes.get("name")
                if name:
                    categories.append(name)
        meta_data = tuple(
            (meta.attributes.get("name", ""), meta.attributes.get("resource", ""))
            for meta in _children(child, "meta-data")
            if "name" in meta.attributes
        )
        authorities_value = child.attributes.get("authorities", "")
        authorities = tuple(
            part.strip() for part in authorities_value.split(";") if part.strip()
        )
        components.append(
            ComponentFacts(
                kind=kind,
                name=child.attributes.get("name", ""),
                exported=_parse_bool(child.attributes.get("exported")),
                permission=child.attributes.get("permission"),
                grant_uri_permissions=_parse_bool(
                    child.attributes.get("grantUriPermissions")
                ),
                foreground_service_type=_parse_int(
                    child.attributes.get("foregroundServiceType")
                ),
                authorities=authorities,
                intent_actions=tuple(actions),
                intent_categories=tuple(categories),
                meta_data_names=tuple(name for name, _ in meta_data),
                meta_data_resources=meta_data,
            )
        )
    return tuple(components)


def manifest_facts(tree: XmlNode) -> ManifestFacts:
    manifest = _first_child(tree, "manifest")
    if manifest is None:
        raise VerificationError("packaged manifest has no manifest element")
    application = _first_child(manifest, "application")
    if application is None:
        raise VerificationError("packaged manifest has no application element")
    permissions = frozenset(
        node.attributes.get("name", "")
        for node in manifest.children
        if node.name.startswith("uses-permission")
    )
    return ManifestFacts(
        application_name=application.attributes.get("name"),
        debuggable=_parse_bool(application.attributes.get("debuggable")),
        activities=_component_children(application, "activity"),
        services=_component_children(application, "service"),
        providers=_component_children(application, "provider"),
        receivers=_component_children(application, "receiver"),
        permissions=permissions,
    )


def parse_badging(text: str) -> BadgingFacts:
    package_line = next(
        (line for line in text.splitlines() if line.startswith("package:")),
        None,
    )
    if package_line is None:
        raise VerificationError("aapt2 did not report a package identity")
    attributes = dict(re.findall(r"([A-Za-z0-9_]+)='([^']*)'", package_line))
    if "name" not in attributes or "versionCode" not in attributes:
        raise VerificationError("aapt2 package identity is incomplete")
    try:
        version_code = int(attributes["versionCode"])
    except ValueError as error:
        raise VerificationError("aapt2 reported a non-numeric versionCode") from error
    min_sdk = re.search(r"^minSdkVersion:'([0-9]+)'", text, re.MULTILINE)
    target_sdk = re.search(r"^targetSdkVersion:'([0-9]+)'", text, re.MULTILINE)
    launchable = re.search(r"^launchable-activity:\s+name='([^']*)'", text, re.MULTILINE)
    native_codes = re.search(r"^native-code:\s+'([^']*)'", text, re.MULTILINE)
    return BadgingFacts(
        package_id=attributes["name"],
        version_code=version_code,
        version_name=attributes.get("versionName", ""),
        min_sdk=int(min_sdk.group(1)) if min_sdk else None,
        target_sdk=int(target_sdk.group(1)) if target_sdk else None,
        debuggable_line="application-debuggable" in text.splitlines(),
        launchable_activity=launchable.group(1) if launchable else None,
        native_codes=(
            tuple(part.strip() for part in native_codes.group(1).split(","))
            if native_codes
            else tuple()
        ),
    )


def parse_apksigner_output(text: str) -> SignatureFacts:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not any(line == "Verifies" for line in lines):
        raise VerificationError("APK signature verification did not report Verifies")
    schemes: list[str] = []
    for line in lines:
        match = re.match(r"Verified using (v[0-9.]+) scheme .*: (true|false)$", line)
        if match and match.group(2) == "true":
            schemes.append(match.group(1))
    signer_match = re.search(r"^Number of signers:\s*([0-9]+)$", text, re.MULTILINE)
    signer_count = int(signer_match.group(1)) if signer_match else 0
    certificates = re.findall(
        r"certificate SHA-256 digest:\s*([0-9a-fA-F:]+)",
        text,
    )
    certificate = certificates[0].replace(":", "").lower() if certificates else None
    return SignatureFacts(
        verified=True,
        schemes=tuple(schemes),
        signer_count=signer_count,
        certificate_sha256=certificate,
    )


def parse_keytool_sha256(text: str) -> str:
    match = re.search(r"SHA256:\s*([0-9A-Fa-f:]+)", text)
    if match is None:
        raise VerificationError("debug signing keystore has no SHA-256 fingerprint")
    return match.group(1).replace(":", "").lower()


def parse_elf_header(data: bytes) -> ElfInfo:
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise VerificationError("native library is not an ELF file")
    elf_class = data[4]
    little_endian = data[5] == 1
    endian = "<" if little_endian else ">"
    elf_type, machine = struct.unpack_from(endian + "HH", data, 16)
    return ElfInfo(
        elf_class=elf_class,
        little_endian=little_endian,
        elf_type=elf_type,
        machine=machine,
    )


def parse_elf_debug_sections(data: bytes) -> tuple[str, ...]:
    """Return unexpected debug section names declared by an ELF shared object.

    Android Release packages should not carry compiler debug information. The
    section table is read directly from the packaged bytes so the result does
    not depend on build-script declarations or host tool availability.
    """

    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise VerificationError("native library is not an ELF file")
    if data[4] != ELF_CLASS_64:
        return ()
    endian = "<" if data[5] == 1 else ">"
    section_offset = struct.unpack_from(endian + "Q", data, 40)[0]
    section_size, section_count, names_index = struct.unpack_from(
        endian + "HHH", data, 58
    )
    if section_offset == 0:
        return ()
    if section_size < 64:
        raise VerificationError("native library has a malformed ELF section table")
    if section_offset + section_size > len(data):
        raise VerificationError("native library has a truncated ELF section table")

    def section_header(index: int) -> tuple[int, ...]:
        return struct.unpack_from(
            endian + "IIQQQQIIQQ", data, section_offset + section_size * index
        )

    first_section = section_header(0)
    if section_count == 0:
        section_count = first_section[5]
    if names_index == 0xFFFF:
        names_index = first_section[6]
    if section_count == 0:
        raise VerificationError("native library has a malformed ELF section count")
    table_end = section_offset + section_size * section_count
    if table_end > len(data):
        raise VerificationError("native library has a truncated ELF section table")
    if names_index == 0:
        raise VerificationError("native library has no ELF section-name table")
    if names_index >= section_count:
        raise VerificationError("native library has a malformed ELF section-name index")
    string_offset, string_size = section_header(names_index)[4:6]
    if string_offset + string_size > len(data):
        raise VerificationError("native library has a truncated ELF section-name table")
    names = data[string_offset : string_offset + string_size]
    found: list[str] = []
    for index in range(section_count):
        name_offset = section_header(index)[0]
        if name_offset >= len(names):
            raise VerificationError("native library has a malformed ELF section name")
        end = names.find(b"\0", name_offset)
        if end < 0:
            end = len(names)
        name = names[name_offset:end].decode("ascii", errors="replace")
        if name in UNEXPECTED_DEBUG_SECTIONS or name.startswith(DEBUG_SECTION_PREFIXES):
            found.append(name)
    return tuple(found)


def parse_native_metadata(value: Any) -> NativeMetadata:
    if not isinstance(value, dict):
        raise VerificationError("native build metadata must be a JSON object")
    if value.get("schema_version") != 1:
        raise VerificationError("native build metadata schema_version must be 1")
    required = {
        "build_profile",
        "cargo_command",
        "features",
        "rust_toolchain",
        "rustc_version",
        "cargo_ndk_version",
        "cargo_ndk_platform",
        "cargo_lock_sha256",
        "source_revision",
        "source_dirty",
        "source_fingerprint",
        "output_directory",
        "libraries",
    }
    missing = sorted(required - set(value))
    if missing:
        raise VerificationError(
            "native build metadata is missing: " + ", ".join(missing)
        )
    for field in (
        "build_profile",
        "features",
        "rust_toolchain",
        "rustc_version",
        "cargo_ndk_version",
        "cargo_ndk_platform",
        "cargo_lock_sha256",
        "source_revision",
        "source_fingerprint",
        "output_directory",
    ):
        if not isinstance(value[field], str) or not value[field]:
            raise VerificationError(
                f"native build metadata {field} must be a non-empty string"
            )
    if not isinstance(value["source_dirty"], bool):
        raise VerificationError("native build metadata source_dirty must be a boolean")
    if not re.fullmatch(r"[0-9a-f]{64}", value["cargo_lock_sha256"]):
        raise VerificationError(
            "native build metadata cargo_lock_sha256 must be a SHA-256 digest"
        )
    if not re.fullmatch(r"[0-9a-f]{64}", value["source_fingerprint"]):
        raise VerificationError(
            "native build metadata source_fingerprint must be a SHA-256 digest"
        )
    command = value["cargo_command"]
    if not isinstance(command, list) or not all(isinstance(item, str) for item in command):
        raise VerificationError("native build metadata cargo_command must be a string array")
    libraries_value = value["libraries"]
    if not isinstance(libraries_value, dict):
        raise VerificationError("native build metadata libraries must be an object")
    libraries: dict[str, DeclaredLibrary] = {}
    for name, entry in libraries_value.items():
        if not isinstance(name, str) or not isinstance(entry, dict):
            raise VerificationError("native build metadata has an invalid library entry")
        digest = entry.get("sha256")
        size = entry.get("size_bytes")
        if (
            not isinstance(digest, str)
            or not re.fullmatch(r"[0-9a-f]{64}", digest)
            or not isinstance(size, int)
            or isinstance(size, bool)
            or size < 0
        ):
            raise VerificationError("native build metadata has an invalid library entry")
        libraries[name] = DeclaredLibrary(sha256=digest, size_bytes=size)
    return NativeMetadata(
        profile=value["build_profile"],
        command=tuple(command),
        features=value["features"],
        rust_toolchain=value["rust_toolchain"],
        rustc_version=value["rustc_version"],
        cargo_ndk_version=value["cargo_ndk_version"],
        cargo_ndk_platform=value["cargo_ndk_platform"],
        cargo_lock_sha256=value["cargo_lock_sha256"],
        source_revision=value["source_revision"],
        source_dirty=value["source_dirty"],
        source_fingerprint=value["source_fingerprint"],
        libraries=libraries,
        output_directory=value["output_directory"],
    )


def _read_json(path: Path, description: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"{description} is not valid readable JSON") from error


def read_native_metadata(path: Path) -> NativeMetadata:
    return parse_native_metadata(_read_json(path, "native build metadata"))


def _resolve_tool(name: str, explicit: str | None, environment: str) -> Path:
    if explicit:
        candidate = Path(explicit).expanduser()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
        raise ToolingError(f"configured {name} is not executable")
    configured = os.environ.get(environment)
    if configured:
        candidate = Path(configured).expanduser()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
        raise ToolingError(f"{environment} does not name an executable {name}")
    found = shutil.which(name)
    if found:
        return Path(found)
    sdk_roots = [
        os.environ.get("ANDROID_SDK_ROOT"),
        os.environ.get("ANDROID_HOME"),
        str(Path.home() / "Library/Android/sdk"),
    ]
    for sdk in sdk_roots:
        if not sdk:
            continue
        build_tools = Path(sdk) / "build-tools"
        if not build_tools.is_dir():
            continue
        candidates = sorted(build_tools.glob(f"*/{name}"))
        for candidate in reversed(candidates):
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate
    raise ToolingError(f"required Android inspection tool is missing: {name}")


def resolve_tools(arguments: argparse.Namespace) -> dict[str, Path]:
    tools = {
        "aapt2": _resolve_tool("aapt2", getattr(arguments, "aapt2", None), "AAPT2"),
        "apksigner": _resolve_tool(
            "apksigner", getattr(arguments, "apksigner", None), "APKSIGNER"
        ),
        "zipalign": _resolve_tool(
            "zipalign", getattr(arguments, "zipalign", None), "ZIPALIGN"
        ),
        "keytool": _resolve_tool("keytool", getattr(arguments, "keytool", None), "KEYTOOL"),
    }
    return tools


def _run_tool(command: Sequence[str], description: str, allow_failure: bool = False) -> subprocess.CompletedProcess[str]:
    try:
        completed = subprocess.run(
            list(command),
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ToolingError(f"could not run {description}") from error
    if completed.returncode != 0 and not allow_failure:
        detail = (completed.stderr or completed.stdout).strip().splitlines()
        message = detail[-1] if detail else "no diagnostic"
        raise VerificationError(f"{description} failed: {message}")
    return completed


def _validate_zip_member_sizes(infos: Iterable[zipfile.ZipInfo]) -> None:
    """Reject declared decompression sizes that could exhaust verifier memory."""

    total = 0
    for info in infos:
        size = info.file_size
        if not isinstance(size, int) or size < 0:
            raise VerificationError(
                f"APK ZIP entry has an invalid decompressed size: {info.filename}"
            )
        if size > APK_MAX_MEMBER_UNCOMPRESSED_BYTES:
            raise VerificationError(
                "APK ZIP entry exceeds the decompressed-size limit: "
                + info.filename
            )
        total += size
        if total > APK_MAX_TOTAL_UNCOMPRESSED_BYTES:
            raise VerificationError(
                "APK ZIP entries exceed the total decompressed-size limit"
            )


def _zip_entries(apk: Path) -> tuple[str, ...]:
    try:
        with zipfile.ZipFile(apk) as archive:
            infos = tuple(archive.infolist())
            _validate_zip_member_sizes(infos)
            broken = archive.testzip()
            if broken is not None:
                raise VerificationError(f"APK has a corrupt entry: {broken}")
            names = tuple(info.filename for info in infos)
    except (OSError, zipfile.BadZipFile) as error:
        raise VerificationError("artifact is not a readable APK ZIP archive") from error
    if len(names) != len(set(names)):
        raise VerificationError("APK contains duplicate ZIP entries")
    return names


def _read_zip_entry(apk: Path, name: str) -> bytes:
    try:
        with zipfile.ZipFile(apk) as archive:
            _validate_zip_member_sizes((archive.getinfo(name),))
            return archive.read(name)
    except (KeyError, OSError, zipfile.BadZipFile) as error:
        raise VerificationError(f"APK is missing readable entry: {name}") from error


def _parse_properties(data: bytes) -> dict[str, str]:
    """Parse the simple Java-properties format written into an Android APK."""

    try:
        text = data.decode("utf-8")
    except UnicodeError as error:
        raise VerificationError("APK build metadata is not UTF-8") from error
    properties: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        if key:
            properties[key] = value
    return properties


def _flutter_release_facts(entries: tuple[str, ...]) -> FlutterReleaseFacts:
    """Distinguish normal Flutter Release packaging from Profile and Debug.

    For the pinned Flutter 3.44.7 Android engine, Profile packages the VM-service
    snapshot as ``libvmservice_snapshot.so``; Release does not. Profile and
    Release both omit the Debug-only kernel and VM/isolate snapshot assets, so
    the packaged native marker is required to distinguish them.
    """

    return FlutterReleaseFacts(
        libapp_present=FLUTTER_APP_LIBRARY in entries,
        libflutter_present=FLUTTER_ENGINE_LIBRARY in entries,
        vmservice_snapshot_present=FLUTTER_VMSERVICE_LIBRARY in entries,
        kernel_blob_present="assets/flutter_assets/kernel_blob.bin" in entries,
        isolate_snapshot_present="assets/flutter_assets/isolate_snapshot_data" in entries,
        vm_snapshot_present="assets/flutter_assets/vm_snapshot_data" in entries,
    )


def _native_library_facts(apk: Path, entries: tuple[str, ...]) -> dict[str, NativeLibraryFacts]:
    native_libraries: dict[str, NativeLibraryFacts] = {}
    for entry in entries:
        if not entry.startswith("lib/"):
            continue
        data = _read_zip_entry(apk, entry)
        native_libraries[entry] = NativeLibraryFacts(
            path=entry,
            sha256=_sha256_bytes(data),
            size_bytes=len(data),
            elf=parse_elf_header(data),
            debug_sections=parse_elf_debug_sections(data),
        )
    return native_libraries


def _resolve_resource_file(
    apk: Path,
    aapt2: Path,
    resource_id: str,
) -> tuple[str, str]:
    """Resolve an XML resource to its packaged file after resource shrinking."""

    completed = _run_tool(
        [str(aapt2), "dump", "resources", str(apk)],
        "aapt2 resource table inspection",
    )
    resource_pattern = re.compile(
        r"^\s*resource\s+(0x[0-9a-fA-F]+)\s+(\S+)\s*$"
    )
    file_pattern = re.compile(
        r"^\s*(?:\([^)]*\)\s+)?\(file\)\s+(\S+)\s+type=XML\s*$"
    )
    current_id: str | None = None
    current_name = ""
    for line in completed.stdout.splitlines():
        match = resource_pattern.match(line)
        if match is not None:
            current_id = match.group(1).lower()
            current_name = match.group(2)
            continue
        file_match = file_pattern.match(line)
        if file_match is not None and current_id == resource_id.lower():
            return current_name, file_match.group(1)
    raise VerificationError("FileProvider paths resource is not present in the APK")


def _provider_paths(
    apk: Path,
    aapt2: Path,
    resource_file: str,
) -> tuple[tuple[str, str, str], ...]:
    completed = _run_tool(
        [str(aapt2), "dump", "xmltree", "--file", resource_file, str(apk)],
        "aapt2 provider path inspection",
    )
    tree = parse_xmltree(completed.stdout)
    paths = _first_child(tree, "paths")
    if paths is None:
        raise VerificationError("FileProvider paths resource has no paths element")
    result: list[tuple[str, str, str]] = []
    for child in paths.children:
        result.append(
            (
                child.name,
                child.attributes.get("name", ""),
                child.attributes.get("path", ""),
            )
        )
    return tuple(result)


def inspect_apk(apk: Path, tools: dict[str, Path]) -> ApkFacts:
    if not apk.is_file():
        raise VerificationError("qualification APK is missing")
    entries = _zip_entries(apk)
    badging_result = _run_tool(
        [str(tools["aapt2"]), "dump", "badging", str(apk)],
        "aapt2 badging inspection",
    )
    badging = parse_badging(badging_result.stdout)
    manifest_result = _run_tool(
        [
            str(tools["aapt2"]),
            "dump",
            "xmltree",
            "--file",
            "AndroidManifest.xml",
            str(apk),
        ],
        "aapt2 manifest inspection",
    )
    manifest = manifest_facts(parse_xmltree(manifest_result.stdout))
    signature_result = _run_tool(
        [
            str(tools["apksigner"]),
            "verify",
            "--print-certs",
            "--verbose",
            "--min-sdk-version",
            str(MINIMUM_SDK),
            str(apk),
        ],
        "APK signature verification",
    )
    signatures = parse_apksigner_output(signature_result.stdout)
    alignment = _run_tool(
        [str(tools["zipalign"]), "-c", "-P", "16", "4", str(apk)],
        "APK alignment verification",
        allow_failure=True,
    )
    flutter_release = _flutter_release_facts(entries)
    native_libraries = _native_library_facts(apk, entries)
    apk_metadata = (
        _parse_properties(_read_zip_entry(apk, BUILD_METADATA_ENTRY))
        if BUILD_METADATA_ENTRY in entries
        else {}
    )
    record_bytes = _read_zip_entry(apk, "assets/qualification-build.json")
    try:
        record = json.loads(record_bytes.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise VerificationError("embedded qualification build record is not valid JSON") from error
    if not isinstance(record, dict):
        raise VerificationError("embedded qualification build record must be an object")
    file_provider = next(
        (provider for provider in manifest.providers if provider.name == EXPECTED_FILE_PROVIDER),
        None,
    )
    if file_provider is None:
        raise VerificationError("packaged manifest has no FileProvider")
    provider_resource = dict(file_provider.meta_data_resources).get(
        "android.support.FILE_PROVIDER_PATHS"
    )
    if not provider_resource:
        raise VerificationError("FileProvider has no paths resource reference")
    resource_match = re.fullmatch(r"@(0x[0-9a-fA-F]+)", provider_resource)
    if resource_match is None:
        raise VerificationError("FileProvider paths reference is not a resource ID")
    resource_name, resource_file = _resolve_resource_file(
        apk, tools["aapt2"], resource_match.group(1)
    )
    if resource_name != "xml/argus_file_paths":
        raise VerificationError(
            f"FileProvider points at an unexpected resource: {resource_name}"
        )
    provider_paths = _provider_paths(apk, tools["aapt2"], resource_file)
    return ApkFacts(
        path=apk,
        sha256=sha256_file(apk),
        size_bytes=apk.stat().st_size,
        entries=entries,
        badging=badging,
        manifest=manifest,
        signatures=signatures,
        alignment_ok=alignment.returncode == 0,
        flutter_release=flutter_release,
        native_libraries=native_libraries,
        build_record=record,
        apk_metadata=apk_metadata,
        provider_paths=provider_paths,
        provider_paths_resource=resource_name,
    )


def read_expected_debug_certificate(keystore: Path, keytool: Path) -> str:
    if not keystore.is_file():
        raise ToolingError(
            "the Android debug signing keystore is missing; build the qualification APK first"
        )
    completed = _run_tool(
        [
            str(keytool),
            "-list",
            "-v",
            "-keystore",
            str(keystore),
            "-alias",
            "androiddebugkey",
            "-storepass",
            "android",
            "-keypass",
            "android",
        ],
        "debug signing certificate inspection",
    )
    return parse_keytool_sha256(completed.stdout + completed.stderr)


def _component_names(components: Iterable[ComponentFacts]) -> tuple[str, ...]:
    return tuple(component.name for component in components)


def _component_document(component: ComponentFacts) -> dict[str, Any]:
    """Serialize every verified manifest attribute needed for review."""

    return {
        "kind": component.kind,
        "name": component.name,
        "exported": component.exported,
        "permission": component.permission,
        "grant_uri_permissions": component.grant_uri_permissions,
        "foreground_service_type": component.foreground_service_type,
        "authorities": list(component.authorities),
        "intent_actions": list(component.intent_actions),
        "intent_categories": list(component.intent_categories),
        "meta_data_names": list(component.meta_data_names),
        "meta_data_resources": [
            {"name": name, "resource": resource}
            for name, resource in component.meta_data_resources
        ],
    }


def _require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def validate_artifact(
    facts: ApkFacts,
    expected: ExpectedArtifact,
    native: NativeMetadata,
    source: SourceState,
    root: Path,
    prebuild_source: SourceState | None = None,
) -> list[str]:
    """Return every independently checkable artifact defect found in the APK."""

    errors: list[str] = []
    _require(facts.badging.package_id == expected.application_id, "application ID mismatch", errors)
    _require(facts.badging.version_code == expected.version_code, "versionCode mismatch", errors)
    _require(facts.badging.version_name == expected.version_name, "versionName mismatch", errors)
    _require(
        read_rust_workspace_version(root) == facts.badging.version_name,
        "Rust workspace version does not match qualification versionName",
        errors,
    )
    _require(facts.badging.min_sdk == MINIMUM_SDK, "minSdkVersion mismatch", errors)
    _require(not facts.badging.debuggable_line, "badging reports a debuggable application", errors)
    _require(facts.manifest.debuggable is not True, "merged manifest is effectively debuggable", errors)
    _require(facts.manifest.application_name == EXPECTED_APPLICATION, "Application class mismatch", errors)
    _require(
        facts.badging.launchable_activity == EXPECTED_MAIN_ACTIVITY,
        "launchable Activity mismatch",
        errors,
    )
    _require(facts.badging.native_codes == ("arm64-v8a",), "packaged native ABIs are not ARM64-only", errors)

    activities = facts.manifest.activities
    _require(_component_names(activities) == (EXPECTED_MAIN_ACTIVITY,), "Activity inventory mismatch", errors)
    if len(activities) == 1:
        activity = activities[0]
        _require(activity.exported is True, "launch Activity is not exported", errors)
        _require("android.intent.action.MAIN" in activity.intent_actions, "launch Activity has no MAIN action", errors)
        _require(
            "android.intent.category.LAUNCHER" in activity.intent_categories,
            "launch Activity has no LAUNCHER category",
            errors,
        )

    services = facts.manifest.services
    _require(
        _component_names(services) == (EXPECTED_FOREGROUND_SERVICE,),
        "foreground Service inventory mismatch",
        errors,
    )
    if len(services) == 1:
        service = services[0]
        _require(service.exported is False, "foreground Service is exported", errors)
        _require(
            service.foreground_service_type is not None
            and bool(service.foreground_service_type & 1),
            "foreground Service does not declare dataSync",
            errors,
        )

    file_providers = [
        provider for provider in facts.manifest.providers if provider.name == EXPECTED_FILE_PROVIDER
    ]
    _require(len(file_providers) == 1, "FileProvider inventory mismatch", errors)
    expected_authority = expected.application_id + ".diagnostics"
    if len(file_providers) == 1:
        provider = file_providers[0]
        _require(
            provider.authorities == (expected_authority,),
            "FileProvider authority mismatch",
            errors,
        )
        _require(provider.exported is False, "FileProvider is exported", errors)
        _require(
            provider.grant_uri_permissions is True,
            "FileProvider does not grant URI permissions",
            errors,
        )
        _require(
            "android.support.FILE_PROVIDER_PATHS" in provider.meta_data_names,
            "FileProvider has no paths metadata",
            errors,
        )
    _require(
        facts.provider_paths == (("files-path", "diagnostics", "argus/diagnostics/"),),
        "FileProvider paths do not expose the diagnostics directory",
        errors,
    )

    all_authorities = facts.manifest.authorities
    expected_startup_authority = expected.application_id + ".androidx-startup"
    _require(
        len(all_authorities) == len(set(all_authorities)),
        "provider authorities are not unique",
        errors,
    )
    _require(
        set(all_authorities) == {expected_authority, expected_startup_authority},
        "provider authority inventory mismatch",
        errors,
    )
    _require(
        not (
            set(all_authorities)
            & {
                ORDINARY_APPLICATION_ID + ".diagnostics",
                ORDINARY_APPLICATION_ID + ".androidx-startup",
            }
        ),
        "qualification APK contains an ordinary-application provider authority",
        errors,
    )
    _require(
        all(authority.startswith(expected.application_id + ".") for authority in all_authorities),
        "qualification provider authority is not scoped to the qualification package",
        errors,
    )
    startup_providers = [
        provider for provider in facts.manifest.providers if provider.name == EXPECTED_STARTUP_PROVIDER
    ]
    _require(len(startup_providers) == 1, "AndroidX startup provider inventory mismatch", errors)
    if len(startup_providers) == 1:
        _require(startup_providers[0].exported is False, "AndroidX startup provider is exported", errors)

    _require(
        facts.manifest.permissions == QUALIFICATION_PERMISSIONS,
        "packaged Android permission inventory mismatch",
        errors,
    )

    exported = [
        component
        for component in (
            *activities,
            *services,
            *facts.manifest.providers,
            *facts.manifest.receivers,
        )
        if component.exported is True
    ]
    exported_names = {component.name for component in exported}
    _require(
        exported_names == {EXPECTED_MAIN_ACTIVITY, EXPECTED_PROFILE_RECEIVER},
        "exported component inventory mismatch",
        errors,
    )
    profile_receivers = [
        receiver for receiver in facts.manifest.receivers if receiver.name == EXPECTED_PROFILE_RECEIVER
    ]
    if len(profile_receivers) == 1:
        _require(
            profile_receivers[0].permission == "android.permission.DUMP",
            "profile installer receiver lacks the DUMP permission",
            errors,
        )

    for required_library in REQUIRED_NATIVE_LIBRARIES:
        _require(required_library in facts.native_libraries, f"missing native library: {required_library}", errors)
    for entry, library in facts.native_libraries.items():
        parts = entry.split("/")
        _require(
            len(parts) >= 2 and parts[1] == "arm64-v8a",
            f"native library is not ARM64: {entry}",
            errors,
        )
        _require(
            library.elf.elf_class == ELF_CLASS_64,
            f"native library is not ELF64: {entry}",
            errors,
        )
        _require(
            library.elf.little_endian,
            f"native library is not little-endian: {entry}",
            errors,
        )
        _require(library.elf.architecture == "aarch64", f"native library ELF machine is not AArch64: {entry}", errors)
        _require(library.elf.elf_type == ELF_TYPE_SHARED, f"native library is not a shared object: {entry}", errors)
        _require(
            not library.debug_sections,
            "native library contains unexpected ELF debug sections: "
            + entry
            + " ("
            + ", ".join(library.debug_sections)
            + ")",
            errors,
        )
    unsupported_abis = {
        parts[1]
        for entry in facts.entries
        if entry.startswith("lib/")
        for parts in (entry.split("/"),)
        if len(parts) >= 3 and parts[1] != "arm64-v8a"
    }
    _require(
        not unsupported_abis,
        "unexpected native ABI packaging: " + ", ".join(sorted(unsupported_abis)),
        errors,
    )

    packaged_non_flutter = set(facts.native_libraries) - FLUTTER_RUNTIME_LIBRARIES
    declared_native = set(native.libraries)
    for required_library in REQUIRED_NATIVE_LIBRARIES:
        _require(
            required_library in declared_native,
            f"native build metadata is missing: {required_library}",
            errors,
        )
    for undeclared in sorted(packaged_non_flutter - declared_native):
        _require(False, f"packaged native library is not declared: {undeclared}", errors)
    for missing in sorted(declared_native - packaged_non_flutter):
        _require(False, f"declared native library is not packaged: {missing}", errors)
    for library_name in sorted(packaged_non_flutter & declared_native):
        actual = facts.native_libraries[library_name]
        declared = native.libraries[library_name]
        _require(
            actual.sha256 == declared.sha256,
            f"native library hash mismatch: {library_name}",
            errors,
        )
        _require(
            actual.size_bytes == declared.size_bytes,
            f"native library size mismatch: {library_name}",
            errors,
        )
    _require(native.profile == "release", "native build profile is not release", errors)
    _require("--release" in native.command, "Cargo command did not request the release profile", errors)
    _require("--locked" in native.command, "Cargo command did not use the lockfile", errors)
    _require("--package" in native.command and "argus-bridge" in native.command, "Cargo command did not build argus-bridge", errors)
    _require("-t" in native.command and "arm64-v8a" in native.command, "Cargo command did not target arm64-v8a", errors)
    _require(native.features == "default", "native build did not use production-default features", errors)
    _require(
        not Path(native.output_directory).is_absolute(),
        "native build output directory is not sanitized",
        errors,
    )
    _require(
        not any(Path(argument).is_absolute() for argument in native.command),
        "native Cargo command contains a host absolute path",
        errors,
    )
    _require(
        native.rust_toolchain == read_rust_channel(root),
        "native build used a different Rust toolchain",
        errors,
    )
    _require(
        native.rustc_version.startswith("rustc " + native.rust_toolchain + " "),
        "native build rustc version does not match the selected toolchain",
        errors,
    )
    _require(
        native.cargo_ndk_version.endswith(read_cargo_ndk_version(root)),
        "native build cargo-ndk version does not match the repository pin",
        errors,
    )
    _require(
        native.cargo_ndk_platform == "30",
        "native build did not target Android API 30",
        errors,
    )
    _require(
        native.cargo_lock_sha256 == sha256_file(root / "rust/Cargo.lock"),
        "native build lockfile digest mismatch",
        errors,
    )
    _require(native.source_revision == source.revision, "native build source revision mismatch", errors)
    _require(native.source_dirty == source.dirty, "native build dirty state mismatch", errors)
    _require(
        native.source_fingerprint == source.fingerprint,
        "native build source fingerprint mismatch",
        errors,
    )
    if prebuild_source is not None:
        _require(
            native.source_revision == prebuild_source.revision
            and native.source_dirty == prebuild_source.dirty
            and native.source_fingerprint == prebuild_source.fingerprint,
            "native build source state differs from the pre-build snapshot",
            errors,
        )

    _require(facts.flutter_release.release_payload, "APK does not contain a Flutter Release AOT payload", errors)
    _require(facts.signatures.verified, "APK signature is not valid", errors)
    _require(facts.signatures.signer_count == 1, "APK must have exactly one signer", errors)
    _require(
        facts.signatures.certificate_sha256 == expected.signer_sha256,
        "APK signer certificate fingerprint mismatch",
        errors,
    )
    _require(facts.alignment_ok, "APK is not zip-aligned", errors)

    record = facts.build_record
    _require(record.get("application_id") == expected.application_id, "embedded build record application ID mismatch", errors)
    _require(record.get("version_code") == expected.version_code, "embedded build record versionCode mismatch", errors)
    _require(record.get("version_name") == expected.version_name, "embedded build record versionName mismatch", errors)
    _require(record.get("android_build_type") == QUALIFICATION_BUILD_TYPE, "embedded build record build type mismatch", errors)
    _require(record.get("flutter_build_mode") == FLUTTER_BUILD_MODE, "embedded build record Flutter mode mismatch", errors)
    record_source = record.get("source")
    if not isinstance(record_source, dict):
        errors.append("embedded build record has no source object")
    else:
        _require(record_source.get("revision") == source.revision, "embedded build record source revision mismatch", errors)
        _require(record_source.get("fingerprint") == source.fingerprint, "embedded build record source fingerprint mismatch", errors)
        _require(record_source.get("fingerprint_algorithm") == "sha256", "embedded build record fingerprint algorithm mismatch", errors)
        _require(
            isinstance(record_source.get("dirty"), bool)
            and record_source.get("dirty") == source.dirty,
            "embedded build record source dirty-state mismatch",
            errors,
        )
    record_prebuild = record.get("prebuild_source")
    if not isinstance(record_prebuild, dict):
        errors.append("embedded build record has no prebuild_source object")
    else:
        _require(record_prebuild == record_source, "embedded pre-build source record changed", errors)
        if prebuild_source is not None:
            _require(
                record_prebuild
                == source_state_document(prebuild_source),
                "embedded build record differs from the pre-build source snapshot",
                errors,
            )
    pinned_inputs = record.get("pinned_build_inputs")
    if not isinstance(pinned_inputs, dict):
        errors.append("embedded build record has no pinned_build_inputs object")
    else:
        _require(pinned_inputs.get("flutter_version") == read_flutter_version(root), "embedded build record Flutter version mismatch", errors)
        _require(pinned_inputs.get("android_gradle_plugin") == read_android_gradle_plugin_version(root), "embedded build record Android Gradle Plugin mismatch", errors)
        _require(pinned_inputs.get("rust_channel") == read_rust_channel(root), "embedded build record Rust channel mismatch", errors)
        _require(pinned_inputs.get("native_profile") == "release", "embedded build record native profile mismatch", errors)
        _require(pinned_inputs.get("native_features") == "default", "embedded build record native feature mismatch", errors)
    _require(
        facts.apk_metadata.get("androidGradlePluginVersion")
        == read_android_gradle_plugin_version(root),
        "APK build metadata Android Gradle Plugin version mismatch",
        errors,
    )
    _require(
        facts.apk_metadata.get("appMetadataVersion") == "1.1",
        "APK build metadata version is unsupported",
        errors,
    )
    return errors


def inspect_comparison_apk(
    apk: Path,
    tools: dict[str, Path],
    revision: str,
) -> ComparisonFacts:
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise VerificationError("comparison revision must be a full 40-character Git SHA")
    entries = _zip_entries(apk)
    badging_result = _run_tool(
        [str(tools["aapt2"]), "dump", "badging", str(apk)],
        "comparison aapt2 badging inspection",
    )
    badging = parse_badging(badging_result.stdout)
    if badging.package_id != ORDINARY_APPLICATION_ID:
        raise VerificationError("comparison artifact is not an ordinary-application Release APK")
    manifest_result = _run_tool(
        [
            str(tools["aapt2"]),
            "dump",
            "xmltree",
            "--file",
            "AndroidManifest.xml",
            str(apk),
        ],
        "comparison aapt2 manifest inspection",
    )
    manifest = manifest_facts(parse_xmltree(manifest_result.stdout))
    signature_result = _run_tool(
        [
            str(tools["apksigner"]),
            "verify",
            "--print-certs",
            "--verbose",
            "--min-sdk-version",
            str(MINIMUM_SDK),
            str(apk),
        ],
        "comparison APK signature verification",
    )
    signatures = parse_apksigner_output(signature_result.stdout)
    return ComparisonFacts(
        path=apk,
        sha256=sha256_file(apk),
        size_bytes=apk.stat().st_size,
        package_id=badging.package_id,
        version_code=badging.version_code,
        version_name=badging.version_name,
        debuggable=badging.debuggable_line or manifest.debuggable is True,
        signatures=signatures,
        flutter_release=_flutter_release_facts(entries),
        native_libraries=_native_library_facts(apk, entries),
        revision=revision,
    )


def validate_comparison(
    facts: ApkFacts,
    comparison: ComparisonFacts,
    expected: ExpectedArtifact,
) -> list[str]:
    errors: list[str] = []
    _require(comparison.package_id == ORDINARY_APPLICATION_ID, "comparison package identity mismatch", errors)
    _require(comparison.version_code == expected.version_code, "comparison versionCode mismatch", errors)
    _require(comparison.version_name == expected.version_name, "comparison versionName mismatch", errors)
    _require(not comparison.debuggable, "comparison APK is debuggable", errors)
    _require(comparison.signatures.verified, "comparison APK signature is not valid", errors)
    _require(comparison.signatures.signer_count == 1, "comparison APK must have exactly one signer", errors)
    _require(comparison.sha256 != facts.sha256, "comparison APK is the qualification APK", errors)
    _require(
        comparison.flutter_release.release_payload,
        "comparison APK does not contain a Flutter Release AOT payload",
        errors,
    )
    comparable = set(facts.native_libraries)
    comparison_libraries = set(comparison.native_libraries)
    for missing in sorted(comparable - comparison_libraries):
        _require(False, f"comparison APK is missing native library: {missing}", errors)
    for extra in sorted(comparison_libraries - comparable):
        _require(False, f"comparison APK has an extra native library: {extra}", errors)
    for library_name in sorted(comparable & comparison_libraries):
        actual = facts.native_libraries[library_name]
        compared = comparison.native_libraries[library_name]
        _require(
            actual.sha256 == compared.sha256,
            f"release-profile native library differs from comparison artifact: {library_name}",
            errors,
        )
        _require(
            actual.size_bytes == compared.size_bytes,
            f"native library size differs from comparison artifact: {library_name}",
            errors,
        )
    return errors


def _source_eligibility(
    facts: ApkFacts,
    source: SourceState,
    allow_provisional: bool,
    expected_revision: str | None,
) -> tuple[list[str], bool]:
    errors: list[str] = []
    if expected_revision is not None and source.revision != expected_revision:
        errors.append("selected source revision does not match the worktree HEAD")
    record_source = facts.build_record.get("source")
    if not isinstance(record_source, dict):
        return (errors + ["embedded build record has no source state"], True)
    record_dirty = record_source.get("dirty")
    if not isinstance(record_dirty, bool):
        return (
            errors + ["embedded build record has no valid source dirty state"],
            True,
        )
    if record_dirty or source.dirty:
        if not allow_provisional:
            errors.append("source tree is dirty; a final artifact requires a clean pinned revision")
        return (errors, True)
    return (errors, False)


def prepare_native_output_directory(requested: Path, default: Path) -> Path:
    """Validate a native output directory before the build replaces its ABI.

    Default Debug/Release directories are build-owned. An explicit directory
    is accepted only when it is empty or carries the marker written by this
    helper, so a caller cannot point the destructive ABI replacement at an
    unrelated directory. Symbolic links are rejected before any removal.
    """

    requested_absolute = Path(os.path.abspath(requested.expanduser()))
    if requested_absolute != requested_absolute.resolve():
        raise VerificationError(
            "native output path must not contain a symbolic link component"
        )
    requested_resolved = requested_absolute
    default_resolved = default.expanduser().resolve()
    if requested_resolved == Path(requested_resolved.anchor):
        raise VerificationError(
            "refusing to use the filesystem root as a native output directory"
        )
    if requested_resolved.exists() and not requested_resolved.is_dir():
        raise VerificationError("native output path is not a directory")
    abi_directory = requested_resolved / "arm64-v8a"
    if abi_directory.is_symlink():
        raise VerificationError("native ABI output directory must not be a symbolic link")
    if abi_directory.exists() and not abi_directory.is_dir():
        raise VerificationError("native ABI output path is not a directory")

    marker = requested_resolved / NATIVE_OUTPUT_MARKER
    if marker.is_symlink():
        raise VerificationError("native output marker must not be a symbolic link")
    build_owned = requested_resolved == default_resolved
    if not build_owned:
        if marker.is_file():
            if marker.read_text(encoding="utf-8") != NATIVE_OUTPUT_MARKER_CONTENT:
                raise VerificationError("native output directory marker is not recognized")
            build_owned = True
        elif requested_resolved.exists() and any(requested_resolved.iterdir()):
            raise VerificationError(
                "refusing to replace an unowned native output directory: "
                + str(requested_resolved)
            )

    requested_resolved.mkdir(parents=True, exist_ok=True)
    if not build_owned:
        marker.write_text(NATIVE_OUTPUT_MARKER_CONTENT, encoding="utf-8")
    return requested_resolved


def _same_file_identity(left: os.stat_result, right: os.stat_result) -> bool:
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)


def _open_verified_directory(path: Path, description: str) -> int:
    """Open a real directory and reject replacement during the open."""

    path_stat = os.stat(path, follow_symlinks=False)
    if not stat.S_ISDIR(path_stat.st_mode):
        raise VerificationError(f"{description} must be a real directory")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        opened_stat = os.fstat(descriptor)
        current_stat = os.stat(path, follow_symlinks=False)
        if not _same_file_identity(path_stat, opened_stat) or not _same_file_identity(
            opened_stat, current_stat
        ):
            raise VerificationError(f"{description} changed during validation")
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def _open_child_directory(parent_fd: int, name: str, description: str) -> int:
    child_stat = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISDIR(child_stat.st_mode):
        raise VerificationError(f"{description} must be a real directory")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        if not _same_file_identity(child_stat, os.fstat(descriptor)):
            raise VerificationError(f"{description} changed during validation")
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def _relative_parts(path: Path, root: Path, description: str) -> tuple[str, ...]:
    candidate = Path(os.path.abspath(path))
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise VerificationError(f"{description} must be inside the native output directory") from error
    if not relative.parts or any(part in {"", ".", ".."} for part in relative.parts):
        raise VerificationError(f"{description} has an unsafe relative path")
    return relative.parts


def _open_relative_parent(
    root_fd: int, parts: tuple[str, ...], description: str
) -> int:
    descriptor = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            child = _open_child_directory(descriptor, part, description)
            os.close(descriptor)
            descriptor = child
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def _read_regular_file_at(
    parent_fd: int, name: str, description: str, maximum_bytes: int
) -> tuple[bytes, os.stat_result]:
    entry_stat = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISREG(entry_stat.st_mode):
        raise VerificationError(f"{description} must be a regular file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        opened_stat = os.fstat(descriptor)
        if not _same_file_identity(entry_stat, opened_stat):
            raise VerificationError(f"{description} changed during validation")
        with os.fdopen(os.dup(descriptor), "rb") as handle:
            data = handle.read(maximum_bytes + 1)
        if len(data) > maximum_bytes:
            raise VerificationError(f"{description} is unexpectedly large")
        return data, opened_stat
    finally:
        os.close(descriptor)


def _validate_native_output_marker(parent_fd: int) -> None:
    data, _ = _read_regular_file_at(
        parent_fd,
        NATIVE_OUTPUT_MARKER,
        "native output marker",
        len(NATIVE_OUTPUT_MARKER_CONTENT.encode()),
    )
    if data != NATIVE_OUTPUT_MARKER_CONTENT.encode():
        raise VerificationError("native output directory marker is not recognized")


def _write_file_atomically_at(parent_fd: int, name: str, data: bytes) -> None:
    temporary = f".{name}.{uuid.uuid4().hex}.tmp"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(temporary, flags, 0o644, dir_fd=parent_fd)
    try:
        with os.fdopen(os.dup(descriptor), "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
            os.fchmod(handle.fileno(), 0o644)
        os.replace(
            temporary,
            name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
        )
    except BaseException:
        try:
            os.unlink(temporary, dir_fd=parent_fd)
        except FileNotFoundError:
            pass
        raise
    finally:
        os.close(descriptor)


def _remove_directory_at(
    parent_fd: int,
    name: str,
    description: str,
    expected: os.stat_result | None = None,
) -> None:
    entry_stat = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if not stat.S_ISDIR(entry_stat.st_mode):
        raise VerificationError(f"{description} is not a real directory")
    if expected is not None and not _same_file_identity(entry_stat, expected):
        raise VerificationError(f"{description} changed before cleanup")
    shutil.rmtree(name, dir_fd=parent_fd)


def commit_native_output(
    requested: Path,
    default: Path,
    staged_abi: Path,
    metadata_temporary: Path,
    metadata: Path,
    maximum_metadata_bytes: int = 1024 * 1024,
) -> Path:
    """Replace native output from a pinned directory and revalidate ownership."""

    output = prepare_native_output_directory(requested, default)
    if metadata.resolve(strict=False).parent != output:
        raise VerificationError("native metadata must be in the output directory")
    if len(_relative_parts(metadata, output, "native metadata")) != 1:
        raise VerificationError("native metadata must be directly in the output directory")

    output_fd = _open_verified_directory(output, "native output directory")
    staged_parent_fd = -1
    metadata_parent_fd = -1
    try:
        if output != default.expanduser().resolve():
            _validate_native_output_marker(output_fd)
        metadata_parts = _relative_parts(metadata_temporary, output, "native metadata temporary")
        metadata_parent_fd = _open_relative_parent(
            output_fd, metadata_parts, "native metadata parent"
        )
        metadata_bytes, metadata_stat = _read_regular_file_at(
            metadata_parent_fd,
            metadata_parts[-1],
            "native metadata temporary",
            maximum_metadata_bytes,
        )

        staged_parts = _relative_parts(staged_abi, output, "staged native ABI")
        staged_parent_fd = _open_relative_parent(
            output_fd, staged_parts, "staged native ABI parent"
        )
        staged_stat = os.stat(
            staged_parts[-1], dir_fd=staged_parent_fd, follow_symlinks=False
        )
        if not stat.S_ISDIR(staged_stat.st_mode):
            raise VerificationError("staged native ABI must be a real directory")

        final_name = "arm64-v8a"
        backup_name: str | None = None
        try:
            final_stat = os.stat(final_name, dir_fd=output_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            if not stat.S_ISDIR(final_stat.st_mode):
                raise VerificationError("native ABI output path must be a real directory")
            backup_name = f".argus-bridge-previous-{uuid.uuid4().hex}"
            os.rename(
                final_name,
                backup_name,
                src_dir_fd=output_fd,
                dst_dir_fd=output_fd,
            )

        try:
            os.rename(
                staged_parts[-1],
                final_name,
                src_dir_fd=staged_parent_fd,
                dst_dir_fd=output_fd,
            )
            _write_file_atomically_at(
                output_fd, metadata.name, metadata_bytes
            )
        except BaseException:
            try:
                _remove_directory_at(
                    output_fd,
                    final_name,
                    "new native ABI",
                    expected=staged_stat,
                )
            except FileNotFoundError:
                pass
            if backup_name is not None:
                os.rename(
                    backup_name,
                    final_name,
                    src_dir_fd=output_fd,
                    dst_dir_fd=output_fd,
                )
            raise

        if backup_name is not None:
            _remove_directory_at(output_fd, backup_name, "previous native ABI")

        current_metadata = os.stat(
            metadata_parts[-1], dir_fd=metadata_parent_fd, follow_symlinks=False
        )
        if _same_file_identity(current_metadata, metadata_stat):
            os.unlink(metadata_parts[-1], dir_fd=metadata_parent_fd)
        return output
    finally:
        if staged_parent_fd >= 0:
            os.close(staged_parent_fd)
        if metadata_parent_fd >= 0:
            os.close(metadata_parent_fd)
        os.close(output_fd)


def _safe_relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.name


def provenance_document(
    facts: ApkFacts,
    native: NativeMetadata,
    source: SourceState,
    expected: ExpectedArtifact,
    comparison: ComparisonFacts | None,
    result: str,
    root: Path,
) -> dict[str, Any]:
    record = facts.build_record
    all_components = (
        *facts.manifest.activities,
        *facts.manifest.services,
        *facts.manifest.providers,
        *facts.manifest.receivers,
    )
    packaged_non_flutter = set(facts.native_libraries) - FLUTTER_RUNTIME_LIBRARIES
    declared_native = set(native.libraries)
    native_inventory_matches = packaged_non_flutter == declared_native and all(
        facts.native_libraries[name].sha256 == declared.sha256
        and facts.native_libraries[name].size_bytes == declared.size_bytes
        for name, declared in native.libraries.items()
        if name in facts.native_libraries
    )
    verified: dict[str, Any] = {
        "artifact": {
            "path": _safe_relative(facts.path, root),
            "sha256": facts.sha256,
            "size_bytes": facts.size_bytes,
        },
        "package": {
            "application_id": facts.badging.package_id,
            "version_code": facts.badging.version_code,
            "version_name": facts.badging.version_name,
            "min_sdk": facts.badging.min_sdk,
            "target_sdk": facts.badging.target_sdk,
        },
        "execution_mode": {
            "debuggable": (
                facts.manifest.debuggable is True or facts.badging.debuggable_line
            ),
            "flutter_release_payload": facts.flutter_release.release_payload,
        },
        "manifest": {
            "application": facts.manifest.application_name,
            "debuggable": facts.manifest.debuggable,
            "components": [_component_document(component) for component in all_components],
            "provider_authorities": list(facts.manifest.authorities),
            "permissions": sorted(facts.manifest.permissions),
            "provider_paths_resource": facts.provider_paths_resource,
            "provider_paths": [
                {"kind": kind, "name": name, "path": path}
                for kind, name, path in facts.provider_paths
            ],
        },
        "signing": {
            "verified": facts.signatures.verified,
            "schemes": list(facts.signatures.schemes),
            "signer_count": facts.signatures.signer_count,
            "certificate_sha256": facts.signatures.certificate_sha256,
            "expected_certificate_sha256": expected.signer_sha256,
            "expected_certificate_source": "configured Android debug signing keystore",
        },
        "native": {
            "abi": "arm64-v8a",
            "libraries": {
                name: {
                    "sha256": library.sha256,
                    "size_bytes": library.size_bytes,
                    "architecture": library.elf.architecture,
                    "elf_class": library.elf.elf_class,
                    "little_endian": library.elf.little_endian,
                    "elf_type": library.elf.elf_type,
                }
                for name, library in sorted(facts.native_libraries.items())
            },
            "non_flutter_inventory_matches_declared": native_inventory_matches,
        },
        "flutter_release": {
            "libapp_present": facts.flutter_release.libapp_present,
            "libflutter_present": facts.flutter_release.libflutter_present,
            "vmservice_snapshot_present": facts.flutter_release.vmservice_snapshot_present,
            "kernel_blob_present": facts.flutter_release.kernel_blob_present,
            "isolate_snapshot_present": facts.flutter_release.isolate_snapshot_present,
            "vm_snapshot_present": facts.flutter_release.vm_snapshot_present,
            "release_discriminator": "absence of lib/arm64-v8a/libvmservice_snapshot.so",
        },
        "apk_build_metadata": {
            "app_metadata_version": facts.apk_metadata.get("appMetadataVersion"),
            "android_gradle_plugin_version": facts.apk_metadata.get(
                "androidGradlePluginVersion"
            ),
        },
        "alignment": facts.alignment_ok,
    }
    declared = {
        "embedded_build_record": record,
        "native_build_metadata": {
            "build_profile": native.profile,
            "cargo_command": list(native.command),
            "features": native.features,
            "rust_toolchain": native.rust_toolchain,
            "rustc_version": native.rustc_version,
            "cargo_ndk_version": native.cargo_ndk_version,
            "cargo_ndk_platform": native.cargo_ndk_platform,
            "cargo_lock_sha256": native.cargo_lock_sha256,
            "output_directory": native.output_directory,
            "source_revision": native.source_revision,
            "source_dirty": native.source_dirty,
            "source_fingerprint": native.source_fingerprint,
            "libraries": {
                name: {"sha256": library.sha256, "size_bytes": library.size_bytes}
                for name, library in sorted(native.libraries.items())
            },
        },
        "tool_version_basis": {
            "flutter": "repository pin in flutter/.fvmrc; not recoverable from the APK",
            "android_gradle_plugin": "repository pin cross-checked against APK build metadata",
            "rust": "rustc version emitted by the pinned native build toolchain",
            "cargo_ndk": "version emitted by the pinned cargo-ndk executable",
        },
    }
    comparison_document: dict[str, Any] | None = None
    if comparison is not None:
        comparison_document = {
            "verified": {
                "artifact": {
                    "path": _safe_relative(comparison.path, root),
                    "sha256": comparison.sha256,
                    "size_bytes": comparison.size_bytes,
                },
                "package": {
                    "application_id": comparison.package_id,
                    "version_code": comparison.version_code,
                    "version_name": comparison.version_name,
                },
                "debuggable": comparison.debuggable,
                "signing": {
                    "verified": comparison.signatures.verified,
                    "signer_count": comparison.signatures.signer_count,
                    "certificate_sha256": comparison.signatures.certificate_sha256,
                },
                "flutter_release": {
                    "libapp_present": comparison.flutter_release.libapp_present,
                    "libflutter_present": comparison.flutter_release.libflutter_present,
                    "vmservice_snapshot_present": comparison.flutter_release.vmservice_snapshot_present,
                    "kernel_blob_present": comparison.flutter_release.kernel_blob_present,
                    "isolate_snapshot_present": comparison.flutter_release.isolate_snapshot_present,
                    "vm_snapshot_present": comparison.flutter_release.vm_snapshot_present,
                    "release_payload": comparison.flutter_release.release_payload,
                },
                "native_inventory_identical": (
                    set(comparison.native_libraries) == set(facts.native_libraries)
                    and all(
                        comparison.native_libraries[name].sha256 == library.sha256
                        and comparison.native_libraries[name].size_bytes == library.size_bytes
                        for name, library in facts.native_libraries.items()
                    )
                ),
                "apk_sha256_matches": comparison.sha256 == facts.sha256,
            },
            "declared": {
                "source_revision": comparison.revision,
                "source_revision_matches_qualification": comparison.revision == source.revision,
                "apk_sha256_expected_to_match": False,
            },
        }
    return {
        "schema_version": SCHEMA_VERSION,
        "verification_result": result,
        "eligible_for_admission": result == "ARTIFACT_VALIDATED",
        "source": source_state_document(source),
        "verified": verified,
        "declared": declared,
        "comparison": comparison_document,
        "assumptions": [
            "The embedded build record describes the build invocation; its revision and fingerprint are cross-checked against the current Git worktree.",
            "Flutter version and native profile/feature selection are build declarations. The pinned Profile marker and APK contents independently establish the observed Flutter Release payload.",
            "An optional comparison source revision is supplied by the verifier operator because an ordinary Release APK does not embed that revision.",
            "A matching source revision and fingerprint establish source provenance, not binary equivalence with a distributable Release artifact.",
        ],
        "limitations": [
            "This host inspection does not install or execute the APK and does not constitute physical qualification.",
            "The qualification APK shares its source and release-profile native libraries with the ordinary Release build, but its package identity and signing certificate are deliberately different.",
        ],
    }


def _default_debug_keystore() -> Path:
    android_user_home = os.environ.get("ANDROID_USER_HOME")
    if android_user_home:
        return Path(android_user_home) / "debug.keystore"
    android_sdk_home = os.environ.get("ANDROID_SDK_HOME")
    if android_sdk_home:
        return Path(android_sdk_home) / ".android/debug.keystore"
    return Path.home() / ".android/debug.keystore"


def command_build_record(arguments: argparse.Namespace) -> int:
    root = Path(arguments.root).resolve()
    output = Path(arguments.output).resolve()
    try:
        prebuild_source = None
        if arguments.prebuild_source_state:
            prebuild_source = parse_source_state(
                _read_json(
                    Path(arguments.prebuild_source_state).resolve(),
                    "pre-build source state",
                ),
                "pre-build source state",
            )
        record = build_record(root, prebuild_source)
    except (OSError, VerificationError) as error:
        print(f"Qualification build record failed: {error}", file=sys.stderr)
        return EXIT_INVALID_ARTIFACT
    write_json(output, record)
    return 0


def command_source_state(arguments: argparse.Namespace) -> int:
    """Capture the exact source state before any build task starts."""

    root = Path(arguments.root).resolve()
    output = Path(arguments.output).resolve()
    try:
        write_json(output, source_state_document(compute_source_state(root)))
    except (OSError, VerificationError) as error:
        print(f"Qualification source snapshot failed: {error}", file=sys.stderr)
        return EXIT_INVALID_ARTIFACT
    return 0


def command_native_output_directory(arguments: argparse.Namespace) -> int:
    """Validate and print the canonical native build output directory."""

    root = Path(arguments.root).resolve()
    requested = Path(arguments.output).expanduser()
    if not requested.is_absolute():
        requested = root / requested
    default = Path(arguments.default_output).expanduser()
    if not default.is_absolute():
        default = root / default
    try:
        print(prepare_native_output_directory(requested, default))
    except (OSError, VerificationError) as error:
        print(f"Native output directory rejected: {error}", file=sys.stderr)
        return EXIT_USAGE
    return 0


def command_native_output_commit(arguments: argparse.Namespace) -> int:
    """Commit staged native output using a revalidated, pinned directory."""

    root = Path(arguments.root).resolve()
    requested = Path(arguments.output).expanduser()
    if not requested.is_absolute():
        requested = root / requested
    default = Path(arguments.default_output).expanduser()
    if not default.is_absolute():
        default = root / default
    staged_abi = Path(arguments.staged_abi).expanduser()
    if not staged_abi.is_absolute():
        staged_abi = root / staged_abi
    metadata_temporary = Path(arguments.metadata_temporary).expanduser()
    if not metadata_temporary.is_absolute():
        metadata_temporary = root / metadata_temporary
    metadata = Path(arguments.metadata).expanduser()
    if not metadata.is_absolute():
        metadata = root / metadata
    try:
        print(
            commit_native_output(
                requested,
                default,
                staged_abi,
                metadata_temporary,
                metadata,
            )
        )
    except (OSError, VerificationError) as error:
        print(f"Native output commit rejected: {error}", file=sys.stderr)
        return EXIT_USAGE
    return 0


def command_verify(arguments: argparse.Namespace) -> int:
    root = Path(arguments.root).resolve()
    apk = Path(arguments.apk).resolve()
    native_metadata_path = Path(arguments.native_metadata).resolve()
    try:
        tools = resolve_tools(arguments)
        prebuild_source = None
        if arguments.prebuild_source_state:
            prebuild_source = parse_source_state(
                _read_json(
                    Path(arguments.prebuild_source_state).resolve(),
                    "pre-build source state",
                ),
                "pre-build source state",
            )
        if bool(arguments.comparison_apk) != bool(arguments.comparison_revision):
            raise VerificationError(
                "comparison APK and explicit comparison revision must be supplied together"
            )
        native = read_native_metadata(native_metadata_path)
        expected_version_name, expected_version_code = read_pubspec_version(root)
        ordinary_id, qualification_id = read_gradle_identity(root)
        if ordinary_id != ORDINARY_APPLICATION_ID or qualification_id != QUALIFICATION_APPLICATION_ID:
            raise VerificationError("source declares an unexpected application identity")
        keystore = (
            Path(arguments.debug_keystore).expanduser()
            if arguments.debug_keystore
            else _default_debug_keystore()
        )
        expected_signer = read_expected_debug_certificate(keystore, tools["keytool"])
        pinned_signer = arguments.expected_signer_sha256
        if pinned_signer is not None:
            pinned_signer = pinned_signer.replace(":", "").lower()
            if pinned_signer != expected_signer:
                raise VerificationError(
                    "pinned signer certificate does not match the configured debug keystore"
                )
        expected = ExpectedArtifact(
            application_id=QUALIFICATION_APPLICATION_ID,
            version_code=expected_version_code,
            version_name=expected_version_name,
            signer_sha256=expected_signer,
        )
        source = compute_source_state(root)
        facts = inspect_apk(apk, tools)
        errors = validate_artifact(
            facts,
            expected,
            native,
            source,
            root,
            prebuild_source,
        )
        comparison: ComparisonFacts | None = None
        if arguments.comparison_apk:
            comparison = inspect_comparison_apk(
                Path(arguments.comparison_apk).resolve(),
                tools,
                arguments.comparison_revision,
            )
            errors.extend(validate_comparison(facts, comparison, expected))
        if errors:
            for error in errors:
                print(f"Qualification artifact rejected: {error}", file=sys.stderr)
            return EXIT_INVALID_ARTIFACT
        source_errors, provisional = _source_eligibility(
            facts,
            source,
            bool(arguments.allow_provisional),
            arguments.expected_revision,
        )
        if source_errors:
            for error in source_errors:
                print(f"Qualification artifact not eligible: {error}", file=sys.stderr)
            return EXIT_SOURCE_NOT_ELIGIBLE
        result = "PROVISIONAL_ARTIFACT" if provisional else "ARTIFACT_VALIDATED"
        document = provenance_document(facts, native, source, expected, comparison, result, root)
        if arguments.provenance_out:
            write_json(Path(arguments.provenance_out).resolve(), document)
        print(f"Qualification artifact verification: {result}")
        print(f"APK SHA-256: {facts.sha256}")
        print(f"Package: {facts.badging.package_id}")
        print(
            "Version: versionCode=%s versionName=%s"
            % (facts.badging.version_code, facts.badging.version_name)
        )
        print(f"Signer SHA-256: {facts.signatures.certificate_sha256}")
        return EXIT_VALIDATED
    except ToolingError as error:
        print(f"Qualification inspection tooling unavailable: {error}", file=sys.stderr)
        return EXIT_TOOLING
    except VerificationError as error:
        print(f"Qualification artifact rejected: {error}", file=sys.stderr)
        return EXIT_INVALID_ARTIFACT
    except (OSError, ValueError) as error:
        print(f"Qualification artifact inspection failed: {error}", file=sys.stderr)
        return EXIT_INVALID_ARTIFACT


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)

    record = subcommands.add_parser(
        "build-record",
        help="write the source and build-mode record embedded in the qualification APK",
    )
    record.add_argument("--root", default=".", help="repository root")
    record.add_argument("--output", required=True, help="record JSON path")
    record.add_argument(
        "--prebuild-source-state",
        help="source snapshot captured immediately before the build",
    )
    record.set_defaults(handler=command_build_record)

    source_state = subcommands.add_parser(
        "source-state",
        help="capture the source revision, dirty state, and fingerprint",
    )
    source_state.add_argument("--root", default=".", help="repository root")
    source_state.add_argument("--output", required=True, help="source-state JSON path")
    source_state.set_defaults(handler=command_source_state)

    native_output = subcommands.add_parser(
        "native-output-dir",
        help="validate a native library output directory before replacing its ABI",
    )
    native_output.add_argument("--root", default=".", help="repository root")
    native_output.add_argument("--output", required=True, help="requested output directory")
    native_output.add_argument(
        "--default-output",
        required=True,
        help="default build-owned output directory for this profile",
    )
    native_output.set_defaults(handler=command_native_output_directory)

    native_output_commit = subcommands.add_parser(
        "native-output-commit",
        help="commit staged native output after revalidating directory ownership",
    )
    native_output_commit.add_argument("--root", default=".", help="repository root")
    native_output_commit.add_argument(
        "--output", required=True, help="validated output directory"
    )
    native_output_commit.add_argument(
        "--default-output",
        required=True,
        help="default build-owned output directory for this profile",
    )
    native_output_commit.add_argument(
        "--staged-abi", required=True, help="staged arm64-v8a directory"
    )
    native_output_commit.add_argument(
        "--metadata-temporary", required=True, help="generated native metadata temporary"
    )
    native_output_commit.add_argument(
        "--metadata", required=True, help="final native metadata path"
    )
    native_output_commit.set_defaults(handler=command_native_output_commit)

    verify = subcommands.add_parser(
        "verify",
        help="independently inspect a qualification APK and write provenance",
    )
    verify.add_argument("--root", default=".", help="repository root")
    verify.add_argument("--apk", required=True, help="qualification APK path")
    verify.add_argument("--native-metadata", required=True, help="native build metadata path")
    verify.add_argument("--provenance-out", help="write sanitized provenance JSON here")
    verify.add_argument("--expected-revision", help="require the qualification source revision")
    verify.add_argument(
        "--expected-signer-sha256",
        help="expected signer digest; must match the configured debug keystore",
    )
    verify.add_argument("--debug-keystore", help="Android debug keystore path")
    verify.add_argument("--comparison-apk", help="optional ordinary Release candidate APK")
    verify.add_argument("--comparison-revision", help="selected ordinary Release source revision")
    verify.add_argument(
        "--prebuild-source-state",
        help="source snapshot captured before the qualification build",
    )
    verify.add_argument(
        "--allow-provisional",
        action="store_true",
        help="accept a dirty source tree as a provisional, non-admissible artifact",
    )
    verify.add_argument("--aapt2", help="aapt2 executable")
    verify.add_argument("--apksigner", help="apksigner executable")
    verify.add_argument("--zipalign", help="zipalign executable")
    verify.add_argument("--keytool", help="keytool executable")
    verify.set_defaults(handler=command_verify)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(list(argv) if argv is not None else None)
    return int(arguments.handler(arguments))


if __name__ == "__main__":
    raise SystemExit(main())
