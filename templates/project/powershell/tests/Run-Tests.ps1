# Runs every tests\Test-*.ps1 and fails if one of them fails.
#
#   powershell -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
#
# Exit code 0 = all test files passed, 1 = at least one failed.

$failed = 0
foreach ($file in @(Get-ChildItem -Path $PSScriptRoot -Filter 'Test-*.ps1' | Sort-Object Name)) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file.FullName
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
if ($failed -gt 0) { "tests: $failed file(s) failed."; exit 1 }
'tests: all passed.'
