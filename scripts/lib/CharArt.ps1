# Pictures made of characters instead of pixels (look "Ausbruch", docs\stil.md): a word is
# set in the block font of "art.font", every block is filled with a random character and
# coloured along the colour wheel. Around the letters characters are sprayed like paint,
# the last letters crumble, and to the right characters break out and fly away, getting
# lighter and fainter on the way. No two pictures are the same.
#
# Dot-sourced by lib\Style.ps1 (it needs Get-StyleConfig, Get-RainbowRgb, Get-RgbCode,
# Get-MixedRgb). Settings: "art" in the active style. Keep this file ASCII-only.

function Get-ArtMask([string]$Text, $Font) {
    # The word as rows of booleans: $true where the font has a block. One empty column
    # between letters; characters the font does not know become a space.
    $glyphs = @()
    foreach ($ch in $Text.ToUpperInvariant().ToCharArray()) {
        $key = [string]$ch
        $entry = $Font.PSObject.Properties[$key]
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

function Get-CharArt([string]$Text, [int]$MaxScale, [int]$Width, [string]$BackgroundHex, [int]$Seed = -1) {
    # Lines of the picture, each with escape sequences, 2 spaces indented. The widest
    # scale up to $MaxScale that fits into $Width columns is used; empty if not even
    # scale 1 fits. $Seed >= 0 gives the same picture every time (for tests).
    $art = (Get-StyleConfig).art
    if (-not $art -or -not $Text) { return @() }
    $mask = @(Get-ArtMask $Text $art.font)
    if ($mask.Count -eq 0) { return @() }
    if ($Seed -ge 0) { $rnd = New-Object System.Random($Seed) } else { $rnd = New-Object System.Random }

    $indent = 2
    $maskWidth = $mask[0].Length
    $scale = [Math]::Max(1, $MaxScale)
    while ($scale -gt 1 -and ($maskWidth * $scale + $indent + 1) -gt $Width) { $scale-- }
    if (($maskWidth * $scale + $indent + 1) -gt $Width) { return @() }

    $fill = [string]$art.fill
    $spray = [string]$art.spray
    $mid = [string]$art.flightMid
    $far = [string]$art.flightFar
    # thinner strokes drown in spray: less of it when the window forced a smaller scale
    $sprayChance = [double]$art.sprayChance * $scale / [Math]::Max(1, $MaxScale)
    $density = [double]$art.flightDensity
    $reach = [double]$art.flightReach
    $span = [double]$art.gradientSpan
    $bg = [int[]](ConvertTo-RgbParts $BackgroundHex)
    $offset = $rnd.NextDouble()

    $logoW = $maskWidth * $scale
    $cols = $Width - $indent - 1
    $pad = 1
    $rows = $mask.Count + 2 * $pad
    $freeW = [Math]::Max(1, $cols - $logoW)

    # $grid[y + 1][x + 1]: is there a block at canvas cell (x, y)? One spare cell on every
    # side, so the neighbours of the edge cells can be looked up without checks.
    $grid = @()
    for ($y = -1; $y -le $rows; $y++) {
        $line = New-Object bool[] ($logoW + 3)
        $my = $y - $pad
        if ($my -ge 0 -and $my -lt $mask.Count) {
            for ($x = 0; $x -lt $logoW; $x++) { $line[$x + 1] = $mask[$my][[int][Math]::Floor($x / $scale)] }
        }
        $grid += , $line
    }

    $reset = [string][char]27 + '[0m'
    $lines = @()
    for ($y = 0; $y -lt $rows; $y++) {
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.Append(' ' * $indent)
        $spaces = 0
        for ($x = 0; $x -lt $cols; $x++) {
            $ch = $null
            $fade = 0.0
            $bold = $false
            $pos = $offset + $span * ($x + 1.5 * $y) / $logoW
            if ($x -lt $logoW -and $grid[$y + 1][$x + 1]) {
                # the letters: dense characters; the last fifth crumbles away
                $ch = $fill[$rnd.Next($fill.Length)]
                $bold = $true
                $tail = ($x / $logoW - 0.8) / 0.2
                if ($tail -gt 0 -and $rnd.NextDouble() -lt 0.35 * $tail * $tail) { $ch = $mid[$rnd.Next($mid.Length)]; $bold = $false; $fade = 0.25 }
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
                    if ($y -lt $pad -or $y -ge $rows - $pad) { $p *= 0.4 }
                    if ($rnd.NextDouble() -lt $p) {
                        if ($d -lt 0.18) { $ch = $fill[$rnd.Next($fill.Length)] }
                        elseif ($d -lt 0.55) { $ch = $mid[$rnd.Next($mid.Length)] }
                        else { $ch = $far[$rnd.Next($far.Length)] }
                        $fade = 0.15 + 0.6 * $d
                    }
                }
            }
            if ($null -eq $ch) { $spaces++; continue }
            if ($spaces -gt 0) { $null = $sb.Append(' ' * $spaces); $spaces = 0 }
            $rgb = Get-MixedRgb (Get-RainbowRgb $pos) $bg $fade
            $null = $sb.Append((Get-RgbCode $rgb -Bold:$bold)).Append($ch).Append($reset)
        }
        $lines += $sb.ToString()
    }
    return $lines
}
