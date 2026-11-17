# Draws files\error.png of the screenshot task: a terminal window with two calls of
# timesum.py that go wrong. What the calls are is only in the picture, not in the prompt.
# Running it again gives the same picture.
#
#   powershell -ExecutionPolicy Bypass -File benchmark\tasks\screenshot\Make-Image.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$lines = @(
    @{ Text = 'PS C:\work\timesheet> python timesum.py 1h30m 2:45 0.5h'; Color = 'White' },
    @{ Text = "error: not a duration: '2:45'"; Color = 'Salmon' },
    @{ Text = 'PS C:\work\timesheet> python timesum.py 50m 50m'; Color = 'White' },
    @{ Text = '1h 100m'; Color = 'Gainsboro' },
    @{ Text = 'PS C:\work\timesheet> _'; Color = 'White' }
)

$width = 900
$lineHeight = 34
$top = 52
$height = $top + $lines.Count * $lineHeight + 20
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(12, 12, 12))

# title bar
$graphics.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(43, 43, 43))), 0, 0, $width, 36)
$titleFont = New-Object System.Drawing.Font 'Segoe UI', 11
$graphics.DrawString('Windows PowerShell', $titleFont, [System.Drawing.Brushes]::Gainsboro, 12, 8)

$font = New-Object System.Drawing.Font 'Consolas', 16
for ($i = 0; $i -lt $lines.Count; $i++) {
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromName($lines[$i].Color))
    $graphics.DrawString($lines[$i].Text, $font, $brush, 12, ($top + $i * $lineHeight))
}

$target = Join-Path $PSScriptRoot 'files\error.png'
$bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
"written: $target"
