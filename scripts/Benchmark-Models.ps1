# Benchmarks the model profiles listed in config\benchmark.json.
#
# Per profile it measures:
#   raw   - load time, answer speed, MTP acceptance, prompt reading speed, tool calling,
#           GPU memory
#   agent - the tasks in benchmark\tasks\ solved through claude-local, checked by a
#           hidden check.py (pass/fail, seconds, turns, output tokens) that also reports
#           which working rules the agent kept (line "RULES {json}", benchmark\lib\rulecheck.py)
#
# To compare settings (context size, GPU split, ...), add a second profile with the other
# values to config\models.json and list it in config\benchmark.json, or change the profile
# and give the run a new -Label.
#
# Results: logs\benchmark\results.jsonl (one JSON object per profile and label, append-only)
# Report:  docs\benchmark.md (regenerated on every run)
#
# The run is resumable: profiles already measured under the same label are skipped unless -Force.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Benchmark-Models.ps1
#   ... -Only "local-*"       only profiles whose name matches
#   ... -SkipAgent            raw measurements only
#   ... -Label split-70-30    name of the run
#   ... -Repeat 3             run every agent task three times
#   ... -Tasks planner        only these agent tasks (comma-separated), default: all in the config
#   ... -Overlay projekt      lay an overlay from benchmark\overlays\ over the task files
#                             (project notes and check command of a template project)
#   ... -Prefix /lokal:feature   put this in front of every task prompt (a command)
#   ... -Git                  work folders become git repositories with a first commit,
#                             so the second look of the closing check runs (it needs a diff)
#   ... -ReviewModel local-coder   reviewer of the second look for this run (default:
#                             "review" in config\agent.json)
#   ... -ExtraSeconds 300     add this to every task time limit (room for the second look)
#   ... -ReportOnly           just rebuild docs\benchmark.md
#
# While it runs the computer does not go to sleep on its own (SetThreadExecutionState; no
# system setting is changed, the request ends with the script).

param(
    [string]$Only = '*',
    [string]$Label = 'default',
    [int]$Repeat = 1,
    [string[]]$Tasks,
    [string]$Overlay,
    [string]$Prefix,
    [switch]$Git,
    [string]$ReviewModel,
    [int]$ExtraSeconds = 0,
    [switch]$SkipAgent,
    [switch]$Force,
    [switch]$ReportOnly
)

. "$PSScriptRoot\_common.ps1"

$cfg = Read-JsonFile (Join-Path $script:ConfigDir 'benchmark.json')
$benchDir = Join-Path $script:ProjectRoot 'logs\benchmark'
# Outside the repository on purpose: Claude Code reads CLAUDE.md files of all parent folders,
# so a work folder inside the repository would give the agent this project's instructions.
$workRoot = [string]$cfg.workDir
$resultsFile = Join-Path $benchDir 'results.jsonl'
$tasksRoot = Join-Path $script:ProjectRoot 'benchmark\tasks'
$launcher = Join-Path $PSScriptRoot 'claude-local.ps1'
$backendName = 'llama.cpp'
New-Item -ItemType Directory -Force -Path $benchDir, $workRoot | Out-Null

function Get-Results {
    if (-not (Test-Path $resultsFile)) { return @() }
    return @(Get-Content -Path $resultsFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-Backend($record) {
    # Records written before the move to llama.cpp have no "backend" field.
    if ($record.backend) { return [string]$record.backend }
    return 'Ollama'
}

function Measure-Raw([string]$model) {
    $r = [ordered]@{}
    Stop-AllModels
    $r.loadSec = Wait-ModelLoaded $model
    $r.gpuMemory = Get-GpuMemory

    $gen = Measure-Generation $model
    $r.genTps = $gen.genTps
    $r.draftAcceptance = $gen.draftAcceptance

    $prompt = Measure-PromptSpeed $model
    $r.promptTokens = $prompt.promptTokens
    $r.promptTps = $prompt.promptTps

    $tool = Test-ToolCall $model
    $r.toolOk = $tool.ok
    if (-not $tool.ok) { $r.toolError = $tool.detail }
    return $r
}

function Invoke-AgentTask([string]$model, [string]$task, [string]$workDir) {
    # Copies the task files to a work folder, lets claude-local solve the task there and
    # runs the task's check.py on the result.
    $taskDir = Join-Path $tasksRoot $task
    New-TaskWorkCopy $taskDir $workDir -Overlay $Overlay -Git:$Git
    $promptFile = Join-Path $taskDir 'prompt.txt'
    if ($Prefix) {
        $promptFile = "$workDir.prompt.txt"
        [System.IO.File]::WriteAllText($promptFile, "$Prefix " + (Get-Content -Raw -Path (Join-Path $taskDir 'prompt.txt') -Encoding UTF8))
    }

    $out = "$workDir.out.txt"
    $err = "$workDir.err.txt"
    $allowed = (@($cfg.allowedTools) | ForEach-Object { '"{0}"' -f $_ }) -join ' '
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Model {1} -OnExit keep -p --permission-mode acceptEdits --allowedTools {2} --output-format json' -f $launcher, $model, $allowed
    $timeoutSeconds = [int]$cfg.agentTimeoutSeconds
    if ($cfg.taskTimeoutSeconds -and $cfg.taskTimeoutSeconds.$task) { $timeoutSeconds = [int]$cfg.taskTimeoutSeconds.$task }
    $timeoutSeconds += $ExtraSeconds

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WorkingDirectory $workDir `
        -RedirectStandardInput $promptFile -RedirectStandardOutput $out -RedirectStandardError $err `
        -WindowStyle Hidden -PassThru
    $finished = $proc.WaitForExit($timeoutSeconds * 1000)
    if (-not $finished) { & cmd /c "taskkill /PID $($proc.Id) /T /F >nul 2>&1" }
    $seconds = [int]$sw.Elapsed.TotalSeconds

    $turns = $null
    $outTokens = $null
    if (Test-Path $out) {
        $jsonLine = Get-Content -Path $out | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            try {
                $answer = $jsonLine | ConvertFrom-Json
                $turns = $answer.num_turns
                if ($answer.modelUsage) {
                    $outTokens = 0
                    foreach ($usage in $answer.modelUsage.PSObject.Properties) { $outTokens += [int]$usage.Value.outputTokens }
                }
            } catch {}
        }
    }

    # the check also says which working rules the agent kept (lib\Tasks.ps1)
    $check = Invoke-TaskCheck $taskDir $workDir
    Set-Content -Path "$workDir.check.txt" -Value $check.output -Encoding utf8
    $result = [ordered]@{ pass = $check.pass; sec = $seconds; timeout = (-not $finished); turns = $turns; outTokens = $outTokens; rules = $check.rules; check = $check.output }
    $reviews = @(Get-ReviewLogEntries $workDir)
    if ($reviews) { $result.reviews = $reviews }
    return $result
}

function Get-ReviewLogEntries([string]$workDir) {
    # The second looks the closing check ran in this work folder (review.log, lib\Review.ps1).
    $log = Join-Path (Split-Path -Parent (Get-ServerConfig).logFile) 'review.log'
    if (-not (Test-Path $log)) { return @() }
    return @(Get-Content -Path $log -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $_ -and $_.folder -eq $workDir } | ForEach-Object {
            [ordered]@{ status = $_.status; lines = $_.lines; seconds = $_.seconds; errors = $_.errors; hints = $_.hints; model = $_.model }
        })
}

function Set-KeepAwake([bool]$On) {
    # Asks Windows not to sleep while the benchmark runs (ES_CONTINUOUS | ES_SYSTEM_REQUIRED);
    # off clears the request. Long runs were cut by sleep before (docs\protokoll.md).
    if (-not ('ClaudeLocal.Power' -as [type])) {
        Add-Type -Namespace ClaudeLocal -Name Power -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
    }
    $flags = [uint32]'0x80000000'
    if ($On) { $flags = [uint32]'0x80000001' }
    $null = [ClaudeLocal.Power]::SetThreadExecutionState($flags)
}

function Get-RuleQuote($runs) {
    # "kept / checked" over the rule results of the given runs, "-" if none was checked.
    $kept = 0
    $checked = 0
    foreach ($run in $runs) {
        if (-not $run.rules) { continue }
        foreach ($rule in $run.rules.PSObject.Properties) {
            $checked++
            if ($rule.Value) { $kept++ }
        }
    }
    if ($checked -eq 0) { return '-' }
    return "$kept / $checked ($([int](100 * $kept / $checked)) %)"
}

function Write-Report {
    $all = Get-Results
    # keep the newest record per backend + id + label
    $latest = @{}
    foreach ($x in $all) { $latest["$(Get-Backend $x)|$($x.id)|$($x.label)"] = $x }
    $rows = $latest.Values | Sort-Object @{e = { Get-Backend $_ } }, @{e = { $_.from } }, @{e = { $_.ctx } }, @{e = { $_.label } }

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('# Benchmark-Ergebnisse')
    $md.Add('')
    $md.Add('Automatisch erzeugt von `scripts\Benchmark-Models.ps1`. Nicht von Hand bearbeiten.')
    $md.Add("Stand: $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Rohdaten: ``logs\benchmark\results.jsonl``.")
    $md.Add('Zeilen mit Backend `Ollama` stammen aus der Zeit vor dem Umbau auf llama.cpp (bis 2026-11-14).')
    $md.Add('')
    $md.Add('## Rohwerte')
    $md.Add('')
    $md.Add('| Backend | Profil | Modell | Kontext | Lauf | GPU-Speicher | Laden | Antwort-Tempo | MTP-Treffer | Prompt-Tempo | Tool-Calls |')
    $md.Add('|---|---|---|---|---|---|---|---|---|---|---|')
    foreach ($x in $rows) {
        $tool = 'FEHLER'
        if ($x.raw.toolOk) { $tool = 'OK' }
        $memory = '-'
        if ($x.raw.gpuMemory) { $memory = "$($x.raw.gpuMemory) MiB" }
        elseif ($x.raw.sizeGB) { $memory = "$($x.raw.sizeGB) GB, $($x.raw.gpuPercent) % GPU" }
        $mtp = '-'
        if ($null -ne $x.raw.draftAcceptance) { $mtp = "$([int]([double]$x.raw.draftAcceptance * 100)) %" }
        $md.Add("| $(Get-Backend $x) | ``$($x.id)`` | ``$($x.from)`` | $([int]($x.ctx / 1024))k | $($x.label) | $memory | $($x.raw.loadSec) s | $($x.raw.genTps) Tok./s | $mtp | $($x.raw.promptTps) Tok./s | $tool |")
    }
    $md.Add('')
    $md.Add('## Agenten-Aufgaben (ueber claude-local)')
    $md.Add('')
    $md.Add('| Backend | Profil | Lauf | Bestanden | Summe Zeit | Regeln eingehalten |')
    $md.Add('|---|---|---|---|---|---|')
    foreach ($x in $rows) {
        if (-not $x.agent) { continue }
        $runs = @($x.agent)
        $passed = @($runs | Where-Object { $_.pass -and -not $_.timeout }).Count
        $sumSec = ($runs | Measure-Object -Property sec -Sum).Sum
        $md.Add("| $(Get-Backend $x) | ``$($x.id)`` | $($x.label) | $passed / $($runs.Count) | $sumSec s | $(Get-RuleQuote $runs) |")
    }
    $md.Add('')
    $md.Add('### Je Aufgabe')
    $md.Add('')
    $md.Add('| Backend | Profil | Lauf | Aufgabe | Bestanden | Laeufe | Regeln eingehalten |')
    $md.Add('|---|---|---|---|---|---|---|')
    $taskNames = @($cfg.tasks)
    foreach ($x in $rows) {
        if (-not $x.agent) { continue }
        # tasks of the config first, in their order; then tasks that are no longer listed
        $names = @($taskNames | Where-Object { $x.agent.task -contains $_ }) + @($x.agent.task | Select-Object -Unique | Where-Object { $taskNames -notcontains $_ })
        foreach ($t in $names) {
            $runs = @($x.agent | Where-Object { $_.task -eq $t })
            $passed = 0
            $parts = @()
            foreach ($run in $runs) {
                # a run that hit the time limit counts as failed, even if the files happen
                # to pass the check (the agent had not finished and might still break them)
                $word = 'nein'
                if ($run.timeout) {
                    $word = 'Zeit'
                    if ($run.pass) { $word = 'Zeit, Dateien ok' }
                } elseif ($run.pass) { $passed++; $word = 'ja' }
                $parts += "$word ($($run.sec) s)"
            }
            $md.Add("| $(Get-Backend $x) | ``$($x.id)`` | $($x.label) | $t | $passed / $($runs.Count) | $($parts -join ', ') | $(Get-RuleQuote $runs) |")
        }
    }
    $md.Add('')
    $md.Add('Legende: `ja` = Pruefung bestanden, `nein` = Ergebnis falsch, `Zeit` = Zeitlimit ueberschritten.')
    $md.Add('`Zeit, Dateien ok` = Zeitlimit ueberschritten, die Pruefung der Dateien waere aber bestanden; zaehlt als nicht bestanden.')
    $md.Add('')
    $md.Add('### Arbeitsregeln')
    $md.Add('')
    $md.Add('Wie oft der Agent eine Arbeitsregel aus `config\entwicklungsregeln.md` eingehalten hat, die der Auftrag nicht nennt.')
    $md.Add('Gezaehlt ueber alle Laeufe der Aufgaben, die die Regel pruefen (auch ueber nicht bestandene). `-` = nicht geprueft.')
    $md.Add('')
    $ruleNames = @('readme', 'tests', 'config', 'docstrings', 'headers', 'nodeadcode', 'fakten')
    $md.Add('| Backend | Profil | Lauf | ' + ($ruleNames -join ' | ') + ' |')
    $md.Add('|---|---|---|' + (($ruleNames | ForEach-Object { '---' }) -join '|') + '|')
    foreach ($x in $rows) {
        $runs = @($x.agent | Where-Object { $_.rules })
        if (-not $runs) { continue }
        $cells = @()
        foreach ($rule in $ruleNames) {
            $with = @($runs | Where-Object { $null -ne $_.rules.$rule })
            if (-not $with) { $cells += '-'; continue }
            $cells += "$(@($with | Where-Object { $_.rules.$rule }).Count) / $($with.Count)"
        }
        $md.Add("| $(Get-Backend $x) | ``$($x.id)`` | $($x.label) | " + ($cells -join ' | ') + ' |')
    }
    $md.Add('')
    $md.Add('`readme` = README angepasst, `tests` = Test fuer das Neue geschrieben, `config` = neue Einstellung in der Konfigurationsdatei statt im Code,')
    $md.Add('`docstrings` = neue oeffentliche Funktionen beschrieben, `headers` = neue Skripte mit Kopfkommentar, `nodeadcode` = kein auskommentierter Code,')
    $md.Add('`fakten` = neuer Fakt mit Quelle in facts/facts.json.')
    $md.Add('Die Bewertung dieser Zahlen steht in [modellwahl.md](modellwahl.md).')
    Set-Content -Path (Join-Path $script:ProjectRoot 'docs\benchmark.md') -Value $md -Encoding utf8
    "report written: docs\benchmark.md"
}

if ($ReportOnly) { Write-Report; exit 0 }

# the closing check runs in the agent's processes and reads the reviewer from there
if ($ReviewModel) { $env:CLAUDE_LOCAL_REVIEW_MODEL = Resolve-ModelName $ReviewModel }
Set-KeepAwake $true
Start-Server
$runTasks = @($cfg.tasks)
if ($Tasks) {
    $runTasks = @($Tasks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($t in $runTasks) { if ($cfg.tasks -notcontains $t) { throw "Task '$t' is not listed in config\benchmark.json." } }
}
$done = @{}
foreach ($x in (Get-Results)) { $done["$(Get-Backend $x)|$($x.id)|$($x.label)"] = $true }

foreach ($name in $cfg.models) {
    if ($name -notlike $Only) { continue }
    if ($done["$backendName|$name|$Label"] -and -not $Force) { "skip $name (already measured, label $Label)"; continue }
    $modelProfile = Get-ModelProfile $name
    if (-not (Test-Path $modelProfile.path)) { "skip $name ($($modelProfile.path) is missing)"; continue }

    "=== $name  ($(Split-Path -Leaf $modelProfile.path), label $Label)"
    $record = [ordered]@{
        id      = $name
        label   = $Label
        time    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        backend = $backendName
        build   = (Get-ServerConfig).build
        claudeCode = Get-ClaudeCodeVersion
        from    = (Split-Path -Leaf $modelProfile.path)
        ctx     = (Get-ModelContextSize $name)
        args    = $modelProfile.args
    }
    if ($Git) { $record.git = $true }
    if ($ReviewModel) { $record.reviewModel = $env:CLAUDE_LOCAL_REVIEW_MODEL }
    if ($ExtraSeconds) { $record.extraSeconds = $ExtraSeconds }
    try {
        $record.raw = Measure-Raw $name
        "  raw: load $($record.raw.loadSec)s, gen $($record.raw.genTps) t/s, prompt $($record.raw.promptTps) t/s, tools $($record.raw.toolOk), gpu $($record.raw.gpuMemory)"

        if (-not $SkipAgent) {
            $agent = @()
            foreach ($task in $runTasks) {
                for ($n = 1; $n -le $Repeat; $n++) {
                    $res = Invoke-AgentTask $name $task (Join-Path $workRoot "$name-$Label-$task-$n")
                    $res.task = $task
                    $agent += $res
                    "  agent $task #$n : pass=$($res.pass) sec=$($res.sec) timeout=$($res.timeout) turns=$($res.turns)"
                }
            }
            $record.agent = $agent
        }
    } catch {
        $record.error = $_.Exception.Message
        "  ERROR: $($record.error)"
    }

    Add-Content -Path $resultsFile -Value ($record | ConvertTo-Json -Depth 10 -Compress) -Encoding utf8
}

Set-KeepAwake $false
Write-Report
