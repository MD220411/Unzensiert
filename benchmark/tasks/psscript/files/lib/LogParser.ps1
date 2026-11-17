# Reads log files with lines of the form
#   2026-11-01 12:00:03 ERROR [db] Connection lost
# Dot-source this file, then call Get-LogEntries.

function ConvertFrom-LogLine([string]$Line) {
    # Turns one log line into an object with Time, Level, Source and Message.
    if ($Line -notmatch '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (\w+) \[(\w+)\] (.*)$') {
        throw "Malformed log line: $Line"
    }
    [pscustomobject]@{
        Time    = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        Level   = $Matches[2]
        Source  = $Matches[3]
        Message = $Matches[4]
    }
}

function Get-LogEntries([string]$Path) {
    # Returns the entries of a log file in file order.
    Get-Content -Path $Path | ForEach-Object { ConvertFrom-LogLine $_ }
}
