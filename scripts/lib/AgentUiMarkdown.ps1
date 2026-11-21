# The answer of the model at the terminal of Unzensiert (lib\AgentUi.ps1). It is printed as it
# streams in, and every finished line is printed again in its final form: Markdown (headings,
# lists with nested signs, task lists, quotes, rules, tables, `code`, **bold**, *italic*,
# ~~strike~~, links), wrapped at word boundaries with hanging indents; code blocks in a frame
# with the colours of their language (keywords, strings, numbers, comments, variables,
# functions, types). While the model thinks, the activity line counts along; with /think the
# thinking is shown as it comes. Keep this file ASCII-only.

$script:UiInlineRe = [regex]('(?<code>`+)(?<ctext>.+?)\k<code>' +
    '|\*\*(?<b1>[^*].*?)\*\*|__(?<b2>[^_].*?)__|~~(?<st>.+?)~~' +
    '|(?<![\w*])\*(?![\s*])(?<i1>.+?)(?<![\s*])\*(?![\w*])' +
    '|(?<![\w_])_(?![\s_])(?<i2>.+?)(?<![\s_])_(?![\w_])' +
    '|\[(?<ltext>[^\]]+)\]\((?<lurl>[^)\s]+)(?:\s+"[^"]*")?\)' +
    '|(?<url>https?://[^\s<>()\[\]"'']*[^\s<>()\[\]"''.,;:!?])')
$script:UiWordRe = [regex]'\s+|\S+'
$script:UiLangSpecs = @{}
$script:UiBlockEnd = @{ '/*' = '*/'; '<#' = '#>'; '"""' = '"""'; "'''" = "'''" }

# --- the stream -----------------------------------------------------------------------------------

function Start-UiAnswer {
    # A new answer of the model begins: the activity line waits with it.
    $script:Ui.answerStarted = $false
    $script:Ui.thinkChars = 0
    $script:Ui.thinkClosed = $false
    $script:Ui.thinkLive = $false
    $script:Ui.inCode = $false
    $script:Ui.codeState = ''
    $script:Ui.inTable = $false
    $null = $script:Ui.line.Clear()
    $script:Ui.lineStarted = $false
    if ($script:Ui.on -and -not $script:Ui.gap) { Write-UiOut "`n"; $script:Ui.gap = $true }
    Start-UiActivity 'model'
}

function Add-UiReasoning([string]$Text) {
    # Thinking of the model: counted in the activity line, or shown dim and italic (/think).
    if (-not $script:Ui.on) { return }
    if ($script:Ui.thinkChars -eq 0) { $script:Ui.thinkStart = [DateTime]::UtcNow }
    $script:Ui.thinkChars += $Text.Length
    if ($script:Ui.showThinking) {
        $mode = $script:Ui.mode
        $bar = '  ' + (Format-UiInk (Get-UiMark 'thinking' '|') $mode.faint) + ' '
        if (-not $script:Ui.thinkLive) {
            Stop-UiActivity
            $script:Ui.thinkLive = $true
            $script:Ui.gap = $false
            Write-UiOut $bar
        }
        $pieces = $Text.Replace("`r", '').Replace("`t", '    ').Split("`n")
        for ($i = 0; $i -lt $pieces.Count; $i++) {
            if ($i -gt 0) { Write-UiOut ("`n" + $bar) }
            if ($pieces[$i]) { $null = Write-UiRaw $pieces[$i] $mode.dim $bar -Italic }
        }
        return
    }
    if ($script:Ui.act.kind -ne 'think') { Start-UiActivity 'think' }
    Add-UiActivityChars $Text.Length
    Update-UiActivity
}

function Close-UiThinking {
    # The thinking is over: one quiet line says how long and how much.
    if (-not $script:Ui.on -or $script:Ui.thinkChars -eq 0 -or $script:Ui.thinkClosed) { return }
    $script:Ui.thinkClosed = $true
    $mode = $script:Ui.mode
    if ($script:Ui.thinkLive) { Write-UiOut "`n"; $script:Ui.thinkLive = $false }
    Clear-UiActivityLine
    if ($script:Ui.act.kind -eq 'think') { $script:Ui.act.kind = '' }
    $secs = ([DateTime]::UtcNow - $script:Ui.thinkStart).TotalSeconds
    $text = Get-UiText 'activity.thought' (Format-UiDuration $secs) (Get-UiCount ([int]($script:Ui.thinkChars / 4)) 'tokens')
    $script:Ui.gap = $false
    Write-UiOut ('  ' + (Format-UiInk (Get-UiMark 'thought' ':') $mode.faint) + ' ' + (Format-UiInk $text $mode.dim -Italic) + "`n")
}

function Add-UiToolDraft([string]$Name) {
    # The model begins to write a tool call: the activity line says which tool.
    if (-not $script:Ui.on) { return }
    Close-UiThinking
    Complete-UiLine
    Start-UiActivity 'call' $Name
}

function Get-UiPrefix {
    # The first line of an answer starts with the sign of the style, the others are indented.
    if (-not $script:Ui.answerStarted) {
        $script:Ui.answerStarted = $true
        return (Format-UiInk (Get-UiMark 'answer' '*') (Get-UiWheelHex $script:StyleRandom.NextDouble()) -Bold) + ' '
    }
    return '  '
}

function Add-UiContent([string]$Text) {
    # Prints the answer as it arrives; a finished line is printed again in its final form.
    # The raw line is broken before the right edge (Write-UiRaw), which counts its rows.
    if (-not $script:Ui.on) { return }
    if ($script:Ui.act.kind) { Stop-UiActivity }
    Close-UiThinking
    $parts = $Text.Split("`n")
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $seg = $parts[$i].TrimEnd("`r").Replace("`t", '    ')
        if ($seg) {
            if (-not $script:Ui.lineStarted) {
                $script:Ui.lineStarted = $true
                $script:Ui.gap = $false
                $script:Ui.rawRows = 0
                $script:Ui.prefix = Get-UiPrefix
                Write-UiOut $script:Ui.prefix
            }
            $null = $script:Ui.line.Append($seg)
            $script:Ui.rawRows += Write-UiRaw $seg
        }
        if ($i -lt $parts.Count - 1) { Complete-UiLine -Force }
    }
}

function Complete-UiLine([switch]$Force) {
    # Ends the current line of the answer: the raw text (which may have wrapped over several
    # rows) is replaced by its formatted, word-wrapped form.
    if (-not $script:Ui.on) { return }
    if (-not $script:Ui.lineStarted) {
        if ($Force -and $script:Ui.answerStarted) {
            if ($script:Ui.inCode) { Write-UiOut (((Format-UiMarkdownLine '' '  ') -join "`n") + "`n") }
            else { $script:Ui.inTable = $false; Write-UiOut "`n" }
        }
        return
    }
    $raw = $script:Ui.line.ToString()
    $null = $script:Ui.line.Clear()
    $script:Ui.lineStarted = $false
    $rows = 1 + $script:Ui.rawRows
    $script:Ui.extraUp = 0
    $out = Format-UiMarkdownLine $raw $script:Ui.prefix
    $rows += $script:Ui.extraUp
    $up = ''
    if ($rows -gt 1) { $up = $script:Esc + '[' + ($rows - 1) + 'A' }
    Write-UiOut ("`r" + $up + $script:Esc + '[J' + (@($out) -join "`n") + "`n")
}

function Complete-UiAnswer {
    Close-UiThinking
    Complete-UiLine
    Stop-UiActivity
}

# --- Markdown ----------------------------------------------------------------------------------------

function Get-UiBox([int]$Index) {
    # Frame signs of "agent.box": 0 top left, 1 bottom left, 2 line, 3 side.
    $box = [string](Get-UiLook 'box' '')
    if ($box.Length -lt 4) { $box = [string][char]0x256D + [char]0x2570 + [char]0x2500 + [char]0x2502 }
    return [string]$box[$Index]
}

function Add-UiSpanPiece($List, [string]$Text, $Src) {
    # Adds text in the look of span $Src, joined to the previous piece of the same span.
    if ($List.Count -gt 0) {
        $last = $List[$List.Count - 1]
        if ([object]::ReferenceEquals($last.src, $Src)) { $last.t += $Text; return }
    }
    $null = $List.Add(@{ t = $Text; fg = $Src.fg; a = $Src.a; bg = $Src.bg; link = $Src.link; src = $Src })
}

function Format-UiWrapped($Spans, [string]$First, [string]$Next, [int]$Indent, [int]$Width, [string]$Bg = '') {
    # The spans as lines broken at spaces, none wider than $Width: $First before the first,
    # $Next before the others (both $Indent columns wide). A word longer than a line is cut.
    $max = [Math]::Max(8, $Width - $Indent - 1)
    $rows = New-Object System.Collections.ArrayList
    $cur = New-Object System.Collections.ArrayList
    $col = 0
    $gap = $null
    foreach ($s in $Spans) {
        if ($null -eq $s -or -not $s.t) { continue }
        foreach ($m in $script:UiWordRe.Matches([string]$s.t)) {
            $tok = $m.Value
            if ([char]::IsWhiteSpace($tok[0])) {
                if ($col -gt 0) { $gap = @($tok, $s) }
                continue
            }
            $need = $tok.Length
            if ($gap) { $need += $gap[0].Length }
            if ($col -gt 0 -and $col + $need -gt $max) {
                $null = $rows.Add($cur)
                $cur = New-Object System.Collections.ArrayList
                $col = 0
                $gap = $null
            }
            if ($gap) { Add-UiSpanPiece $cur $gap[0] $gap[1]; $col += $gap[0].Length; $gap = $null }
            while ($col + $tok.Length -gt $max) {
                $take = $max - $col
                if ($take -gt 0) { Add-UiSpanPiece $cur ($tok.Substring(0, $take)) $s; $tok = $tok.Substring($take) }
                $null = $rows.Add($cur)
                $cur = New-Object System.Collections.ArrayList
                $col = 0
            }
            if ($tok) { Add-UiSpanPiece $cur $tok $s; $col += $tok.Length }
        }
    }
    if ($cur.Count -gt 0 -or $rows.Count -eq 0) { $null = $rows.Add($cur) }
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $p = $Next
        if ($i -eq 0) { $p = $First }
        $null = $out.Add($p + (Format-UiSpans $rows[$i] $Bg))
    }
    return , $out
}

function Split-UiSpans($Spans, [int]$Max) {
    # The spans cut into rows of at most $Max columns (for code, which is not broken at spaces).
    $rows = New-Object System.Collections.ArrayList
    $cur = New-Object System.Collections.ArrayList
    $col = 0
    foreach ($s in $Spans) {
        $t = [string]$s.t
        while ($t.Length -gt 0) {
            $take = [Math]::Min($t.Length, $Max - $col)
            if ($take -le 0) {
                $null = $rows.Add($cur)
                $cur = New-Object System.Collections.ArrayList
                $col = 0
                continue
            }
            Add-UiSpanPiece $cur ($t.Substring(0, $take)) $s
            $col += $take
            $t = $t.Substring($take)
        }
    }
    $null = $rows.Add($cur)
    return , $rows
}

function ConvertTo-UiInlineSpans([string]$Text, [string]$Fg, [string]$Attr = '') {
    # Inline Markdown as spans: `code` (with a tinted background), **bold**, *italic*,
    # ~~strike~~, [links](...) and bare addresses.
    $mode = $script:Ui.mode
    $spans = New-Object System.Collections.ArrayList
    $codeHex = [string]$script:Ui.ink.branch
    $pos = 0
    foreach ($m in $script:UiInlineRe.Matches($Text)) {
        if ($m.Index -gt $pos) { $null = $spans.Add((New-UiSpan ($Text.Substring($pos, $m.Index - $pos)) $Fg $Attr)) }
        $g = $m.Groups
        if ($g['code'].Success) {
            $null = $spans.Add((New-UiSpan $g['ctext'].Value $codeHex $Attr (Get-UiMixHex $codeHex $mode.background 0.86)))
        } elseif ($g['b1'].Success -or $g['b2'].Success) {
            $inner = $g['b1'].Value + $g['b2'].Value
            foreach ($s in (ConvertTo-UiInlineSpans $inner $mode.foreground ($Attr + 'b'))) { $null = $spans.Add($s) }
        } elseif ($g['i1'].Success -or $g['i2'].Success) {
            $inner = $g['i1'].Value + $g['i2'].Value
            foreach ($s in (ConvertTo-UiInlineSpans $inner $Fg ($Attr + 'i'))) { $null = $spans.Add($s) }
        } elseif ($g['st'].Success) {
            $null = $spans.Add((New-UiSpan $g['st'].Value $mode.dim ($Attr + 's')))
        } elseif ($g['ltext'].Success) {
            $null = $spans.Add((New-UiSpan $g['ltext'].Value $codeHex ($Attr + 'u') '' $g['lurl'].Value))
        } else {
            $null = $spans.Add((New-UiSpan $g['url'].Value $codeHex ($Attr + 'u') '' $g['url'].Value))
        }
        $pos = $m.Index + $m.Length
    }
    if ($pos -lt $Text.Length) { $null = $spans.Add((New-UiSpan ($Text.Substring($pos)) $Fg $Attr)) }
    return , $spans
}

function Format-UiTable($Table, [int]$Avail) {
    # The rows of a table so far with aligned columns: the head (the rows above the line of
    # dashes, or the first row) in colour, a faint line under it, cells cut when the table
    # is wider than the window.
    $mode = $script:Ui.mode
    $count = 0
    foreach ($r in $Table.rows) { if (@($r).Count -gt $count) { $count = @($r).Count } }
    $headRows = $Table.sep
    if ($headRows -lt 0) { $headRows = 1 }
    $cells = New-Object System.Collections.ArrayList
    $widths = New-Object 'int[]' $count
    for ($r = 0; $r -lt $Table.rows.Count; $r++) {
        $row = @($Table.rows[$r])
        $spansRow = New-Object System.Collections.ArrayList
        for ($c = 0; $c -lt $count; $c++) {
            $text = ''
            if ($c -lt $row.Count) { $text = [string]$row[$c] }
            if ($r -lt $headRows) { $spans = ConvertTo-UiInlineSpans $text (Get-UiWheelHex ($script:Ui.phase + 0.5 + 0.12 * $c)) 'b' }
            else { $spans = ConvertTo-UiInlineSpans $text $mode.foreground }
            $len = 0
            foreach ($s in $spans) { $len += ([string]$s.t).Length }
            if ($len -gt $widths[$c]) { $widths[$c] = $len }
            $null = $spansRow.Add($spans)
        }
        $null = $cells.Add($spansRow)
    }
    # too wide for the window: take from the widest column until it fits
    $total = 1
    foreach ($w in $widths) { $total += $w + 3 }
    while ($total -gt $Avail) {
        $widest = 0
        for ($c = 1; $c -lt $count; $c++) { if ($widths[$c] -gt $widths[$widest]) { $widest = $c } }
        if ($widths[$widest] -le 4) { break }
        $widths[$widest]--
        $total--
    }
    $bar = Format-UiInk (' ' + [string][char]0x2502 + ' ') $mode.faint
    $lines = New-Object System.Collections.ArrayList
    for ($r = 0; $r -lt $cells.Count; $r++) {
        $sb = ' '
        for ($c = 0; $c -lt $count; $c++) {
            $cut = Split-UiSpans $cells[$r][$c] ([Math]::Max(1, $widths[$c]))
            $used = 0
            foreach ($s in $cut[0]) { $used += ([string]$s.t).Length }
            $sb += Format-UiSpans $cut[0]
            if ($cut.Count -gt 1 -and $cut[1].Count -gt 0) { $sb += Format-UiInk $script:UiDots $mode.dim; $used++ }
            if ($c -lt $count - 1) { $sb += (' ' * [Math]::Max(0, $widths[$c] - $used)) + $bar }
        }
        $null = $lines.Add($sb)
        if ($r -eq $headRows - 1) {
            $h = [string][char]0x2500
            $parts = @()
            for ($c = 0; $c -lt $count; $c++) { $parts += ($h * ($widths[$c] + 2)) }
            $null = $lines.Add((Format-UiInk ($parts -join [string][char]0x253C) $mode.faint))
        }
    }
    return , $lines
}

function Format-UiCodeFrame([string]$Edge, [string]$Label, [int]$Avail) {
    # The top of a code block with its language, or its bottom.
    $mode = $script:Ui.mode
    $h = Get-UiBox 2
    $w = [Math]::Max(12, [Math]::Min($Avail - 1, 64))
    if ($Edge -eq 'top') {
        $text = ''
        if ($Label) { $text = ' ' + $Label + ' ' }
        return (Format-UiInk ((Get-UiBox 0) + $h) $mode.faint) + (Format-UiInk $text $mode.dim -Italic) + (Format-UiInk ($h * [Math]::Max(2, $w - 2 - $text.Length)) $mode.faint)
    }
    return (Format-UiInk ((Get-UiBox 1) + ($h * ($w - 1))) $mode.faint)
}

function Format-UiMarkdownLine([string]$Raw, [string]$Prefix) {
    # One line of the answer in its final form, as one or more terminal lines. $Prefix is
    # the start of the first one (2 columns: the sign of the answer or two spaces).
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    $avail = $width - 2
    $out = New-Object System.Collections.ArrayList
    $trim = $Raw.Trim()

    # code blocks: a frame with the language, the lines in its colours
    if ($script:Ui.inCode) {
        if ($trim -match '^([`~]{3,})\s*$' -and $Matches[1][0] -eq $script:Ui.codeFence[0] -and $Matches[1].Length -ge $script:Ui.codeFence.Length) {
            $script:Ui.inCode = $false
            $null = $out.Add($Prefix + (Format-UiCodeFrame 'bottom' '' $avail))
            return , $out
        }
        $bar = Format-UiInk ((Get-UiBox 3) + ' ') $mode.faint
        $p = $Prefix
        foreach ($r in (Split-UiSpans (ConvertTo-UiCodeSpans $Raw $script:Ui.codeLang) ([Math]::Max(8, $avail - 3)))) {
            $null = $out.Add($p + $bar + (Format-UiSpans $r))
            $p = '  '
        }
        return , $out
    }
    if ($trim -match '^(`{3,}|~{3,})\s*([^\s`]*)') {
        $script:Ui.inCode = $true
        $script:Ui.codeFence = $Matches[1]
        $script:Ui.codeLang = Get-UiCodeLang $Matches[2]
        $script:Ui.codeState = ''
        $null = $out.Add($Prefix + (Format-UiCodeFrame 'top' $Matches[2] $avail))
        return , $out
    }
    if (-not $trim) { $script:Ui.inTable = $false; $null = $out.Add(''); return , $out }

    # tables: kept row by row and drawn again, with aligned columns, as every row arrives
    if ($trim -match '^\|.*\|$') {
        if (-not $script:Ui.inTable) {
            $script:Ui.inTable = $true
            $script:Ui.table = @{ rows = (New-Object System.Collections.ArrayList); sep = -1; printed = 0; prefix = $Prefix }
        }
        $tb = $script:Ui.table
        if ($trim -match '^\|[\s:|-]+\|$' -and $trim.Contains('-')) { $tb.sep = $tb.rows.Count }
        else { $null = $tb.rows.Add(@([regex]::Split($trim.Substring(1, $trim.Length - 2), '(?<!\\)\|') | ForEach-Object { $_.Trim() })) }
        $lines = Format-UiTable $tb $avail
        $height = 40
        try { $height = [Console]::WindowHeight } catch {}
        $first = 0
        if ($tb.printed + 3 -lt $height) { $script:Ui.extraUp = $tb.printed }
        else { $first = $tb.printed }
        for ($i = $first; $i -lt $lines.Count; $i++) {
            $p = '  '
            if ($i -eq 0) { $p = $tb.prefix }
            $null = $out.Add($p + $lines[$i])
        }
        $tb.printed = $lines.Count
        return , $out
    }
    $script:Ui.inTable = $false

    # headings: the first in the colour of the style (along the wheel when it fits), with a
    # sprayed line below
    if ($Raw -match '^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$') {
        $level = $Matches[1].Length
        $text = $Matches[2]
        $ink = [string](Get-UiLook 'headingInk' 'accent')
        if ($level -eq 1 -and $text -notmatch '[`*_\[]' -and $text.Length -lt $avail) {
            $null = $out.Add($Prefix + (Format-UiShimmer $text $ink $script:StyleRandom.NextDouble() -Bold))
        } else {
            $hex = $mode.foreground
            if ($level -le 2) { $hex = Resolve-UiInk $ink $script:StyleRandom.NextDouble() }
            foreach ($l in (Format-UiWrapped (ConvertTo-UiInlineSpans $text $hex 'b') $Prefix '  ' 2 $width)) { $null = $out.Add($l) }
        }
        if ($level -eq 1) { $null = $out.Add('  ' + (Format-UiRule ([Math]::Min($avail - 1, [Math]::Max(12, $text.Length + 6))))) }
        return , $out
    }
    # a rule across
    if ($Raw -match '^\s{0,3}([-*_])(\s*\1){2,}\s*$') {
        $null = $out.Add($Prefix + (Format-UiRule ([Math]::Min($avail - 1, 72))))
        return , $out
    }
    # quotes
    if ($Raw -match '^\s*>\s?(.*)$') {
        $bar = Format-UiInk ((Get-UiLook 'quote' '|') + ' ') $mode.accentSoft
        return (Format-UiWrapped (ConvertTo-UiInlineSpans $Matches[1] $mode.dim 'i') ($Prefix + $bar) ('  ' + $bar) 4 $width)
    }
    # lists: a sign per level, numbers, open and done tasks
    if ($Raw -match '^(\s*)[-*+]\s+(.*)$') {
        $level = [int][Math]::Floor($Matches[1].Length / 2)
        $body = $Matches[2]
        $bullets = @(Get-UiLook 'bullets' @([string][char]0x2022))
        $sign = [string]$bullets[$level % $bullets.Count]
        $hex = Get-UiWheelHex ($script:Ui.phase + 0.17 * $level)
        $fg = $mode.foreground
        if ($body -match '^\[( |x|X)\]\s+(.*)$') {
            if ($Matches[1] -eq ' ') { $sign = [string][char]0x25CB; $hex = $mode.dim }
            else { $sign = [string](Get-UiValue (Get-UiLook 'notes' $null) 'ok' 'x'); $hex = $script:Ui.ink.ok; $fg = $mode.dim }
            $body = $Matches[2]
        }
        $indent = '  ' * $level
        return (Format-UiWrapped (ConvertTo-UiInlineSpans $body $fg) ($Prefix + $indent + (Format-UiInk $sign $hex -Bold) + ' ') ('  ' + $indent + '  ') (4 + 2 * $level) $width)
    }
    if ($Raw -match '^(\s*)(\d+)([.)])\s+(.*)$') {
        $level = [int][Math]::Floor($Matches[1].Length / 2)
        $num = $Matches[2] + $Matches[3]
        $indent = '  ' * $level
        $hex = Get-UiWheelHex ($script:Ui.phase + 0.17 * $level)
        return (Format-UiWrapped (ConvertTo-UiInlineSpans $Matches[4] $mode.foreground) ($Prefix + $indent + (Format-UiInk $num $hex -Bold) + ' ') ('  ' + $indent + (' ' * ($num.Length + 1))) (3 + 2 * $level + $num.Length) $width)
    }
    # a paragraph, indented as the model indented it
    $lead = [Math]::Min(8, $Raw.Length - $Raw.TrimStart().Length)
    $pad = ' ' * $lead
    return (Format-UiWrapped (ConvertTo-UiInlineSpans $trim $mode.foreground) ($Prefix + $pad) ('  ' + $pad) (2 + $lead) $width)
}

# --- the colours of code ---------------------------------------------------------------------------

function Get-UiCodeLang([string]$Name) {
    # The highlighter for the word after ``` or the extension of a file.
    $n = $Name.ToLowerInvariant().TrimStart('.')
    if ($n -match '^(py|python|python3|pyw|pyi)$') { return 'python' }
    if ($n -match '^(ps1|psm1|psd1|powershell|pwsh|ps)$') { return 'powershell' }
    if ($n -match '^(sh|bash|zsh|shell|console|shellsession)$') { return 'bash' }
    if ($n -match '^(js|mjs|cjs|jsx|ts|tsx|javascript|typescript|node)$') { return 'js' }
    if ($n -match '^(c|h|cpp|cc|cxx|hpp|hh|c\+\+|ino|arduino|cs|csharp|java|kt|kotlin|go|golang|rs|rust|swift|dart|php|scala|groovy|gradle)$') { return 'c' }
    if ($n -match '^(json|jsonc|json5|jsonl|geojson)$') { return 'json' }
    if ($n -match '^(yml|yaml)$') { return 'yaml' }
    if ($n -match '^(toml|ini|cfg|conf|properties|env|editorconfig|gitconfig)$') { return 'ini' }
    if ($n -match '^(sql|sqlite|psql|mysql)$') { return 'sql' }
    if ($n -eq 'lua') { return 'lua' }
    if ($n -match '^(bat|cmd|batch)$') { return 'bat' }
    if ($n -match '^(html|htm|xml|svg|xaml|csproj|props|targets|vue)$') { return 'markup' }
    if ($n -match '^(css|scss|sass|less)$') { return 'css' }
    if ($n -match '^(diff|patch)$') { return 'diff' }
    if ($n -match '^(md|markdown|txt|text|plain|log|output)$') { return 'text' }
    return 'generic'
}

function Get-UiLangSpec([string]$Lang) {
    # The tokenizer of a language: one regular expression with named groups, the keywords,
    # whether they ignore case, whether capitalised words are types. Built once.
    if ($script:UiLangSpecs.ContainsKey($Lang)) { return $script:UiLangSpecs[$Lang] }
    $dq = '"(?:[^"\\]|\\.)*"?'
    $sq = "'(?:[^'\\]|\\.)*'?"
    $num = '\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?[fFlLuU]*)\b'
    $op = '[-+*/%=<>!&|^~?:]+'
    $word = '[A-Za-z_]\w*'
    $kw = ''
    $ci = $false
    $types = $false
    switch ($Lang) {
        'python' {
            $p = '(?<blk>"""|' + "''')" + '|(?<com>#.*$)|(?<str>(?:[rRbBfFuU]{1,2})?(?:' + $dq + '|' + $sq + '))|(?<dec>@[\w.]+)|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>' + $op + ')'
            $kw = 'False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls print len range'
            $types = $true
        }
        'powershell' {
            $p = '(?<blk><#)|(?<com>#.*$)|(?<str>"(?:[^"`]|`.)*"?|''(?:[^'']|'''')*''?)|(?<var>\$(?:\{[^}]*\}|[\w:?]+))|(?<type>\[[\w.,\[\] ]+\])|(?<param>(?<![\w-])-[A-Za-z][\w-]*)|(?<cmd>\b[A-Za-z]+-[A-Za-z]\w*)|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>[-+*/%=<>!&|]+)'
            $kw = 'begin break catch class continue data do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using while'
            $ci = $true
        }
        'bash' {
            $p = '(?<com>(?<![\w$])#.*$)|(?<str>' + $dq + "|'[^']*'?)" + '|(?<var>\$(?:\{[^}]*\}|\(|\w+|[@#?$!*0-9]))|(?<param>(?<![\w-])--?[A-Za-z][\w-]*)|(?<num>' + $num + ')|(?<word>[A-Za-z_][\w.-]*)|(?<op>[|&;<>]+)'
            $kw = 'if then else elif fi for while until do done case esac in function return local export readonly declare set unset shift exit source sudo'
        }
        'js' {
            $p = '(?<blk>/\*)|(?<com>//.*$)|(?<str>' + $dq + '|' + $sq + '|`(?:[^`\\]|\\.)*`?)|(?<dec>@\w+)|(?<num>' + $num + ')|(?<word>[A-Za-z_$][\w$]*)|(?<op>' + $op + ')'
            $kw = 'break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of null undefined true false static get set from as interface type enum implements private public protected readonly declare'
            $types = $true
        }
        'c' {
            $p = '(?<blk>/\*)|(?<com>//.*$)|(?<pre>^\s*#\s*\w+)|(?<str>' + $dq + '|' + $sq + ')|(?<dec>@\w+)|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>' + $op + ')'
            $kw = 'auto break case char const continue default do double else enum extern float for goto if int long register return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false class public private protected new delete this namespace using template typename virtual override nullptr string var foreach in out ref is as base readonly sealed async await func package import type interface map chan go defer select range fn let mut impl trait pub use mod match self crate where loop move dyn final extends implements throws throw try catch finally null uint8_t uint16_t uint32_t int8_t int16_t int32_t size_t'
            $types = $true
        }
        'json' {
            $p = '(?<key>"(?:[^"\\]|\\.)*"(?=\s*:))|(?<str>' + $dq + ')|(?<num>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?<word>\b(?:true|false|null)\b)|(?<op>[{}\[\],:])'
            $kw = 'true false null'
        }
        'yaml' {
            $p = '(?<com>(?<!\S)#.*$)|(?<key>^\s*(?:-\s+)?[\w.\-/]+(?=\s*:(?:\s|$)))|(?<str>' + $dq + '|' + $sq + ')|(?<num>' + $num + ')|(?<word>\b(?:true|false|null|yes|no|on|off)\b)|(?<op>[-:|>\[\]{},])'
            $kw = 'true false null yes no on off'
        }
        'ini' {
            $p = '(?<com>^\s*[#;].*$)|(?<pre>^\s*\[.*\]\s*$)|(?<key>^\s*[\w.\-]+(?=\s*=))|(?<str>' + $dq + '|' + $sq + ')|(?<num>' + $num + ')|(?<word>\b(?:true|false)\b)|(?<op>=)'
            $kw = 'true false'
        }
        'sql' {
            $p = '(?<blk>/\*)|(?<com>--.*$)|(?<str>''(?:[^'']|'''')*''?)|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>' + $op + ')'
            $kw = 'select from where and or not insert into values update set delete create table drop alter join left right inner outer on group by order having limit as distinct null is in like between union all case when then else end primary key foreign references index view if exists integer text real blob varchar int'
            $ci = $true
        }
        'lua' {
            $p = '(?<com>--.*$)|(?<str>' + $dq + '|' + $sq + ')|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>' + $op + ')'
            $kw = 'and break do else elseif end false for function goto if in local nil not or repeat return then true until while'
        }
        'bat' {
            $p = '(?<com>^\s*(?:rem\b|::).*$)|(?<var>%[\w~:]+%?|![\w]+!)|(?<str>"[^"]*"?)|(?<pre>^\s*:\w+)|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>[|&<>=]+)'
            $kw = 'echo set if else goto call exit for in do not exist errorlevel setlocal endlocal pause cd start defined equ neq'
            $ci = $true
        }
        'markup' {
            $p = '(?<com><!--.*?(?:-->|$))|(?<pre></?[\w:.-]+|/?>)|(?<key>\b[\w:.-]+(?==))|(?<str>"[^"]*"?|''[^'']*''?)|(?<num>&#?\w+;)'
        }
        'css' {
            $p = '(?<blk>/\*)|(?<str>' + $dq + '|' + $sq + ')|(?<key>[\w-]+(?=\s*:(?!:)))|(?<num>#[0-9a-fA-F]{3,8}\b|-?\d+(?:\.\d+)?(?:px|em|rem|%|s|ms|vh|vw|deg|fr)?)|(?<dec>[.#][\w-]+|@[\w-]+)|(?<word>[\w-]+)|(?<op>[{}:;,>+~])'
        }
        default {
            $p = '(?<str>' + $dq + '|' + $sq + ')|(?<num>' + $num + ')|(?<word>' + $word + ')|(?<op>' + $op + ')'
        }
    }
    $comparer = [System.StringComparer]::Ordinal
    if ($ci) { $comparer = [System.StringComparer]::OrdinalIgnoreCase }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList $comparer
    foreach ($k in ($kw -split ' ')) { if ($k) { $null = $set.Add($k) } }
    $spec = @{ re = [regex]$p; kw = $set; types = $types }
    $script:UiLangSpecs[$Lang] = $spec
    return $spec
}

function Get-UiSyntaxHex([string]$Name) {
    # A colour of "shell.syntax" of the style (the same as the input line of the shell).
    $hex = [string](Get-UiValue $script:Ui.syntax $Name '')
    if ($hex -match '^#[0-9A-Fa-f]{6}$') { return $hex }
    if ($Name -eq 'Comment') { return [string]$script:Ui.mode.dim }
    return [string]$script:Ui.mode.foreground
}

function ConvertTo-UiCodeSpans([string]$Line, [string]$Lang) {
    # One line of code as coloured spans. A block comment or string that does not end on its
    # line carries over to the next ($script:Ui.codeState).
    $spans = New-Object System.Collections.ArrayList
    $def = Get-UiSyntaxHex 'Default'
    if ($Lang -eq 'diff') {
        $hex = $script:Ui.mode.dim
        if ($Line.StartsWith('+')) { $hex = $script:Ui.ink.ok }
        elseif ($Line.StartsWith('-')) { $hex = $script:Ui.ink.error }
        elseif ($Line.StartsWith('@@')) { $hex = $script:Ui.ink.branch }
        $null = $spans.Add((New-UiSpan $Line $hex))
        return , $spans
    }
    if ($Lang -eq 'text' -or -not $Line) {
        if ($Line) { $null = $spans.Add((New-UiSpan $Line $def)) }
        return , $spans
    }
    $spec = Get-UiLangSpec $Lang
    $pos = 0
    if ($script:Ui.codeState) {
        $term = [string]$script:Ui.codeState
        $hex = Get-UiSyntaxHex 'String'
        $attr = ''
        if ($term -eq '*/' -or $term -eq '#>') { $hex = Get-UiSyntaxHex 'Comment'; $attr = 'i' }
        $end = $Line.IndexOf($term)
        if ($end -lt 0) { $null = $spans.Add((New-UiSpan $Line $hex $attr)); return , $spans }
        $pos = $end + $term.Length
        $null = $spans.Add((New-UiSpan ($Line.Substring(0, $pos)) $hex $attr))
        $script:Ui.codeState = ''
    }
    while ($pos -lt $Line.Length) {
        $m = $spec.re.Match($Line, $pos)
        if (-not $m.Success) { break }
        if ($m.Index -gt $pos) { $null = $spans.Add((New-UiSpan ($Line.Substring($pos, $m.Index - $pos)) $def)) }
        if ($m.Length -eq 0) { $null = $spans.Add((New-UiSpan ([string]$Line[$m.Index]) $def)); $pos = $m.Index + 1; continue }
        $text = $m.Value
        $hex = $def
        $attr = ''
        $g = $m.Groups
        if ($g['blk'].Success) {
            $term = [string]$script:UiBlockEnd[$text]
            $hex = Get-UiSyntaxHex 'String'
            if ($term -eq '*/' -or $term -eq '#>') { $hex = Get-UiSyntaxHex 'Comment'; $attr = 'i' }
            $close = $Line.IndexOf($term, $m.Index + $text.Length)
            if ($close -lt 0) { $text = $Line.Substring($m.Index); $script:Ui.codeState = $term }
            else { $text = $Line.Substring($m.Index, $close + $term.Length - $m.Index) }
        }
        elseif ($g['com'].Success) { $hex = Get-UiSyntaxHex 'Comment'; $attr = 'i' }
        elseif ($g['str'].Success) { $hex = Get-UiSyntaxHex 'String' }
        elseif ($g['num'].Success) { $hex = Get-UiSyntaxHex 'Number' }
        elseif ($g['var'].Success) { $hex = Get-UiSyntaxHex 'Variable' }
        elseif ($g['param'].Success) { $hex = Get-UiSyntaxHex 'Parameter' }
        elseif ($g['cmd'].Success) { $hex = Get-UiSyntaxHex 'Command' }
        elseif ($g['type'].Success -or $g['dec'].Success) { $hex = Get-UiSyntaxHex 'Type' }
        elseif ($g['key'].Success) { $hex = Get-UiSyntaxHex 'Member' }
        elseif ($g['pre'].Success) { $hex = Get-UiSyntaxHex 'Keyword' }
        elseif ($g['op'].Success) { $hex = Get-UiSyntaxHex 'Operator' }
        elseif ($g['word'].Success) {
            if ($spec.kw.Contains($text)) { $hex = Get-UiSyntaxHex 'Keyword' }
            else {
                $after = $m.Index + $text.Length
                while ($after -lt $Line.Length -and $Line[$after] -eq ' ') { $after++ }
                if ($after -lt $Line.Length -and $Line[$after] -eq '(') { $hex = Get-UiSyntaxHex 'Command' }
                elseif ($spec.types -and $text -cmatch '^[A-Z][a-z0-9]\w*$') { $hex = Get-UiSyntaxHex 'Type' }
            }
        }
        $null = $spans.Add((New-UiSpan $text $hex $attr))
        $pos = $m.Index + $text.Length
    }
    if ($pos -lt $Line.Length) { $null = $spans.Add((New-UiSpan ($Line.Substring($pos)) $def)) }
    return , $spans
}
