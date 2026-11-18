# Architecture

## Goal

{{PURPOSE}}

## Modules

| Module | Job | Public interface |
|---|---|---|
| `{{PACKAGE}}\config.py` | reads `config\settings.json` | `load_settings()` |
| `{{PACKAGE}}\__main__.py` | entry point of the command line | `main(argv)` |

## Principles

- A module has one job. What other modules may use is in the table above; everything else
  is internal and begins with an underscore.
- Settings are in `config\`, not in the code.
- Decisions with their reasons: [decisions/](decisions/README.md).
