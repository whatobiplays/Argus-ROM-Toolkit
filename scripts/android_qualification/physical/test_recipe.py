"""Protect the canonical host-only qualification test registration."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "docs/archive/qualification/issue-21-v1/archive-manifest-v1.json"


def recipe_lines(lines, name):
    """Return one Just recipe body without shell continuation ambiguity."""
    start = lines.index(name + ":")
    body = []
    for line in lines[start + 1 :]:
        if line and not line.startswith((" ", "\t")):
            break
        if line.strip():
            body.append(line.strip())
    return body


class CanonicalTestRegistrationTests(unittest.TestCase):
    def test_qualification_suite_is_first_and_host_only_in_just_test(self):
        lines = (ROOT / "justfile").read_text(encoding="utf-8").splitlines()
        recipe = recipe_lines(lines, "test")
        command = "just test-android-qualification"
        self.assertTrue(recipe, "just test must have a recipe")
        self.assertEqual(recipe[0], command)
        self.assertLess(recipe.index(command), recipe.index("bash scripts/test_macos_frb_exports.sh"))
        recipe_text = "\n".join(recipe).lower()
        self.assertNotIn("adb", recipe_text)
        self.assertNotIn("argus_release_", recipe_text)
        self.assertNotIn(
            "run_phase_" + "003_android_physical_qualification.sh",
            recipe_text,
        )

    def test_combined_recipe_discovers_both_qualification_packages_once(self):
        lines = (ROOT / "justfile").read_text(encoding="utf-8").splitlines()
        body = recipe_lines(lines, "test-android-qualification")
        command = (
            "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover "
            "-s scripts/android_qualification -p 'test_*.py' -t ."
        )
        self.assertEqual(body, [command])

    def test_check_does_not_register_the_combined_recipe_a_second_time(self):
        lines = (ROOT / "justfile").read_text(encoding="utf-8").splitlines()
        check = next(line for line in lines if line.startswith("check:"))
        self.assertEqual(check.count("test-android-qualification"), 0)

    def test_retired_entrypoint_is_derived_from_archive_manifest(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        entrypoints = [
            entry
            for entry in manifest["entries"]
            if entry["role"] == "retired_entrypoint"
        ]
        self.assertEqual(len(entrypoints), 1)
        retired_path = ROOT / entrypoints[0]["original_path"]
        self.assertFalse(retired_path.exists())


if __name__ == "__main__":
    unittest.main()
