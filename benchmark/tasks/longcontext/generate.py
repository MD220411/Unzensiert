"""Generates the longcontext task: a package with one rule module per country.

The modules share an interface but are written in different styles, so that a change
described in docs/changes-2027.md can only be applied after reading the module it concerns.
The same data, with the changes applied, gives the reference solution and the expected
probe results of the check.

    python generate.py            writes files/, solution/ and expected.json next to this file

Run it again after changing the data below; the output is deterministic.
"""
import copy
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
CATEGORIES = ["general", "food", "books", "ebooks", "electronics", "clothing", "alcohol", "tobacco", "medicine"]
ROUNDING = {"half_up": "ROUND_HALF_UP", "down": "ROUND_DOWN", "half_even": "ROUND_HALF_EVEN"}
ROUNDING_TEXT = {"half_up": "commercially (half up)", "down": "down", "half_even": "to the nearest even cent on a tie"}


def country(name, currency, std, red, reduced, zero, rounding, bands, free, days, pay, returns, fmt, restricted, regions, holidays):
    """One row of the country table."""
    return dict(name=name, currency=currency, std=std, red=red, reduced=reduced, zero=zero, rounding=rounding,
                bands=bands, free=free, days=days, pay=pay, returns=returns, fmt=fmt, restricted=restricted,
                regions=regions, holidays=holidays)


H = {(1, 1): "New Year", (12, 25): "Christmas Day", (12, 26): "Second Christmas Day", (5, 1): "Labour Day"}
COUNTRIES = {
    "DE": country("Germany", "EUR", 19, 7, ["food", "books"], [], "half_up",
                  [(1000, 490), (5000, 690), (20000, 1290), (31500, 1990)], 5000, (3, 1),
                  {"card": None, "paypal": None, "sepa": None, "invoice": 50000}, (14, {}), ("EUR", False, ",", "."), [],
                  {"27498": ("Heligoland", 1500)}, [(1, 1), (5, 1), (10, 3, "German Unity Day"), (12, 25), (12, 26)]),
    "FR": country("France", "EUR", 20, 5.5, ["food", "books"], [], "half_up",
                  [(500, 450), (2000, 750), (10000, 1350), (20000, 2100)], 6000, (4, 2),
                  {"card": None, "paypal": None, "invoice": 30000}, (14, {}), ("EUR", False, ",", " "), ["tobacco"],
                  {"20": ("Corsica", 900), "97": ("Overseas departments", 2500)}, [(1, 1), (5, 1), (7, 14, "Bastille Day"), (12, 25)]),
    "IT": country("Italy", "EUR", 22, 10, ["food"], [], "half_up",
                  [(2000, 690), (10000, 1190), (20000, 1890)], 8000, (5, 2),
                  {"card": None, "paypal": None, "cod": 20000}, (14, {"clothing": 30}), ("EUR", False, ",", "."), [],
                  {"07": ("Sardinia", 800), "9": ("Sicily", 600)}, [(1, 1), (4, 25, "Liberation Day"), (6, 2, "Republic Day"), (12, 25)]),
    "ES": country("Spain", "EUR", 21, 10, ["food", "books"], [], "half_up",
                  [(1000, 550), (5000, 850), (20000, 1500)], 5000, (4, 2),
                  {"card": None, "paypal": None, "invoice": 40000}, (14, {}), ("EUR", False, ",", "."), [],
                  {"35": ("Canary Islands", 2000), "38": ("Canary Islands", 2000), "07": ("Balearic Islands", 700)},
                  [(1, 1), (5, 1), (10, 12, "National Day"), (12, 25)]),
    "NL": country("Netherlands", "EUR", 21, 9, ["food", "books", "medicine"], [], "half_up",
                  [(2000, 595), (10000, 895), (23000, 1395)], 4000, (2, 1),
                  {"card": None, "paypal": None, "ideal": 50000, "invoice": 50000}, (14, {}), ("EUR", True, ",", "."), [],
                  {"88": ("Wadden Islands", 500)}, [(1, 1), (4, 27, "King's Day"), (12, 25), (12, 26)]),
    "BE": country("Belgium", "EUR", 21, 6, ["food", "books", "medicine"], [], "half_up",
                  [(2000, 650), (10000, 950), (30000, 1650)], 5000, (3, 1),
                  {"card": None, "paypal": None, "bancontact": None, "invoice": 25000}, (14, {}), ("EUR", True, ",", "."), ["alcohol"],
                  {}, [(1, 1), (5, 1), (7, 21, "National Day"), (12, 25)]),
    "LU": country("Luxembourg", "EUR", 17, 8, ["food", "books", "medicine"], [], "half_up",
                  [(2000, 700), (10000, 1100), (30000, 1800)], None, (3, 2),
                  {"card": None, "paypal": None, "invoice": 50000}, (14, {}), ("EUR", False, ",", "."), [],
                  {}, [(1, 1), (5, 1), (6, 23, "National Day"), (12, 25)]),
    "AT": country("Austria", "EUR", 20, 10, ["food", "books"], [], "half_up",
                  [(2000, 590), (10000, 990), (31500, 1790)], 6000, (3, 1),
                  {"card": None, "paypal": None, "eps": None, "invoice": 50000}, (14, {}), ("EUR", False, ",", "."), [],
                  {}, [(1, 1), (5, 1), (10, 26, "National Day"), (12, 25), (12, 26)]),
    "PL": country("Poland", "PLN", 23, 8, ["food", "medicine"], [], "half_up",
                  [(1000, 1290), (5000, 1690), (20000, 2490)], 20000, (3, 1),
                  {"card": None, "blik": None, "cod": 100000}, (14, {}), ("PLN", False, ",", " "), ["alcohol"],
                  {}, [(1, 1), (5, 3, "Constitution Day"), (11, 11, "Independence Day"), (12, 25), (12, 26)]),
    "SE": country("Sweden", "SEK", 25, 12, ["food"], [], "half_up",
                  [(1000, 5900), (5000, 8900), (20000, 14900)], 50000, (3, 1),
                  {"card": None, "swish": None, "invoice": 500000}, (14, {"electronics": 30}), ("kr", False, ",", " "), ["alcohol", "tobacco"],
                  {"98": ("Northern Norrland", 4900)}, [(1, 1), (6, 6, "National Day"), (12, 25), (12, 26)]),
    "DK": country("Denmark", "DKK", 25, 25, [], [], "down",
                  [(1000, 4500), (5000, 6500), (20000, 9900)], 49900, (2, 1),
                  {"card": None, "mobilepay": None, "invoice": 300000}, (14, {}), ("kr.", False, ",", "."), [],
                  {"39": ("Greenland", 25000)}, [(1, 1), (6, 5, "Constitution Day"), (12, 25), (12, 26)]),
    "FI": country("Finland", "EUR", 25.5, 14, ["food"], [], "half_up",
                  [(2000, 690), (10000, 1090), (25000, 1690)], 10000, (4, 2),
                  {"card": None, "paypal": None, "invoice": 50000}, (14, {}), ("EUR", False, ",", " "), ["alcohol"],
                  {"22": ("Aland", 1200)}, [(1, 1), (5, 1), (12, 6, "Independence Day"), (12, 25), (12, 26)]),
    "PT": country("Portugal", "EUR", 23, 6, ["food", "books", "medicine"], [], "half_up",
                  [(2000, 590), (10000, 990), (20000, 1590)], 5000, (4, 2),
                  {"card": None, "paypal": None, "mbway": None, "invoice": 20000}, (14, {}), ("EUR", False, ",", "."), [],
                  {"90": ("Madeira", 1500), "95": ("Azores", 1800)}, [(1, 1), (4, 25, "Freedom Day"), (6, 10, "Portugal Day"), (12, 25)]),
    "CZ": country("Czechia", "CZK", 21, 12, ["food", "books", "medicine"], [], "half_even",
                  [(1000, 9900), (5000, 14900), (20000, 24900)], 150000, (3, 1),
                  {"card": None, "cod": 500000}, (14, {}), ("Kc", False, ",", " "), [],
                  {}, [(1, 1), (5, 8, "Liberation Day"), (10, 28, "Statehood Day"), (12, 25), (12, 26)]),
    "HU": country("Hungary", "HUF", 27, 5, ["books", "medicine"], [], "half_up",
                  [(2000, 159000), (10000, 249000), (20000, 399000)], 2000000, (4, 2),
                  {"card": None, "cod": 5000000}, (14, {}), ("Ft", False, ",", " "), ["tobacco"],
                  {}, [(1, 1), (3, 15, "Revolution Day"), (8, 20, "State Foundation Day"), (10, 23, "Republic Day"), (12, 25)]),
    "GR": country("Greece", "EUR", 24, 13, ["food", "medicine"], [], "half_up",
                  [(2000, 750), (10000, 1250), (20000, 1950)], 7000, (5, 3),
                  {"card": None, "paypal": None, "cod": 30000}, (14, {}), ("EUR", False, ",", "."), [],
                  {"7": ("Crete", 700), "85": ("Dodecanese", 1100)}, [(1, 1), (3, 25, "Independence Day"), (10, 28, "Ohi Day"), (12, 25), (12, 26)]),
    "CH": country("Switzerland", "CHF", 8.1, 2.6, ["food", "books", "medicine"], [], "half_up",
                  [(2000, 900), (10000, 1200), (30000, 2100)], 10000, (2, 1),
                  {"card": None, "twint": None, "invoice": 100000}, (14, {}), ("CHF", True, ".", ""), [],
                  {}, [(1, 1), (8, 1, "National Day"), (12, 25), (12, 26)]),
    "NO": country("Norway", "NOK", 25, 15, ["food"], [], "half_up",
                  [(1000, 7900), (5000, 11900), (20000, 19900)], 100000, (3, 2),
                  {"card": None, "vipps": None, "invoice": 500000}, (14, {"electronics": 30}), ("kr", True, ",", " "), ["alcohol"],
                  {"917": ("Svalbard", 15000), "9": ("Northern Norway", 3000)}, [(1, 1), (5, 1), (5, 17, "Constitution Day"), (12, 25), (12, 26)]),
    "RO": country("Romania", "RON", 19, 9, ["food", "medicine"], [], "down",
                  [(1000, 1500), (5000, 2200), (20000, 3500)], 25000, (4, 2),
                  {"card": None, "cod": 300000}, (14, {}), ("lei", False, ",", "."), [],
                  {}, [(1, 1), (5, 1), (12, 1, "National Day"), (12, 25), (12, 26)]),
    "HR": country("Croatia", "EUR", 25, 5, ["books", "medicine"], [], "half_up",
                  [(2000, 650), (10000, 1050), (20000, 1650)], 6000, (4, 2),
                  {"card": None, "paypal": None, "invoice": 20000}, (14, {}), ("EUR", False, ",", "."), [],
                  {"20": ("Dalmatian islands", 600)}, [(1, 1), (5, 30, "Statehood Day"), (8, 5, "Victory Day"), (12, 25), (12, 26)]),
}
IRELAND = country("Ireland", "EUR", 23, 9, ["ebooks"], ["food", "books", "medicine"], "half_up",
                  [(2000, 750), (10000, 1250), (25000, 1950)], 6000, (4, 2),
                  {"card": None, "paypal": None, "invoice": 100000}, (14, {}), ("EUR", True, ".", ","), ["alcohol"],
                  {}, [(1, 1), (3, 17, "Saint Patrick's Day"), (12, 25), (12, 26, "Saint Stephen's Day")])
# style of each generated function, per country: (vat, shipping, days, payment, returns, restricted)
STYLES = {code: ((i % 2), (i // 2) % 2, (i % 3 == 0) * 1, (i + 1) % 2, (i // 3) % 2, (i % 4 < 2) * 1) for i, code in enumerate(COUNTRIES)}
# Ireland: the list of changes says a parcel that is too heavy is refused even when the
# order ships free, so the reference solution checks the weight first (shipping style 1)
STYLES["IE"] = (0, 1, 0, 0, 0, 0)


def apply_changes(countries):
    """Return the country table after the changes of docs/changes-2027.md."""
    after = copy.deepcopy(countries)
    after["DE"]["red"] = 5
    after["FR"]["free"] = 7500
    after["IT"]["bands"].append((30000, 2490))
    after["ES"]["days"] = (4, 1)
    after["NL"]["pay"]["ideal"] = None
    after["PL"]["std"] = 22
    after["SE"]["returns"] = (14, {"electronics": 14})
    after["AT"]["reduced"].append("ebooks")
    for row in after.values():
        if row["currency"] == "EUR" and "invoice" in row["pay"]:
            row["pay"]["invoice"] = 100000
    after["DK"]["rounding"] = "half_up"
    after["CH"]["fmt"] = ("CHF", True, ".", "'")
    after["BE"]["restricted"] = []
    after["LU"]["restricted"] = ["tobacco"]
    after["NO"]["regions"]["917"] = ("Svalbard", 19000)
    after["PT"]["holidays"].insert(3, (10, 5, "Republic Day"))
    after["IE"] = copy.deepcopy(IRELAND)
    return after


def holiday_rows(row):
    return [(entry[0], entry[1], entry[2] if len(entry) > 2 else H[(entry[0], entry[1])]) for entry in row["holidays"]]


def module_source(code, row, style):
    """Python source of one country module."""
    vat, ship, days, pay, returns, restricted = style
    name = row["name"]
    out = [f'"""Rules for orders shipped to {name} ({code}): VAT, shipping, delivery, payment, returns.',
           "",
           f"All amounts are in the smallest unit of {row['currency']} (cents). The functions of this module",
           "are the interface every country module has; shoprules.registry lists the modules.",
           '"""',
           "from decimal import " + ROUNDING[row["rounding"]] + ", Decimal",
           "",
           f'COUNTRY = "{code}"',
           f'NAME = "{name}"',
           f'CURRENCY = "{row["currency"]}"',
           ""]

    # --- VAT ---
    if vat == 0:
        out += ["# --- VAT -------------------------------------------------------------------------",
                f"STANDARD_RATE = {row['std']}",
                f"REDUCED_RATE = {row['red']}",
                f"REDUCED_CATEGORIES = {tuple(row['reduced'])!r}",
                f"ZERO_RATED_CATEGORIES = {tuple(row['zero'])!r}",
                "", "",
                "def vat_rate(category):",
                '    """Return the VAT rate in percent for a product category."""',
                "    if category in ZERO_RATED_CATEGORIES:",
                "        return 0",
                "    if category in REDUCED_CATEGORIES:",
                "        return REDUCED_RATE",
                "    return STANDARD_RATE",
                ""]
    else:
        out += ["# --- VAT -------------------------------------------------------------------------",
                "# rate in percent per product category; categories not listed pay the standard rate",
                "_VAT_RATES = {"]
        for category in CATEGORIES:
            rate = 0 if category in row["zero"] else row["red"] if category in row["reduced"] else row["std"]
            out.append(f'    "{category}": {rate},')
        out += ["}", "", "",
                "def vat_rate(category):",
                '    """Return the VAT rate in percent for a product category."""',
                f"    return _VAT_RATES.get(category, {row['std']})",
                ""]
    out += ["",
            "def vat_cents(net_cents, category):",
            f'    """Return the VAT on a net amount. {name} rounds {ROUNDING_TEXT[row["rounding"]]}."""',
            '    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)',
            f'    return int(amount.quantize(Decimal("1"), rounding={ROUNDING[row["rounding"]]}))',
            ""]

    # --- shipping ---
    out += ["", "# --- shipping --------------------------------------------------------------------"]
    heaviest = row["bands"][-1][0]
    if ship == 0:
        out += ["# (heaviest parcel in grams, price in cents), lightest band first",
                "SHIPPING_BANDS = ("]
        out += [f"    ({limit}, {price})," for limit, price in row["bands"]]
        out += [")",
                "# orders with at least this net value ship free; None = never",
                f"FREE_SHIPPING_FROM = {row['free']}",
                "", "",
                "def shipping_cents(weight_grams, net_cents):",
                '    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""',
                "    if FREE_SHIPPING_FROM is not None and net_cents >= FREE_SHIPPING_FROM:",
                "        return 0",
                "    for limit, price in SHIPPING_BANDS:",
                "        if weight_grams <= limit:",
                "            return price",
                f'    raise ValueError("parcel too heavy for {code}")',
                ""]
    else:
        out += ["", "def shipping_cents(weight_grams, net_cents):",
                '    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""',
                f"    if weight_grams > {heaviest}:",
                f'        raise ValueError("parcel too heavy for {code}")']
        if row["free"] is not None:
            out += [f"    if net_cents >= {row['free']}:",
                    "        return 0"]
        for limit, price in row["bands"][:-1]:
            out += [f"    if weight_grams <= {limit}:",
                    f"        return {price}"]
        out += [f"    return {row['bands'][-1][1]}", ""]

    out += ["",
            "# surcharge for remote regions by the beginning of the postal code: (region, cents)",
            "REGION_SURCHARGES = {"]
    out += [f'    "{prefix}": ("{region}", {cents}),' for prefix, (region, cents) in row["regions"].items()]
    out += ["}", "", "",
            "def region_surcharge(postal_code):",
            '    """Return the surcharge for a postal code; the longest matching beginning counts."""',
            "    best = \"\"",
            "    for prefix in REGION_SURCHARGES:",
            "        if postal_code.startswith(prefix) and len(prefix) > len(best):",
            "            best = prefix",
            "    return REGION_SURCHARGES[best][1] if best else 0",
            ""]

    # --- delivery ---
    out += ["", "# --- delivery --------------------------------------------------------------------"]
    if days == 0:
        out += [f"DELIVERY_DAYS = {row['days'][0]}",
                f"EXPRESS_DELIVERY_DAYS = {row['days'][1]}",
                "", "",
                "def delivery_days(express=False):",
                '    """Return the delivery time in working days."""',
                "    return EXPRESS_DELIVERY_DAYS if express else DELIVERY_DAYS",
                ""]
    else:
        out += ["", "def delivery_days(express=False):",
                '    """Return the delivery time in working days."""',
                "    if express:",
                f"        return {row['days'][1]}",
                f"    return {row['days'][0]}",
                ""]
    out += ["",
            "# (month, day, name) of the public holidays without delivery",
            "PUBLIC_HOLIDAYS = ["]
    out += [f'    ({month}, {day}, "{label}"),' for month, day, label in holiday_rows(row)]
    out += ["]", "", "",
            "def is_holiday(month, day):",
            '    """Return True if nothing is delivered on this date."""',
            "    return any((month, day) == (entry[0], entry[1]) for entry in PUBLIC_HOLIDAYS)",
            ""]

    # --- payment ---
    out += ["", "# --- payment ---------------------------------------------------------------------"]
    if pay == 0:
        out += ["# highest net value in cents a payment method accepts; None = no limit",
                "PAYMENT_LIMITS = {"]
        out += [f'    "{method}": {limit},' for method, limit in row["pay"].items()]
        out += ["}", "", "",
                "def payment_methods(net_cents):",
                '    """Return the sorted payment methods offered for an order of this net value."""',
                "    return sorted(method for method, limit in PAYMENT_LIMITS.items() if limit is None or net_cents <= limit)",
                ""]
    else:
        unlimited = [method for method, limit in row["pay"].items() if limit is None]
        out += ["", "def payment_methods(net_cents):",
                '    """Return the sorted payment methods offered for an order of this net value."""',
                f"    methods = {unlimited!r}"]
        for method, limit in row["pay"].items():
            if limit is not None:
                out += [f"    if net_cents <= {limit}:",
                        f'        methods.append("{method}")']
        out += ["    return sorted(methods)", ""]

    # --- returns ---
    out += ["", "# --- returns ---------------------------------------------------------------------"]
    default, overrides = row["returns"]
    if returns == 0:
        out += [f"RETURN_DAYS = {default}",
                "# categories with their own return period",
                f"RETURN_DAYS_BY_CATEGORY = {overrides!r}",
                "", "",
                "def return_days(category):",
                '    """Return the number of days a product of this category can be sent back."""',
                "    return RETURN_DAYS_BY_CATEGORY.get(category, RETURN_DAYS)",
                ""]
    else:
        out += ["", "def return_days(category):",
                '    """Return the number of days a product of this category can be sent back."""']
        for category, value in overrides.items():
            out += [f'    if category == "{category}":',
                    f"        return {value}"]
        out += [f"    return {default}", ""]
    if restricted == 0:
        out += ["",
                "# categories that are not shipped to this country",
                f"RESTRICTED_CATEGORIES = {tuple(row['restricted'])!r}",
                "", "",
                "def is_restricted(category):",
                '    """Return True if products of this category are not shipped to this country."""',
                "    return category in RESTRICTED_CATEGORIES",
                ""]
    else:
        out += ["", "def is_restricted(category):",
                '    """Return True if products of this category are not shipped to this country."""',
                f"    return category in {tuple(row['restricted'])!r}",
                ""]

    # --- prices ---
    symbol, first, decimal, thousands = row["fmt"]
    out += ["", "# --- prices ----------------------------------------------------------------------",
            f'CURRENCY_SYMBOL = "{symbol}"',
            f"SYMBOL_FIRST = {first}",
            f'DECIMAL_SEPARATOR = "{decimal}"',
            f'THOUSANDS_SEPARATOR = "{thousands}"',
            "", "",
            "def format_price(cents):",
            '    """Return an amount as text the way it is written in this country."""',
            "    whole, fraction = divmod(cents, 100)",
            '    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)',
            '    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"',
            '    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"',
            ""]
    return "\n".join(out)


def registry_source(codes):
    lines = ['"""The country modules by country code."""',
             "from shoprules.countries import " + ", ".join(code.lower() for code in codes),
             "",
             "COUNTRIES = {"]
    lines += [f'    "{code}": {code.lower()},' for code in codes]
    lines += ["}", "", "",
              "def get(code):",
              '    """Return the rule module of a country. Raises KeyError for an unknown code."""',
              "    return COUNTRIES[code.upper()]",
              ""]
    return "\n".join(lines)


def readme_source(countries):
    lines = ["# shoprules", "",
             "Rules of an online shop per destination country: VAT, shipping prices, delivery times,",
             "payment methods, return periods, restricted products and price formatting.", "",
             "## Requirements", "", "Python 3.10 or newer, no further packages.", "",
             "## Usage", "", "```python", "from shoprules import registry", "",
             'rules = registry.get("DE")', 'rules.vat_cents(1000, "food")', "rules.shipping_cents(1500, 4200)", "```", "",
             "Every country module offers the same functions: `vat_rate`, `vat_cents`, `shipping_cents`,",
             "`region_surcharge`, `delivery_days`, `is_holiday`, `payment_methods`, `return_days`,",
             "`is_restricted`, `format_price`. Amounts are integers in the smallest currency unit.",
             "Product categories: " + ", ".join(f"`{category}`" for category in CATEGORIES) + ".", "",
             "## Layout", "", "| Path | Purpose |", "|---|---|",
             "| `shoprules/countries/<code>.py` | rules of one country |",
             "| `shoprules/registry.py` | the country modules by code |",
             "| `tests/test_smoke.py` | tests, run with `python -m unittest discover -s tests` |",
             "| `docs/` | lists of rule changes to apply |", "",
             "## Countries", "", "| Code | Country | Currency |", "|---|---|---|"]
    lines += [f"| {code} | {row['name']} | {row['currency']} |" for code, row in countries.items()]
    return "\n".join(lines) + "\n"


TESTS = '''"""Smoke tests: every country module answers every function, plus fixed values for Germany."""
import unittest

from shoprules import registry


class SmokeTest(unittest.TestCase):
    def test_every_country_answers(self):
        for code, rules in registry.COUNTRIES.items():
            with self.subTest(country=code):
                self.assertEqual(rules.COUNTRY, code)
                self.assertGreaterEqual(rules.vat_cents(1000, "general"), 0)
                self.assertGreaterEqual(rules.shipping_cents(500, 100), 0)
                self.assertGreaterEqual(rules.region_surcharge("00000"), 0)
                self.assertGreater(rules.delivery_days(), 0)
                self.assertTrue(rules.is_holiday(1, 1))
                self.assertIn("card", rules.payment_methods(100))
                self.assertGreater(rules.return_days("general"), 0)
                self.assertIn(rules.is_restricted("alcohol"), (True, False))
                self.assertTrue(rules.format_price(123450))

    def test_germany(self):
        rules = registry.get("de")
        self.assertEqual(rules.vat_rate("general"), 19)
        self.assertEqual(rules.vat_rate("books"), 7)
        self.assertEqual(rules.vat_cents(1050, "food"), 74)
        self.assertEqual(rules.shipping_cents(1500, 4200), 690)
        self.assertEqual(rules.shipping_cents(1500, 5000), 0)
        self.assertEqual(rules.payment_methods(50001), ["card", "paypal", "sepa"])
        self.assertEqual(rules.format_price(123450), "1.234,50 EUR")


if __name__ == "__main__":
    unittest.main()
'''

CHANGES = '''# Rule changes for 2027

Apply every item below to the country modules. Amounts in this list are in whole currency
units (EUR 75 means 7500 cents in the code). Nothing else changes: all other rules of all
countries stay exactly as they are, and every module keeps the functions listed in the
README.

1. **Germany:** the reduced VAT rate falls from 7 % to 5 %.
2. **France:** shipping is free from a net order value of EUR 75 (so far EUR 60).
3. **Italy:** heavier parcels are accepted. A new weight band up to 30 kg costs EUR 24.90;
   parcels above 30 kg are still refused.
4. **Spain:** express delivery now takes 1 working day.
5. **Netherlands:** iDEAL is offered for orders of any value.
6. **Poland:** the standard VAT rate falls from 23 % to 22 %.
7. **Sweden:** electronics get the normal return period of 14 days.
8. **Austria:** e-books are taxed at the reduced rate.
9. **All countries that are billed in EUR:** where payment by invoice is offered, it is
   offered up to a net order value of EUR 1000. Countries with other currencies keep their
   invoice limits, and no country gains invoice as a new payment method by this item.
10. **Denmark:** VAT amounts are rounded commercially (half up) instead of down.
11. **Switzerland:** prices are written with an apostrophe as thousands separator
    (`CHF 1'234.50`).
12. **Belgium:** alcohol is no longer restricted. **Luxembourg:** tobacco becomes restricted.
13. **Norway:** the surcharge for Svalbard rises to NOK 190. The surcharge for the rest of
    Northern Norway stays.
14. **Portugal:** 5 October (Republic Day) becomes a public holiday without delivery.
15. **Ireland (IE) is added as a new country**, with a module of its own that is listed in
    the registry and offers the same functions as the others:
    - currency EUR; prices are written like `EUR 1,234.50` (symbol first, decimal point,
      comma as thousands separator)
    - VAT: standard rate 23 %; e-books 9 %; food, books and medicine 0 %; amounts are
      rounded commercially (half up)
    - shipping: up to 2 kg EUR 7.50, up to 10 kg EUR 12.50, up to 25 kg EUR 19.50; heavier
      parcels are refused with `ValueError`; orders from a net value of EUR 60 ship free
      (also in that case a parcel above 25 kg is refused); no regional surcharges
    - delivery in 4 working days, express in 2; public holidays: 1 January, 17 March
      (Saint Patrick's Day), 25 December, 26 December
    - payment: card and paypal for any value, invoice up to EUR 1000
    - returns: 14 days for every category
    - alcohol is restricted
'''

PROBE = r'''
import json, sys
from shoprules import registry
cats = %(cats)r + ["unknown"]
postal = %(postal)r
dates = %(dates)r
result = {}
def record(key, call, *args):
    try:
        result[key] = call(*args)
    except Exception as error:
        result[key] = type(error).__name__
for code in %(codes)r:
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
'''


def probe_script(countries):
    """Source of the script that asks every country module a fixed list of questions."""
    postal = sorted({prefix + "55" for row in countries.values() for prefix in row["regions"]} | {"00000"})
    dates = sorted({(entry[0], entry[1]) for row in countries.values() for entry in row["holidays"]} | {(2, 28)})
    return PROBE % dict(cats=CATEGORIES, postal=postal, dates=dates, codes=sorted(countries))


def write_tree(root, countries, changes_doc=True):
    """Write the whole project for a country table."""
    if root.exists():
        shutil.rmtree(root)
    (root / "shoprules" / "countries").mkdir(parents=True)
    (root / "tests").mkdir()
    (root / "docs").mkdir()

    def put(relative, text):
        (root / relative).write_text(text, encoding="utf-8", newline="\n")

    put("shoprules/__init__.py", '"""Rules of an online shop per destination country."""\n')
    put("shoprules/countries/__init__.py", '"""One module per destination country."""\n')
    for code, row in countries.items():
        put(f"shoprules/countries/{code.lower()}.py", module_source(code, row, STYLES[code]))
    put("shoprules/registry.py", registry_source(list(countries)))
    put("README.md", readme_source(countries))
    put("tests/test_smoke.py", TESTS)
    if changes_doc:
        put("docs/changes-2027.md", CHANGES)


def main():
    after = apply_changes(COUNTRIES)
    write_tree(HERE / "files", COUNTRIES)
    solved = HERE / "_solved"
    write_tree(solved, after)
    tests = (solved / "tests" / "test_smoke.py").read_text(encoding="utf-8")
    tests = tests.replace('rules.vat_rate("books"), 7)', 'rules.vat_rate("books"), 5)').replace('(1050, "food"), 74)', '(1050, "food"), 53)')
    tests = tests.replace('["card", "paypal", "sepa"])', '["card", "invoice", "paypal", "sepa"])')
    tests = tests.replace('if __name__', 'class IrelandTest(unittest.TestCase):\n    def test_ireland(self):\n        rules = registry.get("IE")\n'
                          '        self.assertEqual(rules.vat_rate("ebooks"), 9)\n        self.assertEqual(rules.format_price(123450), "EUR 1,234.50")\n\n\nif __name__', 1)
    (solved / "tests" / "test_smoke.py").write_text(tests, encoding="utf-8", newline="\n")

    # the solution folder holds only the files that differ from the task files
    solution = HERE / "solution"
    if solution.exists():
        shutil.rmtree(solution)
    for path in sorted(solved.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(solved)
        original = HERE / "files" / relative
        if not original.is_file() or original.read_bytes() != path.read_bytes():
            (solution / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, solution / relative)

    script = probe_script(after)
    (HERE / "probe.py").write_text(script, encoding="utf-8", newline="\n")
    # -B: leave no compiled files behind in the task files
    expected = subprocess.run([sys.executable, "-B", "-c", script], cwd=solved, capture_output=True, text=True, check=True).stdout
    before = subprocess.run([sys.executable, "-B", "-c", script], cwd=HERE / "files", capture_output=True, text=True, check=True).stdout
    (HERE / "expected.json").write_text(json.dumps(json.loads(expected), indent=0, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    shutil.rmtree(solved)

    old, new = json.loads(before), json.loads(expected)
    summary = {}
    for key in new:
        if old.get(key) != new[key]:
            code, function = key.split()[:2]
            summary.setdefault(f"{code} {function}", []).append(f"{' '.join(key.split()[2:])}: {old.get(key)!r} -> {new[key]!r}")
    print(f"{len(new)} probes, {sum(len(v) for v in summary.values())} differ from the task files:")
    for group, rows in summary.items():
        print(f"  {group} ({len(rows)}): " + "; ".join(rows[:3]))


if __name__ == "__main__":
    main()
