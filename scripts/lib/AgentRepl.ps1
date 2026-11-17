# The two ways to use the agent Unzensiert: the conversation at the terminal (input line,
# commands with a slash, ! for a command of your own) and the one-shot run (-p) for scripts
# and the benchmark, with the result as text or as the JSON line Claude Code prints.
# Needs lib\AgentLoop.ps1 and the files it needs. Keep this file ASCII-only.
# Description: docs\unzensiert.md.

$script:InitPrompt = 'Look at this project and write the file AGENTS.md in the project folder with what a coding agent needs to know to work here: ' +
    'what the project is, how it is built and started, the exact commands for tests and checks, the layout of the folders, ' +
    'conventions of code and style that are not obvious, and what to be careful about. Keep it short (about 60 lines at most), concrete and correct; ' +
    'read the files instead of guessing. If AGENTS.md or CLAUDE.md exists already, improve that file instead.'

# --- sessions -----------------------------------------------------------------------------------

function Initialize-AgentSession($Session) {
    # Puts a fresh system prompt in front: date, git state and project rules of today.
    Set-SessionSystemPrompt $Session (New-AgentSystemPrompt $Session)
}

function Reset-AgentSession($Session, [string]$File = '') {
    # Starts over in the same object (/clear), or with an earlier session (/resume). Model,
    # mode and the "always" answers stay.
    $fresh = New-AgentSession $Session.cwd $Session.model
    foreach ($k in 'mode', 'allowed', 'allowedTools', 'showThinking', 'maxTurns') { $fresh[$k] = $Session[$k] }
    foreach ($k in @($fresh.Keys)) { $Session[$k] = $fresh[$k] }
    Initialize-AgentSession $Session
    if ($File) { Import-AgentSession $Session $File }
}

function Select-SessionFile($Session, [string]$Choice) {
    # An earlier session of this folder: by number from the list, or asked at the terminal.
    $files = @(Get-SessionFiles $Session.cwd | Where-Object { $_.file -ne $Session.file } | Select-Object -First 15)
    if ($files.Count -eq 0) { Write-UiNote 'There is no earlier conversation in this folder.'; return '' }
    if (-not $Choice) {
        for ($i = 0; $i -lt $files.Count; $i++) {
            Write-UiNote ('{0,3}  {1}  {2}' -f ($i + 1), $files[$i].time.ToString('yyyy-MM-dd HH:mm'), $files[$i].title)
        }
        $Choice = Read-UiLine 'number (Enter = cancel)'
    }
    $n = 0
    if ([int]::TryParse([string]$Choice, [ref]$n) -and $n -ge 1 -and $n -le $files.Count) { return $files[$n - 1].file }
    return ''
}

# --- input --------------------------------------------------------------------------------------

function ConvertTo-UserContent([string]$Text) {
    # The text of the user as a message; images inserted with Alt+V ("[image: path]") go
    # along as pictures.
    $found = [regex]::Matches($Text, '\[image: ([^\]]+)\]')
    if ($found.Count -eq 0) { return $Text }
    $parts = @(@{ type = 'text'; text = $Text })
    foreach ($m in $found) {
        $path = $m.Groups[1].Value.Trim()
        $ext = [System.IO.Path]::GetExtension($path).ToLower()
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not $script:ImageTypes.ContainsKey($ext)) { continue }
        $data = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
        $parts += , @{ type = 'image_url'; image_url = @{ url = "data:$($script:ImageTypes[$ext]);base64,$data" } }
    }
    return , $parts
}

function Invoke-UserCommand($Session, [string]$Command) {
    # !command: runs a command of the user's own in the project folder; the model sees the
    # command and its output with the next request.
    if (-not $Command) { return }
    $kind = 'PowerShell'
    if ($Session.gitBash) { $kind = 'Bash' }
    $a = @{ command = $Command }
    Write-UiToolStart $kind $a $Session.cwd
    $result = Invoke-ToolShell $Session $kind $a { Test-UiStop }
    Write-UiToolResult $result $kind
    $Session.pending += "The user ran this command ($kind):`n$ $Command`n$($result.text)`n"
}

function Get-AgentCommands {
    # The commands in config\<pluginDir>\commands\*.md (/feature, /bugfix, /pruefen), the
    # same files claude-local loads as plugin: name, description, hint and text.
    $commands = @{}
    $dir = Get-PluginDir
    if (-not $dir -or -not (Test-Path (Join-Path $dir 'commands'))) { return $commands }
    foreach ($f in Get-ChildItem -Path (Join-Path $dir 'commands') -Filter '*.md') {
        $text = [System.IO.File]::ReadAllText($f.FullName)
        $entry = @{ name = $f.BaseName; description = ''; hint = ''; body = $text.Trim() }
        $m = [regex]::Match($text, '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$')
        if ($m.Success) {
            $entry.body = $m.Groups[2].Value.Trim()
            foreach ($line in ($m.Groups[1].Value -split '\r?\n')) {
                if ($line -match '^description:\s*(.*)$') { $entry.description = $Matches[1].Trim() }
                elseif ($line -match '^argument-hint:\s*(.*)$') { $entry.hint = $Matches[1].Trim() }
            }
        }
        $commands[$f.BaseName.ToLowerInvariant()] = $entry
    }
    return $commands
}

function Expand-AgentCommand($Command, [string]$Arguments) {
    # The text of a command with its arguments in place of $ARGUMENTS.
    $body = [string]$Command.body
    if ($body.Contains('$ARGUMENTS')) { return $body.Replace('$ARGUMENTS', $Arguments) }
    if ($Arguments) { return $body + "`n`n" + $Arguments }
    return $body
}

# --- commands with a slash --------------------------------------------------------------------------

function Show-AgentHelp {
    $lines = @(
        'Enter sends, Shift+Enter starts a new line, Esc stops the model, Up/Down: earlier inputs.',
        'Shift+Tab switches the mode (ask, edits, all). Alt+V pastes an image from the clipboard.',
        '!command    run a command yourself; the model sees it with your next message',
        '/model      switch the model            /mode [ask|edits|all]  permission mode',
        '/compact    summarise the conversation  /clear                 start a new conversation',
        '/resume     continue an earlier one     /status                model, context, session',
        '/think      show or hide the thinking   /init                  write AGENTS.md for this project',
        '/exit       end'
    )
    foreach ($l in $lines) { Write-UiNote $l }
    $commands = Get-AgentCommands
    foreach ($k in ($commands.Keys | Sort-Object)) {
        Write-UiNote ('/{0,-10} {1}' -f $k, $commands[$k].description)
    }
}

function Switch-AgentModel($Session, [string]$Choice) {
    # /model: the installed models of the picker in config\agent.json, by number or name.
    $rows = @(@((Get-AgentConfig).picker) | Where-Object { $_ -and (Test-ModelInstalled ([string]$_.model)) })
    if (-not $Choice) {
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $mark = ' '
            if ([string]$rows[$i].model -eq $Session.model) { $mark = '*' }
            Write-UiNote ('{0} {1}  {2,-12} {3}' -f $mark, ($i + 1), $rows[$i].label, $rows[$i].description)
        }
        $Choice = Read-UiLine 'number or name (Enter = keep)'
        if (-not $Choice) { return }
    }
    $target = ''
    $n = 0
    if ([int]::TryParse($Choice, [ref]$n) -and $n -ge 1 -and $n -le $rows.Count) { $target = [string]$rows[$n - 1].model }
    else {
        $target = Resolve-ModelName $Choice
        $row = @($rows | Where-Object { $_.label -eq $Choice }) | Select-Object -First 1
        if ($row) { $target = [string]$row.model }
    }
    if (-not $target -or -not (Test-ModelInstalled $target)) { Write-UiNote "Unknown or not installed: $Choice" 'warn'; return }
    $Session.model = $target
    $Session.promptTokens = 0
    $Session.charsAtPrompt = 0
    Write-UiNote "model: $target (context $(Get-SessionContextSize $Session) tokens); it loads with the next request" 'ok'
    Invoke-AutoCompact $Session
}

function Set-AgentMode($Session, [string]$Choice) {
    if ($Choice) {
        $mode = ConvertTo-PermissionMode $Choice
        if (-not $mode) { Write-UiNote "Unknown mode: $Choice (ask, edits, all)" 'warn'; return }
    } else {
        $i = [array]::IndexOf($script:ModeOrder, $Session.mode)
        $mode = $script:ModeOrder[($i + 1) % $script:ModeOrder.Count]
    }
    $Session.mode = $mode
    $text = @{ ask = 'commands and file changes need your yes'; edits = 'file changes run without asking, commands need your yes'; all = 'everything runs without asking (the guard still decides first)' }
    $kind = 'ok'
    if ($mode -eq 'all') { $kind = 'warn' }
    Write-UiNote "mode $mode - $($text[$mode])" $kind
}

function Show-AgentStatus($Session) {
    $ctx = Get-SessionContextSize $Session
    $used = Get-EstimatedTokens $Session
    Write-UiNote "Unzensiert $(Get-ProgramVersion), model $($Session.model) at $((Get-ServerConfig).baseUrl)"
    Write-UiNote ('context about {0} of {1} tokens ({2} %), summarised at {3} %' -f $used, $ctx, [int](100 * $used / [math]::Max(1, $ctx)), [int](100 * [double](Get-AgentSettings).compactAt))
    Write-UiNote "this session: $($Session.turns) requests, $($Session.inputTokens) tokens read (+$($Session.cachedTokens) from cache), $($Session.outputTokens) written"
    Write-UiNote "mode $($Session.mode); allowed in this session: $((@($Session.allowedTools) + @($Session.allowed.Keys)) -join ', ')"
    Write-UiNote "project instructions: $(@($Session.instructionFiles) -join ', ')"
    Write-UiNote "changed files: $($Session.changed.Count); conversation file: $($Session.file)"
}

function Invoke-SlashCommand($Session, [string]$Line) {
    # Returns @{ exit; prompt }: prompt is the text for the model ('' = nothing to send).
    $m = [regex]::Match($Line, '(?s)^/(\S+)\s*(.*)$')
    $name = $m.Groups[1].Value.ToLowerInvariant()
    $rest = $m.Groups[2].Value.Trim()
    $result = @{ exit = $false; prompt = '' }
    if ($name.StartsWith('lokal:')) { $name = $name.Substring(6) }
    switch ($name) {
        { $_ -in 'exit', 'quit' } { $result.exit = $true }
        { $_ -in 'help', '?' } { Show-AgentHelp }
        { $_ -in 'clear', 'new' } { Reset-AgentSession $Session; Write-UiNote 'new conversation' 'ok' }
        'compact' { $null = Invoke-Compaction $Session $rest }
        'model' { Switch-AgentModel $Session $rest }
        'mode' { Set-AgentMode $Session $rest }
        'resume' {
            $file = Select-SessionFile $Session $rest
            if ($file) {
                Reset-AgentSession $Session $file
                Write-UiNote "continuing the conversation of $((Get-Item $file).LastWriteTime.ToString('yyyy-MM-dd HH:mm')) ($($Session.messages.Count - 1) messages)" 'ok'
            }
        }
        'status' { Show-AgentStatus $Session }
        'think' {
            $Session.showThinking = -not $Session.showThinking
            $script:Ui.showThinking = $Session.showThinking
            Write-UiNote "thinking is $(if ($Session.showThinking) { 'shown' } else { 'hidden' })" 'ok'
        }
        'init' { $result.prompt = $script:InitPrompt }
        default {
            $commands = Get-AgentCommands
            if ($commands.ContainsKey($name)) { $result.prompt = Expand-AgentCommand $commands[$name] $rest }
            else { Write-UiNote "Unknown command /$name - /help lists them." 'warn' }
        }
    }
    return $result
}

# --- the two loops ----------------------------------------------------------------------------------

function Invoke-InteractiveTurn($Session, $Content) {
    # Ctrl+C stops the request like Esc instead of ending the program.
    $saved = $false
    try { $saved = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch {}
    try { $null = Invoke-AgentTurn $Session $Content }
    finally { try { [Console]::TreatControlCAsInput = $saved } catch {} }
}

function Start-AgentRepl($Session, [string]$FirstPrompt = '') {
    # The conversation at the terminal, until /exit, Ctrl+D or the end of the input.
    $cfg = Get-AgentSettings
    $history = Join-Path (Get-ServerConfig).installRoot ([string]$cfg.historyFile)
    Initialize-UiInput $history
    Write-UiNote 'Enter sends, Shift+Enter: new line, Esc: stop, /help: commands, /exit: end'
    if ($FirstPrompt) { Invoke-InteractiveTurn $Session (ConvertTo-UserContent $FirstPrompt) }
    while ($true) {
        $line = Read-UiPrompt $Session
        if ($null -eq $line) { break }
        $text = $line.Trim()
        if (-not $text) { continue }
        if ($text -eq 'exit' -or $text -eq 'quit') { break }
        if ($text.StartsWith('!')) { Invoke-UserCommand $Session $text.Substring(1).Trim(); continue }
        $content = $null
        if ($text.StartsWith('/') -and $text -notmatch '^/[^\s/]*/') {
            $r = Invoke-SlashCommand $Session $text
            if ($r.exit) { break }
            if (-not $r.prompt) { continue }
            $content = $r.prompt
        } else {
            $content = ConvertTo-UserContent $text
        }
        Invoke-InteractiveTurn $Session $content
    }
}

function Write-AgentStdout([string]$Text) {
    [Console]::Out.WriteLine($Text)
    [Console]::Out.Flush()
}

function Invoke-AgentPrint($Session, [string]$Prompt, [string]$Format) {
    # One request without a terminal (-p): the answer as text, or as one JSON line in the
    # form of Claude Code (num_turns, modelUsage ...), which the benchmark reads. Returns
    # the exit code.
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $status = 'error'
    $failure = ''
    try { $status = Invoke-AgentTurn $Session $Prompt } catch { $failure = $_.Exception.Message; [Console]::Error.WriteLine("unzensiert: $failure") }
    $isError = ($status -eq 'error')
    if ($Format -eq 'json') {
        $usage = @{ inputTokens = $Session.inputTokens; outputTokens = $Session.outputTokens; cacheReadInputTokens = $Session.cachedTokens; costUSD = 0 }
        $subtype = 'success'
        if ($isError) { $subtype = 'error_during_execution' }
        elseif ($status -eq 'limit') { $subtype = 'error_max_turns' }
        $line = @{
            type = 'result'; subtype = $subtype; is_error = $isError; result = [string]$Session.lastAnswer
            duration_ms = [int]$watch.Elapsed.TotalMilliseconds; num_turns = $Session.turns; session_id = $Session.id
            total_cost_usd = 0; stop_reason = $status; agent = 'unzensiert'; version = (Get-ProgramVersion)
            usage = @{ input_tokens = $Session.inputTokens; output_tokens = $Session.outputTokens; cache_read_input_tokens = $Session.cachedTokens }
            modelUsage = @{ ([string]$Session.model) = $usage }
            changed_files = @($Session.changed | ForEach-Object { [string]$_ })
        }
        if ($failure) { $line['error'] = $failure }
        Write-AgentStdout (ConvertTo-AgentJson $line)
    } else {
        Write-AgentStdout ([string]$Session.lastAnswer)
    }
    if ($isError) { return 1 }
    return 0
}

# --- arguments of unzensiert ---------------------------------------------------------------------

function Split-ToolList([string]$Text) {
    # "Bash(git log:*) Edit,Read" -> three rules; separators inside parentheses stay.
    $rules = @()
    $sb = [System.Text.StringBuilder]::new()
    $depth = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '(') { $depth++ } elseif ($ch -eq ')') { $depth-- }
        if ($depth -eq 0 -and ($ch -eq ',' -or $ch -eq ' ')) {
            if ($sb.Length -gt 0) { $rules += $sb.ToString(); $null = $sb.Clear() }
            continue
        }
        $null = $sb.Append($ch)
    }
    if ($sb.Length -gt 0) { $rules += $sb.ToString() }
    return $rules
}

function ConvertFrom-AgentArgs($Arguments) {
    # The command line of unzensiert (see the header of scripts\unzensiert.ps1); the flags of
    # Claude Code that the benchmark and scripts use work the same. Returns the options plus
    # positional (the words of a request) and unknown (flags that are ignored).
    $opt = @{
        model = ''; onExit = ''; print = $false; format = 'text'; mode = ''; allowed = @(); maxTurns = 0
        continue = $false; resume = $null; version = $false; help = $false; update = $false; updates = ''
        positional = @(); unknown = @()
    }
    $list = @($Arguments)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $a = [string]$list[$i]
        $next = ''
        if ($i + 1 -lt $list.Count) { $next = [string]$list[$i + 1] }
        if ($a -eq '-Model' -or $a -eq '--model') { $opt.model = $next; $i++ }
        elseif ($a -eq '-OnExit') { $opt.onExit = $next; $i++ }
        elseif ($a -eq '-p' -or $a -eq '--print') { $opt.print = $true }
        elseif ($a -eq '--output-format') { $opt.format = $next; $i++ }
        elseif ($a -eq '--permission-mode') { $opt.mode = $next; $i++ }
        elseif ($a -eq '--dangerously-skip-permissions') { $opt.mode = 'all' }
        elseif ($a -eq '--allowedTools' -or $a -eq '--allowed-tools') {
            while ($i + 1 -lt $list.Count -and -not ([string]$list[$i + 1]).StartsWith('-')) { $i++; $opt.allowed += @(Split-ToolList ([string]$list[$i])) }
        }
        elseif ($a -eq '--max-turns') { $opt.maxTurns = [int]$next; $i++ }
        elseif ($a -eq '-c' -or $a -eq '--continue') { $opt.continue = $true }
        elseif ($a -eq '-r' -or $a -eq '--resume') {
            $opt.resume = ''
            if ($next -and -not $next.StartsWith('-')) { $opt.resume = $next; $i++ }
        }
        elseif ($a -eq '-v' -or $a -eq '--version') { $opt.version = $true }
        elseif ($a -eq '-h' -or $a -eq '--help') { $opt.help = $true }
        elseif ($a -eq '--update') { $opt.update = $true }
        elseif ($a -eq '--updates') { $opt.updates = $next; $i++ }
        elseif ($a -eq '--verbose' -or $a -eq '--debug') { }
        elseif ($a.StartsWith('-') -and $a.Length -gt 1) { $opt.unknown += $a }
        else { $opt.positional += $a }
    }
    return $opt
}
