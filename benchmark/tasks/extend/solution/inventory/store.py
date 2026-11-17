"""The stock of items per warehouse and its JSON file."""
import json
import os

FORMAT_VERSION = 2


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
    """Quantities per item and warehouse."""

    def __init__(self, default_warehouse="main"):
        self._default = normalize_name(default_warehouse)
        self._warehouses = {}

    def _warehouse(self, warehouse):
        """Return the normalized warehouse name, the default warehouse for None."""
        if warehouse is None:
            return self._default
        return normalize_name(warehouse)

    @classmethod
    def load(cls, path, default_warehouse="main"):
        """Read a store from a JSON file (old or new format). A missing file gives an empty store."""
        store = cls(default_warehouse)
        if not os.path.exists(path):
            return store
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        if "warehouses" in data:
            for warehouse, items in data["warehouses"].items():
                for item, quantity in items.items():
                    store.add(item, quantity, warehouse)
        else:
            for item, quantity in data.get("items", {}).items():
                store.add(item, quantity)
        return store

    def save(self, path):
        """Write the store to a JSON file in the format with warehouses."""
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"version": FORMAT_VERSION, "warehouses": self._warehouses}, handle, indent=2, sort_keys=True)

    def add(self, item, quantity, warehouse=None):
        """Add a quantity of an item to a warehouse (default warehouse if none is given)."""
        item = normalize_name(item)
        warehouse = self._warehouse(warehouse)
        check_quantity(quantity)
        items = self._warehouses.setdefault(warehouse, {})
        items[item] = items.get(item, 0) + quantity

    def remove(self, item, quantity, warehouse=None):
        """Remove a quantity of an item from one warehouse. Raises StockError if it holds too little."""
        item = normalize_name(item)
        warehouse = self._warehouse(warehouse)
        check_quantity(quantity)
        items = self._warehouses.get(warehouse, {})
        available = items.get(item, 0)
        if quantity > available:
            raise StockError(f"only {available} of {item} in {warehouse}")
        if quantity == available:
            del items[item]
            if not items:
                del self._warehouses[warehouse]
        else:
            items[item] = available - quantity

    def transfer(self, item, quantity, source, target):
        """Move a quantity of an item from one warehouse to another."""
        source = normalize_name(source)
        target = normalize_name(target)
        if source == target:
            raise ValueError("source and target must differ")
        self.remove(item, quantity, source)
        self.add(item, quantity, target)

    def stock(self, item, warehouse=None):
        """Return the quantity of an item in one warehouse, or the total without a warehouse."""
        item = normalize_name(item)
        if warehouse is None:
            return sum(items.get(item, 0) for items in self._warehouses.values())
        return self._warehouses.get(normalize_name(warehouse), {}).get(item, 0)

    def items(self, warehouse=None):
        """Return the sorted list of (item, quantity) of one warehouse, or the totals."""
        if warehouse is not None:
            return sorted(self._warehouses.get(normalize_name(warehouse), {}).items())
        totals = {}
        for items in self._warehouses.values():
            for item, quantity in items.items():
                totals[item] = totals.get(item, 0) + quantity
        return sorted(totals.items())

    def warehouses(self):
        """Return the sorted names of the warehouses that hold at least one item."""
        return sorted(self._warehouses)
