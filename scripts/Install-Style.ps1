# Applies the look "Nachtschicht" from config\style.json to
#   - Windows Terminal: colour scheme, window theme, font, and a profile that starts
#     PowerShell with scripts\style\Shell.ps1 (becomes the default profile)
#   - Claude Code: two colour themes in ~\.claude\themes\, and in ~\.claude\settings.json
#     the theme for cloud sessions, the status line and the spinner words
# Idempotent: run it again after every change to config\style.json. Before the first
# change each settings file is copied once to <name>.vor-nachtschicht.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1 -PreviewDir C:\Temp\vorschau
#   powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1 -Remove
#
#   -PreviewDir  write the resulting files into this folder instead of the real places
#   -Remove      take our entries out again (the rest of the settings stays as it is)

param(
    [string]$PreviewDir,
    [switch]$Remove
)

. "$PSScriptRoot\_common.ps1"

$style = Get-StyleConfig
$styleName = [string]$style.name
$backupSuffix = '.vor-' + $styleName.ToLower()
$utf8 = New-Object System.Text.UTF8Encoding($false)

# keys this script owns in the settings files (written on install, removed on -Remove)
$terminalDefaultKeys = @('colorScheme', 'font', 'padding', 'cursorShape', 'cursorHeight', 'scrollbarState',
    'adjustIndistinguishableColors', 'intenseTextStyle', 'opacity', 'useAcrylic')
$claudeKeys = @('statusLine', 'spinnerVerbs')

# --- JSON helpers -----------------------------------------------------------------------

function Set-Prop($Object, [string]$Name, $Value) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Remove-Prop($Object, [string]$Name) {
    if ($Object.PSObject.Properties[$Name]) { $Object.PSObject.Properties.Remove($Name) }
}

function ConvertTo-PrettyJson($Object) {
    # ConvertTo-Json of Windows PowerShell 5.1 indents oddly and escapes ' < > &.
    $json = $Object | ConvertTo-Json -Depth 32
    $indent = 0
    $lines = foreach ($raw in ($json -split "`r?`n")) {
        $line = $raw.Trim()
        if ($line -eq '') { continue }
        if ($line -match '^[\}\]]') { $indent-- }
        ('  ' * $indent) + ($line -replace '^("(?:[^"\\]|\\.)*"):\s+', '$1: ')
        if ($line -match '[\{\[]$') { $indent++ }
    }
    $text = ($lines -join "`n")
    $text = [regex]::Replace($text, '\[\s*\n\s*\]', '[]')
    $text = [regex]::Replace($text, '\{\s*\n\s*\}', '{}')
    foreach ($pair in @(@('0027', "'"), @('003c', '<'), @('003e', '>'), @('0026', '&'))) {
        $text = [regex]::Replace($text, '(?<!\\)\\u' + $pair[0], $pair[1])
    }
    return $text + "`n"
}

function Read-SettingsFile([string]$Path) {
    # Parsed settings, or $null with a message if the file cannot be read as JSON
    # (Windows PowerShell 5.1 does not accept comments in JSON).
    try { return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch {
        Write-Warning "SKIPPED $Path - not readable as JSON (comments?): $($_.Exception.Message)"
        return $null
    }
}

function Save-SettingsFile([string]$Path, $Object, [string]$PreviewName) {
    # Writes UTF-8 without BOM. With -PreviewDir the file goes there and the real one
    # stays untouched; otherwise the original is copied once before the first change.
    $text = ConvertTo-PrettyJson $Object
    $null = $text | ConvertFrom-Json           # fail here rather than write broken JSON
    if ($PreviewDir) {
        $null = New-Item -ItemType Directory -Force -Path $PreviewDir
        $target = Join-Path $PreviewDir $PreviewName
        [System.IO.File]::WriteAllText($target, $text, $utf8)
        "preview: $target"
        return
    }
    $backup = $Path + $backupSuffix
    if ((Test-Path $Path) -and -not (Test-Path $backup)) {
        Copy-Item -Path $Path -Destination $backup
        "backup:  $backup"
    }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllText($Path, $text, $utf8)
    "written: $Path"
}

# --- Windows Terminal -------------------------------------------------------------------

function Get-TerminalSettingsPaths {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    return @($candidates | Where-Object { Test-Path $_ })
}

function New-TabIcon {
    # Draws the ember that marks the tab: a small glowing dot. Returns the file path.
    Add-Type -AssemblyName System.Drawing
    $dir = Join-Path $env:LOCALAPPDATA $styleName
    $file = Join-Path $dir 'glut.png'
    if ($PreviewDir) { $file = Join-Path $PreviewDir 'glut.png'; $dir = $PreviewDir }
    $null = New-Item -ItemType Directory -Force -Path $dir

    $size = 64
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $ember = [System.Drawing.ColorTranslator]::FromHtml([string]$style.ink.ember)

    # glow: from the ember colour in the middle to nothing at the edge
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse(2, 2, $size - 4, $size - 4)
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
    $glow.CenterColor = [System.Drawing.Color]::FromArgb(150, $ember)
    $glow.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, $ember))
    $graphics.FillPath($glow, $path)

    # core: bright centre, ember rim
    $core = New-Object System.Drawing.Drawing2D.GraphicsPath
    $core.AddEllipse(18, 18, $size - 36, $size - 36)
    $fill = New-Object System.Drawing.Drawing2D.PathGradientBrush($core)
    $fill.CenterColor = [System.Drawing.Color]::FromArgb(255, 255, 214, 160)
    $fill.SurroundColors = [System.Drawing.Color[]]@($ember)
    $graphics.FillPath($fill, $core)

    $bitmap.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    return $file
}

function Get-TerminalScheme {
    # The colour scheme: 16 ANSI colours from "palette", the rest from the mode werkbank.
    $base = Get-StyleMode 'werkbank'
    $scheme = [ordered]@{
        name                = $styleName
        background          = [string]$base.background
        foreground          = [string]$base.foreground
        cursorColor         = [string]$base.cursor
    }
    foreach ($p in $style.palette.PSObject.Properties) {
        if ($p.Name -notlike '_*') { $scheme[$p.Name] = [string]$p.Value }
    }
    return $scheme
}

function Get-TerminalTheme {
    # Window chrome: the active tab melts into the terminal, the row behind it is darker,
    # and the window gets a hairline frame in dark brass.
    $t = $style.terminal
    return [ordered]@{
        name   = $styleName
        tab    = [ordered]@{ background = 'terminalBackground'; unfocusedBackground = '#00000000'; showCloseButton = 'hover' }
        tabRow = [ordered]@{ background = "$($t.tabRow)FF"; unfocusedBackground = "$($t.tabRow)FF" }
        window = [ordered]@{ applicationTheme = 'dark'; useMica = $false; frame = "$($t.frame)FF"; unfocusedFrame = "$($t.frameUnfocused)FF" }
    }
}

function Get-TerminalProfile([string]$IconPath) {
    $shell = Join-Path $PSScriptRoot 'style\Shell.ps1'
    return [ordered]@{
        guid        = [string]$style.terminal.profileGuid
        name        = $styleName
        commandline = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoExit -ExecutionPolicy RemoteSigned -File "{0}"' -f $shell
        icon        = $IconPath
        hidden      = $false
    }
}

function Update-TerminalSettings([string]$Path) {
    $wt = Read-SettingsFile $Path
    if (-not $wt) { return }
    $guid = [string]$style.terminal.profileGuid
    if (-not $wt.PSObject.Properties['profiles']) { Set-Prop $wt 'profiles' ([pscustomobject]@{}) }
    if (-not $wt.profiles.PSObject.Properties['defaults']) { Set-Prop $wt.profiles 'defaults' ([pscustomobject]@{}) }
    if (-not $wt.profiles.PSObject.Properties['list']) { Set-Prop $wt.profiles 'list' @() }

    $schemes = @(@($wt.schemes) | Where-Object { $_ -and $_.name -ne $styleName })
    $themes = @(@($wt.themes) | Where-Object { $_ -and $_.name -ne $styleName })
    $profiles = @(@($wt.profiles.list) | Where-Object { $_ -and $_.guid -ne $guid })
    $defaults = $wt.profiles.defaults

    if ($Remove) {
        foreach ($key in $terminalDefaultKeys) { Remove-Prop $defaults $key }
        if ($wt.theme -eq $styleName) { Remove-Prop $wt 'theme' }
        if ($wt.defaultProfile -eq $guid) {
            # back to the default profile from before, if the backup still knows it
            $previous = $null
            $backup = $Path + $backupSuffix
            if (Test-Path $backup) { $old = Read-SettingsFile $backup; if ($old) { $previous = $old.defaultProfile } }
            if (-not $previous -and $profiles.Count -gt 0) { $previous = $profiles[0].guid }
            if ($previous) { Set-Prop $wt 'defaultProfile' $previous } else { Remove-Prop $wt 'defaultProfile' }
        }
    } else {
        $f = $style.font
        $face = [string]$f.fallback
        if (Test-FontInstalled ([string]$f.face)) { $face = "$($f.face), $($f.fallback)" }
        else { "note:    font '$($f.face)' is not installed, using '$($f.fallback)' (scripts\Install-Font.ps1)" }
        $t = $style.terminal

        Set-Prop $defaults 'colorScheme' $styleName
        Set-Prop $defaults 'font' ([ordered]@{ face = $face; size = $f.size; weight = [string]$f.weight; cellHeight = [string]$f.cellHeight })
        Set-Prop $defaults 'padding' ([string]$t.padding)
        Set-Prop $defaults 'cursorShape' ([string]$t.cursorShape)
        Set-Prop $defaults 'cursorHeight' ([int]$t.cursorHeight)
        Set-Prop $defaults 'scrollbarState' 'hidden'
        Set-Prop $defaults 'adjustIndistinguishableColors' 'never'
        Set-Prop $defaults 'intenseTextStyle' 'bold'
        Set-Prop $defaults 'opacity' 100
        Set-Prop $defaults 'useAcrylic' $false

        $schemes += Get-TerminalScheme
        $themes += Get-TerminalTheme
        $profiles = @(Get-TerminalProfile (New-TabIcon)) + $profiles
        Set-Prop $wt 'theme' $styleName
        Set-Prop $wt 'defaultProfile' $guid
    }

    Set-Prop $wt 'schemes' $schemes
    Set-Prop $wt 'themes' $themes
    Set-Prop $wt.profiles 'list' $profiles
    Save-SettingsFile $Path $wt ('terminal-' + (Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $Path))) + '.json')
}

# --- Claude Code ------------------------------------------------------------------------

function Update-ClaudeThemes {
    # One theme file per entry of "claude.themes": ~\.claude\themes\nachtschicht-<mode>.json
    foreach ($entry in $style.claude.themes.PSObject.Properties) {
        $file = Get-ClaudeThemeFile $entry.Name
        if ($Remove) {
            if ((Test-Path $file) -and -not $PreviewDir) { Remove-Item $file; "removed: $file" }
            continue
        }
        $text = ConvertTo-PrettyJson $entry.Value
        if ($PreviewDir) {
            $null = New-Item -ItemType Directory -Force -Path $PreviewDir
            $file = Join-Path $PreviewDir (Split-Path -Leaf $file)
        } else {
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file)
        }
        [System.IO.File]::WriteAllText($file, $text, $utf8)
        "written: $file"
    }
}

function Update-ClaudeSettings {
    # User settings of Claude Code. They also apply to claude-local, which replaces the
    # theme with the warm one for its own sessions (scripts\claude-local.ps1).
    $path = Join-Path $env:USERPROFILE '.claude\settings.json'
    if (Test-Path $path) { $settings = Read-SettingsFile $path; if (-not $settings) { return } }
    else { $settings = [pscustomobject]@{} }
    $themeName = 'custom:' + (Get-ClaudeThemeSlug ([string]$style.claude.cloudMode))

    if ($Remove) {
        foreach ($key in $claudeKeys) { Remove-Prop $settings $key }
        if ($settings.theme -eq $themeName) {
            $previous = $null
            $backup = $path + $backupSuffix
            if (Test-Path $backup) { $old = Read-SettingsFile $backup; if ($old) { $previous = $old.theme } }
            if ($previous) { Set-Prop $settings 'theme' $previous } else { Remove-Prop $settings 'theme' }
        }
    } else {
        Set-Prop $settings 'theme' $themeName
        Set-Prop $settings 'statusLine' (Get-StatusLineSetting)
        Set-Prop $settings 'spinnerVerbs' ([ordered]@{ mode = 'replace'; verbs = @($style.claude.spinnerVerbs) })
    }
    Save-SettingsFile $path $settings 'claude-settings.json'
}

# --- run --------------------------------------------------------------------------------

$terminalFiles = Get-TerminalSettingsPaths
if ($terminalFiles.Count -eq 0) { 'note:    no Windows Terminal settings found, skipping the terminal.' }
foreach ($file in $terminalFiles) { Update-TerminalSettings $file }
Update-ClaudeThemes
Update-ClaudeSettings

if ($Remove) { "$styleName removed. Open a new terminal tab." }
elseif (-not $PreviewDir) { "$styleName applied. Open a new terminal tab; running Claude Code sessions pick the theme up at the next start." }
