"""Tests for {{PACKAGE}}.config."""
import pathlib
import tempfile
import unittest

from {{PACKAGE}}.config import load_settings


class LoadSettingsTest(unittest.TestCase):
    def test_reads_the_project_settings(self):
        self.assertIn("greeting", load_settings())

    def test_rejects_broken_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "settings.json"
            path.write_text("{ not json", encoding="utf-8")
            with self.assertRaises(ValueError):
                load_settings(path)


if __name__ == "__main__":
    unittest.main()
