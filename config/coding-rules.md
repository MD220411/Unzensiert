# Working rules for software development

You develop software that is maintained and extended for years. Follow these rules in every
task. The conventions of the project at hand (CLAUDE.md, README, existing style) and explicit
wishes of the user take precedence.

## Before you write code

- Read the README, CLAUDE.md and the files concerned. Adopt the structure, style and naming
  of the project.
- In a new project you first decide on the structure (folders, modules, which part is
  responsible for what) and write it into the README. Only then comes the code.

## Structure

- A module has one job. When a file becomes hard to follow or gets a second job, split it.
- Settings (paths, ports, names, limits) belong in configuration files, not in the code.
- Shared logic lives in exactly one place. Do not copy code.
- Functions are short and named after what they do. Keep public interfaces small.
- Add new dependencies only when they are needed, and pin their version.

## Documentation

- Every project has a README with purpose, requirements, how to start it and the folder
  structure.
- Every file begins with a short comment that says what it is for. Public functions and
  classes get a description (docstring).
- Comments explain why something is done this way, not what the line does.
- When behaviour, an interface or the configuration changes, you update the documentation
  in the same step.
- Record important decisions with their reasons, for example in `docs/`.

## Check facts instead of guessing

- Pins, voltages, addresses, names of functions and configuration keys of other libraries
  and programs, limits from datasheets: never write them from memory. Look them up: in the
  project (`facts/facts.json`, datasheet, documentation), in the source code or headers of
  the library, with `--help`.
- If a value cannot be confirmed, say so explicitly and mark it as an assumption.
- If a value appears in several places (code, README, schematic), there is one source of
  truth. When it changes, you change the source and then search for every other place
  (`Grep` for the old value) before you report that you are done.

## Quality

- Write tests for new logic and for every fixed bug. Run them before you report the task as
  done.
- Report errors clearly, do not swallow them. Check input where it enters the program.
- Work in small, complete steps. Do not rebuild anything that is not part of the task.
- Passwords, keys and other secrets belong neither in the code nor in the repository.

## PowerShell scripts

Scripts must run with Windows PowerShell 5.1 (`powershell.exe`), not only with `pwsh`.

- Errors with an exit code: `[Console]::Error.WriteLine("...")`, then `exit <code>`.
  `Write-Error` and `throw` end with code 1 and write nothing useful to stderr.
- Everything a statement returns that is not assigned ends up in the output. Suppress what
  you do not want with `$null = ...` or `| Out-Null`.
- A list with exactly one entry becomes a single value, an empty one becomes `$null`. Force
  lists with `@(...)`, also before `.Count` and before `ConvertTo-Json`.
- Read files with `-Encoding UTF8`; keep `.ps1` files themselves ASCII-only.
- Before you report that you are done, run the script with
  `powershell.exe -NoProfile -File <script>`, including the error cases, and look at exit
  code, output and stderr separately.

## Finishing

- Check that the result works (tests, starting the program).
- Report briefly: what you changed, in which files, and what is still open.
