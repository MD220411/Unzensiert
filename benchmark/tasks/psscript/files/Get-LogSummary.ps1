# Prints how many entries of each level a log file contains.
#
#   powershell -ExecutionPolicy Bypass -File Get-LogSummary.ps1 -Path sample.log

param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\LogParser.ps1"

$settings = Get-Content -Raw -Path "$PSScriptRoot\config\settings.json" | ConvertFrom-Json
$entries = Get-LogEntries $Path
foreach ($level in $settings.levels) {
    $count = @($entries | Where-Object { $_.Level -eq $level }).Count
    "$level $count"
}
