"""Rules for orders shipped to France (FR): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of EUR (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_HALF_UP, Decimal

COUNTRY = "FR"
NAME = "France"
CURRENCY = "EUR"

# --- VAT -------------------------------------------------------------------------
# rate in percent per product category; categories not listed pay the standard rate
_VAT_RATES = {
    "general": 20,
    "food": 5.5,
    "books": 5.5,
    "ebooks": 20,
    "electronics": 20,
    "clothing": 20,
    "alcohol": 20,
    "tobacco": 20,
    "medicine": 20,
}


def vat_rate(category):
    """Return the VAT rate in percent for a product category."""
    return _VAT_RATES.get(category, 20)


def vat_cents(net_cents, category):
    """Return the VAT on a net amount. France rounds commercially (half up)."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


# --- shipping --------------------------------------------------------------------
# (heaviest parcel in grams, price in cents), lightest band first
SHIPPING_BANDS = (
    (500, 450),
    (2000, 750),
    (10000, 1350),
    (20000, 2100),
)
# orders with at least this net value ship free; None = never
FREE_SHIPPING_FROM = 7500


def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if FREE_SHIPPING_FROM is not None and net_cents >= FREE_SHIPPING_FROM:
        return 0
    for limit, price in SHIPPING_BANDS:
        if weight_grams <= limit:
            return price
    raise ValueError("parcel too heavy for FR")


# surcharge for remote regions by the beginning of the postal code: (region, cents)
REGION_SURCHARGES = {
    "20": ("Corsica", 900),
    "97": ("Overseas departments", 2500),
}


def region_surcharge(postal_code):
    """Return the surcharge for a postal code; the longest matching beginning counts."""
    best = ""
    for prefix in REGION_SURCHARGES:
        if postal_code.startswith(prefix) and len(prefix) > len(best):
            best = prefix
    return REGION_SURCHARGES[best][1] if best else 0


# --- delivery --------------------------------------------------------------------
DELIVERY_DAYS = 4
EXPRESS_DELIVERY_DAYS = 2


def delivery_days(express=False):
    """Return the delivery time in working days."""
    return EXPRESS_DELIVERY_DAYS if express else DELIVERY_DAYS


# (month, day, name) of the public holidays without delivery
PUBLIC_HOLIDAYS = [
    (1, 1, "New Year"),
    (5, 1, "Labour Day"),
    (7, 14, "Bastille Day"),
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
    "invoice": 100000,
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
    return category in ('tobacco',)


# --- prices ----------------------------------------------------------------------
CURRENCY_SYMBOL = "EUR"
SYMBOL_FIRST = False
DECIMAL_SEPARATOR = ","
THOUSANDS_SEPARATOR = " "


def format_price(cents):
    """Return an amount as text the way it is written in this country."""
    whole, fraction = divmod(cents, 100)
    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)
    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"
    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"
