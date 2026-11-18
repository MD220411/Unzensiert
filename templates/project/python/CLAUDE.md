# Notes for working on {{NAME}}

## Commands

```
python -m {{PACKAGE}}                                        # start
python -m unittest discover -s tests -t .                   # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1  # check everything, before reporting done
```

## Where things belong

- **Code:** `{{PACKAGE}}\`, one module per job. A new module follows the pattern of
  `{{PACKAGE}}\config.py`: header comment, small public functions with a description.
- **Settings:** every fixed value (default name, limit, count, path) becomes a key in
  `config\settings.json` and is read through `{{PACKAGE}}.config.load_settings()`. New keys
  go into the table "Settings" of the README.
- **Tests:** `tests\test_<module>.py` following the pattern of `tests\test_config.py`. Every
  new function and every fixed bug gets a test.
- **Documentation:** new commands and options go into the README, new modules into
  `docs\architecture.md`, every change into `CHANGELOG.md` under "Unreleased".
- **Decisions:** when the structure, a public interface, a file format or a dependency
  changes, a file `docs\decisions\NNNN-title.md` following `0000-template.md` and a row in
  the table there.
- **Dependencies:** only when needed, with a pinned version in `requirements.txt`.

## Check facts instead of guessing

Pins, voltages, addresses, names of other programs' functions and configuration keys, limits
from datasheets: never from memory. Look in `facts\facts.json` first; if the fact is
missing, look it up in the datasheet, documentation or source code and add it with its
source; if it cannot be confirmed, add it with `"status": "assumption"` and tell the user.
Change a fact only in `facts\facts.json`, then run `scripts\Check.ps1`: it names every file
that still has the old value. Format: `facts\README.md`.
