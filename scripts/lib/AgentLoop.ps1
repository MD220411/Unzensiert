# The agent loop of Unzensiert: a request of the user becomes rounds of model answer and
# tool calls until the model answers without a call. Before a call runs, the guard
# (scripts\hooks\GuardRules.ps1, config\guard.json) and the permission mode decide; when the
# model wants to end an answer in which it changed files, the closing check runs
# (scripts\hooks\Check-Stop.ps1, "stopCheck" in config\agent.json). Also here: shortening and
# summarising the conversation when the context window fills up. The commands typed with a
# slash and the loops for the terminal and for one-shot runs are in lib\AgentRepl.ps1.
# Needs lib\AgentApi.ps1, AgentTools.ps1, AgentSession.ps1, AgentUi.ps1 and lib\Quality.ps1.
# Keep this file ASCII-only. Description: docs\unzensiert.md.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'hooks\GuardRules.ps1')

$script:ModeOrder = @('ask', 'edits', 'all')
$script:ReadOnlyTools = @('Read', 'Glob', 'Grep')
$script:FileTools = @('Edit', 'Write')
$script:HookPrefix = 'Stop hook feedback:'
$script:Md5 = [System.Security.Cryptography.MD5]::Create()

# --- helpers ----------------------------------------------------------------------------------

function ConvertTo-PermissionMode([string]$Name) {
    # ask, edits or all; the names of Claude Code (default, acceptEdits, bypassPermissions)
    # are understood too. '' for an unknown name.
    $n = $Name.ToLowerInvariant()
    if (@('ask', 'default', 'plan', 'dontask') -contains $n) { return 'ask' }
    if (@('edits', 'acceptedits') -contains $n) { return 'edits' }
    if (@('all', 'bypasspermissions') -contains $n) { return 'all' }
    return ''
}

function ConvertTo-PlainHashtable($Dict) {
    # Arguments of a tool call as a hashtable (the guard reads them as properties).
    $h = @{}
    if ($Dict -is [System.Collections.IDictionary]) { foreach ($k in @($Dict.Keys)) { $h[[string]$k] = $Dict[$k] } }
    return $h
}

function Get-ContentText($Content) {
    # The text of a message content: a string, or the text parts of a list.
    if ($Content -is [string]) { return $Content }
    $texts = @()
    foreach ($part in @($Content)) {
        $t = Get-DictValue $part 'text'
        if ($t) { $texts += [string]$t }
    }
    return ($texts -join "`n")
}

function Get-TextHash([string]$Text) {
    $bytes = $script:Md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    return [Convert]::ToBase64String($bytes)
}

function Get-ResultShape([string]$Text) {
    # A result as compared for repeats: run times and memory addresses differ between two runs
    # of the same failing test ("Ran 7 tests in 0.507s"), so decimal numbers and 0x addresses
    # count as equal. Whole numbers (line numbers, counts) still count.
    return [regex]::Replace([regex]::Replace($Text, '0x[0-9a-fA-F]+', '0x#'), '\d+\.\d+', '#')
}

function Get-ChangedFilesState($Session) {
    # A hash over the current content of the files changed in this session. Two calls with
    # the same state saw the same files, also when a file was changed and changed back, or
    # changed by a command. A file over 4 MB counts by size and time.
    $sb = [System.Text.StringBuilder]::new()
    foreach ($path in @($Session.changed)) {
        $null = $sb.Append($path).Append('=')
        try {
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            if ($item.Length -gt 4MB) { $null = $sb.Append("$($item.Length)/$($item.LastWriteTimeUtc.Ticks)") }
            else { $null = $sb.Append([Convert]::ToBase64String($script:Md5.ComputeHash([System.IO.File]::ReadAllBytes($path)))) }
        } catch {
            $null = $sb.Append('missing')
        }
        $null = $sb.Append(';')
    }
    return (Get-TextHash $sb.ToString())
}

function Get-SessionContextSize($Session) {
    # Context window of the session model in tokens, read once per model.
    if (-not $Session.ctxModel -or $Session.ctxModel -ne $Session.model) {
        $ctx = 0
        try { $ctx = Get-ModelContextSize $Session.model } catch {}
        if ($ctx -le 0) { $ctx = [int](Get-AgentConfig).fallbackContextTokens }
        $Session.ctx = $ctx
        $Session.ctxModel = $Session.model
    }
    return [int]$Session.ctx
}

# --- permissions ------------------------------------------------------------------------------

function Split-CommandParts([string]$Command) {
    # The single commands of a command line, split at && || ; | and line breaks outside of
    # quotes, so that python -c "import a; a.run()" stays one command.
    $parts = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $quote = [char]0
    $n = $Command.Length
    $i = 0
    while ($i -lt $n) {
        $ch = $Command[$i]
        if ($quote -ne [char]0) {
            if ($ch -eq $quote) { $quote = [char]0 }
            elseif ($ch -eq [char]'\' -and $quote -eq [char]'"' -and $i + 1 -lt $n) { $null = $sb.Append($ch); $i++; $ch = $Command[$i] }
            $null = $sb.Append($ch)
            $i++
            continue
        }
        if ($ch -eq [char]'"' -or $ch -eq [char]"'") { $quote = $ch; $null = $sb.Append($ch); $i++; continue }
        $sep = 0
        if (($ch -eq [char]'&' -or $ch -eq [char]'|') -and $i + 1 -lt $n -and $Command[$i + 1] -eq $ch) { $sep = 2 }
        elseif ($ch -eq [char]';' -or $ch -eq [char]'|' -or $ch -eq [char]"`n" -or $ch -eq [char]"`r") { $sep = 1 }
        if ($sep -gt 0) {
            $part = $sb.ToString().Trim()
            if ($part) { $parts.Add($part) }
            $null = $sb.Clear()
            $i += $sep
            continue
        }
        $null = $sb.Append($ch)
        $i++
    }
    $part = $sb.ToString().Trim()
    if ($part) { $parts.Add($part) }
    return $parts.ToArray()
}

function Test-ProjectFileCommand([string]$Part, [string]$Cwd) {
    # True if the command only creates, copies, moves or deletes files inside the project
    # folder ("fileCommands" in config\unzensiert.json); in mode edits that is a file change
    # like Edit and Write. Variables, redirections or a target outside: not such a command.
    $words = @(Get-CommandTokens $Part)
    if ($words.Count -lt 2 -or @((Get-AgentSettings).fileCommands) -notcontains $words[0].ToLowerInvariant()) { return $false }
    if ($Part -match '[`$%<>]') { return $false }
    foreach ($w in $words[1..($words.Count - 1)]) {
        if ($w -match '^-' -or $w -match '^/[a-zA-Z?]$') { continue }
        $t = $w.Trim('"', "'")
        if (-not $t -or $t.StartsWith('~')) { return $false }
        # strictly below the project folder: the folder itself (rm -r .) is no file change
        if (-not (Resolve-AgentPath $t $Cwd).StartsWith($Cwd.TrimEnd([char]92) + [char]92, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

function Test-ReadOnlyCommand([string]$Command) {
    # True if every part of the command only reads ("readOnlyCommands" and "readOnlyGit" in
    # config\unzensiert.json): such commands run in every mode without a question.
    $cfg = Get-AgentSettings
    if ($Command -match '`|\$\(|<\(|>\(') { return $false }
    $parts = @(Split-CommandParts $Command)
    if ($parts.Count -eq 0) { return $false }
    foreach ($part in $parts) {
        # output into a file writes; 2>&1 and the null device do not
        $rest = $part -replace '\d?>\s*&\s*\d', '' -replace '\d?>\s*(/dev/null|\$null|nul)(\s|$)', ' '
        if ($rest.Contains('>')) { return $false }
        $words = @($part -split '\s+')
        $first = $words[0].ToLowerInvariant()
        if ($first -eq 'git') {
            if ($words.Count -lt 2 -or @($cfg.readOnlyGit) -notcontains $words[1].ToLowerInvariant()) { return $false }
            if ($part -match '\s--output') { return $false }
            continue
        }
        if (@($cfg.readOnlyCommands) -notcontains $first) { return $false }
        if ($first -eq 'find' -and $part -match '\s-(delete|exec|execdir|ok|okdir|fprint\w*|fls)(\s|$)') { return $false }
        if ($first -eq 'sort' -and $part -match '\s(-o|--output)') { return $false }
    }
    return $true
}

function Test-CommandPattern([string]$Command, [string]$Spec) {
    # A rule like "python:*" (the program and anything after it) or an exact command.
    $cmd = $Command.Trim()
    if ($Spec.EndsWith(':*')) { $prefix = $Spec.Substring(0, $Spec.Length - 2) }
    elseif ($Spec.EndsWith('*')) { $prefix = $Spec.Substring(0, $Spec.Length - 1).TrimEnd() }
    else { return ($cmd -eq $Spec) }
    return ($cmd -eq $prefix -or $cmd.StartsWith($prefix + ' ', [StringComparison]::OrdinalIgnoreCase))
}

function Test-ToolAllowed($Session, [string]$Name, $A) {
    # True if --allowedTools or an "always" answer of this session covers the call. For a
    # command, every part of it must be covered or only read.
    $rules = @($Session.allowedTools) + @($Session.allowed.Keys)
    if ($Name -eq 'Bash' -or $Name -eq 'PowerShell') {
        $parts = @(Split-CommandParts ([string](Get-DictValue $A 'command')))
        if ($parts.Count -eq 0) { return $false }
        foreach ($part in $parts) {
            $ok = (Test-ReadOnlyCommand $part) -or ($Session.mode -eq 'edits' -and (Test-ProjectFileCommand $part $Session.cwd))
            foreach ($rule in $rules) {
                if ($ok) { break }
                if ($rule -eq $Name) { $ok = $true }
                elseif ($rule -match '^(\w+)\((.+)\)$' -and $Matches[1] -eq $Name -and (Test-CommandPattern $part $Matches[2])) { $ok = $true }
            }
            if (-not $ok) { return $false }
        }
        return $true
    }
    foreach ($rule in $rules) {
        if ($rule -eq $Name) { return $true }
        if ($rule -match '^(\w+)\((.+)\)$' -and $Matches[1] -eq $Name) {
            $glob = $Matches[2]
            $path = (Get-DisplayPath (Resolve-AgentPath (Get-DictValue $A 'file_path') $Session.cwd) $Session.cwd).Replace('\', '/')
            if ((ConvertTo-GlobRegex $glob).IsMatch($path)) { return $true }
        }
    }
    return $false
}

function Get-AlwaysRules([string]$Name, $A) {
    # What an "always" answer allows for the rest of the session: for a command its programs
    # (with the subcommand for git, npm and the like), for a file change all file changes.
    if ($script:FileTools -contains $Name) { return @('Edit', 'Write') }
    $two = @('git', 'npm', 'npx', 'pnpm', 'yarn', 'pip', 'uv', 'poetry', 'dotnet', 'cargo', 'go', 'docker', 'winget', 'choco', 'mvn', 'gradle')
    $rules = @()
    foreach ($part in @(Split-CommandParts ([string](Get-DictValue $A 'command')))) {
        if (Test-ReadOnlyCommand $part) { continue }
        $words = @($part -split '\s+')
        $prefix = $words[0]
        if ($words.Count -gt 1 -and $two -contains $words[0].ToLowerInvariant() -and -not $words[1].StartsWith('-')) { $prefix += ' ' + $words[1] }
        $rules += "$Name(${prefix}:*)"
    }
    return $rules
}

function Get-CallPreview([string]$Name, $A) {
    # What the question before a call shows: the command, or the path with the change.
    $plain = ConvertTo-PlainHashtable $A
    $text = Get-GuardSubject $Name $plain
    if ($Name -eq 'Edit') {
        $old = @(([string]$plain['old_string']).Replace("`r", '').Split("`n") | ForEach-Object { "- $_" })
        $new = @(([string]$plain['new_string']).Replace("`r", '').Split("`n") | ForEach-Object { "+ $_" })
        $text += "`n" + ((@($old) + @($new)) -join "`n")
    } elseif ($Name -eq 'Write') {
        $text += "`n" + ((@(([string]$plain['content']).Replace("`r", '').Split("`n") | ForEach-Object { "+ $_" })) -join "`n")
    }
    return $text
}

function Get-CallDecision($Session, [string]$Name, $A, $Guard) {
    # How a call goes ahead: @{ action = run, ask or deny; why; guard }. The guard decides
    # first and in every mode; then the mode and the rules of the session.
    $plain = ConvertTo-PlainHashtable $A
    $verdict = Invoke-GuardCheck $Name $plain $Session.cwd $Guard
    if ($verdict.decision -ne 'none') { Write-GuardLog $Name (Get-GuardSubject $Name $plain) $verdict }
    if ($verdict.decision -eq 'deny') {
        return @{ action = 'deny'; guard = $true; why = "Blocked by the guard of Unzensiert (rule $($verdict.rule)): $($verdict.reason). It protects the user's computer; do not try to get around it." }
    }
    if ($verdict.decision -eq 'ask') { return @{ action = 'ask'; guard = $true; why = "guard rule $($verdict.rule): $($verdict.reason)" } }
    if ($script:ReadOnlyTools -contains $Name -or $Session.mode -eq 'all') { return @{ action = 'run' } }
    if ($script:FileTools -contains $Name -and $Session.mode -eq 'edits') {
        # edits covers the project folder; a file outside it asks, as in Claude Code
        $target = Resolve-AgentPath (Get-DictValue $A 'file_path') $Session.cwd
        if ($target.StartsWith($Session.cwd.TrimEnd([char]92) + [char]92, [StringComparison]::OrdinalIgnoreCase)) { return @{ action = 'run' } }
        if (Test-ToolAllowed $Session $Name $A) { return @{ action = 'run' } }
        return @{ action = 'ask'; guard = $false; why = 'outside the project folder' }
    }
    if (Test-ToolAllowed $Session $Name $A) { return @{ action = 'run' } }
    return @{ action = 'ask'; guard = $false; why = '' }
}

# --- one request --------------------------------------------------------------------------------

function Clear-OldReasoning($Session) {
    # The thinking of earlier requests is dropped; the chat templates leave it out anyway,
    # only the thinking of the current request goes back to the model.
    foreach ($m in $Session.messages) {
        if ($m['role'] -eq 'assistant' -and ([System.Collections.IDictionary]$m).Contains('reasoning_content')) { $m.Remove('reasoning_content') }
    }
}

function Add-ToolMessage($Session, [string]$Id, [string]$Text) {
    Add-SessionMessage $Session @{ role = 'tool'; tool_call_id = $Id; content = [string]$Text }
}

function Test-JsonObjectText([string]$Text) {
    try { return ((ConvertFrom-AgentJson $Text) -is [System.Collections.IDictionary]) } catch { return $false }
}

function New-AssistantCallMessage($Answer, $Calls) {
    # The answer with its tool calls, as it goes back to the model. Arguments that are not
    # valid JSON are stored as {} (the server would refuse the whole conversation); the
    # model learns from the tool result what was wrong.
    $list = @()
    foreach ($c in $Calls) {
        $argText = [string]$c.arguments
        if (-not (Test-JsonObjectText $argText)) { $argText = '{}' }
        $list += , @{ id = [string]$c.id; type = 'function'; function = @{ name = [string]$c.name; arguments = $argText } }
    }
    $msg = @{ role = 'assistant'; content = [string]$Answer.content; tool_calls = $list }
    if ($Answer.reasoning) { $msg['reasoning_content'] = [string]$Answer.reasoning }
    return $msg
}

function Get-AnswerTokenBudget($Session) {
    # max_tokens of a request: the setting, but never more than the window has room for.
    $max = [int](Get-AgentSettings).maxOutputTokens
    $ctx = Get-SessionContextSize $Session
    $room = $ctx - (Get-EstimatedTokens $Session) - 512
    if ($room -lt $max) { $max = [int][math]::Max(1024, $room) }
    return $max
}

function Invoke-ModelRound($Session, $Schemas) {
    # One answer of the model, shown as it streams in. Tries again once each when the server
    # is down (starts it), the window is full (summarises) or the model takes no images.
    # $null after an error that remains.
    $retried = @{}
    while ($true) {
        Start-UiAnswer
        $charsBefore = Get-SessionChars $Session
        $budget = Get-AnswerTokenBudget $Session
        $Session.lastBudget = $budget
        try {
            $answer = Invoke-ChatStream -Model $Session.model -Messages $Session.messages -Tools $Schemas -MaxTokens $budget `
                -OnEvent {
                    param($kind, $text)
                    if ($kind -eq 'reasoning') { Add-UiReasoning $text }
                    elseif ($kind -eq 'content') { Add-UiContent $text }
                    elseif ($kind -eq 'tool') { Add-UiToolDraft $text }
                } -ShouldStop { Test-UiStop }
            Complete-UiAnswer
            $Session.turns++
            if ($answer.promptTokens -gt 0) {
                $Session.promptTokens = $answer.promptTokens
                $Session.charsAtPrompt = $charsBefore
                $Session.inputTokens += [math]::Max(0, $answer.promptTokens - $answer.cachedTokens)
                $Session.cachedTokens += $answer.cachedTokens
            }
            $Session.outputTokens += $answer.completionTokens
            if ($answer.tokensPerSecond -gt 0) { $Session.tokensPerSecond = $answer.tokensPerSecond }
            $Session.lastFinish = $answer.finish
            return $answer
        } catch {
            Complete-UiAnswer
            $msg = $_.Exception.Message
            if (-not $retried['server'] -and -not (Test-ServerUp)) {
                $retried['server'] = $true
                Write-UiNote (Get-UiText 'notes.serverStarting') 'warn'
                try { foreach ($l in @(Start-Server)) { Write-UiNote ([string]$l) } } catch { Write-UiNote $_.Exception.Message 'error'; return $null }
                continue
            }
            if (-not $retried['context'] -and $msg -match 'context') {
                $retried['context'] = $true
                Write-UiNote (Get-UiText 'notes.contextFull') 'warn'
                if (Invoke-Compaction $Session '') { continue }
            }
            if (-not $retried['image'] -and $msg -match 'image|mmproj|multimodal|vision') {
                $retried['image'] = $true
                if (Remove-SessionImages $Session) {
                    Write-UiNote (Get-UiText 'notes.noImages') 'warn'
                    continue
                }
            }
            Write-UiNote (Get-UiText 'notes.error' $msg) 'error'
            return $null
        }
    }
}

function Remove-SessionImages($Session) {
    # Replaces every image in the conversation by a note. True if there was one.
    $found = $false
    foreach ($m in $Session.messages) {
        $content = $m['content']
        if (-not ($content -is [System.Array])) { continue }
        $parts = @()
        foreach ($p in $content) {
            if ((Get-DictValue $p 'type') -eq 'image_url') { $found = $true; $parts += , @{ type = 'text'; text = '[image left out: this model takes no images]' } }
            else { $parts += , $p }
        }
        $m['content'] = $parts
    }
    return $found
}

function Invoke-ToolCalls($Session, $Calls, $Guard) {
    # Runs the calls of one answer in order; every call gets a result, also when the request
    # was stopped before it. Returns ok, stopped (Esc, a no) or loop.
    $cfg = Get-AgentSettings
    $limit = [math]::Max(2, [int]$cfg.maxRepeats)
    $images = @()
    $outcome = 'ok'
    foreach ($c in $Calls) {
        if ($outcome -ne 'ok') { Add-ToolMessage $Session $c.id 'Not run: the request was stopped.'; continue }
        $argText = [string]$c.arguments
        if (-not $argText.Trim()) { $argText = '{}' }
        $parsed = $null
        try { $parsed = ConvertFrom-AgentJson $argText } catch {}
        Write-UiToolStart $c.name $parsed $Session.cwd
        if (-not ($parsed -is [System.Collections.IDictionary])) {
            $why = 'The arguments of this call are not valid JSON'
            if ($Session.lastFinish -eq 'length') { $why += " (your answer was cut off at the limit of $($Session.lastBudget) tokens: write smaller pieces, for example a shorter file first and the rest with Edit)" }
            $result = New-ToolResult ("$why. They began with: " + $argText.Substring(0, [math]::Min(200, $argText.Length))) $true
            Write-UiToolResult $result $c.name
            Add-ToolMessage $Session $c.id $result.text
            continue
        }

        $decision = Get-CallDecision $Session $c.name $parsed $Guard
        if ($decision.action -eq 'ask') {
            if (-not $script:Ui.on) {
                $why = 'Not allowed in this run: no one is at the terminal to confirm it'
                if ($decision.why) { $why += " ($($decision.why))" }
                $decision = @{ action = 'deny'; why = "$why. Find another way or say in your answer what is needed." }
            } else {
                $reply = Read-UiPermission $c.name (Get-CallPreview $c.name $parsed) $decision.why (-not $decision.guard) $parsed
                if ($reply -eq 'always') { foreach ($r in @(Get-AlwaysRules $c.name $parsed)) { $Session.allowed[$r] = $true } }
                if ($reply -eq 'no') {
                    Add-ToolMessage $Session $c.id 'The user said no to this call. Stop and wait for their instructions.'
                    $outcome = 'stopped'
                    continue
                }
            }
        }
        if ($decision.action -eq 'deny') {
            $Session.denials++
            $result = New-ToolResult $decision.why $true
            if ($Session.denials -ge $limit) {
                $result.text += "`n[Note from Unzensiert: $($Session.denials) calls were refused in this request. Do not try other commands for the same goal: finish what is possible without them and say in your answer what is left.]"
            }
            Write-UiToolResult $result $c.name
            Add-ToolMessage $Session $c.id $result.text
            if ($Session.denials -ge 3 * $limit) {
                Write-UiNote (Get-UiText 'notes.refused' $Session.denials) 'warn'
                $outcome = 'loop'
            }
            continue
        }

        $result = Invoke-AgentTool $Session $c.name $parsed { Test-UiStop }
        if ($result.changed) {
            $Session.answerEdits++
            if (-not $Session.changed.Contains($result.changed)) { $null = $Session.changed.Add($result.changed) }
            Add-HookTranscript $Session $c.name $result.changed $c.id
        }
        # the same call with the same result while the changed files hold the same content: a
        # repeat. The content is part of the print (instead of forgetting all prints on every
        # change), so changing a file back and forth does not hide a loop.
        $fp = Get-TextHash ($c.name + "`n" + $argText + "`n" + (Get-ResultShape ([string]$result.text)) + "`n" + (Get-ChangedFilesState $Session))
        $count = 1
        if ($Session.fingerprints.ContainsKey($fp)) { $count = $Session.fingerprints[$fp] + 1 }
        $Session.fingerprints[$fp] = $count
        $text = [string]$result.text
        if ($count -ge $limit) {
            $text += "`n[Note from Unzensiert: you made exactly this call $count times with the same result and the files unchanged in between. Repeating it will not help: change your approach, or end your answer and say what blocks you.]"
        }
        if ($result.noop) {
            # Edit or Write that leave the file as it is, whatever their arguments
            $Session.noEffect++
            if ($Session.noEffect -ge $limit) {
                $text += "`n[Note from Unzensiert: $($Session.noEffect) of your edits in this request changed nothing; the files already hold that text. Stop editing this place: if a check still fails, read its error message again and look for the cause elsewhere, or end your answer and say what blocks you.]"
            }
        }
        Write-UiToolResult $result $c.name
        Add-ToolMessage $Session $c.id $text
        if ($result.image) { $images += , $result.image }
        if ($result.userStop) { $outcome = 'stopped' }
        elseif ($count -ge 2 * $limit) {
            Write-UiNote (Get-UiText 'notes.repeating' $c.name) 'warn'
            $outcome = 'loop'
        } elseif ($result.noop -and $Session.noEffect -ge 2 * $limit) {
            Write-UiNote (Get-UiText 'notes.noEffect' $Session.noEffect) 'warn'
            $outcome = 'loop'
        }
    }
    if ($images.Count -gt 0) {
        # images reach the model as part of a user message (a tool result can only be text)
        $parts = @(@{ type = 'text'; text = 'The image(s) from your last Read call:' })
        foreach ($img in $images) { $parts += , @{ type = 'image_url'; image_url = @{ url = "data:$($img.mime);base64,$($img.data)" } } }
        Add-SessionMessage $Session @{ role = 'user'; content = $parts }
    }
    return $outcome
}

function Invoke-AgentClosingCheck($Session) {
    # The closing check, when this answer changed files or the check sent the model back.
    # Returns the answer of the hook (decision, reason, systemMessage) or $null.
    if ($Session.answerEdits -eq 0 -and -not $Session.stopActive) { return $null }
    $agent = Get-AgentConfig
    if (-not $agent.stopCheck -or -not $agent.stopCheck.enabled) { return $null }
    Start-UiActivity 'check'
    try {
        $hook = Invoke-StopHook $Session.id $Session.hookTranscript $Session.cwd $Session.stopActive { Test-UiStop }
    } catch {
        Stop-UiActivity
        Write-UiNote (Get-UiText 'notes.checkFailed' $_.Exception.Message) 'warn'
        return $null
    }
    Stop-UiActivity
    if ($hook.cancelled) { Write-UiNote (Get-UiText 'notes.checkStopped') 'warn'; return $null }
    return $hook
}

function Invoke-AgentTurn($Session, $Content) {
    # One request of the user, worked off until the model answers without a tool call.
    # Returns done, stopped (Esc or a no), loop, limit or error.
    $cfg = Get-AgentSettings
    $guard = Get-GuardRules
    $schemas = Get-AgentToolSchemas $Session.gitBash
    Clear-OldReasoning $Session
    if ($Session.pending) {
        # what the user ran with ! since the last request
        if ($Content -is [string]) { $Content = $Session.pending + "`n`n" + $Content }
        else { $Content = @(@{ type = 'text'; text = $Session.pending }) + @($Content) }
        $Session.pending = ''
    }
    Add-SessionMessage $Session @{ role = 'user'; content = $Content }
    $Session.lastPrompt = Get-ContentText $Content
    Add-HookTranscript $Session 'prompt' $Session.lastPrompt
    $Session.stopActive = $false
    $Session.fingerprints = @{}
    $Session.denials = 0
    $Session.noEffect = 0
    $Session.answerEdits = 0
    $Session.lastAnswer = ''
    $maxRounds = [int]$cfg.maxToolRounds
    if ($Session.maxTurns -gt 0) { $maxRounds = [int]$Session.maxTurns }

    for ($round = 1; $round -le $maxRounds; $round++) {
        Invoke-AutoCompact $Session
        $answer = Invoke-ModelRound $Session $schemas
        if ($null -eq $answer) { return 'error' }
        if ($answer.cancelled) {
            $text = [string]$answer.content
            if ($text) { $text += "`n" }
            Add-SessionMessage $Session @{ role = 'assistant'; content = $text + '[stopped by the user]' }
            return 'stopped'
        }
        $calls = @($answer.toolCalls)
        if ($calls.Count -eq 0) {
            $msg = @{ role = 'assistant'; content = [string]$answer.content }
            if ($answer.reasoning) { $msg['reasoning_content'] = [string]$answer.reasoning }
            Add-SessionMessage $Session $msg
            $Session.lastAnswer = [string]$answer.content
            if ($answer.finish -eq 'length') { Write-UiNote (Get-UiText 'notes.cutOff' $Session.lastBudget) 'warn' }
            $hook = Invoke-AgentClosingCheck $Session
            if ($hook -and $hook.decision -eq 'block') {
                $first = ([string]$hook.reason).Split("`n")[0]
                if ($first.Length -gt 110) { $first = $first.Substring(0, 110) + '...' }
                Write-UiNote (Get-UiText 'notes.checkSays' $first) 'warn'
                Add-SessionMessage $Session @{ role = 'user'; content = $script:HookPrefix + "`n" + [string]$hook.reason }
                $Session.stopActive = $true
                continue
            }
            if ($hook -and $hook.systemMessage) { Write-UiNote ([string]$hook.systemMessage) 'warn' }
            return 'done'
        }
        Add-SessionMessage $Session (New-AssistantCallMessage $answer $calls)
        $outcome = Invoke-ToolCalls $Session $calls $guard
        if ($outcome -ne 'ok') { return $outcome }
    }
    Write-UiNote (Get-UiText 'notes.maxRounds' $maxRounds) 'warn'
    return 'limit'
}

# --- context window -----------------------------------------------------------------------------

function Invoke-AutoCompact($Session) {
    # Makes room when the conversation fills "compactAt" of the window: first the old tool
    # results are shortened, if that is not enough the conversation is summarised.
    $cfg = Get-AgentSettings
    $limit = [int]((Get-SessionContextSize $Session) * [double]$cfg.compactAt)
    if ((Get-EstimatedTokens $Session) -lt $limit) { return }
    $saved = Compress-OldToolResults $Session ([int]$cfg.keepRecentRounds) ([int]$cfg.oldToolResultChars)
    if ($saved -gt 0) {
        Write-UiNote (Get-UiText 'notes.shortened' (Format-Number $saved 0))
        if ((Get-EstimatedTokens $Session) -lt $limit) { return }
    }
    $null = Invoke-Compaction $Session ''
}

function Get-CompactionText($Session) {
    # The conversation as plain text for the summary, with long tool results shortened.
    $sb = New-Object System.Text.StringBuilder
    foreach ($m in $Session.messages) {
        $role = [string]$m['role']
        if ($role -eq 'system') { continue }
        if ($role -eq 'user') {
            $null = $sb.Append("## User`n" + (Get-ContentText $m['content']) + "`n`n")
        } elseif ($role -eq 'assistant') {
            $null = $sb.Append("## Assistant`n" + [string]$m['content'] + "`n")
            foreach ($c in @($m['tool_calls'])) {
                if (-not $c) { continue }
                $fn = Get-DictValue $c 'function'
                $a = [string](Get-DictValue $fn 'arguments')
                if ($a.Length -gt 400) { $a = $a.Substring(0, 400) + '...' }
                $null = $sb.Append("-> call $(Get-DictValue $fn 'name') $a`n")
            }
            $null = $sb.Append("`n")
        } elseif ($role -eq 'tool') {
            $t = [string]$m['content']
            if ($t.Length -gt 800) { $t = $t.Substring(0, 800) + "... [$($t.Length) characters]" }
            $null = $sb.Append("## Tool result`n$t`n`n")
        }
    }
    return $sb.ToString()
}

function Invoke-Compaction($Session, [string]$Focus) {
    # Replaces the conversation by a summary the model writes of it, followed by the current
    # request. True if it worked. The session file gets a mark: a resumed session starts there.
    if ($Session.messages.Count -le 2) { Write-UiNote (Get-UiText 'notes.nothingToSummarise'); return $false }
    $text = Get-CompactionText $Session
    # the summary request must fit itself: about 60 % of the window at 3 characters a token
    $maxChars = [int]((Get-SessionContextSize $Session) * 0.6 * 3)
    if ($text.Length -gt $maxChars) { $text = "[... the beginning is left out ...]`n" + $text.Substring($text.Length - $maxChars) }
    $instruction = 'Write a summary of the conversation above for yourself, so that you can continue the work without it. ' +
        'Include: what the user asked for (their words where short), the files read and changed (paths, what changed), ' +
        'decisions and findings, errors and how they were solved, results of tests and checks, the current state, and the next steps. ' +
        'Be concrete: paths, names of functions, commands, numbers. Write only the summary.'
    if ($Focus) { $instruction += " Pay special attention to: $Focus" }
    $request = @(
        @{ role = 'system'; content = 'You summarise the work of a coding agent precisely and completely.' },
        @{ role = 'user'; content = "$text`n`n---`n$instruction" }
    )
    Start-UiActivity 'compact'
    try {
        $answer = Invoke-ChatStream -Model $Session.model -Messages $request -Tools $null -MaxTokens 6000 `
            -OnEvent { param($kind, $t) if ($kind -eq 'reasoning' -or $kind -eq 'content') { Add-UiActivityChars $t.Length } } -ShouldStop { Test-UiStop }
    } catch {
        Stop-UiActivity
        Write-UiNote (Get-UiText 'notes.summaryFailed' $_.Exception.Message) 'error'
        return $false
    }
    Stop-UiActivity
    if ($answer.cancelled -or -not $answer.content.Trim()) { Write-UiNote (Get-UiText 'notes.noSummary') 'warn'; return $false }
    $system = $Session.messages[0]
    $Session.messages.Clear()
    $null = $Session.messages.Add($system)
    try { [System.IO.File]::AppendAllText($Session.file, '{"compact":true}' + "`n", (New-Object System.Text.UTF8Encoding($false))) } catch {}
    $summary = "This conversation was summarised because the context window was full.`n`n" + $answer.content.Trim()
    if ($Session.lastPrompt) { $summary += "`n`nThe last request of the user, word for word:`n" + $Session.lastPrompt }
    $summary += "`n`nContinue from here. Files you read before the summary must be read again before you change them."
    Add-SessionMessage $Session @{ role = 'user'; content = $summary }
    $Session.reads = @{}
    $Session.promptTokens = 0
    $Session.charsAtPrompt = 0
    Write-UiNote (Get-UiText 'notes.summarised' (Get-UiCount (Get-EstimatedTokens $Session) 'tokens')) 'ok'
    return $true
}
