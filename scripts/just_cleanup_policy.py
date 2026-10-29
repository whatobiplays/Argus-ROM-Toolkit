"""Repository-level ownership policy for the Just cleanup helper.

Cleanup eligibility is decided by an exact generated directory root. Files,
directories, extensions, and names below an admitted root are intentionally
not classified: an approved build directory belongs entirely to disposable
build output. The helper still enforces the safety checks implemented in
``just_cleanup.py`` before it deletes anything.

``PROTECTED_PATHS`` documents durable repository locations outside the
cleanup roots. They appear in preview and apply reports as skipped paths so
users can confirm why those locations are not cleanup candidates.
"""

from __future__ import annotations


GIT_CONTEXT_ENVIRONMENT: tuple[str, ...] = (
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_CEILING_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_DIR",
    "GIT_DISCOVERY_ACROSS_FILESYSTEM",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_WORK_TREE",
)


PROTECTED_PATHS: tuple[tuple[str, str], ...] = (
    (".chatgpt", "Review and run evidence is retained."),
    (".codex", "Local Codex state is retained."),
    ("build", "The root build directory is retained."),
    ("docs/archive", "Archived evidence is retained."),
    ("docs/qualification", "Qualification records are retained."),
    ("flutter/.fvm", "The pinned Flutter SDK and cache are retained."),
    (
        "flutter/android/app/outputs",
        "Android application outputs may contain distributable packages.",
    ),
    (
        "flutter/android/local.properties",
        "Machine-local Android configuration is retained.",
    ),
    (
        "flutter/build/app/outputs",
        "Debug and release APKs are retained.",
    ),
    (
        "flutter/build/native-jni",
        "Native JNI artifacts and metadata are retained.",
    ),
    (
        "flutter/build/qualification",
        "Qualification APKs and provenance are retained.",
    ),
    ("flutter/lib", "Tracked and generated Dart source is retained."),
)
