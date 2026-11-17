from shop.cart import Cart
from shop.models import Product


def main():
    cart = Cart()
    cart.add(Product("A1", "Notebook", 1000), 2)
    cart.add(Product("B2", "Pen", 599))
    print("subtotal:", cart.subtotal_cents())
    print("total:", cart.total_cents())


if __name__ == "__main__":
    main()
