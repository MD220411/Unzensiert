"""Rules for orders shipped to Portugal (PT): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of EUR (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_HALF_UP, Decimal

COUNTRY = "PT"
NAME = "Portugal"
CURRENCY = "EUR"

# --- VAT -------------------------------------------------------------------------
STANDARD_RATE = 23
REDUCED_RATE = 6
REDUCED_CATEGORIES = ('food', 'books', 'medicine')
ZERO_RATED_CATEGORIES = ()


def vat_rate(category):
    """Return the VAT rate in percent for a product category."""
    if category in ZERO_RATED_CATEGORIES:
        return 0
    if category in REDUCED_CATEGORIES:
        return REDUCED_RATE
    return STANDARD_RATE


def vat_cents(net_cents, category):
    """Return the VAT on a net amount. Portugal rounds commercially (half up)."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


# --- shipping --------------------------------------------------------------------
# (heaviest parcel in grams, price in cents), lightest band first
SHIPPING_BANDS = (
    (2000, 590),
    (10000, 990),
    (20000, 1590),
)
# orders with at least this net value ship free; None = never
FREE_SHIPPING_FROM = 5000


def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if FREE_SHIPPING_FROM is not None and net_cents >= FREE_SHIPPING_FROM:
        return 0
    for limit, price in SHIPPING_BANDS:
        if weight_grams <= limit:
            return price
    raise ValueError("parcel too heavy for PT")


# surcharge for remote regions by the beginning of the postal code: (region, cents)
REGION_SURCHARGES = {
    "90": ("Madeira", 1500),
    "95": ("Azores", 1800),
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
    (4, 25, "Freedom Day"),
    (6, 10, "Portugal Day"),
    (10, 5, "Republic Day"),
    (12, 25, "Christmas Day"),
]


def is_holiday(month, day):
    """Return True if nothing is delivered on this date."""
    return any((month, day) == (entry[0], entry[1]) for entry in PUBLIC_HOLIDAYS)


# --- payment ---------------------------------------------------------------------

def payment_methods(net_cents):
    """Return the sorted payment methods offered for an order of this net value."""
    methods = ['card', 'paypal', 'mbway']
    if net_cents <= 100000:
        methods.append("invoice")
    return sorted(methods)


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
