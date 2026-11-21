# Planning at the terminal of Unzensiert (lib\AgentPlan.ps1): the task list under a TodoWrite
# call (done steps struck through, the current one bright), the current step in the activity
# line, the frame of a question with numbered choices, and the plan with the keys to approve
# it. Keep this file ASCII-only.

function Set-UiStep($Todos) {
    # The step in progress, which the activity line shows instead of a word of the style.
    $script:Ui.step = ''
    foreach ($t in @($Todos)) {
        if ($t -and $t.status -eq 'in_progress') { $script:Ui.step = [string]$t.content; break }
    }
}

function Get-UiTodoRows($Todos, [int]$Width, [int]$MaxRows = 14) {
    # The rows of the task list: a sign and the step; completed dim and struck through, in
    # progress bold in the accent colour, pending plain. A long list keeps the steps around
    # the current one.
    $mode = $script:Ui.mode
    $list = @($Todos | Where-Object { $_ })
    $first = 0
    if ($list.Count -gt $MaxRows) {
        $at = 0
        for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].status -ne 'completed') { $at = $i; break } }
        $first = [Math]::Max(0, [Math]::Min($at - 2, $list.Count - $MaxRows))
    }
    $rows = New-Object System.Collections.ArrayList
    if ($first -gt 0) { $null = $rows.Add((Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.doneBefore' $first)) $mode.faint -Italic)) }
    $last = [Math]::Min($list.Count, $first + $MaxRows) - 1
    for ($i = $first; $i -le $last; $i++) {
        $t = $list[$i]
        $text = Limit-UiText ([string]$t.content) ($Width - 3)
        if ($t.status -eq 'completed') {
            $row = (Format-UiInk (Get-UiMark 'todoDone' 'x') $script:Ui.ink.ok -Bold) + ' ' + (Format-UiSpans @(New-UiSpan $text $mode.dim 's'))
        } elseif ($t.status -eq 'in_progress') {
            $row = (Format-UiInk (Get-UiMark 'todoActive' '>') $mode.accent -Bold) + ' ' + (Format-UiInk $text $mode.accent -Bold)
        } else {
            $row = (Format-UiInk (Get-UiMark 'todoOpen' '-') $mode.dim) + ' ' + (Format-UiInk $text $mode.foreground)
        }
        $null = $rows.Add($row)
    }
    if ($last -lt $list.Count - 1) { $null = $rows.Add((Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($list.Count - 1 - $last) 'steps'))) $mode.faint -Italic)) }
    return $rows.ToArray()
}

function Get-UiKeyBadge([string]$Key, [string]$Hex) {
    # A key in a small coloured box, as in the question before a call.
    $mode = $script:Ui.mode
    return (Format-UiSpans @(New-UiSpan (' ' + $Key + ' ') $mode.background 'b' $Hex))
}

function Format-UiKeyLine($Items, [string]$Hex) {
    # The line of keys under a question or the plan: @(@(key, what it does), ...) as badges,
    # then the prompt sign. It never reaches the right edge (the status bar counts columns,
    # lib\AgentUiBar.ps1, and a wrapped line would also stay behind when the answer replaces
    # it): with less room the gaps shrink, then the texts get shorter, at last only the keys
    # stay.
    $mode = $script:Ui.mode
    $room = (Get-UiWidth) - 2
    $tail = '   ' + (Format-UiInk ([string][char]0x203A) $Hex -Bold) + ' '
    $line = ''
    foreach ($try in @(@('    ', 200), @('  ', 200), @('  ', 14), @('  ', 0))) {
        $parts = @()
        foreach ($item in $Items) {
            $part = Get-UiKeyBadge ([string]$item[0]) $Hex
            if ([int]$try[1] -gt 0 -and $item[1]) { $part += ' ' + (Format-UiInk (Limit-UiText ([string]$item[1]) ([int]$try[1])) $mode.foreground) }
            $parts += $part
        }
        $line = '  ' + ($parts -join [string]$try[0]) + $tail
        if ((Measure-UiText $line) -lt $room) { break }
    }
    return $line
}

function Write-UiFrameTop([string]$Sign, [string]$Title, [string]$Hex, [string]$Chip = '') {
    # The top edge of a frame with its title (and a label in a box), as the question before a
    # call has it.
    $width = Get-UiWidth
    $h = Get-UiBox 2
    $head = '  ' + (Format-UiInk ((Get-UiBox 0) + $h + ' ') $Hex) + (Format-UiInk ($Sign + ' ' + $Title) $Hex -Bold) + ' '
    if ($Chip) { $head += ' ' + (Get-UiKeyBadge $Chip $Hex) + ' ' }
    $head += Format-UiInk ($h * [Math]::Max(2, $width - 2 - (Measure-UiText $head))) $Hex
    Write-UiOut ($head + "`n")
}

function Write-UiFrameBottom([string]$Hex) {
    Write-UiOut ('  ' + (Format-UiInk ((Get-UiBox 1) + ((Get-UiBox 2) * ((Get-UiWidth) - 5))) $Hex) + "`n")
}

function Write-UiChoiceAnswer([string]$Kind, [string]$Text) {
    # Replaces the line with the keys by what was chosen.
    $hex = $script:Ui.ink.ok
    if ($Kind -eq 'error') { $hex = $script:Ui.ink.error } elseif ($Kind -eq 'warn') { $hex = $script:Ui.ink.warn }
    Write-UiOut ("`r" + $script:Esc + '[2K  ' + (Get-UiSign $Kind) + ' ' + (Format-UiInk (Limit-UiText $Text ((Get-UiWidth) - 6)) $hex) + "`n")
}

function Show-UiQuestion($Question, [int]$Index, [int]$Count) {
    # A question of AskUserQuestion in a frame: the question, the numbered choices with what
    # they mean, and the number for an answer of one's own.
    $mode = $script:Ui.mode
    $hex = $mode.accent
    $look = Get-UiToolLook 'AskUserQuestion'
    $inner = (Get-UiWidth) - 6
    $side = '  ' + (Format-UiInk (Get-UiBox 3) $hex) + ' '
    $title = Get-UiText 'question.title'
    if ($Count -gt 1) { $title += ' ' + (Get-UiText 'question.count' $Index $Count) }
    Write-UiFrameTop $look.icon $title $hex $Question.header
    $out = New-Object System.Collections.ArrayList
    foreach ($l in (Format-UiWrapped @(New-UiSpan $Question.question $mode.foreground 'b') '' '' 0 $inner)) { $null = $out.Add($side + $l) }
    $null = $out.Add($side)
    $n = 0
    foreach ($o in @($Question.options)) {
        $n++
        $badge = (Get-UiKeyBadge ([string]$n) $hex) + ' '
        foreach ($l in (Format-UiWrapped @(New-UiSpan ([string]$o.label) $mode.foreground 'b') $badge '    ' 4 $inner)) { $null = $out.Add($side + $l) }
        if ($o.description) {
            foreach ($l in (Format-UiWrapped @(New-UiSpan ([string]$o.description) $mode.dim) '    ' '    ' 4 $inner)) { $null = $out.Add($side + $l) }
        }
    }
    $ownText = Get-UiText 'question.own'
    if ($Question.multi) { $ownText = Get-UiText 'question.multi' }
    if ($n -gt 0 -and -not $Question.multi) { $null = $out.Add($side + (Get-UiKeyBadge ([string]($n + 1)) $mode.dim) + ' ' + (Format-UiInk $ownText $mode.dim -Italic)) }
    elseif ($n -gt 0) { $null = $out.Add($side + (Format-UiInk $ownText $mode.dim -Italic)) }
    Write-UiOut ((@($out) -join "`n") + "`n")
    Write-UiFrameBottom $hex
}

function Format-UiQuestionKeys($Question) {
    # The line with the keys under a question of single choice: the numbers, Enter for the
    # first option (the recommendation), Esc.
    $options = @($Question.options)
    $items = @(@(('1-' + ($options.Count + 1)), (Get-UiText 'question.choose')), @('Enter', (Limit-UiText ([string]$options[0].label) 30)), @('Esc', (Get-UiText 'question.stop')))
    return (Format-UiKeyLine $items $script:Ui.mode.accent)
}

function Read-UiQuestion($Question, [int]$Index, [int]$Count) {
    # Asks one question and returns @{ stopped; answer; own }. Single choice: the number
    # chooses, Enter takes the first (the recommendation), the last number or o types an
    # answer of one's own, Esc stops. Several choices or none: a line with numbers or text.
    Stop-UiActivity
    Show-UiQuestion $Question $Index $Count
    Set-UiProgress 0
    $options = @($Question.options)
    if ($options.Count -eq 0 -or $Question.multi) {
        $label = Get-UiText 'question.ownPrompt'
        if ($Question.multi) { $label = Get-UiText 'question.numbers' }
        $reply = ConvertFrom-QuestionReply $Question (Read-UiLine $label)
        if (-not $reply.answer) { Write-UiChoiceAnswer 'warn' (Get-UiText 'question.none'); return @{ stopped = $false; answer = ''; own = $false } }
        Write-UiChoiceAnswer 'ok' $reply.answer
        return @{ stopped = $false; answer = $reply.answer; own = $reply.own }
    }
    $keys = Format-UiQuestionKeys $Question
    while ($true) {
        Write-UiOut $keys
        $choice = 0
        $own = $false
        while ($choice -eq 0 -and -not $own) {
            $k = [Console]::ReadKey($true)
            $c = [string]$k.KeyChar
            if ($k.Key -eq [ConsoleKey]::Escape -or ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control))) {
                Write-UiChoiceAnswer 'error' (Get-UiText 'question.stopped')
                return @{ stopped = $true; answer = ''; own = $false }
            }
            if ($k.Key -eq [ConsoleKey]::Enter) { $choice = 1 }
            elseif ($c -match '^[1-9]$' -and [int]$c -le $options.Count) { $choice = [int]$c }
            elseif (($c -match '^[1-9]$' -and [int]$c -eq $options.Count + 1) -or $c -eq 'o' -or $k.Key -eq [ConsoleKey]::Tab) { $own = $true }
        }
        if ($choice -gt 0) {
            $label = [string]$options[$choice - 1].label
            Write-UiChoiceAnswer 'ok' $label
            return @{ stopped = $false; answer = $label; own = $false }
        }
        Write-UiOut ("`r" + $script:Esc + '[2K')
        $text = Read-UiLine (Get-UiText 'question.ownPrompt')
        if ($text) {
            Write-UiChoiceAnswer 'ok' $text
            return @{ stopped = $false; answer = $text; own = $true }
        }
        # nothing typed: back to the choices
    }
}

function Show-UiPlan([string]$Plan, [bool]$OfferEdits) {
    # The plan between two edges, rendered like an answer, and the line with the keys.
    $hex = $script:Ui.ink.ok
    $look = Get-UiToolLook 'PresentPlan'
    Write-UiOut "`n"
    Write-UiFrameTop $look.icon (Get-UiText 'plan.title') $hex
    $script:Ui.gap = $true
    Start-UiAnswer
    Add-UiContent ($Plan.Replace("`r", '') + "`n")
    Complete-UiAnswer
    Write-UiFrameBottom $hex
    $items = @(, @('y', (Get-UiText 'plan.yes')))
    if ($OfferEdits) { $items += , @('e', (Get-UiText 'plan.edits')) }
    $items += , @('n', (Get-UiText 'plan.no'))
    $items += , @('Esc', (Get-UiText 'question.stop'))
    Write-UiOut (Format-UiKeyLine $items $hex)
}

function Read-UiPlanApproval([string]$Plan, [bool]$OfferEdits) {
    # Shows the plan (Show-UiPlan) and reads one key: y or Enter approve, e approve and let
    # file changes run without asking ($OfferEdits), n say what should change (a line;
    # nothing typed = stop), Esc stop. Returns @{ choice = yes, edits, no or stop; feedback }.
    Stop-UiActivity
    Show-UiPlan $Plan $OfferEdits
    Set-UiProgress 0
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [string]$k.KeyChar
        if ($k.Key -eq [ConsoleKey]::Escape -or ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control))) {
            Write-UiChoiceAnswer 'error' (Get-UiText 'plan.stopped')
            return @{ choice = 'stop'; feedback = '' }
        }
        if ($k.Key -eq [ConsoleKey]::Enter -or $c -eq 'y' -or $c -eq 'j') {
            Write-UiChoiceAnswer 'ok' (Get-UiText 'plan.approved')
            return @{ choice = 'yes'; feedback = '' }
        }
        if ($OfferEdits -and $c -eq 'e') {
            Write-UiChoiceAnswer 'ok' (Get-UiText 'plan.approvedEdits')
            return @{ choice = 'edits'; feedback = '' }
        }
        if ($c -eq 'n') {
            Write-UiOut ("`r" + $script:Esc + '[2K')
            $text = Read-UiLine (Get-UiText 'plan.feedback')
            if (-not $text) { Write-UiChoiceAnswer 'error' (Get-UiText 'plan.stopped'); return @{ choice = 'stop'; feedback = '' } }
            Write-UiChoiceAnswer 'warn' (Get-UiText 'plan.rejected')
            return @{ choice = 'no'; feedback = $text }
        }
    }
}
