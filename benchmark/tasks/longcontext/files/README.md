# shoprules

Rules of an online shop per destination country: VAT, shipping prices, delivery times,
payment methods, return periods, restricted products and price formatting.

## Requirements

Python 3.10 or newer, no further packages.

## Usage

```python
from shoprules import registry

rules = registry.get("DE")
rules.vat_cents(1000, "food")
rules.shipping_cents(1500, 4200)
```

Every country module offers the same functions: `vat_rate`, `vat_cents`, `shipping_cents`,
`region_surcharge`, `delivery_days`, `is_holiday`, `payment_methods`, `return_days`,
`is_restricted`, `format_price`. Amounts are integers in the smallest currency unit.
Product categories: `general`, `food`, `books`, `ebooks`, `electronics`, `clothing`, `alcohol`, `tobacco`, `medicine`.

## Layout

| Path | Purpose |
|---|---|
| `shoprules/countries/<code>.py` | rules of one country |
| `shoprules/registry.py` | the country modules by code |
| `tests/test_smoke.py` | tests, run with `python -m unittest discover -s tests` |
| `docs/` | lists of rule changes to apply |

## Countries

| Code | Country | Currency |
|---|---|---|
| DE | Germany | EUR |
| FR | France | EUR |
| IT | Italy | EUR |
| ES | Spain | EUR |
| NL | Netherlands | EUR |
| BE | Belgium | EUR |
| LU | Luxembourg | EUR |
| AT | Austria | EUR |
| PL | Poland | PLN |
| SE | Sweden | SEK |
| DK | Denmark | DKK |
| FI | Finland | EUR |
| PT | Portugal | EUR |
| CZ | Czechia | CZK |
| HU | Hungary | HUF |
| GR | Greece | EUR |
| CH | Switzerland | CHF |
| NO | Norway | NOK |
| RO | Romania | RON |
| HR | Croatia | EUR |
