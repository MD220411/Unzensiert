"""Tests for warehouses in inventory.store."""
import unittest

from inventory.store import StockError, Store


class WarehouseTest(unittest.TestCase):
    def test_totals_and_single_warehouse(self):
        store = Store()
        store.add("bolt", 12)
        store.add("bolt", 4, "north")
        self.assertEqual(store.stock("bolt"), 16)
        self.assertEqual(store.stock("bolt", "north"), 4)
        self.assertEqual(store.warehouses(), ["main", "north"])

    def test_transfer(self):
        store = Store()
        store.add("bolt", 12)
        with self.assertRaises(StockError):
            store.transfer("bolt", 13, "main", "north")
        with self.assertRaises(ValueError):
            store.transfer("bolt", 1, "main", "main")
        store.transfer("bolt", 12, "main", "north")
        self.assertEqual(store.warehouses(), ["north"])


if __name__ == "__main__":
    unittest.main()
