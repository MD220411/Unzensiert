"""Check for the multifile task. Usage: python -I check.py <workdir>. Exit code 0 = passed."""
import pathlib
import subprocess
import sys

work = pathlib.Path(sys.argv[1])

hidden = r'''
from shop.cart import Cart
from shop.models import Product
from shop import pricing

def tax(n):
    return (n * 119 + 50) // 100

assert pricing.COUPONS["SAVE10"] == 10 and pricing.COUPONS["HALF"] == 50
assert pricing.apply_discount(2599, 10) == 2339
assert pricing.apply_discount(1000, 0) == 1000

cart = Cart()
cart.add(Product("A1", "Notebook", 1000), 2)
cart.add(Product("B2", "Pen", 599))
assert cart.subtotal_cents() == 2599
assert cart.total_cents() == tax(2599)

cart.apply_coupon("SAVE10")
assert cart.subtotal_cents() == 2599, "subtotal must stay undiscounted"
assert cart.total_cents() == tax(2339), cart.total_cents()

try:
    cart.apply_coupon("NOPE")
except ValueError:
    pass
else:
    raise AssertionError("unknown coupon must raise ValueError")
assert cart.total_cents() == tax(2339), "failed coupon must not change the cart"

cart.apply_coupon("HALF")
assert cart.total_cents() == tax(1299), cart.total_cents()
print("HIDDEN OK")
'''

run = subprocess.run([sys.executable, "-c", hidden], cwd=work, capture_output=True, text=True, timeout=30)
if run.returncode != 0 or "HIDDEN OK" not in run.stdout:
    print("FAIL: hidden cases\n" + run.stderr[-600:])
    sys.exit(1)

run = subprocess.run([sys.executable, "main.py"], cwd=work, capture_output=True, text=True, timeout=30)
if run.returncode != 0:
    print("FAIL: main.py crashes\n" + run.stderr[-600:])
    sys.exit(1)
if "3093" not in run.stdout or "2783" not in run.stdout:
    print("FAIL: main.py must print the total (3093) and the total with SAVE10 (2783)\n" + run.stdout[-300:])
    sys.exit(1)
print("PASS")
