# {{NAME}}

{{PURPOSE}}

## Requirements

Windows PowerShell 5.1 (`powershell.exe`), no further modules.

## Start

```
powershell -ExecutionPolicy Bypass -File scripts\Show-Settings.ps1
```

## Check

```
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
```

Runs every step of `config\check.json` (syntax and ASCII of all scripts, tests). The same
command runs before every commit.

## Structure

```
scripts\          one script per job; Check.ps1 is the check command
scripts\lib\      shared building blocks, one topic per file
config\           settings: settings.json (scripts), check.json (check steps)
tests\            tests: Test-<Topic>.ps1, started by Run-Tests.ps1
docs\             architecture.md, decisions\
CHANGELOG.md      changes per version
CLAUDE.md         notes for working with a coding agent
```

## Scripts

| Script | Purpose |
|---|---|
| `scripts\Show-Settings.ps1` | shows the settings (placeholder of the template) |
| `scripts\Check.ps1` | checks the project |

## Settings

`config\settings.json`, read through `Get-Settings` from `scripts\lib\Config.ps1`:

| Key | Meaning |
|---|---|
| `greeting` | text `Show-Settings.ps1` prints (placeholder of the template) |

## Documentation

| File | Content |
|---|---|
| [docs/architecture.md](docs/architecture.md) | scripts, building blocks and their jobs |
| [docs/decisions/](docs/decisions/README.md) | decisions with their reasons |
| [CHANGELOG.md](CHANGELOG.md) | changes per version |
