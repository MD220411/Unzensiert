"""The stock of items and its JSON file."""
import json
import os


class StockError(Exception):
    """Raised when more is removed than is in stock."""


def normalize_name(name):
    """Return the name trimmed and in lower case. An empty name raises ValueError."""
    if not isinstance(name, str) or not name.strip():
        raise ValueError("name must not be empty")
    return name.strip().lower()


def check_quantity(quantity):
    """Raise ValueError unless quantity is a positive integer."""
    if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity <= 0:
        raise ValueError("quantity must be a positive integer")


class Store:
    """Quantities per item."""

    def __init__(self):
        self._items = {}

    @classmethod
    def load(cls, path):
        """Read a store from a JSON file. A missing file gives an empty store."""
        store = cls()
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
            for item, quantity in data.get("items", {}).items():
                store.add(item, quantity)
        return store

    def save(self, path):
        """Write the store to a JSON file."""
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"items": self._items}, handle, indent=2, sort_keys=True)

    def add(self, item, quantity):
        """Add a quantity of an item."""
        item = normalize_name(item)
        check_quantity(quantity)
        self._items[item] = self._items.get(item, 0) + quantity

    def remove(self, item, quantity):
        """Remove a quantity of an item. Raises StockError if there is not enough."""
        item = normalize_name(item)
        check_quantity(quantity)
        available = self._items.get(item, 0)
        if quantity > available:
            raise StockError(f"only {available} of {item} in stock")
        if quantity == available:
            del self._items[item]
        else:
            self._items[item] = available - quantity

    def stock(self, item):
        """Return the quantity of an item, 0 if it is unknown."""
        return self._items.get(normalize_name(item), 0)

    def items(self):
        """Return the sorted list of (item, quantity)."""
        return sorted(self._items.items())
