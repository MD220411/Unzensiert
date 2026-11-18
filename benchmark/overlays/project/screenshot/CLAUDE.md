# Working on timesum

## Commands

```
python test_timesum.py        # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1   # full check, run it before you report a task as done
```

## Where things go

- **Code:** `timesum.py`. Public functions get a docstring.
- **Tests:** `test_timesum.py`. Every fixed bug and every new notation gets a test there.
- **Documentation:** the table of notations in `README.md` lists every accepted notation.
  Update it in the same step as the code.
- **Check:** `scripts\Check.ps1` runs the steps in `config\check.json`. Leave both as they are.
