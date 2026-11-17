# csvsum

Command line tool that summarizes one numeric column of a CSV file.

## Usage

```
python csvsum.py <file.csv> <column>
```

## Behaviour

- The CSV file has a header row. `<column>` is a column name from the header.
- Cells that are empty or contain only whitespace are skipped.
- All other cells of the column are numbers (integers or decimals).
- Print exactly one line to stdout: a JSON object with these keys:
  - `count`: number of values used
  - `sum`: sum of the values
  - `min`: smallest value
  - `max`: largest value
  - `mean`: sum divided by count
- If no values remain, print `{"count": 0, "sum": 0, "min": null, "max": null, "mean": null}`.
- If the column does not exist: print an error message to stderr and exit with code 2.
  Nothing is printed to stdout in that case.
- Use only the Python standard library.

## Example

```
python csvsum.py sample.csv price
{"count": 3, "sum": 36.5, "min": 4.5, "max": 20.0, "mean": 12.166666666666666}
```
