# The agent loop of Unzensiert: a request of the user becomes rounds of model answer and
# tool calls until the model answers without a call. Before a call runs, the guard
# (scripts\hooks\GuardRules.ps1, config\guard.json) and the permission mode decide; when the
# model wants to end an answer in which it changed files, the closing check runs
# (scripts\hooks\Check-Stop.ps1, "stopCheck" in config\agent.json); before that, open steps of
# the task list send it back to work (lib\AgentPlan.ps1). In plan mode file changes are
# refused until the user approves the plan. Also here: shortening and summarising the
# conversation when the context window fills up. The commands typed with a slash and the
# loops for the terminal and for one-shot runs are in lib\AgentRepl.ps1.
# Needs lib\AgentApi.ps1, AgentTools.ps1, AgentPlan.ps1, AgentWeb.ps1, AgentSession.ps1,
# AgentUi.ps1, CommandRules.ps1, Trust.ps1 and lib\Quality.ps1. Keep this file ASCII-only.
# Description: docs\unzensiert.md.

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'hooks\GuardRules.ps1')
# Grep and Glob leave protected files out by themselves (lib\AgentTools.ps1)
$script:GuardOwnTools = $true

# the order of Shift+Tab, as in Claude Code: plan mode after edits, everything allowed last
$script:ModeOrder = @('ask', 'edits', 'plan', 'all')
$script:ReadOnlyTools = @('Read', 'Glob', 'Grep')
$script:FileTools = @('Edit', 'EditLines', 'Write')
# tools that change nothing and reach nobody: they need no permission in any mode
$script:FreeTools = @('TodoWrite', 'AskUserQuestion', 'PresentPlan')
# tools that reach the internet: a question except in mode all
$script:WebTools = @('WebSearch', 'WebFetch')

function Get-CanonicalToolName([string]$Name) {
    # EditLines is Unzensiert's own way of editing: for the guard, the rights of a session
    # and the transcript of the closing check it is an Edit, so no rule is weaker for it.
    if ($Name -eq 'EditLines') { return 'Edit' }
    return $Name
}
$script:HookPrefix = 'Stop hook feedback:'
$script:Md5 = [System.Security.Cryptography.MD5]::Create()

# --- helpers ----------------------------------------------------------------------------------

function ConvertTo-PermissionMode([string]$Name) {
    # ask, edits, plan or all; the names of Claude Code (default, acceptEdits, plan,
    # bypassPermissions) are understood too. '' for an unknown name.
    $n = $Name.ToLowerInvariant()
    if (@('ask', 'default', 'dontask') -contains $n) { return 'ask' }
    if ($n -eq 'plan') { return 'plan' }
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

function Test-ToolAllowed($Session, [string]$Name, $A, $Guard = $null) {
    # True if the call runs without a question by a rule or because it only reads. What cannot be
    # worked out (a path that is none) is not allowed, so it asks.
    try { return [bool](Test-ToolCovered $Session $Name $A $Guard) } catch { return $false }
}

function Test-ToolCovered($Session, [string]$Name, $A, $Guard = $null) {
    # True if --allowedTools or an "always" answer of this session covers the call. For a
    # command, every part of it must be covered, only read, or (mode edits) only change files of
    # the project; a line that is not understood is covered by a rule for the whole tool or for
    # exactly this line.
    $rules = @($Session.allowedTools) + @($Session.allowed.Keys)
    $Name = Get-CanonicalToolName $Name
    if ($script:WebTools -contains $Name) {
        # WebSearch or WebFetch as a whole, or WebFetch(domain:example.com) for that host and
        # the hosts below it
        $hostName = ''
        if ($Name -eq 'WebFetch') { $hostName = Get-WebHost ([string](Get-DictValue $A 'url')) }
        foreach ($rule in $rules) {
            $r = [string]$rule
            if ($r -eq $Name) { return $true }
            if ($hostName -and $Name -eq 'WebFetch' -and $r -match '^WebFetch\(domain:(.+)\)$') {
                $want = $Matches[1].Trim().ToLowerInvariant()
                if ($hostName -eq $want -or $hostName.EndsWith('.' + $want)) { return $true }
            }
        }
        return $false
    }
    if ($Name -eq 'Bash' -or $Name -eq 'PowerShell') {
        $command = [string](Get-DictValue $A 'command')
        if (-not $command.Trim()) { return $false }
        foreach ($rule in $rules) { if ([string]$rule -ceq $Name -or [string]$rule -ceq "$Name($command)") { return $true } }
        $parts = Read-CommandLine $Name $command $false
        if ($null -eq $parts -or @($parts).Count -eq 0) { return $false }
        $state = New-ReadState $Session.cwd
        $away = $false
        $more = $false
        foreach ($part in @($parts)) {
            $writes = @($part.writes)
            $alone = Read-CommandLine $Name ([string]$part.text) $true
            # what comes in through a pipe counts for it as well
            if ($null -ne $alone -and @($alone).Count -eq 1) { @($alone)[0]['before'] = $part.before }
            if ($writes.Count -eq 0 -and $null -ne $alone -and @($alone).Count -eq 1 -and (Test-ReadOnlyPart @($alone)[0] $Name $state $Session.cwd $Guard)) { continue }
            if ([string]$part.words[0] -match '^(cd|chdir|pushd|popd|sl|set-location|push-location|pop-location)$') {
                # a "cd" that leads somewhere else: nothing reads, writes or runs there without a
                # question, except by a rule given on the command line
                $state.folder = ''
                $state.folders = @()
                $away = $true
                $to = [string](@($part.words)[1])
                if ($writes.Count -eq 0 -and @($part.words).Count -eq 2 -and -not $part.vars -and $to -notmatch '[$%]' -and (Test-PlainArgument $to) -and @('network', 'device') -notcontains [string](Get-PathFacts $to $Session.cwd).kind -and @('network', 'device') -notcontains [string](Get-ShellPath $Name $to $Session.cwd).kind) { continue }
            }
            # a command that only changes files of the project, wherever in it the line stands by then
            $files = ($null -ne $alone -and @($alone).Count -eq 1 -and @($state.folders).Count -gt 0)
            if ($files) { foreach ($f in @($state.folders)) { if (-not (Test-ProjectFileCommand @($alone)[0] $Name $Session.cwd $f $Guard)) { $files = $false; break } } }
            if ($Session.mode -eq 'edits' -and $files) { $more = $true; $state.changed = $true; continue }
            $ok = $false
            foreach ($rule in $rules) {
                if ($away -and @($Session.allowedTools) -cnotcontains $rule) { continue }
                if ([string]$rule -match '(?s)^(\w+)\((.+)\)$' -and $Matches[1] -eq $Name -and (Test-CommandPattern $part $Matches[2])) {
                    $ok = $true
                    # "always" for cp, mv, rm ... means files of the project that are not protected,
                    # like "always" for Edit; a rule given on the command line holds as it is
                    if (@($Session.allowedTools) -cnotcontains $rule -and @((Get-AgentSettings).fileCommands) -contains ([string]$part.words[0]).ToLowerInvariant()) {
                        $ok = $files
                    }
                    if ($ok) { break }
                }
            }
            # output of a covered program may go into files of the project, nowhere else
            if ($ok) {
                foreach ($target in $writes) {
                    if (@('/dev/null', '$null', 'nul', '/dev/stderr', '/dev/stdout') -contains $target.ToLowerInvariant()) { continue }
                    if (@($state.folders).Count -eq 0 -or $target -match '[$%*?]') { $ok = $false; break }
                    foreach ($f in @($state.folders)) {
                        if (-not (Test-InProject $target $Session.cwd $false $f $Name) -or (Test-ProtectedFile ((Get-ShellPath $Name $target $f).full) $Session.cwd $Guard)) { $ok = $false; break }
                    }
                }
            }
            if (-not $ok) { return $false }
            $more = $true
            $state.changed = $true
        }
        # nothing but reading: then the line as a whole has to be a reading one, too
        if (-not $more) { return (Test-ReadOnlyCommand $command $Name $Session.cwd $Guard) }
        return $true
    }
    # file changes: "always" means the files of the project, except those that run later by
    # themselves; a rule with a pattern on the command line may name others
    $path = [string](Get-DictValue $A 'file_path')
    $inside = Test-InProject $path $Session.cwd $false
    foreach ($rule in $rules) {
        if ($inside -and $rule -eq $Name) { return $true }
        if ([string]$rule -match '^(\w+)\((.+)\)$' -and $Matches[1] -eq $Name) {
            $glob = $Matches[2]
            $f = Get-PathFacts $path $Session.cwd
            if (-not $f.ok) { continue }
            if ((ConvertTo-GlobRegex $glob).IsMatch((Get-DisplayPath $f.full $Session.cwd).Replace('\', '/')) -and ($inside -or $f.full -ieq $f.real)) { return $true }
        }
    }
    return $false
}

function Get-AlwaysRules([string]$Name, $A) {
    # What an "always" answer allows for the rest of the session: for a command its programs
    # (Get-CommandRule: with the subcommand for git, npm and the like, for an interpreter only the
    # script or module), for a file change all changes to files of the project, for a web search
    # all searches, for a web page all pages of its host.
    if ($script:FileTools -contains $Name) { return @('Edit', 'Write') }   # EditLines counts as Edit
    if ($Name -eq 'WebSearch') { return @('WebSearch') }
    if ($Name -eq 'WebFetch') {
        $hostName = Get-WebHost ([string](Get-DictValue $A 'url'))
        if ($hostName) { return @("WebFetch(domain:$hostName)") }
        return @('WebFetch')
    }
    $command = [string](Get-DictValue $A 'command')
    $parts = Read-CommandLine $Name $command $false
    # a line nobody can take apart: only exactly this line
    if ($null -eq $parts -or @($parts).Count -eq 0) { return @("$Name($command)") }
    $rules = @()
    foreach ($part in @($parts)) {
        if (@($part.writes).Count -eq 0 -and (Test-ReadOnlyCommand ([string]$part.text) $Name $script:Ui.toolCwd)) { continue }
        $rule = Get-CommandRule $part $Name
        if ($rules -cnotcontains $rule) { $rules += $rule }
    }
    return $rules
}

function Get-CallPreview([string]$Name, $A) {
    # What the question before a call shows: the command, or the path with the change.
    $plain = ConvertTo-PlainHashtable $A
    $text = Get-GuardSubject (Get-CanonicalToolName $Name) $plain
    if ($Name -eq 'WebSearch') { $text = [string]$plain['query'] }
    elseif ($Name -eq 'WebFetch') { $text = [string]$plain['url'] }
    elseif ($Name -eq 'EditLines') {
        $text += "`n" + (Get-UiText 'tools.range' ([int]$plain['start_line']) ([int]$plain['end_line']))
        $text += "`n" + ((@(([string]$plain['new_text']).Replace("`r", '').Split("`n") | ForEach-Object { "+ $_" })) -join "`n")
    } elseif ($Name -eq 'Edit') {
        $old = @(([string]$plain['old_string']).Replace("`r", '').Split("`n") | ForEach-Object { "- $_" })
        $new = @(([string]$plain['new_string']).Replace("`r", '').Split("`n") | ForEach-Object { "+ $_" })
        $text += "`n" + ((@($old) + @($new)) -join "`n")
    } elseif ($Name -eq 'Write') {
        $text += "`n" + ((@(([string]$plain['content']).Replace("`r", '').Split("`n") | ForEach-Object { "+ $_" })) -join "`n")
    }
    return $text
}

function Get-CallTarget($Session, [string]$Name, $A) {
    # What the path of a file tool means (Get-PathFacts), $null for other tools and for Glob and
    # Grep without a path.
    $field = ''
    if (@('Read', 'Edit', 'EditLines', 'Write') -contains $Name) { $field = 'file_path' }
    elseif (@('Glob', 'Grep') -contains $Name) { $field = 'path' }
    if (-not $field) { return $null }
    $value = [string](Get-DictValue $A $field)
    if (-not $value -and $field -eq 'path') { return $null }
    return (Get-PathFacts $value $Session.cwd)
}

function Get-CallDecision($Session, [string]$Name, $A, $Guard) {
    # How a call goes ahead: @{ action = run, ask or deny; why; guard; noAlways; real }. The guard
    # decides first and in every mode; then the mode and the rules of the session. noAlways: a
    # question that "always" cannot answer; real: the file the decision is about.
    $plain = ConvertTo-PlainHashtable $A
    $guardName = Get-CanonicalToolName $Name
    $target = Get-CallTarget $Session $Name $A
    $real = ''
    if ($target) {
        if (-not $target.ok) { return @{ action = 'deny'; guard = $false; why = "This path cannot be used: $($target.reason)."; real = '' } }
        $real = [string]$target.real
    }
    $verdict = Invoke-GuardCheck $guardName $plain $Session.cwd $Guard
    if ($verdict.decision -ne 'none') { Write-GuardLog $guardName (Get-GuardSubject $guardName $plain) $verdict }
    if ($verdict.decision -eq 'deny') {
        return @{ action = 'deny'; guard = $true; why = "Blocked by the guard of Unzensiert (rule $($verdict.rule)): $($verdict.reason). It protects the user's computer; do not try to get around it."; real = $real }
    }
    if ($verdict.decision -eq 'ask') { return @{ action = 'ask'; guard = $true; why = "guard rule $($verdict.rule): $($verdict.reason)"; real = $real } }
    if ($script:ReadOnlyTools -contains $Name -or $script:FreeTools -contains $Name) { return @{ action = 'run'; real = $real } }
    if ($script:WebTools -contains $Name) {
        # search terms and addresses leave the computer: the user sees them first
        if ($Session.mode -eq 'all' -or (Test-ToolAllowed $Session $Name $A $Guard)) { return @{ action = 'run' } }
        return @{ action = 'ask'; guard = $false; why = 'web' }
    }
    if (($Name -eq 'Bash' -or $Name -eq 'PowerShell') -and [bool]$Session.sandbox -and [bool](Get-DictValue $A 'outside_sandbox')) {
        # out of the sandbox (lib\Sandbox.ps1): the user decides every time, in every mode
        return @{ action = 'ask'; guard = $false; noAlways = $true; why = 'outside the sandbox' }
    }
    if ($Session.mode -eq 'plan') {
        # research yes, changes no: file changes are refused, commands that only read run,
        # other commands ask (some only look something up)
        if ($script:FileTools -contains $Name) { return @{ action = 'deny'; guard = $false; why = (Get-PlanModeRefusal $Session); real = $real } }
        if ($Name -eq 'Bash' -or $Name -eq 'PowerShell') {
            if (Test-ToolAllowed $Session $Name $A $Guard) { return @{ action = 'run' } }
            foreach ($part in [regex]::Split([string](Get-DictValue $A 'command'), '[;|&\r\n]+')) {
                $first = @(Get-CommandTokens $part)
                if ($first.Count -gt 0 -and @((Get-AgentSettings).fileCommands) -contains ([string]$first[0]).ToLowerInvariant()) {
                    return @{ action = 'deny'; guard = $false; why = (Get-PlanModeRefusal $Session) }
                }
            }
            return @{ action = 'ask'; guard = $false; why = 'plan' }
        }
    }
    if ($Session.mode -eq 'all') { return @{ action = 'run'; real = $real } }
    if ($script:FileTools -contains $Name) {
        $path = [string](Get-DictValue $A 'file_path')
        # a rule with a pattern on the command line may name any file
        $named = (@($Session.allowedTools | Where-Object { [string]$_ -match '^\w+\(' }).Count -gt 0 -and (Test-ToolAllowed $Session $Name $A $Guard))
        if (-not $named) {
            # files that run or are obeyed later by themselves, and files outside the project: the
            # user decides every time
            if (Test-ProtectedFile $path $Session.cwd $Guard) { return @{ action = 'ask'; guard = $false; noAlways = $true; why = 'protected'; real = $real } }
            if (-not (Test-InProject $path $Session.cwd $false)) { return @{ action = 'ask'; guard = $false; noAlways = $true; why = 'outside the project folder'; real = $real } }
        }
        if ($Session.mode -eq 'edits' -or $named -or (Test-ToolAllowed $Session $Name $A $Guard)) { return @{ action = 'run'; real = $real } }
        return @{ action = 'ask'; guard = $false; why = ''; real = $real }
    }
    if (Test-ToolAllowed $Session $Name $A $Guard) { return @{ action = 'run' } }
    return @{ action = 'ask'; guard = $false; why = '' }
}

# --- one request --------------------------------------------------------------------------------

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
        $parallel = [bool](Get-AgentSettings).parallelToolCalls
        try {
            $answer = Invoke-ChatStream -Model $Session.model -Messages $Session.messages -Tools $Schemas -MaxTokens $budget -ParallelToolCalls $parallel `
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

        try { $decision = Get-CallDecision $Session $c.name $parsed $Guard }
        catch { $decision = @{ action = 'deny'; guard = $false; why = "The call could not be checked ($($_.Exception.Message)), so it does not run." } }
        $asked = $false
        if ($decision.action -eq 'ask') {
            if (-not $script:Ui.on) {
                $why = 'Not allowed in this run: no one is at the terminal to confirm it'
                $reason = [string]$decision.why
                if ($reason -eq 'plan') { $reason = 'plan mode is on, only commands that read run' }
                elseif ($reason -eq 'protected') { $reason = 'this file runs or is obeyed later by itself' }
                elseif ($reason -eq 'web') { $reason = 'it would reach the internet' }
                if ($reason) { $why += " ($reason)" }
                $decision = @{ action = 'deny'; why = "$why. Find another way or say in your answer what is needed." }
            } else {
                $reply = Read-UiPermission $c.name (Get-CallPreview $c.name $parsed) $decision.why (-not $decision.guard -and -not $decision.noAlways) $parsed ([bool]$decision.guard)
                $asked = $true
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

        # the same file as at the decision? (a link changed in between leads somewhere else)
        if ($decision.real) {
            $again = Get-CallTarget $Session $c.name $parsed
            if (-not $again -or -not $again.ok -or $again.real -ine $decision.real) {
                $result = New-ToolResult 'Not run: the path leads to another file now than when it was checked. Try again.' $true
                Write-UiToolResult $result $c.name
                Add-ToolMessage $Session $c.id $result.text
                continue
            }
        }
        # the project folder as it was before this request, for /undo (lib\Undo.ps1); a failure
        # there only ends /undo for this conversation, never the work
        try { if (Test-UndoChange $Session $c.name $parsed) { Save-UndoBefore $Session $c.name $parsed } }
        catch { if ($Session.undo) { Set-UndoOff $Session 'error' $_.Exception.Message } }
        $result = Invoke-AgentTool $Session $c.name $parsed { Test-UiStop }
        if ($result.changed -and $asked) { Update-TrustAfterWrite $Session $result.changed ($c.name -ceq 'Write') }
        if ($result.changed) {
            $Session.answerEdits++
            if (-not $Session.changed.Contains($result.changed)) { $null = $Session.changed.Add($result.changed) }
            Add-HookTranscript $Session (Get-CanonicalToolName $c.name) $result.changed $c.id
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
        if ($c.name -eq 'TodoWrite' -and @($Calls).Count -eq 1 -and -not $result.error -and @(Get-OpenTodos $Session).Count -gt 0 -and [bool]$cfg.parallelToolCalls) {
            # a list update alone costs a whole round of the model: next time with the next call
            $text += "`n[Note from Unzensiert: this update came in an answer of its own. Send the next one in the same answer as the first tool call of the step you start.]"
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
    # the check command of the project runs only with the user's yes (lib\Trust.ps1)
    $runCheck = $false
    try { $runCheck = Test-CheckAllowed $Session } catch {}
    Start-UiActivity 'check'
    try {
        $hook = Invoke-StopHook $Session.id $Session.hookTranscript $Session.cwd $Session.stopActive { Test-UiStop } $runCheck
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
    $guard = Get-SessionGuard $Session
    $schemas = Get-AgentToolSchemas $Session.gitBash @(Get-AgentOwnTools $Session) ([bool]$Session.sandbox)
    # The thinking of earlier requests stays in the conversation: the chat templates show it
    # (preserve_thinking), so removing it would change the text the server has cached and make
    # it read the whole previous request again (21k tokens, 22 s measured, docs\unzensiert.md).
    # Compress-OldToolResults drops it from old rounds when room is needed.
    if ($Session.pending) {
        # what the user ran with ! since the last request
        if ($Content -is [string]) { $Content = $Session.pending + "`n`n" + $Content }
        else { $Content = @(@{ type = 'text'; text = $Session.pending }) + @($Content) }
        $Session.pending = ''
    }
    $Session.lastPrompt = Get-ContentText $Content
    if ($Session.mode -eq 'plan') {
        # the note goes with the request, the words of the user stay the last prompt
        $note = Get-PlanModeNote $Session
        if ($Content -is [string]) { $Content = $Content + "`n`n" + $note }
        else { $Content = @($Content) + @(@{ type = 'text'; text = $note }) }
    }
    Add-SessionMessage $Session @{ role = 'user'; content = $Content }
    Add-HookTranscript $Session 'prompt' $Session.lastPrompt
    $Session.stopActive = $false
    $Session.fingerprints = @{}
    $Session.denials = 0
    $Session.noEffect = 0
    $Session.answerEdits = 0
    $Session.lastAnswer = ''
    $Session.requestTools = 0
    $Session.todoReminders = 0
    $Session.emptyAnswers = 0
    $maxRounds = [int]$cfg.maxToolRounds
    if ($Session.maxTurns -gt 0) { $maxRounds = [int]$Session.maxTurns }
    try { Start-UndoRequest $Session $Session.lastPrompt } catch {}
    # the end of the request also keeps the project folder for /undo, however it ends
    try {
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
                # neither text nor a tool call: the model thought but gave no result, which is no
                # end of the work (it failed the task pinwechsel of the run plan1 after two rounds)
                if (-not ([string]$answer.content).Trim() -and $Session.emptyAnswers -lt [int]$cfg.emptyAnswerNotes) {
                    $Session.emptyAnswers++
                    Write-UiNote (Get-UiText 'notes.emptyAnswer') 'warn'
                    Add-SessionMessage $Session @{ role = 'user'; content = "$($script:NotePrefix): your answer was empty, without text and without a tool call. Go on with the task: make the tool call you planned next, or give your final report.]" }
                    continue
                }
                # open steps of the task list first: the work is not done yet
                $reminder = Get-TodoReminder $Session
                if ($reminder) {
                    $openCount = @(Get-OpenTodos $Session).Count
                    Write-UiNote (Get-UiText 'notes.todoOpen' (Get-UiCount $openCount 'steps')) 'warn'
                    Add-SessionMessage $Session @{ role = 'user'; content = $reminder }
                    continue
                }
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
            $Session.requestTools += $calls.Count
            $outcome = Invoke-ToolCalls $Session $calls $guard
            if ($outcome -ne 'ok') { return $outcome }
        }
        Write-UiNote (Get-UiText 'notes.maxRounds' $maxRounds) 'warn'
        return 'limit'
    } finally {
        try { $null = Complete-UndoRequest $Session } catch { if ($Session.undo) { Set-UndoOff $Session 'error' $_.Exception.Message } }
    }
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
    # the task list survives word for word: it is what keeps a long piece of work on track
    if (@($Session.todos).Count -gt 0) { $summary += "`n`nYour task list (TodoWrite) at the time of the summary:`n" + (Format-TodoLines $Session.todos) }
    $summary += "`n`nContinue from here. Files you read before the summary must be read again before you change them."
    Add-SessionMessage $Session @{ role = 'user'; content = $summary }
    $Session.reads = @{}
    $Session.promptTokens = 0
    $Session.charsAtPrompt = 0
    Write-UiNote (Get-UiText 'notes.summarised' (Get-UiCount (Get-EstimatedTokens $Session) 'tokens')) 'ok'
    return $true
}
