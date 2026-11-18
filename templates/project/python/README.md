# {{NAME}}

{{PURPOSE}}

## Requirements

Python 3.10 or newer. Further packages: none (`requirements.txt`).

## Start

```
python -m {{PACKAGE}}
```

## Check

```
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
```

Runs every step of `config\check.json` (syntax, tests, linter if installed). The same
command runs before every commit.

## Structure

```
{{PACKAGE}}\      the code, one module per job
config\           settings: settings.json (program), check.json (check steps)
tests\            tests (unittest), one file test_<module>.py per module
scripts\          Check.ps1: the check command
docs\             architecture.md, decisions\
CHANGELOG.md      changes per version
CLAUDE.md         notes for working with a coding agent
```

## Settings

`config\settings.json`, read by `{{PACKAGE}}\config.py`:

| Key | Meaning |
|---|---|
| `greeting` | text the program prints at start (placeholder of the template) |

## Documentation

| File | Content |
|---|---|
| [docs/architecture.md](docs/architecture.md) | modules and their jobs |
| [docs/decisions/](docs/decisions/README.md) | decisions with their reasons |
| [CHANGELOG.md](CHANGELOG.md) | changes per version |
