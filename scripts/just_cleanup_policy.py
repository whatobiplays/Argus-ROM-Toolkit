"""Reviewed retention and producer-path policy for the Just cleanup helper.

This module classifies repository-generated files without performing filesystem
mutation. The executable helper supplies directory handles and uses these pure
predicates before deleting anything.
"""

from __future__ import annotations

import os
import stat
from pathlib import Path
from typing import Sequence


_PROTECTED_COMPONENT_NAMES = {
    ".chatgpt",
    ".codex",
    ".git",
    ".superpowers",
    "rom",
    "roms",
    "library",
    "libraries",
    "qualification",
    "provenance",
    "evidence",
    "baselines",
    "foreign",
    "unknown",
}
_PROTECTED_EXACT_FILE_NAMES = {
    ".envrc",
    ".git-credentials",
    "gradle.properties",
    ".netrc",
    ".npmrc",
    ".pypirc",
    "id_ed25519",
    "id_rsa",
    "keystore",
    "local.properties",
    "signing",
}
_PROTECTED_SENSITIVE_NAME_PARTS = frozenset(
    {
        "accesskey",
        "apikey",
        "auth",
        "authentication",
        "authorization",
        "clientsecret",
        "codesign",
        "credential",
        "credentials",
        "password",
        "passwd",
        "passphrase",
        "private",
        "privatekey",
        "secret",
        "secrets",
        "signing",
        "token",
        "tokens",
    }
)
_PROTECTED_FILE_SUFFIXES = (
    ".aab",
    ".apk",
    ".cer",
    ".crt",
    ".csr",
    ".db",
    ".der",
    ".gba",
    ".iso",
    ".jks",
    ".keystore",
    ".key",
    ".kdbx",
    ".local",
    ".mobileprovision",
    ".ovpn",
    ".p8",
    ".p12",
    ".pem",
    ".pfx",
    ".provisionprofile",
    ".rom",
    ".sqlite",
    ".sqlite3",
    ".zip",
)

_PRODUCER_FILE_SUFFIXES = {
    "rust": frozenset(
        {
            ".a",
            ".crate",
            ".d",
            ".dll",
            ".dylib",
            ".json",
            ".lib",
            ".o",
            ".obj",
            ".pdb",
            ".rlib",
            ".rmeta",
            ".so",
            ".toml",
            ".wasm",
        }
    ),
    "android": frozenset(
        {
            ".aidl",
            ".a",
            ".aar",
            ".arsc",
            ".class",
            ".cmake",
            ".d",
            ".dex",
            ".dill",
            ".flat",
            ".gif",
            ".hash",
            ".jar",
            ".java",
            ".jdeps",
            ".jpg",
            ".jpeg",
            ".json",
            ".kt",
            ".kotlin",
            ".kotlin_builtins",
            ".kotlin_module",
            ".kotlin_project",
            ".lst",
            ".make",
            ".map",
            ".ninja",
            ".ninja_deps",
            ".ninja_log",
            ".o",
            ".png",
            ".pro",
            ".profile",
            ".properties",
            ".rules",
            ".sha1",
            ".so",
            ".stamp",
            ".svg",
            ".tlog",
            ".tmp",
            ".txt",
            ".webp",
            ".xml",
        }
    ),
    "native": frozenset(
        {
            ".a",
            ".bc",
            ".d",
            ".dia",
            ".json",
            ".log",
            ".modulemap",
            ".o",
            ".pch",
            ".pcm",
            ".plist",
            ".pri",
            ".strings",
            ".swiftdeps",
            ".swiftdoc",
            ".swiftmodule",
            ".xcactivitylog",
            ".xib",
        }
    ),
    "flutter": frozenset(
        {".d", ".dill", ".json", ".log", ".snapshot", ".stamp", ".tmp", ".yaml"}
    ),
    "gradle": frozenset(
        {
            ".bin",
            ".class",
            ".dat",
            ".jar",
            ".json",
            ".lock",
            ".log",
            ".md5",
            ".out",
            ".pro",
            ".properties",
            ".sha1",
            ".txt",
            ".xml",
            ".xd",
        }
    ),
    "kotlin": frozenset(
        {
            ".bin",
            ".class",
            ".json",
            ".kotlin_module",
            ".len",
            ".lock",
            ".tab",
            ".tmp",
        }
    ),
}

_GENERIC_PRODUCER_FILE_SUFFIXES = frozenset(
    {".json", ".toml", ".xml", ".plist", ".yaml", ".properties", ".txt"}
)


# Names are compared after case-folding in ``_producer_relative_parts``.
_PRODUCER_TOP_LEVEL_DIRECTORIES = {
    "rust": frozenset(
        {
            ".fingerprint",
            "build",
            "debug",
            "deps",
            "doc",
            "examples",
            "incremental",
            "package",
            "release",
            "tmp",
        }
    ),
    "android": frozenset(
        {
            ".cxx",
            "aar_metadata",
            "android_res",
            "annotation_processor_list",
            "ap_generated_sources",
            "apk_ide_redirect_file",
            "app_metadata",
            "assets",
            "build_config",
            "compile_and_runtime_not_namespaced_r_class_jar",
            "compile_app_classes_jar",
            "compile_library_classes_jar",
            "compile_r_class_jar",
            "compressed_assets",
            "debug",
            "debug_symbols",
            "default_proguard_files_jar",
            "desugar_graph",
            "dex",
            "dex_archive_input_jar_hashes",
            "generated",
            "incremental",
            "incremental_sources",
            "java_res",
            "javac",
            "kotlin",
            "manifest_merge_blame_file",
            "merged_assets",
            "merged_jni_libs",
            "merged_manifest",
            "merged_manifests",
            "merged_native_libs",
            "merged_res",
            "merged_shaders",
            "navigation_json",
            "packaged_manifests",
            "processed_res",
            "profile",
            "release",
            "res",
            "runtime_symbol_list",
            "source",
            "source_set_path_map",
            "stripped_native_libs",
            "symbol_list_with_package_name",
            "tmp",
            "unit_test_config_directory",
        }
    ),
    "gradle": frozenset(
        {
            ".tmp",
            "buildoutputcleanup",
            "caches",
            "checksums",
            "configuration-cache",
            "daemon",
            "executionhistory",
            "filechanges",
            "filehashes",
            "jdks",
            "kotlin-dsl",
            "native",
            "notifications",
            "transforms",
            "vcs-1",
            "wrapper",
        }
    ),
    "kotlin": frozenset(
        {
            "compiler",
            "daemon",
            "errors",
            "kotlin-daemon",
            "sessions",
        }
    ),
}

# Prefixes identify task directories emitted by Android and Gradle builds.
_PRODUCER_TOP_LEVEL_DIRECTORY_PREFIXES = {
    "android": (
        "bundle",
        "check",
        "compile",
        "copy",
        "create",
        "desugar",
        "dex",
        "extract",
        "generate",
        "java",
        "kapt",
        "lint",
        "merge",
        "package",
        "prepare",
        "process",
        "strip",
        "transform",
        "validate",
        "write",
    ),
    "gradle": ("transforms-",),
}




def _producer_relative_parts(category: str, entry_path: str) -> tuple[str, ...]:
    """Return path components below the selected producer root."""

    parts = tuple(part.casefold() for part in Path(entry_path).parts)
    markers = {
        "rust": ("target",),
        "native": ("intermediates.noindex",),
        "flutter": ("flutter_build",),
        "gradle": (".gradle",),
        "kotlin": (".kotlin",),
        "python": ("__pycache__",),
    }.get(category, ())
    if category == "android":
        for index, part in enumerate(parts[:-1]):
            if part != "app":
                continue
            candidate = parts[index + 1]
            if candidate in {".cxx", "generated", "intermediates", "tmp"}:
                return parts[index + 2 :]
        return ()
    for marker in markers:
        try:
            index = parts.index(marker)
        except ValueError:
            continue
        return parts[index + 1 :]
    return ()


def _cargo_hashed_directory(name: str) -> bool:
    """Return whether a Cargo-owned directory ends in a 16-digit hex hash."""

    suffix = name.rsplit("-", 1)[-1]
    return len(suffix) == 16 and all(character in "0123456789abcdef" for character in suffix)


def _task_family_directory(raw_directory: str, prefix: str) -> bool:
    """Match one reviewed CamelCase task family without accepting siblings."""

    if raw_directory == prefix:
        return True
    if prefix.endswith("-"):
        suffix = raw_directory[len(prefix) :]
        return raw_directory.startswith(prefix) and bool(suffix) and suffix.isdigit()
    return (
        raw_directory.startswith(prefix)
        and len(raw_directory) > len(prefix)
        and "A" <= raw_directory[len(prefix)] <= "Z"
    )


def _native_target_directory(name: str) -> bool:
    """Accept only a conservative Xcode target-directory spelling."""

    if not name.endswith(".build") or name == ".build":
        return False
    target = name[: -len(".build")]
    return bool(target) and all(
        character.isalnum() or character in {"_", " "} for character in target
    )


def _native_producer_directory_allowed(relative_parts: Sequence[str]) -> bool:
    """Accept only reviewed Xcode object directories below Intermediates."""

    if not relative_parts or not _native_target_directory(relative_parts[0]):
        return False
    if len(relative_parts) == 1:
        return True
    if relative_parts[1] != "objects-normal":
        return False
    if len(relative_parts) == 2:
        return True
    architecture = relative_parts[2]
    if not architecture or not all(
        character.isalnum() or character in {"_", "-"} for character in architecture
    ):
        return False
    if len(relative_parts) == 3:
        return True
    return False


def _rust_producer_directory_allowed(relative_parts: Sequence[str]) -> bool:
    """Validate a Cargo target directory without accepting arbitrary siblings."""

    if not relative_parts:
        return False
    top_level = relative_parts[0]
    if len(relative_parts) == 1:
        return top_level in _PRODUCER_TOP_LEVEL_DIRECTORIES["rust"]
    if top_level == "build":
        return _cargo_hashed_directory(relative_parts[1])
    if top_level == ".fingerprint":
        return len(relative_parts) == 2 and _cargo_hashed_directory(relative_parts[1])
    if top_level in {"debug", "release"}:
        producer_directory = relative_parts[1]
        if len(relative_parts) == 2:
            return producer_directory in {
                ".fingerprint",
                "build",
                "deps",
                "doc",
                "examples",
                "incremental",
                "package",
                "tmp",
            }
        if producer_directory in {"build", "incremental", ".fingerprint"}:
            return _cargo_hashed_directory(relative_parts[2])
        return producer_directory == "doc"
    return False


def _nested_producer_directory_allowed(
    category: str,
    relative_parts: Sequence[str],
) -> bool:
    """Validate directories below category-specific producer roots."""

    nested = relative_parts[1:]
    if not nested:
        return True
    if category == "native":
        return _native_producer_directory_allowed(relative_parts)
    if category == "flutter":
        return False
    if category == "android":
        reviewed = {
            "assets",
            "classes",
            "debug",
            "generated",
            "incremental",
            "java",
            "kotlin",
            "manifests",
            "merged_manifests",
            "merged_res",
            "packaged_res",
            "release",
            "res",
            "resources",
            "values",
        }
        return all(part in reviewed for part in nested)
    if category == "kotlin":
        return all(part in {"compiler", "sessions"} for part in nested)
    if category == "gradle":
        if relative_parts[0] != "caches":
            return all(part in {"dists", "gradle-version", "wrapper"} for part in nested)
        if len(nested) == 1:
            return nested[0] in {"modules-2", "transforms", "transforms-3", "transforms-4"}
        if nested[0] == "modules-2" and nested[1].startswith("files-2."):
            return True
        return False
    return False


def _producer_directory_allowed(category: str, entry_path: str) -> bool:
    """Return whether a directory has a reviewed producer location."""

    relative_parts = _producer_relative_parts(category, entry_path)
    if category == "python":
        return False
    if not relative_parts:
        return False
    if category == "rust":
        return _rust_producer_directory_allowed(relative_parts)
    if category == "native":
        return _native_producer_directory_allowed(relative_parts)
    directory = relative_parts[0]
    raw_parts = tuple(Path(entry_path).parts)
    raw_directory = raw_parts[-len(relative_parts)]
    top_level_allowed = directory in _PRODUCER_TOP_LEVEL_DIRECTORIES.get(
        category, frozenset()
    ) or any(
        _task_family_directory(raw_directory, prefix)
        for prefix in _PRODUCER_TOP_LEVEL_DIRECTORY_PREFIXES.get(category, ())
    )
    if category == "flutter" and len(directory) == 64 and all(
            character in "0123456789abcdef" for character in directory
        ):
        top_level_allowed = True
    if category == "gradle" and bool(directory) and all(
            character.isdigit() or character == "." for character in directory
        ):
        top_level_allowed = True
    if not top_level_allowed:
        return False
    return _nested_producer_directory_allowed(category, relative_parts)


def _producer_generic_file_allowed(
    category: str,
    entry_path: str,
    suffix: str,
) -> bool:
    """Match generic data files to a producer-specific path and filename."""

    parts = tuple(part.casefold() for part in Path(entry_path).parts)
    parent_parts = parts[:-1]
    name = Path(entry_path).name.casefold()

    if category == "rust":
        try:
            target_index = parts.index("target")
        except ValueError:
            return False
        target_parts = parts[target_index + 1 :]
        if suffix == ".json":
            if name == ".rustc_info.json" and len(target_parts) == 1:
                return True
            return (
                ".fingerprint" in target_parts
                and name.endswith(".json")
                and name.startswith(
                    ("bin-", "build-script-", "lib-", "run-build-script-", "test-")
                )
            )
        if suffix == ".toml":
            return name == "cargo.toml" and "package" in target_parts
        return False

    if category == "android":
        if suffix == ".json":
            return (
                name == "metadata.json" and "app_metadata" in parent_parts
            ) or (
                name == "build-info.json" and "build_config" in parent_parts
            ) or (
                name == "output-metadata.json"
                and "outputs" in parent_parts
                and any(part in {"apk", "bundle"} for part in parent_parts)
            )
        if suffix == ".xml":
            if name == "androidmanifest.xml":
                return any(
                    part in {"merged_manifest", "merged_manifests"}
                    for part in parent_parts
                )
            return name in {"public.xml", "values.xml"} and any(
                part in {"merged_res", "packaged_res"} for part in parent_parts
            ) and "values" in parent_parts
        if suffix == ".properties":
            return name == "aar-metadata.properties" and "aar_metadata" in parent_parts
        if suffix == ".txt":
            return name in {
                "maindexlist.txt",
                "missing_rules.txt",
                "proguard-rules.txt",
            } and any(
                part in {"desugar_graph", "default_proguard_files_jar"}
                for part in parent_parts
            )
        return False

    if category == "native":
        relative_parts = _producer_relative_parts(category, entry_path)
        if len(relative_parts) < 3:
            return False
        has_build_directory = any(part.endswith(".build") for part in parent_parts)
        if suffix == ".json":
            return (
                name.endswith("-outputfilemap.json")
                and "objects-normal" in parent_parts
                and has_build_directory
            )
        if suffix == ".plist":
            return name == "info.plist" and has_build_directory
        return False

    if category == "flutter":
        return (
            suffix == ".json"
            and name in {"outputs.json", "kernel_snapshot_program.json"}
            and "flutter_build" in parent_parts
        )

    if category == "gradle":
        return (
            suffix == ".xml"
            and name == "pom.xml"
            and "caches" in parent_parts
            and any(part.startswith("files-2.") for part in parent_parts)
        )

    if category == "kotlin":
        return (
            suffix == ".json"
            and name == "build-history.json"
            and any(part in {"build-history", "compiler"} for part in parent_parts)
        )

    return False


def _producer_file_path_allowed(category: str, entry_path: str) -> bool:
    """Require a non-generic file to use an explicitly reviewed producer path."""

    parent_path = str(Path(entry_path).parent)
    relative_parts = _producer_relative_parts(category, parent_path)
    if category == "native" and len(relative_parts) < 3:
        return False
    return bool(relative_parts) and _producer_directory_allowed(category, parent_path)


def _producer_content_allowed(
    category: str,
    entry_path: str,
    metadata: os.stat_result,
) -> bool:
    """Return whether a regular file has a reviewed producer signature."""

    name = Path(entry_path).name.casefold()
    suffix = Path(entry_path).suffix.casefold()
    if _protected_nested_entry(name):
        return False
    if category == "rust":
        components = tuple(part.casefold() for part in Path(entry_path).parts)
        try:
            target_index = components.index("target")
        except ValueError:
            return False
        target_parts = components[target_index + 1 :]
        reviewed_root_file = name in {
            ".cargo-lock",
            ".rustc_info.json",
            "cachedir.tag",
        }
        if len(target_parts) == 1:
            return reviewed_root_file
        if not _producer_directory_allowed("rust", str(Path(entry_path).parent)):
            return False
        if reviewed_root_file:
            return True

    if suffix in _GENERIC_PRODUCER_FILE_SUFFIXES:
        return _producer_generic_file_allowed(category, entry_path, suffix)
    if suffix in _PRODUCER_FILE_SUFFIXES.get(category, frozenset()):
        return _producer_file_path_allowed(category, entry_path)
    if category != "rust":
        return False

    if any(part in {"build", "doc", "incremental", "package"} for part in target_parts):
        return True
    if ".fingerprint" in target_parts and name.startswith(
        ("bin-", "build-script-", "lib-", "test-")
    ):
        return True
    if (
        bool(stat.S_IMODE(metadata.st_mode) & 0o111)
        and len(target_parts) >= 2
        and target_parts[-2] in {"debug", "release"}
    ):
        return True
    return False




def _protected_nested_entry(name: str) -> str | None:
    """Return a retention reason for names that can hold private user state."""

    folded = name.casefold()
    if folded.startswith(".env"):
        return "credential files are protected"
    name_parts = folded.replace("-", " ").replace("_", " ").replace(".", " ").split()
    normalized = "".join(name_parts)
    if any(part in _PROTECTED_SENSITIVE_NAME_PARTS for part in name_parts) or any(
        marker in normalized
        for marker in {
            "accesskey",
            "apikey",
            "authentication",
            "clientsecret",
            "codesign",
            "credential",
            "passphrase",
            "password",
            "passwd",
            "private",
            "privatekey",
            "secret",
            "signing",
            "token",
        }
    ):
        return "credential, secret, token, private-state, and signing files are protected"
    if folded in _PROTECTED_EXACT_FILE_NAMES:
        return "credential and machine-local configuration files are protected"
    if folded.endswith(_PROTECTED_FILE_SUFFIXES):
        return "databases, ROM/media files, and distributable packages are protected"
    if folded.startswith(("signing.", "codesign.")):
        return "signing material is protected"
    if folded in _PROTECTED_COMPONENT_NAMES:
        return "evidence and user library directories are protected"
    return None



