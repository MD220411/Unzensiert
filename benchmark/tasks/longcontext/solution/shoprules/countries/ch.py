"""Rules for orders shipped to Switzerland (CH): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of CHF (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_HALF_UP, Decimal

COUNTRY = "CH"
NAME = "Switzerland"
CURRENCY = "CHF"

# --- VAT -------------------------------------------------------------------------
STANDARD_RATE = 8.1
REDUCED_RATE = 2.6
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
    """Return the VAT on a net amount. Switzerland rounds commercially (half up)."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


# --- shipping --------------------------------------------------------------------
# (heaviest parcel in grams, price in cents), lightest band first
SHIPPING_BANDS = (
    (2000, 900),
    (10000, 1200),
    (30000, 2100),
)
# orders with at least this net value ship free; None = never
FREE_SHIPPING_FROM = 10000


def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if FREE_SHIPPING_FROM is not None and net_cents >= FREE_SHIPPING_FROM:
        return 0
    for limit, price in SHIPPING_BANDS:
        if weight_grams <= limit:
            return price
    raise ValueError("parcel too heavy for CH")


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
DELIVERY_DAYS = 2
EXPRESS_DELIVERY_DAYS = 1


def delivery_days(express=False):
    """Return the delivery time in working days."""
    return EXPRESS_DELIVERY_DAYS if express else DELIVERY_DAYS


# (month, day, name) of the public holidays without delivery
PUBLIC_HOLIDAYS = [
    (1, 1, "New Year"),
    (8, 1, "National Day"),
    (12, 25, "Christmas Day"),
    (12, 26, "Second Christmas Day"),
]


def is_holiday(month, day):
    """Return True if nothing is delivered on this date."""
    return any((month, day) == (entry[0], entry[1]) for entry in PUBLIC_HOLIDAYS)


# --- payment ---------------------------------------------------------------------

def payment_methods(net_cents):
    """Return the sorted payment methods offered for an order of this net value."""
    methods = ['card', 'twint']
    if net_cents <= 100000:
        methods.append("invoice")
    return sorted(methods)


# --- returns ---------------------------------------------------------------------

def return_days(category):
    """Return the number of days a product of this category can be sent back."""
    return 14


def is_restricted(category):
    """Return True if products of this category are not shipped to this country."""
    return category in ()


# --- prices ----------------------------------------------------------------------
CURRENCY_SYMBOL = "CHF"
SYMBOL_FIRST = True
DECIMAL_SEPARATOR = "."
THOUSANDS_SEPARATOR = "'"


def format_price(cents):
    """Return an amount as text the way it is written in this country."""
    whole, fraction = divmod(cents, 100)
    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)
    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"
    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"
