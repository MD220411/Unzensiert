# inventory

Small command line tool that keeps the stock of items in a JSON file.

## Requirements

Python 3.10 or newer, no further packages.

## Usage

```
python -m inventory <datafile> add <item> <quantity>
python -m inventory <datafile> remove <item> <quantity>
python -m inventory <datafile> stock <item>
python -m inventory <datafile> list
python -m inventory <datafile> low
```

- `add` and `remove` change the stock and save the file. A missing file is created.
- `stock` prints the quantity of one item, `list` prints all items as `item quantity`.
- `low` prints the items whose stock is at or below `lowStockThreshold` from `config.json`.
- Item names are trimmed and compared in lower case.
- Errors (for example removing more than is in stock) are printed to stderr as
  `error: <message>` and end the program with exit code 1.

## Layout

| Path | Purpose |
|---|---|
| `inventory/store.py` | the stock and its JSON file |
| `inventory/report.py` | evaluations of the stock |
| `inventory/config.py` | reads `config.json` |
| `inventory/__main__.py` | command line |
| `config.json` | settings |
| `tests/` | tests, run with `python -m unittest discover -s tests` |
| `docs/` | specifications of changes |

## Data file

```json
{"items": {"bolt": 12, "nut": 3}}
```
