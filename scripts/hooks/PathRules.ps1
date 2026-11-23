# One reading of a path for everybody: the guard (GuardRules.ps1), the rights of a session and
# the tools of the agent Unzensiert (lib\AgentLoop.ps1, lib\AgentTools.ps1). A path the guard
# reads differently from the tool that opens it is a way around the guard, so there is only this
# one. Self-contained, because the hook of Claude Code loads it for every call.
# Keep this file ASCII-only. Description: docs\security.md.

function Get-LinkTarget([string]$Path) {
    # Where a junction or symbolic link points to, '' for everything else (also for other
    # reparse points such as the files of OneDrive).
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (@('Junction', 'SymbolicLink') -notcontains [string]$item.LinkType) { return '' }
        return [string](@($item.Target)[0])
    } catch { return '' }
}

function Split-PathParts([string]$Full, [string]$Root) {
    return @($Full.Substring($Root.Length).Split('\') | Where-Object { $_ })
}

function Resolve-RealPath([string]$Full) {
    # $Full with every junction and symbolic link on the way followed; parts that do not exist
    # yet stay as they are. $null when the links lead in a circle or cannot be read.
    $links = 0
    $current = [System.IO.Path]::GetPathRoot($Full)
    if (-not $current) { return $null }
    $parts = @(Split-PathParts $Full $current)
    $i = 0
    while ($i -lt $parts.Count) {
        $next = [System.IO.Path]::Combine($current, $parts[$i])
        try { $attributes = [System.IO.File]::GetAttributes($next) }
        catch {
            for (; $i -lt $parts.Count; $i++) { $current = [System.IO.Path]::Combine($current, $parts[$i]) }
            return $current
        }
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $target = Get-LinkTarget $next
            if ($target) {
                if (++$links -gt 20) { return $null }
                if ($target.StartsWith('\??\')) { $target = $target.Substring(4) }
                try {
                    if (-not [System.IO.Path]::IsPathRooted($target)) { $target = [System.IO.Path]::Combine($current, $target) }
                    $target = [System.IO.Path]::GetFullPath($target)
                } catch { return $null }
                $rest = @()
                if ($i + 1 -lt $parts.Count) { $rest = @($parts[($i + 1)..($parts.Count - 1)]) }
                if ($target.StartsWith('\\')) { return (@($target.TrimEnd('\')) + $rest) -join '\' }
                $current = [System.IO.Path]::GetPathRoot($target)
                $parts = @(Split-PathParts $target $current) + $rest
                $i = 0
                continue
            }
        }
        $current = $next
        $i++
    }
    return $current
}

function Get-PathFacts([string]$Path, [string]$Cwd) {
    # What a path means, as a model writes it: relative to $Cwd, ~ for the user folder, /c/...
    # of Git Bash. Returns @{ ok; kind; full; real; reason }:
    #   kind    file, network (\\server\share), device (\\.\, \\?\, CON ...) or invalid
    #   full    the full path, real: the same with junctions and links followed
    #   ok      $false for device and invalid: nothing may open such a path
    $r = @{ ok = $false; kind = 'invalid'; full = ''; real = ''; reason = '' }
    $p = ([string]$Path).Trim().Trim('"', "'").Trim()
    if (-not $p) { $r.reason = 'the path is empty'; return $r }
    if ($p -match '[\x00-\x1F\x7F]') { $r.reason = 'the path holds control characters'; return $r }
    if ($p -ceq '~' -or $p.StartsWith('~/') -or $p.StartsWith('~\')) { $p = $env:USERPROFILE + $p.Substring(1) }
    if ($p -match '^/([a-zA-Z])(/.*)?$') { $p = $Matches[1] + ':' + [string]$Matches[2] }
    $p = $p.Replace('/', '\')
    if ($p -match '^\\\\[?.](\\|$)' -or $p -match '^\\\?\?\\') { $r.kind = 'device'; $r.reason = 'device paths (\\?\, \\.\) are not opened'; return $r }
    $network = $p.StartsWith('\\')
    if (-not $network) {
        if ($p -match '^[a-zA-Z]:$') { $p += '\' }
        if ($p -match '^[a-zA-Z]:[^\\]') { $r.reason = 'a drive needs a backslash after the colon'; return $r }
        if ($p.LastIndexOf(':') -gt 1 -or ($p.IndexOf(':') -ge 0 -and $p -notmatch '^[a-zA-Z]:')) { $r.reason = 'a colon inside a path names a data stream, which is not opened'; return $r }
    }
    if ($p -match '[*?<>|"]') { $r.reason = 'the path holds characters no file name may have (* ? < > | ")'; return $r }
    try {
        if (-not $network -and $p.StartsWith('\')) {
            # no drive: the drive of the project folder
            $root = [System.IO.Path]::GetPathRoot($Cwd)
            if (-not $root -or $root.StartsWith('\\')) { $root = "$env:SystemDrive\" }
            $p = $root.TrimEnd('\') + $p
        } elseif (-not [System.IO.Path]::IsPathRooted($p)) { $p = [System.IO.Path]::Combine($Cwd, $p) }
        $full = [System.IO.Path]::GetFullPath($p)
    } catch { $r.reason = 'this is no valid path'; return $r }
    if ($full -match '^\\\\[?.]\\') { $r.kind = 'device'; $r.reason = 'names such as CON, NUL or COM1 are devices'; return $r }
    if ($full -match '\\(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9]|CONIN\$|CONOUT\$)\s*(\.[^\\]*)?(\\|$)') { $r.kind = 'device'; $r.reason = 'names such as CON, NUL or COM1 are devices'; return $r }
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    $r.full = $full
    if ($full.StartsWith('\\')) {
        $r.ok = $true
        $r.real = $full
        # a project that lies on a network drive itself may use its own files
        if ($Cwd -and $Cwd.StartsWith('\\') -and (Test-PathInside $full $Cwd)) { $r.kind = 'file' } else { $r.kind = 'network' }
        return $r
    }
    $real = Resolve-RealPath $full
    if (-not $real) { $r.reason = 'a link on the way leads in a circle or cannot be read'; return $r }
    $r.real = $real
    $r.ok = $true
    if ($real.StartsWith('\\')) { $r.kind = 'network' } else { $r.kind = 'file' }
    return $r
}

function ConvertTo-PosixPath([string]$Full) {
    # E:\Projekte\x as Git Bash names it: /e/Projekte/x. '' for a folder on another computer.
    if ($Full -notmatch '^([a-zA-Z]):[\\/]?(.*)$') { return '' }
    return ('/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2].Replace('\', '/')).TrimEnd('/')
}

function ConvertFrom-PosixParts($Parts) {
    # The Windows path of the parts of a path below the root of Git Bash: the drives are /c, /d ...,
    # /tmp is the temp folder. '' for everything else (the folder of Git Bash itself, /proc, /dev).
    if ($Parts.Count -eq 0) { return '' }
    $first = ([string]$Parts[0]).ToLowerInvariant()
    $from = 1
    if ($first -ceq 'cygdrive' -and $Parts.Count -gt 1) { $first = ([string]$Parts[1]).ToLowerInvariant(); $from = 2 }
    if ($first -cmatch '^[a-z]$') { $base = $first.ToUpperInvariant() + ':\' }
    elseif ($first -ceq 'tmp' -and $from -eq 1) { $base = $env:TEMP.TrimEnd('\') + '\' }
    else { return '' }
    $rest = @()
    if ($Parts.Count -gt $from) { $rest = @($Parts[$from..($Parts.Count - 1)]) }
    return $base + ($rest -join '\')
}

function Get-MountDepth([string]$Folder) {
    # How many parts of /c/Users/... belong to the place where Git Bash hangs a folder in: one for a
    # drive, more for the temp folder (/tmp) and its own folder (/). Above it ".." leads elsewhere.
    $depth = 1
    $mounts = @($env:TEMP, $env:TMP, $script:GitBashRoot)
    foreach ($m in @($mounts | Where-Object { $_ } | Select-Object -Unique)) {
        try { $full = [System.IO.Path]::GetFullPath([string]$m).TrimEnd('\') } catch { continue }
        if (Test-PathInside $Folder $full) { $depth = [Math]::Max($depth, @($full.Split('\')).Count) }
    }
    return $depth
}

# the folder of Git for Windows (its /), known once Git Bash was looked for
$script:GitBashRoot = ''
foreach ($c in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' }))) {
    if ($c -and [System.IO.File]::Exists("$c\Git\usr\bin\bash.exe")) { $script:GitBashRoot = "$c\Git"; break }
}

function Resolve-BashPath([string]$Word, [string]$Folder) {
    # What a word means as a path to Git Bash in $Folder. Its drives lie below one root, so a ".."
    # above a drive leads to the others (../../../c/Users, /usr/../c/Users). Returns
    # @{ ok; kind; full; real }, kind:
    #   file     full and real as Get-PathFacts gives them
    #   shell    inside the folder of Git Bash itself (/usr, /etc)
    #   name     no path of a file (a colon in it, as in HEAD:a.txt)
    #   device   /proc, /dev ...      network   another computer
    #   odd      cannot be told: ~name, ~+, c:name, control characters, ".." out of a drive or behind
    #            a link
    $r = @{ ok = $false; kind = 'odd'; full = ''; real = '' }
    $w = $Word
    if (-not $w -or $w -match '[\x00-\x1F\x7F]') { return $r }
    if ($w -match '^[\\/]{2}') { $r.kind = 'network'; if ($w -match '^[\\/]{2}[?.]') { $r.kind = 'device' }; return $r }
    if ($w -match '^[a-zA-Z]:') {
        # the Windows spelling keeps its drive
        if ($w -match '^[a-zA-Z]:[^\\/]') { return $r }
        $w = '/' + $w.Substring(0, 1) + $w.Substring(2)
    }
    # a backslash separates as well
    $w = $w.Replace('\', '/')
    $depth = 1
    if ($w.StartsWith('~')) {
        if ($w -cnotmatch '^~(/|$)') { return $r }
        $home1 = ConvertTo-PosixPath $env:USERPROFILE
        if ($env:HOME) { $home1 = $env:HOME.Replace('\', '/'); if ($home1 -match '^[a-zA-Z]:') { $home1 = ConvertTo-PosixPath $env:HOME } }
        if (-not $home1.StartsWith('/')) { return $r }
        $w = $home1 + $w.Substring(1)
    }
    if ($w.IndexOf(':') -ge 0) { $r.kind = 'name'; return $r }
    if (-not $w.StartsWith('/')) {
        $base = ConvertTo-PosixPath $Folder
        if (-not $base) {
            $f = Get-PathFacts $w $Folder                         # the project lies on another computer itself
            if ($f.ok) { $r.ok = $true; $r.kind = $f.kind; $r.full = $f.full; $r.real = $f.real }
            return $r
        }
        $depth = Get-MountDepth $Folder
        $w = $base + '/' + $w
    }
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in $w.Split('/')) {
        if ($p -ceq '' -or $p -ceq '.') { continue }
        if ($p -cne '..') { $null = $parts.Add($p); continue }
        # out of the drive, /tmp or /usr: where that leads depends on how Git Bash is set up
        if ($parts.Count -le $depth) { return $r }
        # behind a link ".." leads to the folder above its target
        $here = ConvertFrom-PosixParts $parts
        if ($here) {
            try { if (([System.IO.File]::GetAttributes($here) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and (Get-LinkTarget $here)) { return $r } } catch {}
        }
        $parts.RemoveAt($parts.Count - 1)
    }
    if ($parts.Count -gt 0 -and @('proc', 'dev', 'sys') -contains [string]$parts[0]) {
        if (($parts -join '/') -ceq 'dev/null') { $r.ok = $true; $r.kind = 'shell'; return $r }
        $r.kind = 'device'
        return $r
    }
    $full = ConvertFrom-PosixParts $parts
    if (-not $full) { $r.ok = $true; $r.kind = 'shell'; $r.full = '<shell-root>\' + ($parts -join '\'); $r.real = $r.full; return $r }
    try { $full = [System.IO.Path]::GetFullPath($full) } catch { return $r }
    if ($full -match '^\\\\[?.]\\') { $r.kind = 'device'; return $r }
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    $real = Resolve-RealPath $full
    if (-not $real) { return $r }
    $r.full = $full
    $r.real = $real
    $r.kind = 'file'
    if ($real.StartsWith('\\')) { $r.kind = 'network' }
    $r.ok = $true
    return $r
}

function Expand-WildPath([string]$Wild) {
    # What a full path with wildcards (* ?) meets: @{ ok; links; paths }. links: a junction or symbolic
    # link is among it, so what it leads to is not what the path says. ok is $false if there is too much
    # to look at.
    $r = @{ ok = $false; links = $false; paths = @() }
    $parts = $Wild.Split('\')
    if ($parts[0] -notmatch '^[a-zA-Z]:$') { return $r }
    $dirs = @($parts[0] + '\')
    $open = $false
    $looked = 0
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $p = $parts[$i]
        $next = New-Object System.Collections.ArrayList
        foreach ($d in $dirs) {
            if ($p -notmatch '[*?]') {
                # a part no file name may have: nothing is met, but nothing is known either
                try { $e = [System.IO.Path]::Combine($d, $p) } catch { return $r }
                try { $a = [System.IO.File]::GetAttributes($e) } catch { continue }
                if ($open -and ($a -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and (Get-LinkTarget $e)) { $r.links = $true }
                $null = $next.Add($e)
                continue
            }
            $open = $true
            try {
                foreach ($e in [System.IO.Directory]::EnumerateFileSystemEntries($d)) {
                    if (++$looked -gt 5000) { return $r }
                    if ($e.Substring($e.LastIndexOf('\') + 1) -notlike $p) { continue }
                    $a = [System.IO.File]::GetAttributes($e)
                    if (($a -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and (Get-LinkTarget $e)) { $r.links = $true }
                    if ($i -eq $parts.Count - 1 -or ($a -band [System.IO.FileAttributes]::Directory) -ne 0) { $null = $next.Add($e) }
                }
            } catch {}
        }
        $dirs = $next
    }
    $r.ok = $true
    $r.paths = @($dirs)
    return $r
}

function Test-WildLinks([string]$Wild) {
    # True if a full path with wildcards meets a link, or too much to look at.
    $r = Expand-WildPath $Wild
    return (-not $r.ok -or $r.links)
}

function Test-TreeLinks([string]$Folder, [bool]$Recurse) {
    # True if a folder (with $Recurse everything below it) holds a junction or symbolic link, or too
    # much to look at.
    $stack = New-Object System.Collections.Stack
    $stack.Push($Folder)
    $looked = 0
    while ($stack.Count -gt 0) {
        $dir = [string]$stack.Pop()
        try {
            foreach ($e in (New-Object System.IO.DirectoryInfo($dir)).EnumerateFileSystemInfos()) {
                if (++$looked -gt 20000) { return $true }
                if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and (Get-LinkTarget $e.FullName)) { return $true }
                if ($Recurse -and ($e.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) { $stack.Push($e.FullName) }
            }
        } catch {}
    }
    return $false
}

function Get-ShellPath([string]$Tool, [string]$Word, [string]$Folder) {
    # A path in a command as the shell of the tool reads it.
    if ($Tool -eq 'Bash') { return (Resolve-BashPath $Word $Folder) }
    return (Get-PathFacts $Word $Folder)
}

function Test-PathInside([string]$Path, [string]$Root) {
    # True if $Path is $Root or lies below it.
    if (-not $Path -or -not $Root) { return $false }
    if ($Path -ieq $Root) { return $true }
    return $Path.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}
