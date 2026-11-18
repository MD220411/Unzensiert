# Building blocks of the look (docs\style.md): reads the active style, turns colours into
# terminal escape sequences, mixes the colour wheel of colourful styles, tints the terminal
# per mode and takes the readings that the prompt, the greeting and the status line show
# (graphics cards, git, llama-server). Pictures made of characters: lib\CharArt.ps1.
#
# Which style is active says config\style.json ("active"); the styles themselves live in
# config\styles\<name>.json (breakout, nightshift, ...).
#
# Self-contained on purpose: the interactive shell and the status line of Claude Code load
# only this file (and CharArt.ps1). They must start fast, and $ErrorActionPreference =
# 'Stop' from _common.ps1 must not leak into an interactive shell.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI. All
# non-ASCII characters (glyphs, texts with typographic signs) therefore live in the style files.

$script:StyleProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:StyleSelectionCache = $null
$script:StyleConfigCache = $null
$script:StyleRainbowCache = $null
$script:StyleRandom = New-Object System.Random
$script:StyleEsc = [string][char]27
$script:StyleReset = $script:StyleEsc + '[0m'
$script:StyleCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

. "$PSScriptRoot\CharArt.ps1"

# --- configuration ------------------------------------------------------------------

function Read-StyleJson([string]$Path) {
    # ReadAllText decodes UTF-8 reliably (Get-Content of PS 5.1 would guess ANSI).
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-StyleSelection {
    # config\style.json: the active style and what all styles share (profile GUID,
    # mode variable, backup suffix). Read once per process.
    if (-not $script:StyleSelectionCache) {
        $script:StyleSelectionCache = Read-StyleJson (Join-Path $script:StyleProjectRoot 'config\style.json')
    }
    return $script:StyleSelectionCache
}

function Get-StyleFile([string]$Name) {
    return (Join-Path $script:StyleProjectRoot ("config\styles\{0}.json" -f $Name))
}

function Get-StyleConfig {
    # The active style, config\styles\<active>.json, read once per process.
    if (-not $script:StyleConfigCache) {
        $name = [string](Get-StyleSelection).active
        $path = Get-StyleFile $name
        if (-not (Test-Path $path)) { throw "Style '$name' (config\style.json) has no file $path." }
        $script:StyleConfigCache = Read-StyleJson $path
    }
    return $script:StyleConfigCache
}

function Get-KnownStyles {
    # Every style in config\styles\, parsed: Install-Style.ps1 removes the entries of all
    # of them before it writes the active one, so a switch leaves nothing behind.
    $dir = Join-Path $script:StyleProjectRoot 'config\styles'
    return @(Get-ChildItem -Path $dir -Filter '*.json' | Sort-Object Name | ForEach-Object { Read-StyleJson $_.FullName })
}

function Get-ShellModeName {
    # The mode of the plain shell ("shell.mode"); older style files had no key for it.
    $mode = [string](Get-StyleConfig).shell.mode
    if (-not $mode) { $mode = 'workbench' }
    return $mode
}

function Get-StyleMode([string]$Name) {
    # One entry of "modes"; unknown names fall back to the mode of the shell.
    $modes = (Get-StyleConfig).modes
    $entry = $modes.PSObject.Properties[$Name]
    if ($entry -and $entry.Value -isnot [string]) { return $entry.Value }
    return $modes.PSObject.Properties[(Get-ShellModeName)].Value
}

function Get-StyleGlyph([string]$Name) {
    # A glyph from "glyphs". A list means: a different one each time.
    $value = (Get-StyleConfig).glyphs.$Name
    if ($value -is [array]) { return [string]$value[$script:StyleRandom.Next($value.Count)] }
    return [string]$value
}

function Get-ClaudeThemeSlug([string]$ModeName, $Style = $null) {
    # Name of the Claude Code theme file (without .json) that belongs to a mode.
    if (-not $Style) { $Style = Get-StyleConfig }
    return ([string]$Style.claude.themePrefix) + $ModeName
}

function Get-ClaudeThemeFile([string]$ModeName, $Style = $null) {
    return (Join-Path $env:USERPROFILE (".claude\themes\{0}.json" -f (Get-ClaudeThemeSlug $ModeName $Style)))
}

function Test-FontInstalled([string]$Face) {
    # True if Windows knows a font family of this name (system-wide or for this user).
    Add-Type -AssemblyName System.Drawing
    $families = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
    return ($families -contains $Face)
}

# --- colours --------------------------------------------------------------------------

function ConvertTo-RgbParts([string]$Hex) {
    $h = $Hex.TrimStart('#')
    return @(
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16)
    )
}

function Get-RgbCode([int[]]$Rgb, [switch]$Bold) {
    # Escape sequence for a colour given as three numbers (faster than parsing hex).
    $code = $script:StyleEsc + '[38;2;' + $Rgb[0] + ';' + $Rgb[1] + ';' + $Rgb[2] + 'm'
    if ($Bold) { $code += $script:StyleEsc + '[1m' }
    return $code
}

function Get-MixedRgb([int[]]$A, [int[]]$B, [double]$T) {
    # $A blended towards $B; $T = 0 gives $A, 1 gives $B.
    if ($T -lt 0) { $T = 0 }
    if ($T -gt 1) { $T = 1 }
    return [int[]]@(
        [int]($A[0] + ($B[0] - $A[0]) * $T),
        [int]($A[1] + ($B[1] - $A[1]) * $T),
        [int]($A[2] + ($B[2] - $A[2]) * $T)
    )
}

function Test-Rainbow {
    # True if the active style has a colour wheel ("rainbow.colors").
    $r = (Get-StyleConfig).PSObject.Properties['rainbow']
    return [bool]($r -and @($r.Value.colors).Count -ge 2)
}

function Get-RainbowRgb([double]$Position) {
    # Colour on the wheel at $Position (0..1, wraps around), blended smoothly between
    # neighbouring colours of "rainbow.colors".
    if (-not $script:StyleRainbowCache) {
        $script:StyleRainbowCache = @(@((Get-StyleConfig).rainbow.colors) | ForEach-Object { , [int[]](ConvertTo-RgbParts ([string]$_)) })
    }
    $wheel = $script:StyleRainbowCache
    $p = $Position - [Math]::Floor($Position)
    $f = $p * $wheel.Count
    $i = [int][Math]::Floor($f)
    if ($i -ge $wheel.Count) { $i = 0 }
    return (Get-MixedRgb $wheel[$i] $wheel[($i + 1) % $wheel.Count] ($f - $i))
}

function Format-Rainbow([string]$Text, [double]$Offset = 0, [double]$Span = 1, [switch]$Bold) {
    # $Text letter by letter in the colours of the wheel, from $Offset over $Span of it.
    # Without a colour wheel: plain text.
    if (-not $Text) { return '' }
    if (-not (Test-Rainbow)) { return $Text }
    $sb = New-Object System.Text.StringBuilder
    $n = [Math]::Max(1, $Text.Length - 1)
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq ' ') { $null = $sb.Append(' '); continue }
        $null = $sb.Append((Get-RgbCode (Get-RainbowRgb ($Offset + $Span * $i / $n)) -Bold:$Bold)).Append($ch)
    }
    $null = $sb.Append($script:StyleReset)
    return $sb.ToString()
}

function Get-InkCode([string]$Hex, [switch]$Bold, [switch]$Italic) {
    # Escape sequence that switches the text colour to $Hex (24 bit).
    $c = ConvertTo-RgbParts $Hex
    $code = '{0}[38;2;{1};{2};{3}m' -f $script:StyleEsc, $c[0], $c[1], $c[2]
    if ($Bold) { $code += $script:StyleEsc + '[1m' }
    if ($Italic) { $code += $script:StyleEsc + '[3m' }
    return $code
}

function Format-Ink([string]$Text, [string]$Hex, [switch]$Bold, [switch]$Italic) {
    # $Text in colour $Hex, followed by a reset.
    if (-not $Text) { return '' }
    return (Get-InkCode $Hex -Bold:$Bold -Italic:$Italic) + $Text + $script:StyleReset
}

function Format-Gauge([double]$Fraction, [int]$Width, [string]$OnHex, [string]$OffHex) {
    # An instrument line: the filled part in $OnHex, the rest in $OffHex. $OnHex 'rainbow'
    # paints the filled part along the colour wheel, so a full line shows all of it. With
    # "glyphs.gaugeSpray" the filled part is sprayed from random characters instead of
    # drawn with one.
    if ($Fraction -lt 0) { $Fraction = 0 }
    if ($Fraction -gt 1) { $Fraction = 1 }
    $glyphs = (Get-StyleConfig).glyphs
    $glyph = [string]$glyphs.gauge
    $spray = ''
    if ($glyphs.PSObject.Properties['gaugeSpray']) { $spray = [string]$glyphs.gaugeSpray }
    $on = [int][Math]::Round($Fraction * $Width)
    if ($on -eq 0 -and $Fraction -ge 0.02) { $on = 1 }
    $rainbow = ($OnHex -eq 'rainbow') -and (Test-Rainbow)
    if ($OnHex -eq 'rainbow' -and -not $rainbow) { $OnHex = (Get-StyleMode (Get-ShellModeName)).accent }
    if (-not $spray -and -not $rainbow) {
        return (Format-Ink ($glyph * $on) $OnHex) + (Format-Ink ($glyph * ($Width - $on)) $OffHex)
    }
    $sb = New-Object System.Text.StringBuilder
    $fixed = ''
    if (-not $rainbow) { $fixed = Get-InkCode $OnHex }
    for ($i = 0; $i -lt $on; $i++) {
        if ($rainbow) { $null = $sb.Append((Get-RgbCode (Get-RainbowRgb ($i / [Math]::Max(1, $Width - 1))))) }
        else { $null = $sb.Append($fixed) }
        if ($spray) { $null = $sb.Append($spray[$script:StyleRandom.Next($spray.Length)]) }
        else { $null = $sb.Append($glyph) }
    }
    if ($on -gt 0) { $null = $sb.Append($script:StyleReset) }
    return $sb.ToString() + (Format-Ink ($glyph * ($Width - $on)) $OffHex)
}

function Get-GaugeInk($Mode, [string]$Default) {
    # Colour of the filled part of a gauge in a mode: "gaugeInk" (may be 'rainbow') or
    # $Default.
    if ($Mode.PSObject.Properties['gaugeInk']) { return [string]$Mode.gaugeInk }
    return $Default
}

function Format-ModeLabel($Mode) {
    # Mark and name of a mode: in its accent, or along the colour wheel ("labelInk").
    $mark = Format-Ink ([string]$Mode.mark) $Mode.accent
    if ($Mode.PSObject.Properties['labelInk'] -and [string]$Mode.labelInk -eq 'rainbow' -and (Test-Rainbow)) {
        return $mark + ' ' + (Format-Rainbow ([string]$Mode.label) $script:StyleRandom.NextDouble() 0.6 -Bold)
    }
    return $mark + ' ' + (Format-Ink ([string]$Mode.label) $Mode.accent -Bold)
}

# --- sprayed details (colourful styles) ----------------------------------------------

function Test-ModeTrail($Mode) {
    # True if a mode wants the sprayed details: separators, trails of characters.
    return [bool]($Mode.PSObject.Properties['trail'] -and $Mode.trail -and (Test-Rainbow))
}

function Get-StyleText([string]$Name) {
    # A text from "texts"; a list means: a different one each time.
    $value = (Get-StyleConfig).texts.$Name
    if ($value -is [array]) { return [string]$value[$script:StyleRandom.Next($value.Count)] }
    return [string]$value
}

function Format-StyleSep($Mode) {
    # The separator between parts of a line: plain and faint, or in sprayed modes a
    # random character from "glyphs.sepSpray" in a random colour of the wheel.
    $glyphs = (Get-StyleConfig).glyphs
    if ((Test-ModeTrail $Mode) -and $glyphs.PSObject.Properties['sepSpray']) {
        $set = [string]$glyphs.sepSpray
        $rgb = Get-MixedRgb (Get-RainbowRgb $script:StyleRandom.NextDouble()) (ConvertTo-RgbParts $Mode.background) 0.2
        return (Get-RgbCode $rgb) + $set[$script:StyleRandom.Next($set.Length)] + $script:StyleReset
    }
    return Format-Ink ([string]$glyphs.sep) $Mode.faint
}

function Format-Trail([int]$Length, $Mode) {
    # Characters breaking away at the end of a line, lighter and fainter towards the
    # right, like the picture. Always $Length columns wide.
    $art = (Get-StyleConfig).art
    if ($Length -le 0 -or -not $art) { return '' }
    $mid = [string]$art.flightMid
    $far = [string]$art.flightFar
    $bg = ConvertTo-RgbParts $Mode.background
    $start = $script:StyleRandom.NextDouble()
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Length; $i++) {
        $d = $i / $Length
        if ($script:StyleRandom.NextDouble() -lt 0.2 + 0.5 * $d) { $null = $sb.Append(' '); continue }
        if ($d -lt 0.4) { $set = $mid } else { $set = $far }
        $rgb = Get-MixedRgb (Get-RainbowRgb ($start + 0.07 * $i)) $bg (0.15 + 0.6 * $d)
        $null = $sb.Append((Get-RgbCode $rgb)).Append($set[$script:StyleRandom.Next($set.Length)]).Append($script:StyleReset)
    }
    return $sb.ToString()
}

function Format-SprayLine([int]$Width, [string]$BackgroundHex, [string]$MonoHex = '') {
    # A line sprayed across the window from the characters of "art.line": thin at the
    # ends, dense and bright in the middle, along the wheel (or in one colour).
    $art = (Get-StyleConfig).art
    if ($Width -le 0 -or -not $art -or -not $art.PSObject.Properties['line']) { return '' }
    $set = [string]$art.line
    $bg = ConvertTo-RgbParts $BackgroundHex
    $mono = $null
    if ($MonoHex) { $mono = [int[]](ConvertTo-RgbParts $MonoHex) }
    $start = $script:StyleRandom.NextDouble()
    $sb = New-Object System.Text.StringBuilder
    for ($x = 0; $x -lt $Width; $x++) {
        $e = [Math]::Sin([Math]::PI * ($x + 0.5) / $Width)
        if ($script:StyleRandom.NextDouble() -ge 0.2 + 0.7 * $e) { $null = $sb.Append(' '); continue }
        if ($mono) { $rgb = $mono } else { $rgb = Get-RainbowRgb ($start + 0.9 * $x / $Width) }
        $rgb = Get-MixedRgb $rgb $bg (0.65 - 0.5 * $e)
        $null = $sb.Append((Get-RgbCode $rgb)).Append($set[$script:StyleRandom.Next($set.Length)]).Append($script:StyleReset)
    }
    return $sb.ToString()
}

function Get-WindowWidth {
    # Width of the console in columns; 80 when there is no console (redirected output).
    try { $w = $Host.UI.RawUI.WindowSize.Width; if ($w -gt 0) { return $w } } catch { }
    return 80
}

function Format-Number([double]$Value, [int]$Decimals = 0) {
    # number format of the texts (English): 1,234.5
    return $Value.ToString("N$Decimals", $script:StyleCulture)
}

# --- terminal tint --------------------------------------------------------------------

function Set-TerminalPalette([string]$ModeName) {
    # Tints the running terminal (background, text, cursor) in the colours of a mode, so
    # the light in the room changes with where the thinking happens. Only in Windows
    # Terminal, whose colour scheme is the mode of the shell (scripts\Install-Style.ps1);
    # elsewhere, and when the output is redirected, nothing happens.
    if (-not $env:WT_SESSION) { return }
    if (-not (Test-StyleInstalled)) { return }
    if (-not (Test-StyledOutput)) { return }
    $mode = Get-StyleMode $ModeName
    $bel = [string][char]7
    $out = ''
    foreach ($pair in @(@(11, $mode.background), @(10, $mode.foreground), @(12, $mode.cursor))) {
        $h = ([string]$pair[1]).TrimStart('#')
        $out += '{0}]{1};rgb:{2}/{3}/{4}{5}' -f $script:StyleEsc, $pair[0], $h.Substring(0, 2), $h.Substring(2, 2), $h.Substring(4, 2), $bel
    }
    [Console]::Write($out)
}

# --- Claude Code ----------------------------------------------------------------------

function Test-StyleInstalled {
    # True once scripts\Install-Style.ps1 has run (it writes the theme files).
    return (Test-Path (Get-ClaudeThemeFile ([string](Get-StyleConfig).claude.localMode)))
}

function Test-StyledOutput {
    # False when the output goes to a file or a pipe: no colours, no terminal tint.
    try { return (-not [Console]::IsOutputRedirected) } catch { return $false }
}

function Get-StatusLineSetting([int]$RefreshSeconds = 0) {
    # The "statusLine" entry for Claude Code settings. Forward slashes, because Claude
    # Code may run the command through Git Bash.
    $script = (Join-Path $script:StyleProjectRoot 'scripts\style\Statusline.ps1') -replace '\\', '/'
    $entry = [ordered]@{
        type    = 'command'
        command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $script
        padding = 0
    }
    if ($RefreshSeconds -gt 0) { $entry['refreshInterval'] = $RefreshSeconds }
    return $entry
}

function Get-LocalLookSettings {
    # Settings that give a claude-local session its own look: the warm theme and a status
    # line that re-reads the graphics cards every few seconds. Empty if the look is not
    # installed. claude-local merges this into the settings file of the launch.
    $result = [ordered]@{}
    if (-not (Test-StyleInstalled)) { return $result }
    $claude = (Get-StyleConfig).claude
    $result['theme'] = 'custom:' + (Get-ClaudeThemeSlug ([string]$claude.localMode))
    $result['statusLine'] = Get-StatusLineSetting ([int]$claude.statusLine.localRefreshSeconds)
    return $result
}

function Get-LocalLookBanner([string]$Model, [string]$BaseUrl, [int]$ContextUsable, [int]$ContextTotal, [string[]]$PickerModels, [string]$Name = 'claude-local') {
    # The lines claude-local and unzensiert print before a session starts. Plain text when
    # the output is redirected (benchmark, scripts) or the look is not installed.
    $lines = @()
    if (-not (Test-StyledOutput) -or -not (Test-StyleInstalled)) {
        $lines += "${Name}: model '$Model' at $BaseUrl, context $ContextUsable of $ContextTotal tokens"
        if ($PickerModels.Count -gt 1) { $lines += "${Name}: switch inside the session with /model ($($PickerModels -join ', '))" }
        return $lines
    }
    $cfg = Get-StyleConfig
    $mode = Get-StyleMode ([string]$cfg.claude.localMode)
    $sep = '  ' + (Format-Ink ([string]$cfg.glyphs.sep) $mode.faint) + '  '
    $lines += ''
    # colourful styles start every local session with a picture made of characters
    if ($cfg.PSObject.Properties['art'] -and $cfg.art.bannerText) {
        $width = Get-WindowWidth
        $lines += @(Get-CharArt ([string]$cfg.art.bannerText) ([int]$cfg.art.bannerScale) $width $mode.background)
        $line = Format-SprayLine ($width - 5) $mode.background
        if ($line) { $lines += '  ' + $line }
        $lines += ''
    }
    $lines += ' ' + (Format-ModeLabel $mode) + '  ' +
        (Format-Ink $Model $mode.foreground) + $sep +
        (Format-Ink ([string]$cfg.texts.contextOf -f (Format-Number $ContextUsable), (Format-Number $ContextTotal)) $mode.dim) + $sep +
        (Format-Ink $BaseUrl $mode.dim)
    if ($PickerModels.Count -gt 1) { $lines += '   ' + (Format-Ink ([string]$cfg.texts.switchModel -f ($PickerModels -join ', ')) $mode.dim) }
    return $lines
}

function Enter-LocalLook {
    # Marks the process as a local session (the status line reads the variable) and
    # warms the terminal up. Undo with Exit-LocalLook.
    $claude = (Get-StyleConfig).claude
    Set-Item -Path ("Env:" + [string](Get-StyleSelection).modeVariable) -Value ([string]$claude.localMode)
    Set-TerminalPalette ([string]$claude.localMode)
}

function Exit-LocalLook {
    Set-TerminalPalette (Get-ShellModeName)
}

function Get-LocalLookFarewell([datetime]$Started) {
    # The lines after a local session: a sprayed line and how long it lasted ("texts.
    # farewell"). Empty for styles without it, when the look is not installed or the
    # output is redirected.
    $cfg = Get-StyleConfig
    if (-not $cfg.texts.PSObject.Properties['farewell']) { return @() }
    if (-not (Test-StyledOutput) -or -not (Test-StyleInstalled)) { return @() }
    $mode = Get-StyleMode ([string]$cfg.claude.localMode)
    $minutes = ((Get-Date) - $Started).TotalMinutes
    if ($minutes -ge 60) { $took = '{0} h {1} min' -f [int][Math]::Floor($minutes / 60), [int]($minutes % 60) }
    elseif ($minutes -ge 1) { $took = '{0} min' -f [int][Math]::Round($minutes) }
    else { $took = '{0} s' -f [int][Math]::Round($minutes * 60) }
    $width = Get-WindowWidth
    return @(
        '',
        ('  ' + (Format-SprayLine ([Math]::Min(60, $width - 5)) $mode.background)),
        (' ' + (Format-Ink ([string]$mode.mark) $mode.accent) + ' ' + (Format-Rainbow ([string]$cfg.texts.farewell -f $took) $script:StyleRandom.NextDouble() 0.6) + '  ' + (Format-Trail 6 $mode)),
        ''
    )
}

# --- readings -------------------------------------------------------------------------

function Get-GpuReadings {
    # One object per graphics card: name, usedMiB, totalMiB, temperature, load.
    # Empty if nvidia-smi is missing.
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return @() }
    $rows = @()
    try {
        $lines = & nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null
        foreach ($line in $lines) {
            $f = @($line -split ',' | ForEach-Object { $_.Trim() })
            if ($f.Count -lt 5) { continue }
            $rows += [pscustomobject]@{
                name        = ($f[0] -replace '^NVIDIA\s+', '' -replace '^GeForce\s+', '')
                usedMiB     = [double]$f[1]
                totalMiB    = [double]$f[2]
                temperature = [int]$f[3]
                load        = [int]$f[4]
            }
        }
    } catch { }
    return $rows
}

function Get-EmberProcess {
    # The running llama-server, or $null: is the own fire lit?
    $name = [string](Get-StyleConfig).shell.emberProcess
    return (Get-Process -Name $name -ErrorAction SilentlyContinue | Sort-Object StartTime | Select-Object -First 1)
}

function Get-GitSummary([string]$Dir) {
    # Branch and number of changed files of the repository that contains $Dir, or $null.
    # Walks up to find .git first, so folders outside a repository cost no git call.
    $probe = $Dir
    $found = $false
    while ($probe) {
        if (Test-Path -LiteralPath (Join-Path $probe '.git')) { $found = $true; break }
        $parent = Split-Path -Parent $probe
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
    if (-not $found) { return $null }

    $lines = $null
    try { $lines = & git -C $Dir status --porcelain=v2 --branch 2>$null } catch { return $null }
    if ($LASTEXITCODE -ne 0 -or -not $lines) { return $null }
    $branch = ''
    $ahead = 0
    $behind = 0
    $changed = 0
    foreach ($line in $lines) {
        if ($line -match '^# branch\.head (.+)$') { $branch = $Matches[1] }
        elseif ($line -match '^# branch\.ab \+(\d+) -(\d+)$') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
        elseif ($line -notmatch '^#') { $changed++ }
    }
    return [pscustomobject]@{ branch = $branch; ahead = $ahead; behind = $behind; changed = $changed }
}

function Format-GitSummary($Git, [string]$DimHex) {
    # "main +-6 ^1" in colour; empty string without a repository.
    if (-not $Git) { return '' }
    $cfg = Get-StyleConfig
    $text = Format-Ink $Git.branch $cfg.ink.branch -Italic
    if ($Git.changed -gt 0) { $text += ' ' + (Format-Ink ("{0}{1}" -f $cfg.glyphs.dirty, $Git.changed) $cfg.ink.warn) }
    if ($Git.ahead -gt 0) { $text += ' ' + (Format-Ink ("{0}{1}" -f $cfg.glyphs.ahead, $Git.ahead) $DimHex) }
    if ($Git.behind -gt 0) { $text += ' ' + (Format-Ink ("{0}{1}" -f $cfg.glyphs.behind, $Git.behind) $DimHex) }
    return $text
}

function Get-VisibleLength([string]$Text) {
    # Length of a string without its escape sequences.
    return ($Text -replace ($script:StyleEsc + '\[[0-9;]*m'), '').Length
}
