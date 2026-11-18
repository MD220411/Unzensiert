# Shows every element of the terminal of Unzensiert once, with the made-up session of
# tests\agent-design.json: the welcome, the status line, the answer with Markdown and code,
# tool calls with their results, a diff, the questions before a call, notes, the end of a
# request, the overviews of /status, /help and /model, the activity line and the farewell.
# Needs no model and no server and changes nothing. The look: docs\stil.md.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Show-AgentDesign.ps1
#   ... -Style nachtschicht      another style of config\styles\, without switching to it
#   ... -Width 100               as in a window of this many columns
#   ... -OutFile design.ans      the output with its escape sequences into a file (UTF-8)
#   ... -Seed 7                  the same random choices (colours, sayings) every time

param(
    [string]$Style = '',
    [int]$Width = 0,
    [string]$OutFile = '',
    [int]$Seed = -1
)

. "$PSScriptRoot\_common.ps1"

if ($Style) {
    $file = Get-StyleFile $Style
    if (-not (Test-Path $file)) { throw "There is no style '$Style' in config\styles\." }
    $script:StyleConfigCache = Read-StyleJson $file
    $script:StyleRainbowCache = $null
}
if ($Seed -ge 0) { $script:StyleRandom = New-Object System.Random $Seed }
$data = ConvertFrom-AgentJson ([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\tests\agent-design.json'), [System.Text.Encoding]::UTF8))

$orig = [Console]::Out
$sw = $null
if ($OutFile) {
    $sw = New-Object System.IO.StringWriter
    [Console]::SetOut($sw)
}
$savedEncoding = [Console]::OutputEncoding
try {
    Initialize-AgentUi $true $false
    $script:Ui.on = $true
    if ($OutFile) { $script:Ui.wt = $false; $script:Ui.links = $false }
    if ($Width -gt 0) { $script:Ui.fixedWidth = $Width }
    elseif ($OutFile -or [Console]::IsOutputRedirected) { $script:Ui.fixedWidth = 120 }

    # a session as the agent keeps it, without a file and without a server
    $cwd = (Get-Location).ProviderPath
    $model = Get-DefaultAgentModel
    if (-not $model) { $model = 'local-coder' }
    $s = $data['session']
    $session = @{
        id = 'design'; cwd = $cwd; model = $model; mode = 'ask'; messages = [System.Collections.ArrayList]::new()
        ctx = 0; ctxModel = ''; promptTokens = 0; charsAtPrompt = 0; tokensPerSecond = 0.0
        inputTokens = 0; cachedTokens = 0; outputTokens = 0; turns = 0
        changed = [System.Collections.ArrayList]::new(); allowed = @{}; allowedTools = @(); instructionFiles = @()
        file = (Join-Path (Get-ServerConfig).installRoot 'sessions\design.jsonl')
    }
    foreach ($name in 'AGENTS.md', 'CLAUDE.md') {
        $p = Join-Path $cwd $name
        if (Test-Path $p) { $session.instructionFiles = @($session.instructionFiles) + @($p) }
    }
    $session.promptTokens = [int]((Get-SessionContextSize $session) * [double]$s['contextShare'])

    # the welcome and the first input
    $info = Get-AgentUiInfo $session
    $info.serverUp = $true
    Write-UiWelcome $session $info
    Write-UiStatus $session
    $sign = [string]@($script:Ui.glyphs.prompt)[0]
    [Console]::Write($sign + ' ' + [string]$data['prompt'] + "`n")
    Write-UiEcho ([string]$data['prompt']) $sign (Get-UiWheelHex 0.1)

    # the answer: thinking, Markdown, code
    $snap = Start-UiTurn $session
    Start-UiAnswer
    $script:Ui.thinkChars = [int]$data['thinkingChars']
    $script:Ui.thinkStart = [DateTime]::UtcNow.AddSeconds(-[double]$data['thinkingSeconds'])
    Add-UiContent ([string]$data['answer'])
    Complete-UiAnswer

    # tool calls and their results
    foreach ($step in $data['steps']) {
        $a = $step['args']
        Write-UiToolStart ([string]$step['tool']) $a $cwd
        Stop-UiActivity
        $seconds = 0.2
        if ($step['seconds']) { $seconds = [double]$step['seconds'] }
        $script:Ui.toolStarted = [DateTime]::UtcNow.AddSeconds(-$seconds)
        $r = $step['result']
        $result = New-ToolResult ([string]$r['text']) ([bool]$r['error'])
        $result.info = $r['info']
        if ($r['changed']) { $result.changed = Join-Path $cwd ([string]$r['changed']) }
        if ($r['diff']) { $result.diff = $r['diff'] }
        Write-UiToolResult $result ([string]$step['tool'])
    }

    # the questions before a call, answered
    foreach ($q in $data['questions']) {
        [Console]::WriteLine()
        $script:Ui.toolCwd = $cwd
        Show-UiPermission ([string]$q['tool']) '' ([string]$q['why']) ([bool]$q['always']) $q['args']
        Write-UiPermissionAnswer ([string]$q['reply'])
    }

    # notes of every kind, the last answer, the end of the request
    Write-UiNote (Get-UiText 'notes.shortened' (Format-Number 12400 0))
    Write-UiNote (Get-UiText 'notes.checkSays' 'README.md beschreibt mul noch nicht.') 'warn'
    Write-UiNote (Get-UiText 'notes.summaryFailed' 'timeout') 'error'
    Write-UiNote (Get-UiText 'modes.switched' 'edits' (Get-UiText 'modes.edits')) 'ok'
    Start-UiAnswer
    Add-UiContent ([string]$data['final'])
    Complete-UiAnswer
    $t = $data['turn']
    $script:Ui.turnFiles = @{}
    foreach ($f in $t['files']) { $script:Ui.turnFiles[(Join-Path $cwd ([string]$f))] = $true }
    $session.turns = [int]$t['rounds']
    $session.outputTokens = [int]$t['outputTokens']
    $session.tokensPerSecond = [double]$t['tokensPerSecond']
    $snap.at = [DateTime]::UtcNow.AddSeconds(-[double]$t['seconds'])
    $snap.turns = 0
    $snap.out = 0
    Complete-UiTurn $session $snap 'done'
    $snap.at = [DateTime]::UtcNow.AddSeconds(-12)
    Complete-UiTurn $session $snap 'stopped'

    # the overviews
    $session.inputTokens = [int]$s['inputTokens']
    $session.cachedTokens = [int]$s['cachedTokens']
    foreach ($f in $t['files']) { $null = $session.changed.Add((Join-Path $cwd ([string]$f))) }
    $session.allowed['Edit'] = $true
    $session.allowed['Write'] = $true
    Write-UiStatus $session
    [Console]::Write($sign + " /status`n")
    Write-UiEcho '/status' $sign (Get-UiWheelHex 0.3)
    Show-UiStatus $session $info
    Show-UiHelp (Get-AgentCommands)
    $rows = @(@((Get-AgentConfig).picker) | Where-Object { $_ })
    Show-UiModelList $rows $session.model

    # the activity line, which a real session shows only while something runs
    Write-UiHeading (Get-UiText 'demo.activity')
    foreach ($kind in 'model', 'think', 'call', 'tool', 'check') {
        $script:Ui.act.kind = $kind
        $script:Ui.act.started = [DateTime]::UtcNow.AddSeconds(-14)
        $script:Ui.act.chars = 2400
        $script:Ui.act.detail = 'Write'
        $script:Ui.act.verb = Get-UiVerb
        $script:Ui.toolName = 'Bash'
        $script:Ui.act.frame++
        [Console]::Write((Format-UiActivityLine) + "`n")
    }
    $script:Ui.act.kind = ''

    # the end of the session
    $script:Ui.requests = 3
    Write-UiFarewell $session ((Get-Date).AddMinutes(-[double]$s['minutes'])) 'models unloaded.'
} finally {
    if ($sw) {
        [Console]::SetOut($orig)
        [System.IO.File]::WriteAllText($OutFile, $sw.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    }
    [Console]::OutputEncoding = $savedEncoding
}
