# Sets up an interactive PowerShell in the look "Nachtschicht": two-line prompt, colours
# of the input line, a greeting with the state of both graphics cards, and a `claude`
# function that tints the terminal while a cloud session runs.
#
# Started by the Windows Terminal profile that scripts\Install-Style.ps1 creates:
#   powershell -NoLogo -NoExit -ExecutionPolicy RemoteSigned -File scripts\style\Shell.ps1
# It can also be dot-sourced from a PowerShell profile. Colours, glyphs and texts come
# from config\style.json (docs\stil.md).

. "$PSScriptRoot\..\lib\Style.ps1"

# Native programs (git, claude) write UTF-8; decode their output as such.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$global:NachtschichtState = @{
    lastHistoryId = -1
    isAdmin       = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- input line -----------------------------------------------------------------------

function Set-NachtschichtInputColors {
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
    $mode = Get-StyleMode 'werkbank'
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
    $left = ' ' + $ember + ' ' + (Format-Ink $leaf $mode.foreground -Bold)
    if ($parent) { $left += '  ' + (Format-Ink $parent $mode.dim) }
    if ($git) { $left += '  ' + (Format-Ink ([string]$g.sep) $mode.faint) + '  ' + (Format-GitSummary $git $mode.dim) }
    if ($global:NachtschichtState.isAdmin) { $left += '  ' + (Format-Ink ([string]$cfg.texts.admin) $cfg.ink.error -Bold) }

    # measured, not claimed: how long the last command took
    $right = ''
    $last = Get-History -Count 1
    if ($last -and $last.Id -ne $global:NachtschichtState.lastHistoryId) {
        $global:NachtschichtState.lastHistoryId = $last.Id
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

    if ($ok) { $mark = Format-Ink ([string]$g.prompt) $mode.accent -Bold }
    else { $mark = Format-Ink ([string]$g.prompt) $cfg.ink.error -Bold }

    try { $Host.UI.RawUI.WindowTitle = $leaf } catch { }
    $global:LASTEXITCODE = $exitCode
    return "`n" + $line1 + "`n " + $mark + ' '
}

# --- greeting -------------------------------------------------------------------------

function Show-NachtschichtGreeting {
    # Name of the look, date, one gauge per graphics card and whether the fire is lit.
    $cfg = Get-StyleConfig
    $mode = Get-StyleMode 'werkbank'
    $sep = Format-Ink ([string]$cfg.glyphs.sep) $mode.faint

    $title = (([string]$cfg.name).ToUpper().ToCharArray() -join ' ')
    $now = Get-Date
    $date = $now.ToString('dddd, d. MMMM', [System.Globalization.CultureInfo]::GetCultureInfo('de-DE'))
    $left = '  ' + (Format-Ink $title $mode.accent)
    $right = (Format-Ink $date $mode.dim) + ' ' + $sep + ' ' + (Format-Ink ($now.ToString('HH:mm')) $mode.dim)
    $gap = $Host.UI.RawUI.WindowSize.Width - (Get-VisibleLength $left) - (Get-VisibleLength $right) - 1
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
                (Format-Gauge $fraction ([int]$cfg.shell.gaugeWidth) $cfg.ink.ember $mode.faint) + '   ' +
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
    # Runs the real claude.exe (Anthropic cloud) and tints the terminal in the cool mode
    # for as long as the session lasts. Arguments and piped input pass through unchanged.
    $exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { Write-Error 'claude.exe not found on PATH.'; return }
    Set-TerminalPalette ([string](Get-StyleConfig).claude.cloudMode)
    try {
        if ($MyInvocation.ExpectingInput) { $input | & $exe.Source @args }
        else { & $exe.Source @args }
    } finally {
        Set-TerminalPalette 'werkbank'
    }
}

# --- start ----------------------------------------------------------------------------

Set-NachtschichtInputColors
Set-TerminalPalette 'werkbank'
if ((Get-StyleConfig).shell.greeting) { Show-NachtschichtGreeting }
