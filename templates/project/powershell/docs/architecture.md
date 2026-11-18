# Architecture

## Goal

{{PURPOSE}}

## Scripts and building blocks

| File | Job | Public functions |
|---|---|---|
| `scripts\lib\Config.ps1` | reads `config\settings.json` | `Get-Settings` |
| `scripts\Show-Settings.ps1` | shows the settings | |
| `scripts\Check.ps1` | check command, steps in `config\check.json` | |

## Principles

- One script, one job. Shared logic lives in `scripts\lib\`, never twice.
- Settings are in `config\`, not in scripts.
- Scripts are repeatable: every run brings about the intended state.
- Decisions with their reasons: [decisions/](decisions/README.md).
