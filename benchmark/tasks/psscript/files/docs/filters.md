# Change: filters, JSON output, tolerant reading

`Get-LogSummary.ps1` gets filters and a second output format, and it no longer stops at
lines it cannot read. It must keep running with Windows PowerShell 5.1 (`powershell.exe`).
Without the new parameters the output for a clean log file stays as it is.

## Reading

- A line that does not have the log format is skipped and counted. This includes empty
  lines. The script no longer stops at such a line.
- A source name may contain letters, digits, `-`, `.` and `_` (for example `auth-svc`,
  `cache.l2`). Sources are compared without regard to case and reported in lower case.
- Levels are read without regard to case and reported in upper case (`info` counts as
  `INFO`). A line whose level is not listed under `levels` in `config\settings.json` is
  skipped and counted like a malformed line.

## Parameters

- `-Since 'yyyy-MM-dd HH:mm:ss'`: only entries at or after this time are counted.
- `-Source <name>`: only entries of this source are counted.
- `-Format text|json`: output format, `text` if not given.
- Both filters can be combined. The number of skipped lines always refers to the whole
  file, whatever the filters are.

## Output

Format `text`: one line per level as before (all levels, also those with 0 entries, counted
after the filters). If lines were skipped, one more line follows: `skipped: <number>`.
Without skipped lines this line is absent.

Format `json`: one JSON document on stdout and nothing else, for example

```json
{
  "total": 7,
  "skipped": 1,
  "levels": {"ERROR": 2, "WARN": 1, "INFO": 4, "DEBUG": 0},
  "topSources": [
    {"source": "db", "count": 3},
    {"source": "auth-svc", "count": 2},
    {"source": "web", "count": 2}
  ]
}
```

- `total` is the number of entries after the filters.
- `levels` has every level from the settings.
- `topSources` lists the three sources with the most entries after the filters, ordered by
  count (highest first), sources with the same count by name (ascending). It is always a
  JSON array, also when it has one element or none.

## Errors

If the log file does not exist or the value of `-Since` is not a valid time in the format
above, the script writes a message to stderr, writes nothing to stdout and ends with exit
code 2.
