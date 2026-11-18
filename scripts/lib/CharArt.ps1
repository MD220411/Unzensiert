# Pictures made of characters instead of pixels (look "Breakout", docs\style.md): a word is
# set in the block font of "art.font", every block is filled with a random character and
# coloured along the colour wheel, lit from above and darker towards the bottom. Behind
# the letters lies a shadow, paint runs down from their lower edges, spray settles around
# them, the last letters crumble, and to the right characters break out and fly away,
# getting lighter and fainter on the way, with a spark here and there. No two pictures
# are the same.
#
# A picture is first a canvas of cells (Get-CharArtCells), then text for the terminal
# (Format-ArtCells) or a PNG (Save-ArtCellsImage, the wall behind the terminal that
# scripts\Install-Style.ps1 draws with New-CharWall).
#
# Dot-sourced by lib\Style.ps1 (it needs Get-StyleConfig, Get-RainbowRgb, Get-RgbCode,
# Get-MixedRgb, ConvertTo-RgbParts). Settings: "art" in the active style. ASCII only.

function Get-ArtMask([string]$Text, $Font) {
    # The word as rows of booleans: $true where the font has a block. One empty column
    # between letters; characters the font does not know become a space.
    $glyphs = @()
    foreach ($ch in $Text.ToUpperInvariant().ToCharArray()) {
        $entry = $Font.PSObject.Properties[[string]$ch]
        if (-not $entry) { $entry = $Font.PSObject.Properties[' '] }
        if ($entry) { $glyphs += , @($entry.Value) }
    }
    if ($glyphs.Count -eq 0) { return @() }
    $height = @($glyphs[0]).Count
    $rows = @()
    for ($y = 0; $y -lt $height; $y++) {
        $row = New-Object System.Collections.Generic.List[bool]
        for ($g = 0; $g -lt $glyphs.Count; $g++) {
            $line = [string]$glyphs[$g][$y]
            $w = 0
            foreach ($r in $glyphs[$g]) { if (([string]$r).Length -gt $w) { $w = ([string]$r).Length } }
            for ($x = 0; $x -lt $w; $x++) { $row.Add(($x -lt $line.Length) -and ($line[$x] -ne ' ')) }
            if ($g -lt $glyphs.Count - 1) { $row.Add($false) }
        }
        $rows += , $row.ToArray()
    }
    return $rows
}

function Get-ArtValue($Art, [string]$Name, $Default) {
    # A setting of "art", or $Default for style files that do not have it.
    $p = $Art.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $Default
}

function New-ArtCell([char]$Char, [int[]]$Rgb, [bool]$Bold = $false) {
    return , @($Char, $Rgb, $Bold)
}

function Get-CharArtCells([string]$Text, [int]$MaxScale, [int]$Width, [string]$BackgroundHex, [int]$Seed = -1, [string]$MonoHex = '') {
    # The picture as a canvas: an array of rows, each an array of cells; a cell is
    # @(char, rgb, bold) or $null. The widest scale up to $MaxScale whose letters fit into
    # $Width columns (minus 3 for indent and edge) is used; $null if not even scale 1
    # fits. $MonoHex paints everything in one colour instead of the wheel. $Seed >= 0
    # gives the same picture every time (for tests).
    $art = (Get-StyleConfig).art
    if (-not $art -or -not $Text) { return $null }
    $mask = @(Get-ArtMask $Text $art.font)
    if ($mask.Count -eq 0) { return $null }
    if ($Seed -ge 0) { $rnd = New-Object System.Random($Seed) } else { $rnd = New-Object System.Random }

    $maskWidth = $mask[0].Length
    $scale = [Math]::Max(1, $MaxScale)
    while ($scale -gt 1 -and ($maskWidth * $scale + 3) -gt $Width) { $scale-- }
    if (($maskWidth * $scale + 3) -gt $Width) { return $null }

    $fill = [string]$art.fill
    $spray = [string]$art.spray
    $mid = [string]$art.flightMid
    $far = [string]$art.flightFar
    $shadowChars = [string](Get-ArtValue $art 'shadow' '')
    $dripBody = [string](Get-ArtValue $art 'dripBody' '|')
    $dripEnd = [string](Get-ArtValue $art 'dripEnd' '.')
    $dripChance = [double](Get-ArtValue $art 'dripChance' 0)
    $dripMax = [int](Get-ArtValue $art 'dripLength' 3)
    $sparkChars = [string](Get-ArtValue $art 'sparkle' '')
    $sparkChance = [double](Get-ArtValue $art 'sparkleChance' 0)
    $light = [double](Get-ArtValue $art 'light' 0)
    # thinner strokes drown in spray: less of it when the window forced a smaller scale
    $sprayChance = [double]$art.sprayChance * $scale / [Math]::Max(1, $MaxScale)
    $density = [double]$art.flightDensity
    $reach = [double]$art.flightReach
    $span = [double]$art.gradientSpan
    $bg = [int[]](ConvertTo-RgbParts $BackgroundHex)
    $white = [int[]]@(255, 255, 255)
    $mono = $null
    if ($MonoHex) { $mono = [int[]](ConvertTo-RgbParts $MonoHex) }
    $offset = $rnd.NextDouble()

    $logoW = $maskWidth * $scale
    $cols = $Width - 3
    $padTop = 1
    $padBottom = 1
    if ($dripChance -gt 0) { $padBottom = 1 + $dripMax }
    $height = $mask.Count
    $rows = $height + $padTop + $padBottom
    $freeW = [Math]::Max(1, $cols - $logoW)

    # $grid[y + 1][x + 1]: is there a block at canvas cell (x, y)? Spare cells on every
    # side, so neighbours of edge cells (and the shadow two to the left) need no checks.
    $grid = @()
    for ($y = -1; $y -le $rows; $y++) {
        $line = New-Object bool[] ($logoW + 4)
        $my = $y - $padTop
        if ($my -ge 0 -and $my -lt $height) {
            for ($x = 0; $x -lt $logoW; $x++) { $line[$x + 1] = $mask[$my][[int][Math]::Floor($x / $scale)] }
        }
        $grid += , $line
    }

    # paint running down from lower edges: one drip per block column at most
    $drips = @()
    for ($y = 0; $y -lt $rows; $y++) { $drips += , (New-Object object[] $logoW) }
    if ($dripChance -gt 0) {
        for ($y = 0; $y -lt $rows; $y++) {
            for ($mx = 0; $mx -lt $maskWidth; $mx++) {
                $x = $mx * $scale + $rnd.Next($scale)
                if (-not $grid[$y + 1][$x + 1] -or $grid[$y + 2][$x + 1]) { continue }
                if ($rnd.NextDouble() -ge $dripChance) { continue }
                $len = 1 + $rnd.Next($dripMax)
                for ($k = 1; $k -le $len; $k++) {
                    $yy = $y + $k
                    if ($yy -ge $rows -or $grid[$yy + 1][$x + 1]) { break }
                    $last = ($k -eq $len) -or ($yy + 1 -lt $rows -and $grid[$yy + 2][$x + 1])
                    if ($last) { $ch = $dripEnd[$rnd.Next($dripEnd.Length)] } else { $ch = $dripBody[$rnd.Next($dripBody.Length)] }
                    $drips[$yy][$x] = @($ch, $k)
                    if ($last) { break }
                }
            }
        }
    }

    $canvas = @()
    for ($y = 0; $y -lt $rows; $y++) {
        $row = New-Object object[] $cols
        $my = $y - $padTop
        for ($x = 0; $x -lt $cols; $x++) {
            # first what goes into the cell, then (only if anything) its colour: $fade
            # blends towards the background, $shine towards white
            $ch = $null
            $fade = 0.0
            $shine = 0.0
            $bold = $false
            if ($x -lt $logoW -and $grid[$y + 1][$x + 1]) {
                # the letters: dense characters, lit from above; the last fifth crumbles
                $t = 0.5
                if ($height -gt 1) { $t = $my / ($height - 1) }
                $ch = $fill[$rnd.Next($fill.Length)]
                $shine = $light * (1 - $t)
                $fade = 0.25 * $light * $t
                $bold = $true
                $tail = ($x / $logoW - 0.8) / 0.2
                if ($tail -gt 0 -and $rnd.NextDouble() -lt 0.35 * $tail * $tail) { $ch = $mid[$rnd.Next($mid.Length)]; $shine = 0; $fade = 0.25; $bold = $false }
            } elseif ($x -lt $logoW -and $null -ne $drips[$y][$x]) {
                # paint running down
                $d = $drips[$y][$x]
                $ch = $d[0]
                $fade = 0.05 + 0.15 * $d[1]
            } elseif ($shadowChars -and $x -lt $logoW + $scale + 1 -and $x -ge $scale -and $grid[$y][$x + 1 - $scale]) {
                # the shadow: down and to the right, as if the letters stood off the wall
                $ch = $shadowChars[$rnd.Next($shadowChars.Length)]
                $fade = 0.72
            } elseif ($x -lt $logoW + 1) {
                # paint spray right next to the letters
                $near = $grid[$y + 1][$x] -or $grid[$y + 1][$x + 2] -or $grid[$y][$x + 1] -or $grid[$y + 2][$x + 1]
                if ($near -and $rnd.NextDouble() -lt $sprayChance) { $ch = $spray[$rnd.Next($spray.Length)]; $fade = 0.45 }
            }
            if ($null -eq $ch -and $x -ge $logoW) {
                # breaking out: characters fly off to the right, lighter and fainter
                $d = ($x - $logoW) / ($freeW * $reach)
                if ($d -lt 1) {
                    $p = $density * [Math]::Pow(1 - $d, 1.6)
                    if ($y -lt $padTop -or $y -ge $padTop + $height) { $p *= 0.4 }
                    if ($rnd.NextDouble() -lt $p) {
                        if ($d -lt 0.18) { $ch = $fill[$rnd.Next($fill.Length)] }
                        elseif ($d -lt 0.55) { $ch = $mid[$rnd.Next($mid.Length)] }
                        else { $ch = $far[$rnd.Next($far.Length)] }
                        $fade = 0.15 + 0.6 * $d
                    }
                }
            }
            if ($null -eq $ch -and $sparkChars -and $rnd.NextDouble() -lt $sparkChance) {
                # a spark: bright, anywhere in the free space
                $ch = $sparkChars[$rnd.Next($sparkChars.Length)]
                $shine = 0.45
                $bold = $true
            }
            if ($null -eq $ch) { continue }
            if ($mono) { $rgb = $mono } else { $rgb = Get-RainbowRgb ($offset + $span * ($x + 1.5 * $y) / $logoW) }
            if ($shine -gt 0) { $rgb = Get-MixedRgb $rgb $white $shine }
            if ($fade -gt 0) { $rgb = Get-MixedRgb $rgb $bg $fade }
            $row[$x] = @($ch, $rgb, $bold)
        }
        $canvas += , $row
    }
    return $canvas
}

function Format-ArtCells($Canvas, [int]$Indent = 2) {
    # The canvas as terminal lines with escape sequences.
    $reset = [string][char]27 + '[0m'
    $lines = @()
    foreach ($row in $Canvas) {
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.Append(' ' * $Indent)
        $spaces = 0
        foreach ($cell in $row) {
            if ($null -eq $cell) { $spaces++; continue }
            if ($spaces -gt 0) { $null = $sb.Append(' ' * $spaces); $spaces = 0 }
            $null = $sb.Append((Get-RgbCode $cell[1] -Bold:$cell[2])).Append($cell[0]).Append($reset)
        }
        $lines += $sb.ToString()
    }
    return $lines
}

function Get-CharArt([string]$Text, [int]$MaxScale, [int]$Width, [string]$BackgroundHex, [int]$Seed = -1, [string]$MonoHex = '') {
    # Lines of the picture, 2 spaces indented; empty if the window is too narrow.
    $canvas = Get-CharArtCells $Text $MaxScale $Width $BackgroundHex $Seed $MonoHex
    if ($null -eq $canvas) { return @() }
    return (Format-ArtCells $canvas 2)
}

function New-CharWall([int]$Cols, [int]$Rows, [string]$Text, [string]$BackgroundHex, [int]$Seed = -1) {
    # A wall of characters for the background of the terminal: the picture of $Text in
    # the lower right corner, around it characters sprayed on the wall, dense in the
    # corner and thinning out towards the upper left, where the text of the session is.
    $art = (Get-StyleConfig).art
    if ($Seed -ge 0) { $rnd = New-Object System.Random($Seed) } else { $rnd = New-Object System.Random }
    $bg = [int[]](ConvertTo-RgbParts $BackgroundHex)
    $fill = [string]$art.fill
    $mid = [string]$art.flightMid
    $far = [string]$art.flightFar
    $offset = $rnd.NextDouble()
    $wall = @()
    for ($y = 0; $y -lt $Rows; $y++) { $wall += , (New-Object object[] $Cols) }

    $mask = @(Get-ArtMask $Text $art.font)
    $pic = $null
    if ($mask.Count -gt 0) { $pic = Get-CharArtCells $Text 2 ($mask[0].Length * 2 + 3 + 12) $BackgroundHex $rnd.Next() }
    if ($pic) {
        $top = $Rows - $pic.Count
        $left = $Cols - $pic[0].Count - 1
        for ($y = 0; $y -lt $pic.Count; $y++) {
            for ($x = 0; $x -lt $pic[$y].Count; $x++) {
                if ($top + $y -ge 0 -and $left + $x -ge 0 -and $pic[$y][$x]) { $wall[$top + $y][$left + $x] = $pic[$y][$x] }
            }
        }
    }
    for ($y = 0; $y -lt $Rows; $y++) {
        for ($x = 0; $x -lt $Cols; $x++) {
            if ($wall[$y][$x]) { continue }
            $dx = 1 - $x / $Cols
            $dy = 1 - $y / $Rows
            $d = [Math]::Sqrt($dx * $dx + $dy * $dy) / [Math]::Sqrt(2)
            if ($rnd.NextDouble() -ge 0.5 * [Math]::Pow(1 - $d, 2.4)) { continue }
            if ($d -lt 0.25) { $ch = $fill[$rnd.Next($fill.Length)] }
            elseif ($d -lt 0.55) { $ch = $mid[$rnd.Next($mid.Length)] }
            else { $ch = $far[$rnd.Next($far.Length)] }
            $rgb = Get-MixedRgb (Get-RainbowRgb ($offset + 1.2 * ($x + 1.5 * $y) / $Cols)) $bg (0.2 + 0.5 * $d)
            $wall[$y][$x] = New-ArtCell $ch $rgb ($d -lt 0.25)
        }
    }
    return $wall
}

function Save-ArtCellsImage($Canvas, [string]$Path, [string]$FontFace, [int]$FontPixels = 18) {
    # Draws a canvas into a PNG with a transparent background, one character per cell.
    Add-Type -AssemblyName System.Drawing
    $cw = [int][Math]::Ceiling($FontPixels * 0.62)
    $ch = [int][Math]::Ceiling($FontPixels * 1.3)
    $rows = $Canvas.Count
    $cols = $Canvas[0].Count
    $bitmap = New-Object System.Drawing.Bitmap(($cols * $cw), ($rows * $ch))
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $regular = New-Object System.Drawing.Font($FontFace, $FontPixels, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $bold = New-Object System.Drawing.Font($FontFace, $FontPixels, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    for ($y = 0; $y -lt $rows; $y++) {
        for ($x = 0; $x -lt $cols; $x++) {
            $cell = $Canvas[$y][$x]
            if ($null -eq $cell) { continue }
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, $cell[1][0], $cell[1][1], $cell[1][2]))
            $font = $regular
            if ($cell[2]) { $font = $bold }
            $g.DrawString([string]$cell[0], $font, $brush, [single]($x * $cw - 2), [single]($y * $ch))
            $brush.Dispose()
        }
    }
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $regular.Dispose(); $bold.Dispose(); $g.Dispose(); $bitmap.Dispose()
}
