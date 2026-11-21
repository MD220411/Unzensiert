# The status bar of the agent Unzensiert (lib\AgentUi.ps1): one line at the bottom of what the
# terminal shows - look and model, how full the context is, the rights, the graphics cards,
# folder and git, the last speed, the time - that stays visible while the model thinks and
# works and while you type, like the status line of Claude Code.
#
# It is not a fixed region of the window (lines scrolled out of such a region are lost in
# Windows Terminal, and PSReadLine does not know about it). Instead the bar always stands two
# rows under the end of the text, and every write that moves the text down takes the bar away
# and draws it again below, in the same write. Once the window is full, that is its bottom
# edge. So everything the terminal shows goes through Write-UiOut. Text that stays in its row
# (the activity line, the answer as it streams in) leaves the bar alone, so it does not
# flicker.
#
# The bar follows the column of the text by counting, without asking the console. That works
# because no printed row reaches the right edge of the window: the renderers wrap one column
# early, and text that streams in is broken by Write-UiRaw. Only when a row does reach the
# edge after all is the console asked where the cursor is.
#
# Without a real terminal (tests, the design preview, -p) the bar stays off and Write-UiOut
# just writes. Keep this file ASCII-only.

# --- writing ----------------------------------------------------------------------------------

function Write-UiOut([string]$Text, [switch]$Redraw) {
    # Everything the terminal shows. With the bar on: text that moves down (a new line, a block
    # printed again over its raw form) takes the bar away first and draws it again under the
    # new end; -Redraw draws it again in place (what it shows has changed).
    $bar = $script:Ui.bar
    $width = Get-UiWidth
    $cut = [Math]::Max($Text.LastIndexOf("`n"), $Text.LastIndexOf("`r"))
    if ($cut -ge 0) { $col = Measure-UiText $Text.Substring($cut + 1) }
    else { $col = $script:Ui.col + (Measure-UiText $Text) }
    $wrapped = ($col -ge $width)
    if (-not $bar.on) {
        if ($Text) { [Console]::Write($Text) }
        if ($wrapped) { $col = $col % $width }
        $script:Ui.col = $col
        return
    }
    $down = $wrapped -or $Text.Contains("`n") -or $Text.Contains($script:Esc + '[J')
    if ($bar.shown -and -not $down -and -not $Redraw) {
        if ($Text) { [Console]::Write($Text) }
        $script:Ui.col = $col
        return
    }
    $clear = ''
    if ($bar.shown) { $clear = $script:Esc + '[J' }
    if ($wrapped) {
        # a row reached the right edge after all and the terminal broke it: the console knows
        # where the cursor is now
        [Console]::Write($clear + $Text)
        $clear = ''
        $Text = ''
        try { $col = [Console]::CursorLeft } catch { $col = $col % $width }
    }
    [Console]::Write($clear + $Text + (Format-UiBarDraw $col $width))
    $script:Ui.col = $col
    $bar.shown = $true
}

function Write-UiRaw([string]$Text, [string]$Hex = '', [string]$Indent = '', [switch]$Italic) {
    # Text as it streams in, broken one column before the right edge instead of by the
    # terminal, so the bar under it can follow; new rows start with $Indent. Returns the
    # number of rows it began.
    $width = Get-UiWidth
    $breaks = 0
    $rest = $Text
    while ($rest.Length -gt 0) {
        $room = $width - 1 - $script:Ui.col
        if ($room -le 0) {
            Write-UiOut ("`n" + $Indent)
            $breaks++
            continue
        }
        $take = [Math]::Min($room, $rest.Length)
        Write-UiOut (Format-UiInk $rest.Substring(0, $take) $Hex -Italic:$Italic)
        $rest = $rest.Substring($take)
    }
    return $breaks
}

# --- the bar ----------------------------------------------------------------------------------

function Enable-UiBar($Session, [switch]$Force) {
    # Puts the bar under the text and keeps it there until Disable-UiBar (scripts\unzensiert.ps1
    # after the welcome). Only in a real terminal; -Force for the tests, which print into a
    # writer and start at column 0.
    if (-not $script:Ui.on) { return }
    if (-not $Force -and [Console]::IsOutputRedirected) { return }
    $bar = $script:Ui.bar
    $bar.session = $Session
    $bar.on = $true
    $bar.shown = $false
    $bar.key = ''
    if ($Force) { $script:Ui.col = 0 }
    else { try { $script:Ui.col = [Console]::CursorLeft } catch {} }
    Update-UiBarReadings
    Write-UiOut '' -Redraw
}

function Clear-UiInputTail {
    # For the keys of PSReadLine (lib\AgentUi.ps1): an input of three rows writes over the row
    # of the bar, and what is left of the bar stays to the right of it. With the cursor at the
    # end of the input that rest is cleared; the bar comes back under the next text.
    if (-not $script:Ui.bar.on) { return }
    $line = $null
    $cursor = $null
    try {
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($cursor -eq ([string]$line).Length) { [Console]::Write($script:Esc + '[K') }
    } catch {}
}

function Disable-UiBar {
    # Takes the bar off the screen (the end of the session): the terminal is left clean.
    $bar = $script:Ui.bar
    if (-not $bar.on) { return }
    if ($bar.shown) { [Console]::Write($script:Esc + '[J') }
    $bar.on = $false
    $bar.shown = $false
}

function Update-UiBarReadings([switch]$Cards, [switch]$Git) {
    # What the bar shows from outside the session: the graphics cards and git. -Cards reads
    # only the cards (the regular refresh while something runs), -Git only git (after a tool).
    $bar = $script:Ui.bar
    if (-not $bar.session) { return }
    if (-not $Git) {
        try { $bar.gpus = @(Get-GpuReadings) } catch { $bar.gpus = @() }
    }
    if (-not $Cards) {
        try { $bar.git = Get-GitSummary $bar.session.cwd } catch { $bar.git = $null }
    }
    $bar.readAt = [DateTime]::UtcNow.Ticks
}

function Update-UiBar {
    # Called about ten times a second while something runs (Test-UiStop): once a second it
    # looks whether what the bar shows has changed (time, cards, context, speed) and draws it
    # again; the cards are read again every "barRefreshSeconds" (style, section agent).
    $bar = $script:Ui.bar
    if (-not $bar.on) { return }
    $now = [DateTime]::UtcNow.Ticks
    if ($now - $bar.checkAt -lt 10000000) { return }
    $bar.checkAt = $now
    $every = [double](Get-UiLook 'barRefreshSeconds' 5)
    if ($every -gt 0 -and ($now - $bar.readAt) -ge $every * 10000000) { Update-UiBarReadings -Cards }
    if ((Get-UiBarKey (Get-UiWidth)) -cne $bar.key) { Write-UiOut '' -Redraw }
}

function Get-UiBarKey([int]$Width) {
    # What the line of the bar depends on, in values that are cheap to read: when this
    # changes, the line is built again.
    $bar = $script:Ui.bar
    $s = $bar.session
    return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $Width, $s.model, $s.mode, $s.promptTokens, $s.messages.Count, [int]$s.tokensPerSecond, [DateTime]::Now.ToString('HH:mm'), $bar.readAt)
}

function Get-UiBarLine([int]$Width) {
    # The line of the bar, built again only when something in it has changed (building it
    # sprays new separators and counts the context).
    $bar = $script:Ui.bar
    $key = Get-UiBarKey $Width
    if ($key -cne $bar.key) {
        $line = ''
        try { $line = Format-UiStatusLine $bar.session $Width $bar.gpus $bar.git } catch {}
        $bar.line = $line
        $bar.key = $key
    }
    return $bar.line
}

function Format-UiBarDraw([int]$Col, [int]$Width) {
    # Clears everything under the cursor, draws the bar two rows lower (an empty row between,
    # where a second row of input fits) and goes back up to the column of the text.
    return $script:Esc + '[J' + "`n`n" + (Get-UiBarLine $Width) + $script:Esc + '[2A' + $script:Esc + '[' + ($Col + 1) + 'G'
}

# --- the line ---------------------------------------------------------------------------------

function Get-UiContextShare($Session) {
    # Share of the context window in use (0..1), -1 when the size is unknown.
    $ctx = Get-SessionContextSize $Session
    if ($ctx -le 0) { return -1 }
    return [math]::Min(1.0, (Get-EstimatedTokens $Session) / [double]$ctx)
}

function Get-UiContextInk([double]$Used) {
    # Colour of the context gauge: the gauge colour of the mode (may be 'rainbow'), yellow
    # from 70 %, red from 85 %.
    $mode = $script:Ui.mode
    if ($Used -ge 0.85) { return $script:Ui.ink.error }
    if ($Used -ge 0.7) { return $script:Ui.ink.warn }
    return (Get-GaugeInk $mode $mode.accent)
}

function Format-UiContextGauge($Session, [int]$Width) {
    # Gauge and share of the context window in use.
    $mode = $script:Ui.mode
    $used = Get-UiContextShare $Session
    if ($used -lt 0) { return '' }
    return (Format-Gauge $used $Width (Get-UiContextInk $used) $mode.faint) + ' ' + (Format-UiInk ('{0} %' -f [int]($used * 100)) $mode.foreground)
}

function Format-UiStatusLine($Session, [int]$Width, $Gpus, $Git) {
    # The line of the bar, at most $Width - 1 columns: look and model, how full the context
    # is, the rights, the graphics cards, folder and git, the last speed, the time at the right
    # edge. When it does not fit, one step after the other until it does: speed and time go,
    # the folder loses git, the model the name of the look, the cards their names (gauges
    # only), the context its gauge; then folder, cards, context and rights go.
    $mode = $script:Ui.mode
    $parts = [ordered]@{}
    $model = Format-UiInk $Session.model $mode.foreground
    $parts['model'] = @{ text = (Format-ModeLabel $mode) + '  ' + $model; short = (Format-UiInk ([string]$mode.mark) $mode.accent) + ' ' + $model }
    $used = Get-UiContextShare $Session
    if ($used -ge 0) {
        $word = Format-UiInk (Get-UiText 'status.context') $mode.dim
        $shareHex = $mode.foreground
        if ($used -ge 0.7) { $shareHex = Get-UiContextInk $used }
        $share = Format-UiInk ('{0} %' -f [int]($used * 100)) $shareHex
        $parts['context'] = @{ text = $word + ' ' + (Format-UiContextGauge $Session 8); short = $word + ' ' + $share }
    }
    $parts['rights'] = @{ text = (Format-UiInk (Get-UiText 'status.rights') $mode.dim) + ' ' + (Format-UiInk $Session.mode (Get-UiModeInk $Session.mode) -Bold); short = '' }
    $cards = @(@($Gpus) | Where-Object { $_ })
    if ($cards.Count -gt 0) {
        $long = @()
        $gauges = @()
        $ink = Get-GaugeInk $mode $mode.accent
        foreach ($gpu in $cards) {
            $fraction = 0
            if ($gpu.totalMiB -gt 0) { $fraction = $gpu.usedMiB / $gpu.totalMiB }
            $long += (Format-UiInk ([string]$gpu.name -replace '^RTX\s+', '') $mode.dim) + ' ' + (Format-Gauge $fraction 6 $ink $mode.faint)
            $gauges += Format-Gauge $fraction 4 $ink $mode.faint
        }
        $parts['cards'] = @{ text = ($long -join '  '); short = (Format-UiInk (Get-UiText 'status.cards') $mode.dim) + ' ' + ($gauges -join ' ') }
    }
    $folder = Format-UiInk (Split-Path -Leaf $Session.cwd) $mode.foreground
    $parts['folder'] = @{ text = $folder; short = '' }
    if ($Git) { $parts['folder'] = @{ text = $folder + ' ' + (Format-GitSummary $Git $mode.dim); short = $folder } }
    if ($Session.tokensPerSecond -gt 0) { $parts['speed'] = @{ text = (Format-UiInk ('{0} tok/s' -f [int]$Session.tokensPerSecond) $mode.foreground); short = '' } }
    $clock = (Get-Date).ToString('HH:mm')
    $steps = @('speed-', 'clock-', 'folder<', 'model<', 'cards<', 'context<', 'folder-', 'cards-', 'context-', 'rights-')
    $step = 0
    while ($true) {
        $total = 1 + 5 * ($parts.Count - 1)
        foreach ($p in $parts.Values) { $total += (Measure-UiText $p.text) }
        if ($clock) { $total += $clock.Length + 2 }
        if ($total -lt $Width -or $step -ge $steps.Count) { break }
        $name = $steps[$step].Substring(0, $steps[$step].Length - 1)
        $shorten = $steps[$step].EndsWith('<')
        $step++
        if ($name -eq 'clock') { $clock = ''; continue }
        if (-not $parts.Contains($name)) { continue }
        if (-not $shorten) { $parts.Remove($name); continue }
        if ($parts[$name].short) { $parts[$name].text = $parts[$name].short }
    }
    $line = ''
    foreach ($p in $parts.Values) {
        if ($line) { $line += (Get-UiSep) } else { $line = ' ' }
        $line += $p.text
    }
    if ($clock) {
        $pad = $Width - 1 - (Measure-UiText $line) - $clock.Length
        $line += (' ' * [Math]::Max(2, $pad)) + (Format-UiInk $clock $mode.dim)
    }
    return $line
}

function Write-UiStatus($Session) {
    # The line of the bar printed once in the text, with an empty line before it (the design
    # preview and the tests; a session shows it in the bar).
    $line = Format-UiStatusLine $Session (Get-UiWidth) @(Get-GpuReadings) (Get-GitSummary $Session.cwd)
    Write-UiOut ("`n" + $line + "`n")
}
