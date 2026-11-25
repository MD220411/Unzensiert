# /undo of the agent Unzensiert: before the first change of a request the files of the project
# folder are kept in a repository of their own, and again when the request ends. /undo puts back
# what the last request changed, wherever nothing changed since; your own later changes stay. The
# repository lies next to the saved conversations (<installRoot>\sessions\<project>\undo), never in
# the project, and its git reads no configuration of the user or of the project: no filters, no
# hooks, no change of line ends. Files git ignores in the project (.gitignore) are kept only when a
# file tool changes them; files larger than "maxFileMB", the repository itself (.git) and changes
# outside the folder are not kept. Settings: "undo" in config\unzensiert.json; description:
# docs\unzensiert.md ("Undo"). Needs lib\Git.ps1, lib\Machine.ps1, hooks\PathRules.ps1,
# lib\AgentTools.ps1, lib\CommandRules.ps1. Keep this file ASCII-only.

$script:UndoDefaults = @{ enabled = $true; maxFileMB = 20; maxFiles = 30000; keepDays = 7; timeoutSeconds = 60; exclude = @() }

function Get-UndoSettings {
    # "undo" of config\unzensiert.json, with defaults for what is missing.
    $r = @{}
    foreach ($k in $script:UndoDefaults.Keys) { $r[$k] = $script:UndoDefaults[$k] }
    $u = (Get-AgentSettings).undo
    if ($u) { foreach ($p in $u.PSObject.Properties) { if ($r.ContainsKey($p.Name)) { $r[$p.Name] = $p.Value } } }
    $r.exclude = @(@($r.exclude) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    return $r
}

function Test-UndoFolder([string]$Folder) {
    # '' if the folder can be kept; otherwise why not: a drive, the user folder or a folder of
    # Windows is no project, and a folder on another computer is not kept.
    if (-not $Folder) { return 'root' }
    $full = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\')
    if ($full.StartsWith('\\')) { return 'network' }
    if ($full.Length -le 2) { return 'root' }
    $profiles = ''
    if ($env:USERPROFILE) { $profiles = Split-Path -Parent $env:USERPROFILE }
    foreach ($v in @($env:USERPROFILE, $profiles, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)) {
        if ($v -and $full -ieq ([string]$v).TrimEnd('\')) { return 'root' }
    }
    return ''
}

function Initialize-Undo($Session) {
    # $Session.undo, set up once per conversation (a new one after /clear, the earlier one again
    # after /resume): where the repository lies, the limits, whether undo is on in this folder.
    if ($Session.undo -and $Session.undo.sid -eq $Session.id) { return $Session.undo }
    $s = Get-UndoSettings
    $store = [System.IO.Path]::Combine([string]$Session.folder, 'undo')
    $u = @{
        sid = [string]$Session.id; store = $store
        index = [System.IO.Path]::Combine($store, "index-$($Session.id)")
        state = [System.IO.Path]::Combine($store, "$($Session.id).json")
        list = [System.Collections.ArrayList]::new(); current = $null; prompt = ''
        off = ''; detail = ''; noted = $false; ready = $false
        maxBytes = [long]([double]$s.maxFileMB * 1MB); maxFiles = [int]$s.maxFiles
        timeout = [math]::Max(5, [int]$s.timeoutSeconds); keepDays = [math]::Max(1, [int]$s.keepDays)
        exclude = @($s.exclude)
    }
    if (-not $s.enabled) { $u.off = 'disabled' }
    elseif (-not (Get-GitExe)) { $u.off = 'git' }
    else { $u.off = Test-UndoFolder $Session.cwd }
    if (-not $u.off -and [System.IO.File]::Exists($u.state)) {
        # a conversation continued with /resume: its requests can still be taken back
        try {
            # assigned first: ConvertFrom-Json of Windows PowerShell 5.1 hands on an array as one object
            $rows = Get-Content -Raw -Encoding UTF8 -LiteralPath $u.state | ConvertFrom-Json
            foreach ($e in $rows) {
                if (-not $e) { continue }
                $null = $u.list.Add(@{ n = [int]$e.n; prompt = [string]$e.prompt; before = [string]$e.before; beforeTree = [string]$e.beforeTree; after = [string]$e.after; afterTree = [string]$e.afterTree; undone = [string]$e.undone })
            }
        } catch {}
    }
    $Session.undo = $u
    return $u
}

function ConvertTo-UndoArgument([string]$Text) {
    # One argument on the command line of a program, quoted by the rules of the C runtime.
    if ($Text -and $Text -notmatch '[\s"]') { return $Text }
    $s = [regex]::Replace($Text, '(\\*)"', '$1$1\"')
    $s = [regex]::Replace($s, '(\\+)$', '$1$1')
    return '"' + $s + '"'
}

function Invoke-UndoGit($Session, [string[]]$Arguments, [string]$Index = '', [string]$InputText = $null, [switch]$Plain) {
    # git on the repository of undo with the project folder as its work tree. No configuration of
    # the user (global, system) counts, paths are taken literally, and the settings below keep the
    # files byte for byte; the repository itself has no hooks and no filters. $Plain: without
    # repository and work tree (git init). Returns @{ code; out; err } with the NUL characters of
    # -z kept; code 124 when the time limit ended it.
    $u = $Session.undo
    $list = @()
    if (-not $Plain) { $list += @("--git-dir=$($u.store)", "--work-tree=$($Session.cwd)") }
    foreach ($c in @('core.fsmonitor=false', 'core.autocrlf=false', 'core.safecrlf=false', 'core.longpaths=true',
            'core.quotepath=off', "core.hooksPath=$([System.IO.Path]::Combine($u.store, 'no-hooks'))", 'gc.auto=0',
            'advice.addEmbeddedRepo=false', 'user.name=Unzensiert', 'user.email=undo@unzensiert.invalid')) { $list += @('-c', $c) }
    $list += @($Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-GitExe
    $psi.Arguments = (@($list | ForEach-Object { ConvertTo-UndoArgument ([string]$_) }) -join ' ')
    $psi.WorkingDirectory = $Session.cwd
    $vars = $psi.EnvironmentVariables
    foreach ($name in @($vars.Keys)) { if ([string]$name -match '^GIT_') { $vars.Remove($name) } }
    $vars['GIT_CONFIG_NOSYSTEM'] = '1'
    $vars['GIT_CONFIG_GLOBAL'] = [System.IO.Path]::Combine($u.store, 'empty.gitconfig')
    $vars['GIT_LITERAL_PATHSPECS'] = '1'
    $vars['GIT_NO_LAZY_FETCH'] = '1'
    $vars['GIT_TERMINAL_PROMPT'] = '0'
    if (-not $Plain) { if ($Index) { $vars['GIT_INDEX_FILE'] = $Index } else { $vars['GIT_INDEX_FILE'] = $u.index } }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $proc = Start-ChildProcess $psi
    if ($null -ne $InputText) {
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($InputText)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    $proc.StandardInput.Close()
    $outBytes = New-Object System.IO.MemoryStream
    $errBytes = New-Object System.IO.MemoryStream
    $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outBytes)
    $errTask = $proc.StandardError.BaseStream.CopyToAsync($errBytes)
    $code = 124
    if ($proc.WaitForExit($u.timeout * 1000)) { $proc.WaitForExit(); $code = $proc.ExitCode }
    else { Stop-ProcessTree $proc.Id; $null = $proc.WaitForExit(5000) }
    $null = $outTask.Wait(5000); $null = $errTask.Wait(5000)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    return @{ code = $code; out = $utf8.GetString($outBytes.ToArray()); err = $utf8.GetString($errBytes.ToArray()).Trim() }
}

function Set-UndoOff($Session, [string]$Why, [string]$Detail = '') {
    # Undo stops for this conversation; the work goes on. The note comes once.
    $u = $Session.undo
    $u.off = $Why
    $u.detail = $Detail
    $u.current = $null
}

function ConvertTo-UndoPattern([string]$Path) {
    # A path of the project as a line of info\exclude that means exactly this file.
    $s = [regex]::Replace($Path, '([\\*?\[\]!#])', '\$1')
    if ($s.EndsWith(' ')) { $s = $s.Substring(0, $s.Length - 1) + '\ ' }
    return '/' + $s
}

function Initialize-UndoStore($Session) {
    # The repository of undo for this project folder, made when it is missing; old conversations
    # leave it after keepDays. The index of a new conversation starts as a copy of the newest one
    # (git then reads only the files that changed since). $false if it cannot be used.
    $u = $Session.undo
    if ($u.ready) { return $true }
    if ($u.off) { return $false }
    try {
        if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($u.store, 'HEAD'))) {
            New-Item -ItemType Directory -Force -Path $u.store | Out-Null
            $r = Invoke-UndoGit $Session @('init', '--bare', '--quiet', $u.store) -Plain
            if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return $false }
        }
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $info = [System.IO.Path]::Combine($u.store, 'info')
        New-Item -ItemType Directory -Force -Path $info | Out-Null
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($u.store, 'empty.gitconfig'), '', $utf8)
        # byte for byte: no line ends changed, no filter, no encoding of the work tree
        [System.IO.File]::WriteAllText([System.IO.Path]::Combine($info, 'attributes'), "* -text -filter -ident -diff -merge -working-tree-encoding`n", $utf8)
        $exclude = [System.IO.Path]::Combine($info, 'exclude')
        $lines = @()
        if ([System.IO.File]::Exists($exclude)) { $lines = @([System.IO.File]::ReadAllLines($exclude)) }
        $missing = @($u.exclude | Where-Object { $lines -notcontains $_ })
        if ($missing.Count -gt 0 -or $lines.Count -eq 0) {
            if ($lines.Count -eq 0) { $lines = @('# not kept by /undo of Unzensiert (folders that are made again, files that are too large)') }
            [System.IO.File]::WriteAllText($exclude, ((@($lines) + $missing) -join "`n") + "`n", $utf8)
        }
        if (-not [System.IO.File]::Exists($u.index)) {
            $newest = Get-ChildItem -LiteralPath $u.store -Filter 'index-*' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($newest) { Copy-Item -LiteralPath $newest.FullName -Destination $u.index -Force }
        }
        Remove-UndoOld $Session
        $u.ready = $true
        return $true
    } catch {
        Set-UndoOff $Session 'error' $_.Exception.Message
        return $false
    }
}

function Remove-UndoOld($Session) {
    # Conversations older than keepDays: their entry, list and index go, then whatever only they
    # kept (objects younger than an hour stay, another conversation may be writing them).
    $u = $Session.undo
    $r = Invoke-UndoGit $Session @('for-each-ref', '--format=%(refname)', 'refs/undo/')
    if ($r.code -ne 0) { return }
    $limit = [datetime]::Today.AddDays(-$u.keepDays).ToString('yyyyMMdd')
    $gone = 0
    foreach ($ref in @($r.out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if ($ref -notmatch '^refs/undo/((\d{8})-\d{6}-[0-9a-f]+)$') { continue }
        $sid = $Matches[1]
        if ($sid -eq $u.sid -or [string]::CompareOrdinal($Matches[2], $limit) -ge 0) { continue }
        $null = Invoke-UndoGit $Session @('update-ref', '-d', $ref)
        foreach ($f in @("index-$sid", "$sid.json")) { Remove-Item -Force -LiteralPath ([System.IO.Path]::Combine($u.store, $f)) -ErrorAction SilentlyContinue }
        $gone++
    }
    if ($gone -gt 0) { $null = Invoke-UndoGit $Session @('gc', '--quiet', '--prune=1.hour.ago') }
}

function Save-UndoTree($Session) {
    # Brings the index of this conversation up to the files of the project folder and returns
    # its tree ('' when undo stopped). New files larger than maxFileMB are left out, and from now
    # on stay out (info\exclude); more than maxFiles new files stop undo for this folder.
    $u = $Session.undo
    if (-not (Initialize-UndoStore $Session)) { return '' }
    $r = Invoke-UndoGit $Session @('ls-files', '-z', '--others', '--exclude-standard')
    if ($r.code -eq 124) { Set-UndoOff $Session 'slow' ([string]$u.timeout); return '' }
    if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return '' }
    $new = @($r.out.Split([char]0) | Where-Object { $_ })
    if ($new.Count -gt $u.maxFiles) { Set-UndoOff $Session 'tooMany' ([string]$u.maxFiles); return '' }
    $r = Invoke-UndoGit $Session @('ls-files', '-z', '--modified')
    $grown = @()
    if ($r.code -eq 0) { $grown = @($r.out.Split([char]0) | Where-Object { $_ }) }
    # Left out before git reads them: folders that are junctions or links (git for Windows would
    # follow a junction out of the project), files that are links or only in the cloud (reading
    # them would download them), and files that are too large. Only names were listed so far.
    $dirs = @{}
    $skipDirs = @()
    $skipFiles = @()
    $away = [int]([System.IO.FileAttributes]::ReparsePoint -bor [System.IO.FileAttributes]::Offline) -bor 0x40000 -bor 0x400000
    foreach ($p in @($new + $grown)) {
        $parts = $p.Split('/')
        $rel = ''
        $linked = $false
        for ($i = 0; $i -lt $parts.Count - 1; $i++) {
            if ($rel) { $rel += '/' }
            $rel += $parts[$i]
            if (-not $dirs.ContainsKey($rel)) {
                $isLink = $false
                try { $isLink = [bool]([int][System.IO.File]::GetAttributes([System.IO.Path]::Combine($Session.cwd, $rel.Replace('/', '\'))) -band [int][System.IO.FileAttributes]::ReparsePoint) } catch {}
                $dirs[$rel] = $isLink
                if ($isLink) { $skipDirs += $rel }
            }
            if ($dirs[$rel]) { $linked = $true; break }
        }
        if ($linked) { continue }
        try {
            $fi = New-Object System.IO.FileInfo ([System.IO.Path]::Combine($Session.cwd, $p.Replace('/', '\')))
            if ($fi.Exists -and (($fi.Length -gt $u.maxBytes) -or ([int]$fi.Attributes -band $away))) { $skipFiles += $p }
        } catch {}
    }
    if ($skipDirs.Count + $skipFiles.Count -gt 0) {
        $exclude = [System.IO.Path]::Combine($u.store, 'info\exclude')
        $patterns = @($skipDirs | ForEach-Object { (ConvertTo-UndoPattern $_) + '/' }) + @($skipFiles | ForEach-Object { ConvertTo-UndoPattern $_ })
        [System.IO.File]::AppendAllText($exclude, (($patterns -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        # what the index already held there goes out of it as well
        $tracked = @($skipDirs) + @($skipFiles | Where-Object { $grown -contains $_ })
        if ($tracked.Count -gt 0) { $null = Invoke-UndoGit $Session (@('rm', '--cached', '-r', '--quiet', '--ignore-unmatch', '--') + $tracked) }
    }
    $r = Invoke-UndoGit $Session @('add', '-A')
    if ($r.code -eq 124) { Set-UndoOff $Session 'slow' ([string]$u.timeout); return '' }
    if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return '' }
    $r = Invoke-UndoGit $Session @('write-tree')
    if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return '' }
    return $r.out.Trim()
}

function New-UndoCommit($Session, [string]$Tree, [string]$Message) {
    # A commit of $Tree after the last one of this conversation, which keeps all of them from
    # being cleaned away (one entry refs/undo/<conversation>). '' if it fails.
    $u = $Session.undo
    $ref = "refs/undo/$($u.sid)"
    $args0 = @('commit-tree', $Tree, '-m', $Message)
    $head = Invoke-UndoGit $Session @('rev-parse', '--verify', '--quiet', $ref)
    if ($head.code -eq 0 -and $head.out.Trim()) { $args0 += @('-p', $head.out.Trim()) }
    $r = Invoke-UndoGit $Session $args0
    if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return '' }
    $commit = $r.out.Trim()
    $r = Invoke-UndoGit $Session @('update-ref', $ref, $commit)
    if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return '' }
    return $commit
}

function Save-UndoState($Session) {
    # The list of this conversation for /resume (<conversation>.json next to the repository).
    $u = $Session.undo
    $rows = @($u.list | ForEach-Object { [ordered]@{ n = $_.n; prompt = $_.prompt; before = $_.before; beforeTree = $_.beforeTree; after = $_.after; afterTree = $_.afterTree; undone = $_.undone } })
    $json = '[]'
    if ($rows.Count -gt 0) { $json = ConvertTo-Json -InputObject @($rows) -Depth 3 }
    try { [System.IO.File]::WriteAllText($u.state, $json, (New-Object System.Text.UTF8Encoding($false))) } catch {}
}

function Get-UndoRelative($Session, [string]$Full) {
    # A file of the project as git writes it (src/a.txt); '' if it lies outside the folder or a
    # link on the way leads somewhere else.
    if (-not $Full) { return '' }
    $root = [System.IO.Path]::GetFullPath($Session.cwd).TrimEnd('\')
    try { $Full = [System.IO.Path]::GetFullPath($Full).TrimEnd('\') } catch { return '' }
    if ($Full -ieq $root -or -not (Test-PathInside $Full $root)) { return '' }
    $rel = $Full.Substring($root.Length + 1)
    $rootReal = (Get-PathFacts $root $root).real
    $facts = Get-PathFacts $Full $root
    if (-not $rootReal -or -not $facts.ok -or -not $facts.real) { return '' }
    if (-not (Test-PathInside $facts.real $rootReal) -or $facts.real.Substring($rootReal.TrimEnd('\').Length).TrimStart('\') -ine $rel) { return '' }
    return $rel.Replace('\', '/')
}

function Test-UndoChange($Session, [string]$Name, $A) {
    # Can this call change files of the project? The file tools always; a command unless it only
    # reads (lib\CommandRules.ps1). Reading tools and the web never.
    if (@('Edit', 'EditLines', 'Write') -contains $Name) { return $true }
    if (@('Bash', 'PowerShell') -notcontains $Name) { return $false }
    try { return (-not (Test-ReadOnlyCommand ([string](Get-DictValue $A 'command')) $Name $Session.cwd (Get-SessionGuard $Session))) }
    catch { return $true }
}

function Start-UndoRequest($Session, [string]$Prompt) {
    # A new request: nothing kept for it yet.
    $u = Initialize-Undo $Session
    $u.current = $null
    $p = ([string]$Prompt).Trim()
    $at = $p.IndexOfAny([char[]]@("`r", "`n"))
    if ($at -ge 0) { $p = $p.Substring(0, $at) }
    if ($p.Length -gt 80) { $p = $p.Substring(0, 77) + '...' }
    $u.prompt = $p
}

function Save-UndoBefore($Session, [string]$Name, $A) {
    # Before a call that can change files: the first one of a request keeps the project folder as
    # it is. A file tool also keeps its file when git ignores it (.env, a log), as it is now.
    $u = Initialize-Undo $Session
    if ($u.off) { Show-UndoOff $Session; return }
    $file = ''
    if (@('Edit', 'EditLines', 'Write') -contains $Name) {
        $full = Resolve-AgentPath ([string](Get-DictValue $A 'file_path')) $Session.cwd
        $rel = Get-UndoRelative $Session $full
        if ($rel -and [System.IO.File]::Exists($full) -and (New-Object System.IO.FileInfo $full).Length -le $u.maxBytes) { $file = $rel }
    }
    if (-not $u.current) {
        if (-not (Initialize-UndoStore $Session)) { Show-UndoOff $Session; return }
        if ($file) { $null = Invoke-UndoGit $Session @('add', '-f', '--', $file) }
        $tree = Save-UndoTree $Session
        if (-not $tree) { Show-UndoOff $Session; return }
        $n = 1
        if ($u.list.Count -gt 0) { $n = [int]$u.list[$u.list.Count - 1].n + 1 }
        $commit = New-UndoCommit $Session $tree "before request $n"
        if (-not $commit) { Show-UndoOff $Session; return }
        $u.current = @{ n = $n; prompt = $u.prompt; before = $commit; beforeTree = $tree; after = ''; afterTree = ''; undone = '' }
        $null = $u.list.Add($u.current)
        Save-UndoState $Session
        return
    }
    if (-not $file) { return }
    # a file git ignores that the first look of this request did not keep: add it, as it is before
    # this call, to what the request started from
    $known = Invoke-UndoGit $Session @('ls-tree', '--name-only', $u.current.beforeTree, '--', $file)
    if ($known.code -ne 0 -or $known.out.Trim()) { return }
    $ignored = Invoke-UndoGit $Session @('check-ignore', '-q', '--no-index', '--', $file)
    if ($ignored.code -ne 0) { return }
    $null = Invoke-UndoGit $Session @('add', '-f', '--', $file)
    $temp = [System.IO.Path]::Combine($u.store, "index-amend-$($u.sid)")
    try {
        $r = Invoke-UndoGit $Session @('read-tree', $u.current.beforeTree) $temp
        if ($r.code -eq 0) { $r = Invoke-UndoGit $Session @('add', '-f', '--', $file) $temp }
        if ($r.code -eq 0) { $r = Invoke-UndoGit $Session @('write-tree') $temp }
        if ($r.code -ne 0) { return }
        $tree = $r.out.Trim()
        $commit = New-UndoCommit $Session $tree "before request $($u.current.n), with $file"
        if ($commit) {
            $u.current.before = $commit
            $u.current.beforeTree = $tree
            Save-UndoState $Session
        }
    } finally {
        Remove-Item -Force -LiteralPath $temp -ErrorAction SilentlyContinue
    }
}

function Complete-UndoRequest($Session) {
    # The end of a request that kept something: the project folder as it is now. A request that
    # changed nothing leaves no entry.
    $u = $Session.undo
    if (-not $u -or -not $u.current) { return }
    $entry = $u.current
    $u.current = $null
    if ($u.off) { return }
    $tree = Save-UndoTree $Session
    if (-not $tree) { return }
    if ($tree -eq $entry.beforeTree) {
        $u.list.Remove($entry)
        Save-UndoState $Session
        return
    }
    $commit = New-UndoCommit $Session $tree "after request $($entry.n)"
    if (-not $commit) { return }
    $entry.after = $commit
    $entry.afterTree = $tree
    Save-UndoState $Session
}

function Show-UndoOff($Session) {
    # The note why there is no /undo here, once per conversation (not for "switched off").
    $u = $Session.undo
    if ($u.noted -or $u.off -eq 'disabled') { return }
    $u.noted = $true
    Write-UiNote (Get-UiText 'undo.off' (Get-UndoOffText $u)) 'warn'
}

function Get-UndoOffText($U) {
    # Why there is no undo, in words of config\unzensiert-texts.json.
    $text = Get-UiText ("undo.why." + $U.off) $U.detail
    if (-not $text -or $text -eq "undo.why.$($U.off)") { $text = Get-UiText 'undo.why.error' $U.detail }
    return $text
}

function Split-UndoNul([string]$Text) {
    return @($Text.Split([char]0) | Where-Object { $_ -ne '' })
}

function Get-UndoPlan($Session) {
    # What /undo would do now: the last request of this conversation that changed something and is
    # not taken back yet. @{ entry; restore; remove; kept } (paths as git writes them; kept = changed
    # again since, they stay), @{ off } when undo cannot work here, $null when nothing is left.
    $u = Initialize-Undo $Session
    if ($u.off) { return @{ off = $u.off } }
    $entry = $null
    for ($i = $u.list.Count - 1; $i -ge 0; $i--) {
        $e = $u.list[$i]
        if ($e.after -and -not $e.undone -and $e.afterTree -ne $e.beforeTree) { $entry = $e; break }
    }
    if (-not $entry) { return $null }
    $r = Invoke-UndoGit $Session @('diff-tree', '-r', '-z', '--no-renames', '--name-status', $entry.beforeTree, $entry.afterTree)
    if ($r.code -ne 0) { Set-UndoOff $Session 'error' $r.err; return @{ off = 'error' } }
    $parts = Split-UndoNul $r.out
    $now = Save-UndoTree $Session
    if (-not $now) { return @{ off = $u.off } }
    $since = @{}
    $r2 = Invoke-UndoGit $Session @('diff-tree', '-r', '-z', '--no-renames', '--name-only', $entry.afterTree, $now)
    foreach ($p in (Split-UndoNul $r2.out)) { $since[$p] = $true }
    $plan = @{ entry = $entry; restore = @(); remove = @(); kept = @(); now = $now }
    for ($i = 0; $i + 1 -lt $parts.Count; $i += 2) {
        $status = $parts[$i]
        $path = $parts[$i + 1]
        if ($since.ContainsKey($path)) { $plan.kept += $path }
        elseif ($status -eq 'A') { $plan.remove += $path }
        else { $plan.restore += $path }
    }
    return $plan
}

function Invoke-UndoPlan($Session, $Plan) {
    # Puts the files back: what the request created goes, what it changed or deleted comes back as
    # it was. Never through a link that leads out of the project. Returns @{ restored; removed;
    # failed (texts) }; the model reads what happened with the next request.
    $u = $Session.undo
    $root = [System.IO.Path]::GetFullPath($Session.cwd).TrimEnd('\')
    $failed = @()
    $removed = 0
    foreach ($p in @($Plan.remove)) {
        $full = [System.IO.Path]::Combine($root, $p.Replace('/', '\'))
        if ((Get-UndoRelative $Session $full) -cne $p) { $failed += "$p ($(Get-UiText 'undo.outside'))"; continue }
        try {
            if ([System.IO.File]::Exists($full)) {
                $attr = [System.IO.File]::GetAttributes($full)
                if ($attr -band [System.IO.FileAttributes]::ReadOnly) { [System.IO.File]::SetAttributes($full, $attr -bxor [System.IO.FileAttributes]::ReadOnly) }
                [System.IO.File]::Delete($full)
            }
            $removed++
            # folders that only this file filled
            $dir = [System.IO.Path]::GetDirectoryName($full)
            while ($dir -and $dir.Length -gt $root.Length -and (Test-PathInside $dir $root) -and [System.IO.Directory]::Exists($dir) -and -not [System.IO.Directory]::EnumerateFileSystemEntries($dir).GetEnumerator().MoveNext()) {
                [System.IO.Directory]::Delete($dir)
                $dir = [System.IO.Path]::GetDirectoryName($dir)
            }
        } catch { $failed += "$p ($($_.Exception.Message))" }
    }
    $restore = @()
    foreach ($p in @($Plan.restore)) {
        $full = [System.IO.Path]::Combine($root, $p.Replace('/', '\'))
        if ((Get-UndoRelative $Session $full) -cne $p) { $failed += "$p ($(Get-UiText 'undo.outside'))" } else { $restore += $p }
    }
    $restored = 0
    if ($restore.Count -gt 0) {
        $list = [System.IO.Path]::Combine($u.store, "paths-$($u.sid)")
        try {
            [System.IO.File]::WriteAllText($list, (($restore -join [string][char]0) + [char]0), (New-Object System.Text.UTF8Encoding($false)))
            $r = Invoke-UndoGit $Session @('checkout', $Plan.entry.before, "--pathspec-from-file=$list", '--pathspec-file-nul')
            if ($r.code -eq 0) { $restored = $restore.Count } else { $failed += $r.err }
        } finally { Remove-Item -Force -LiteralPath $list -ErrorAction SilentlyContinue }
    }
    # the folder as it is now, kept as the end of this undo; the request counts as taken back
    $tree = Save-UndoTree $Session
    $commit = ''
    if ($tree) { $commit = New-UndoCommit $Session $tree "undo of request $($Plan.entry.n)" }
    $Plan.entry.undone = $(if ($commit) { $commit } else { 'yes' })
    Save-UndoState $Session
    # the model learns it with the next request (as with a command of the user)
    $names = @(@($Plan.restore) + @($Plan.remove) | Select-Object -First 12)
    $more = @($Plan.restore).Count + @($Plan.remove).Count - $names.Count
    $text = "The user took back the file changes of the request `"$($Plan.entry.prompt)`" with /undo: " + ($names -join ', ')
    if ($more -gt 0) { $text += " and $more more" }
    $text += ' are as they were before that request.'
    if (@($Plan.kept).Count -gt 0) { $text += ' Changed again since and left as they are: ' + (@($Plan.kept | Select-Object -First 12) -join ', ') + '.' }
    $text += " Read a file again before you change it.`n"
    $Session.pending += $text
    return @{ restored = $restored; removed = $removed; failed = @($failed | Where-Object { $_ }) }
}

# --- /undo at the terminal ---------------------------------------------------------------------------

function Show-UiUndo($Plan) {
    # The question in a frame: the request, what comes back, what goes, what stays.
    $mode = $script:Ui.mode
    $hex = $script:Ui.ink.warn
    $inner = (Get-UiWidth) - 6
    $side = '  ' + (Format-UiInk (Get-UiBox 3) $hex) + ' '
    Write-UiOut "`n"
    Write-UiFrameTop '<' (Get-UiText 'undo.title') $hex
    $out = New-Object System.Collections.ArrayList
    foreach ($l in (Format-UiWrapped @(New-UiSpan ([string]$Plan.entry.prompt) $mode.foreground 'b') '' '' 0 $inner)) { $null = $out.Add($side + $l) }
    foreach ($row in @(@('undo.restore', $Plan.restore), @('undo.remove', $Plan.remove), @('undo.kept', $Plan.kept))) {
        $paths = @($row[1])
        if ($paths.Count -eq 0) { continue }
        $shown = @($paths | Select-Object -First 8)
        $line = ($shown -join ', ')
        if ($paths.Count -gt $shown.Count) { $line += ' ' + (Get-UiText 'undo.more' ($paths.Count - $shown.Count)) }
        $spans = @((New-UiSpan ((Get-UiText $row[0] $paths.Count) + ' ') $mode.foreground), (New-UiSpan $line $hex 'i'))
        foreach ($l in (Format-UiWrapped $spans '- ' '  ' 2 $inner)) { $null = $out.Add($side + $l) }
    }
    Write-UiOut ((@($out) -join "`n") + "`n")
    Write-UiFrameBottom $hex
    Write-UiOut (Format-UiKeyLine @(@('y', (Get-UiText 'undo.yes')), @('n', (Get-UiText 'undo.no'))) $hex)
}

function Invoke-UndoCommand($Session) {
    # /undo: shows what the last request changed and puts it back after a yes.
    $plan = Get-UndoPlan $Session
    if ($null -eq $plan) { Write-UiNote (Get-UiText 'undo.nothing'); return }
    if ($plan.off) {
        if ($plan.off -eq 'disabled') { Write-UiNote (Get-UiText 'undo.disabled') 'warn' }
        else { Write-UiNote (Get-UiText 'undo.off' (Get-UndoOffText $Session.undo)) 'warn' }
        return
    }
    if (@($plan.restore).Count + @($plan.remove).Count -eq 0) {
        Write-UiNote (Get-UiText 'undo.allChanged' @($plan.kept).Count) 'warn'
        return
    }
    Show-UiUndo $plan
    Clear-UiKeys
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [string]$k.KeyChar
        if ($c -eq 'y' -or $c -eq 'j') { break }
        if ($c -eq 'n' -or $k.Key -eq [ConsoleKey]::Escape -or ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control))) {
            Write-UiChoiceAnswer 'warn' (Get-UiText 'undo.declined')
            return
        }
    }
    $done = Invoke-UndoPlan $Session $plan
    if (@($done.failed).Count -gt 0) {
        Write-UiChoiceAnswer 'error' (Get-UiText 'undo.failed' ((@($done.failed) | Select-Object -First 5) -join '; '))
    } else {
        Write-UiChoiceAnswer 'ok' (Get-UiText 'undo.done' ($done.restored + $done.removed))
    }
}
