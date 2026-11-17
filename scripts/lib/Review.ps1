# Second look ("zweiter Blick"): a second local model checks a change in a fresh context.
# It gets the task, the project rules (CLAUDE.md), the facts (facts\facts.json) and the
# git diff in one request and answers with findings. Used by scripts\Invoke-Review.ps1,
# which the closing check (scripts\hooks\Check-Stop.ps1) starts after larger changes.
# Settings: "review" in config\agent.json, instructions: config\zweiter-blick.md.
# Needs lib\Config.ps1 and lib\Server.ps1. Keep this file ASCII-only.
# Description: docs\agent.md.

function Get-ReviewSettings {
    # The "review" block of config\agent.json, or $null.
    return (Get-AgentConfig).review
}

function Invoke-Git([string]$Folder, [string[]]$Arguments) {
    # Runs git in $Folder and returns its output lines as UTF-8 (Windows PowerShell 5.1
    # would decode them with the console code page), plus the exit code.
    $before = [Console]::OutputEncoding
    # with 'Stop', Windows PowerShell 5.1 turns any git warning on stderr into an error
    $ErrorActionPreference = 'Continue'
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $lines = @(& git -C $Folder -c core.quotepath=off @Arguments 2>$null)
        return @{ code = $LASTEXITCODE; lines = $lines }
    } finally {
        [Console]::OutputEncoding = $before
    }
}

function Get-ChangeForReview([string]$Folder, [int]$MaxChars) {
    # The uncommitted change in $Folder: diff against HEAD plus untracked files as new
    # files. Returns ok, reason (why not), lines (added + removed), files, diff (cut to
    # $MaxChars).
    $result = @{ ok = $false; reason = ''; lines = 0; files = @(); diff = '' }
    $inside = Invoke-Git $Folder @('rev-parse', '--is-inside-work-tree')
    if ($inside.code -ne 0) { $result.reason = 'no git repository'; return $result }
    $hasHead = ((Invoke-Git $Folder @('rev-parse', '--verify', '-q', 'HEAD')).code -eq 0)

    $parts = New-Object System.Collections.Generic.List[string]
    $files = New-Object System.Collections.Generic.List[string]
    $lines = 0
    if ($hasHead) {
        foreach ($row in (Invoke-Git $Folder @('diff', 'HEAD', '--numstat')).lines) {
            $cells = ([string]$row) -split "`t"
            if ($cells.Count -lt 3) { continue }
            $files.Add($cells[2])
            if ($cells[0] -ne '-') { $lines += [int]$cells[0] + [int]$cells[1] }
        }
        $parts.Add(((Invoke-Git $Folder @('diff', 'HEAD', '--no-color', '--unified=5')).lines -join "`n"))
    }
    $new = @((Invoke-Git $Folder @('ls-files', '--others', '--exclude-standard')).lines)
    if (-not $hasHead) { $new = @($new) + @((Invoke-Git $Folder @('ls-files')).lines) }
    foreach ($rel in ($new | Where-Object { $_ } | Sort-Object -Unique)) {
        $path = Join-Path $Folder $rel
        if (-not (Test-Path $path -PathType Leaf) -or (Get-Item $path).Length -gt 200KB) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes -contains 0) { continue }                       # binary file
        $text = (New-Object System.Text.UTF8Encoding($false)).GetString($bytes)
        $body = @($text.TrimEnd("`r", "`n") -split "`r?`n")
        $files.Add($rel)
        $lines += $body.Count
        $parts.Add("--- /dev/null`n+++ b/$rel  (neue Datei)`n" + (($body | ForEach-Object { "+$_" }) -join "`n"))
    }
    $diff = (($parts | Where-Object { $_ }) -join "`n").Trim()
    if (-not $diff) { $result.reason = 'no uncommitted change'; return $result }
    if ($diff.Length -gt $MaxChars) {
        $diff = $diff.Substring(0, $MaxChars) + "`n[... Diff nach $MaxChars Zeichen abgeschnitten ...]"
    }
    $result.ok = $true
    $result.lines = $lines
    $result.files = @($files | Sort-Object -Unique)
    $result.diff = $diff
    return $result
}

function Get-LastUserPrompt([string]$Transcript, [int]$MaxChars = 4000) {
    # The last thing the user typed in the session (the task), read from the transcript
    # of Claude Code (JSON lines). Tool results, hook messages and meta entries are skipped.
    if (-not $Transcript -or -not (Test-Path $Transcript)) { return '' }
    $last = ''
    foreach ($line in [System.IO.File]::ReadAllLines($Transcript)) {
        if ($line -notmatch '"type"\s*:\s*"user"') { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ($entry.type -ne 'user' -or $entry.isMeta -or -not $entry.message) { continue }
        $content = $entry.message.content
        $text = ''
        if ($content -is [string]) {
            $text = $content
        } else {
            $text = (@($content | Where-Object { $_.type -eq 'text' } | ForEach-Object { [string]$_.text }) -join "`n")
        }
        if ($text.Trim() -and $text -notmatch '^\s*<(local-command|command-stdout)') { $last = $text.Trim() }
    }
    if ($last.Length -gt $MaxChars) { $last = $last.Substring(0, $MaxChars) + ' [...]' }
    return $last
}

function Get-FileHead([string]$Path, [int]$MaxChars) {
    # The start of a text file, or '' if it does not exist.
    if (-not (Test-Path $Path -PathType Leaf)) { return '' }
    $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false))).Trim()
    if ($text.Length -gt $MaxChars) { $text = $text.Substring(0, $MaxChars) + "`n[...]" }
    return $text
}

function Get-ChangedFilesText([string]$Folder, $Files, [int]$MaxChars) {
    # The current content of the changed files, smallest first, as long as they fit into
    # $MaxChars: a contradiction to a line the diff does not show (README still names the
    # old pin) is only visible in the whole file.
    $blocks = @()
    $used = 0
    $sized = foreach ($rel in @($Files)) {
        $path = Join-Path $Folder $rel
        if (Test-Path $path -PathType Leaf) { [pscustomobject]@{ rel = $rel; path = $path; size = (Get-Item $path).Length } }
    }
    foreach ($file in @($sized | Sort-Object size)) {
        $text = Get-FileHead $file.path ([int]::MaxValue)
        if (-not $text -or $text.IndexOf([char]0) -ge 0) { continue }
        if ($used + $text.Length -gt $MaxChars) { continue }
        $used += $text.Length
        $blocks += "### $($file.rel)`n`n``````$("`n")$text`n``````"
    }
    return ($blocks -join "`n`n")
}

function New-ReviewRequest([string]$Folder, [string]$Task, $Change, [int]$MaxFileChars) {
    # The user message for the reviewing model.
    $sections = @()
    if (-not $Task) { $Task = '(nicht bekannt; aus dem Diff erschliessen)' }
    $sections += "## Auftrag an den Autor`n`n$Task"
    $rules = Get-FileHead (Join-Path $Folder 'CLAUDE.md') 6000
    if ($rules) { $sections += "## Regeln des Projekts (CLAUDE.md)`n`n$rules" }
    $facts = Get-FileHead (Join-Path $Folder 'facts\facts.json') 12000
    if ($facts) { $sections += "## Belegte Fakten (facts/facts.json)`n`n$facts" }
    $sections += "## Geaenderte Dateien`n`n" + (($Change.files | ForEach-Object { "- $_" }) -join "`n")
    $sections += "## Aenderung (git diff)`n`n``````diff`n$($Change.diff)`n``````"
    $whole = Get-ChangedFilesText $Folder $Change.files $MaxFileChars
    if ($whole) { $sections += "## Geaenderte Dateien im neuen Stand (soweit sie hineinpassen)`n`n$whole" }
    return ($sections -join "`n`n")
}

function ConvertFrom-ReviewAnswer([string]$Text) {
    # Splits the answer of the reviewing model into errors and hints. Lines that follow
    # neither form are ignored; "KEINE BEFUNDE" or nothing usable means no finding.
    $errors = @(); $hints = @()
    foreach ($line in ($Text -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s*(?:[-*]\s*|\d+[.)]\s*)?\**(FEHLER|HINWEIS)\**\s*[|:]\s*(.+?)\s*$')
        if (-not $match.Success) { continue }
        $body = ($match.Groups[2].Value -replace '\s*\|\s*', ' | ').Trim()
        if ($match.Groups[1].Value -eq 'FEHLER') { $errors += $body } else { $hints += $body }
    }
    return @{ errors = @($errors); hints = @($hints) }
}

function Invoke-ReviewModel([string]$Model, [string]$System, [string]$User, [int]$MaxTokens, [int]$TimeoutSec) {
    # One chat request to the reviewing model through the router (which loads it, and
    # unloads another model if the memory is needed). Returns the answer text.
    $body = [ordered]@{
        model      = $Model
        max_tokens = $MaxTokens
        messages   = @(
            [ordered]@{ role = 'system'; content = $System },
            [ordered]@{ role = 'user'; content = $User }
        )
    }
    $answer = Invoke-ServerApi '/v1/chat/completions' $body $TimeoutSec
    return [string]$answer.choices[0].message.content
}

function Write-ReviewLog($Entry) {
    # One JSON line per review in <logs>\review.log, for measuring how often the second
    # look finds something.
    $log = Join-Path (Split-Path -Parent (Get-ServerConfig).logFile) 'review.log'
    $line = ($Entry | ConvertTo-Json -Compress -Depth 4)
    [System.IO.File]::AppendAllText($log, $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-Review([string]$Folder, [string]$Task, [string]$Model, [int]$MinLines) {
    # The whole second look. Returns status (skipped, clean, findings, error), reason,
    # errors, hints, lines, files, seconds, model.
    $cfg = Get-ReviewSettings
    # CLAUDE_LOCAL_REVIEW_MODEL: set by Benchmark-Models.ps1 -ReviewModel to compare reviewers
    if (-not $Model -and $env:CLAUDE_LOCAL_REVIEW_MODEL) { $Model = Resolve-ModelName $env:CLAUDE_LOCAL_REVIEW_MODEL }
    if (-not $Model) { $Model = Resolve-ModelName ([string]$cfg.model) }
    # A machine with only one model reviews with that one: a fresh context still sees
    # what the author overlooked (docs\agent.md, second look).
    if (-not (Test-ModelInstalled $Model)) { $Model = Get-DefaultAgentModel }
    $result = [ordered]@{ status = 'skipped'; reason = ''; errors = @(); hints = @(); lines = 0; files = @(); seconds = 0; model = $Model }
    if (-not $Model) { $result.reason = 'no model installed'; return $result }
    $change = Get-ChangeForReview $Folder ([int]$cfg.maxDiffChars)
    if (-not $change.ok) { $result.reason = $change.reason; return $result }
    $result.lines = $change.lines
    $result.files = $change.files
    if ($change.lines -lt $MinLines) { $result.reason = "change has $($change.lines) lines, review starts at $MinLines"; return $result }

    $instructions = Get-FileHead (Join-Path $script:ConfigDir ([string]$cfg.instructionsFile)) 20000
    $request = New-ReviewRequest $Folder $Task $change ([int]$cfg.maxFileChars)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Start-Server
        $text = Invoke-ReviewModel $Model $instructions $request ([int]$cfg.maxTokens) ([int]$cfg.timeoutSeconds)
        $found = ConvertFrom-ReviewAnswer $text
        $result.errors = $found.errors
        $result.hints = $found.hints
        $result.status = 'clean'
        if ($found.errors.Count -gt 0 -or $found.hints.Count -gt 0) { $result.status = 'findings' }
    } catch {
        $result.status = 'error'
        $result.reason = $_.Exception.Message
    }
    $result.seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    try {
        Write-ReviewLog ([ordered]@{ time = (Get-Date -Format 's'); folder = $Folder; model = $Model; status = $result.status; lines = $result.lines; seconds = $result.seconds; errors = $result.errors.Count; hints = $result.hints.Count; reason = $result.reason })
    } catch {}
    return $result
}
