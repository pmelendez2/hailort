"""Tests of generated release metadata, without changing repository files."""
import importlib.util
import unittest
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / 'scripts/sync-release-docs.py'
SPEC = importlib.util.spec_from_file_location('sync_release_docs', PATH)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class ReleaseDocsTests(unittest.TestCase):
    def setUp(self):
        self.source = '# Heading\n\nExisting prose.\n'
        self.block = MOD.render('4.24.0-mps.1')

    def test_init_preserves_prose(self):
        updated = MOD.transform(self.source, self.block, True)
        self.assertIn('Existing prose.', updated)
        self.assertEqual(updated.count(MOD.START), 1)

    def test_sync_idempotent(self):
        updated = MOD.transform(self.source, self.block, True)
        self.assertEqual(MOD.transform(updated, self.block, False), updated)

    def test_stale_replaced(self):
        previous = MOD.render('4.24.0-mps.2')
        updated = MOD.transform(self.source, previous, True)
        result = MOD.transform(updated, self.block, False)
        self.assertIn('v4.24.0-mps.1', result)
        self.assertNotIn('v4.24.0-mps.2', result)

    def test_missing_marker_fails(self):
        with self.assertRaisesRegex(ValueError, 'missing'):
            MOD.transform(self.source, self.block, False)

    def test_duplicate_markers_fail(self):
        updated = MOD.transform(self.source, self.block, True)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            MOD.transform(updated + '\n' + self.block, self.block, False)

    def test_version_pattern(self):
        self.assertTrue(MOD.PATTERN.fullmatch('4.24.0-mps.1'))
        self.assertFalse(MOD.PATTERN.fullmatch('4.25.0-mps.1'))
        self.assertFalse(MOD.PATTERN.fullmatch('4.24.0-mps.0'))


if __name__ == '__main__':
    unittest.main()
