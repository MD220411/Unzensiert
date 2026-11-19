# Talking to a person at the terminal: numbered steps, notes, warnings, yes/no questions.
# Used by Install.ps1 and Uninstall.ps1. A script sets $script:AssumeYes = $true to take
# every suggested answer without asking (switch -Yes). Keep this file ASCII-only.

$script:AssumeYes = $false
$script:StepNumber = 0

function Write-Step([string]$Text, [int]$Of) {
    $script:StepNumber++
    Write-Host ''
    Write-Host "[$script:StepNumber/$Of] $Text" -ForegroundColor Cyan
}

function Write-Note([string]$Text) { Write-Host "      $Text" }

function Write-Warn([string]$Text) { Write-Host "      ! $Text" -ForegroundColor Yellow }

function ConvertFrom-YesNo([string]$Answer, [bool]$Default) {
    # $true, $false or $null (not understood) for a typed answer; empty takes the default.
    # A slip like "#y" is not understood rather than taken as no (or as yes: the uninstaller
    # asks before deleting), so the question comes again.
    $text = ([string]$Answer).Trim()
    if (-not $text) { return $Default }
    if ($text -match '^(y|yes|j|ja)$') { return $true }
    if ($text -match '^(n|no|nein)$') { return $false }
    return $null
}

function Confirm-Step([string]$Question, [bool]$Default = $true) {
    # A yes/no question; Enter takes the default, an answer that is neither asks again.
    if ($script:AssumeYes) { return $Default }
    $hint = '[Y/n]'
    if (-not $Default) { $hint = '[y/N]' }
    while ($true) {
        $result = ConvertFrom-YesNo (Read-Host "      $Question $hint") $Default
        if ($null -ne $result) { return $result }
        Write-Host '      Please answer y (yes) or n (no).'
    }
}

function Read-Answer([string]$Question, [string]$Default) {
    # A question with a suggested answer; Enter takes it.
    if ($script:AssumeYes) { return $Default }
    $answer = ([string](Read-Host "      $Question [$Default]")).Trim()
    if ($answer) { return $answer }
    return $Default
}

function Assert-CanAsk {
    # Questions need a person; without one only -Yes can go on.
    if (-not $script:AssumeYes -and [Console]::IsInputRedirected) {
        throw 'This script asks questions. Start it in a terminal window, or add -Yes to take the suggested answers.'
    }
}

function Invoke-ProjectScript([string]$Name, [string[]]$Arguments = @(), [switch]$OnlyProblems) {
    # Runs a script from scripts\ in a process of its own (the scripts end with exit),
    # shows its output as notes and returns its exit code. -OnlyProblems hides the "ok"
    # lines of the test scripts.
    $file = Join-Path (Join-Path $script:ProjectRoot 'scripts') $Name
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file @Arguments |
        Where-Object { -not $OnlyProblems -or $_ -notmatch '^ok ' } |
        ForEach-Object { Write-Note $_ }
    return $LASTEXITCODE
}
