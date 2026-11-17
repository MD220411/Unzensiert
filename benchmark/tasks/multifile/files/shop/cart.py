from .models import Product
from .pricing import add_tax


class Cart:
    def __init__(self):
        self._quantities = {}
        self._products = {}

    def add(self, product: Product, quantity: int = 1):
        if quantity <= 0:
            raise ValueError("quantity must be positive")
        self._products[product.sku] = product
        self._quantities[product.sku] = self._quantities.get(product.sku, 0) + quantity

    def subtotal_cents(self):
        """Net amount of all items."""
        return sum(self._products[sku].price_cents * qty for sku, qty in self._quantities.items())

    def total_cents(self):
        """Gross amount to pay."""
        return add_tax(self.subtotal_cents())
