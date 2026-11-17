# Checks the benchmark tasks themselves, without a model: for every task in
# config\benchmark.json the hidden check must fail on the untouched task files and, if the
# task has a reference solution (benchmark\tasks\<name>\solution\), pass on it with every
# working rule kept. Copies of the project tools in a task (check_facts.py, Check.ps1) must
# equal the project template. Run it after changing a task, benchmark\lib\rulecheck.py or
# the scripts in templates\projekt\gemeinsam\scripts\.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Tasks.ps1
#   ... -Only "ext*"     only tasks whose name matches
#   ... -Overlay projekt  with an overlay from benchmark\overlays\ laid over the task files
#
# Exit code 0 = all tasks are sound, 1 = at least one is not.

param(
    [string]$Only = '*',
    [string]$Overlay
)

. "$PSScriptRoot\_common.ps1"

$cfg = Get-BenchmarkConfig
$tasksRoot = Join-Path $script:ProjectRoot 'benchmark\tasks'
$workRoot = Join-Path $env:TEMP 'claude-local-task-test'
$failures = 0

foreach ($task in $cfg.tasks) {
    if ($task -notlike $Only) { continue }
    $taskDir = Join-Path $tasksRoot $task
    $problems = @()
    foreach ($needed in 'check.py', 'prompt.txt', 'files') {
        if (-not (Test-Path (Join-Path $taskDir $needed))) { $problems += "$needed is missing" }
    }
    $note = ''
    if (-not $problems) {
        # a fresh folder for every check (lib\Tasks.ps1)
        $workDir = Join-Path $workRoot "$task-template"
        New-TaskWorkCopy $taskDir $workDir -Overlay $Overlay
        $template = Invoke-TaskCheck $taskDir $workDir
        if ($template.pass) { $problems += 'the check passes on the untouched task files' }

        if (Test-Path (Join-Path $taskDir 'solution')) {
            $workDir = Join-Path $workRoot "$task-solution"
            New-TaskWorkCopy $taskDir $workDir -WithSolution -Overlay $Overlay
            $solved = Invoke-TaskCheck $taskDir $workDir
            if (-not $solved.pass) { $problems += "the check fails on the reference solution: $($solved.output)" }
            if ($solved.rules) {
                $broken = @($solved.rules.PSObject.Properties | Where-Object { -not $_.Value } | ForEach-Object { $_.Name })
                if ($broken) { $problems += "the reference solution breaks the rules: $($broken -join ', ')" }
                $note = "solution passes, $(@($solved.rules.PSObject.Properties).Count) rules kept"
            } else {
                $note = 'solution passes, task checks no rules'
            }
        } else {
            $note = 'no reference solution'
        }
    }
    if ($problems) {
        $failures++
        "FAIL  $task"
        foreach ($problem in $problems) { "        $problem" }
    } else {
        "ok    $task (template fails, $note)"
    }
}

# Tasks that carry the project tools (check command, facts check) must carry the current
# version from the project template, or they measure an old one.
$shared = Join-Path $script:ProjectRoot 'templates\projekt\gemeinsam\scripts'
foreach ($copy in @(Get-ChildItem -Path $tasksRoot -Recurse -File -Include 'check_facts.py', 'Check.ps1' | Where-Object { $_.FullName -match '\\(files|solution)\\scripts\\' })) {
    $source = Join-Path $shared $copy.Name
    $same = (Test-Path $source) -and ((Get-FileHash $source).Hash -eq (Get-FileHash $copy.FullName).Hash)
    $relative = $copy.FullName.Substring($tasksRoot.Length + 1)
    if ($same) { "ok    $relative is the template version" } else { $failures++; "FAIL  $relative differs from templates\projekt\gemeinsam\scripts\$($copy.Name)" }
}

if (Test-Path $workRoot) { Remove-Item -Path $workRoot -Recurse -Force -Confirm:$false }
if ($failures -gt 0) { "tasks: $failures with problems"; exit 1 }
'tasks: all sound.'
