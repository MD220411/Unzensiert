# Installs the font of the active look ("font" in config\styles\<name>.json) for the
# current user. No administrator rights needed, nothing is installed system-wide.
# Idempotent: files that are already installed are skipped. Afterwards run
# scripts\Install-Style.ps1 so that Windows Terminal uses the font. The archive comes over https
# only and must have the size and SHA-256 of "source" in the style file.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Install-Font.ps1

. "$PSScriptRoot\_common.ps1"

$font = (Get-StyleConfig).font
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$regKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$workDir = Join-Path $env:TEMP 'style-font'

if (Test-FontInstalled ([string]$font.face)) {
    "already installed: $($font.face)"
    exit 0
}

# --- download and unpack --------------------------------------------------------------
if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir }
$null = New-Item -ItemType Directory -Force -Path $workDir
$zip = Join-Path $workDir 'font.zip'
"downloading $($font.source.url)"
Save-VerifiedDownload ([string]$font.source.url) $zip ([long]$font.source.size) ([string]$font.source.sha256)
Expand-Archive -Path $zip -DestinationPath (Join-Path $workDir 'unpacked') -Force

# one file per name; the archive may hold the same font in several folders
$files = @(Get-ChildItem -Path (Join-Path $workDir 'unpacked') -Recurse -Filter ([string]$font.source.pattern) |
    Sort-Object Name -Unique)
if ($files.Count -eq 0) { throw "No file matching '$($font.source.pattern)' in the archive $($font.source.url)." }

# --- install for this user ------------------------------------------------------------
# Same places Windows itself uses for "Install" (per user): the file goes to
# %LOCALAPPDATA%\Microsoft\Windows\Fonts and is listed under HKCU. AddFontResource makes
# it usable right away, without signing out.
Add-Type -Namespace StyleFont -Name Gdi -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string path);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
'@

$null = New-Item -ItemType Directory -Force -Path $fontDir
if (-not (Test-Path $regKey)) { $null = New-Item -Path $regKey -Force }
foreach ($file in $files) {
    $target = Join-Path $fontDir $file.Name
    if (-not (Test-Path $target)) { Copy-Item -Path $file.FullName -Destination $target }
    Set-ItemProperty -Path $regKey -Name "$($file.BaseName) (TrueType)" -Value $target
    $null = [StyleFont.Gdi]::AddFontResourceW($target)
}
# WM_FONTCHANGE to all windows, so running programs notice the new fonts
$result = [IntPtr]::Zero
$null = [StyleFont.Gdi]::SendMessageTimeoutW([IntPtr]0xFFFF, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result)

Remove-Item -Recurse -Force $workDir
"installed $($files.Count) files of '$($font.face)' ($($font.source.license)) to $fontDir"
'next: powershell -ExecutionPolicy Bypass -File scripts\Install-Style.ps1'
