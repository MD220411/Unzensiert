"""Tests for inventory.report."""
import unittest

from inventory.report import low_stock
from inventory.store import Store


class ReportTest(unittest.TestCase):
    def test_low_stock(self):
        store = Store()
        store.add("bolt", 12)
        store.add("nut", 5)
        store.add("washer", 1)
        self.assertEqual(low_stock(store, 5), [("nut", 5), ("washer", 1)])
        self.assertEqual(low_stock(store, 0), [])


if __name__ == "__main__":
    unittest.main()
