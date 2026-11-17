# logtool

Summarizes a log file on the command line. Runs with Windows PowerShell 5.1
(`powershell.exe`), no modules needed.

## Usage

```
powershell -ExecutionPolicy Bypass -File Get-LogSummary.ps1 -Path <logfile> [-Since 'yyyy-MM-dd HH:mm:ss'] [-Source <name>] [-Format text|json]
```

Prints one line per level with the number of entries, in the order of `levels` in
`config\settings.json`:

```
ERROR 1
WARN 1
INFO 3
DEBUG 1
```

`-Since` and `-Source` filter the entries, `-Format json` prints a JSON document with the
counts and the sources with the most entries (their number is `topSources` in the
settings). Lines that are no log entries are skipped and reported as `skipped: <number>`.
Details: `docs\filters.md`.

## Log format

```
2026-11-01 12:00:03 ERROR [db] Connection lost
```

Date and time, level, source in square brackets, message.

## Layout

| Path | Purpose |
|---|---|
| `Get-LogSummary.ps1` | the command |
| `lib\LogParser.ps1` | reads log lines |
| `config\settings.json` | settings |
| `tests\Test-LogParser.ps1` | tests, run with `powershell -ExecutionPolicy Bypass -File tests\Test-LogParser.ps1` |
| `docs\` | specifications of changes |
| `sample.log` | example |
