# Working on inventory

## Commands

```
python -m unittest discover -s tests        # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1   # full check, run it before you report a task as done
```

## Where things go

- **Code:** `inventory/`, one module per job (layout table in `README.md`). New public
  functions get a docstring, like the ones in `inventory/store.py`.
- **Settings:** every fixed value (default names, limits, thresholds) is a key in
  `config.json` and is read through `inventory/config.py`, like `lowStockThreshold`. No such
  values as constants in the code.
- **Tests:** `tests/test_<module>.py`, pattern `tests/test_store.py`. Every new function,
  command and option gets tests in a test file.
- **Documentation:** `README.md` lists every command and option and describes the data
  file. Update it in the same step as the code.
- **Check:** `scripts\Check.ps1` runs the steps in `config\check.json`. Leave both as they are.
