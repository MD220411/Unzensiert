"""Rules for orders shipped to Romania (RO): VAT, shipping, delivery, payment, returns.

All amounts are in the smallest unit of RON (cents). The functions of this module
are the interface every country module has; shoprules.registry lists the modules.
"""
from decimal import ROUND_DOWN, Decimal

COUNTRY = "RO"
NAME = "Romania"
CURRENCY = "RON"

# --- VAT -------------------------------------------------------------------------
STANDARD_RATE = 19
REDUCED_RATE = 9
REDUCED_CATEGORIES = ('food', 'medicine')
ZERO_RATED_CATEGORIES = ()


def vat_rate(category):
    """Return the VAT rate in percent for a product category."""
    if category in ZERO_RATED_CATEGORIES:
        return 0
    if category in REDUCED_CATEGORIES:
        return REDUCED_RATE
    return STANDARD_RATE


def vat_cents(net_cents, category):
    """Return the VAT on a net amount. Romania rounds down."""
    amount = Decimal(net_cents) * Decimal(str(vat_rate(category))) / Decimal(100)
    return int(amount.quantize(Decimal("1"), rounding=ROUND_DOWN))


# --- shipping --------------------------------------------------------------------

def shipping_cents(weight_grams, net_cents):
    """Return the shipping price of a parcel. Raises ValueError if it is too heavy."""
    if weight_grams > 20000:
        raise ValueError("parcel too heavy for RO")
    if net_cents >= 25000:
        return 0
    if weight_grams <= 1000:
        return 1500
    if weight_grams <= 5000:
        return 2200
    return 3500


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

def delivery_days(express=False):
    """Return the delivery time in working days."""
    if express:
        return 2
    return 4


# (month, day, name) of the public holidays without delivery
PUBLIC_HOLIDAYS = [
    (1, 1, "New Year"),
    (5, 1, "Labour Day"),
    (12, 1, "National Day"),
    (12, 25, "Christmas Day"),
    (12, 26, "Second Christmas Day"),
]


def is_holiday(month, day):
    """Return True if nothing is delivered on this date."""
    return any((month, day) == (entry[0], entry[1]) for entry in PUBLIC_HOLIDAYS)


# --- payment ---------------------------------------------------------------------

def payment_methods(net_cents):
    """Return the sorted payment methods offered for an order of this net value."""
    methods = ['card']
    if net_cents <= 300000:
        methods.append("cod")
    return sorted(methods)


# --- returns ---------------------------------------------------------------------
RETURN_DAYS = 14
# categories with their own return period
RETURN_DAYS_BY_CATEGORY = {}


def return_days(category):
    """Return the number of days a product of this category can be sent back."""
    return RETURN_DAYS_BY_CATEGORY.get(category, RETURN_DAYS)


# categories that are not shipped to this country
RESTRICTED_CATEGORIES = ()


def is_restricted(category):
    """Return True if products of this category are not shipped to this country."""
    return category in RESTRICTED_CATEGORIES


# --- prices ----------------------------------------------------------------------
CURRENCY_SYMBOL = "lei"
SYMBOL_FIRST = False
DECIMAL_SEPARATOR = ","
THOUSANDS_SEPARATOR = "."


def format_price(cents):
    """Return an amount as text the way it is written in this country."""
    whole, fraction = divmod(cents, 100)
    digits = f"{whole:,}".replace(",", THOUSANDS_SEPARATOR)
    text = f"{digits}{DECIMAL_SEPARATOR}{fraction:02d}"
    return f"{CURRENCY_SYMBOL} {text}" if SYMBOL_FIRST else f"{text} {CURRENCY_SYMBOL}"
