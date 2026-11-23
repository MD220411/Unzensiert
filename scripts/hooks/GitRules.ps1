# What a repository would make git start or contact, read from its files without starting git:
# programs its configuration names, hooks, submodules (git reads their configuration as well, and
# the settings of lib\Git.ps1 do not reach them), objects on another computer. Part of
# TrustRules.ps1: an ordinary repository has none of it, everything else the user confirms.
# Needs PathRules.ps1. Keep this file ASCII-only. Description: docs\security.md.

# Settings that only describe a repository. Everything else may start a program or open a path
# (core.fsmonitor, filter.*, diff.*, alias.*, include.path ...) and is shown to the user.
$script:HarmlessGitKeys = '^(?:' +
    'core\.(?:repositoryformatversion|filemode|bare|logallrefupdates|symlinks|ignorecase|autocrlf|eol|safecrlf|longpaths|quotepath|compression|loosecompression|precomposeunicode|protectntfs|protecthfs|hidedotfiles|preloadindex|untrackedcache|splitindex|sparsecheckout|sparsecheckoutcone|abbrev|whitespace|multipackindex|commitgraph|trustctime|checkstat|fscache|bigfilethreshold|packedgitlimit|packedgitwindowsize|deltabasecachelimit|commentchar|sharedrepository|warnambiguousrefs|checkroundtripencoding)' +
    '|remote\..+\.partialclonefilter|maintenance\.(?:auto|autodetach|strategy)|maintenance\..+\.(?:enabled|schedule|auto)' +
    '|extensions\.(?:objectformat|compatobjectformat|worktreeconfig|noop|preciousobjects|refstorage|relativeworktrees)' +
    '|remote\..+\.(?:url|pushurl|fetch|push|mirror|tagopt|prune|prunetags|skipdefaultupdate|skipfetchall|gh-resolved|followremotehead)' +
    '|remote\.pushdefault' +
    '|branch\..+\.(?:remote|pushremote|merge|rebase|description|gh-merge-base|vscode-merge-base|github-pr-owner-number)' +
    '|branch\.(?:autosetupmerge|autosetuprebase|sort)' +
    '|user\.(?:name|email|signingkey|useconfigonly)|author\.(?:name|email)|committer\.(?:name|email)' +
    '|commit\.(?:gpgsign|status|verbose|cleanup)|tag\.(?:gpgsign|sort|forcesignannotated)' +
    '|push\.(?:default|autosetupremote|followtags|useforceifincludes|usebitmaps|negotiate)' +
    '|pull\.(?:rebase|ff|octopus|twohead)' +
    '|fetch\.(?:prune|prunetags|parallel|fsckobjects|showforcedupdates|writecommitgraph|unpacklimit|all)' +
    '|rebase\.(?:autosquash|autostash|stat|updaterefs|missingcommitscheck|abbreviatecommands|rebasemerges)' +
    '|init\.defaultbranch|gc\.(?:auto|autodetach|autopacklimit|pruneexpire|reflogexpire|reflogexpireunreachable|worktreepruneexpire|writecommitgraph|aggressivewindow|aggressivedepth)' +
    '|pack\.(?:window|depth|threads|windowmemory|packsizelimit|compression|deltacachesize|deltacachelimit|writebitmaps|writebitmaphashcache|usebitmaps|allowpackreuse)' +
    '|index\.(?:version|threads|sparse|recordendofindexentries|recordoffsettable|skiphash)|feature\.(?:manyfiles|experimental)' +
    '|status\.(?:short|branch|relativepaths|showuntrackedfiles|showstash|aheadbehind|renames|renamelimit|displaycommentprefix)' +
    '|log\.(?:date|decorate|abbrevcommit|follow|mailmap|showroot|graphcolors|initialdecorationset|excludedecoration)|format\.pretty' +
    '|rerere\.(?:enabled|autoupdate)|checkout\.(?:defaultremote|guess|workers|thresholdforparallelism)|clean\.requireforce|stash\.(?:showpatch|showstat|showincludeuntracked)' +
    '|merge\.(?:ff|conflictstyle|log|renames|renamelimit|stat|branchdesc|directoryrenames)' +
    '|diff\.(?:algorithm|renames|renamelimit|colormoved|colormovedws|context|interhunkcontext|mnemonicprefix|noprefix|wserrorhighlight|indentheuristic|relative|statgraphwidth|statnamewidth|suppressblankempty|dirstat|autorefreshindex)' +
    '|(?:color|advice|column|i18n)\..+' +
    '|diff\.(?:tool|guitool)|merge\.(?:tool|guitool)|(?:difftool|mergetool)\.(?:prompt|keepbackup|trustexitcode|guidefault|hideresolved|writetotemp)' +
    '|http\.(?:postbuffer|version|lowspeedlimit|lowspeedtime)|credential\.(?:.+\.)?(?:username|usehttppath)' +
    '|transfer\.(?:fsckobjects|unpacklimit)|receive\.(?:fsckobjects|denycurrentbranch|denynonfastforwards|denydeletes|autogc|unpacklimit)' +
    '|gitflow\.(?:branch|prefix)\..+|gitflow\.origin' +
    '|submodule\..+\.(?:url|active|path|branch|ignore|fetchrecursesubmodules|shallow)|submodule\.(?:active|fetchjobs)' +
    '|gui\.(?:encoding|geometry|wmstate|tabsize|fontui|fontdiff|matchtrackingbranch|pruneduringfetch|trustmtime)|gitk\..+|github\.user' +
    '|lfs\.(?:repositoryformatversion|fetchinclude|fetchexclude|allowincompletepush)|lfs\.http.+\.(?:locksverify|access)' +
    ')$'

$script:GitIndexCache = @{}

function Find-GitRoot([string]$Folder) {
    # The folder that holds .git, from $Folder upwards; '' outside a repository. Starts nothing.
    $dir = $Folder
    while ($dir) {
        if ($null -ne (Get-EntryAttributes (Join-Path $dir '.git'))) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { return '' }
        $dir = $parent
    }
    return ''
}

function Get-EntryAttributes([string]$Path) {
    # The attributes of a file, folder or link itself (a link is not followed); $null if there is none.
    try { return [System.IO.File]::GetAttributes($Path) } catch { return $null }
}

function Test-FarPath([string]$Path) {
    # True if a path leads to another computer, also through a link, or cannot be followed. The
    # path itself is not opened. (A project that lies on a network drive itself is the user's choice.)
    if ($Path.StartsWith('\\') -or $Path.StartsWith('//')) { return $true }
    $real = $null
    try { $real = Resolve-RealPath ([System.IO.Path]::GetFullPath($Path)) } catch {}
    return (-not $real -or $real.StartsWith('\\'))
}

function Test-GitFolder([string]$GitDir, [string]$Common) {
    # True if git itself takes a .git folder for a repository: HEAD, objects and refs. If not, git
    # goes on looking in the folder above.
    try {
        $head = Join-Path $GitDir 'HEAD'
        if (-not [System.IO.File]::Exists($head)) { return $false }
        $text = [System.IO.File]::ReadAllText($head)
        if ($text -notmatch '^ref:\s*refs/' -and $text -notmatch '^[0-9a-fA-F]{40}') { return $false }
        return ([System.IO.Directory]::Exists((Join-Path $Common 'objects')) -and [System.IO.Directory]::Exists((Join-Path $Common 'refs')))
    } catch { return $false }
}

# --- the configuration --------------------------------------------------------------------------

function Read-GitValueEnd([string]$Text, [bool]$Quoted) {
    # Does a value go on in the next line? A backslash at its end, not in a comment. Returns
    # @(goes on, inside quotes).
    foreach ($m in [regex]::Matches($Text, '\\(.?)|["#;]')) {
        $sign = $m.Value[0]
        if ($sign -eq '"') { $Quoted = -not $Quoted }
        elseif ($sign -eq '\') { if (-not $m.Groups[1].Value) { return @($true, $Quoted) } }
        elseif (-not $Quoted) { return @($false, $false) }
    }
    return @($false, $Quoted)
}

function Read-GitConfig([string]$File) {
    # The settings of a git configuration file, as git reads it: objects with key (section in lower
    # case) and value. What is not understood comes as key '?'.
    $out = New-Object System.Collections.ArrayList
    try { $lines = [System.IO.File]::ReadAllText($File).Replace("`r`n", "`n").Split("`n") } catch { $null = $out.Add(@{ key = '?'; value = "$File cannot be read" }); return , $out }
    $section = ''
    $open = $null                                             # a value that goes on in this line
    $quoted = $false
    foreach ($raw in $lines) {
        if ($null -ne $open) {
            $end = Read-GitValueEnd $raw $quoted
            $open.value += ' ' + $raw.Trim()
            $quoted = [bool]$end[1]
            if (-not $end[0]) { if ($quoted) { $null = $out.Add(@{ key = '?'; value = $raw.Trim() }) }; $open = $null; $quoted = $false }
            continue
        }
        $line = $raw.Trim(' ', "`t", "`r")
        if ($line -match '^\[') {
            $m = [regex]::Match($line, '^\[([A-Za-z0-9.-]+)(?:[ \t]+"((?:[^"\\]|\\.)*)")?\](.*)$')
            if (-not $m.Success) { $null = $out.Add(@{ key = '?'; value = $line }); continue }
            $section = $m.Groups[1].Value.ToLowerInvariant()
            if ($m.Groups[2].Success) { $section += '.' + [regex]::Replace($m.Groups[2].Value, '\\(.)', '$1') }
            $line = $m.Groups[3].Value.Trim(' ', "`t", "`r")
        }
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        $m = [regex]::Match($line, '^([A-Za-z][A-Za-z0-9-]*)[ \t]*(?:=(.*))?$')
        if (-not $m.Success -or -not $section) { $null = $out.Add(@{ key = '?'; value = $line }); continue }
        $entry = @{ key = "$section." + $m.Groups[1].Value.ToLowerInvariant(); value = $m.Groups[2].Value.Trim() }
        $null = $out.Add($entry)
        if ($m.Groups[2].Success) {
            $end = Read-GitValueEnd $m.Groups[2].Value $false
            if ($end[0]) { $open = $entry; $entry.value = $entry.value.TrimEnd('\').Trim(); $quoted = [bool]$end[1] }
            elseif ($end[1]) { $null = $out.Add(@{ key = '?'; value = $line }) }
        }
    }
    return , $out
}

function Test-HarmlessSetting([string]$Key, [string]$Value, [string]$WorkTree, [string]$GitDir) {
    # True if a setting starts nothing and opens nothing outside the repository.
    $lower = $Key.ToLowerInvariant()
    if ($lower -ceq 'core.fsmonitor') { return (@('', 'true', 'false', 'yes', 'no', 'on', 'off', '0', '1') -contains $Value.ToLowerInvariant()) }
    if ($lower -ceq 'core.worktree') {
        # submodules name the folder they belong to
        try { return ([System.IO.Path]::GetFullPath([System.IO.Path]::Combine($GitDir, $Value.Trim('"').Replace('/', '\'))).TrimEnd('\') -ieq $WorkTree.TrimEnd('\')) } catch { return $false }
    }
    if ($lower -ceq 'blame.ignorerevsfile') { return ($Value.Trim('"') -match '^[\w.-][\w./\\ -]*$' -and $Value -notmatch '\.\.') }
    if ($lower -match '^submodule\..+\.update$') { return (@('checkout', 'rebase', 'merge', 'none') -contains $Value.ToLowerInvariant()) }
    if ($lower -notmatch $script:HarmlessGitKeys) { return $false }
    # an address can name a program as well (ext::, or a helper of one's own)
    if ($lower -match '\.(url|pushurl|remote|pushremote|pushdefault)$' -and $Value.Trim('"') -match '^[A-Za-z0-9+.-]+::') { return $false }
    return $true
}

# --- submodules ---------------------------------------------------------------------------------

function Get-GitLinks([string]$GitDir) {
    # The paths of the submodules the index of a repository names (git status and git diff start a
    # git of their own in each). A list that holds '?' when the index cannot be read here.
    $files = @()
    try {
        $index = Join-Path $GitDir 'index'
        if ([System.IO.File]::Exists($index)) { $files += (New-Object System.IO.FileInfo($index)) }
        $shared = @((New-Object System.IO.DirectoryInfo($GitDir)).GetFiles('sharedindex.*'))
        $files += $shared
    } catch { return @('?') }
    $paths = New-Object System.Collections.ArrayList
    # a gitlink has the mode 160000 (0x0000E000), in an index four bytes in a row
    $mark = [string][char]0 + [char]0 + [char]0xE0 + [char]0
    foreach ($f in $files) {
        $stamp = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
        $cached = $script:GitIndexCache[$f.FullName]
        if (-not $cached -or $cached.stamp -cne $stamp) {
            $cached = @{ stamp = $stamp; paths = @() }
            $list = New-Object System.Collections.ArrayList
            try {
                if ($f.Length -gt 200MB) { throw 'too big' }
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
                $plain = ($text.Length -gt 12 -and $text.StartsWith('DIRC', [StringComparison]::Ordinal) -and $bytes[7] -le 3 -and @($files).Count -eq 1)
                $at = $text.IndexOf($mark, 12, [StringComparison]::Ordinal)
                while ($at -ge 0) {
                    if (-not $plain) { $null = $list.Add('?'); break }
                    # after the mode: uid, gid, size, the hash (20 or 32 bytes), flags (2 or 4), the path
                    foreach ($start in ($at + 38), ($at + 40), ($at + 50), ($at + 52)) {
                        if ($start -ge $bytes.Length) { continue }
                        $stop = $text.IndexOf([string][char]0, $start, [StringComparison]::Ordinal)
                        if ($stop -le $start -or $stop - $start -gt 1000) { continue }
                        $null = $list.Add([System.Text.Encoding]::UTF8.GetString($bytes, $start, $stop - $start))
                    }
                    $at = $text.IndexOf($mark, $at + 1, [StringComparison]::Ordinal)
                }
            } catch { $null = $list.Add('?') }
            $cached.paths = $list.ToArray()
            $script:GitIndexCache[$f.FullName] = $cached
        }
        foreach ($p in $cached.paths) { $null = $paths.Add($p) }
    }
    return @($paths.ToArray() | Select-Object -Unique)
}

# --- a repository -------------------------------------------------------------------------------

function Get-GitFolder([string]$WorkTree) {
    # Where the .git of a folder really is: @{ dir; common; problem }. Nothing on another computer
    # is opened.
    $dot = Join-Path $WorkTree '.git'
    $r = @{ dir = $dot; common = $dot; problem = '' }
    $attributes = Get-EntryAttributes $dot
    if (Test-FarPath $dot) { if (-not $WorkTree.StartsWith('\\')) { $r.problem = '.git is a link to another place'; return $r } }
    if (($attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
        $m = $null
        try { $m = [regex]::Match([System.IO.File]::ReadAllText($dot), '^gitdir:\s*(.+?)\s*$') } catch {}
        if (-not $m -or -not $m.Success) { $r.problem = '.git cannot be read'; return $r }
        $target = $m.Groups[1].Value.Replace('/', '\')
        try {
            if (-not [System.IO.Path]::IsPathRooted($target)) { $target = [System.IO.Path]::Combine($WorkTree, $target) }
            if ((Test-FarPath $target) -and -not $WorkTree.StartsWith('\\')) { $r.problem = "gitdir: $($m.Groups[1].Value)"; return $r }
            $target = [System.IO.Path]::GetFullPath($target)
        } catch { $r.problem = '.git cannot be read'; return $r }
        $r.dir = $target
        $r.common = $target
    }
    $file = Join-Path $r.dir 'commondir'
    if ($null -ne (Get-EntryAttributes $file)) {
        try {
            $target = ([System.IO.File]::ReadAllText($file)).Trim().Replace('/', '\')
            if (-not [System.IO.Path]::IsPathRooted($target)) { $target = [System.IO.Path]::Combine($r.dir, $target) }
            if ((Test-FarPath $target) -and -not $WorkTree.StartsWith('\\')) { $r.problem = "commondir: $target"; return $r }
            $r.common = [System.IO.Path]::GetFullPath($target)
        } catch { $r.problem = 'commondir cannot be read' }
    }
    return $r
}

function Test-GitFolderBack([string]$WorkTree, $Git) {
    # True if the git folder a .git file points to belongs to this folder: a work tree names it in
    # "gitdir", a submodule in core.worktree. Otherwise git here would work on another repository.
    $back = Join-Path $Git.dir 'gitdir'
    if ($null -ne (Get-EntryAttributes $back)) {
        try {
            $target = ([System.IO.File]::ReadAllText($back)).Trim().Replace('/', '\')
            if (-not [System.IO.Path]::IsPathRooted($target)) { $target = [System.IO.Path]::Combine($Git.dir, $target) }
            return ([System.IO.Path]::GetFullPath($target) -ieq [System.IO.Path]::GetFullPath((Join-Path $WorkTree '.git')))
        } catch { return $false }
    }
    foreach ($s in (Read-GitConfig (Join-Path $Git.common 'config'))) {
        if ($s.key -ceq 'core.worktree') { return (Test-HarmlessSetting $s.key $s.value $WorkTree $Git.dir) }
    }
    return $false
}

function Add-GitFacts([string]$WorkTree, [string]$Prefix, $Found, [int]$Depth) {
    # Collects in $Found what the repository of $WorkTree would start or contact. Returns $true if
    # git would take it (it looks no further above then).
    $git = Get-GitFolder $WorkTree
    if ($git.problem) { $null = $Found.Add("$Prefix$($git.problem)"); return $true }
    if ($git.dir -ine (Join-Path $WorkTree '.git') -and -not (Test-GitFolderBack $WorkTree $git)) { $null = $Found.Add("${Prefix}git here works on $($git.dir)") }
    # links inside .git lead git elsewhere
    foreach ($dir in @($git.dir, (Join-Path $git.common 'objects'), (Join-Path $git.common 'objects\info'), (Join-Path $git.common 'info'), (Join-Path $git.common 'refs')) | Select-Object -Unique) {
        try {
            foreach ($e in (New-Object System.IO.DirectoryInfo($dir)).GetFileSystemInfos()) {
                if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -and (Get-LinkTarget $e.FullName)) { $null = $Found.Add("${Prefix}link $($e.Name) -> $(Get-LinkTarget $e.FullName)") }
            }
        } catch {}
    }
    foreach ($file in @((Join-Path $git.common 'config'), (Join-Path $git.dir 'config.worktree')) | Select-Object -Unique) {
        if ($null -eq (Get-EntryAttributes $file)) { continue }
        $settings = Read-GitConfig $file
        foreach ($s in $settings) {
            if ($s.key -ceq '?') { $null = $Found.Add("${Prefix}not understood: $($s.value)"); continue }
            if (Test-HarmlessSetting $s.key $s.value $WorkTree $git.dir) { continue }
            $note = ''
            # a partial clone: a look at a file can make git fetch it
            $remote = ''
            if ($s.key -ceq 'extensions.partialclone') { $remote = $s.value } elseif ($s.key -match '^remote\.(.+)\.promisor$') { $remote = $Matches[1] }
            if ($remote) { $note = " (git fetches missing files from $(@($settings | Where-Object { $_.key -ceq "remote.$remote.url" } | ForEach-Object { $_.value }) -join ', '))" }
            $null = $Found.Add("$Prefix$($s.key) = $($s.value)$note")
        }
    }
    $hooks = Join-Path $git.common 'hooks'
    if ([System.IO.Directory]::Exists($hooks)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $hooks -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.sample' } | Sort-Object Name)) {
            $hash = 'unread'
            if (-not (Test-FarPath $f.FullName) -or $WorkTree.StartsWith('\\')) { $hash = Get-ContentHash $f.FullName }
            $null = $Found.Add("${Prefix}hook $($f.Name) $($hash.Substring(0, [Math]::Min(12, $hash.Length)))")
        }
    }
    # objects of other repositories, named by their folder
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue((Join-Path $git.common 'objects'))
    for ($n = 0; $n -lt 10 -and $queue.Count -gt 0; $n++) {
        $objects = [string]$queue.Dequeue()
        $file = Join-Path $objects 'info\alternates'
        if ($null -eq (Get-EntryAttributes $file)) { continue }
        try { $rows = [System.IO.File]::ReadAllLines($file) } catch { $null = $Found.Add("${Prefix}alternates cannot be read"); continue }
        foreach ($row in $rows) {
            $path = $row.Trim()
            if (-not $path -or $path.StartsWith('#')) { continue }
            $path = $path.Trim('"').Replace('/', '\')
            try { if (-not [System.IO.Path]::IsPathRooted($path)) { $path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($objects, $path)) } } catch {}
            if ((Test-FarPath $path) -and -not $WorkTree.StartsWith('\\')) { $null = $Found.Add("${Prefix}objects from $path") } else { $queue.Enqueue($path) }
        }
    }
    if ($Depth -lt 5) {
        foreach ($link in @(Get-GitLinks $git.dir)) {
            if ($link -ceq '?') { $null = $Found.Add("${Prefix}submodules that cannot be checked here"); continue }
            $sub = ''
            try { $sub = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($WorkTree, $link.Replace('/', '\'))) } catch { continue }
            if (-not (Test-PathInside $sub $WorkTree) -or $sub -ieq $WorkTree.TrimEnd('\') -or ($Found.Count -gt 200)) { continue }
            if ($null -eq (Get-EntryAttributes (Join-Path $sub '.git'))) { continue }
            $null = Add-GitFacts $sub "$Prefix$($link): " $Found ($Depth + 1)
        }
    }
    return (Test-GitFolder $git.dir $git.common)
}

function Get-GitPrograms([string]$Root) {
    # The settings of the repository of $Root that may start a program or contact another computer
    # ("key = value"), its own hooks ("hook <name>"), those of its submodules. Empty for an ordinary
    # repository and outside of one. A .git that git itself would not take does not hide the one
    # above it.
    $found = New-Object System.Collections.ArrayList
    $dir = $Root
    while ($dir) {
        if ($null -ne (Get-EntryAttributes (Join-Path $dir '.git')) -and (Add-GitFacts $dir '' $found 0)) { break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return @($found.ToArray() | Select-Object -Unique)
}
