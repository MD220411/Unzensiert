# Building blocks of the look "Nachtschicht": reads config\style.json, turns colours into
# terminal escape sequences, tints the terminal per mode and takes the readings that the
# prompt, the greeting and the status line show (graphics cards, git, llama-server).
#
# Self-contained on purpose: the interactive shell and the status line of Claude Code load
# only this file. They must start fast, and $ErrorActionPreference = 'Stop' from
# _common.ps1 must not leak into an interactive shell.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI. All
# non-ASCII characters (glyphs, German texts) therefore live in config\style.json.

$script:StyleProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:StyleConfigCache = $null
$script:StyleEsc = [string][char]27
$script:StyleReset = $script:StyleEsc + '[0m'
$script:StyleCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')

# --- configuration ------------------------------------------------------------------

function Get-StyleConfig {
    # config\style.json, read once per process. ReadAllText decodes UTF-8 reliably.
    if (-not $script:StyleConfigCache) {
        $path = Join-Path $script:StyleProjectRoot 'config\style.json'
        $script:StyleConfigCache = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    return $script:StyleConfigCache
}

function Get-StyleMode([string]$Name) {
    # One entry of "modes" (werkbank, glut, fernlicht); unknown names fall back to werkbank.
    $modes = (Get-StyleConfig).modes
    $entry = $modes.PSObject.Properties[$Name]
    if ($entry -and $entry.Value -isnot [string]) { return $entry.Value }
    return $modes.werkbank
}

function Get-ClaudeThemeSlug([string]$ModeName) {
    # Name of the Claude Code theme file (without .json) that belongs to a mode.
    return ([string](Get-StyleConfig).claude.themePrefix) + $ModeName
}

function Get-ClaudeThemeFile([string]$ModeName) {
    return (Join-Path $env:USERPROFILE (".claude\themes\{0}.json" -f (Get-ClaudeThemeSlug $ModeName)))
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
    # A thin instrument line: the filled part in $OnHex, the rest in $OffHex.
    if ($Fraction -lt 0) { $Fraction = 0 }
    if ($Fraction -gt 1) { $Fraction = 1 }
    $glyph = [string](Get-StyleConfig).glyphs.gauge
    $on = [int][Math]::Round($Fraction * $Width)
    if ($on -eq 0 -and $Fraction -ge 0.02) { $on = 1 }
    return (Format-Ink ($glyph * $on) $OnHex) + (Format-Ink ($glyph * ($Width - $on)) $OffHex)
}

function Format-Number([double]$Value, [int]$Decimals = 0) {
    # German number format: 1.234,5
    return $Value.ToString("N$Decimals", $script:StyleCulture)
}

# --- terminal tint --------------------------------------------------------------------

function Set-TerminalPalette([string]$ModeName) {
    # Tints the running terminal (background, text, cursor) in the colours of a mode, so
    # the light in the room changes with where the thinking happens. Only in Windows
    # Terminal, whose colour scheme is the mode "werkbank" (scripts\Install-Style.ps1);
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

function Get-LocalLookBanner([string]$Model, [string]$BaseUrl, [int]$ContextUsable, [int]$ContextTotal, [string[]]$PickerModels) {
    # The lines claude-local prints before Claude Code starts. Plain text when the output
    # is redirected (benchmark, scripts) or the look is not installed.
    $lines = @()
    if (-not (Test-StyledOutput) -or -not (Test-StyleInstalled)) {
        $lines += "claude-local: model '$Model' at $BaseUrl, context $ContextUsable of $ContextTotal tokens"
        if ($PickerModels.Count -gt 1) { $lines += "claude-local: switch inside the session with /model ($($PickerModels -join ', '))" }
        return $lines
    }
    $cfg = Get-StyleConfig
    $mode = Get-StyleMode ([string]$cfg.claude.localMode)
    $sep = '  ' + (Format-Ink ([string]$cfg.glyphs.sep) $mode.faint) + '  '
    $lines += ''
    $lines += ' ' + (Format-Ink ([string]$mode.mark) $mode.accent) + ' ' + (Format-Ink ([string]$mode.label) $mode.accent -Bold) + '  ' +
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
    Set-Item -Path ("Env:" + [string]$claude.modeVariable) -Value ([string]$claude.localMode)
    Set-TerminalPalette ([string]$claude.localMode)
}

function Exit-LocalLook {
    Set-TerminalPalette 'werkbank'
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
