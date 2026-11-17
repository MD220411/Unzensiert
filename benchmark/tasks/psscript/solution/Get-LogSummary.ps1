# Prints how many entries of each level a log file contains, optionally filtered by time
# and source, as text or JSON. Lines that are not log entries are skipped and counted.
#
#   powershell -ExecutionPolicy Bypass -File Get-LogSummary.ps1 -Path sample.log
#   ... -Since '2026-11-01 12:00:04'    only entries at or after this time
#   ... -Source db                      only entries of this source
#   ... -Format json                    JSON instead of text

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Since,
    [string]$Source,
    [ValidateSet('text', 'json')][string]$Format = 'text'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\LogParser.ps1"

function Stop-WithError([string]$Message) {
    # Usage errors go to stderr with exit code 2, stdout stays empty.
    [Console]::Error.WriteLine($Message)
    exit 2
}

$settings = Get-Content -Raw -Path "$PSScriptRoot\config\settings.json" | ConvertFrom-Json

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-WithError "Log file not found: $Path" }
$sinceTime = $null
if ($Since) {
    $sinceTime = ConvertTo-LogTime $Since
    if ($null -eq $sinceTime) { Stop-WithError "Invalid value for -Since (expected yyyy-MM-dd HH:mm:ss): $Since" }
}

$log = Read-LogFile $Path $settings.levels
$entries = @($log.Entries | Where-Object {
        ($null -eq $sinceTime -or $_.Time -ge $sinceTime) -and (-not $Source -or $_.Source -eq $Source)
    })

$levels = [ordered]@{}
foreach ($level in $settings.levels) {
    $levels[$level] = @($entries | Where-Object { $_.Level -eq $level }).Count
}

if ($Format -eq 'json') {
    $top = @($entries | Group-Object -Property Source |
            Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
            Select-Object -First ([int]$settings.topSources) |
            ForEach-Object { [ordered]@{ source = $_.Name; count = $_.Count } })
    [ordered]@{ total = $entries.Count; skipped = $log.Skipped; levels = $levels; topSources = $top } | ConvertTo-Json -Depth 5
} else {
    foreach ($level in $levels.Keys) { "$level $($levels[$level])" }
    if ($log.Skipped -gt 0) { "skipped: $($log.Skipped)" }
}
