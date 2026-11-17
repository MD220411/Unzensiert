# The terminal of the agent Unzensiert, in the colours of the active look (config\style.json,
# lib\Style.ps1): the answer as it streams in (with a little Markdown), the thinking as a
# running count, tool calls with their result and the lines an edit changed, yes/no
# questions, the input line (PSReadLine: history, several lines, Alt+V pastes an image,
# Shift+Tab switches the mode) and the status line above it. Without a terminal (-p) it
# prints nothing. Needs lib\Style.ps1. Keep this file ASCII-only.

$script:Ui = @{ on = $false }
$script:Esc = [string][char]27
$script:Glyph = @{
    dot = [string][char]0x25CF; corner = [string][char]0x23BF; dots = [string][char]0x2026
    since = [string][char]0x2234; bullet = [string][char]0x2022; bar = [string][char]0x2502
    spin = @([string][char]0x25D0, [string][char]0x25D3, [string][char]0x25D1, [string][char]0x25D2)
}

function Initialize-AgentUi([bool]$Interactive, [bool]$ShowThinking) {
    $style = Get-StyleConfig
    $mode = Get-StyleMode ([string]$style.claude.localMode)
    $script:Ui = @{
        on = ($Interactive -and -not [Console]::IsOutputRedirected)
        mode = $mode; ink = $style.ink; glyphs = $style.glyphs
        line = (New-Object System.Text.StringBuilder); lineStarted = $false
        inCode = $false; answerStarted = $false; showThinking = $ShowThinking
        thinkChars = 0; thinkClosed = $false; spinAt = [datetime]::MinValue; spinIndex = 0
        width = 100; psrl = $false
    }
    try { $script:Ui.width = [math]::Max(40, [Console]::WindowWidth) } catch {}
    if ($script:Ui.on) { try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {} }
}

function Format-UiInk([string]$Text, [string]$Hex, [switch]$Bold, [switch]$Italic) {
    if (-not $script:Ui.on -or -not $Hex) { return $Text }
    return (Format-Ink $Text $Hex -Bold:$Bold -Italic:$Italic)
}

function Write-UiRaw([string]$Text) {
    if ($script:Ui.on) { [Console]::Write($Text) }
}

function Get-UiClearLine { return "`r" + $script:Esc + '[2K' }

function Write-UiNote([string]$Text, [string]$Kind = 'dim') {
    # A line of the program itself: dim, warn, error or ok.
    if (-not $script:Ui.on) {
        if ($Kind -eq 'error') { [Console]::Error.WriteLine($Text) }
        return
    }
    Close-UiThinking
    Complete-UiLine
    $hex = $script:Ui.mode.dim
    if ($Kind -eq 'warn') { $hex = $script:Ui.ink.warn }
    elseif ($Kind -eq 'error') { $hex = $script:Ui.ink.error }
    elseif ($Kind -eq 'ok') { $hex = $script:Ui.ink.ok }
    [Console]::Write('  ' + (Format-UiInk $Text $hex) + "`n")
}

# --- the answer -------------------------------------------------------------------------------

function Start-UiAnswer {
    $script:Ui.answerStarted = $false
    $script:Ui.thinkChars = 0
    $script:Ui.thinkClosed = $false
    $script:Ui.inCode = $false
    $null = $script:Ui.line.Clear()
    $script:Ui.lineStarted = $false
}

function Add-UiReasoning([string]$Text) {
    if (-not $script:Ui.on) { return }
    $script:Ui.thinkChars += $Text.Length
    if ($script:Ui.showThinking) {
        [Console]::Write((Format-UiInk $Text $script:Ui.mode.dim -Italic))
        return
    }
    $now = Get-Date
    if (($now - $script:Ui.spinAt).TotalMilliseconds -lt 150) { return }
    $script:Ui.spinAt = $now
    $script:Ui.spinIndex = ($script:Ui.spinIndex + 1) % $script:Glyph.spin.Count
    $tokens = [int]($script:Ui.thinkChars / 4)
    [Console]::Write((Get-UiClearLine) + '  ' + (Format-UiInk ($script:Glyph.spin[$script:Ui.spinIndex] + ' thinking' + $script:Glyph.dots + ' ' + $tokens + ' tokens') $script:Ui.mode.dim))
}

function Close-UiThinking {
    # Replaces the running count by one quiet line once the model starts to answer.
    if (-not $script:Ui.on -or $script:Ui.thinkChars -eq 0 -or $script:Ui.thinkClosed) { return }
    $script:Ui.thinkClosed = $true
    if ($script:Ui.showThinking) { [Console]::Write("`n"); return }
    [Console]::Write((Get-UiClearLine) + '  ' + (Format-UiInk ($script:Glyph.since + ' thought for about ' + [int]($script:Ui.thinkChars / 4) + ' tokens') $script:Ui.mode.dim) + "`n")
}

function Format-UiMarkdown([string]$Raw) {
    # A little Markdown for the terminal: code blocks, headings, lists, `code`, **bold**.
    $mode = $script:Ui.mode
    $codeHex = $script:Ui.ink.branch
    if ($Raw.TrimStart().StartsWith('```')) {
        $script:Ui.inCode = -not $script:Ui.inCode
        return (Format-UiInk $Raw $mode.faint)
    }
    if ($script:Ui.inCode) { return (Format-UiInk $script:Glyph.bar $mode.faint) + ' ' + (Format-UiInk $Raw $codeHex) }
    if ($Raw -match '^\s*#{1,6}\s+(.*)$') { return (Format-UiInk $Matches[1] $mode.accent -Bold) }
    $line = $Raw
    if ($line -match '^(\s*)[-*]\s+(.*)$') { $line = $Matches[1] + (Format-UiInk $script:Glyph.bullet $mode.accent) + ' ' + $Matches[2] }
    $line = [regex]::Replace($line, '`([^`]+)`', { param($m) Format-UiInk $m.Groups[1].Value $codeHex })
    $line = [regex]::Replace($line, '\*\*([^*]+)\*\*', { param($m) Format-UiInk $m.Groups[1].Value $mode.foreground -Bold })
    return $line
}

function Get-UiPrefix {
    # The first line of an answer starts with a dot, the others are indented.
    if (-not $script:Ui.answerStarted) {
        $script:Ui.answerStarted = $true
        return (Format-UiInk $script:Glyph.dot $script:Ui.mode.accent) + ' '
    }
    return '  '
}

function Add-UiContent([string]$Text) {
    # Prints the answer as it arrives; a finished line is printed again with its Markdown.
    if (-not $script:Ui.on) { return }
    Close-UiThinking
    $parts = $Text.Split("`n")
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $seg = $parts[$i].TrimEnd("`r")
        if ($seg) {
            if (-not $script:Ui.lineStarted) {
                $script:Ui.lineStarted = $true
                $script:Ui.prefix = Get-UiPrefix
                [Console]::Write($script:Ui.prefix)
            }
            $null = $script:Ui.line.Append($seg)
            [Console]::Write($seg)
        }
        if ($i -lt $parts.Count - 1) { Complete-UiLine -Force }
    }
}

function Complete-UiLine([switch]$Force) {
    # Ends the current line of the answer; a line that fit on one row is shown formatted.
    if (-not $script:Ui.on) { return }
    if (-not $script:Ui.lineStarted) {
        if ($Force -and $script:Ui.answerStarted) { [Console]::Write("`n") }
        return
    }
    $raw = $script:Ui.line.ToString()
    $null = $script:Ui.line.Clear()
    $script:Ui.lineStarted = $false
    $formatted = Format-UiMarkdown $raw
    if ($raw.Length + 2 -lt $script:Ui.width) { [Console]::Write((Get-UiClearLine) + $script:Ui.prefix + $formatted + "`n") }
    else { [Console]::Write("`n") }
}

function Complete-UiAnswer {
    Close-UiThinking
    Complete-UiLine
}

# --- tools ------------------------------------------------------------------------------------

function Get-UiToolLabel([string]$Name, $A, [string]$Cwd) {
    if ($null -eq $A) { return '' }
    $label = ''
    switch ($Name) {
        { $_ -eq 'Bash' -or $_ -eq 'PowerShell' } { $label = ([string](Get-DictValue $A 'command')).Split("`n")[0] }
        { $_ -eq 'Read' -or $_ -eq 'Edit' -or $_ -eq 'Write' } { $label = Get-DisplayPath (Resolve-AgentPath (Get-DictValue $A 'file_path') $Cwd) $Cwd }
        'Glob' { $label = [string](Get-DictValue $A 'pattern') }
        'Grep' {
            $label = [string](Get-DictValue $A 'pattern')
            $p = [string](Get-DictValue $A 'path')
            if ($p) { $label += "  in $p" }
        }
    }
    $max = $script:Ui.width - $Name.Length - 8
    if ($label.Length -gt $max) { $label = $label.Substring(0, [math]::Max(10, $max)) + $script:Glyph.dots }
    return $label
}

function Write-UiToolStart([string]$Name, $A, [string]$Cwd) {
    if (-not $script:Ui.on) { return }
    Close-UiThinking
    Complete-UiLine
    $label = ''
    try { $label = Get-UiToolLabel $Name $A $Cwd } catch {}
    [Console]::Write("`n" + (Format-UiInk $script:Glyph.dot $script:Ui.mode.accent) + ' ' + (Format-UiInk $Name $script:Ui.mode.foreground -Bold) + ' ' + (Format-UiInk $label $script:Ui.mode.dim) + "`n")
}

function Write-UiToolResult($Result, [string]$Name) {
    if (-not $script:Ui.on) { return }
    $corner = '  ' + (Format-UiInk $script:Glyph.corner $script:Ui.mode.faint) + '  '
    if ($Result.error) {
        $first = @(([string]$Result.text).Split("`n") | Where-Object { $_.Trim() } | Select-Object -First 3)
        foreach ($l in $first) { [Console]::Write($corner + (Format-UiInk $l $script:Ui.ink.error) + "`n"); $corner = '     ' }
        return
    }
    if ($Result.diff) {
        [Console]::Write($corner + (Format-UiInk "changed at line $($Result.diff.line)" $script:Ui.mode.dim) + "`n")
        $old = @($Result.diff.old.Split("`n"))
        $new = @($Result.diff.new.Split("`n"))
        foreach ($l in ($old | Select-Object -First 12)) { [Console]::Write('     ' + (Format-UiInk "- $l" $script:Ui.ink.error) + "`n") }
        if ($old.Count -gt 12) { [Console]::Write('     ' + (Format-UiInk "  $($script:Glyph.dots) $($old.Count - 12) more" $script:Ui.mode.dim) + "`n") }
        foreach ($l in ($new | Select-Object -First 12)) { [Console]::Write('     ' + (Format-UiInk "+ $l" $script:Ui.ink.ok) + "`n") }
        if ($new.Count -gt 12) { [Console]::Write('     ' + (Format-UiInk "  $($script:Glyph.dots) $($new.Count - 12) more" $script:Ui.mode.dim) + "`n") }
        return
    }
    if ($Name -eq 'Bash' -or $Name -eq 'PowerShell') {
        $lines = @(([string]$Result.text).Split("`n") | Where-Object { $_ -ne '' })
        $show = @($lines | Select-Object -First 6)
        foreach ($l in $show) {
            if ($l.Length -gt $script:Ui.width - 8) { $l = $l.Substring(0, $script:Ui.width - 8) + $script:Glyph.dots }
            [Console]::Write($corner + (Format-UiInk $l $script:Ui.mode.dim) + "`n")
            $corner = '     '
        }
        if ($lines.Count -gt 6) { [Console]::Write('     ' + (Format-UiInk "$($script:Glyph.dots) $($lines.Count - 6) more lines" $script:Ui.mode.faint) + "`n") }
        return
    }
    $summary = [string]$Result.summary
    if (-not $summary) { $summary = ([string]$Result.text).Split("`n")[0] }
    [Console]::Write($corner + (Format-UiInk $summary $script:Ui.mode.dim) + "`n")
}

function Read-UiPermission([string]$Name, [string]$Subject, [string]$Why, [bool]$CanAlways) {
    # Asks before a call runs: yes, always (this session), or no. One key, no Enter.
    $warn = $script:Ui.ink.warn
    $line = "  ? Allow $Name"
    if ($Why) { $line += " - $Why" }
    [Console]::Write((Format-UiInk $line $warn -Bold) + "`n")
    if ($Subject) {
        $lines = @($Subject.Replace("`r", '').Split("`n"))
        $n = 0
        foreach ($l in $lines) {
            if (++$n -gt 30) { [Console]::Write('    ' + (Format-UiInk "$($script:Glyph.dots) $($lines.Count - 30) more lines" $script:Ui.mode.dim) + "`n"); break }
            if ($l.Length -gt $script:Ui.width - 6) { $l = $l.Substring(0, $script:Ui.width - 6) + $script:Glyph.dots }
            $hex = $script:Ui.mode.foreground
            if ($l.StartsWith('- ')) { $hex = $script:Ui.ink.error } elseif ($l.StartsWith('+ ')) { $hex = $script:Ui.ink.ok }
            [Console]::Write('    ' + (Format-UiInk $l $hex) + "`n")
        }
    }
    $choices = '    [y] yes   [n] no'
    if ($CanAlways) { $choices = '    [y] yes   [a] always in this session   [n] no' }
    [Console]::Write((Format-UiInk $choices $script:Ui.mode.dim) + ' ')
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [string]$k.KeyChar
        if ($k.Key -eq [ConsoleKey]::Enter -or $c -eq 'y' -or $c -eq 'j') { [Console]::Write((Format-UiInk 'yes' $script:Ui.ink.ok) + "`n"); return 'yes' }
        if ($CanAlways -and ($c -eq 'a' -or $c -eq 'i')) { [Console]::Write((Format-UiInk 'always' $script:Ui.ink.ok) + "`n"); return 'always' }
        if ($k.Key -eq [ConsoleKey]::Escape -or $c -eq 'n') { [Console]::Write((Format-UiInk 'no' $script:Ui.ink.error) + "`n"); return 'no' }
    }
}

function Test-UiStop {
    # Esc or Ctrl+C pressed while the model works? (Ctrl+C reaches us as a key during a
    # request, see TreatControlCAsInput in lib\AgentLoop.ps1.)
    if (-not $script:Ui.on) { return $false }
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Escape) { return $true }
            if ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { return $true }
        }
    } catch {}
    return $false
}

# --- input and status line ----------------------------------------------------------------------

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
    [Console]::Write('  ' + (Format-UiInk ($Label + ': ') $script:Ui.mode.dim))
    $l = [Console]::In.ReadLine()
    if ($null -eq $l) { return '' }
    return $l.Trim()
}

function Read-UiPrompt($Session) {
    # Status line, prompt sign, one input (Enter sends, Shift+Enter starts a new line).
    if (-not $script:Ui.on) { return [Console]::In.ReadLine() }
    if ($global:UnzensiertDraft) {
        $global:UnzensiertDraft = $false
        Write-UiNote 'your text is in the history: Up brings it back'
    }
    Write-UiStatus $Session
    $sign = $script:Ui.glyphs.prompt
    if ($sign -is [array]) { $sign = $sign[(Get-Random -Maximum $sign.Count)] }
    [Console]::Write((Format-UiInk ([string]$sign + ' ') $script:Ui.mode.accent -Bold))
    if ($script:Ui.psrl) {
        try { return [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext) }
        catch {
            try { return [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $null) }
            catch { $script:Ui.psrl = $false }
        }
    }
    return [Console]::In.ReadLine()
}

function Write-UiStatus($Session) {
    # One line before every input: look and model, how full the context is, the last speed,
    # the mode, the graphics cards, folder and git.
    $mode = $script:Ui.mode
    $parts = @((Format-ModeLabel $mode) + '  ' + (Format-UiInk $Session.model $mode.foreground))
    $ctx = Get-ModelContextSize $Session.model
    if ($ctx -gt 0) {
        $used = [math]::Min(1.0, (Get-EstimatedTokens $Session) / [double]$ctx)
        $ink = Get-GaugeInk $mode $mode.accent
        if ($used -ge 0.7) { $ink = $script:Ui.ink.warn }
        if ($used -ge 0.85) { $ink = $script:Ui.ink.error }
        $parts += (Format-UiInk 'context' $mode.dim) + ' ' + (Format-Gauge $used 8 $ink $mode.faint) + ' ' + (Format-UiInk ('{0} %' -f [int]($used * 100)) $mode.foreground)
    }
    if ($Session.tokensPerSecond -gt 0) { $parts += (Format-UiInk ('{0} tok/s' -f [int]$Session.tokensPerSecond) $mode.foreground) }
    $modeInk = $mode.dim
    if ($Session.mode -eq 'all') { $modeInk = $script:Ui.ink.warn }
    $parts += (Format-UiInk "mode $($Session.mode)" $modeInk)
    try {
        foreach ($gpu in @(Get-GpuReadings)) {
            $fraction = 0
            if ($gpu.totalMiB -gt 0) { $fraction = $gpu.usedMiB / $gpu.totalMiB }
            $parts += (Format-UiInk ($gpu.name -replace '^RTX\s+', '') $mode.dim) + ' ' + (Format-Gauge $fraction 6 (Get-GaugeInk $mode $mode.accent) $mode.faint)
        }
    } catch {}
    $where = Format-UiInk (Split-Path -Leaf $Session.cwd) $mode.foreground
    try {
        $git = Get-GitSummary $Session.cwd
        if ($git) { $where += ' ' + (Format-GitSummary $git $mode.dim) }
    } catch {}
    $parts += $where
    $line = ' ' + $parts[0]
    for ($i = 1; $i -lt $parts.Count; $i++) { $line += '  ' + (Format-StyleSep $mode) + '  ' + $parts[$i] }
    [Console]::Write("`n" + $line + "`n")
}
