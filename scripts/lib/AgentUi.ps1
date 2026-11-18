# The terminal of the agent Unzensiert, in the look of the active style (config\style.json,
# section "agent" of the style file, lib\Style.ps1) and with the texts of
# config\unzensiert-texte.json: the welcome, the activity line while the model or a tool
# works (spinner, time so far, window title, the progress mark of Windows Terminal), notes,
# the input line with the status line above it, the overviews of /help, /status and /model,
# the line after every request and the farewell. The answer with its Markdown lives in
# lib\AgentUiMarkdown.ps1, tool calls, changes and questions in lib\AgentUiTools.ps1.
# Without a terminal (-p) nothing is printed.
#
# Text is built from spans (New-UiSpan: text, colour, background, attributes, link) and
# turned into escape sequences by Format-UiSpans, so lines can be measured, wrapped and
# given a background. Needs lib\Style.ps1. Keep this file ASCII-only: every glyph and
# every German text lives in the style file or in config\unzensiert-texte.json.

$script:Ui = @{ on = $false }
$script:Esc = [string][char]27
$script:UiTextCache = $null
$script:UiRgbCache = @{}
$script:UiDots = [string][char]0x2026
$script:UiMid = [string][char]0x00B7

# --- settings and texts ---------------------------------------------------------------------

function Get-UiValue($Object, [string]$Name, $Default) {
    # A key of a parsed JSON object, or $Default when it is missing (older style files).
    if ($null -eq $Object -or $Object -is [string]) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Get-UiLook([string]$Name, $Default) {
    # A setting of the section "agent" of the active style.
    return (Get-UiValue $script:Ui.look $Name $Default)
}

function Get-UiMark([string]$Name, [string]$Default) {
    # A sign of "agent.marks": answer, thought, corner, turn, stopped, thinking.
    return [string](Get-UiValue (Get-UiLook 'marks' $null) $Name $Default)
}

function Get-UiTexts {
    if ($null -eq $script:UiTextCache) {
        $script:UiTextCache = New-Object PSObject
        try { $script:UiTextCache = Read-StyleJson (Join-Path $script:StyleProjectRoot 'config\unzensiert-texte.json') } catch {}
    }
    return $script:UiTextCache
}

function Get-UiText([string]$Key) {
    # A text of config\unzensiert-texte.json by its path ("notes.stopped"); further arguments
    # fill {0}, {1} ... A missing text shows its path, so nothing breaks.
    $node = Get-UiTexts
    foreach ($part in $Key.Split('.')) {
        $node = Get-UiValue $node $part $null
        if ($null -eq $node) { break }
    }
    if ($null -eq $node) { $node = $Key }
    $text = [string]$node
    if ($args.Count -gt 0) { try { $text = $text -f $args } catch {} }
    return $text
}

function Get-UiCount([double]$N, [string]$Key) {
    # A number with its word from "count" ("1 Zeile", "12 Zeilen").
    $forms = @(Get-UiValue (Get-UiValue (Get-UiTexts) 'count' $null) $Key $null)
    $shown = Format-Number $N 0
    if ($forms.Count -eq 0 -or $null -eq $forms[0]) { return $shown }
    if ($N -eq 1 -or $forms.Count -lt 2) { return ([string]$forms[0] -f $shown) }
    return ([string]$forms[1] -f $shown)
}

function Format-UiDuration([double]$Seconds, [switch]$Coarse) {
    # "2,4 s", "42 s", "3 min 12 s" ("3 min" with -Coarse), "1 h 5 min"
    if ($Seconds -lt 10) { return (Format-Number $Seconds 1) + ' s' }
    if ($Seconds -lt 60) { return ('{0} s' -f [int][Math]::Floor($Seconds)) }
    if ($Coarse -and $Seconds -lt 3600) { return ('{0} min' -f [int][Math]::Round($Seconds / 60)) }
    if ($Seconds -lt 3600) { return ('{0} min {1} s' -f [int][Math]::Floor($Seconds / 60), [int][Math]::Floor($Seconds % 60)) }
    return ('{0} h {1} min' -f [int][Math]::Floor($Seconds / 3600), [int][Math]::Floor(($Seconds % 3600) / 60))
}

function Format-UiElapsed([double]$Seconds) {
    # Whole seconds for the activity line, so the number does not flicker.
    if ($Seconds -lt 60) { return ('{0} s' -f [int][Math]::Floor($Seconds)) }
    return ('{0} min {1:00} s' -f [int][Math]::Floor($Seconds / 60), [int][Math]::Floor($Seconds % 60))
}

function Get-UiWidth {
    # Columns of the window (a fixed number for tests and the design preview).
    if ($script:Ui.fixedWidth -gt 0) { return [int]$script:Ui.fixedWidth }
    try { $w = [Console]::WindowWidth; if ($w -gt 0) { return [Math]::Max(40, $w) } } catch {}
    return 100
}

# --- colours and spans ------------------------------------------------------------------------

function Get-UiRgb([string]$Hex) {
    # "r;g;b" of a colour, cached: the renderers ask for the same colours very often.
    $code = $script:UiRgbCache[$Hex]
    if (-not $code) {
        if ($script:UiRgbCache.Count -gt 4096) { $script:UiRgbCache.Clear() }
        $c = ConvertTo-RgbParts $Hex
        $code = '{0};{1};{2}' -f $c[0], $c[1], $c[2]
        $script:UiRgbCache[$Hex] = $code
    }
    return $code
}

function ConvertTo-UiHex([int[]]$Rgb) {
    return ('#{0:X2}{1:X2}{2:X2}' -f $Rgb[0], $Rgb[1], $Rgb[2])
}

function Get-UiMixHex([string]$A, [string]$B, [double]$T) {
    # $A blended towards $B ($T = 0 gives $A, 1 gives $B).
    return (ConvertTo-UiHex (Get-MixedRgb (ConvertTo-RgbParts $A) (ConvertTo-RgbParts $B) $T))
}

function Get-UiWheelHex([double]$Position) {
    # A colour of the wheel of the style, or the accent in styles without one.
    if ($script:Ui.rainbow) { return (ConvertTo-UiHex (Get-RainbowRgb $Position)) }
    return [string]$script:Ui.mode.accent
}

function Resolve-UiInk([string]$Ink, [double]$Phase = 0) {
    # A colour setting of the style: '#RRGGBB', 'rainbow' (the wheel at $Phase) or 'accent';
    # anything else gives the accent.
    if ($Ink -match '^#[0-9A-Fa-f]{6}$') { return $Ink }
    if ($Ink -eq 'rainbow') { return (Get-UiWheelHex $Phase) }
    return [string]$script:Ui.mode.accent
}

function Format-UiInk([string]$Text, [string]$Hex, [switch]$Bold, [switch]$Italic) {
    if (-not $script:Ui.on -or -not $Hex) { return $Text }
    return (Format-Ink $Text $Hex -Bold:$Bold -Italic:$Italic)
}

function New-UiSpan([string]$Text, [string]$Fg = '', [string]$Attr = '', [string]$Bg = '', [string]$Link = '') {
    # A piece of text with its look: colour, attributes (b bold, i italic, u underline,
    # s strike), background and the address of a link.
    return @{ t = $Text; fg = $Fg; a = $Attr; bg = $Bg; link = $Link }
}

function Format-UiSpans($Spans, [string]$Bg = '') {
    # Spans as terminal text; $Bg is the background of spans without their own. Links are
    # clickable (OSC 8) in Windows Terminal.
    $sb = New-Object System.Text.StringBuilder
    foreach ($s in $Spans) {
        if ($null -eq $s -or -not $s.t) { continue }
        if (-not $script:Ui.on) { $null = $sb.Append($s.t); continue }
        $codes = ''
        if ($s.fg) { $codes += ';38;2;' + (Get-UiRgb $s.fg) }
        $back = $s.bg
        if (-not $back) { $back = $Bg }
        if ($back) { $codes += ';48;2;' + (Get-UiRgb $back) }
        $attr = [string]$s.a
        if ($attr.Contains('b')) { $codes += ';1' }
        if ($attr.Contains('i')) { $codes += ';3' }
        if ($attr.Contains('u')) { $codes += ';4' }
        if ($attr.Contains('s')) { $codes += ';9' }
        $linked = $s.link -and $script:Ui.links
        if ($linked) { $null = $sb.Append($script:Esc + ']8;;' + $s.link + $script:Esc + '\') }
        if ($codes) { $null = $sb.Append($script:Esc + '[' + $codes.Substring(1) + 'm') }
        $null = $sb.Append($s.t)
        if ($codes) { $null = $sb.Append($script:Esc + '[0m') }
        if ($linked) { $null = $sb.Append($script:Esc + ']8;;' + $script:Esc + '\') }
    }
    return $sb.ToString()
}

function Measure-UiText([string]$Text) {
    # Columns a text takes on the screen: without colours and links.
    $plain = $Text -replace ($script:Esc + '\[[0-9;]*m'), ''
    $plain = $plain -replace ($script:Esc + '\]8;;[^' + $script:Esc + ']*' + $script:Esc + '\\'), ''
    return $plain.Length
}

function Limit-UiText([string]$Text, [int]$Max) {
    # Plain text cut to $Max columns with an ellipsis.
    if ($Max -lt 2) { return '' }
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max - 1) + $script:UiDots
}

function Format-UiShimmer([string]$Text, [string]$Ink, [double]$Phase, [switch]$Bold) {
    # A word that seems alive: along the colour wheel moving with $Phase ('rainbow'), or with
    # a light running through it ('shimmer'); any other setting gives one colour.
    if (-not $Text) { return '' }
    $attr = ''
    if ($Bold) { $attr = 'b' }
    $spans = New-Object System.Collections.ArrayList
    if ($Ink -eq 'rainbow' -and $script:Ui.rainbow) {
        $n = [Math]::Max(1, $Text.Length - 1)
        for ($i = 0; $i -lt $Text.Length; $i++) { $null = $spans.Add((New-UiSpan ([string]$Text[$i]) (Get-UiWheelHex ($Phase + 0.45 * $i / $n)) $attr)) }
    } elseif ($Ink -eq 'shimmer' -or $Ink -eq 'rainbow') {
        $mode = $script:Ui.mode
        $pos = (($Phase * 1.7) % 1.0) * ($Text.Length + 8) - 4
        for ($i = 0; $i -lt $Text.Length; $i++) {
            $t = [Math]::Max(0, 1 - [Math]::Abs($i - $pos) / 3.5)
            $null = $spans.Add((New-UiSpan ([string]$Text[$i]) (Get-UiMixHex $mode.accent $mode.foreground $t) $attr))
        }
    } else {
        return (Format-UiSpans @(New-UiSpan $Text (Resolve-UiInk $Ink $Phase) $attr))
    }
    return (Format-UiSpans $spans)
}

function Format-UiRule([int]$Width) {
    # A line across: sprayed in colourful styles ("agent.rule" = spray), else a faint stroke.
    $mode = $script:Ui.mode
    if ([string](Get-UiLook 'rule' 'line') -eq 'spray' -and $script:Ui.rainbow) { return (Format-SprayLine $Width $mode.background) }
    return (Format-UiInk ([string][char]0x2500 * $Width) $mode.faint)
}

function Format-UiTrail([int]$Length) {
    # Characters flying away at the end of a line, in styles that have them.
    if ($Length -le 0 -or -not (Test-ModeTrail $script:Ui.mode)) { return '' }
    return (Format-Trail $Length $script:Ui.mode)
}

function Get-UiSep {
    # The separator between parts of a line, sprayed in colourful styles.
    return ('  ' + (Format-StyleSep $script:Ui.mode) + '  ')
}

# --- start and end ------------------------------------------------------------------------------

function Initialize-AgentUi([bool]$Interactive, [bool]$ShowThinking) {
    $style = Get-StyleConfig
    $mode = Get-StyleMode ([string]$style.claude.localMode)
    $script:Ui = @{
        on = ($Interactive -and -not [Console]::IsOutputRedirected)
        style = $style; mode = $mode; ink = $style.ink; glyphs = $style.glyphs
        look = (Get-UiValue $style 'agent' $null); rainbow = (Test-Rainbow)
        syntax = (Get-UiValue $style.shell 'syntax' $null)
        fixedWidth = 0; wt = [bool]$env:WT_SESSION; links = [bool]$env:WT_SESSION
        showThinking = $ShowThinking; psrl = $false; savedTitle = $null; title = ''; progress = -1
        folder = ''; phase = $script:StyleRandom.NextDouble(); prompts = 0; requests = 0
        # the answer as it streams in (lib\AgentUiMarkdown.ps1)
        line = (New-Object System.Text.StringBuilder); lineStarted = $false; answerStarted = $false; prefix = ''
        inCode = $false; codeLang = ''; codeFence = ''; codeState = ''; inTable = $false; table = $null; extraUp = 0; gap = $false
        thinkChars = 0; thinkClosed = $false; thinkStart = $null; thinkLive = $false
        # the activity line
        act = @{ kind = ''; shown = $false; started = [DateTime]::UtcNow; lastDraw = 0; frame = 0; verb = ''; detail = ''; delayMs = 0; chars = 0 }
        # the running tool and the request (lib\AgentUiTools.ps1)
        toolName = ''; toolStarted = [DateTime]::UtcNow; toolPath = ''; turnFiles = @{}
    }
    if ($script:Ui.on) {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        try { $script:Ui.savedTitle = [Console]::Title } catch {}
    }
}

function Exit-AgentUi {
    # Gives the window its title back and takes the progress mark off the tab.
    if (-not $script:Ui.on) { return }
    Stop-UiActivity
    Set-UiProgress 0
    if ($null -ne $script:Ui.savedTitle) { try { [Console]::Title = $script:Ui.savedTitle } catch {} }
}

function Set-UiTitle([string]$Text) {
    # The title of the window or tab: what Unzensiert is doing, in which folder.
    if (-not $script:Ui.on -or $script:Ui.title -eq $Text) { return }
    $script:Ui.title = $Text
    try { [Console]::Title = $Text } catch {}
}

function Set-UiIdleTitle {
    Set-UiTitle ((Get-UiMark 'turn' '*') + ' Unzensiert ' + $script:UiMid + ' ' + $script:Ui.folder)
}

function Set-UiProgress([int]$State) {
    # The progress mark of Windows Terminal on the tab and in the taskbar (OSC 9;4):
    # 0 none, 2 error (red), 3 busy (moving).
    if (-not $script:Ui.on -or -not $script:Ui.wt -or $script:Ui.progress -eq $State) { return }
    $script:Ui.progress = $State
    [Console]::Write($script:Esc + ']9;4;' + $State + ';0' + [char]7)
}

# --- the activity line ----------------------------------------------------------------------------

function Get-UiVerb {
    # A word of the style for "the model is at work" ("agent.verbs", else claude.spinnerVerbs).
    $verbs = @(Get-UiLook 'verbs' $null)
    if ($verbs.Count -eq 0 -or $null -eq $verbs[0]) { $verbs = @(Get-UiValue $script:Ui.style.claude 'spinnerVerbs' @('Denkt nach')) }
    return [string]$verbs[$script:StyleRandom.Next($verbs.Count)]
}

function Start-UiActivity([string]$Kind, [string]$Detail = '', [int]$DelayMs = 0) {
    # The line at the cursor that shows what is going on while nothing else moves: spinner,
    # what happens, the time so far, "Esc stops". It vanishes as soon as something else is
    # printed. Kinds: model (waiting for the model), think, call (the model writes a tool
    # call), tool, check (closing check), compact, server. Test-UiStop keeps it moving.
    if (-not $script:Ui.on) { return }
    $act = $script:Ui.act
    Clear-UiActivityLine
    $sameRequest = ($act.kind -in 'model', 'think', 'call') -and ($Kind -in 'think', 'call')
    if (-not $sameRequest) { $act.started = [DateTime]::UtcNow; $act.chars = 0 }
    if ($Kind -eq 'model' -or -not $act.verb) { $act.verb = Get-UiVerb }
    $act.kind = $Kind
    $act.detail = $Detail
    $act.delayMs = $DelayMs
    $act.lastDraw = 0
    Set-UiProgress 3
    $what = $act.verb
    if ($Kind -eq 'tool') { $what = $script:Ui.toolName }
    elseif ($Kind -eq 'check') { $what = Get-UiText 'activity.check' }
    elseif ($Kind -eq 'compact') { $what = Get-UiText 'activity.compact' }
    Set-UiTitle ((Get-UiMark 'turn' '*') + ' ' + $what + ' ' + $script:UiDots + ' ' + $script:UiMid + ' ' + $script:Ui.folder)
    Update-UiActivity -Force
}

function Format-UiActivityLine {
    $act = $script:Ui.act
    $mode = $script:Ui.mode
    $frames = @(Get-UiLook 'spinner' @('|', '/', '-', '\'))
    $frame = [string]$frames[$act.frame % $frames.Count]
    $phase = $script:Ui.phase + $act.frame * 0.03
    $spin = Format-UiSpans @(New-UiSpan $frame (Resolve-UiInk ([string](Get-UiLook 'spinnerInk' 'accent')) ($phase * 4)) 'b')
    $verbInk = [string](Get-UiLook 'verbInk' 'accent')
    $secs = ([DateTime]::UtcNow - $act.started).TotalSeconds
    $lead = '  '
    $what = $act.verb
    $parts = @()
    switch ($act.kind) {
        'think' { $parts += (Get-UiText 'activity.think') + ' ' + (Get-UiCount ([int]($act.chars / 4)) 'tokens') }
        'call' { $parts += (Get-UiText 'activity.call' $act.detail) }
        'tool' {
            $lead = '  ' + (Format-UiInk (Get-UiMark 'corner' '|') $mode.faint) + '  '
            $what = Get-UiText 'activity.tool'
        }
        'check' { $what = Get-UiText 'activity.check' }
        'compact' {
            $what = Get-UiText 'activity.compact'
            if ($act.chars -gt 0) { $parts += (Get-UiCount ([int]($act.chars / 4)) 'tokens') }
        }
        'server' { $what = Get-UiText 'activity.server' }
    }
    $line = $lead + $spin + ' ' + (Format-UiShimmer $what $verbInk $phase -Bold) + (Format-UiInk $script:UiDots $mode.dim) + '  ' + (Format-UiInk (Format-UiElapsed $secs) $mode.foreground)
    foreach ($p in $parts) { $line += (Format-UiInk ('  ' + $script:UiMid + '  ' + $p) $mode.dim) }
    $hint = '  ' + $script:UiMid + '  ' + (Get-UiText 'activity.stop')
    $width = Get-UiWidth
    $used = Measure-UiText $line
    if ($used + $hint.Length + 8 -lt $width) { $line += (Format-UiInk $hint $mode.faint) + '  ' + (Format-UiTrail ([int](Get-UiLook 'trail' 0))) }
    elseif ($used -ge $width) { $line = $lead + $spin + ' ' + (Format-UiShimmer (Limit-UiText $what ($width - 20)) $verbInk $phase -Bold) + '  ' + (Format-UiInk (Format-UiElapsed $secs) $mode.foreground) }
    return $line
}

function Update-UiActivity([switch]$Force) {
    # Draws the activity line again, at most ten times a second.
    $act = $script:Ui.act
    if (-not $script:Ui.on -or -not $act.kind) { return }
    $now = [DateTime]::UtcNow
    if (-not $Force -and ($now.Ticks - $act.lastDraw) -lt 1000000) { return }
    if (($now - $act.started).TotalMilliseconds -lt $act.delayMs) { return }
    $act.lastDraw = $now.Ticks
    $act.frame++
    [Console]::Write("`r" + $script:Esc + '[2K' + (Format-UiActivityLine))
    $act.shown = $true
}

function Add-UiActivityChars([int]$Count) {
    # Characters that arrived for the running activity (thinking, a summary).
    if ($script:Ui.on) { $script:Ui.act.chars += $Count }
}

function Clear-UiActivityLine {
    # Takes the activity line off the screen; it comes back with the next update.
    if ($script:Ui.on -and $script:Ui.act.shown) {
        [Console]::Write("`r" + $script:Esc + '[2K')
        $script:Ui.act.shown = $false
    }
}

function Stop-UiActivity {
    if (-not $script:Ui.on) { return }
    Clear-UiActivityLine
    $script:Ui.act.kind = ''
}

function Test-UiStop {
    # Esc or Ctrl+C pressed while the model works? (Ctrl+C reaches us as a key during a
    # request, see TreatControlCAsInput in lib\AgentRepl.ps1.) Every wait asks this about ten
    # times a second, so it also keeps the activity line moving.
    if (-not $script:Ui.on) { return $false }
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Escape) { return $true }
            if ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { return $true }
        }
    } catch {}
    Update-UiActivity
    return $false
}

# --- notes -----------------------------------------------------------------------------------------

function Write-UiNote([string]$Text, [string]$Kind = 'dim') {
    # A line of the program itself: dim, ok, warn or error, with the sign of its kind
    # ("agent.notes"), wrapped at the window edge.
    if (-not $script:Ui.on) {
        if ($Kind -eq 'error') { [Console]::Error.WriteLine($Text) }
        return
    }
    Close-UiThinking
    Complete-UiLine
    Clear-UiActivityLine
    $script:Ui.gap = $false
    $mode = $script:Ui.mode
    $textHex = $mode.dim
    $iconHex = $mode.faint
    if ($Kind -eq 'ok') { $textHex = $mode.foreground; $iconHex = $script:Ui.ink.ok }
    elseif ($Kind -eq 'warn') { $textHex = $script:Ui.ink.warn; $iconHex = $script:Ui.ink.warn }
    elseif ($Kind -eq 'error') { $textHex = $script:Ui.ink.error; $iconHex = $script:Ui.ink.error }
    $icon = [string](Get-UiValue (Get-UiLook 'notes' $null) $Kind '')
    $first = '  '
    if ($icon) { $first = '  ' + (Format-UiSpans @(New-UiSpan $icon $iconHex 'b')) + ' ' }
    $indent = 2
    if ($icon) { $indent = 4 }
    $lines = Format-UiWrapped @(New-UiSpan $Text $textHex) $first (' ' * $indent) $indent (Get-UiWidth)
    [Console]::Write((@($lines) -join "`n") + "`n")
}

function Write-UiHeading([string]$Text) {
    # A small heading inside the conversation: sign, words, a faint line towards the right.
    if (-not $script:Ui.on) { return }
    Clear-UiActivityLine
    $mode = $script:Ui.mode
    $rest = [Math]::Max(4, [Math]::Min(48, (Get-UiWidth) - $Text.Length - 8))
    [Console]::Write("`n " + (Format-UiInk (Get-UiMark 'turn' '*') $mode.accent) + ' ' + (Format-UiShimmer $Text ([string](Get-UiLook 'headingInk' 'accent')) $script:Ui.phase -Bold) + ' ' + (Format-UiInk ([string][char]0x2500 * $rest) $mode.faint) + "`n")
}

function Write-UiRows($Rows, [int]$LabelWidth = 10) {
    # Rows of a small table: @(label, value as terminal text); long values are wrapped
    # under themselves.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    foreach ($row in $Rows) {
        $label = '   ' + (Format-UiInk (([string]$row[0]).PadRight($LabelWidth)) $mode.dim) + ' '
        [Console]::Write($label + [string]$row[1] + "`n")
    }
}

# --- input and status line -------------------------------------------------------------------------

function Save-UiClipboardImage {
    # The image in the clipboard as a PNG file, '' if there is none.
    try {
        Add-Type -AssemblyName System.Drawing
        $img = Get-Clipboard -Format Image -ErrorAction Stop
        if (-not $img) { return '' }
        $dir = Join-Path $env:TEMP 'unzensiert'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $path = Join-Path $dir ('image-' + (Get-Date -Format 'HHmmss-fff') + '.png')
        $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        return $path
    } catch { return '' }
}

function Initialize-UiInput([string]$HistoryFile) {
    # PSReadLine as the line editor, with plain text colours (it would colour the input as
    # PowerShell otherwise). Without it, or without a terminal, input is a plain line.
    $script:Ui.psrl = $false
    if (-not $script:Ui.on -or [Console]::IsInputRedirected) { return }
    try {
        Import-Module PSReadLine -ErrorAction Stop
        Set-PSReadLineOption -HistorySavePath $HistoryFile -HistoryNoDuplicates -BellStyle None
        $plain = $script:Esc + '[39m'
        $colors = @{}
        foreach ($k in 'Command', 'Comment', 'Keyword', 'String', 'Operator', 'Variable', 'Type', 'Number', 'Member', 'Parameter', 'Default') { $colors[$k] = $plain }
        Set-PSReadLineOption -Colors $colors
        Set-PSReadLineKeyHandler -Chord 'Shift+Enter' -Function AddLine
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Enter' -Function AddLine
        Set-PSReadLineKeyHandler -Chord 'Alt+v' -ScriptBlock {
            $p = Save-UiClipboardImage
            if ($p) { [Microsoft.PowerShell.PSConsoleReadLine]::Insert("[image: $p] ") }
        }
        Set-PSReadLineKeyHandler -Chord 'Shift+Tab' -ScriptBlock {
            # the text typed so far goes into the history (Up brings it back), then /mode
            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($line) { [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line); $global:UnzensiertDraft = $true }
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert('/mode')
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
        # the mode switch of Shift+Tab is no input worth keeping
        Set-PSReadLineOption -AddToHistoryHandler { param($line) return ($line -ne '/mode') }
        Set-PSReadLineOption -ContinuationPrompt '  '
        $script:Ui.psrl = $true
    } catch {}
}

function Read-UiLine([string]$Label) {
    # One plain line for a choice; '' without a terminal.
    if (-not $script:Ui.on) { return '' }
    $mode = $script:Ui.mode
    [Console]::Write('   ' + (Format-UiInk ([string][char]0x203A) $mode.accent -Bold) + ' ' + (Format-UiInk ($Label + ': ') $mode.dim))
    $l = [Console]::In.ReadLine()
    if ($null -eq $l) { return '' }
    return $l.Trim()
}

function Read-UiPrompt($Session) {
    # Status line, prompt sign, one input (Enter sends, Shift+Enter starts a new line).
    if (-not $script:Ui.on) { return [Console]::In.ReadLine() }
    Stop-UiActivity
    Set-UiIdleTitle
    if ($global:UnzensiertDraft) {
        $global:UnzensiertDraft = $false
        Write-UiNote (Get-UiText 'notes.draft')
    }
    Write-UiStatus $Session
    $script:Ui.prompts++
    $sign = $script:Ui.glyphs.prompt
    if ($sign -is [array]) { $sign = $sign[$script:StyleRandom.Next($sign.Count)] }
    $hex = Resolve-UiInk ([string](Get-UiLook 'promptInk' 'accent')) ($script:Ui.phase + $script:Ui.prompts / 7.0)
    [Console]::Write((Format-UiInk ([string]$sign) $hex -Bold) + ' ')
    $line = $null
    $read = $false
    if ($script:Ui.psrl) {
        try { $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext); $read = $true }
        catch {
            try { $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $null); $read = $true }
            catch { $script:Ui.psrl = $false }
        }
    }
    if (-not $read) { $line = [Console]::In.ReadLine() }
    if ($line -and $line.Trim()) { Write-UiEcho $line ([string]$sign) $hex }
    return $line
}

function Write-UiEcho([string]$Text, [string]$Sign, [string]$Hex) {
    # Replaces what was just typed by the same text on a tinted bar across the window, so
    # the own messages stand out in a long conversation.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    $lines = $Text.Replace("`r", '').Split("`n")
    $rows = 0
    foreach ($l in $lines) { $rows += [int][Math]::Max(1, [Math]::Ceiling((2 + $l.Length) / [double]$width)) }
    $bg = Get-UiMixHex $Hex $mode.background 0.84
    $out = New-Object System.Collections.ArrayList
    $first = $true
    foreach ($l in $lines) {
        $lead = Format-UiSpans @(New-UiSpan '  ' '' '' $bg)
        if ($first) { $lead = Format-UiSpans @((New-UiSpan $Sign $Hex 'b' $bg), (New-UiSpan ' ' '' '' $bg)) }
        $first = $false
        foreach ($w in (Format-UiWrapped @(New-UiSpan $l $mode.foreground) $lead (Format-UiSpans @(New-UiSpan '  ' '' '' $bg)) 2 $width $bg)) {
            $pad = $width - 1 - (Measure-UiText $w)
            if ($pad -gt 0) { $w += Format-UiSpans @(New-UiSpan (' ' * $pad) '' '' $bg) }
            $null = $out.Add($w)
        }
    }
    [Console]::Write("`r" + $script:Esc + '[' + $rows + 'A' + $script:Esc + '[J' + ($out -join "`n") + "`n")
}

function Get-UiModeInk([string]$Mode) {
    # Colour of a permission mode: ask calm, edits green, all a warning.
    if ($Mode -eq 'all') { return $script:Ui.ink.warn }
    if ($Mode -eq 'edits') { return $script:Ui.ink.ok }
    return $script:Ui.ink.branch
}

function Format-UiContextGauge($Session, [int]$Width) {
    # Gauge and share of the context window in use; yellow from 70 %, red from 85 %.
    $mode = $script:Ui.mode
    $ctx = Get-SessionContextSize $Session
    if ($ctx -le 0) { return '' }
    $used = [math]::Min(1.0, (Get-EstimatedTokens $Session) / [double]$ctx)
    $ink = Get-GaugeInk $mode $mode.accent
    if ($used -ge 0.7) { $ink = $script:Ui.ink.warn }
    if ($used -ge 0.85) { $ink = $script:Ui.ink.error }
    return (Format-Gauge $used $Width $ink $mode.faint) + ' ' + (Format-UiInk ('{0} %' -f [int]($used * 100)) $mode.foreground)
}

function Write-UiStatus($Session) {
    # One line before every input: look and model, how full the context is, the last speed,
    # the rights, the graphics cards, folder and git, the time at the right edge. What does
    # not fit into the window is left out, the least important first.
    $mode = $script:Ui.mode
    $parts = New-Object System.Collections.ArrayList
    $null = $parts.Add(@{ text = (Format-ModeLabel $mode) + '  ' + (Format-UiInk $Session.model $mode.foreground); rank = 100 })
    $gauge = Format-UiContextGauge $Session 8
    if ($gauge) { $null = $parts.Add(@{ text = (Format-UiInk (Get-UiText 'status.context') $mode.dim) + ' ' + $gauge; rank = 90 }) }
    if ($Session.tokensPerSecond -gt 0) { $null = $parts.Add(@{ text = (Format-UiInk ('{0} tok/s' -f [int]$Session.tokensPerSecond) $mode.foreground); rank = 40 }) }
    $null = $parts.Add(@{ text = (Format-UiInk (Get-UiText 'status.rights') $mode.dim) + ' ' + (Format-UiInk $Session.mode (Get-UiModeInk $Session.mode) -Bold); rank = 80 })
    $rank = 30
    try {
        foreach ($gpu in @(Get-GpuReadings)) {
            $fraction = 0
            if ($gpu.totalMiB -gt 0) { $fraction = $gpu.usedMiB / $gpu.totalMiB }
            $null = $parts.Add(@{ text = (Format-UiInk ($gpu.name -replace '^RTX\s+', '') $mode.dim) + ' ' + (Format-Gauge $fraction 6 (Get-GaugeInk $mode $mode.accent) $mode.faint); rank = $rank })
            $rank--
        }
    } catch {}
    $where = Format-UiInk (Split-Path -Leaf $Session.cwd) $mode.foreground
    try {
        $git = Get-GitSummary $Session.cwd
        if ($git) { $where += ' ' + (Format-GitSummary $git $mode.dim) }
    } catch {}
    $null = $parts.Add(@{ text = $where; rank = 60 })
    $clock = (Get-Date).ToString('HH:mm')
    $width = Get-UiWidth
    $sepWidth = 5
    while ($true) {
        $total = 1
        foreach ($p in $parts) { $total += (Measure-UiText $p.text) }
        $total += $sepWidth * ($parts.Count - 1)
        if ($total + $clock.Length + 2 -lt $width -or $parts.Count -le 1) { break }
        $lowest = $parts[0]
        foreach ($p in $parts) { if ($p.rank -lt $lowest.rank) { $lowest = $p } }
        $parts.Remove($lowest)
    }
    $line = ' ' + $parts[0].text
    for ($i = 1; $i -lt $parts.Count; $i++) { $line += (Get-UiSep) + $parts[$i].text }
    $pad = $width - 1 - (Measure-UiText $line) - $clock.Length
    if ($pad -ge 2) { $line += (' ' * $pad) + (Format-UiInk $clock $mode.dim) }
    [Console]::Write("`n" + $line + "`n")
}

# --- welcome -----------------------------------------------------------------------------------------

function Get-UiInstructionNames($Session) {
    # The project instructions of the session as short paths.
    $names = @()
    foreach ($f in @($Session.instructionFiles)) {
        if (-not $f) { continue }
        $names += Get-DisplayPath ([string]$f) $Session.cwd
    }
    return , $names
}

function Get-UiWelcomeRows($Session, $Info, [int]$Width) {
    # The facts of the session for the welcome: model, context, project, cards, rights,
    # rules, server; every value cut to $Width columns.
    $mode = $script:Ui.mode
    $rows = New-Object System.Collections.ArrayList
    $max = [Math]::Max(20, $Width - 13)
    $desc = [string]$Info.description
    $model = Format-UiInk $Session.model $mode.foreground -Bold
    if ($desc) { $model += (Format-UiInk ('  ' + (Limit-UiText $desc ($max - $Session.model.Length - 2))) $mode.dim) }
    $null = $rows.Add(@((Get-UiText 'welcome.model'), $model))
    $ctx = Get-SessionContextSize $Session
    $null = $rows.Add(@((Get-UiText 'welcome.context'), (Format-UiInk (Limit-UiText (Get-UiText 'welcome.contextValue' (Format-Number $ctx 0) ([int](100 * [double]$Info.compactAt))) $max) $mode.foreground)))
    $where = Format-UiInk (Split-Path -Leaf $Session.cwd) $mode.foreground -Bold
    try {
        $git = Get-GitSummary $Session.cwd
        if ($git) { $where += '  ' + (Format-GitSummary $git $mode.dim) }
    } catch {}
    $null = $rows.Add(@((Get-UiText 'welcome.project'), $where))
    try {
        $label = Get-UiText 'welcome.cards'
        foreach ($gpu in @(Get-GpuReadings)) {
            $fraction = 0
            if ($gpu.totalMiB -gt 0) { $fraction = $gpu.usedMiB / $gpu.totalMiB }
            $name = ($gpu.name -replace '^RTX\s+', '').PadRight(8)
            $mem = '{0} / {1} GB' -f (Format-Number ($gpu.usedMiB / 1024) 1), (Format-Number ($gpu.totalMiB / 1024) 1)
            $null = $rows.Add(@($label, ((Format-UiInk $name $mode.foreground) + ' ' + (Format-Gauge $fraction 12 (Get-GaugeInk $mode $mode.accent) $mode.faint) + '  ' + (Format-UiInk $mem $mode.dim))))
            $label = ''
        }
    } catch {}
    $rights = (Format-UiInk $Session.mode (Get-UiModeInk $Session.mode) -Bold) + (Format-UiInk ('  ' + (Limit-UiText (Get-UiText "modes.$($Session.mode)") ($max - 8))) $mode.dim)
    $null = $rows.Add(@((Get-UiText 'welcome.rights'), $rights))
    $names = Get-UiInstructionNames $Session
    if ($names.Count -gt 0) { $rules = Format-UiInk (Limit-UiText ($names -join '  ') $max) $mode.foreground }
    else { $rules = Format-UiInk (Limit-UiText (Get-UiText 'welcome.noRules') $max) $mode.dim }
    $null = $rows.Add(@((Get-UiText 'welcome.rules'), $rules))
    $state = Get-UiText 'welcome.serverDown'
    if ($Info.serverUp) { $state = Get-UiText 'welcome.serverUp' }
    $null = $rows.Add(@((Get-UiText 'welcome.server'), (Format-UiInk (Limit-UiText ("$($Info.server)  $script:UiMid  $state") $max) $mode.dim)))
    if ($Info.continued) { $null = $rows.Add(@('', (Format-UiInk (Limit-UiText ([string]$Info.continued) $max) $script:Ui.ink.ok))) }
    return , $rows
}

function Format-UiWelcomePanel($Session, $Info, [int]$Width) {
    # The right side of the welcome: name and version, date, then the facts.
    $mode = $script:Ui.mode
    $lines = New-Object System.Collections.ArrayList
    $date = (Get-Date).ToString('dddd, d. MMMM', $script:StyleCulture) + '  ' + $script:UiMid + '  ' + (Get-Date).ToString('HH:mm')
    $head = (Format-ModeLabel $mode) + ' ' + (Format-UiInk ([string]$Info.version) $mode.dim)
    $gap = $Width - (Measure-UiText $head) - $date.Length
    if ($gap -ge 3) { $head += (' ' * $gap) + (Format-UiInk $date $mode.dim) }
    $null = $lines.Add($head)
    $null = $lines.Add('')
    foreach ($row in (Get-UiWelcomeRows $Session $Info $Width)) {
        $null = $lines.Add((Format-UiInk (([string]$row[0]).PadRight(9)) $mode.dim) + ' ' + [string]$row[1])
    }
    return , $lines
}

function Write-UiWelcome($Session, $Info) {
    # The start of a session: the picture of the style (agent.bannerText) with the facts of
    # the session beside it - or below it in a narrow window, or under the name in styles
    # without pictures - then a sprayed line, a saying of the style and the keys.
    # $Info: version, server, serverUp, compactAt, description, continued.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    $style = $script:Ui.style
    $width = Get-UiWidth
    $script:Ui.folder = Split-Path -Leaf $Session.cwd
    Set-UiIdleTitle
    $out = New-Object System.Collections.ArrayList
    $null = $out.Add('')
    $artText = [string](Get-UiLook 'bannerText' (Get-UiValue $style.art 'bannerText' ''))
    $artWidth = [int](Get-UiLook 'bannerWidth' 60)
    $art = @()
    $hasArt = $false
    if ($style.PSObject.Properties['art'] -and $artText) { $hasArt = $true }
    if ($hasArt -and $width -ge $artWidth + 52) {
        $canvas = Get-CharArtCells $artText ([int](Get-UiLook 'bannerScale' 2)) $artWidth $mode.background
        if ($null -ne $canvas) { $art = @(Format-ArtCells $canvas 2) }
    }
    if ($art.Count -gt 0) {
        # side by side: the picture left, the facts right, both vertically centred
        $panelWidth = [Math]::Min(78, $width - $artWidth - 4)
        $panel = Format-UiWelcomePanel $Session $Info $panelWidth
        $rows = [Math]::Max($art.Count, $panel.Count)
        $artTop = [int][Math]::Floor(($rows - $art.Count) / 2)
        $panelTop = [int][Math]::Floor(($rows - $panel.Count) / 2)
        for ($r = 0; $r -lt $rows; $r++) {
            $left = ''
            if ($r - $artTop -ge 0 -and $r - $artTop -lt $art.Count) { $left = $art[$r - $artTop] }
            $pad = $artWidth + 2 - (Measure-UiText $left)
            $right = ''
            if ($r - $panelTop -ge 0 -and $r - $panelTop -lt $panel.Count) { $right = $panel[$r - $panelTop] }
            $null = $out.Add($left + (' ' * [Math]::Max(1, $pad)) + $right)
        }
    } else {
        if ($hasArt) { foreach ($l in @(Get-CharArt $artText ([int](Get-UiLook 'bannerScale' 2)) $width $mode.background)) { $null = $out.Add($l) } }
        else {
            $title = [string](Get-UiLook 'title' 'UNZENSIERT')
            $null = $out.Add('  ' + (Format-UiShimmer $title ([string](Get-UiLook 'headingInk' 'accent')) $script:Ui.phase -Bold))
        }
        $null = $out.Add('')
        foreach ($l in (Format-UiWelcomePanel $Session $Info ([Math]::Min(96, $width - 4)))) { $null = $out.Add('  ' + $l) }
    }
    $null = $out.Add('')
    $null = $out.Add('  ' + (Format-UiRule ([Math]::Min(110, $width - 5))))
    $saying = ''
    try { $saying = Get-StyleText 'sprueche' } catch {}
    if ($saying) {
        $quoted = [string][char]0x201E + $saying + [string][char]0x201C
        $null = $out.Add('  ' + (Format-UiTrail 3) + ' ' + (Format-UiShimmer $quoted ([string](Get-UiLook 'headingInk' 'accent')) $script:StyleRandom.NextDouble() -Bold))
    }
    $null = $out.Add('  ' + (Format-UiInk (Limit-UiText (Get-UiText 'welcome.keys') ($width - 4)) $mode.dim))
    [Console]::Write(($out -join "`n") + "`n")
}

# --- one request, the end of the session ----------------------------------------------------------

function Start-UiTurn($Session) {
    # A snapshot before a request of the user, for the line after it.
    $script:Ui.turnFiles = @{}
    $script:Ui.requests++
    if ($script:Ui.on) { Set-UiProgress 3 }
    return @{ at = [DateTime]::UtcNow; turns = $Session.turns; out = $Session.outputTokens }
}

function Complete-UiTurn($Session, $Snap, [string]$Status) {
    # The line after a request: how it ended, how long it took, rounds, changed files,
    # tokens written, speed. The tab shows red after an error until the next input.
    if (-not $script:Ui.on) { return }
    Stop-UiActivity
    Close-UiThinking
    Complete-UiLine
    $mode = $script:Ui.mode
    $secs = ([DateTime]::UtcNow - $Snap.at).TotalSeconds
    $took = Format-UiDuration $secs
    $head = ''
    switch ($Status) {
        'done' {
            $verbs = @(Get-UiLook 'doneVerbs' @('Fertig'))
            $verb = [string]$verbs[$script:StyleRandom.Next($verbs.Count)]
            $head = (Format-UiInk (Get-UiMark 'turn' '*') (Get-UiWheelHex $script:StyleRandom.NextDouble()) -Bold) + ' ' + (Format-UiShimmer (Get-UiText 'turn.done' $verb $took) ([string](Get-UiLook 'headingInk' 'accent')) $script:StyleRandom.NextDouble())
        }
        'stopped' { $head = (Format-UiInk ((Get-UiMark 'stopped' '#') + ' ' + (Get-UiText 'turn.stopped' $took)) $script:Ui.ink.warn -Bold) }
        default {
            $key = 'turn.error'
            if ($Status -eq 'loop') { $key = 'turn.loop' } elseif ($Status -eq 'limit') { $key = 'turn.limit' }
            $head = (Format-UiInk ([string](Get-UiValue (Get-UiLook 'notes' $null) 'error' 'x') + ' ' + (Get-UiText $key $took)) $script:Ui.ink.error -Bold)
        }
    }
    $parts = @()
    $rounds = $Session.turns - $Snap.turns
    if ($rounds -gt 0) { $parts += (Get-UiCount $rounds 'rounds') }
    if ($script:Ui.turnFiles.Count -gt 0) { $parts += (Get-UiCount $script:Ui.turnFiles.Count 'changed') }
    $written = $Session.outputTokens - $Snap.out
    if ($written -gt 0) { $parts += (Get-UiCount $written 'tokens') }
    if ($Session.tokensPerSecond -gt 0 -and $written -gt 0) { $parts += (Get-UiText 'turn.speed' ([int]$Session.tokensPerSecond)) }
    $line = '  ' + $head
    if ($parts.Count -gt 0) { $line += (Format-UiInk ('  ' + $script:UiMid + '  ' + ($parts -join ('  ' + $script:UiMid + '  '))) $mode.dim) }
    if ((Measure-UiText $line) + 8 -lt (Get-UiWidth)) { $line += '  ' + (Format-UiTrail ([int](Get-UiLook 'trail' 0))) }
    [Console]::Write("`n" + $line + "`n")
    $script:Ui.gap = $false
    if ($Status -in 'error', 'loop', 'limit') { Set-UiProgress 2 } else { Set-UiProgress 0 }
    Set-UiIdleTitle
}

function Write-UiFarewell($Session, [datetime]$Started, [string]$Closing) {
    # The end of a session: a sprayed line, how long it lasted, what happened in it, and what
    # became of the models ($Closing, from Complete-AgentSession).
    if (-not $script:Ui.on) { return }
    Stop-UiActivity
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    $took = Format-UiDuration ((Get-Date) - $Started).TotalSeconds -Coarse
    $text = ''
    if ($script:Ui.style.texts.PSObject.Properties['farewell']) { $text = Get-StyleText 'farewell' }
    if (-not $text) { $text = Get-UiText 'farewell.default' }
    $text = $text -f $took
    $out = @('', ('  ' + (Format-UiRule ([Math]::Min(60, $width - 5)))))
    $out += ' ' + (Format-UiInk (Get-UiMark 'turn' '*') $mode.accent) + ' ' + (Format-UiShimmer $text ([string](Get-UiLook 'headingInk' 'accent')) $script:StyleRandom.NextDouble()) + '  ' + (Format-UiTrail 6)
    if ($script:Ui.requests -gt 0) {
        $read = $Session.inputTokens + $Session.cachedTokens
        $stats = Get-UiText 'farewell.stats' (Get-UiCount $script:Ui.requests 'requests') (Get-UiCount $Session.turns 'rounds') (Format-Number $read 0) (Format-Number $Session.cachedTokens 0) (Get-UiCount $Session.outputTokens 'tokens')
        $out += '   ' + (Format-UiInk (Limit-UiText $stats ($width - 4)) $mode.dim)
        if ($Session.changed.Count -gt 0) {
            $names = @($Session.changed | ForEach-Object { Get-DisplayPath ([string]$_) $Session.cwd })
            $out += '   ' + (Format-UiInk (Get-UiCount $names.Count 'changed') $mode.foreground) + (Format-UiInk ('  ' + (Limit-UiText ($names -join '  ') ($width - 30))) $mode.dim)
        }
    }
    if ($Closing) { $out += '   ' + (Format-UiInk (Limit-UiText $Closing ($width - 4)) $mode.faint) }
    $out += ''
    [Console]::Write(($out -join "`n") + "`n")
}

# --- overviews: /help, /status, /model, /resume ------------------------------------------------------

function Show-UiHelp($Commands) {
    # Keys, commands and the fixed flows of config\<pluginDir>\commands\, in three groups.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    $groups = @(
        @((Get-UiText 'help.keysTitle'), @(Get-UiValue (Get-UiTexts).help 'keys' @())),
        @((Get-UiText 'help.commandsTitle'), @(Get-UiValue (Get-UiTexts).help 'commands' @()))
    )
    $flows = @()
    foreach ($k in ($Commands.Keys | Sort-Object)) { $flows += , @("/$k", [string]$Commands[$k].description) }
    if ($flows.Count -gt 0) { $groups += , @((Get-UiText 'help.flowsTitle'), $flows) }
    $width = Get-UiWidth
    $i = 0
    foreach ($g in $groups) {
        Write-UiHeading ([string]$g[0])
        foreach ($row in @($g[1])) {
            $key = [string]$row[0]
            $hex = Get-UiWheelHex ($script:Ui.phase + 0.11 * $i)
            $i++
            $first = '   ' + (Format-UiInk ($key.PadRight(13)) $hex -Bold) + ' '
            $lines = Format-UiWrapped @(New-UiSpan ([string]$row[1]) $mode.foreground) $first (' ' * 17) 17 $width
            [Console]::Write((@($lines) -join "`n") + "`n")
        }
    }
}

function Show-UiStatus($Session, $Info) {
    # /status: version, model, context with its gauge, the numbers of the session, speed,
    # rights, what is allowed, project instructions, changed files, the conversation file.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    $max = [Math]::Max(20, $width - 18)
    $ctx = Get-SessionContextSize $Session
    $used = Get-EstimatedTokens $Session
    Write-UiHeading (Get-UiText 'statusPanel.title')
    $rows = @(
        @((Get-UiText 'statusPanel.version'), (Format-UiInk ('Unzensiert ' + [string]$Info.version) $mode.foreground)),
        @((Get-UiText 'statusPanel.model'), ((Format-UiInk $Session.model $mode.foreground -Bold) + (Format-UiInk ('  ' + [string]$Info.server) $mode.dim))),
        @((Get-UiText 'statusPanel.context'), ((Format-UiContextGauge $Session 24) + (Format-UiInk ('  ' + (Get-UiText 'statusPanel.contextValue' (Format-Number $used 0) (Format-Number $ctx 0) ([int](100 * [double]$Info.compactAt)))) $mode.dim)))
    )
    $numbers = Get-UiText 'statusPanel.sessionValue' (Get-UiCount $Session.turns 'rounds') (Format-Number $Session.inputTokens 0) (Format-Number $Session.cachedTokens 0) (Format-Number $Session.outputTokens 0)
    $rows += , @((Get-UiText 'statusPanel.session'), (Format-UiInk (Limit-UiText $numbers $max) $mode.foreground))
    if ($Session.tokensPerSecond -gt 0) { $rows += , @((Get-UiText 'statusPanel.speed'), (Format-UiInk ('{0} tok/s' -f [int]$Session.tokensPerSecond) $mode.foreground)) }
    $rows += , @((Get-UiText 'statusPanel.rights'), ((Format-UiInk $Session.mode (Get-UiModeInk $Session.mode) -Bold) + (Format-UiInk ('  ' + (Get-UiText "modes.$($Session.mode)")) $mode.dim)))
    $allowed = @(@($Session.allowedTools) + @($Session.allowed.Keys) | Where-Object { $_ })
    if ($allowed.Count -gt 0) { $rows += , @((Get-UiText 'statusPanel.allowed'), (Format-UiInk (Limit-UiText ($allowed -join '  ') $max) $mode.foreground)) }
    else { $rows += , @((Get-UiText 'statusPanel.allowed'), (Format-UiInk (Get-UiText 'statusPanel.nothingAllowed') $mode.dim)) }
    $names = Get-UiInstructionNames $Session
    if ($names.Count -gt 0) { $rows += , @((Get-UiText 'statusPanel.rules'), (Format-UiInk (Limit-UiText ($names -join '  ') $max) $mode.foreground)) }
    if ($Session.changed.Count -gt 0) {
        $changed = @($Session.changed | ForEach-Object { Get-DisplayPath ([string]$_) $Session.cwd })
        $rows += , @((Get-UiText 'statusPanel.changed'), ((Format-UiInk (Get-UiCount $changed.Count 'files') $mode.foreground) + (Format-UiInk ('  ' + (Limit-UiText ($changed -join '  ') ($max - 12))) $mode.dim)))
    }
    $rows += , @((Get-UiText 'statusPanel.file'), (Format-UiInk (Limit-UiText ([string]$Session.file) $max) $mode.faint))
    Write-UiRows $rows 11
}

function Show-UiModelList($Rows, [string]$Current) {
    # /model: the models of the picker with number, name and description; the current one
    # carries the mark of the style.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    Write-UiHeading (Get-UiText 'modelPanel.title')
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $r = $Rows[$i]
        $isCurrent = ([string]$r.model -eq $Current)
        $mark = '  '
        $hex = $mode.foreground
        if ($isCurrent) { $mark = (Format-UiInk (Get-UiMark 'answer' '*') $mode.accent -Bold) + ' '; $hex = $mode.accent }
        $desc = [string]$r.description -replace ('^' + [regex]::Escape([string]$r.model) + ':\s*'), ''
        $line = '   ' + $mark + (Format-UiInk ('{0}' -f ($i + 1)) $mode.dim) + '  ' + (Format-UiInk (([string]$r.label).PadRight(12)) $hex -Bold) + ' ' + (Format-UiInk (([string]$r.model).PadRight(14)) $mode.foreground) + (Format-UiInk (Limit-UiText $desc ($width - 40)) $mode.dim)
        [Console]::Write($line + "`n")
    }
}

function Show-UiSessionList($Files) {
    # /resume: the earlier conversations of this folder, newest first.
    if (-not $script:Ui.on) { return }
    $mode = $script:Ui.mode
    $width = Get-UiWidth
    Write-UiHeading (Get-UiText 'resumePanel.title')
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $f = $Files[$i]
        $line = '   ' + (Format-UiInk ('{0,3}' -f ($i + 1)) $mode.accent -Bold) + '  ' + (Format-UiInk $f.time.ToString('ddd dd.MM. HH:mm', $script:StyleCulture) $mode.dim) + '  ' + (Format-UiInk (Limit-UiText ([string]$f.title) ($width - 28)) $mode.foreground)
        [Console]::Write($line + "`n")
    }
}
