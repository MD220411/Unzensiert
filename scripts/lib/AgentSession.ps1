# Conversation state of the agent Unzensiert: the messages, the files read and changed, and
# where a session is kept: <installRoot>\sessions\<project>\<start>.jsonl (one message per
# line, images left out) plus <start>.hook.jsonl, the short transcript the closing check
# (scripts\hooks\Check-Stop.ps1) reads. Needs lib\Config.ps1, lib\AgentApi.ps1.
# Keep this file ASCII-only.

function Get-SessionFolder([string]$Cwd) {
    # One folder per project folder: a readable part and a short hash of the full path.
    $lower = $Cwd.ToLowerInvariant().TrimEnd('\')
    $key = ($lower -replace '[^a-z0-9]+', '-').Trim('-')
    if ($key.Length -gt 50) { $key = $key.Substring($key.Length - 50).Trim('-') }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { $hash = -join (@($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lower)))[0..3] | ForEach-Object { $_.ToString('x2') }) }
    finally { $md5.Dispose() }
    return [string](Join-Path (Get-ServerConfig).installRoot "sessions\$key-$hash")
}

function New-AgentSession([string]$Cwd, [string]$Model) {
    $cfg = Get-AgentSettings
    $folder = Get-SessionFolder $Cwd
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $id = [datetime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    # [type]::new() and [string]: no PSObject wrappers in data that becomes JSON (lib\AgentApi.ps1)
    return @{
        id = $id; cwd = $Cwd; model = $Model; folder = $folder
        file = [System.IO.Path]::Combine($folder, "$id.jsonl"); hookTranscript = [System.IO.Path]::Combine($folder, "$id.hook.jsonl")
        messages = [System.Collections.ArrayList]::new()
        reads = @{}; changed = [System.Collections.ArrayList]::new()
        mode = [string]$cfg.permissionMode; allowed = @{}; allowedTools = @()
        gitBash = [string](Find-GitBash); showThinking = [bool]$cfg.showThinking
        ctx = 0; ctxModel = ''; lastBudget = 0; lastFinish = ''
        promptTokens = 0; charsAtPrompt = 0; tokensPerSecond = 0.0; cachedTokens = 0
        inputTokens = 0; outputTokens = 0; turns = 0; maxTurns = 0
        stopActive = $false; answerEdits = 0; fingerprints = @{}; denials = 0; noEffect = 0
        lastPrompt = ''; lastAnswer = ''; pending = ''
        instructionFiles = @(); started = [datetime]::Now
    }
}

function Get-StoredMessage($Message) {
    # A message as it is written to the session file: images replaced by a note, they are
    # large and can be read again from their file.
    $content = $Message['content']
    if ($content -is [System.Array]) {
        $parts = @()
        foreach ($part in $content) {
            if ((Get-DictValue $part 'type') -eq 'image_url') { $parts += , @{ type = 'text'; text = '[image left out of the saved session]' } }
            else { $parts += , $part }
        }
        $copy = @{}
        foreach ($k in $Message.Keys) { $copy[$k] = $Message[$k] }
        $copy['content'] = $parts
        return $copy
    }
    return $Message
}

function Add-SessionMessage($Session, $Message) {
    $null = $Session.messages.Add($Message)
    if ($Message['role'] -eq 'system') { return }
    try {
        [System.IO.File]::AppendAllText($Session.file, (ConvertTo-AgentJson (Get-StoredMessage $Message)) + "`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}

function Set-SessionSystemPrompt($Session, [string]$Text) {
    # The system prompt is always the first message and never stored: a resumed session
    # gets a fresh one (date, git state, rules of today).
    if ($Session.messages.Count -gt 0 -and $Session.messages[0]['role'] -eq 'system') { $Session.messages[0] = @{ role = 'system'; content = $Text } }
    else { $Session.messages.Insert(0, @{ role = 'system'; content = $Text }) }
}

function Import-AgentSession($Session, [string]$File) {
    # Loads the messages of an earlier session into $Session and continues in its file. A
    # line {"compact":true} marks a summary: only what follows it is loaded.
    $system = $null
    if ($Session.messages.Count -gt 0 -and $Session.messages[0]['role'] -eq 'system') { $system = $Session.messages[0] }
    $Session.messages.Clear()
    if ($system) { $null = $Session.messages.Add($system) }
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        if (-not $line.Trim()) { continue }
        try { $m = ConvertFrom-AgentJson $line } catch { continue }
        if (Get-DictValue $m 'compact') {
            $Session.messages.Clear()
            if ($system) { $null = $Session.messages.Add($system) }
            continue
        }
        if ($m -and (Get-DictValue $m 'role')) { $null = $Session.messages.Add($m) }
    }
    foreach ($m in $Session.messages) {
        if ($m['role'] -eq 'user' -and $m['content'] -is [string] -and -not $m['content'].StartsWith('Stop hook feedback')) { $Session.lastPrompt = [string]$m['content'] }
    }
    $Session.file = $File
    $Session.hookTranscript = $File -replace '\.jsonl$', '.hook.jsonl'
    $Session.id = [System.IO.Path]::GetFileNameWithoutExtension($File)
}

function Get-SessionFiles([string]$Cwd) {
    # Earlier sessions of this project folder, newest first: @{ file; time; title }.
    $folder = Get-SessionFolder $Cwd
    if (-not (Test-Path $folder)) { return @() }
    return @(Get-ChildItem -Path $folder -Filter '*.jsonl' | Where-Object { $_.Name -notlike '*.hook.jsonl' -and $_.Length -gt 0 } |
            Sort-Object LastWriteTime -Descending | ForEach-Object {
                $title = ''
                foreach ($line in [System.IO.File]::ReadLines($_.FullName)) {
                    try { $m = ConvertFrom-AgentJson $line } catch { continue }
                    if ((Get-DictValue $m 'role') -eq 'user' -and (Get-DictValue $m 'content') -is [string]) { $title = [string]$m['content']; break }
                }
                $title = ($title -replace '\s+', ' ').Trim()
                if ($title.Length -gt 70) { $title = $title.Substring(0, 70) + '...' }
                [pscustomobject]@{ file = $_.FullName; time = $_.LastWriteTime; title = $title }
            })
}

function Add-HookTranscript($Session, [string]$Kind, $Value, [string]$Id = '') {
    # The short transcript for scripts\hooks\Check-Stop.ps1 and the second look, in the
    # form they know from Claude Code: the prompts of the user and the file changes
    # ("type":"tool_use","id":...,"name":... in this order).
    if ($Kind -eq 'prompt') {
        $line = '{"type":"user","message":{"role":"user","content":' + (ConvertTo-AgentJson ([string]$Value)) + '}}'
    } else {
        $line = '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":' + (ConvertTo-AgentJson $Id) + ',"name":' + (ConvertTo-AgentJson $Kind) + ',"input":{"file_path":' + (ConvertTo-AgentJson ([string]$Value)) + '}}]}}'
    }
    try { [System.IO.File]::AppendAllText($Session.hookTranscript, $line + "`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
}

function Get-MessageChars($Message) {
    # Size of a message in characters, for estimating tokens between two answers.
    $n = 0
    $content = $Message['content']
    if ($content -is [string]) { $n += $content.Length }
    elseif ($content -is [System.Array]) { foreach ($p in $content) { $t = Get-DictValue $p 'text'; if ($t) { $n += ([string]$t).Length } else { $n += 3000 } } }
    $reasoning = Get-DictValue $Message 'reasoning_content'
    if ($reasoning) { $n += ([string]$reasoning).Length }
    $calls = $Message['tool_calls']
    if ($calls) { foreach ($c in $calls) { $n += ([string](Get-DictValue (Get-DictValue $c 'function') 'arguments')).Length + 40 } }
    return $n
}

function Get-SessionChars($Session) {
    $n = 0
    foreach ($m in $Session.messages) { $n += Get-MessageChars $m }
    return $n
}

function Get-EstimatedTokens($Session) {
    # Tokens of the conversation now: what the server counted at the last request, plus or
    # minus the characters added or shortened since then, at the ratio of that request
    # (without a count about 3.5 characters a token).
    $chars = Get-SessionChars $Session
    $ratio = 3.5
    if ($Session.promptTokens -gt 0 -and $Session.charsAtPrompt -gt 0) { $ratio = [math]::Max(1.5, $Session.charsAtPrompt / [double]$Session.promptTokens) }
    if ($Session.promptTokens -gt 0) { return [int][math]::Max(0, $Session.promptTokens + ($chars - $Session.charsAtPrompt) / $ratio) }
    return [int]($chars / $ratio)
}

function Compress-OldToolResults($Session, [int]$KeepRounds, [int]$MaxChars) {
    # Shortens the results of tools older than the last $KeepRounds answers of the model to
    # their beginning: the cheap way to make room before a summary is needed. Returns the
    # number of characters saved.
    $assistantSeen = 0
    $saved = 0
    for ($i = $Session.messages.Count - 1; $i -ge 0; $i--) {
        $m = $Session.messages[$i]
        if ($m['role'] -eq 'assistant') { $assistantSeen++ }
        if ($assistantSeen -le $KeepRounds) { continue }
        if ($m['role'] -eq 'tool' -and $m['content'] -is [string] -and $m['content'].Length -gt $MaxChars) {
            $old = $m['content']
            $m['content'] = $old.Substring(0, $MaxChars) + "`n... [shortened afterwards, was $($old.Length) characters; read the file again if needed]"
            $saved += $old.Length - $m['content'].Length
        }
    }
    return $saved
}
