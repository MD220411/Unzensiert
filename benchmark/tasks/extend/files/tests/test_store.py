"""Tests for inventory.store."""
import json
import os
import tempfile
import unittest

from inventory.store import StockError, Store


class StoreTest(unittest.TestCase):
    def test_add_and_stock(self):
        store = Store()
        store.add("Bolt", 5)
        store.add(" bolt ", 2)
        self.assertEqual(store.stock("BOLT"), 7)
        self.assertEqual(store.stock("nut"), 0)

    def test_invalid_input(self):
        store = Store()
        for item, quantity in [("", 1), ("  ", 1), ("bolt", 0), ("bolt", -1), ("bolt", 1.5), ("bolt", True)]:
            with self.assertRaises(ValueError):
                store.add(item, quantity)
        self.assertEqual(store.items(), [])

    def test_remove(self):
        store = Store()
        store.add("bolt", 5)
        store.remove("bolt", 2)
        self.assertEqual(store.stock("bolt"), 3)
        with self.assertRaises(StockError):
            store.remove("bolt", 4)
        self.assertEqual(store.stock("bolt"), 3)
        store.remove("bolt", 3)
        self.assertEqual(store.items(), [])

    def test_items_sorted(self):
        store = Store()
        store.add("nut", 1)
        store.add("bolt", 2)
        self.assertEqual(store.items(), [("bolt", 2), ("nut", 1)])

    def test_save_and_load(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "data.json")
            self.assertEqual(Store.load(path).items(), [])
            store = Store()
            store.add("bolt", 12)
            store.add("nut", 3)
            store.save(path)
            self.assertEqual(Store.load(path).items(), [("bolt", 12), ("nut", 3)])

    def test_load_existing_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "data.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump({"items": {"bolt": 12, "nut": 3}}, handle)
            store = Store.load(path)
            self.assertEqual(store.stock("bolt"), 12)
            self.assertEqual(store.items(), [("bolt", 12), ("nut", 3)])


if __name__ == "__main__":
    unittest.main()
