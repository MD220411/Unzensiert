"""Rules for orders shipped to Czechia (CZ): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of CZK (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_HALF_EVEN, Decimal

COUNTRY = "CZ"
NAME = "Czechia"
CURRENCY = "CZK"

# --- VAT -------------------------------------------------------------------------
# rate in percent per product category; categories not listed pay the standard rate
_VAT_RATES = {
    "general": 21,
    "food": 12,
    "books": 12,
    "ebooks": 21,
    "electronics": 21,
    "clothing": 21,
    "alcohol": 21,
    "tobacco": 21,
    "medicine": 12,
}


def vat_rate(category):
    """Return the VAT rate in percent for a product category."""
    return _VAT_RATES.get(category, 21)


def vat_cents(net_cents, category):
    """Return the VAT on a net amount. Czechia rounds to the nearest even cent on a tie."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_EVEN))


# --- shipping --------------------------------------------------------------------
# (heaviest parcel in grams, price in cents), lightest band first
SHIPPING_BANDS = (
    (1000, 9900),
    (5000, 14900),
    (20000, 24900),
)
# orders with at least this net value ship free; None = never
FREE_SHIPPING_FROM = 150000


def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if FREE_SHIPPING_FROM is not None and net_cents >= FREE_SHIPPING_FROM:
        return 0
    for limit, price in SHIPPING_BANDS:
        if weight_grams <= limit:
            return price
    raise ValueError("parcel too heavy for CZ")


# surcharge for remote regions by the beginning of the postal code: (region, cents)
REGION_SURCHARGES = {
}


def region_surcharge(postal_code):
    """Return the surcharge for a postal code; the longest matching beginning counts."""
    best = ""
    for prefix in REGION_SURCHARGES:
        if postal_code.startswith(prefix) and len(prefix) > len(best):
            best = prefix
    return REGION_SURCHARGES[best][1] if best else 0


# --- delivery --------------------------------------------------------------------
DELIVERY_DAYS = 3
EXPRESS_DELIVERY_DAYS = 1


def delivery_days(express=False):
    """Return the delivery time in working days."""
    return EXPRESS_DELIVERY_DAYS if express else DELIVERY_DAYS


# (month, day, name) of the public holidays without delivery
PUBLIC_HOLIDAYS = [
    (1, 1, "New Year"),
    (5, 8, "Liberation Day"),
    (10, 28, "Statehood Day"),
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
    "cod": 500000,
}


def payment_methods(net_cents):
    """Return the sorted payment methods offered for an order of this net value."""
    return sorted(method for method, limit in PAYMENT_LIMITS.items() if limit is None or net_cents <= limit)


# --- returns ---------------------------------------------------------------------
RETURN_DAYS = 14
# categories with their own return period
RETURN_DAYS_BY_CATEGORY = {}


def return_days(category):
    """Return the number of days a product of this category can be sent back."""
    return RETURN_DAYS_BY_CATEGORY.get(category, RETURN_DAYS)


def is_restricted(category):
    """Return True if products of this category are not shipped to this country."""
    return category in ()


# --- prices ----------------------------------------------------------------------
CURRENCY_SYMBOL = "Kc"
SYMBOL_FIRST = False
DECIMAL_SEPARATOR = ","
THOUSANDS_SEPARATOR = " "


def format_price(cents):
    """Return an amount as text the way it is written in this country."""
    whole, fraction = divmod(cents, 100)
    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)
    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"
    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"
