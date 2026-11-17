# Status line of Claude Code in the look "Nachtschicht". Claude Code passes the state of
# the session as JSON on stdin and shows the line this script prints.
#
#   local session (claude-local):  mark, model, context, memory of both graphics cards
#   cloud session (claude):        mark, model, context, 5-hour usage limit
#
# Registered by scripts\Install-Style.ps1 ("statusLine" in ~\.claude\settings.json). The
# mode comes from the variable that claude-local sets ("claude.modeVariable" in
# config\style.json). Try it by hand:
#   '{"model":{"display_name":"Test"}}' | powershell -NoProfile -File scripts\style\Statusline.ps1

. "$PSScriptRoot\..\lib\Style.ps1"

function Read-StdinUtf8 {
    # Console.In would decode with the OEM code page; read the bytes and decode UTF-8.
    $stream = [Console]::OpenStandardInput()
    $buffer = New-Object System.IO.MemoryStream
    $stream.CopyTo($buffer)
    return [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
}

function Write-StdoutUtf8([string]$Text) {
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Text)
    $stream = [Console]::OpenStandardOutput()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

function Get-JsonValue($Object, [string]$Path) {
    # Reads "a.b.c" from a parsed JSON object; $null if any step is missing.
    $current = $Object
    foreach ($step in $Path -split '\.') {
        if ($null -eq $current) { return $null }
        $prop = $current.PSObject.Properties[$step]
        if (-not $prop) { return $null }
        $current = $prop.Value
    }
    return $current
}

function ConvertTo-LocalTime($Value) {
    # resets_at arrives as epoch seconds or as an ISO date, depending on the source.
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [string] -and $Value -notmatch '^\d+$') { return ([datetime]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)).ToLocalTime() }
        return ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime().AddSeconds([double]$Value).ToLocalTime()
    } catch { return $null }
}

$cfg = Get-StyleConfig
$session = $null
try { $session = (Read-StdinUtf8) | ConvertFrom-Json } catch { }

$modeName = [Environment]::GetEnvironmentVariable([string]$cfg.claude.modeVariable)
if (-not $modeName) { $modeName = [string]$cfg.claude.cloudMode }
$isLocal = ($modeName -eq [string]$cfg.claude.localMode)
$mode = Get-StyleMode $modeName
$width = [int]$cfg.claude.statusLine.gaugeWidth
$sep = '  ' + (Format-Ink ([string]$cfg.glyphs.sep) $mode.faint) + '  '

$parts = @()

# who is thinking: mark and name of the mode, then the model
$model = [string](Get-JsonValue $session 'model.display_name')
if (-not $model) { $model = [string](Get-JsonValue $session 'model.id') }
$head = (Format-Ink ([string]$mode.mark) $mode.accent) + ' ' + (Format-Ink ([string]$mode.label) $mode.accent -Bold)
if ($model) { $head += '  ' + (Format-Ink $model $mode.foreground) }
$parts += $head

# how full the context window is
$used = Get-JsonValue $session 'context_window.used_percentage'
if ($null -ne $used) {
    $used = [double]$used
    $ink = $mode.accent
    if ($used -ge [double]$cfg.claude.statusLine.contextWarnPercent) { $ink = $cfg.ink.warn }
    if ($used -ge [double]$cfg.claude.statusLine.contextFullPercent) { $ink = $cfg.ink.error }
    $parts += (Format-Ink ([string]$cfg.texts.context) $mode.dim) + ' ' + (Format-Gauge ($used / 100) $width $ink $mode.faint) + ' ' +
        (Format-Ink ('{0} %' -f [int][Math]::Round($used)) $mode.foreground)
}

if ($isLocal) {
    # the own machine: memory in use on each graphics card
    foreach ($gpu in @(Get-GpuReadings)) {
        $fraction = 0
        if ($gpu.totalMiB -gt 0) { $fraction = $gpu.usedMiB / $gpu.totalMiB }
        $parts += (Format-Ink ($gpu.name -replace '^RTX\s+', '') $mode.dim) + ' ' + (Format-Gauge $fraction $width $mode.accent $mode.faint) + ' ' +
            (Format-Ink ((Format-Number ($gpu.usedMiB / 1024) 1) + ' GB') $mode.foreground)
    }
} else {
    # the cloud: how much of the 5-hour limit is used, and when it resets
    $limit = Get-JsonValue $session 'rate_limits.five_hour.used_percentage'
    if ($null -ne $limit) {
        $limit = [double]$limit
        $ink = $mode.accent
        if ($limit -ge 70) { $ink = $cfg.ink.warn }
        if ($limit -ge 90) { $ink = $cfg.ink.error }
        $text = (Format-Ink ([string]$cfg.texts.limit5h) $mode.dim) + ' ' + (Format-Gauge ($limit / 100) $width $ink $mode.faint) + ' ' +
            (Format-Ink ('{0} %' -f [int][Math]::Round($limit)) $mode.foreground)
        $reset = ConvertTo-LocalTime (Get-JsonValue $session 'rate_limits.five_hour.resets_at')
        if ($reset) { $text += ' ' + (Format-Ink ([string]$cfg.texts.limitUntil -f $reset.ToString('HH:mm')) $mode.dim) }
        $parts += $text
    }
}

# where: folder and git state
$dir = [string](Get-JsonValue $session 'workspace.current_dir')
if ($dir) {
    $where = Format-Ink (Split-Path -Leaf $dir) $mode.foreground
    $git = Get-GitSummary $dir
    if ($git) { $where += ' ' + (Format-GitSummary $git $mode.dim) }
    $parts += $where
}

Write-StdoutUtf8 (' ' + ($parts -join $sep))
