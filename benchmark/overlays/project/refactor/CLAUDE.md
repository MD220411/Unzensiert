# Working on tracker

## Commands

```
python -m unittest discover -s tests        # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1   # full check, run it before you report a task as done
```

## Where things go

- **Code:** `tracker/`, one module per job (layout table in `README.md`). Every module
  starts with a docstring saying what it is for; public functions get a docstring.
- **Tests:** `tests/test_<module>.py`, pattern `tests/test_tracker.py`. A new module gets
  its own test file.
- **Documentation:** the layout table in `README.md` lists every module. Update it in the
  same step as the code.
- **Check:** `scripts\Check.ps1` runs the steps in `config\check.json`. Leave both as they are.
