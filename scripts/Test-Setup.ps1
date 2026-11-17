# Checks the project itself, without loading a model: are the configuration files valid
# and do they fit together, are all scripts readable for Windows PowerShell 5.1, are the
# files they point to in place, does the safety guard answer. Takes a few seconds; run it
# after every change to config\ or scripts\.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Setup.ps1
#
# Exit code 0 = everything in order, 1 = at least one check failed.

. "$PSScriptRoot\_common.ps1"

$script:Failures = 0
function Assert-That([bool]$Condition, [string]$What) {
    # Prints one result line; only failures are counted.
    if ($Condition) { "ok    $What" } else { $script:Failures++; "FAIL  $What" }
}

# --- 1. JSON files -------------------------------------------------------------------
$jsonFiles = @(Get-ChildItem -Path $script:ConfigDir -Filter '*.json') + @(Get-ChildItem -Path (Join-Path $script:ConfigDir 'styles') -Filter '*.json' -ErrorAction SilentlyContinue) +
    @(Get-ChildItem -Path (Join-Path $script:ProjectRoot 'tests') -Filter '*.json' -ErrorAction SilentlyContinue)
$jsonBroken = $false
foreach ($file in $jsonFiles) {
    $valid = $true
    try { $null = Read-JsonFile $file.FullName } catch { $valid = $false; $jsonBroken = $true }
    Assert-That $valid "valid JSON: $($file.Name)"
}
if ($jsonBroken) {
    "setup: $script:Failures check(s) failed. Fix the JSON files first, the other checks need them."
    exit 1
}

# --- 2. scripts ----------------------------------------------------------------------
# Windows PowerShell 5.1 reads files without BOM as ANSI, so anything beyond ASCII breaks.
$notAscii = @()
$syntax = @()
$scriptFiles = @(Get-ChildItem -Path (Join-Path $script:ProjectRoot 'scripts') -Filter '*.ps1' -Recurse) + @(Get-ChildItem -Path $script:ProjectRoot -Filter '*.ps1')
foreach ($file in $scriptFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 9 -and $_ -ne 10 -and $_ -ne 13) } | Select-Object -First 1) { $notAscii += $file.Name }
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { $syntax += "$($file.Name) line $($errors[0].Extent.StartLineNumber)" }
    # a comment whose "#" got lost shows up as a command named "\"
    if (@(Get-Content -Path $file.FullName) -match '^\s*\\\s') { $syntax += "$($file.Name) (line starts with a backslash)" }
}
Assert-That ($notAscii.Count -eq 0) "all .ps1 files are plain ASCII $($notAscii -join ', ')"
Assert-That ($syntax.Count -eq 0) "all .ps1 files parse $($syntax -join ', ')"

# --- 3. server -----------------------------------------------------------------------
$server = Get-ServerConfig
Assert-That (Test-Path $server.exe) "llama-server is installed: $($server.exe)"
Assert-That (Test-Path $server.modelsDir) "model folder exists: $($server.modelsDir)"
if ($server.requireApiKey) { Assert-That ((Get-ServerApiKey).Length -ge 32) 'server key is present (created on first use)' }

# --- 4. model profiles ---------------------------------------------------------------
# Not every profile is downloaded on every machine (scripts\Get-Model.ps1); a profile that
# is installed must be complete, and every profile must say where its files come from.
$profiles = Get-ModelNames
$machineFiles = @{}
foreach ($p in @((Get-MachineConfig).models.PSObject.Properties)) { if ($p.Value.file) { $machineFiles[$p.Name] = $true } }
foreach ($name in $profiles) {
    $model = Get-ModelProfile $name
    Assert-That (@('agent', 'autocomplete', 'compare') -contains $model.role) "profile $name`: role '$($model.role)' is agent, autocomplete or compare"
    if (Test-Path $model.path) {
        foreach ($key in 'mmproj', 'chat-template-file') {
            if ($model.args.Contains($key)) { Assert-That (Test-Path $model.args[$key]) "profile $name`: $key $(Split-Path -Leaf $model.args[$key])" }
        }
    } else {
        "note  profile $name is not installed on this machine"
    }
    # the download must bring the model file and the image encoder of the profile
    $files = @()
    try { $files = @(Get-ModelFiles $name) } catch {}
    $names = @($files | ForEach-Object { $_.name })
    $complete = $files.Count -gt 0 -and @($files | Where-Object { $_.size -le 0 -or $_.sha256 -notmatch '^[0-9a-f]{64}$' }).Count -eq 0
    if (-not $machineFiles[$name]) { $complete = $complete -and ($names -contains $model.file) }
    if ($model.args.Contains('mmproj')) { $complete = $complete -and ($names -contains (Split-Path -Leaf $model.args['mmproj'])) }
    Assert-That $complete "profile $name`: download entry names all its files with size and SHA-256"
}
Assert-That ([bool](Get-DefaultAgentModel)) "at least one agent model is installed (claude-local starts with '$(Get-DefaultAgentModel)')"

# --- 5. names that must be profiles ------------------------------------------------------
$agent = Get-AgentConfig
Assert-That ($profiles -contains [string]$agent.model) "agent.json: model '$($agent.model)' is a profile"
foreach ($alias in $agent.aliases.PSObject.Properties) { Assert-That ($profiles -contains [string]$alias.Value) "agent.json: alias '$($alias.Name)' points to a profile" }
foreach ($row in $agent.picker) { Assert-That ($profiles -contains [string]$row.model) "agent.json: picker entry '$($row.model)' is a profile" }
if ($agent.rulesFile) { Assert-That (Test-Path (Join-Path $script:ConfigDir ([string]$agent.rulesFile))) "agent.json: rules file $($agent.rulesFile) exists" }
Assert-That (@('unload', 'stop', 'keep') -contains [string]$agent.onExit) "agent.json: onExit '$($agent.onExit)' is unload, stop or keep"

foreach ($setup in (Get-Setups)) {
    $ok = ($profiles -contains [string]$setup.model) -and ((Get-ModelProfile ([string]$setup.model)).role -eq 'agent') -and $setup.args.'ctx-size'
    if ($setup.PSObject.Properties['alternative']) {
        $ok = $ok -and ($profiles -contains [string]$setup.alternative) -and ((Get-ModelProfile ([string]$setup.alternative)).role -eq 'agent')
    }
    Assert-That $ok "setups.json: setup '$($setup.name)' uses agent profiles ('$($setup.model)') and sets ctx-size"
}

$bench = Get-BenchmarkConfig
foreach ($name in $bench.models) { Assert-That ($profiles -contains [string]$name) "benchmark.json: model '$name' is a profile" }
foreach ($task in $bench.tasks) { Assert-That (Test-Path (Join-Path $script:ProjectRoot "benchmark\tasks\$task\check.py")) "benchmark.json: task '$task' has a check.py" }

$continue = Get-Content -Raw -Path (Join-Path $script:ConfigDir 'continue.config.yaml')
foreach ($m in [regex]::Matches($continue, '(?m)^\s+model:\s*(\S+)\s*$')) {
    Assert-That ($profiles -contains $m.Groups[1].Value) "continue.config.yaml: model '$($m.Groups[1].Value)' is a profile"
}
Assert-That ($continue -match "apiBase: $([regex]::Escape($server.baseUrl))") "continue.config.yaml: address matches server.json ($($server.baseUrl))"

# --- 6. safety guard -------------------------------------------------------------------
$guard = Get-GuardConfig
Assert-That (Test-Path (Get-GuardScript)) 'guard script exists'
foreach ($rule in $guard.commandRules) {
    $valid = $true
    try { $null = New-Object System.Text.RegularExpressions.Regex ([string]$rule.pattern) } catch { $valid = $false }
    Assert-That ($valid -and (@('ask', 'deny') -contains [string]$rule.decision)) "guard.json: rule '$($rule.id)' has a valid pattern and decision"
}
if ($guard.enabled) {
    $probe = Invoke-GuardHook 'Bash' @{ command = 'rm -rf /' } $script:ProjectRoot
    Assert-That ($probe.decision -eq 'deny') 'guard answers: "rm -rf /" is denied'
    $probe = Invoke-GuardHook 'Bash' @{ command = 'git status' } $script:ProjectRoot
    Assert-That ($probe.decision -eq 'none') 'guard answers: "git status" passes'
} else {
    'note  the safety guard is switched off ("enabled" in config\guard.json)'
}

# --- 7. closing check and commands -----------------------------------------------------
# The Stop hook is asked the way Claude Code does, with a made-up transcript in a scratch
# folder: no edit = silent, edit = reminder, failing check script = handed back.
if ($agent.stopCheck -and $agent.stopCheck.enabled) {
    Assert-That (Test-Path (Get-StopCheckScript)) 'closing check: hook script exists'
    $scratch = Join-Path $env:TEMP "claude-local-stopcheck-$PID"
    New-Item -ItemType Directory -Force -Path (Join-Path $scratch 'scripts') | Out-Null
    try {
        $transcript = Join-Path $scratch 'transcript.jsonl'
        $session = "setup-test-$PID"
        Set-Content -Path $transcript -Encoding ASCII -Value '{"type":"tool_use","name":"Read"}'
        $answer = Invoke-StopHook $session $transcript $scratch $false
        Assert-That ($answer.decision -eq '') 'closing check: silent after an answer without edits'
        Add-Content -Path $transcript -Encoding ASCII -Value '{"type":"tool_use","name":"Edit","input":{"file_path":"src/app.py"}}'
        $answer = Invoke-StopHook $session $transcript $scratch $false
        if ($agent.stopCheck.reminderFile) {
            Assert-That ($answer.decision -eq 'block' -and $answer.reason -match 'README') 'closing check: reminder after an edit'
            $answer = Invoke-StopHook $session $transcript $scratch $false
            Assert-That ($answer.decision -eq '') 'closing check: no second reminder without new edits'
        }
        if ($agent.stopCheck.reminderFile -and $agent.stopCheck.reminderPoints) {
            foreach ($file in 'src/app.py', 'README.md') {
                Add-Content -Path $transcript -Encoding ASCII -Value ('{"type":"tool_use","name":"Edit","input":{"file_path":"' + $file + '"}}')
            }
            $answer = Invoke-StopHook $session $transcript $scratch $false
            Assert-That ($answer.decision -eq 'block' -and $answer.reason -match 'Test:' -and $answer.reason -notmatch 'Dokumentation:') 'closing check: reminder leaves out the point that is done (README edited)'
            foreach ($file in 'src/app.py', 'README.md', 'tests/test_app.py', 'config/settings.json') {
                Add-Content -Path $transcript -Encoding ASCII -Value ('{"type":"tool_use","name":"Write","input":{"file_path":"' + $file + '"}}')
            }
            $answer = Invoke-StopHook $session $transcript $scratch $false
            Assert-That ($answer.decision -eq '') 'closing check: no reminder when code, test, README and settings were edited'
        }
        Set-Content -Path (Join-Path $scratch 'scripts\Check.ps1') -Encoding ASCII -Value "'planted failure'; exit 1"
        Add-Content -Path $transcript -Encoding ASCII -Value '{"type":"tool_use","name":"Write"}'
        $answer = Invoke-StopHook $session $transcript $scratch $true
        Assert-That ($answer.decision -eq 'block' -and $answer.reason -match 'planted failure') 'closing check: failing project check is handed back with its output'
        Set-Content -Path (Join-Path $scratch 'scripts\Check.ps1') -Encoding ASCII -Value "'fine'; exit 0"
        $answer = Invoke-StopHook $session $transcript $scratch $true
        Assert-That ($answer.decision -eq '') 'closing check: passing project check lets the model stop'
    } finally {
        Remove-Item -Recurse -Force -Path $scratch -ErrorAction SilentlyContinue
        Remove-Item -Force -Path (Join-Path $server.runDir "stop\$session.json") -ErrorAction SilentlyContinue
    }
    if ($agent.stopCheck.reminderFile) { Assert-That (Test-Path (Join-Path $script:ConfigDir ([string]$agent.stopCheck.reminderFile))) "agent.json: reminder file $($agent.stopCheck.reminderFile) exists" }

    # second look, without a model: what the reviewer would get and how its answer is read
    if ($agent.review -and $agent.review.enabled) {
        $review = $agent.review
        Assert-That ((Get-ModelNames) -contains (Resolve-ModelName ([string]$review.model))) "review: reviewer $($review.model) is a profile in models.json"
        Assert-That (Test-Path (Join-Path $script:ConfigDir ([string]$review.instructionsFile))) "review: instructions $($review.instructionsFile) exist"
        $found = ConvertFrom-ReviewAnswer "1. **FEHLER** | a.c:3 | off by one`nHINWEIS: b.md:1 | unclear`nsome prose`n- FEHLER | c.h:9 | wrong pin"
        Assert-That ($found.errors.Count -eq 2 -and $found.hints.Count -eq 1) 'review: answer split into 2 errors and 1 hint'
        Assert-That ((ConvertFrom-ReviewAnswer 'KEINE BEFUNDE').errors.Count -eq 0) 'review: KEINE BEFUNDE means no finding'

        $repo = Join-Path $env:TEMP "claude-local-review-$PID"
        New-Item -ItemType Directory -Force -Path $repo | Out-Null
        try {
            Assert-That ((Get-ChangeForReview $repo 1000).reason -eq 'no git repository') 'review: skipped outside a git repository'
            $null = Invoke-Git $repo @('init', '-q')
            Set-Content -Path (Join-Path $repo 'a.txt') -Value @('one', 'two', 'three') -Encoding ASCII
            $null = Invoke-Git $repo @('add', 'a.txt')
            $null = Invoke-Git $repo @('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'base')
            Set-Content -Path (Join-Path $repo 'a.txt') -Value @('one', 'TWO', 'three') -Encoding ASCII
            Set-Content -Path (Join-Path $repo 'neu.txt') -Value @('x', 'y') -Encoding ASCII
            $change = Get-ChangeForReview $repo 100000
            Assert-That ($change.ok -and $change.lines -eq 4 -and @($change.files).Count -eq 2 -and $change.diff -match '\+TWO' -and $change.diff -match '\+y') 'review: change = diff against HEAD plus new files (4 lines, 2 files)'
            $request = New-ReviewRequest $repo 'Aufgabe X' $change 100000
            Assert-That ($request -match 'Aufgabe X' -and $request -match '### neu\.txt') 'review: request has the task and the changed files in full'
            $fake = Join-Path $repo 'transcript.jsonl'
            Set-Content -Path $fake -Encoding ASCII -Value @(
                '{"type":"user","message":{"role":"user","content":"erste Aufgabe"}}',
                '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"zweite Aufgabe"}]}}',
                '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"output"}]}}',
                '{"type":"user","isMeta":true,"message":{"role":"user","content":"hook text"}}')
            Assert-That ((Get-LastUserPrompt $fake) -eq 'zweite Aufgabe') 'review: task = last prompt typed by the user'
        } finally {
            Remove-Item -Recurse -Force -Path $repo -ErrorAction SilentlyContinue
        }
        Assert-That (([int](Get-QualitySettings).hooks.Stop[0].hooks[0].timeout) -gt [int]$review.timeoutSeconds) 'review: the Stop hook may run longer than the second look'
    }
} else {
    'note  the closing check is switched off ("stopCheck" in config\agent.json)'
}
if ($agent.pluginDir) {
    Assert-That ((Get-PluginDir) -ne '') "agent.json: plugin folder config\$($agent.pluginDir) has a plugin.json"
    foreach ($file in @(Get-ChildItem -Path (Join-Path $script:ConfigDir "$($agent.pluginDir)\commands") -Filter '*.md')) {
        Assert-That ((Get-Content -Raw -Path $file.FullName -Encoding UTF8) -match '(?s)^---.*?description:.*?---') "command /$($file.BaseName) has a description"
    }
}

# --- 8. look ---------------------------------------------------------------------------
# config\style.json picks one of config\styles\ (docs\stil.md).
$selection = Get-StyleSelection
Assert-That (Test-Path (Get-StyleFile ([string]$selection.active))) "style.json: active style '$($selection.active)' has a file in config\styles"
$known = @(Get-KnownStyles)
Assert-That (@($known | ForEach-Object { $_.name } | Select-Object -Unique).Count -eq $known.Count) 'styles: names are unique'
Assert-That (@($known | ForEach-Object { $_.claude.themePrefix } | Select-Object -Unique).Count -eq $known.Count) 'styles: theme prefixes are unique'
foreach ($s in $known) {
    $modeNames = @($s.modes.PSObject.Properties | Where-Object { $_.Name -notlike '_*' } | ForEach-Object { $_.Name })
    $shellMode = [string]$s.shell.mode
    if (-not $shellMode) { $shellMode = 'werkbank' }
    $needed = @($shellMode, [string]$s.claude.localMode, [string]$s.claude.cloudMode)
    Assert-That (@($needed | Where-Object { $modeNames -notcontains $_ }).Count -eq 0) "style $($s.name): modes for shell, local and cloud ($($needed -join ', '))"
    Assert-That ($s.claude.themes.PSObject.Properties[[string]$s.claude.localMode] -and $s.claude.themes.PSObject.Properties[[string]$s.claude.cloudMode]) "style $($s.name): Claude Code themes for local and cloud"
    if ($s.PSObject.Properties['art']) {
        $font = $s.art.font
        $bad = @($font.PSObject.Properties | Where-Object {
            $rows = @($_.Value)
            $rows.Count -ne 5 -or @($rows | ForEach-Object { ([string]$_).Length } | Select-Object -Unique).Count -ne 1
        } | ForEach-Object { $_.Name })
        Assert-That ($bad.Count -eq 0) "style $($s.name): every letter of the art font has 5 rows of one width $($bad -join ' ')"
        $missing = @(([string]$s.art.text + [string]$s.art.bannerText).ToUpperInvariant().ToCharArray() | Where-Object { -not $font.PSObject.Properties[[string]$_] } | Select-Object -Unique)
        Assert-That ($missing.Count -eq 0) "style $($s.name): the art font has all letters of text and bannerText $($missing -join ' ')"
    }
}
$style = Get-StyleConfig
if ($style.PSObject.Properties['art']) {
    $bg = (Get-StyleMode (Get-ShellModeName)).background
    $wide = @(Get-CharArt ([string]$style.art.text) ([int]$style.art.scale) 160 $bg 7)
    $over = @($wide | Where-Object { (Get-VisibleLength $_) -gt 159 })
    Assert-That ($wide.Count -eq 7 -and $over.Count -eq 0) "art: picture of '$($style.art.text)' has 7 lines within 160 columns"
    Assert-That (@(Get-CharArt ([string]$style.art.text) ([int]$style.art.scale) 10 $bg 7).Count -eq 0) 'art: no picture when the window is too narrow'
}
Assert-That ((Get-VisibleLength (Format-Gauge 0.4 12 'rainbow' '#333333')) -eq 12) 'gauge: a gauge of width 12 is 12 characters wide'
# the status line reads JSON from stdin; a PowerShell pipe may send a byte order mark first
$sample = '{"model":{"display_name":"probe-model"},"context_window":{"used_percentage":42}}'
$line = $sample | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:ProjectRoot 'scripts\style\Statusline.ps1')
Assert-That (($line -join '') -match 'probe-model' -and ($line -join '') -match '42 %') 'status line: shows model and context from the JSON on stdin'

if ($script:Failures -gt 0) { "setup: $script:Failures check(s) failed."; exit 1 }
'setup: all checks passed. (Full guard cases: scripts\Test-Guard.ps1, a model: scripts\Test-Model.ps1)'
