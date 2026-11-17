# Checks the safety guard (scripts\hooks\Guard-Tool.ps1) against the cases in
# tests\guard-cases.json: every case is handed to the guard exactly as Claude Code does it
# (JSON on stdin of a new process), and the decision is compared with the expected one.
# Run after every change to config\guard.json or to the guard. Needs no graphics card.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Guard.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Guard.ps1 -ShowAll
#
# Exit code 0 = all cases as expected, 1 = at least one differs.

param([switch]$ShowAll)

. "$PSScriptRoot\_common.ps1"

$casesFile = Join-Path $script:ProjectRoot 'tests\guard-cases.json'
$set = Read-JsonFile $casesFile
# The cases are written for a fixed example machine ("machine" in the case file), so they
# give the same result on every computer: the guard (a child process) gets these folders
# instead of the real ones. {repo} in a case stands for this repository.
$env:CLAUDE_LOCAL_ROOT = [string]$set.machine.installRoot
$env:CLAUDE_LOCAL_PROJECTS = [string]$set.machine.projectsRoot
$failed = 0
$watch = [Diagnostics.Stopwatch]::StartNew()

foreach ($case in $set.cases) {
    $tool = 'Bash'
    if ($case.tool) { $tool = [string]$case.tool }
    $toolInput = [ordered]@{}
    foreach ($field in 'command', 'file_path', 'path') {
        if ($null -ne $case.$field) { $toolInput[$field] = ([string]$case.$field).Replace('{repo}', $script:ProjectRoot) }
    }
    $cwd = [string]$set.defaultCwd
    if ($case.cwd) { $cwd = [string]$case.cwd }
    $subject = @($toolInput.Values)[0]

    $got = Invoke-GuardHook $tool $toolInput $cwd
    $ok = ($got.decision -eq [string]$case.expect)
    if (-not $ok) { $failed++ }
    if ($ShowAll -or -not $ok) {
        $mark = 'ok  '
        if (-not $ok) { $mark = 'FAIL' }
        "$mark  expected $(([string]$case.expect).PadRight(4))  got $($got.decision.PadRight(4))  $($got.rule.PadRight(18))  $tool  $subject"
    }
}

$count = @($set.cases).Count
"guard: $($count - $failed) of $count cases as expected, $([int]($watch.ElapsedMilliseconds / $count)) ms per call"
if ($failed -gt 0) { exit 1 }
