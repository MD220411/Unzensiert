# Working on shoprules

## Commands

```
python -m unittest discover -s tests        # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1   # full check, run it before you report a task as done
```

## Where things go

- **Code:** `shoprules/countries/<code>.py`, one module per country, all with the same
  functions; `shoprules/registry.py` lists them. The modules are written in different
  styles: keep the style of the module you change.
- **Tests:** `tests/test_smoke.py`. Every changed rule and every new country gets a test
  there.
- **Documentation:** the country table in `README.md` lists every country. Update it in
  the same step as the code.
- **Large jobs:** work through a list item by item and read only the modules the current
  item names; do not read all country modules at once.
- **Check:** `scripts\Check.ps1` runs the steps in `config\check.json`. Leave both as they are.
