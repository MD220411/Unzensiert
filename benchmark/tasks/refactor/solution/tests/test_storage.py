"""Tests for tracker.storage."""
import os
import tempfile
import unittest

from tracker import storage


class StorageTest(unittest.TestCase):
    def test_missing_file_and_round_trip(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "data.json")
            self.assertEqual(storage.load(path), {"tasks": [], "projects": [], "next_id": 1})
            storage.save(path, {"tasks": [], "projects": ["Büro"], "next_id": 1})
            self.assertEqual(storage.load(path)["projects"], ["Büro"])

    def test_failed_save_keeps_the_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "data.json")
            storage.save(path, storage.empty_database())
            with self.assertRaises(TypeError):
                storage.save(path, {"tasks": [object()]})
            self.assertEqual(os.listdir(folder), ["data.json"])

    def test_invalid_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "data.json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("{")
            with self.assertRaises(storage.StorageError):
                storage.load(path)


if __name__ == "__main__":
    unittest.main()
