# Tests for lib\LogParser.ps1 and Get-LogSummary.ps1. Exit code 0 = all passed.
#
#   powershell -ExecutionPolicy Bypass -File tests\Test-LogParser.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. "$root\lib\LogParser.ps1"

$failed = 0
function Assert-Equal($Expected, $Actual, [string]$Name) {
    if ("$Expected" -ne "$Actual") {
        "FAIL $Name : expected '$Expected', got '$Actual'"
        $script:failed++
    } else {
        "ok   $Name"
    }
}

$entry = ConvertFrom-LogLine '2026-11-01 12:00:03 error [DB] Connection lost' @('ERROR')
Assert-Equal 'ERROR' $entry.Level 'level'
Assert-Equal 'db' $entry.Source 'source'
Assert-Equal 'Connection lost' $entry.Message 'message'
Assert-Equal 3 $entry.Time.Second 'time'

$summary = & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Get-LogSummary.ps1" -Path "$root\sample.log"
Assert-Equal 'ERROR 1 WARN 1 INFO 3 DEBUG 1' ($summary -join ' ') 'summary of sample.log'

Assert-Equal '' (ConvertFrom-LogLine 'broken' @('ERROR')) 'malformed line'
$since = & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Get-LogSummary.ps1" -Path "$root\sample.log" -Since '2026-11-01 12:00:09' -Format json | ConvertFrom-Json
Assert-Equal 3 $since.total 'json with -Since'

if ($failed -gt 0) { exit 1 }
