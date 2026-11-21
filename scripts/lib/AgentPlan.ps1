# Planning in the agent Unzensiert: which of its own tools a session offers ("addTools" in
# config\unzensiert.json), the task list (TodoWrite) with the note that sends the model back
# to open steps, questions with choices (AskUserQuestion), the plan the user approves
# (PresentPlan) and plan mode, in which the model researches and plans but changes nothing.
# The terminal side (frames, keys, the list) is in lib\AgentUiPlan.ps1, the web tools in
# lib\AgentWeb.ps1. Used by lib\AgentLoop.ps1, lib\AgentTools.ps1 and lib\AgentPrompt.ps1.
# Keep this file ASCII-only. Description: docs\unzensiert.md.

$script:OwnToolNames = @('TodoWrite', 'AskUserQuestion', 'PresentPlan', 'WebSearch', 'WebFetch')
$script:NotePrefix = '[Note from Unzensiert'

# --- which tools ---------------------------------------------------------------------------------

function Test-WebToolAllowed($Session, [string]$Name) {
    # True if a web tool would run without a question: mode all, or a rule of --allowedTools
    # that names it (WebSearch, WebFetch, WebFetch(domain:...)).
    if ($null -eq $Session) { return $false }
    if ($Session.mode -eq 'all') { return $true }
    foreach ($rule in @($Session.allowedTools)) {
        $r = [string]$rule
        if ($r -eq $Name -or $r.StartsWith($Name + '(', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-AgentOwnTools($Session) {
    # The tools of "addTools" this session offers. Questions and the plan need someone at the
    # terminal; without a terminal the web tools are only offered when they would be allowed,
    # because there every question becomes a refusal. The set stays the same for a session,
    # so the text the server has cached stays valid. Call it as @(Get-AgentOwnTools ...).
    $list = @()
    foreach ($entry in @((Get-AgentSettings).addTools)) {
        $name = [string]$entry
        if ($script:OwnToolNames -notcontains $name) { continue }
        if (($name -eq 'AskUserQuestion' -or $name -eq 'PresentPlan') -and -not $script:Ui.on) { continue }
        if (($name -eq 'WebSearch' -or $name -eq 'WebFetch') -and -not $script:Ui.on -and -not (Test-WebToolAllowed $Session $name)) { continue }
        $list += $name
    }
    return $list
}

# --- task list -----------------------------------------------------------------------------------

function ConvertTo-TodoStatus([string]$Status) {
    # pending, in_progress or completed; the other words local models use for them too.
    $s = ($Status.Trim().ToLowerInvariant() -replace '[\s-]+', '_')
    if (@('completed', 'complete', 'done', 'finished') -contains $s) { return 'completed' }
    if (@('in_progress', 'inprogress', 'active', 'doing', 'started', 'current', 'working') -contains $s) { return 'in_progress' }
    if (@('pending', 'todo', 'open', 'not_started', 'planned', 'waiting', '') -contains $s) { return 'pending' }
    return ''
}

function ConvertTo-TodoList($Value) {
    # The list of a TodoWrite call: @{ todos = @(@{ content; status }); error }. The list may
    # also come as JSON text; a step without a state counts as pending.
    $usage = 'todos must be a list of steps such as [{"content": "Write the parser", "status": "in_progress"}] with the states pending, in_progress and completed.'
    if ($Value -is [string]) {
        try { $Value = ConvertFrom-AgentJson $Value } catch { return @{ todos = @(); error = $usage } }
    }
    if ($null -eq $Value) { return @{ todos = @(); error = $usage } }
    $list = @()
    foreach ($item in @($Value)) {
        if ($item -is [string]) { $item = @{ content = $item } }
        if (-not ($item -is [System.Collections.IDictionary])) { return @{ todos = @(); error = $usage } }
        $content = [string](Get-DictValue $item 'content')
        foreach ($other in 'task', 'title', 'text', 'step') { if (-not $content.Trim()) { $content = [string](Get-DictValue $item $other) } }
        $content = ($content -replace '\s+', ' ').Trim()
        if (-not $content) { continue }
        $status = ConvertTo-TodoStatus ([string](Get-DictValue $item 'status'))
        if (-not $status) { return @{ todos = @(); error = "Unknown state '$(Get-DictValue $item 'status')' of the step '$content'. $usage" } }
        $list += , @{ content = $content; status = $status }
    }
    return @{ todos = $list; error = '' }
}

function Get-OpenTodos($Session) {
    # The steps of the task list that are not completed; call it as @(Get-OpenTodos ...).
    return @(@($Session.todos) | Where-Object { $_ -and $_.status -ne 'completed' })
}

function Format-TodoLines($Todos) {
    # The list as text for the model: [x] completed, [>] in progress, [ ] pending.
    $lines = @()
    foreach ($t in @($Todos)) {
        if (-not $t) { continue }
        $mark = '[ ]'
        if ($t.status -eq 'completed') { $mark = '[x]' } elseif ($t.status -eq 'in_progress') { $mark = '[>]' }
        $lines += "$mark $($t.content)"
    }
    return ($lines -join "`n")
}

function Invoke-ToolTodoWrite($Session, $A) {
    # Keeps the whole list the model sends; the terminal shows it (lib\AgentUiPlan.ps1).
    $parsed = ConvertTo-TodoList (Get-DictValue $A 'todos')
    if ($parsed.error) { return (New-ToolResult $parsed.error $true) }
    $Session.todos = @($parsed.todos)
    $total = $Session.todos.Count
    $done = @($Session.todos | Where-Object { $_.status -eq 'completed' }).Count
    $active = @($Session.todos | Where-Object { $_.status -eq 'in_progress' })
    if ($total -eq 0) { $text = 'The task list is empty now.' }
    elseif ($done -eq $total) { $text = "All $total steps of the task list are completed." }
    else {
        $next = $active | Select-Object -First 1
        if (-not $next) { $next = @(Get-OpenTodos $Session)[0] }
        $text = "Task list saved: $total steps, $done completed, $($active.Count) in progress, $($total - $done - $active.Count) pending. Now: $($next.content)"
        if ($active.Count -gt 1) { $text += "`nKeep only one step in_progress: finish it and mark it completed before you start the next one." }
    }
    $r = New-ToolResult $text
    $r.summary = "$done/$total"
    $r.info = @{ todos = $Session.todos }
    return $r
}

function Get-TodoReminder($Session) {
    # The note that sends the model back to the open steps of its task list, or '' when none
    # is due: only in a request in which it used tools, not in plan mode, and at most
    # "todoReminders" times per request.
    $open = @(Get-OpenTodos $Session)
    if ($open.Count -eq 0 -or $Session.requestTools -eq 0 -or $Session.mode -eq 'plan') { return '' }
    if ($Session.todoReminders -ge [int](Get-AgentSettings).todoReminders) { return '' }
    $Session.todoReminders++
    $decide = 'if only the user can decide something, ask with AskUserQuestion'
    if (@(Get-AgentOwnTools $Session) -notcontains 'AskUserQuestion') { $decide = 'if a step needs a decision only the user can make, take it off the list and name it in your final report' }
    return "$($script:NotePrefix): your task list still has $($open.Count) open step(s):`n" + (Format-TodoLines $open) +
        "`nGo on with the next step now. If a step is no longer needed, take it off the list with TodoWrite; $decide. End your answer only when the list is done.]"
}

function Restore-SessionTodos($Session) {
    # The task list of a resumed conversation: the last valid TodoWrite call in its messages.
    $Session.todos = @()
    foreach ($m in @($Session.messages)) {
        if ((Get-DictValue $m 'role') -ne 'assistant') { continue }
        $calls = Get-DictValue $m 'tool_calls'
        foreach ($c in @($calls)) {
            if (-not $c) { continue }
            $fn = Get-DictValue $c 'function'
            if ((Get-DictValue $fn 'name') -ne 'TodoWrite') { continue }
            try { $parsed = ConvertTo-TodoList (Get-DictValue (ConvertFrom-AgentJson ([string](Get-DictValue $fn 'arguments'))) 'todos') } catch { continue }
            if (-not $parsed.error) { $Session.todos = @($parsed.todos) }
        }
    }
}

# --- questions -------------------------------------------------------------------------------------

function ConvertTo-QuestionList($Value) {
    # The questions of an AskUserQuestion call: @{ questions = @(@{ question; header; multi;
    # options = @(@{ label; description }) }); error }. At most four questions with six
    # options each; options may also come as plain words.
    $usage = 'questions must be a list such as [{"question": "Which database?", "header": "Database", "options": [{"label": "SQLite (Recommended)", "description": "one file, no server"}, {"label": "PostgreSQL", "description": "a server"}]}].'
    if ($Value -is [string]) { try { $Value = ConvertFrom-AgentJson $Value } catch { return @{ questions = @(); error = $usage } } }
    if ($Value -is [System.Collections.IDictionary]) { $Value = @($Value) }
    $list = @()
    foreach ($q in @($Value)) {
        if (-not ($q -is [System.Collections.IDictionary])) { continue }
        $text = ([string](Get-DictValue $q 'question')).Trim()
        if (-not $text) { continue }
        $options = @()
        # Get-DictValue keeps a list whole: assigned first, then made a list with @()
        $given = Get-DictValue $q 'options'
        foreach ($o in @($given)) {
            if ($null -eq $o) { continue }
            if ($o -is [string]) { if ($o.Trim()) { $options += , @{ label = $o.Trim(); description = '' } }; continue }
            if (-not ($o -is [System.Collections.IDictionary])) { continue }
            $label = ([string](Get-DictValue $o 'label')).Trim()
            if ($label) { $options += , @{ label = $label; description = ([string](Get-DictValue $o 'description')).Trim() } }
        }
        if ($options.Count -gt 6) { $options = $options[0..5] }
        $multi = Get-DictValue $q 'multiSelect'
        if ($multi -is [string]) { $multi = ($multi -eq 'true') }
        $list += , @{ question = $text; header = ([string](Get-DictValue $q 'header')).Trim(); multi = [bool]$multi; options = $options }
    }
    if ($list.Count -eq 0) { return @{ questions = @(); error = $usage } }
    if ($list.Count -gt 4) { $list = $list[0..3] }
    return @{ questions = $list; error = '' }
}

function ConvertFrom-QuestionReply($Question, [string]$Reply) {
    # What the user typed for a question: option numbers (several, separated by commas or
    # spaces, when the question allows it) become their labels, anything else is an answer
    # of their own. @{ answer; own }; answer '' for an empty reply.
    $r = $Reply.Trim()
    if (-not $r) { return @{ answer = ''; own = $false } }
    $count = @($Question.options).Count
    $pattern = '^\d+$'
    if ($Question.multi) { $pattern = '^\d+([\s,;]+\d+)*$' }
    if ($count -gt 0 -and $r -match $pattern) {
        $labels = @()
        foreach ($piece in ($r -split '[\s,;]+')) {
            $n = [int]$piece
            if ($n -lt 1 -or $n -gt $count) { $labels = @(); break }
            $label = [string]$Question.options[$n - 1].label
            if ($labels -notcontains $label) { $labels += $label }
        }
        if ($labels.Count -gt 0) { return @{ answer = ($labels -join ', '); own = $false } }
    }
    return @{ answer = $r; own = $true }
}

function Format-QuestionAnswers($Questions, $Answers) {
    # The answers for the model, each after its question.
    $lines = @('The user answered:')
    for ($i = 0; $i -lt @($Questions).Count; $i++) {
        $a = $Answers[$i]
        $shown = [string]$a.answer
        if (-not $shown) { $shown = '(no answer)' } elseif ($a.own) { $shown = "(own answer) $shown" }
        $lines += "- `"$($Questions[$i].question)`" -> $shown"
    }
    $lines += 'Go on with these answers.'
    return ($lines -join "`n")
}

function Invoke-ToolAskUser($Session, $A) {
    # Asks the questions one after the other at the terminal (Read-UiQuestion). Esc stops the
    # request, as a no to a call does.
    $parsed = ConvertTo-QuestionList (Get-DictValue $A 'questions')
    if ($parsed.error) { return (New-ToolResult $parsed.error $true) }
    if (-not $script:Ui.on) {
        return (New-ToolResult 'No one is at the terminal to answer. Decide yourself: take the option that fits the request and the project best, name it as an assumption in your final report, and go on.')
    }
    $questions = @($parsed.questions)
    $answers = @()
    for ($i = 0; $i -lt $questions.Count; $i++) {
        $reply = Read-UiQuestion $questions[$i] ($i + 1) $questions.Count
        if ($reply.stopped) {
            $r = New-ToolResult 'The user stopped instead of answering. Stop and wait for their instructions.'
            $r.userStop = $true
            return $r
        }
        $answers += , $reply
    }
    $r = New-ToolResult (Format-QuestionAnswers $questions $answers)
    $r.summary = (@($answers | ForEach-Object { [string]$_.answer }) -join ' / ')
    return $r
}

# --- the plan and plan mode ------------------------------------------------------------------------

function Get-ModeAfterPlan($Session) {
    # The rights mode once a plan is approved: the mode before plan mode, otherwise ask; outside
    # plan mode the mode stays.
    if ($Session.mode -ne 'plan') { return $Session.mode }
    if (@('ask', 'edits', 'all') -contains $Session.modeBeforePlan) { return $Session.modeBeforePlan }
    return 'ask'
}

function Invoke-ToolPresentPlan($Session, $A) {
    # Shows the plan and waits for the user: y approve, e approve and let file changes run
    # without asking, n say what should change, Esc stop. Approving ends plan mode.
    $plan = ([string](Get-DictValue $A 'plan')).Trim()
    if (-not $plan) { return (New-ToolResult 'plan is empty: write the plan in Markdown into plan.' $true) }
    if (-not $script:Ui.on) {
        if ($Session.mode -eq 'plan') { return (New-ToolResult 'No one is at the terminal to approve the plan. End your answer now and give the plan as your final answer.') }
        return (New-ToolResult 'Approved without a question: no one is at the terminal. Work through the plan now.')
    }
    $after = Get-ModeAfterPlan $Session
    $offerEdits = @('edits', 'all') -notcontains $after
    $reply = Read-UiPlanApproval $plan $offerEdits
    $wasPlan = ($Session.mode -eq 'plan')
    if ($reply.choice -eq 'stop' -or ($reply.choice -eq 'no' -and -not $reply.feedback)) {
        $r = New-ToolResult 'The user did not approve the plan. Stop and wait for their instructions.'
        $r.userStop = $true
        return $r
    }
    if ($reply.choice -eq 'no') {
        return (New-ToolResult ("The user did not approve the plan. What they want changed: $($reply.feedback)`nChange the plan accordingly (ask if something is unclear) and present it again with PresentPlan."))
    }
    if ($reply.choice -eq 'edits') { $after = 'edits' }
    $Session.mode = $after
    $text = 'The user approved the plan. Work through it now step by step without stopping, and keep the task list up to date.'
    if ($wasPlan) { $text += ' Plan mode is over: you may change files now.' }
    if ($after -eq 'edits') { $text += ' File changes in the project folder run without a question.' }
    $r = New-ToolResult $text
    $r.summary = $after
    return $r
}

function Get-PlanModeNote($Session) {
    # Added to every request in plan mode, after the text of the user.
    $own = @(Get-AgentOwnTools $Session)
    $ask = ''
    if ($own -contains 'AskUserQuestion') { $ask = ' ask with AskUserQuestion where the request leaves decisions open,' }
    $how = 'give the plan as your final answer'
    if ($own -contains 'PresentPlan') { $how = 'present the plan with PresentPlan and wait for the approval' }
    return "$($script:NotePrefix): plan mode is on. Research and plan, but change nothing yet: read files and look things up,$ask write the steps into the task list (TodoWrite) and $how. File changes are refused until the plan is approved.]"
}

function Get-PlanModeRefusal($Session) {
    # Why a change is refused in plan mode.
    $how = 'give the plan as your final answer'
    if (@(Get-AgentOwnTools $Session) -contains 'PresentPlan') { $how = 'present your plan with PresentPlan; once the user approves it, you may change files' }
    return "Plan mode is on: no changes before the user has approved your plan. Finish your research and $how."
}
