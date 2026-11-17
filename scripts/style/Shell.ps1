# Sets up an interactive PowerShell in the active look (config\style.json): two-line
# prompt, colours of the input line, a greeting with the state of both graphics cards
# (in colourful styles under a picture made of characters), and a `claude` function that
# tints the terminal while a cloud session runs.
#
# Started by the Windows Terminal profile that scripts\Install-Style.ps1 creates:
#   powershell -NoLogo -NoExit -ExecutionPolicy RemoteSigned -File scripts\style\Shell.ps1
# It can also be dot-sourced from a PowerShell profile. Colours, glyphs and texts come
# from the active style in config\styles\ (docs\stil.md).

. "$PSScriptRoot\..\lib\Style.ps1"

# Native programs (git, claude) write UTF-8; decode their output as such.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$global:StyleState = @{
    lastHistoryId = -1
    promptCount   = 0
    isAdmin       = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- input line -----------------------------------------------------------------------

function Set-StyleInputColors {
    # Colours of the text being typed (PSReadLine), from "shell.syntax".
    $syntax = (Get-StyleConfig).shell.syntax
    $colors = @{}
    foreach ($p in $syntax.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }
        $colors[$p.Name] = Get-InkCode ([string]$p.Value) -Italic:($p.Name -eq 'Comment')
    }
    try {
        Set-PSReadLineOption -Colors $colors
        Set-PSReadLineOption -ContinuationPrompt '   '
    } catch { }
    # Windows PowerShell paints errors and warnings on a black box by default.
    try {
        $bg = $Host.UI.RawUI.BackgroundColor
        $Host.PrivateData.ErrorBackgroundColor = $bg
        $Host.PrivateData.WarningBackgroundColor = $bg
        $Host.PrivateData.VerboseBackgroundColor = $bg
        $Host.PrivateData.DebugBackgroundColor = $bg
    } catch { }
}

# --- prompt ---------------------------------------------------------------------------

function global:prompt {
    # Line 1: ember dot, folder, parent path, git state; at the right edge the measured
    #         duration of the last command and the time.
    # Line 2: the prompt glyph, red after a failed command.
    $ok = $?
    $exitCode = $global:LASTEXITCODE
    $cfg = Get-StyleConfig
    $mode = Get-StyleMode (Get-ShellModeName)
    $g = $cfg.glyphs

    # the own fire: lit while llama-server runs
    if (Get-EmberProcess) { $ember = Format-Ink ([string]$mode.mark) $cfg.ink.ember }
    else { $ember = Format-Ink ([string]$g.emberOff) $mode.faint }

    # where: the folder first, like a title, then the way to it
    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    $path = $location.Path
    $git = $null
    if ($location.Provider.Name -eq 'FileSystem') {
        $git = Get-GitSummary $path
        $leaf = Split-Path -Leaf $path
        $parent = Split-Path -Parent $path
        if (-not $leaf) { $leaf = $path; $parent = '' }
        if ($path -eq $HOME) { $leaf = '~'; $parent = '' }
    } else {
        $leaf = $path
        $parent = ''
    }
    # colourful styles: the folder letter by letter, a little further round the wheel
    # after every command
    $rainbow = [bool]$cfg.shell.rainbow -and (Test-Rainbow)
    $turn = $global:StyleState.promptCount / 7.0
    $global:StyleState.promptCount++
    if ($rainbow) { $title = Format-Rainbow $leaf $turn 0.35 -Bold }
    else { $title = Format-Ink $leaf $mode.foreground -Bold }
    $left = ' ' + $ember + ' ' + $title
    if ($parent) { $left += '  ' + (Format-Ink $parent $mode.dim) }
    if ($git) { $left += '  ' + (Format-Ink ([string]$g.sep) $mode.faint) + '  ' + (Format-GitSummary $git $mode.dim) }
    if ($global:StyleState.isAdmin) { $left += '  ' + (Format-Ink ([string]$cfg.texts.admin) $cfg.ink.error -Bold) }

    # measured, not claimed: how long the last command took
    $right = ''
    $last = Get-History -Count 1
    if ($last -and $last.Id -ne $global:StyleState.lastHistoryId) {
        $global:StyleState.lastHistoryId = $last.Id
        $seconds = ($last.EndExecutionTime - $last.StartExecutionTime).TotalSeconds
        if (-not $ok -and $exitCode) { $right += (Format-Ink ([string]$cfg.texts.exitCode -f $exitCode) $cfg.ink.error) + '  ' }
        if ($seconds -ge [double]$cfg.shell.slowCommandSeconds) {
            if ($seconds -ge 60) { $took = '{0} min {1} s' -f [int][Math]::Floor($seconds / 60), [int]($seconds % 60) }
            else { $took = (Format-Number $seconds 1) + ' s' }
            $right += (Format-Ink $took $mode.accentSoft) + ' ' + (Format-Ink ([string]$g.sep) $mode.faint) + ' '
        }
    }
    $right += Format-Ink (Get-Date -Format 'HH:mm') $mode.dim

    $width = $Host.UI.RawUI.WindowSize.Width
    $gap = $width - (Get-VisibleLength $left) - (Get-VisibleLength $right) - 1
    if ($gap -ge 2) { $line1 = $left + (' ' * $gap) + $right } else { $line1 = $left }

    $glyph = Get-StyleGlyph 'prompt'
    if (-not $ok) { $mark = Format-Ink $glyph $cfg.ink.error -Bold }
    elseif ($rainbow) { $mark = (Get-RgbCode (Get-RainbowRgb $turn) -Bold) + $glyph + $script:StyleReset }
    else { $mark = Format-Ink $glyph $mode.accent -Bold }

    try { $Host.UI.RawUI.WindowTitle = $leaf } catch { }
    $global:LASTEXITCODE = $exitCode
    return "`n" + $line1 + "`n " + $mark + ' '
}

# --- greeting -------------------------------------------------------------------------

function Show-StyleGreeting {
    # Name of the look (or its picture made of characters), date, one gauge per graphics
    # card and whether the server runs.
    $cfg = Get-StyleConfig
    $mode = Get-StyleMode (Get-ShellModeName)
    $sep = Format-Ink ([string]$cfg.glyphs.sep) $mode.faint
    $width = $Host.UI.RawUI.WindowSize.Width

    $art = @()
    if ($cfg.PSObject.Properties['art'] -and $cfg.art.text) {
        $art = @(Get-CharArt ([string]$cfg.art.text) ([int]$cfg.art.scale) $width $mode.background)
    }
    $now = Get-Date
    $date = $now.ToString('dddd, d. MMMM', [System.Globalization.CultureInfo]::GetCultureInfo('de-DE'))
    if ($art.Count -gt 0) {
        ''
        $art
        $left = '  ' + (Format-Rainbow ([string]$cfg.texts.tagline) $script:StyleRandom.NextDouble() 0.8)
    } else {
        $title = (([string]$cfg.name).ToUpper().ToCharArray() -join ' ')
        $left = '  ' + (Format-Ink $title $mode.accent)
    }
    $right = (Format-Ink $date $mode.dim) + ' ' + $sep + ' ' + (Format-Ink ($now.ToString('HH:mm')) $mode.dim)
    $gap = $width - (Get-VisibleLength $left) - (Get-VisibleLength $right) - 1
    if ($gap -lt 2) { $gap = 2 }
    ''
    $left + (' ' * $gap) + $right
    ''

    $gpus = @(Get-GpuReadings)
    if ($gpus.Count -gt 0) {
        $nameWidth = ($gpus | ForEach-Object { $_.name.Length } | Measure-Object -Maximum).Maximum
        foreach ($gpu in $gpus) {
            $fraction = 0
            if ($gpu.totalMiB -gt 0) { $fraction = $gpu.usedMiB / $gpu.totalMiB }
            $memory = '{0,5} / {1} GB' -f (Format-Number ($gpu.usedMiB / 1024) 1), (Format-Number ($gpu.totalMiB / 1024) 1)
            '  ' + (Format-Ink ($gpu.name.PadRight($nameWidth)) $mode.foreground) + '   ' +
                (Format-Gauge $fraction ([int]$cfg.shell.gaugeWidth) (Get-GaugeInk $mode $cfg.ink.ember) $mode.faint) + '   ' +
                (Format-Ink $memory $mode.dim) + '   ' + (Format-Ink ('{0} {1}C' -f $gpu.temperature, [char]0xB0) $mode.dim)
        }
        ''
    }

    $server = Get-EmberProcess
    if ($server) {
        '  ' + (Format-Ink ([string]$mode.mark) $cfg.ink.ember) + ' ' +
            (Format-Ink ([string]$cfg.texts.emberOn -f $server.StartTime.ToString('HH:mm')) $mode.dim)
    } else {
        '  ' + (Format-Ink ([string]$cfg.glyphs.emberOff) $mode.faint) + ' ' + (Format-Ink ([string]$cfg.texts.emberOff) $mode.dim)
    }
}

# --- cloud sessions -------------------------------------------------------------------

function global:claude {
    # Runs the real claude.exe (Anthropic cloud) and tints the terminal in the cloud mode
    # for as long as the session lasts. Arguments and piped input pass through unchanged.
    $exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { Write-Error 'claude.exe not found on PATH.'; return }
    Set-TerminalPalette ([string](Get-StyleConfig).claude.cloudMode)
    try {
        if ($MyInvocation.ExpectingInput) { $input | & $exe.Source @args }
        else { & $exe.Source @args }
    } finally {
        Set-TerminalPalette (Get-ShellModeName)
    }
}

# --- start ----------------------------------------------------------------------------

Set-StyleInputColors
Set-TerminalPalette (Get-ShellModeName)
if ((Get-StyleConfig).shell.greeting) { Show-StyleGreeting }
