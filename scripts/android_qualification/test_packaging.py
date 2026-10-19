"""Host-only tests for Android qualification artifact verification.

These tests build immutable fact objects directly so every rejection path can
run without an Android SDK, a device, or a packaged artifact. The separate
qualification build script exercises the same verifier against a real APK.
"""

from __future__ import annotations

import argparse
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

from scripts.android_qualification import packaging


ROOT = Path(__file__).resolve().parents[2]


def _qualification_shell_environment(
    root: Path, fvm_body: str
) -> tuple[Path, dict[str, str]]:
    """Create a disposable script tree with a stub ``fvm`` executable.

    The build script derives its repository root from its own location, so a
    temporary copy exercises the real script without touching the checkout or
    requiring Flutter. ``local.properties`` already exists to skip dependency
    resolution, and ``ANDROID_NDK_HOME`` is set to skip host NDK discovery.
    """
    scripts = root / "scripts"
    scripts.mkdir(parents=True)
    for name in ("build_android_qualification.sh", "android_sdk_common.sh"):
        shutil.copy2(ROOT / "scripts" / name, scripts / name)
    local_properties = root / "flutter" / "android" / "local.properties"
    local_properties.parent.mkdir(parents=True)
    local_properties.write_text("", encoding="utf-8")
    bin_directory = root / "bin"
    bin_directory.mkdir()
    fvm = bin_directory / "fvm"
    fvm.write_text(f"#!/bin/sh\n{fvm_body}\n", encoding="utf-8")
    fvm.chmod(0o755)
    environment = os.environ.copy()
    environment["PATH"] = (
        f"{bin_directory}{os.pathsep}{environment.get('PATH', '')}"
    )
    environment["ANDROID_NDK_HOME"] = str(root / "ndk")
    return scripts / "build_android_qualification.sh", environment
REVISION = "a" * 40
OTHER_REVISION = "b" * 40
FINGERPRINT = "c" * 64
BRIDGE_SHA256 = "1" * 64
KEYRING_SHA256 = "2" * 64
SEVENZ_SHA256 = "7" * 64
SIGNER_SHA256 = "3" * 64
QUALIFICATION_APK_SHA256 = "4" * 64
RELEASE_APK_SHA256 = "5" * 64


def _git(root: Path, *arguments: str) -> None:
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=Qualification Test",
            "-c",
            "user.email=qualification-test@example.invalid",
            *arguments,
        ],
        cwd=root,
        check=True,
        capture_output=True,
    )


def _elf(machine: int = packaging.ELF_MACHINE_AARCH64) -> packaging.ElfInfo:
    return packaging.ElfInfo(
        elf_class=2,
        little_endian=True,
        elf_type=packaging.ELF_TYPE_SHARED,
        machine=machine,
    )


def _elf_with_sections(names: tuple[str, ...]) -> bytes:
    """Build a minimal ELF64 little-endian object with named sections."""

    string_table = bytearray(b"\0")
    name_offsets: dict[str, int] = {}
    for name in names:
        name_offsets[name] = len(string_table)
        string_table += name.encode("ascii") + b"\0"
    shstr_index = 1
    shstr_name = len(string_table)
    string_table += b".shstrtab\0"
    section_offset = 64 + len(string_table)
    data = bytearray(64)
    data[0:4] = b"\x7fELF"
    data[4:7] = bytes((2, 1, 1))
    data[40:48] = section_offset.to_bytes(8, "little")
    data[58:60] = (64).to_bytes(2, "little")
    data[60:62] = (len(names) + 2).to_bytes(2, "little")
    data[62:64] = shstr_index.to_bytes(2, "little")
    data += string_table

    def header(name_offset: int, offset: int, size: int) -> bytes:
        section = bytearray(64)
        section[0:4] = name_offset.to_bytes(4, "little")
        section[4:8] = (1).to_bytes(4, "little")
        section[24:32] = offset.to_bytes(8, "little")
        section[32:40] = size.to_bytes(8, "little")
        return bytes(section)

    data += header(0, 0, 0)
    data += header(shstr_name, 64, len(string_table))
    for name in names:
        data += header(name_offsets[name], 0, 0)
    return bytes(data)


def _component(
    kind: str,
    name: str,
    *,
    exported: bool | None,
    permission: str | None = None,
    grant_uri_permissions: bool | None = None,
    foreground_service_type: int | None = None,
    authorities: tuple[str, ...] = (),
    actions: tuple[str, ...] = (),
    categories: tuple[str, ...] = (),
    meta_data_names: tuple[str, ...] = (),
) -> packaging.ComponentFacts:
    return packaging.ComponentFacts(
        kind=kind,
        name=name,
        exported=exported,
        permission=permission,
        grant_uri_permissions=grant_uri_permissions,
        foreground_service_type=foreground_service_type,
        authorities=authorities,
        intent_actions=actions,
        intent_categories=categories,
        meta_data_names=meta_data_names,
        meta_data_resources=(),
    )


def _valid_manifest() -> packaging.ManifestFacts:
    qualification_id = packaging.QUALIFICATION_APPLICATION_ID
    return packaging.ManifestFacts(
        application_name=packaging.EXPECTED_APPLICATION,
        debuggable=False,
        activities=(
            _component(
                "activity",
                packaging.EXPECTED_MAIN_ACTIVITY,
                exported=True,
                actions=("android.intent.action.MAIN",),
                categories=("android.intent.category.LAUNCHER",),
            ),
        ),
        services=(
            _component(
                "service",
                packaging.EXPECTED_FOREGROUND_SERVICE,
                exported=False,
                foreground_service_type=1,
            ),
        ),
        providers=(
            _component(
                "provider",
                packaging.EXPECTED_FILE_PROVIDER,
                exported=False,
                grant_uri_permissions=True,
                authorities=(qualification_id + ".diagnostics",),
                meta_data_names=("android.support.FILE_PROVIDER_PATHS",),
            ),
            _component(
                "provider",
                packaging.EXPECTED_STARTUP_PROVIDER,
                exported=False,
                authorities=(qualification_id + ".androidx-startup",),
            ),
        ),
        receivers=(
            _component(
                "receiver",
                packaging.EXPECTED_PROFILE_RECEIVER,
                exported=True,
                permission="android.permission.DUMP",
            ),
        ),
        permissions=packaging.QUALIFICATION_PERMISSIONS,
    )


def _valid_native(source: packaging.SourceState) -> packaging.NativeMetadata:
    return packaging.NativeMetadata(
        profile="release",
        command=(
            "cargo",
            "ndk",
            "-t",
            "arm64-v8a",
            "--manifest-path",
            "rust/Cargo.toml",
            "build",
            "--package",
            "argus-bridge",
            "--locked",
            "--release",
        ),
        features="default",
        rust_toolchain=packaging.read_rust_channel(ROOT),
        rustc_version=f"rustc {packaging.read_rust_channel(ROOT)} (test toolchain)",
        cargo_ndk_version=f"cargo-ndk {packaging.read_cargo_ndk_version(ROOT)}",
        cargo_ndk_platform="30",
        cargo_lock_sha256=packaging.sha256_file(ROOT / "rust/Cargo.lock"),
        source_revision=source.revision,
        source_dirty=source.dirty,
        source_fingerprint=source.fingerprint,
        libraries={
            packaging.BRIDGE_LIBRARY: packaging.DeclaredLibrary(BRIDGE_SHA256, 101),
            packaging.KEYRING_LIBRARY: packaging.DeclaredLibrary(KEYRING_SHA256, 202),
            "lib/arm64-v8a/libsevenz_rust2-test.so": packaging.DeclaredLibrary(
                SEVENZ_SHA256,
                303,
            ),
        },
        output_directory="flutter/build/native-jni/release",
    )


def _valid_native_json(source: packaging.SourceState) -> dict[str, object]:
    native = _valid_native(source)
    return {
        "schema_version": 1,
        "build_profile": native.profile,
        "cargo_command": list(native.command),
        "features": native.features,
        "rust_toolchain": native.rust_toolchain,
        "rustc_version": native.rustc_version,
        "cargo_ndk_version": native.cargo_ndk_version,
        "cargo_ndk_platform": native.cargo_ndk_platform,
        "cargo_lock_sha256": native.cargo_lock_sha256,
        "source_revision": native.source_revision,
        "source_dirty": native.source_dirty,
        "source_fingerprint": native.source_fingerprint,
        "output_directory": native.output_directory,
        "libraries": {
            name: {"sha256": facts.sha256, "size_bytes": facts.size_bytes}
            for name, facts in native.libraries.items()
        },
    }


def _valid_record(source: packaging.SourceState) -> dict[str, object]:
    version_name, version_code = packaging.read_pubspec_version(ROOT)
    return {
        "schema_version": packaging.SCHEMA_VERSION,
        "application_id": packaging.QUALIFICATION_APPLICATION_ID,
        "version_name": version_name,
        "version_code": version_code,
        "android_build_type": packaging.QUALIFICATION_BUILD_TYPE,
        "flutter_build_mode": packaging.FLUTTER_BUILD_MODE,
        "source": packaging.source_state_document(source),
        "prebuild_source": packaging.source_state_document(source),
        "pinned_build_inputs": {
            "flutter_version": packaging.read_flutter_version(ROOT),
            "android_gradle_plugin": packaging.read_android_gradle_plugin_version(ROOT),
            "rust_channel": packaging.read_rust_channel(ROOT),
            "native_profile": "release",
            "native_features": "default",
            "basis": "repository pins; Flutter version is not recoverable from the APK",
        },
    }


def _valid_source(*, dirty: bool = False) -> packaging.SourceState:
    return packaging.SourceState(
        revision=REVISION,
        dirty=dirty,
        fingerprint=FINGERPRINT,
        changed_path_count=3 if dirty else 0,
    )


def _valid_expected() -> packaging.ExpectedArtifact:
    version_name, version_code = packaging.read_pubspec_version(ROOT)
    return packaging.ExpectedArtifact(
        application_id=packaging.QUALIFICATION_APPLICATION_ID,
        version_code=version_code,
        version_name=version_name,
        signer_sha256=SIGNER_SHA256,
    )


def _valid_facts(
    source: packaging.SourceState | None = None,
) -> packaging.ApkFacts:
    source = source or _valid_source()
    version_name, version_code = packaging.read_pubspec_version(ROOT)
    return packaging.ApkFacts(
        path=Path("flutter/build/qualification/argus-qualification.apk"),
        sha256=QUALIFICATION_APK_SHA256,
        size_bytes=4096,
        entries=(
            packaging.BRIDGE_LIBRARY,
            packaging.KEYRING_LIBRARY,
            "lib/arm64-v8a/libsevenz_rust2-test.so",
            packaging.FLUTTER_APP_LIBRARY,
            packaging.FLUTTER_ENGINE_LIBRARY,
            "assets/qualification-build.json",
        ),
        badging=packaging.BadgingFacts(
            package_id=packaging.QUALIFICATION_APPLICATION_ID,
            version_code=version_code,
            version_name=version_name,
            min_sdk=packaging.MINIMUM_SDK,
            target_sdk=36,
            debuggable_line=False,
            launchable_activity=packaging.EXPECTED_MAIN_ACTIVITY,
            native_codes=("arm64-v8a",),
        ),
        manifest=_valid_manifest(),
        signatures=packaging.SignatureFacts(
            verified=True,
            schemes=("v2", "v3"),
            signer_count=1,
            certificate_sha256=SIGNER_SHA256,
        ),
        alignment_ok=True,
        flutter_release=packaging.FlutterReleaseFacts(
            libapp_present=True,
            libflutter_present=True,
            vmservice_snapshot_present=False,
            kernel_blob_present=False,
            isolate_snapshot_present=False,
            vm_snapshot_present=False,
        ),
        native_libraries={
            packaging.BRIDGE_LIBRARY: packaging.NativeLibraryFacts(
                path=packaging.BRIDGE_LIBRARY,
                sha256=BRIDGE_SHA256,
                size_bytes=101,
                elf=_elf(),
            ),
            packaging.KEYRING_LIBRARY: packaging.NativeLibraryFacts(
                path=packaging.KEYRING_LIBRARY,
                sha256=KEYRING_SHA256,
                size_bytes=202,
                elf=_elf(),
            ),
            "lib/arm64-v8a/libsevenz_rust2-test.so": packaging.NativeLibraryFacts(
                path="lib/arm64-v8a/libsevenz_rust2-test.so",
                sha256=SEVENZ_SHA256,
                size_bytes=303,
                elf=_elf(),
            ),
        },
        build_record=_valid_record(source),
        apk_metadata={
            "appMetadataVersion": "1.1",
            "androidGradlePluginVersion": packaging.read_android_gradle_plugin_version(
                ROOT
            ),
        },
        provider_paths=(("files-path", "diagnostics", "argus/diagnostics/"),),
        provider_paths_resource="xml/argus_file_paths",
    )


def _valid_comparison(facts: packaging.ApkFacts) -> packaging.ComparisonFacts:
    return packaging.ComparisonFacts(
        path=Path("flutter/build/app/outputs/flutter-apk/app-release.apk"),
        sha256=RELEASE_APK_SHA256,
        size_bytes=8192,
        package_id=packaging.ORDINARY_APPLICATION_ID,
        version_code=facts.badging.version_code,
        version_name=facts.badging.version_name,
        debuggable=False,
        signatures=packaging.SignatureFacts(
            verified=True,
            schemes=("v2", "v3"),
            signer_count=1,
            certificate_sha256="6" * 64,
        ),
        flutter_release=replace(facts.flutter_release),
        native_libraries=dict(facts.native_libraries),
        revision=REVISION,
    )


class ArtifactValidationTests(unittest.TestCase):
    def assertRejected(self, facts: packaging.ApkFacts, expected_message: str) -> None:
        errors = packaging.validate_artifact(
            facts,
            _valid_expected(),
            _valid_native(_valid_source()),
            _valid_source(),
            ROOT,
        )
        self.assertTrue(errors)
        self.assertTrue(
            any(expected_message in error for error in errors),
            msg=f"expected {expected_message!r} in {errors!r}",
        )

    def test_valid_artifact_has_no_errors(self) -> None:
        self.assertEqual(
            packaging.validate_artifact(
                _valid_facts(),
                _valid_expected(),
                _valid_native(_valid_source()),
                _valid_source(),
                ROOT,
            ),
            [],
        )

    def test_omitted_debuggable_attribute_is_effectively_false(self) -> None:
        facts = replace(
            _valid_facts(),
            manifest=replace(_valid_manifest(), debuggable=None),
        )
        self.assertEqual(
            packaging.validate_artifact(
                facts,
                _valid_expected(),
                _valid_native(_valid_source()),
                _valid_source(),
                ROOT,
            ),
            [],
        )

    def test_rejects_wrong_identity_version_and_signer(self) -> None:
        facts = replace(
            _valid_facts(),
            badging=replace(
                _valid_facts().badging,
                package_id=packaging.ORDINARY_APPLICATION_ID,
                version_code=999,
                version_name="9.9.9",
            ),
            signatures=replace(
                _valid_facts().signatures,
                certificate_sha256="0" * 64,
            ),
        )
        errors = packaging.validate_artifact(
            facts,
            _valid_expected(),
            _valid_native(_valid_source()),
            _valid_source(),
            ROOT,
        )
        for expected in (
            "application ID mismatch",
            "versionCode mismatch",
            "versionName mismatch",
            "signer certificate fingerprint mismatch",
        ):
            self.assertIn(expected, "\n".join(errors))

    def test_rejects_effectively_debuggable_artifacts(self) -> None:
        self.assertRejected(
            replace(
                _valid_facts(),
                badging=replace(_valid_facts().badging, debuggable_line=True),
            ),
            "badging reports a debuggable application",
        )
        self.assertRejected(
            replace(
                _valid_facts(),
                manifest=replace(_valid_manifest(), debuggable=True),
            ),
            "merged manifest is effectively debuggable",
        )

    def test_rejects_wrong_activity_service_provider_and_exported_flags(self) -> None:
        manifest = _valid_manifest()
        wrong_activity = replace(
            manifest.activities[0],
            exported=False,
            intent_actions=(),
            intent_categories=(),
        )
        self.assertRejected(
            replace(
                _valid_facts(),
                manifest=replace(manifest, activities=(wrong_activity,)),
            ),
            "launch Activity",
        )
        wrong_service = replace(manifest.services[0], exported=True)
        self.assertRejected(
            replace(
                _valid_facts(),
                manifest=replace(manifest, services=(wrong_service,)),
            ),
            "foreground Service is exported",
        )
        wrong_provider = replace(
            manifest.providers[0],
            authorities=(packaging.ORDINARY_APPLICATION_ID + ".diagnostics",),
            exported=True,
        )
        providers = (wrong_provider, manifest.providers[1])
        self.assertRejected(
            replace(
                _valid_facts(),
                manifest=replace(manifest, providers=providers),
            ),
            "FileProvider authority mismatch",
        )

    def test_rejects_extra_packaged_permission(self) -> None:
        manifest = _valid_manifest()
        permissions = frozenset(
            set(manifest.permissions) | {"android.permission.INTERNET"}
        )
        self.assertRejected(
            replace(
                _valid_facts(),
                manifest=replace(manifest, permissions=permissions),
            ),
            "packaged Android permission inventory mismatch",
        )

    def test_rejects_file_provider_without_uri_grants(self) -> None:
        manifest = _valid_manifest()
        for value in (False, None):
            with self.subTest(grant_uri_permissions=value):
                provider = replace(
                    manifest.providers[0], grant_uri_permissions=value
                )
                self.assertRejected(
                    replace(
                        _valid_facts(),
                        manifest=replace(
                            manifest,
                            providers=(provider, manifest.providers[1]),
                        ),
                    ),
                    "FileProvider does not grant URI permissions",
                )

    def test_rejects_wrong_file_provider_path_mapping(self) -> None:
        variants = {
            "wrong name": ("files-path", "shared", "argus/diagnostics/"),
            "missing name": ("files-path", "", "argus/diagnostics/"),
            "wrong path": ("files-path", "diagnostics", "argus/other/"),
        }
        for label, mapping in variants.items():
            with self.subTest(label=label):
                self.assertRejected(
                    replace(_valid_facts(), provider_paths=(mapping,)),
                    "FileProvider paths do not expose the diagnostics directory",
                )

    def test_rejects_rust_workspace_version_mismatch(self) -> None:
        facts = _valid_facts()
        self.assertRejected(
            replace(
                facts,
                badging=replace(facts.badging, version_name="9.9.9"),
            ),
            "Rust workspace version does not match qualification versionName",
        )

    def test_rejects_native_library_debug_sections(self) -> None:
        facts = _valid_facts()
        bridge = replace(
            facts.native_libraries[packaging.BRIDGE_LIBRARY],
            debug_sections=(".debug_info", ".debug_line"),
        )
        self.assertRejected(
            replace(
                facts,
                native_libraries={
                    **facts.native_libraries,
                    packaging.BRIDGE_LIBRARY: bridge,
                },
            ),
            "native library contains unexpected ELF debug sections",
        )

    def test_rejects_missing_embedded_source_dirty_state(self) -> None:
        facts = _valid_facts()
        record = json.loads(json.dumps(facts.build_record))
        del record["source"]["dirty"]
        self.assertRejected(
            replace(facts, build_record=record),
            "embedded build record source dirty-state mismatch",
        )

    def test_rejects_missing_abi_and_wrong_elf_architecture(self) -> None:
        facts = _valid_facts()
        missing = dict(facts.native_libraries)
        del missing[packaging.BRIDGE_LIBRARY]
        self.assertRejected(
            replace(facts, native_libraries=missing),
            "missing native library",
        )

        x86 = packaging.NativeLibraryFacts(
            path="lib/x86_64/libargus_bridge.so",
            sha256=BRIDGE_SHA256,
            size_bytes=101,
            elf=_elf(62),
        )
        self.assertRejected(
            replace(
                facts,
                entries=(*facts.entries, x86.path),
                native_libraries={**facts.native_libraries, x86.path: x86},
            ),
            "unexpected native ABI packaging",
        )

        wrong_machine = packaging.NativeLibraryFacts(
            path=packaging.KEYRING_LIBRARY,
            sha256=KEYRING_SHA256,
            size_bytes=202,
            elf=_elf(62),
        )
        self.assertRejected(
            replace(
                facts,
                native_libraries={
                    packaging.BRIDGE_LIBRARY: facts.native_libraries[
                        packaging.BRIDGE_LIBRARY
                    ],
                    packaging.KEYRING_LIBRARY: wrong_machine,
                },
            ),
            "ELF machine is not AArch64",
        )

    def test_rejects_native_profile_features_hash_and_source_provenance(self) -> None:
        source = _valid_source()
        native = _valid_native(source)
        facts = _valid_facts(source)
        scenarios = (
            (replace(native, profile="debug"), "native build profile is not release"),
            (
                replace(native, command=tuple(arg for arg in native.command if arg != "--release")),
                "Cargo command did not request the release profile",
            ),
            (replace(native, features="qualification"), "production-default features"),
            (replace(native, rust_toolchain="unexpected"), "different Rust toolchain"),
            (replace(native, rustc_version="rustc unexpected"), "rustc version"),
            (replace(native, cargo_ndk_version="cargo-ndk 0.0.0"), "cargo-ndk version"),
            (replace(native, cargo_ndk_platform="29"), "Android API 30"),
            (replace(native, cargo_lock_sha256="0" * 64), "lockfile digest mismatch"),
            (replace(native, source_revision=OTHER_REVISION), "source revision mismatch"),
            (replace(native, source_dirty=True), "dirty state mismatch"),
            (replace(native, source_fingerprint="0" * 64), "source fingerprint mismatch"),
            (replace(native, output_directory="/private/build"), "not sanitized"),
            (
                replace(native, command=(*native.command, "/private/tool")),
                "host absolute path",
            ),
        )
        for changed_native, expected in scenarios:
            with self.subTest(expected=expected):
                errors = packaging.validate_artifact(
                    facts,
                    _valid_expected(),
                    changed_native,
                    source,
                    ROOT,
                )
                self.assertIn(expected, "\n".join(errors))

        bad_hashes = dict(native.libraries)
        bad_hashes[packaging.BRIDGE_LIBRARY] = packaging.DeclaredLibrary(
            "0" * 64,
            101,
        )
        errors = packaging.validate_artifact(
            facts,
            _valid_expected(),
            replace(native, libraries=bad_hashes),
            source,
            ROOT,
        )
        self.assertTrue(any("native library hash mismatch" in error for error in errors))

        missing_declaration = dict(native.libraries)
        del missing_declaration[packaging.KEYRING_LIBRARY]
        errors = packaging.validate_artifact(
            facts,
            _valid_expected(),
            replace(native, libraries=missing_declaration),
            source,
            ROOT,
        )
        self.assertTrue(
            any("native build metadata is missing" in error for error in errors)
        )

    def test_rejects_debug_profile_and_build_record_source_mismatch(self) -> None:
        facts = _valid_facts()
        debug_payload = replace(
            facts.flutter_release,
            libapp_present=False,
            kernel_blob_present=True,
            isolate_snapshot_present=True,
        )
        self.assertRejected(
            replace(facts, flutter_release=debug_payload),
            "Flutter Release AOT payload",
        )

        profile_record = dict(facts.build_record)
        profile_record["flutter_build_mode"] = "profile"
        self.assertRejected(
            replace(facts, build_record=profile_record),
            "embedded build record Flutter mode mismatch",
        )

        stale_record = json.loads(json.dumps(facts.build_record))
        stale_record["source"]["revision"] = OTHER_REVISION
        stale_record["source"]["fingerprint"] = "0" * 64
        self.assertRejected(
            replace(facts, build_record=stale_record),
            "embedded build record source",
        )

    def test_rejects_non_release_payload_and_invalid_signature(self) -> None:
        self.assertRejected(
            replace(
                _valid_facts(),
                signatures=replace(
                    _valid_facts().signatures,
                    verified=False,
                    signer_count=2,
                ),
            ),
            "APK signature is not valid",
        )
        self.assertRejected(
            replace(
                _valid_facts(),
                flutter_release=replace(
                    _valid_facts().flutter_release,
                    vm_snapshot_present=True,
                ),
            ),
            "Flutter Release AOT payload",
        )

    def test_rejects_profile_vm_service_snapshot_payload(self) -> None:
        facts = _valid_facts()
        profile = packaging.NativeLibraryFacts(
            path=packaging.FLUTTER_VMSERVICE_LIBRARY,
            sha256="8" * 64,
            size_bytes=404,
            elf=_elf(),
        )
        self.assertRejected(
            replace(
                facts,
                entries=(*facts.entries, packaging.FLUTTER_VMSERVICE_LIBRARY),
                flutter_release=replace(
                    facts.flutter_release,
                    vmservice_snapshot_present=True,
                ),
                native_libraries={**facts.native_libraries, profile.path: profile},
            ),
            "Flutter Release AOT payload",
        )

    def test_rejects_extra_stale_native_library(self) -> None:
        facts = _valid_facts()
        stale_path = "lib/arm64-v8a/libsevenz_rust2-c212e587417b8188.so"
        stale = packaging.NativeLibraryFacts(
            path=stale_path,
            sha256="9" * 64,
            size_bytes=505,
            elf=_elf(),
        )
        self.assertRejected(
            replace(
                facts,
                entries=(*facts.entries, stale_path),
                native_libraries={**facts.native_libraries, stale_path: stale},
            ),
            "packaged native library is not declared",
        )

    def test_rejects_wrong_elf_class_and_endianness(self) -> None:
        facts = _valid_facts()
        for elf, expected in (
            (
                replace(
                    facts.native_libraries[packaging.BRIDGE_LIBRARY].elf,
                    elf_class=1,
                ),
                "is not ELF64",
            ),
            (
                replace(
                    facts.native_libraries[packaging.BRIDGE_LIBRARY].elf,
                    little_endian=False,
                ),
                "is not little-endian",
            ),
        ):
            with self.subTest(expected=expected):
                library = replace(
                    facts.native_libraries[packaging.BRIDGE_LIBRARY],
                    elf=elf,
                )
                self.assertRejected(
                    replace(
                        facts,
                        native_libraries={
                            **facts.native_libraries,
                            packaging.BRIDGE_LIBRARY: library,
                        },
                    ),
                    expected,
                )

    def test_rejects_duplicate_provider_authority(self) -> None:
        manifest = _valid_manifest()
        duplicate = replace(
            manifest.providers[1],
            authorities=(
                packaging.QUALIFICATION_APPLICATION_ID + ".diagnostics",
                packaging.QUALIFICATION_APPLICATION_ID + ".androidx-startup",
            ),
        )
        self.assertRejected(
            replace(
                _valid_facts(),
                manifest=replace(
                    manifest,
                    providers=(manifest.providers[0], duplicate),
                ),
            ),
            "provider authorities are not unique",
        )

    def test_rejects_apk_metadata_and_prebuild_source_mismatch(self) -> None:
        facts = _valid_facts()
        self.assertRejected(
            replace(
                facts,
                apk_metadata={
                    **facts.apk_metadata,
                    "androidGradlePluginVersion": "0.0.0",
                },
            ),
            "APK build metadata Android Gradle Plugin version mismatch",
        )
        errors = packaging.validate_artifact(
            facts,
            _valid_expected(),
            _valid_native(_valid_source()),
            _valid_source(),
            ROOT,
            prebuild_source=replace(_valid_source(), fingerprint="0" * 64),
        )
        self.assertIn("pre-build snapshot", "\n".join(errors))


class SourceEligibilityTests(unittest.TestCase):
    def test_clean_source_is_eligible_final_artifact(self) -> None:
        facts = _valid_facts()
        errors, provisional = packaging._source_eligibility(
            facts,
            _valid_source(),
            allow_provisional=False,
            expected_revision=REVISION,
        )
        self.assertEqual(errors, [])
        self.assertFalse(provisional)

    def test_dirty_source_requires_provisional_opt_in(self) -> None:
        source = _valid_source(dirty=True)
        facts = _valid_facts(source)
        errors, provisional = packaging._source_eligibility(
            facts,
            source,
            allow_provisional=False,
            expected_revision=REVISION,
        )
        self.assertTrue(provisional)
        self.assertTrue(any("source tree is dirty" in error for error in errors))

        errors, provisional = packaging._source_eligibility(
            facts,
            source,
            allow_provisional=True,
            expected_revision=REVISION,
        )
        self.assertTrue(provisional)
        self.assertEqual(errors, [])

    def test_missing_record_dirty_state_is_provisional(self) -> None:
        facts = _valid_facts()
        record = json.loads(json.dumps(facts.build_record))
        del record["source"]["dirty"]
        errors, provisional = packaging._source_eligibility(
            replace(facts, build_record=record),
            _valid_source(),
            allow_provisional=True,
            expected_revision=REVISION,
        )
        self.assertTrue(provisional)
        self.assertTrue(
            any("no valid source dirty state" in error for error in errors)
        )

    def test_wrong_expected_revision_is_never_eligible(self) -> None:
        errors, _ = packaging._source_eligibility(
            _valid_facts(),
            _valid_source(),
            allow_provisional=True,
            expected_revision=OTHER_REVISION,
        )
        self.assertTrue(any("selected source revision" in error for error in errors))

    def test_source_fingerprint_changes_with_dirty_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _git(root, "init", "--quiet")
            tracked = root / "tracked.txt"
            tracked.write_text("first\n", encoding="utf-8")
            _git(root, "add", "tracked.txt")
            _git(root, "commit", "--quiet", "-m", "initial")

            clean = packaging.compute_source_state(root)
            self.assertFalse(clean.dirty)
            self.assertEqual(clean.changed_path_count, 0)
            self.assertEqual(len(clean.revision), 40)

            tracked.write_text("second\n", encoding="utf-8")
            changed = packaging.compute_source_state(root)
            self.assertTrue(changed.dirty)
            self.assertEqual(changed.revision, clean.revision)
            self.assertNotEqual(changed.fingerprint, clean.fingerprint)
            self.assertEqual(changed.changed_path_count, 1)

            _git(root, "config", "core.abbrev", "7")
            abbreviated_config = packaging.compute_source_state(root)
            self.assertEqual(abbreviated_config.fingerprint, changed.fingerprint)

            # The source identity describes bytes, not index placement. Staging
            # the same content must not invalidate a build captured earlier in
            # the invocation.
            _git(root, "add", "tracked.txt")
            staged = packaging.compute_source_state(root)
            self.assertTrue(staged.dirty)
            self.assertEqual(staged.fingerprint, changed.fingerprint)
            self.assertEqual(staged.changed_path_count, 1)

            untracked = root / "new.txt"
            untracked.write_text("new\n", encoding="utf-8")
            with_untracked = packaging.compute_source_state(root)
            self.assertNotEqual(with_untracked.fingerprint, changed.fingerprint)
            self.assertEqual(with_untracked.changed_path_count, 2)

            untracked.chmod(0o755)
            with_mode_change = packaging.compute_source_state(root)
            self.assertNotEqual(with_mode_change.fingerprint, with_untracked.fingerprint)
            self.assertEqual(with_mode_change.changed_path_count, 2)

    def test_qualification_shell_configures_before_source_snapshot(self) -> None:
        script = (ROOT / "scripts/build_android_qualification.sh").read_text(
            encoding="utf-8"
        )
        config_only = script.index(
            "fvm flutter build apk --release --config-only "
            "--target-platform android-arm64"
        )
        source_snapshot = script.index("packaging source-state")
        gradle_package = script.index("./gradlew :app:packageQualification")

        self.assertLess(config_only, source_snapshot)
        self.assertLess(source_snapshot, gradle_package)
        self.assertIn(
            "Flutter Android configuration could not be initialized", script
        )
        self.assertNotIn("build-android-debug", script)

    def test_qualification_shell_captures_apk_baseline_before_config_only(
        self,
    ) -> None:
        script = (ROOT / "scripts/build_android_qualification.sh").read_text(
            encoding="utf-8"
        )
        config_only = script.index(
            "fvm flutter build apk --release --config-only "
            "--target-platform android-arm64"
        )
        release_baseline = script.index(
            'release_before="$(sha256_file "$RELEASE_APK")"'
        )
        debug_baseline = script.index(
            'debug_before="$(sha256_file "$DEBUG_APK")"'
        )
        release_checkpoint = script.index(
            'release_after_config="$(sha256_file "$RELEASE_APK")"'
        )
        debug_checkpoint = script.index(
            'debug_after_config="$(sha256_file "$DEBUG_APK")"'
        )

        self.assertLess(release_baseline, config_only)
        self.assertLess(debug_baseline, config_only)
        self.assertLess(config_only, release_checkpoint)
        self.assertLess(config_only, debug_checkpoint)

    def test_qualification_shell_fails_closed_when_config_only_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script, environment = _qualification_shell_environment(
                root, "exit 42"
            )
            result = subprocess.run(
                ["bash", str(script)],
                cwd=root,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(
                "Flutter Android configuration could not be initialized",
                result.stderr,
            )

    def test_qualification_shell_fails_when_config_only_mutates_apk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            release_apk = (
                root
                / "flutter"
                / "build"
                / "app"
                / "outputs"
                / "flutter-apk"
                / "app-release.apk"
            )
            release_apk.parent.mkdir(parents=True)
            release_apk.write_bytes(b"preserved release bytes")
            script, environment = _qualification_shell_environment(
                root,
                'printf "mutated" >> "$QUALIFICATION_TEST_APK"',
            )
            environment["QUALIFICATION_TEST_APK"] = str(release_apk)
            result = subprocess.run(
                ["bash", str(script)],
                cwd=root,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn(
                "Flutter configuration-only changed the existing "
                "distributable Release APK",
                result.stderr,
            )

    def test_kotlin_session_state_is_ignored_but_source_changes_are_not(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _git(root, "init", "--quiet")
            flutter = root / "flutter"
            android = flutter / "android"
            android.mkdir(parents=True)
            (flutter / ".gitignore").write_bytes(
                (ROOT / "flutter/.gitignore").read_bytes()
            )
            tracked = android / "Tracked.kt"
            tracked.write_text("class Tracked\n", encoding="utf-8")
            _git(root, "add", ".")
            _git(root, "commit", "--quiet", "-m", "initial")

            clean = packaging.compute_source_state(root)
            session = android / ".kotlin/sessions/build-daemon.salive"
            session.parent.mkdir(parents=True)
            session.write_text("session\n", encoding="utf-8")
            ignored = subprocess.run(
                ["git", "check-ignore", "-v", str(session.relative_to(root))],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("/android/.kotlin/", ignored.stdout)
            self.assertEqual(packaging.compute_source_state(root), clean)

            tracked.write_text("class TrackedChanged\n", encoding="utf-8")
            changed = packaging.compute_source_state(root)
            self.assertNotEqual(changed.fingerprint, clean.fingerprint)
            self.assertEqual(changed.changed_path_count, 1)

            untracked = android / "NewSource.kt"
            untracked.write_text("class NewSource\n", encoding="utf-8")
            with_untracked = packaging.compute_source_state(root)
            self.assertNotEqual(with_untracked.fingerprint, changed.fingerprint)
            self.assertEqual(with_untracked.changed_path_count, 2)


class ComparisonValidationTests(unittest.TestCase):
    def test_comparison_records_source_parity_without_binary_parity(self) -> None:
        facts = _valid_facts()
        comparison = _valid_comparison(facts)
        self.assertEqual(
            packaging.validate_comparison(facts, comparison, _valid_expected()),
            [],
        )
        self.assertNotEqual(comparison.sha256, facts.sha256)

    def test_rejects_wrong_comparison_identity_version_and_native_bytes(self) -> None:
        facts = _valid_facts()
        comparison = _valid_comparison(facts)
        scenarios = (
            (replace(comparison, package_id="wrong.package"), "package identity mismatch"),
            (replace(comparison, version_code=999), "versionCode mismatch"),
            (replace(comparison, version_name="wrong"), "versionName mismatch"),
            (replace(comparison, sha256=facts.sha256), "comparison APK is the qualification APK"),
            (
                replace(
                    comparison,
                    native_libraries={
                        **comparison.native_libraries,
                        packaging.BRIDGE_LIBRARY: replace(
                            comparison.native_libraries[packaging.BRIDGE_LIBRARY],
                            sha256="0" * 64,
                        ),
                    },
                ),
                "release-profile native library differs",
            ),
        )
        for changed, expected in scenarios:
            with self.subTest(expected=expected):
                errors = packaging.validate_comparison(facts, changed, _valid_expected())
                self.assertTrue(any(expected in error for error in errors))

    def test_rejects_debuggable_profile_and_incomplete_comparison_payloads(self) -> None:
        facts = _valid_facts()
        comparison = _valid_comparison(facts)
        scenarios = (
            (replace(comparison, debuggable=True), "comparison APK is debuggable"),
            (
                replace(
                    comparison,
                    flutter_release=replace(
                        comparison.flutter_release,
                        vmservice_snapshot_present=True,
                    ),
                ),
                "Flutter Release AOT payload",
            ),
            (
                replace(
                    comparison,
                    flutter_release=replace(
                        comparison.flutter_release,
                        libapp_present=False,
                    ),
                ),
                "Flutter Release AOT payload",
            ),
            (
                replace(
                    comparison,
                    native_libraries={
                        name: library
                        for name, library in comparison.native_libraries.items()
                        if name != packaging.KEYRING_LIBRARY
                    },
                ),
                "comparison APK is missing native library",
            ),
            (
                replace(
                    comparison,
                    native_libraries={
                        **comparison.native_libraries,
                        packaging.BRIDGE_LIBRARY: replace(
                            comparison.native_libraries[packaging.BRIDGE_LIBRARY],
                            size_bytes=999,
                        ),
                    },
                ),
                "native library size differs",
            ),
        )
        for changed, expected in scenarios:
            with self.subTest(expected=expected):
                errors = packaging.validate_comparison(facts, changed, _valid_expected())
                self.assertTrue(any(expected in error for error in errors), msg=errors)


class ProvenanceTests(unittest.TestCase):
    def test_separates_apk_facts_from_build_declarations(self) -> None:
        facts = _valid_facts()
        document = packaging.provenance_document(
            facts,
            _valid_native(_valid_source()),
            _valid_source(),
            _valid_expected(),
            _valid_comparison(facts),
            "PROVISIONAL_ARTIFACT",
            ROOT,
        )

        verified_native = document["verified"]["native"]
        self.assertNotIn("cargo_profile", verified_native)
        self.assertNotIn("cargo_command", verified_native)
        declared_native = document["declared"]["native_build_metadata"]
        self.assertEqual(declared_native["build_profile"], "release")
        self.assertIn("--release", declared_native["cargo_command"])
        self.assertEqual(
            declared_native["source_fingerprint"],
            FINGERPRINT,
        )

        flutter = document["verified"]["flutter_release"]
        self.assertFalse(flutter["vmservice_snapshot_present"])
        self.assertTrue(document["verified"]["execution_mode"]["flutter_release_payload"])
        self.assertEqual(
            document["verified"]["apk_build_metadata"]["android_gradle_plugin_version"],
            packaging.read_android_gradle_plugin_version(ROOT),
        )
        components = document["verified"]["manifest"]["components"]
        self.assertTrue(
            any(
                component["kind"] == "receiver"
                and component["name"] == packaging.EXPECTED_PROFILE_RECEIVER
                and component["exported"] is True
                for component in components
            )
        )
        self.assertEqual(
            document["comparison"]["verified"]["native_inventory_identical"],
            True,
        )
        self.assertEqual(
            document["comparison"]["declared"]["source_revision"],
            REVISION,
        )


class InputParsingTests(unittest.TestCase):
    def test_parses_badging_and_detects_debuggable_line(self) -> None:
        text = "\n".join(
            (
                "package: name='com.argusromtoolkit.argus.qualification' "
                "versionCode='7' versionName='0.1.0'",
                "minSdkVersion:'30'",
                "targetSdkVersion:'36'",
                "application-debuggable",
                "native-code: 'arm64-v8a'",
                "launchable-activity: name='com.argusromtoolkit.argus.MainActivity' "
                "label='' icon=''",
            )
        )
        facts = packaging.parse_badging(text)
        self.assertEqual(facts.version_code, 7)
        self.assertTrue(facts.debuggable_line)
        self.assertEqual(facts.native_codes, ("arm64-v8a",))

    def test_manifest_collects_every_permission_element(self) -> None:
        text = "\n".join(
            (
                "E: manifest (line=2)",
                "  E: uses-permission (line=3)",
                '    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.permission.INTERNET"',
                "  E: uses-permission-sdk-23 (line=4)",
                '    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.permission.CAMERA"',
                "  E: uses-permission-sdk-m (line=5)",
                '    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.permission.RECORD_AUDIO"',
                "  E: uses-permission-sdk-28 (line=6)",
                '    A: http://schemas.android.com/apk/res/android:name(0x01010003)="android.permission.READ_CONTACTS"',
                "  E: application (line=6)",
            )
        )
        facts = packaging.manifest_facts(packaging.parse_xmltree(text))
        self.assertEqual(
            facts.permissions,
            frozenset(
                {
                    "android.permission.INTERNET",
                    "android.permission.CAMERA",
                    "android.permission.RECORD_AUDIO",
                    "android.permission.READ_CONTACTS",
                }
            ),
        )

    def test_signature_parser_requires_verified_output(self) -> None:
        verified = "\n".join(
            (
                "Verifies",
                "Verified using v2 scheme (APK Signature Scheme v2): true",
                "Number of signers: 1",
                "Signer #1 certificate SHA-256 digest: " + ":".join(["AB"] * 32),
            )
        )
        facts = packaging.parse_apksigner_output(verified)
        self.assertTrue(facts.verified)
        self.assertEqual(facts.certificate_sha256, "ab" * 32)
        with self.assertRaises(packaging.VerificationError):
            packaging.parse_apksigner_output("DOES NOT VERIFY")

    def test_native_metadata_rejects_malformed_shapes(self) -> None:
        valid = _valid_native_json(_valid_source())
        invalid_values: list[object] = [
            [],
            {"build_profile": "release"},
            {**valid, "cargo_command": "not-an-array"},
            {**valid, "schema_version": 2},
            {**valid, "source_dirty": "false"},
            {**valid, "cargo_lock_sha256": "not-a-digest"},
            {
                **valid,
                "libraries": {
                    "lib/arm64-v8a/example.so": {
                        "sha256": "0" * 64,
                        "size_bytes": "12",
                    }
                },
            },
        ]
        for value in invalid_values:
            with self.subTest(value=value):
                with self.assertRaises(packaging.VerificationError):
                    packaging.parse_native_metadata(value)

    def test_malformed_and_duplicate_zip_artifacts_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            malformed = Path(directory) / "malformed.apk"
            malformed.write_bytes(b"not an apk")
            with self.assertRaises(packaging.VerificationError):
                packaging._zip_entries(malformed)

            duplicate = Path(directory) / "duplicate.apk"
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(duplicate, "w") as archive:
                    archive.writestr("entry.txt", "first")
                    archive.writestr("entry.txt", "second")
            with self.assertRaisesRegex(packaging.VerificationError, "duplicate"):
                packaging._zip_entries(duplicate)

            oversized_member = Path(directory) / "oversized-member.apk"
            with zipfile.ZipFile(oversized_member, "w") as archive:
                archive.writestr("large.bin", b"x" * 64)
            with mock.patch.object(
                packaging, "APK_MAX_MEMBER_UNCOMPRESSED_BYTES", 32
            ):
                with self.assertRaisesRegex(
                    packaging.VerificationError, "entry exceeds"
                ):
                    packaging._zip_entries(oversized_member)
                with self.assertRaisesRegex(
                    packaging.VerificationError, "entry exceeds"
                ):
                    packaging._read_zip_entry(oversized_member, "large.bin")

            oversized_total = Path(directory) / "oversized-total.apk"
            with zipfile.ZipFile(oversized_total, "w") as archive:
                archive.writestr("first.bin", b"a" * 20)
                archive.writestr("second.bin", b"b" * 20)
            with mock.patch.object(
                packaging, "APK_MAX_TOTAL_UNCOMPRESSED_BYTES", 32
            ):
                with self.assertRaisesRegex(
                    packaging.VerificationError, "total decompressed-size limit"
                ):
                    packaging._zip_entries(oversized_total)

    def test_native_metadata_file_must_be_readable_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "native-build.json"
            path.write_text("{", encoding="utf-8")
            with self.assertRaises(packaging.VerificationError):
                packaging.read_native_metadata(path)

    def test_source_state_round_trip_rejects_malformed_documents(self) -> None:
        source = _valid_source(dirty=True)
        self.assertEqual(
            packaging.parse_source_state(
                packaging.source_state_document(source),
                "test source",
            ),
            source,
        )
        for value in (
            [],
            {
                **packaging.source_state_document(source),
                "revision": "short",
            },
            {
                **packaging.source_state_document(source),
                "fingerprint_algorithm": "md5",
            },
            {
                **packaging.source_state_document(source),
                "fingerprint": "0" * 63,
            },
        ):
            with self.subTest(value=value):
                with self.assertRaises(packaging.VerificationError):
                    packaging.parse_source_state(value, "test source")

    def test_parses_elf64_little_endian_header(self) -> None:
        data = b"\x7fELF" + bytes((2, 1, 1, 0)) + b"\0" * 8
        data += (packaging.ELF_TYPE_SHARED).to_bytes(2, "little")
        data += (packaging.ELF_MACHINE_AARCH64).to_bytes(2, "little")
        parsed = packaging.parse_elf_header(data)
        self.assertEqual(parsed.elf_class, 2)
        self.assertTrue(parsed.little_endian)
        self.assertEqual(parsed.elf_type, packaging.ELF_TYPE_SHARED)
        self.assertEqual(parsed.machine, packaging.ELF_MACHINE_AARCH64)

    def test_detects_unexpected_elf_debug_sections(self) -> None:
        data = _elf_with_sections(
            (
                ".debug_info",
                ".text",
                ".debug_line",
                ".debug_str",
                ".debug_abbrev",
                ".zdebug_info",
            )
        )
        self.assertEqual(
            packaging.parse_elf_debug_sections(data),
            (
                ".debug_info",
                ".debug_line",
                ".debug_str",
                ".debug_abbrev",
                ".zdebug_info",
            ),
        )

    def test_elf_debug_section_parser_rejects_truncated_table(self) -> None:
        data = bytearray(_elf_with_sections((".debug_info",)))
        data[40:48] = (len(data) + 8).to_bytes(8, "little")
        self.assertRaisesRegex(
            packaging.VerificationError,
            "truncated ELF section table",
            packaging.parse_elf_debug_sections,
            bytes(data),
        )

    def test_detects_debug_sections_with_extended_elf_numbering(self) -> None:
        data = bytearray(_elf_with_sections((".debug_info", ".debug_str")))
        section_offset = int.from_bytes(data[40:48], "little")
        section_count = int.from_bytes(data[60:62], "little")
        data[60:62] = (0).to_bytes(2, "little")
        data[62:64] = (0xFFFF).to_bytes(2, "little")
        data[section_offset + 32 : section_offset + 40] = section_count.to_bytes(
            8, "little"
        )
        data[section_offset + 40 : section_offset + 44] = (1).to_bytes(4, "little")
        self.assertEqual(
            packaging.parse_elf_debug_sections(bytes(data)),
            (".debug_info", ".debug_str"),
        )

    def test_elf_debug_parser_rejects_malformed_section_metadata(self) -> None:
        data = bytearray(_elf_with_sections((".debug_info",)))
        section_offset = int.from_bytes(data[40:48], "little")

        without_names = bytearray(data)
        without_names[62:64] = (0).to_bytes(2, "little")
        self.assertRaisesRegex(
            packaging.VerificationError,
            "no ELF section-name table",
            packaging.parse_elf_debug_sections,
            bytes(without_names),
        )

        bad_name = bytearray(data)
        bad_name[section_offset + 128 : section_offset + 132] = (
            0xFFFF
        ).to_bytes(4, "little")
        self.assertRaisesRegex(
            packaging.VerificationError,
            "malformed ELF section name",
            packaging.parse_elf_debug_sections,
            bytes(bad_name),
        )

        zero_count = bytearray(data)
        zero_count[60:62] = (0).to_bytes(2, "little")
        self.assertRaisesRegex(
            packaging.VerificationError,
            "malformed ELF section count",
            packaging.parse_elf_debug_sections,
            bytes(zero_count),
        )

    def test_reads_rust_workspace_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "rust").mkdir()
            (root / "rust/Cargo.toml").write_text(
                '[workspace]\nmembers = []\n\n[workspace.package]\nversion = "1.2.3"\n',
                encoding="utf-8",
            )
            self.assertEqual(packaging.read_rust_workspace_version(root), "1.2.3")

    def test_rust_workspace_version_requires_pinned_section(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "rust").mkdir()
            (root / "rust/Cargo.toml").write_text(
                "[workspace]\nmembers = []\n",
                encoding="utf-8",
            )
            self.assertRaises(
                packaging.VerificationError,
                packaging.read_rust_workspace_version,
                root,
            )

    def test_parses_apk_build_metadata_properties(self) -> None:
        self.assertEqual(
            packaging._parse_properties(
                b"appMetadataVersion=1.1\nandroidGradlePluginVersion=9.0.1\n"
            ),
            {
                "appMetadataVersion": "1.1",
                "androidGradlePluginVersion": "9.0.1",
            },
        )

    def test_build_record_requires_matching_prebuild_source(self) -> None:
        source = packaging.compute_source_state(ROOT)
        with self.assertRaisesRegex(
            packaging.VerificationError,
            "source tree changed",
        ):
            packaging.build_record(
                ROOT,
                replace(source, fingerprint="0" * 64),
            )


class CliErrorClassificationTests(unittest.TestCase):
    def _arguments(self, **changes: object) -> argparse.Namespace:
        values: dict[str, object] = {
            "root": str(ROOT),
            "apk": str(ROOT / "missing.apk"),
            "native_metadata": str(ROOT / "missing.json"),
            "provenance_out": None,
            "expected_revision": None,
            "expected_signer_sha256": None,
            "debug_keystore": str(ROOT / "missing.keystore"),
            "comparison_apk": None,
            "comparison_revision": None,
            "prebuild_source_state": None,
            "allow_provisional": False,
            "aapt2": None,
            "apksigner": None,
            "zipalign": None,
            "keytool": None,
        }
        values.update(changes)
        return argparse.Namespace(**values)

    def test_missing_inspection_tool_has_tooling_exit_status(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            status = packaging.command_verify(
                self._arguments(aapt2="/definitely/missing/aapt2")
            )
        self.assertEqual(status, packaging.EXIT_TOOLING)
        self.assertIn("tooling unavailable", stderr.getvalue())

    def test_missing_artifact_is_an_invalid_artifact(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            status = packaging.command_verify(
                self._arguments(
                    aapt2="/usr/bin/true",
                    apksigner="/usr/bin/true",
                    zipalign="/usr/bin/true",
                    keytool="/usr/bin/true",
                )
            )
        self.assertEqual(status, packaging.EXIT_INVALID_ARTIFACT)
        self.assertIn("native build metadata", stderr.getvalue())

    def test_comparison_without_explicit_revision_is_rejected(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            status = packaging.command_verify(
                self._arguments(
                    aapt2="/usr/bin/true",
                    apksigner="/usr/bin/true",
                    zipalign="/usr/bin/true",
                    keytool="/usr/bin/true",
                    comparison_apk=str(ROOT / "release.apk"),
                )
            )
        self.assertEqual(status, packaging.EXIT_INVALID_ARTIFACT)
        self.assertIn("supplied together", stderr.getvalue())

    def test_successful_verification_writes_provenance(self) -> None:
        source = _valid_source()
        facts = _valid_facts(source)
        with tempfile.TemporaryDirectory() as directory:
            provenance = Path(directory) / "provenance.json"
            stdout = io.StringIO()
            with (
                mock.patch.object(packaging, "resolve_tools", return_value={
                    "aapt2": Path("/usr/bin/true"),
                    "apksigner": Path("/usr/bin/true"),
                    "zipalign": Path("/usr/bin/true"),
                    "keytool": Path("/usr/bin/true"),
                }),
                mock.patch.object(
                    packaging,
                    "read_native_metadata",
                    return_value=_valid_native(source),
                ),
                mock.patch.object(
                    packaging,
                    "read_expected_debug_certificate",
                    return_value=SIGNER_SHA256,
                ),
                mock.patch.object(packaging, "compute_source_state", return_value=source),
                mock.patch.object(packaging, "inspect_apk", return_value=facts),
                redirect_stdout(stdout),
            ):
                status = packaging.command_verify(
                    self._arguments(
                        apk=str(ROOT / "qualification.apk"),
                        native_metadata=str(ROOT / "native-build.json"),
                        provenance_out=str(provenance),
                    )
                )
            self.assertEqual(status, packaging.EXIT_VALIDATED)
            self.assertIn("ARTIFACT_VALIDATED", stdout.getvalue())
            document = json.loads(provenance.read_text(encoding="utf-8"))
            self.assertEqual(document["verification_result"], "ARTIFACT_VALIDATED")

    def test_native_output_directory_command_classifies_ownership(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            accepted = argparse.Namespace(
                root=str(root),
                output=str(root / "out"),
                default_output=str(root / "default"),
            )
            with redirect_stdout(io.StringIO()) as stdout:
                self.assertEqual(
                    packaging.command_native_output_directory(accepted),
                    packaging.EXIT_VALIDATED,
                )
            self.assertEqual(
                stdout.getvalue().strip(), str((root / "out").resolve())
            )

            (root / "unowned").mkdir()
            (root / "unowned/info.txt").write_text("keep", encoding="utf-8")
            rejected = argparse.Namespace(
                root=str(root),
                output=str(root / "unowned"),
                default_output=str(root / "default"),
            )
            with redirect_stderr(io.StringIO()) as stderr:
                self.assertEqual(
                    packaging.command_native_output_directory(rejected),
                    packaging.EXIT_USAGE,
                )
            self.assertIn("unowned native output directory", stderr.getvalue())


class NativeOutputDirectoryTests(unittest.TestCase):
    def test_default_directory_is_build_owned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            default = root / "native-jni/release"
            result = packaging.prepare_native_output_directory(default, default)
            self.assertEqual(result, default.resolve())
            self.assertFalse((result / packaging.NATIVE_OUTPUT_MARKER).exists())

    def test_empty_explicit_directory_is_claimed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            result = packaging.prepare_native_output_directory(
                requested, root / "native-jni/release"
            )
            self.assertEqual(result, requested.resolve())
            self.assertEqual(
                (result / packaging.NATIVE_OUTPUT_MARKER).read_text(encoding="utf-8"),
                packaging.NATIVE_OUTPUT_MARKER_CONTENT,
            )

    def test_marked_explicit_directory_is_reused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            first = packaging.prepare_native_output_directory(
                requested, root / "default"
            )
            (first / "arm64-v8a").mkdir()
            second = packaging.prepare_native_output_directory(
                requested, root / "default"
            )
            self.assertEqual(first, second)

    def test_unowned_nonempty_explicit_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            requested.mkdir()
            (requested / "notes.txt").write_text("keep", encoding="utf-8")
            self.assertRaisesRegex(
                packaging.VerificationError,
                "unowned native output directory",
                packaging.prepare_native_output_directory,
                requested,
                root / "default",
            )

    def test_unrecognized_marker_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            requested.mkdir()
            (requested / packaging.NATIVE_OUTPUT_MARKER).write_text(
                "another tool\n", encoding="utf-8"
            )
            self.assertRaisesRegex(
                packaging.VerificationError,
                "marker is not recognized",
                packaging.prepare_native_output_directory,
                requested,
                root / "default",
            )

    def test_symlinked_output_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            target = root / "target"
            target.mkdir()
            link = root / "link"
            link.symlink_to(target, target_is_directory=True)
            self.assertRaisesRegex(
                packaging.VerificationError,
                "must not contain a symbolic link component",
                packaging.prepare_native_output_directory,
                link,
                root / "default",
            )

    def test_symlinked_output_parent_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            target = root / "target"
            target.mkdir()
            link = root / "link"
            link.symlink_to(target, target_is_directory=True)
            self.assertRaisesRegex(
                packaging.VerificationError,
                "must not contain a symbolic link component",
                packaging.prepare_native_output_directory,
                link / "nested",
                root / "default",
            )

    def test_symlinked_abi_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            requested.mkdir()
            target = root / "elsewhere"
            target.mkdir()
            (requested / "arm64-v8a").symlink_to(
                target, target_is_directory=True
            )
            self.assertRaisesRegex(
                packaging.VerificationError,
                "native ABI output directory must not be a symbolic link",
                packaging.prepare_native_output_directory,
                requested,
                root / "default",
            )

    def test_filesystem_root_is_rejected(self) -> None:
        self.assertRaisesRegex(
            packaging.VerificationError,
            "filesystem root",
            packaging.prepare_native_output_directory,
            Path("/"),
            Path("/tmp/unused-native-output"),
        )

    def test_commit_replaces_owned_abi_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            output = packaging.prepare_native_output_directory(
                requested, root / "default"
            )
            final_abi = output / "arm64-v8a"
            final_abi.mkdir()
            (final_abi / "old.txt").write_text("old\n", encoding="utf-8")
            staging = Path(tempfile.mkdtemp(dir=output, prefix=".argus-bridge."))
            staged_abi = staging / "arm64-v8a"
            staged_abi.mkdir()
            (staged_abi / "new.txt").write_text("new\n", encoding="utf-8")
            metadata = output / "native-build.json"
            metadata_temporary = output / "native-build.json.tmp"
            metadata_temporary.write_text('{"build":"ready"}\n', encoding="utf-8")

            packaging.commit_native_output(
                output,
                root / "default",
                staged_abi,
                metadata_temporary,
                metadata,
            )

            self.assertFalse((final_abi / "old.txt").exists())
            self.assertEqual(
                (final_abi / "new.txt").read_text(encoding="utf-8"), "new\n"
            )
            self.assertEqual(
                metadata.read_text(encoding="utf-8"), '{"build":"ready"}\n'
            )
            self.assertFalse(metadata_temporary.exists())
            self.assertEqual(list(output.glob(".argus-bridge-previous-*")), [])

    def test_commit_accepts_default_directory_without_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            default = root / "native-jni/release"
            output = packaging.prepare_native_output_directory(default, default)
            staging = Path(tempfile.mkdtemp(dir=output, prefix=".argus-bridge."))
            staged_abi = staging / "arm64-v8a"
            staged_abi.mkdir()
            (staged_abi / "libargus_bridge.so").write_bytes(b"native")
            metadata_temporary = output / "native-build.json.tmp"
            metadata_temporary.write_text("{}\n", encoding="utf-8")

            packaging.commit_native_output(
                output,
                default,
                staged_abi,
                metadata_temporary,
                output / "native-build.json",
            )

            self.assertEqual(
                (output / "arm64-v8a/libargus_bridge.so").read_bytes(), b"native"
            )
            self.assertFalse((output / packaging.NATIVE_OUTPUT_MARKER).exists())

    def test_commit_revalidates_abi_symlink_after_initial_validation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            output = packaging.prepare_native_output_directory(
                requested, root / "default"
            )
            target = root / "elsewhere"
            target.mkdir()
            (output / "arm64-v8a").symlink_to(target, target_is_directory=True)
            staging = Path(tempfile.mkdtemp(dir=output, prefix=".argus-bridge."))
            staged_abi = staging / "arm64-v8a"
            staged_abi.mkdir()
            metadata_temporary = output / "native-build.json.tmp"
            metadata_temporary.write_text("{}\n", encoding="utf-8")

            with self.assertRaisesRegex(
                packaging.VerificationError,
                "native ABI output directory must not be a symbolic link",
            ):
                packaging.commit_native_output(
                    output,
                    root / "default",
                    staged_abi,
                    metadata_temporary,
                    output / "native-build.json",
                )

    def test_commit_revalidates_parent_after_initial_validation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            requested = root / "custom"
            output = packaging.prepare_native_output_directory(
                requested, root / "default"
            )
            staging = Path(tempfile.mkdtemp(dir=output, prefix=".argus-bridge."))
            staged_abi = staging / "arm64-v8a"
            staged_abi.mkdir()
            metadata_temporary = output / "native-build.json.tmp"
            metadata_temporary.write_text("{}\n", encoding="utf-8")

            moved = root / "moved"
            output.rename(moved)
            target = root / "target"
            target.mkdir()
            output.symlink_to(target, target_is_directory=True)

            with self.assertRaisesRegex(
                packaging.VerificationError,
                "must not contain a symbolic link component",
            ):
                packaging.commit_native_output(
                    output,
                    root / "default",
                    moved / staging.name / "arm64-v8a",
                    moved / "native-build.json.tmp",
                    moved / "native-build.json",
                )


class RealFlutterPayloadTests(unittest.TestCase):
    """Check the Flutter mode discriminator against real packaged APKs.

    Synthetic ZIP entry lists prove the validator logic. These tests also
    prove that the pinned Flutter engine actually packages the distinguishing
    VM-service snapshot in Profile mode. They need host build outputs and are
    skipped on machines that have not produced those Flutter variants.
    """

    FLUTTER_APK_DIRECTORY = (
        ROOT / "flutter" / "build" / "app" / "outputs" / "flutter-apk"
    )

    def _payload(self, name: str) -> packaging.FlutterReleaseFacts:
        apk = self.FLUTTER_APK_DIRECTORY / name
        if not apk.is_file():
            self.skipTest(f"host Flutter build artifact is unavailable: {apk}")
        with zipfile.ZipFile(apk) as archive:
            entries = tuple(archive.namelist())
        return packaging._flutter_release_facts(entries)

    def test_real_profile_apk_is_not_release_payload(self) -> None:
        payload = self._payload("app-profile.apk")

        self.assertTrue(payload.vmservice_snapshot_present)
        self.assertFalse(payload.release_payload)

        errors = packaging.validate_artifact(
            replace(_valid_facts(), flutter_release=payload),
            _valid_expected(),
            _valid_native(_valid_source()),
            _valid_source(),
            ROOT,
        )
        self.assertTrue(
            any("Flutter Release AOT payload" in error for error in errors),
            msg=f"expected the real Profile payload to be rejected: {errors!r}",
        )

    def test_real_release_apk_is_release_payload(self) -> None:
        payload = self._payload("app-release.apk")

        self.assertFalse(payload.vmservice_snapshot_present)
        self.assertTrue(payload.release_payload)


if __name__ == "__main__":
    unittest.main()
