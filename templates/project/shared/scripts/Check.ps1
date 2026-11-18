# The one check command of this project: runs every step listed in config\check.json
# (syntax, tests, linter) and fails if one of them fails. Run it before every commit; the
# git hook .githooks\pre-commit does so, and claude-local runs it when the model wants to
# report a task as done.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Check.ps1
#
# Exit code 0 = all steps passed, 1 = at least one failed. Steps marked "optional" are
# skipped when their tool ("needs") is not installed. Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$steps = @((Get-Content -Raw -Path (Join-Path $root 'config\check.json') -Encoding UTF8 | ConvertFrom-Json).steps)

function Test-PowerShellFiles {
    # Built-in step "powershell-syntax": every .ps1 file parses and is plain ASCII
    # (Windows PowerShell 5.1 reads files without BOM as ANSI).
    $problems = @()
    foreach ($file in @(Get-ChildItem -Path $root -Filter '*.ps1' -Recurse)) {
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { $problems += "$($file.Name) line $($errors[0].Extent.StartLineNumber): $($errors[0].Message)" }
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if (@($bytes | Where-Object { $_ -gt 126 }).Count -gt 0) { $problems += "$($file.Name): not plain ASCII" }
    }
    return $problems
}

$failed = 0
foreach ($step in $steps) {
    $name = [string]$step.name
    if ($step.needs -and -not (Get-Command ([string]$step.needs) -ErrorAction SilentlyContinue)) {
        if ($step.optional) { "skip  $name ($($step.needs) is not installed)"; continue }
        $failed++; "FAIL  $name ($($step.needs) is not installed)"; continue
    }
    if ($step.builtin -eq 'powershell-syntax') {
        $output = @(Test-PowerShellFiles)
        $ok = ($output.Count -eq 0)
    } else {
        $output = @(& cmd /c "$($step.command) 2>&1")
        $ok = ($LASTEXITCODE -eq 0)
    }
    if ($ok) { "ok    $name"; continue }
    $failed++
    "FAIL  $name"
    $output | Select-Object -Last 30 | ForEach-Object { "      $_" }
}

if ($failed -gt 0) { "check: $failed step(s) failed."; exit 1 }
'check: all steps passed.'
