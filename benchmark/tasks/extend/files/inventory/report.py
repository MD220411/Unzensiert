"""Evaluations of the stock."""


def low_stock(store, threshold):
    """Return the sorted list of (item, quantity) with a quantity at or below the threshold."""
    return [(item, quantity) for item, quantity in store.items() if quantity <= threshold]
