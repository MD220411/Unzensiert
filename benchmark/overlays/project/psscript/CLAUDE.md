# Working on logtool

## Commands

```
powershell -ExecutionPolicy Bypass -File tests\Test-LogParser.ps1   # tests
powershell -ExecutionPolicy Bypass -File scripts\Check.ps1          # full check, run it before you report a task as done
```

## Where things go

- **Command:** `Get-LogSummary.ps1`; shared logic in `lib\`, one topic per file, pattern
  `lib\LogParser.ps1`. Every script starts with a comment saying what it is for.
- **Settings:** every fixed value (lists, limits, counts) is a key in
  `config\settings.json`, like `levels`. No such values in the scripts.
- **Tests:** `tests\Test-LogParser.ps1`. Every new function, parameter and error case gets
  a test there.
- **Documentation:** `README.md` describes every parameter, the output and the exit
  codes. Update it in the same step as the code.
- **Check:** `scripts\Check.ps1` runs the steps in `config\check.json`. Leave both as they are.

## Windows PowerShell 5.1

The scripts must run with `powershell.exe`. Try every case from the specification with
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File Get-LogSummary.ps1 ...` and look
at exit code, stdout and stderr separately before you report the task as done.
