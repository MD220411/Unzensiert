# 0001: Project structure

Date: {{DATE}}

## Situation

The project begins. It should stay maintainable and extendable for years, even when a local
model writes most of the code.

## Decision

Fixed places: settings in `config\`, tests in `tests\`, documentation in `docs\`, decisions
in `docs\decisions\`. One check command for everything: `scripts\Check.ps1`, its steps are
in `config\check.json`. The git hook `.githooks\pre-commit` runs it before every commit.

## Reasons

Whoever looks for something finds it in the same place as in every other project made from
this template. A single check command is easy to remember, for people and models.

## Rejected

Settings as constants in the code: they would be scattered over the files and could only be
changed with a code change.
