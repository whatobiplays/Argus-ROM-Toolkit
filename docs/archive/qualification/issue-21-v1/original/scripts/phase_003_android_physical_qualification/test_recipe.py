"""Protect the host-only qualification tests in the canonical test gate."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class CanonicalTestRegistrationTests(unittest.TestCase):
    def test_qualification_suite_is_first_and_host_only_in_just_test(self):
        lines = (ROOT / 'justfile').read_text(encoding='utf-8').splitlines()
        start = lines.index('test:')
        recipe = []
        for line in lines[start + 1:]:
            if line and not line.startswith((' ', '\t')):
                break
            if line.strip():
                recipe.append(line.strip())

        command = (
            "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover "
            "-s scripts/phase_003_android_physical_qualification "
            "-p 'test_*.py'"
        )
        self.assertTrue(recipe, 'just test must have a recipe')
        self.assertEqual(recipe[0], command)
        self.assertLess(recipe.index(command), recipe.index('bash scripts/test_macos_frb_exports.sh'))
        recipe_text = '\n'.join(recipe).lower()
        self.assertNotIn('adb', recipe_text)
        self.assertNotIn('argus_release_', recipe_text)
        self.assertNotIn('run_phase_003_android_physical_qualification.sh', recipe_text)
