# Tests for scripts\lib\Config.ps1.
#
#   powershell -ExecutionPolicy Bypass -File tests\Test-Config.ps1
#
# Exit code 0 = all tests passed, 1 = at least one failed.

. "$PSScriptRoot\..\scripts\lib\Config.ps1"

$script:Failures = 0
function Assert-That([bool]$Condition, [string]$What) {
    # Prints one result line; only failures are counted.
    if ($Condition) { "ok    $What" } else { $script:Failures++; "FAIL  $What" }
}

Assert-That ([bool](Get-Settings).greeting) 'Get-Settings reads the project settings'

$broken = Join-Path $env:TEMP "settings-broken-$PID.json"
Set-Content -Path $broken -Encoding ASCII -Value '{ not json'
$message = ''
try { $null = Get-Settings $broken } catch { $message = $_.Exception.Message }
Remove-Item -Path $broken -Force
Assert-That ($message -match 'not valid JSON') 'Get-Settings rejects broken JSON with a clear message'

if ($script:Failures -gt 0) { exit 1 }
