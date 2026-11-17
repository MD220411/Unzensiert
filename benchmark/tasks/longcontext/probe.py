
import json, sys
from shoprules import registry
cats = ['general', 'food', 'books', 'ebooks', 'electronics', 'clothing', 'alcohol', 'tobacco', 'medicine'] + ["unknown"]
postal = ['00000', '0755', '2055', '2255', '2749855', '3555', '3855', '3955', '755', '8555', '8855', '9055', '91755', '955', '9555', '9755', '9855']
dates = [(1, 1), (2, 28), (3, 15), (3, 17), (3, 25), (4, 25), (4, 27), (5, 1), (5, 3), (5, 8), (5, 17), (5, 30), (6, 2), (6, 5), (6, 6), (6, 10), (6, 23), (7, 14), (7, 21), (8, 1), (8, 5), (8, 20), (10, 3), (10, 5), (10, 12), (10, 23), (10, 26), (10, 28), (11, 11), (12, 1), (12, 6), (12, 25), (12, 26)]
result = {}
def record(key, call, *args):
    try:
        result[key] = call(*args)
    except Exception as error:
        result[key] = type(error).__name__
for code in ['AT', 'BE', 'CH', 'CZ', 'DE', 'DK', 'ES', 'FI', 'FR', 'GR', 'HR', 'HU', 'IE', 'IT', 'LU', 'NL', 'NO', 'PL', 'PT', 'RO', 'SE']:
    try:
        rules = registry.get(code)
    except Exception as error:
        result[code + " module"] = "missing"
        continue
    for name in ("COUNTRY", "CURRENCY"):
        result[f"{code} {name}"] = getattr(rules, name, "missing")
    for c in cats:
        record(f"{code} vat_rate {c}", lambda: rules.vat_rate(c))
        record(f"{code} return_days {c}", lambda: rules.return_days(c))
        record(f"{code} is_restricted {c}", lambda: rules.is_restricted(c))
    for n in (1, 99, 1050, 3333, 12345):
        for c in ("general", "food", "books", "ebooks"):
            record(f"{code} vat_cents {n} {c}", lambda: rules.vat_cents(n, c))
    for w in (100, 2000, 2001, 20000, 20001, 25000, 25001, 30000, 30001):
        for n in (100, 5999, 6000, 7499, 7500, 10**9):
            record(f"{code} shipping_cents {w} {n}", lambda: rules.shipping_cents(w, n))
    for express in (False, True):
        record(f"{code} delivery_days {express}", lambda: rules.delivery_days(express))
    for n in (100, 20001, 30001, 50000, 50001, 100000, 100001, 10**9):
        record(f"{code} payment_methods {n}", lambda: rules.payment_methods(n))
    for n in (5, 123450, 100000000):
        record(f"{code} format_price {n}", lambda: rules.format_price(n))
    for p in postal:
        record(f"{code} region_surcharge {p}", lambda: rules.region_surcharge(p))
    for month, day in dates:
        record(f"{code} is_holiday {month}-{day}", lambda: rules.is_holiday(month, day))
json.dump(result, sys.stdout, sort_keys=True)
