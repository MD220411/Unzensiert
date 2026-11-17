# Reads log files with lines of the form
#   2026-11-01 12:00:03 ERROR [db] Connection lost
# Dot-source this file, then call Read-LogFile.

function ConvertTo-LogTime([string]$Text) {
    # Returns the time for a text in the log format, $null if the text is not a valid time.
    $time = [datetime]::MinValue
    $style = [System.Globalization.DateTimeStyles]::None
    if ([datetime]::TryParseExact($Text, 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture, $style, [ref]$time)) { return $time }
    return $null
}

function ConvertFrom-LogLine([string]$Line, [string[]]$Levels) {
    # Turns one log line into an object with Time, Level, Source and Message.
    # Returns $null for a line that is no log entry or has a level outside $Levels.
    if ($Line -notmatch '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (\w+) \[([A-Za-z0-9._-]+)\] (.*)$') { return $null }
    $time = ConvertTo-LogTime $Matches[1]
    $level = $Matches[2].ToUpperInvariant()
    if ($null -eq $time -or ($Levels -and $Levels -notcontains $level)) { return $null }
    [pscustomobject]@{
        Time    = $time
        Level   = $level
        Source  = $Matches[3].ToLowerInvariant()
        Message = $Matches[4]
    }
}

function Read-LogFile([string]$Path, [string[]]$Levels) {
    # Returns Entries (in file order) and Skipped (number of lines that are no entries).
    $entries = @()
    $skipped = 0
    foreach ($line in (Get-Content -Path $Path)) {
        $entry = ConvertFrom-LogLine $line $Levels
        if ($null -eq $entry) { $skipped++ } else { $entries += $entry }
    }
    [pscustomobject]@{ Entries = $entries; Skipped = $skipped }
}
