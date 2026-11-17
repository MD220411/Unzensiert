"""Rules for orders shipped to Spain (ES): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of EUR (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_HALF_UP, Decimal

COUNTRY = "ES"
NAME = "Spain"
CURRENCY = "EUR"

# --- VAT -------------------------------------------------------------------------
# rate in percent per product category; categories not listed pay the standard rate
_VAT_RATES = {
    "general": 21,
    "food": 10,
    "books": 10,
    "ebooks": 21,
    "electronics": 21,
    "clothing": 21,
    "alcohol": 21,
    "tobacco": 21,
    "medicine": 21,
}


def vat_rate(category):
    """Return the VAT rate in percent for a product category."""
    return _VAT_RATES.get(category, 21)


def vat_cents(net_cents, category):
    """Return the VAT on a net amount. Spain rounds commercially (half up)."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


# --- shipping --------------------------------------------------------------------

def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if weight_grams > 20000:
        raise ValueError("parcel too heavy for ES")
    if net_cents >= 5000:
        return 0
    if weight_grams <= 1000:
        return 550
    if weight_grams <= 5000:
        return 850
    return 1500


# surcharge for remote regions by the beginning of the postal code: (region, cents)
REGION_SURCHARGES = {
    "35": ("Canary Islands", 2000),
    "38": ("Canary Islands", 2000),
    "07": ("Balearic Islands", 700),
}


def region_surcharge(postal_code):
    """Return the surcharge for a postal code; the longest matching beginning counts."""
    best = ""
    for prefix in REGION_SURCHARGES:
        if postal_code.startswith(prefix) and len(prefix) > len(best):
            best = prefix
    return REGION_SURCHARGES[best][1] if best else 0


# --- delivery --------------------------------------------------------------------

def delivery_days(express=False):
    """Return the delivery time in working days."""
    if express:
        return 2
    return 4


# (month, day, name) of the public holidays without delivery
PUBLIC_HOLIDAYS = [
    (1, 1, "New Year"),
    (5, 1, "Labour Day"),
    (10, 12, "National Day"),
    (12, 25, "Christmas Day"),
]


def is_holiday(month, day):
    """Return True if nothing is delivered on this date."""
    return any((month, day) == (entry[0], entry[1]) for entry in PUBLIC_HOLIDAYS)


# --- payment ---------------------------------------------------------------------
# highest net value in cents a payment method accepts; None = no limit
PAYMENT_LIMITS = {
    "card": None,
    "paypal": None,
    "invoice": 40000,
}


def payment_methods(net_cents):
    """Return the sorted payment methods offered for an order of this net value."""
    return sorted(method for method, limit in PAYMENT_LIMITS.items() if limit is None or net_cents <= limit)


# --- returns ---------------------------------------------------------------------

def return_days(category):
    """Return the number of days a product of this category can be sent back."""
    return 14


# categories that are not shipped to this country
RESTRICTED_CATEGORIES = ()


def is_restricted(category):
    """Return True if products of this category are not shipped to this country."""
    return category in RESTRICTED_CATEGORIES


# --- prices ----------------------------------------------------------------------
CURRENCY_SYMBOL = "EUR"
SYMBOL_FIRST = False
DECIMAL_SEPARATOR = ","
THOUSANDS_SEPARATOR = "."


def format_price(cents):
    """Return an amount as text the way it is written in this country."""
    whole, fraction = divmod(cents, 100)
    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)
    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"
    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"
