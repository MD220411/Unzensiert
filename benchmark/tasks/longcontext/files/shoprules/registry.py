"""The country modules by country code."""
from shoprules.countries import de, fr, it, es, nl, be, lu, at, pl, se, dk, fi, pt, cz, hu, gr, ch, no, ro, hr

COUNTRIES = {
    "DE": de,
    "FR": fr,
    "IT": it,
    "ES": es,
    "NL": nl,
    "BE": be,
    "LU": lu,
    "AT": at,
    "PL": pl,
    "SE": se,
    "DK": dk,
    "FI": fi,
    "PT": pt,
    "CZ": cz,
    "HU": hu,
    "GR": gr,
    "CH": ch,
    "NO": no,
    "RO": ro,
    "HR": hr,
}


def get(code):
    """Return the rule module of a country. Raises KeyError for an unknown code."""
    return COUNTRIES[code.upper()]
