# Notes for working on {{NAME}}

## Commands

```
powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1     # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1       # check everything, before reporting done
```

## Where things belong

- **Scripts:** `scripts\`, one script per job, named `Verb-Noun.ps1`, header comment with
  purpose and usage. Pattern: `scripts\Show-Settings.ps1`.
- **Shared logic:** `scripts\lib\`, one topic per file, pattern `scripts\lib\Config.ps1`.
  No duplicated code.
- **Settings:** every fixed value (default name, limit, count, path) becomes a key in
  `config\settings.json` and is read with `Get-Settings`. New keys go into the table
  "Settings" of the README.
- **Tests:** `tests\Test-<Topic>.ps1` following the pattern of `tests\Test-Config.ps1`.
  Every new function and every fixed bug gets a test.
- **Documentation:** new scripts and parameters go into the README, new building blocks into
  `docs\architecture.md`, every change into `CHANGELOG.md` under "Unreleased".
- **Decisions:** when the structure, an interface, a file format or a dependency changes, a
  file `docs\decisions\NNNN-title.md` following `0000-template.md`.

## Check facts instead of guessing

Paths of other programs, names of cmdlets, parameters, registry keys and configuration keys,
limits: never from memory. Look in `facts\facts.json` first; if the fact is missing, look it
up with `Get-Help`, `Get-Command` or in the documentation and add it with its source; if it
cannot be confirmed, add it with `"status": "assumption"` and tell the user. Change a fact
only in `facts\facts.json`, then run `scripts\Check.ps1`: it names every file that still has
the old value. Format: `facts\README.md`.

## Windows PowerShell 5.1

- `.ps1` files ASCII-only, comments in English.
- Errors with an exit code: `[Console]::Error.WriteLine("...")`, then `exit <code>`.
- Force lists with `@(...)`, also before `.Count` and `ConvertTo-Json`.
- Suppress unwanted output with `$null = ...`.
