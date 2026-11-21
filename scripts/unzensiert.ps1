# Unzensiert: the coding agent of this project. It works in the current folder with a local
# model of llama-server - reads and changes files, runs commands - and needs no cloud and no
# other program. The guard (config\guard.json) checks every tool call, the closing check
# ("stopCheck" in config\agent.json) runs the tests of the project before the model reports
# "done". Settings: config\unzensiert.json, config\agent.json. Description: docs\unzensiert.md.
#
#   unzensiert                            conversation at the terminal
#   unzensiert "task"                     the same, starting with this request
#   unzensiert -Model schnell             another model (short name or profile name)
#   unzensiert -p "question"              one request without a terminal, the answer as text
#   unzensiert -p --output-format json    ... as one JSON line (the benchmark reads it)
#   unzensiert -c | --continue            continue the last conversation in this folder
#   unzensiert --resume [id]              continue an earlier one (without id: choose)
#   unzensiert --permission-mode edits    ask, edits, plan or all (Claude Code's names work too)
#   unzensiert --allowedTools "Bash(python:*)" ...   allowed without a question
#   unzensiert --max-turns 30             at most this many rounds of tool calls
#   unzensiert -OnExit keep               unload, stop or keep (default: "onExit" in agent.json)
#   unzensiert --version | --help
#   unzensiert --update                   look for a new release now and install it
#   unzensiert --updates on|off           automatic updates on this machine
#
# No param() block on purpose, like claude-local: PowerShell would take -p and the flags of
# Claude Code as its own. ConvertFrom-AgentArgs (lib\AgentRepl.ps1) splits the arguments.

. "$PSScriptRoot\_common.ps1"
$opt = ConvertFrom-AgentArgs $args
$positional = @($opt.positional)
$unknown = @($opt.unknown)

# the closing check (scripts\hooks\Check-Stop.ps1) names the agent in its messages
$env:CLAUDE_LOCAL_AGENT = 'Unzensiert'

if ($opt.version) { "Unzensiert $(Get-ProgramVersion)"; exit 0 }
if ($opt.help) {
    # the lines of the header that list the calls
    (Get-Content -Path $PSCommandPath -TotalCount 20 | Select-Object -Skip 6 | ForEach-Object { $_ -replace '^#\s?', '' }) -join "`n"
    exit 0
}
if ($opt.updates) {
    if ($opt.updates -match '^(on|an|ein|true|1|yes|ja)$') { $on = $true }
    elseif ($opt.updates -match '^(off|aus|false|0|no|nein)$') { $on = $false }
    else { [Console]::Error.WriteLine("unzensiert: --updates takes on or off, not '$($opt.updates)'"); exit 1 }
    Set-UpdatesEnabled $on
    $state = 'off'
    if ($on) { $state = 'on' }
    "unzensiert: automatic updates are $state on this machine (config\machine.json)."
    exit 0
}
if ($opt.update) { Invoke-UpdateCheck -Force; exit 0 }
foreach ($u in $unknown) { [Console]::Error.WriteLine("unzensiert: unknown option $u is ignored (--help lists the options)") }

$agent = Get-AgentConfig
$cfg = Get-AgentSettings
$server = Get-ServerConfig

# piped input without -p: one request, like -p
if (-not $opt.print -and [Console]::IsInputRedirected) { $opt.print = $true }
$interactive = -not $opt.print -and -not [Console]::IsOutputRedirected

function Write-LaunchNote([string]$Text) {
    # Notes before the session: in a -p run to stderr, so stdout holds only the answer.
    if ($opt.print) { [Console]::Error.WriteLine("unzensiert: $Text") } else { "unzensiert: $Text" }
}

# a new release: install it and start again with the new files (once)
if ($interactive -and -not $env:UNZENSIERT_UPDATED) {
    Invoke-UpdateCheck
    if ($script:ProgramUpdated) {
        $env:UNZENSIERT_UPDATED = '1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
        exit $LASTEXITCODE
    }
}

$start = Resolve-StartModel $opt.model
if ($start.problem) { [Console]::Error.WriteLine("unzensiert: $($start.problem)"); exit 1 }
$model = $start.model

# the terminal in the look of the style (lib\AgentUi.ps1); nothing of it in a -p run
$savedEncoding = [Console]::OutputEncoding
if ($opt.print) { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }
Initialize-AgentUi $interactive ([bool]$cfg.showThinking)

if (-not (Test-ServerUp)) {
    if ($script:Ui.on) { Write-UiNote (Get-UiText 'notes.serverStarting') 'warn' }
    else { Write-LaunchNote 'llama-server is not running, starting it ...' }
    foreach ($line in @(Start-Server)) { if ($line) { if ($script:Ui.on) { Write-UiNote ([string]$line) } else { Write-LaunchNote ([string]$line) } } }
}

# --- the session --------------------------------------------------------------------------
$cwd = (Get-Location).ProviderPath
$session = New-AgentSession $cwd $model
if ($opt.mode) {
    $mode = ConvertTo-PermissionMode $opt.mode
    if (-not $mode) { [Console]::Error.WriteLine("unzensiert: unknown permission mode '$($opt.mode)' (ask, edits, plan, all)"); [Console]::OutputEncoding = $savedEncoding; exit 1 }
    $session.mode = $mode
}
if (-not (ConvertTo-PermissionMode $session.mode)) { $session.mode = 'ask' }
$session.allowedTools = @($opt.allowed)
$session.maxTurns = $opt.maxTurns
Initialize-AgentSession $session

$continued = $null
if ($opt.continue) {
    $last = @(Get-SessionFiles $cwd) | Select-Object -First 1
    if ($last) { Import-AgentSession $session $last.file; $continued = $last.time }
    else { Write-LaunchNote 'there is no earlier conversation in this folder, starting a new one' }
} elseif ($null -ne $opt.resume) {
    $file = ''
    if ($opt.resume) {
        $file = Join-Path $session.folder "$($opt.resume).jsonl"
        if (-not (Test-Path $file)) { [Console]::Error.WriteLine("unzensiert: no conversation $($opt.resume) in this folder"); [Console]::OutputEncoding = $savedEncoding; exit 1 }
    } elseif ($interactive) {
        $file = Select-SessionFile $session ''
    }
    if ($file) { Import-AgentSession $session $file; $continued = (Get-Item $file).LastWriteTime }
}
if ($continued -and -not $script:Ui.on) { Write-LaunchNote "continuing the conversation of $($continued.ToString('yyyy-MM-dd HH:mm'))" }

# the models this run may have loaded: the start model and the ones of the picker
$pickerModels = @(@($agent.picker) | Where-Object { $_ -and (Test-ModelInstalled ([string]$_.model)) } | ForEach-Object { [string]$_.model })
$sessionModels = @(@($model) + $pickerModels | Select-Object -Unique)
if (-not $opt.onExit) { $opt.onExit = [string]$agent.onExit }
if (-not $opt.onExit) { $opt.onExit = 'keep' }
Register-AgentSession $model

if ($opt.print) {
    $prompt = ($positional -join ' ')
    if ([Console]::IsInputRedirected) {
        # the prompt from a pipe or file, read as UTF-8 like the other agents do
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false)))
        $piped = $reader.ReadToEnd()
        if ($piped.Trim()) { $prompt = ($prompt + "`n`n" + $piped).Trim() }
    }
    $code = 1
    try {
        if (-not $prompt.Trim()) { [Console]::Error.WriteLine('unzensiert: -p needs a request, as argument or on stdin') }
        else { $code = Invoke-AgentPrint $session $prompt $opt.format }
    } finally {
        [Console]::Error.WriteLine("unzensiert: $(Complete-AgentSession $opt.onExit $sessionModels)")
        [Console]::OutputEncoding = $savedEncoding
    }
    exit $code
}

# --- at the terminal ------------------------------------------------------------------------
$sessionStart = Get-Date
Enter-LocalLook
if ($script:Ui.on) {
    # the welcome of the style: picture, facts of the session, a saying, the keys
    $info = Get-AgentUiInfo $session
    $info.serverUp = Test-ServerUp
    if ($continued) { $info.continued = Get-UiText 'welcome.continued' ($continued.ToString('MMM d, HH:mm', $script:StyleCulture)) (Get-UiCount ($session.messages.Count - 1) 'messages') }
    Write-UiWelcome $session $info
    if ($agent.gitCheck) {
        $note = Get-GitSafetyNote $cwd
        if ($note) { Write-UiNote $note 'warn' }
    }
    # from here on the status bar stands under the text (lib\AgentUiBar.ps1)
    Enable-UiBar $session
} else {
    $ctx = Get-SessionContextSize $session
    Get-LocalLookBanner $model $server.baseUrl ([int]($ctx * [double]$cfg.compactAt)) $ctx $pickerModels 'unzensiert'
    if ($agent.gitCheck -and $interactive) {
        $note = Get-GitSafetyNote $cwd
        if ($note) { "unzensiert: $note" }
    }
}
try {
    Start-AgentRepl $session ($positional -join ' ')
} finally {
    $closing = Complete-AgentSession $opt.onExit $sessionModels
    if ($script:Ui.on) {
        Write-UiFarewell $session $sessionStart $closing
        Exit-AgentUi
    }
    [Console]::OutputEncoding = $savedEncoding
    Exit-LocalLook
    if (-not $script:Ui.on) {
        Get-LocalLookFarewell $sessionStart
        "unzensiert: $closing"
    }
}
exit 0
