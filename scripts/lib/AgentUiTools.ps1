# Tool calls at the terminal of Unzensiert (lib\AgentUi.ps1): a header with the sign and the
# colour of the tool (a command in the colours of its shell), the activity line while it
# runs, then the result - a tick or a cross with the time, the output of a command with its
# beginning and its end, what was read, written or found - and for Edit the change as a diff:
# line numbers, tinted backgrounds, the changed characters stronger, the code in the colours
# of its language. The question before a call stands in a frame with the same preview.
# Keep this file ASCII-only.

function Get-UiToolLook([string]$Name) {
    # Sign and colour of a tool ("agent.tools" of the style).
    $entry = Get-UiValue (Get-UiLook 'tools' $null) $Name $null
    $icon = [string](Get-UiValue $entry 'icon' (Get-UiMark 'answer' '*'))
    $ink = [string](Get-UiValue $entry 'ink' 'accent')
    return @{ icon = $icon; ink = (Resolve-UiInk $ink 0.1) }
}

function Get-UiSign([string]$Kind) {
    # The sign of a kind of note (ok, warn, error) in its colour.
    $glyph = [string](Get-UiValue (Get-UiLook 'notes' $null) $Kind '')
    if (-not $glyph) { $glyph = '*' }
    $hex = $script:Ui.ink.ok
    if ($Kind -eq 'error') { $hex = $script:Ui.ink.error } elseif ($Kind -eq 'warn') { $hex = $script:Ui.ink.warn }
    return (Format-UiInk $glyph $hex -Bold)
}

function Get-UiShellLang([string]$Name) {
    if ($Name -eq 'PowerShell') { return 'powershell' }
    return 'bash'
}

function Format-UiCodeLine([string]$Text, [string]$Lang, [int]$Max) {
    # One line of code in its colours, cut to $Max columns; the state of multi-line comments
    # of an answer stays untouched.
    $saved = $script:Ui.codeState
    $script:Ui.codeState = ''
    $spans = ConvertTo-UiCodeSpans $Text $Lang
    $script:Ui.codeState = $saved
    $rows = Split-UiSpans $spans ([Math]::Max(4, $Max - 1))
    $line = Format-UiSpans $rows[0]
    if ($rows.Count -gt 1 -and $rows[1].Count -gt 0) { $line += (Format-UiInk $script:UiDots $script:Ui.mode.dim) }
    return $line
}

function Get-UiToolLabel([string]$Name, $A, [string]$Cwd) {
    # What the header of a call names (the command, the file, the pattern) and a detail.
    $label = ''
    $detail = ''
    if ($null -eq $A) { return @('', '') }
    switch ($Name) {
        { $_ -eq 'Bash' -or $_ -eq 'PowerShell' } {
            $lines = @(([string](Get-DictValue $A 'command')).Replace("`r", '').Split("`n") | Where-Object { $_.Trim() })
            if ($lines.Count -gt 0) { $label = $lines[0].Trim() }
            if ($lines.Count -gt 1) { $detail = Get-UiText 'tools.more' (Get-UiCount ($lines.Count - 1) 'lines') }
        }
        'Read' {
            $label = Get-DisplayPath (Resolve-AgentPath (Get-DictValue $A 'file_path') $Cwd) $Cwd
            $first = [int](Get-DictValue $A 'offset')
            $count = [int](Get-DictValue $A 'limit')
            if ($first -gt 0 -or $count -gt 0) {
                if ($first -le 0) { $first = 1 }
                if ($count -gt 0) { $detail = Get-UiText 'tools.range' $first ($first + $count - 1) }
                else { $detail = Get-UiText 'tools.from' $first }
            }
        }
        { $_ -eq 'Edit' -or $_ -eq 'Write' } { $label = Get-DisplayPath (Resolve-AgentPath (Get-DictValue $A 'file_path') $Cwd) $Cwd }
        'EditLines' {
            $label = Get-DisplayPath (Resolve-AgentPath (Get-DictValue $A 'file_path') $Cwd) $Cwd
            $first = [int](Get-DictValue $A 'start_line')
            $last = [int](Get-DictValue $A 'end_line')
            if ($first -gt 0) { $detail = Get-UiText 'tools.range' $first ([math]::Max($first, $last)) }
        }
        'Glob' {
            $label = [string](Get-DictValue $A 'pattern')
            $p = [string](Get-DictValue $A 'path')
            if ($p) { $detail = Get-UiText 'tools.in' $p }
        }
        'Grep' {
            $label = [string](Get-DictValue $A 'pattern')
            $where = @()
            foreach ($k in 'path', 'glob') { $v = [string](Get-DictValue $A $k); if ($v) { $where += $v } }
            if ($where.Count -gt 0) { $detail = Get-UiText 'tools.in' ($where -join ' ') }
        }
        'TodoWrite' {
            $todos = @((ConvertTo-TodoList (Get-DictValue $A 'todos')).todos)
            $done = @($todos | Where-Object { $_.status -eq 'completed' }).Count
            $label = Get-UiText 'tools.todo' $done $todos.Count
        }
        'WebSearch' { $label = [string](Get-DictValue $A 'query') }
        'WebFetch' {
            $label = [string](Get-DictValue $A 'url')
            $from = [int](Get-DictValue $A 'offset')
            if ($from -gt 0) { $detail = Get-UiText 'tools.fromChar' (Format-Number $from 0) }
        }
    }
    return @($label, $detail)
}

function Write-UiToolStart([string]$Name, $A, [string]$Cwd) {
    # The header of a tool call; the activity line under it shows that it runs. A question and
    # the plan have a frame of their own instead (lib\AgentUiPlan.ps1).
    if (-not $script:Ui.on) { return }
    Stop-UiActivity
    Close-UiThinking
    Complete-UiLine
    if ($Name -eq 'AskUserQuestion' -or $Name -eq 'PresentPlan') {
        $script:Ui.toolName = $Name
        $script:Ui.toolArgs = $A
        $script:Ui.toolCwd = $Cwd
        $script:Ui.toolStarted = [DateTime]::UtcNow
        return
    }
    $mode = $script:Ui.mode
    $look = Get-UiToolLook $Name
    $label = @('', '')
    $gap = "`n"
    if ($script:Ui.gap) { $gap = '' }
    $script:Ui.gap = $false
    try { $label = @(Get-UiToolLabel $Name $A $Cwd) } catch {}
    $detail = [string]$label[1]
    $room = (Get-UiWidth) - $Name.Length - 6
    if ($detail) { $room -= $detail.Length + 2 }
    $room = [Math]::Max(12, $room)
    $head = (Format-UiInk $look.icon $look.ink -Bold) + ' ' + (Format-UiInk $Name $look.ink -Bold) + '  '
    if ($Name -eq 'Bash' -or $Name -eq 'PowerShell') { $head += Format-UiCodeLine ([string]$label[0]) (Get-UiShellLang $Name) $room }
    else { $head += Format-UiInk (Limit-UiText ([string]$label[0]) $room) $mode.foreground }
    if ($detail) { $head += '  ' + (Format-UiInk $detail $mode.dim) }
    Write-UiOut ($gap + $head + "`n")
    $script:Ui.toolName = $Name
    $script:Ui.toolArgs = $A
    $script:Ui.toolCwd = $Cwd
    $script:Ui.toolStarted = [DateTime]::UtcNow
    Start-UiActivity 'tool' '' 400
}

function Get-UiOutputHex([string]$Line) {
    # Colour of a line of command output: errors red, warnings yellow, success green.
    if ($Line -match '(?i)\b(error|errors|fehler|failed|failure|fail|exception|traceback|fatal)\b') { return $script:Ui.ink.error }
    if ($Line -match '(?i)\b(warn|warning|warnings|warnung|deprecated)\b') { return $script:Ui.ink.warn }
    if ($Line -match '(?i)\b(passed|success|successful|succeeded|ok|erfolgreich|bestanden)\b') { return $script:Ui.ink.ok }
    return $script:Ui.mode.dim
}

function Write-UiToolResult($Result, [string]$Name) {
    # The result under the header: sign and time, then what the tool found or changed.
    if (-not $script:Ui.on) { return }
    Stop-UiActivity
    # a question and the plan show their answer in their own frame already
    if (($Name -eq 'AskUserQuestion' -or $Name -eq 'PresentPlan') -and -not $Result.error) { return }
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    $secs = ([DateTime]::UtcNow - $script:Ui.toolStarted).TotalSeconds
    $corner = '  ' + (Format-UiInk (Get-UiMark 'corner' '|') $mode.faint) + '  '
    $pad = '     '
    $max = $width - 7
    $info = Get-DictValue $Result 'info'
    if ($Result.changed) { $script:Ui.turnFiles[[string]$Result.changed] = $true }
    $out = New-Object System.Collections.ArrayList
    $sep = Format-UiInk ('  ' + $script:UiMid + '  ') $mode.faint
    $isShell = ($Name -eq 'Bash' -or $Name -eq 'PowerShell')

    if ($isShell -and $info) {
        $code = [int](Get-DictValue $info 'exit')
        $stopped = [string](Get-DictValue $info 'stopped')
        if ($Result.userStop) { $head = (Format-UiInk ((Get-UiMark 'stopped' '#') + ' ' + (Get-UiText 'tools.stopped')) $script:Ui.ink.warn -Bold) }
        elseif ($stopped) { $head = (Get-UiSign 'error') + ' ' + (Format-UiInk (Get-UiText 'tools.timeLimit') $script:Ui.ink.error) }
        elseif ($code -ne 0) { $head = (Get-UiSign 'error') + ' ' + (Format-UiInk (Get-UiText 'tools.exit' $code) $script:Ui.ink.error -Bold) }
        else { $head = '' }
        if ($head) { $head += $sep } else { $head = (Get-UiSign 'ok') + ' ' }
        $null = $out.Add($corner + $head + (Format-UiInk (Format-UiDuration $secs) $mode.dim))
        $lines = @(([string](Get-DictValue $info 'output')).Split("`n") | Where-Object { $_.Trim() -ne '' })
        if ($lines.Count -eq 0) { $null = $out.Add($pad + (Format-UiInk (Get-UiText 'tools.noOutput') $mode.faint -Italic)) }
        $show = $lines
        $hidden = 0
        if ($lines.Count -gt 9) { $hidden = $lines.Count - 7; $show = @($lines[0..2]) + @('') + @($lines[($lines.Count - 4)..($lines.Count - 1)]) }
        foreach ($l in $show) {
            if ($l -eq '' -and $hidden -gt 0) { $null = $out.Add($pad + (Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount $hidden 'lines'))) $mode.faint -Italic)); continue }
            $null = $out.Add($pad + (Format-UiInk (Limit-UiText $l.TrimEnd() $max) (Get-UiOutputHex $l)))
        }
    } elseif ($Result.error) {
        $lines = @(([string]$Result.text).Split("`n") | Where-Object { $_.Trim() } | Select-Object -First 4)
        $first = $true
        foreach ($l in $lines) {
            $lead = $pad
            if ($first) { $lead = $corner + (Get-UiSign 'error') + ' '; $first = $false }
            $null = $out.Add($lead + (Format-UiInk (Limit-UiText $l.Trim() ($max - 2)) $script:Ui.ink.error))
        }
    } elseif ($Result.diff) {
        $diff = Get-UiDiffRows ([string]$Result.diff.old) ([string]$Result.diff.new) ([int]$Result.diff.line) ([string](Get-DictValue $script:Ui.toolArgs 'file_path')) 24 ($width - 6)
        $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk (Get-UiText 'tools.at' $Result.diff.line) $mode.foreground) + $sep + (Format-UiInk ('-' + $diff.removed) $script:Ui.ink.error -Bold) + ' ' + (Format-UiInk ('+' + $diff.added) $script:Ui.ink.ok -Bold))
        foreach ($r in $diff.rows) { $null = $out.Add($pad + $r) }
    } elseif ($Name -eq 'Write' -and $info) {
        $what = Get-UiText 'tools.replaced'
        if (Get-DictValue $info 'created') { $what = Get-UiText 'tools.created' }
        $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk $what $mode.foreground) + $sep + (Format-UiInk (Get-UiCount ([int](Get-DictValue $info 'lines')) 'lines') $mode.dim))
        $content = [string](Get-DictValue $script:Ui.toolArgs 'content')
        foreach ($r in (Get-UiPreviewRows $content ([string](Get-DictValue $script:Ui.toolArgs 'file_path')) 6 ($width - 6))) { $null = $out.Add($pad + $r) }
    } elseif ($Name -eq 'Read' -and $info) {
        if (Get-DictValue $info 'image') { $what = Get-UiText 'tools.image' }
        else { $what = Get-UiCount ([int](Get-DictValue $info 'lines')) 'lines' }
        $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk $what $mode.dim))
    } elseif (($Name -eq 'Glob' -or $Name -eq 'Grep') -and $info) {
        $files = [int](Get-DictValue $info 'files')
        $hits = [int](Get-DictValue $info 'lines')
        $list = @(([string]$Result.text).Split("`n") | Where-Object { $_.Trim() -and $_ -notmatch '^\[' })
        if ($files -eq 0 -and $hits -eq 0) {
            $null = $out.Add($corner + (Format-UiInk ([string](Get-UiValue (Get-UiLook 'notes' $null) 'dim' '-')) $mode.faint) + ' ' + (Format-UiInk (Get-UiText 'tools.nothing') $mode.dim))
        } elseif ($Name -eq 'Grep' -and -not (Get-DictValue $info 'filesOnly')) {
            $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk ((Get-UiCount $hits 'matches') + ' ' + (Get-UiText 'tools.in' (Get-UiCount $files 'files'))) $mode.dim))
            foreach ($l in ($list | Select-Object -First 4)) {
                if ($l -match '^(.*?):(\d+):(.*)$') {
                    $null = $out.Add($pad + (Format-UiInk $Matches[1] $mode.dim) + (Format-UiInk (':' + $Matches[2] + ' ') $mode.accentSoft) + (Format-UiInk (Limit-UiText $Matches[3].Trim() ([Math]::Max(10, $max - $Matches[1].Length - $Matches[2].Length - 3))) $mode.foreground))
                } else { $null = $out.Add($pad + (Format-UiInk (Limit-UiText $l $max) $mode.dim)) }
            }
            if ($hits -gt 4) { $null = $out.Add($pad + (Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($hits - 4) 'matches'))) $mode.faint -Italic)) }
        } else {
            $count = $files
            if ($count -eq 0) { $count = $list.Count }
            $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk (Get-UiCount $count 'files') $mode.dim))
            $row = ''
            $rowsShown = 0
            foreach ($f in $list) {
                $name = $f.Trim()
                if ($row -and $row.Length + $name.Length + 3 -gt $max) {
                    $null = $out.Add($pad + (Format-UiInk $row $mode.foreground))
                    $row = ''
                    if (++$rowsShown -ge 2) { break }
                }
                if ($row) { $row += '   ' }
                $row += (Limit-UiText $name $max)
            }
            if ($row -and $rowsShown -lt 2) { $null = $out.Add($pad + (Format-UiInk $row $mode.foreground)) }
        }
    } elseif ($Name -eq 'TodoWrite' -and $info) {
        $todos = Get-DictValue $info 'todos'
        $todos = @($todos)
        Set-UiStep $todos
        $rows = @(Get-UiTodoRows $todos $max)
        if ($rows.Count -eq 0) { $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk (Get-UiText 'tools.todoEmpty') $mode.dim)) }
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $lead = $pad
            if ($i -eq 0) { $lead = $corner }
            $null = $out.Add($lead + $rows[$i])
        }
    } elseif ($Name -eq 'WebSearch' -and $info) {
        $found = Get-DictValue $info 'results'
        $found = @($found)
        if ($found.Count -eq 0) {
            $null = $out.Add($corner + (Format-UiInk ([string](Get-UiValue (Get-UiLook 'notes' $null) 'dim' '-')) $mode.faint) + ' ' + (Format-UiInk (Get-UiText 'tools.nothing') $mode.dim))
        } else {
            $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk ((Get-UiCount $found.Count 'results') + ' ' + (Get-UiText 'tools.via' (Get-DictValue $info 'engine'))) $mode.dim))
            foreach ($f in ($found | Select-Object -First 3)) {
                $hostName = Get-WebHost ([string]$f.url)
                $title = Limit-UiText ([string]$f.title) ([Math]::Max(10, $max - $hostName.Length - 3))
                $null = $out.Add($pad + (Format-UiSpans @(New-UiSpan $title $mode.foreground '' '' ([string]$f.url))) + '  ' + (Format-UiInk $hostName $mode.dim))
            }
            if ($found.Count -gt 3) { $null = $out.Add($pad + (Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($found.Count - 3) 'results'))) $mode.faint -Italic)) }
        }
    } elseif ($Name -eq 'WebFetch' -and $info) {
        $what = [string](Get-DictValue $info 'title')
        if (-not $what) { $what = Get-UiText 'tools.page' }
        $part = Get-UiText 'tools.chars' (Format-Number ([int](Get-DictValue $info 'to') - [int](Get-DictValue $info 'from')) 0) (Format-Number ([int](Get-DictValue $info 'total')) 0)
        $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk (Limit-UiText $what ([Math]::Max(10, $max - $part.Length - 6))) $mode.foreground) + $sep + (Format-UiInk $part $mode.dim))
    } else {
        $summary = [string]$Result.summary
        if (-not $summary) { $summary = ([string]$Result.text).Split("`n")[0] }
        $null = $out.Add($corner + (Get-UiSign 'ok') + ' ' + (Format-UiInk (Limit-UiText $summary ($max - 2)) $mode.dim))
    }
    # a tool may have changed files: the bar reads git again
    if ($script:Ui.bar.on) { Update-UiBarReadings -Git }
    Write-UiOut ((@($out) -join "`n") + "`n")
}

# --- changes ------------------------------------------------------------------------------------------

function Get-UiLineDiff([string[]]$Old, [string[]]$New) {
    # The lines of two texts as steps @(kind, old index, new index): ' ' in both, '-' only
    # in the old, '+' only in the new. Common beginning and end first, then the longest common
    # subsequence; for very long middles all old lines out and all new ones in.
    $ops = New-Object System.Collections.ArrayList
    $n = $Old.Count
    $m = $New.Count
    $pre = 0
    while ($pre -lt $n -and $pre -lt $m -and $Old[$pre] -ceq $New[$pre]) { $pre++ }
    $suf = 0
    while ($suf -lt ($n - $pre) -and $suf -lt ($m - $pre) -and $Old[$n - 1 - $suf] -ceq $New[$m - 1 - $suf]) { $suf++ }
    for ($i = 0; $i -lt $pre; $i++) { $null = $ops.Add(@(' ', $i, $i)) }
    $on = $n - $pre - $suf
    $nn = $m - $pre - $suf
    if ($on -gt 0 -and $nn -gt 0 -and $on * $nn -le 10000) {
        $t = New-Object 'int[,]' ($on + 1), ($nn + 1)
        for ($i = $on - 1; $i -ge 0; $i--) {
            for ($j = $nn - 1; $j -ge 0; $j--) {
                $i1 = $i + 1
                $j1 = $j + 1
                if ($Old[$pre + $i] -ceq $New[$pre + $j]) { $t[$i, $j] = $t[$i1, $j1] + 1 }
                else {
                    $down = $t[$i1, $j]
                    $right = $t[$i, $j1]
                    if ($down -ge $right) { $t[$i, $j] = $down } else { $t[$i, $j] = $right }
                }
            }
        }
        $i = 0
        $j = 0
        while ($i -lt $on -and $j -lt $nn) {
            if ($Old[$pre + $i] -ceq $New[$pre + $j]) { $null = $ops.Add(@(' ', ($pre + $i), ($pre + $j))); $i++; $j++ }
            elseif ((Get-UiLcsStep $t $i $j)) { $null = $ops.Add(@('-', ($pre + $i), -1)); $i++ }
            else { $null = $ops.Add(@('+', -1, ($pre + $j))); $j++ }
        }
        for (; $i -lt $on; $i++) { $null = $ops.Add(@('-', ($pre + $i), -1)) }
        for (; $j -lt $nn; $j++) { $null = $ops.Add(@('+', -1, ($pre + $j))) }
    } else {
        for ($i = 0; $i -lt $on; $i++) { $null = $ops.Add(@('-', ($pre + $i), -1)) }
        for ($j = 0; $j -lt $nn; $j++) { $null = $ops.Add(@('+', -1, ($pre + $j))) }
    }
    for ($k = 0; $k -lt $suf; $k++) { $null = $ops.Add(@(' ', ($n - $suf + $k), ($m - $suf + $k))) }
    return , $ops
}

function Get-UiLcsStep($Table, [int]$I, [int]$J) {
    # True when the walk through the table of the longest common subsequence goes down
    # (a line of the old text is removed) rather than right.
    $i1 = $I + 1
    $j1 = $J + 1
    return ($Table[$i1, $J] -ge $Table[$I, $j1])
}

function Set-UiSpansBg($Spans, [int]$From, [int]$To, [string]$Bg) {
    # The spans with the background $Bg on the characters $From up to (not including) $To.
    $out = New-Object System.Collections.ArrayList
    $pos = 0
    foreach ($s in $Spans) {
        $t = [string]$s.t
        $len = $t.Length
        $x = [Math]::Max($From, $pos)
        $y = [Math]::Min($To, $pos + $len)
        if ($y -le $x) { $null = $out.Add($s); $pos += $len; continue }
        if ($x -gt $pos) { $null = $out.Add((New-UiSpan ($t.Substring(0, $x - $pos)) $s.fg $s.a $s.bg $s.link)) }
        $null = $out.Add((New-UiSpan ($t.Substring($x - $pos, $y - $x)) $s.fg $s.a $Bg $s.link))
        if ($y -lt $pos + $len) { $null = $out.Add((New-UiSpan ($t.Substring($y - $pos)) $s.fg $s.a $s.bg $s.link)) }
        $pos += $len
    }
    return , $out
}

function Get-UiChangedRange([string]$Old, [string]$New) {
    # What differs between two similar lines: @(start, end in old, end in new), or $null when
    # they have too little in common for the mark to help.
    $p = 0
    while ($p -lt $Old.Length -and $p -lt $New.Length -and $Old[$p] -ceq $New[$p]) { $p++ }
    $s = 0
    while ($s -lt ($Old.Length - $p) -and $s -lt ($New.Length - $p) -and $Old[$Old.Length - 1 - $s] -ceq $New[$New.Length - 1 - $s]) { $s++ }
    $shorter = [Math]::Min($Old.Length, $New.Length)
    if ($shorter -eq 0 -or ($p + $s) * 3 -lt $shorter) { return $null }
    return @($p, ($Old.Length - $s), ($New.Length - $s))
}

function Format-UiDiffRow([string]$Kind, [int]$Number, [string]$Text, [int]$NumWidth, [string]$Lang, [int]$RowWidth, $Range) {
    # One row of a diff: number, sign, code; removed and added rows on a tinted background
    # across the row, the changed characters ($Range) stronger.
    $mode = $script:Ui.mode
    $ink = $script:Ui.ink
    $tint = [double](Get-UiLook 'diffTint' 0.8)
    $strong = [double](Get-UiLook 'diffStrong' 0.58)
    $num = ''
    if ($Number -gt 0) { $num = ([string]$Number).PadLeft($NumWidth) }
    else { $num = ' ' * $NumWidth }
    $room = [Math]::Max(8, $RowWidth - $NumWidth - 4)
    if ($Kind -eq '~') {
        return (Format-UiInk (((' ' * ($NumWidth - 1)) + [string][char]0x22EF)) $mode.faint)
    }
    if ($Kind -eq ' ') {
        return (Format-UiInk $num $mode.faint) + '   ' + (Format-UiInk (Limit-UiText $Text $room) $mode.dim)
    }
    $hex = $ink.ok
    if ($Kind -eq '-') { $hex = $ink.error }
    $bg = Get-UiMixHex $hex $mode.background $tint
    $saved = $script:Ui.codeState
    $script:Ui.codeState = ''
    $code = ConvertTo-UiCodeSpans $Text $Lang
    $script:Ui.codeState = $saved
    if ($Range) {
        $end = $Range[1]
        if ($Kind -eq '+') { $end = $Range[2] }
        if ($end -gt $Range[0]) { $code = Set-UiSpansBg $code $Range[0] $end (Get-UiMixHex $hex $mode.background $strong) }
    }
    $rows = Split-UiSpans $code $room
    $spans = New-Object System.Collections.ArrayList
    $null = $spans.Add((New-UiSpan $num (Get-UiMixHex $hex $mode.foreground 0.35)))
    $null = $spans.Add((New-UiSpan (' ' + $Kind + ' ') $hex 'b'))
    $used = $NumWidth + 3
    foreach ($s in $rows[0]) { $null = $spans.Add($s); $used += ([string]$s.t).Length }
    if ($rows.Count -gt 1 -and $rows[1].Count -gt 0) { $null = $spans.Add((New-UiSpan $script:UiDots $mode.dim)); $used++ }
    if ($used -lt $RowWidth) { $null = $spans.Add((New-UiSpan (' ' * ($RowWidth - $used)) '')) }
    return (Format-UiSpans $spans $bg)
}

function Get-UiDiffRows([string]$Old, [string]$New, [int]$Line, [string]$Path, [int]$MaxRows, [int]$RowWidth) {
    # The rows of a change ($Old replaced by $New from line $Line of file $Path) and how many
    # lines went and came: @{ rows; removed; added }. Long runs of unchanged lines are folded.
    $oldLines = @($Old.Replace("`r", '').Split("`n"))
    $newLines = @($New.Replace("`r", '').Split("`n"))
    $ops = Get-UiLineDiff $oldLines $newLines
    if ($Line -le 0) { $Line = 1 }
    $lang = Get-UiCodeLang ([System.IO.Path]::GetExtension($Path))
    $numWidth = ([string]($Line + [Math]::Max($oldLines.Count, $newLines.Count))).Length
    # pair removed lines with the added lines that follow them, to mark what changed inside
    $items = New-Object System.Collections.ArrayList
    $removed = 0
    $added = 0
    $k = 0
    while ($k -lt $ops.Count) {
        $op = $ops[$k]
        if ($op[0] -eq ' ') { $null = $items.Add(@{ kind = ' '; num = $Line + $op[2]; text = $newLines[$op[2]]; range = $null }); $k++; continue }
        $minus = New-Object System.Collections.ArrayList
        $plus = New-Object System.Collections.ArrayList
        while ($k -lt $ops.Count -and $ops[$k][0] -eq '-') { $null = $minus.Add($ops[$k]); $k++ }
        while ($k -lt $ops.Count -and $ops[$k][0] -eq '+') { $null = $plus.Add($ops[$k]); $k++ }
        $ranges = @{}
        for ($p = 0; $p -lt [Math]::Min($minus.Count, $plus.Count); $p++) { $ranges[$p] = Get-UiChangedRange $oldLines[$minus[$p][1]] $newLines[$plus[$p][2]] }
        for ($p = 0; $p -lt $minus.Count; $p++) { $null = $items.Add(@{ kind = '-'; num = $Line + $minus[$p][1]; text = $oldLines[$minus[$p][1]]; range = $ranges[$p] }); $removed++ }
        for ($p = 0; $p -lt $plus.Count; $p++) { $null = $items.Add(@{ kind = '+'; num = $Line + $plus[$p][2]; text = $newLines[$plus[$p][2]]; range = $ranges[$p] }); $added++ }
    }
    # fold unchanged lines: two at the edges, one on each side of a long middle run
    $shown = New-Object System.Collections.ArrayList
    $i = 0
    while ($i -lt $items.Count) {
        if ($items[$i].kind -ne ' ') { $null = $shown.Add($items[$i]); $i++; continue }
        $j = $i
        while ($j -lt $items.Count -and $items[$j].kind -eq ' ') { $j++ }
        $run = $j - $i
        $atStart = ($i -eq 0)
        $atEnd = ($j -eq $items.Count)
        if ($atStart -and $atEnd) { for ($x = $i; $x -lt $j; $x++) { $null = $shown.Add($items[$x]) } }
        elseif ($atStart) { for ($x = [Math]::Max($i, $j - 2); $x -lt $j; $x++) { $null = $shown.Add($items[$x]) } }
        elseif ($atEnd) { for ($x = $i; $x -lt [Math]::Min($j, $i + 2); $x++) { $null = $shown.Add($items[$x]) } }
        elseif ($run -le 3) { for ($x = $i; $x -lt $j; $x++) { $null = $shown.Add($items[$x]) } }
        else {
            $null = $shown.Add($items[$i])
            $null = $shown.Add(@{ kind = '~'; num = 0; text = ''; range = $null })
            $null = $shown.Add($items[$j - 1])
        }
        $i = $j
    }
    $rows = New-Object System.Collections.ArrayList
    $limit = [Math]::Min($shown.Count, $MaxRows)
    if ($shown.Count -gt $MaxRows) { $limit = $MaxRows - 1 }
    for ($r = 0; $r -lt $limit; $r++) {
        $it = $shown[$r]
        $null = $rows.Add((Format-UiDiffRow $it.kind $it.num ([string]$it.text) $numWidth $lang $RowWidth $it.range))
    }
    if ($shown.Count -gt $limit) {
        $null = $rows.Add((Format-UiInk ((' ' * ($numWidth + 3)) + $script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($shown.Count - $limit) 'lines'))) $script:Ui.mode.faint -Italic))
    }
    return @{ rows = $rows; removed = $removed; added = $added }
}

function Get-UiPreviewRows([string]$Text, [string]$Path, [int]$MaxRows, [int]$RowWidth) {
    # The first lines of a file with line numbers, in the colours of its language.
    $mode = $script:Ui.mode
    $lines = @($Text.Replace("`r", '').TrimEnd("`n").Split("`n"))
    $lang = Get-UiCodeLang ([System.IO.Path]::GetExtension($Path))
    $numWidth = [Math]::Max(2, ([string][Math]::Min($lines.Count, $MaxRows)).Length)
    $rows = New-Object System.Collections.ArrayList
    $saved = $script:Ui.codeState
    $script:Ui.codeState = ''
    for ($i = 0; $i -lt [Math]::Min($lines.Count, $MaxRows); $i++) {
        $spans = ConvertTo-UiCodeSpans ($lines[$i].Replace("`t", '    ')) $lang
        $cut = Split-UiSpans $spans ([Math]::Max(8, $RowWidth - $numWidth - 3))
        $line = (Format-UiInk (([string]($i + 1)).PadLeft($numWidth)) $mode.faint) + '  ' + (Format-UiSpans $cut[0])
        if ($cut.Count -gt 1 -and $cut[1].Count -gt 0) { $line += (Format-UiInk $script:UiDots $mode.dim) }
        $null = $rows.Add($line)
    }
    $script:Ui.codeState = $saved
    if ($lines.Count -gt $MaxRows) {
        $null = $rows.Add((Format-UiInk ((' ' * ($numWidth + 2)) + $script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($lines.Count - $MaxRows) 'lines'))) $mode.faint -Italic))
    }
    return , $rows
}

function Get-UiEditLine([string]$Path, [string]$Old) {
    # The line where $Old begins in the file, for the question before an edit; 1 if unknown.
    try {
        $text = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
        $at = $text.IndexOf($Old.Replace("`r`n", "`n"))
        if ($at -ge 0) { return ($text.Substring(0, $at).Split("`n")).Count }
    } catch {}
    return 1
}

# --- the question before a call ----------------------------------------------------------------------------

function Show-UiPermission([string]$Name, [string]$Subject, [string]$Why, [bool]$CanAlways, $A = $null) {
    # The question before a call, in a frame: what would happen (the command in its colours,
    # the change as a diff, the start of a new file), why it asks, and the keys: yes, always
    # (this session; not for questions of the guard) or no. The cursor stays after the keys.
    $mode = $script:Ui.mode
    $ink = $script:Ui.ink
    $width = Get-UiWidth
    $guard = -not $CanAlways
    $hex = $ink.warn
    $sign = '?'
    $title = Get-UiText 'permission.title'
    if ($guard) { $hex = $mode.accent; $sign = '!'; $title = Get-UiText 'permission.guard' }
    $look = Get-UiToolLook $Name
    $h = Get-UiBox 2
    $side = '  ' + (Format-UiInk (Get-UiBox 3) $hex) + ' '
    $inner = $width - 6
    $head = '  ' + (Format-UiInk ((Get-UiBox 0) + $h + ' ') $hex) + (Format-UiInk ($sign + ' ' + $title) $hex -Bold) + '  ' + (Format-UiInk $look.icon $look.ink -Bold) + ' ' + (Format-UiInk $Name $look.ink -Bold) + ' '
    $head += Format-UiInk ($h * [Math]::Max(2, $width - 2 - (Measure-UiText $head))) $hex
    $body = New-Object System.Collections.ArrayList
    $cwd = [string]$script:Ui.toolCwd
    if (($Name -eq 'Bash' -or $Name -eq 'PowerShell') -and $A) {
        $lines = @(([string](Get-DictValue $A 'command')).Replace("`r", '').Split("`n"))
        $n = 0
        foreach ($l in $lines) {
            if (++$n -gt 20) { $null = $body.Add((Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($lines.Count - 20) 'lines'))) $mode.dim)); break }
            $null = $body.Add((Format-UiCodeLine $l (Get-UiShellLang $Name) $inner))
        }
    } elseif ($Name -eq 'Edit' -and $A) {
        $path = Resolve-AgentPath (Get-DictValue $A 'file_path') $cwd
        $old = [string](Get-DictValue $A 'old_string')
        $null = $body.Add((Format-UiInk (Get-DisplayPath $path $cwd) $mode.foreground -Bold))
        $diff = Get-UiDiffRows $old ([string](Get-DictValue $A 'new_string')) (Get-UiEditLine $path $old) $path 20 $inner
        foreach ($r in $diff.rows) { $null = $body.Add($r) }
    } elseif ($Name -eq 'Write' -and $A) {
        $path = Resolve-AgentPath (Get-DictValue $A 'file_path') $cwd
        $null = $body.Add((Format-UiInk (Get-DisplayPath $path $cwd) $mode.foreground -Bold))
        foreach ($r in (Get-UiPreviewRows ([string](Get-DictValue $A 'content')) $path 16 $inner)) { $null = $body.Add($r) }
    } else {
        $lines = @($Subject.Replace("`r", '').Split("`n"))
        $n = 0
        foreach ($l in $lines) {
            if (++$n -gt 30) { $null = $body.Add((Format-UiInk ($script:UiDots + ' ' + (Get-UiText 'tools.more' (Get-UiCount ($lines.Count - 30) 'lines'))) $mode.dim)); break }
            $lineHex = $mode.foreground
            if ($l.StartsWith('- ')) { $lineHex = $ink.error } elseif ($l.StartsWith('+ ')) { $lineHex = $ink.ok }
            $null = $body.Add((Format-UiInk (Limit-UiText $l $inner) $lineHex))
        }
    }
    if ($Why) {
        $reason = $Why
        if ($reason -eq 'outside the project folder') { $reason = Get-UiText 'permission.outside' }
        elseif ($reason -eq 'web' -and $Name -eq 'WebSearch') { $reason = Get-UiText 'permission.webSearch' }
        elseif ($reason -eq 'web') { $reason = Get-UiText 'permission.webFetch' }
        elseif ($reason -eq 'plan') { $reason = Get-UiText 'permission.planMode' }
        $label = (Get-UiText 'permission.why') + ': '
        foreach ($l in (Format-UiWrapped @(New-UiSpan $reason $mode.dim 'i') (Format-UiInk $label $hex) (' ' * $label.Length) $label.Length $inner)) { $null = $body.Add($l) }
    }
    $out = @($head)
    foreach ($b in $body) { $out += $side + $b }
    $out += '  ' + (Format-UiInk ((Get-UiBox 1) + ($h * ($width - 5))) $hex)
    Write-UiOut (($out -join "`n") + "`n")

    $badge = { param($key) Format-UiSpans @(New-UiSpan (' ' + $key + ' ') $mode.background 'b' $hex) }
    $choices = '  ' + (& $badge 'y') + ' ' + (Format-UiInk (Get-UiText 'permission.yes') $mode.foreground) + '    '
    if ($CanAlways) {
        $rules = @()
        if ($A) { try { $rules = @(Get-AlwaysRules $Name $A) } catch {} }
        $always = Get-UiText 'permission.always'
        if ($rules.Count -gt 0) { $always = Get-UiText 'permission.alwaysFor' ($rules -join ', ') }
        $choices += (& $badge 'a') + ' ' + (Format-UiInk (Limit-UiText $always ($width - 40)) $mode.foreground) + '    '
    }
    $choices += (& $badge 'n') + ' ' + (Format-UiInk (Get-UiText 'permission.no') $mode.foreground) + '   ' + (Format-UiInk ([string][char]0x203A) $hex -Bold) + ' '
    Write-UiOut $choices
}

function Write-UiPermissionAnswer([string]$Reply) {
    # Replaces the keys of the question by the answer.
    $ink = $script:Ui.ink
    $answer = (Get-UiSign 'ok') + ' ' + (Format-UiInk (Get-UiText 'permission.allowed') $ink.ok)
    if ($Reply -eq 'always') { $answer = (Get-UiSign 'ok') + ' ' + (Format-UiInk (Get-UiText 'permission.allowedAlways') $ink.ok) }
    if ($Reply -eq 'no') { $answer = (Get-UiSign 'error') + ' ' + (Format-UiInk (Get-UiText 'permission.denied') $ink.error) }
    Write-UiOut ("`r" + $script:Esc + '[2K  ' + $answer + "`n")
}

function Read-UiPermission([string]$Name, [string]$Subject, [string]$Why, [bool]$CanAlways, $A = $null) {
    # Asks before a call runs (Show-UiPermission) and reads one key: Enter, y or j yes;
    # a or i always; Esc or n no.
    Stop-UiActivity
    Show-UiPermission $Name $Subject $Why $CanAlways $A
    Set-UiProgress 0
    $reply = ''
    while (-not $reply) {
        $k = [Console]::ReadKey($true)
        $c = [string]$k.KeyChar
        # y and a; the German j (ja) and i (immer) of earlier versions work as well
        if ($k.Key -eq [ConsoleKey]::Enter -or $c -eq 'y' -or $c -eq 'j') { $reply = 'yes' }
        elseif ($CanAlways -and ($c -eq 'a' -or $c -eq 'i')) { $reply = 'always' }
        elseif ($k.Key -eq [ConsoleKey]::Escape -or $c -eq 'n') { $reply = 'no' }
    }
    Write-UiPermissionAnswer $reply
    if ($reply -ne 'no') {
        $script:Ui.toolStarted = [DateTime]::UtcNow
        Start-UiActivity 'tool' '' 400
    }
    return $reply
}
