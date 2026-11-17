"""Rules for orders shipped to Sweden (SE): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of SEK (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_HALF_UP, Decimal

COUNTRY = "SE"
NAME = "Sweden"
CURRENCY = "SEK"

# --- VAT -------------------------------------------------------------------------
# rate in percent per product category; categories not listed pay the standard rate
_VAT_RATES = {
    "general": 25,
    "food": 12,
    "books": 25,
    "ebooks": 25,
    "electronics": 25,
    "clothing": 25,
    "alcohol": 25,
    "tobacco": 25,
    "medicine": 25,
}


def vat_rate(category):
    """Return the VAT rate in percent for a product category."""
    return _VAT_RATES.get(category, 25)


def vat_cents(net_cents, category):
    """Return the VAT on a net amount. Sweden rounds commercially (half up)."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


# --- shipping --------------------------------------------------------------------
# (heaviest parcel in grams, price in cents), lightest band first
SHIPPING_BANDS = (
    (1000, 5900),
    (5000, 8900),
    (20000, 14900),
)
# orders with at least this net value ship free; None = never
FREE_SHIPPING_FROM = 50000


def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if FREE_SHIPPING_FROM is not None and net_cents >= FREE_SHIPPING_FROM:
        return 0
    for limit, price in SHIPPING_BANDS:
        if weight_grams <= limit:
            return price
    raise ValueError("parcel too heavy for SE")


# surcharge for remote regions by the beginning of the postal code: (region, cents)
REGION_SURCHARGES = {
    "98": ("Northern Norrland", 4900),
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
        return 1
    return 3


# (month, day, name) of the public holidays without delivery
PUBLIC_HOLIDAYS = [
    (1, 1, "New Year"),
    (6, 6, "National Day"),
    (12, 25, "Christmas Day"),
    (12, 26, "Second Christmas Day"),
]


def is_holiday(month, day):
    """Return True if nothing is delivered on this date."""
    return any((month, day) == (entry[0], entry[1]) for entry in PUBLIC_HOLIDAYS)


# --- payment ---------------------------------------------------------------------
# highest net value in cents a payment method accepts; None = no limit
PAYMENT_LIMITS = {
    "card": None,
    "swish": None,
    "invoice": 500000,
}


def payment_methods(net_cents):
    """Return the sorted payment methods offered for an order of this net value."""
    return sorted(method for method, limit in PAYMENT_LIMITS.items() if limit is None or net_cents <= limit)


# --- returns ---------------------------------------------------------------------

def return_days(category):
    """Return the number of days a product of this category can be sent back."""
    if category == "electronics":
        return 14
    return 14


def is_restricted(category):
    """Return True if products of this category are not shipped to this country."""
    return category in ('alcohol', 'tobacco')


# --- prices ----------------------------------------------------------------------
CURRENCY_SYMBOL = "kr"
SYMBOL_FIRST = False
DECIMAL_SEPARATOR = ","
THOUSANDS_SEPARATOR = " "


def format_price(cents):
    """Return an amount as text the way it is written in this country."""
    whole, fraction = divmod(cents, 100)
    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)
    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"
    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"
