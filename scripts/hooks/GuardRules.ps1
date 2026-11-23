# Rules of the safety guard (config\guard.json): what a tool call of the local model may
# do. Shared by the hook for Claude Code (Guard-Tool.ps1, a process per call) and by the
# agent Unzensiert (scripts\lib\AgentLoop.ps1), which calls Invoke-GuardCheck in its own
# process. Needs $script:ProjectRoot and the folders of HookEnvironment.ps1 (or _common.ps1);
# loads PathRules.ps1 (what a path means) and DeleteRules.ps1 (deletes in a command line).
# Description: docs\security.md. Keep this file ASCII-only.

. (Join-Path $PSScriptRoot 'PathRules.ps1')
. (Join-Path $PSScriptRoot 'DeleteRules.ps1')

$script:Rank = @{ none = 0; ask = 1; deny = 2 }
$script:Verdict = @{ decision = 'none'; rule = ''; reason = '' }
# the tools of Unzensiert leave protected files out by themselves (lib\AgentTools.ps1); with the
# tools of Claude Code a search through a folder that holds some has to ask
$script:GuardOwnTools = $false

# --- verdict ------------------------------------------------------------------------------

function Set-Verdict([string]$Decision, [string]$Rule, [string]$Reason) {
    # Keeps the strictest decision seen so far.
    if ($script:Rank[$Decision] -gt $script:Rank[$script:Verdict.decision]) {
        $script:Verdict = @{ decision = $Decision; rule = $Rule; reason = $Reason }
    }
}

# --- paths ----------------------------------------------------------------------------

function Expand-ConfigPath([string]$Path) {
    # A path from guard.json: %VARIABLES% expanded (also %MyDocuments%, %Startup% and the like, the
    # real folders of this user), relative paths taken from the program folder.
    $p = $Path
    foreach ($name in 'MyDocuments', 'MyPictures', 'MyMusic', 'MyVideos', 'DesktopDirectory', 'Startup', 'CommonStartup') {
        if ($p.IndexOf("%$name%", [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $folder = [Environment]::GetFolderPath($name)
        if (-not $folder) { return $null }
        $p = [regex]::Replace($p, "(?i)%$name%", $folder.Replace('$', '$$'))
    }
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($p -match '%') { return $null }                      # variable unknown on this machine
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $script:ProjectRoot $p }
    return (Get-NormalPath $p)
}

$script:PathListCache = @{}

function Get-ConfigPaths($Config, [string]$Name) {
    # The paths of one list of guard.json on this computer, worked out once per set of rules.
    $entry = $script:PathListCache[$Name]
    if (-not $entry -or -not [object]::ReferenceEquals($entry.config, $Config)) {
        $list = @(@($Config.$Name) | Where-Object { $_ } | ForEach-Object { Expand-ConfigPath ([string]$_) } | Where-Object { $_ })
        $entry = @{ config = $Config; paths = [string[]]$list }
        $script:PathListCache[$Name] = $entry
    }
    return $entry.paths
}

function Get-NormalPath([string]$Path) {
    # Full path without trailing separator; $null if it cannot be a path.
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
        return $full
    } catch { return $null }
}

function Remove-DevicePrefix([string]$Path) {
    # \\?\C:\x, \\.\C:\x and the share every Windows has of its drives (\\localhost\C$\x) are other
    # spellings of C:\x; \\?\UNC\server\share is \\server\share.
    if ($Path -notmatch '^[\\/]{2}') { return $Path }
    $p = $Path -replace '^[\\/]{2}[?.][\\/]UNC[\\/]', '\\' -replace '^[\\/]{2}[?.][\\/](?=[a-zA-Z]:)', ''
    $own = 'localhost|127\.\d+\.\d+\.\d+|::1|' + [regex]::Escape([string]$env:COMPUTERNAME)
    return ($p -replace ('^[\\/]{2}(?:' + $own + ')(?:@\w+)?[\\/]([a-zA-Z])\$(?=[\\/]|$)'), '$1:')
}

function Expand-ShellToken([string]$Token) {
    # A word of a command with the variables this computer knows filled in: ~, $HOME, %VAR%,
    # $env:VAR, ${HOME:?}. $null if it still holds a variable or expression.
    $t = $Token.Trim().Trim('"', "'", '`').Trim()
    if (-not $t) { return $null }
    $t = $t -replace '^\$\{?env:(\w+)\}?', '%$1%'            # $env:TEMP
    $t = $t -replace '^\$(?:\{(HOME|USERPROFILE|TEMP|TMP|APPDATA|LOCALAPPDATA|SystemRoot|windir|ProgramFiles|ProgramData|SystemDrive|HOMEDRIVE)(?:[:%#/^,@][^}]*)?\}|(HOME|USERPROFILE|TEMP|TMP|APPDATA|LOCALAPPDATA|SystemRoot|windir|ProgramFiles|ProgramData|SystemDrive|HOMEDRIVE)(?![\w]))', '%$1$2%'
    $t = $t -replace '^%HOME%', '%USERPROFILE%'
    if ($t -eq '~' -or $t -match '^~[\\/]') { $t = '%USERPROFILE%' + $t.Substring(1) }
    $t = Remove-DevicePrefix ([Environment]::ExpandEnvironmentVariables($t))
    if ($t -match '[$%`]|\$\(') { return $null }
    return $t
}

function Resolve-CommandPath([string]$Token, [string]$BaseDir) {
    # Turns a path as written in a shell command into a full Windows path. Understands quotes,
    # ~, $HOME, %VAR%, $env:VAR and the /c/... form of Git Bash. Returns $null if the token
    # still holds a variable or expression that cannot be known here.
    $t = Expand-ShellToken $Token
    if ($null -eq $t) { return $null }
    $t = $t.Replace('/', '\')
    if ($t -match '^\\([a-zA-Z])(\\.*)?$') { $t = $Matches[1].ToUpper() + ':\' + ([string]$Matches[2]).TrimStart('\') }   # /c/Users
    elseif ($t -match '^\\tmp(\\.*)?$') { $t = $env:TEMP + [string]$Matches[1] }
    elseif ($t -match '^\\(cygdrive|mnt)\\([a-zA-Z])(\\.*)?$') { $t = $Matches[2].ToUpper() + ':\' + ([string]$Matches[3]).TrimStart('\') }
    elseif ($t -match '^\\[^\\]' -or $t -eq '\') { return '<shell-root>' + $t.TrimEnd('\') }   # /, /usr, /etc: the shell's own root
    if ($t -match '^[a-zA-Z]:$') { $t += '\' }
    try {
        if (-not [System.IO.Path]::IsPathRooted($t)) {
            if (-not $BaseDir) { return $null }
            $t = [System.IO.Path]::Combine($BaseDir, $t)
        }
    } catch { return $null }
    return (Get-NormalPath $t)
}

# characters GetFullPath refuses, kept apart while a path with wildcards is brought into order
$script:WildStar = [string][char]0xE000
$script:WildMark = [string][char]0xE001

function Resolve-WildPath([string]$Token, [string]$BaseDir) {
    # Like Resolve-CommandPath for a word with * and ?: a full path that still holds them, to be
    # compared with -like. $null when it cannot be known.
    $safe = (Remove-DevicePrefix $Token.Trim().Trim('"', "'").Trim()).Replace('*', $script:WildStar).Replace('?', $script:WildMark)
    $full = Resolve-CommandPath $safe $BaseDir
    if (-not $full -or $full -like '<shell-root>*') { return $null }
    return $full.Replace($script:WildStar, '*').Replace($script:WildMark, '?')
}

function Get-CommandPaths([string]$Token, [string]$BaseDir) {
    # Every path a word of a command may mean: as Windows reads it, and as Git Bash does (".." above
    # a drive, /usr/../c). Wildcards (* ?) stay in.
    $out = @()
    if ($Token -match '[*?]') { $out += Resolve-WildPath $Token $BaseDir } else { $out += Resolve-CommandPath $Token $BaseDir }
    if ($Token -match '\.\.' -and $Token.Contains('/')) {
        $t = Expand-ShellToken (Remove-DevicePrefix $Token.Trim().Trim('"', "'").Trim())
        if ($t -and ($BaseDir -or $t -match '^([a-zA-Z]:|[\\/~])')) {
            $b = Resolve-BashPath ($t.Replace('*', $script:WildStar).Replace('?', $script:WildMark)) $BaseDir
            if ($b.full) { $out += $b.full.Replace($script:WildStar, '*').Replace($script:WildMark, '?') }
            else {
                # out of the drive: below the one root Git Bash has (/c, /d ...)
                $m = [regex]::Match($t.Replace('\', '/'), '(?:^|/)\.\./([a-zA-Z](?:/.*)?)$')
                if ($b.kind -eq 'odd' -and $m.Success) { $out += Get-NormalPath ($m.Groups[1].Value.Substring(0, 1) + ':\' + $m.Groups[1].Value.Substring(1).TrimStart('/').Replace('/', '\')) }
            }
        }
    }
    return @($out | Where-Object { $_ } | Select-Object -Unique)
}

function Get-WildParent([string]$Wild) {
    # The folder before the first wildcard of a full path.
    $cut = $Wild.IndexOfAny([char[]]'*?')
    if ($cut -lt 0) { return $Wild }
    return (Get-NormalPath ($Wild.Substring(0, $Wild.LastIndexOf('\', $cut) + 1)))
}

# --- secrets, guard files, autostart ----------------------------------------------------------

function Get-SecretPaths($Config) {
    # The folders and files of "secretPaths" on this computer.
    return (Get-ConfigPaths $Config 'secretPaths')
}

function Test-SecretException([string]$Leaf, $Config) {
    foreach ($pattern in @($Config.secretExceptions)) { if ($Leaf -like $pattern) { return $true } }
    return $false
}

function Test-SecretFile([string]$Full, $Config) {
    # True if a file (full path) is one the model only gets after a question.
    if (-not $Full) { return $false }
    $leaf = $Full.Substring($Full.LastIndexOf('\') + 1)
    if (Test-SecretException $leaf $Config) { return $false }
    foreach ($secret in @(Get-SecretPaths $Config)) { if (Test-PathInside $Full $secret) { return $true } }
    foreach ($pattern in @($Config.secretFileNames)) { if ($leaf -like $pattern) { return $true } }
    return $false
}

function Test-HoldsSecrets([string]$Full, $Config) {
    # True if a protected place lies below the folder.
    if (-not $Full) { return $false }
    foreach ($secret in @(Get-SecretPaths $Config)) { if ($secret -ine $Full -and (Test-PathInside $secret $Full)) { return $true } }
    return $false
}

function Test-SecretWild([string]$Wild, $Secrets, $Config, [bool]$Recursive) {
    # True if a full path with wildcards can meet a protected file or folder.
    $leaf = $Wild.Substring($Wild.LastIndexOf('\') + 1)
    $parts = $Wild.Split('\')
    foreach ($s in @($Secrets)) {
        if ($s -like $Wild -or $s -like "$Wild\*" -or $Wild -like "$s\*") { return $true }
        # a wildcard on the way to it: ~/.ss?/key
        $depth = $s.Split('\').Count
        if ($parts.Count -gt $depth -and $s -like (@($parts[0..($depth - 1)]) -join '\')) { return $true }
    }
    foreach ($pattern in @($Config.secretFileNames)) {
        if ($leaf -ieq $pattern) { return $true }
        if ($leaf -notmatch '^\*?(\.\w+)?$' -and (([string]$pattern).Replace('*', 'x')) -like $leaf) { return $true }
    }
    return ($Recursive -and (Test-HoldsSecrets (Get-WildParent $Wild) $Config))
}

function Test-SecretSpelling([string]$Word, [string]$Folder, $Secrets, $Config, [bool]$Recursive, [string]$Tool = '') {
    # True if a word of a command names a protected file or folder, also with wildcards; with
    # $Recursive also a folder that holds one. For Bash also what cannot be told (/proc, ~+, a
    # line break in a path): the question costs nothing but a key.
    if ($Word -match '[\x00-\x1F]') { return $true }
    $odd = @('odd', 'device', 'network')
    if ($Word -match '[*?\[]') {
        # a short name (SEC~1) next to a wildcard cannot be followed
        if ($Word -match '~\d') { return $true }
        # [a-z], [!x], []a], [[:alpha:]] stand for one character
        $plain = $Word -replace '\[:\w*:\]|\[=.=\]|\[\..\.\]', 'x' -replace '\[[!^]?\]?[^\]]*\]?', '?'
        $wilds = @()
        if ($Tool -eq 'Bash') {
            $b = Resolve-BashPath ($plain.Replace('*', $script:WildStar).Replace('?', $script:WildMark)) $Folder
            if ($odd -contains $b.kind) { return $true }
            if ($b.kind -eq 'file') { $wilds += $b.full.Replace($script:WildStar, '*').Replace($script:WildMark, '?') }
        }
        $wilds += Resolve-WildPath $plain $Folder
        # \Users\x without a drive: the drive of the folder, for Windows programs and PowerShell
        if ($plain -match '^[\\/](?![\\/])' -and $Folder -match '^[a-zA-Z]:') { $wilds += Resolve-WildPath ($Folder.Substring(0, 2) + $plain) $Folder }
        $wilds = @($wilds | Where-Object { $_ } | Select-Object -Unique)
        foreach ($wild in $wilds) {
            if (Test-SecretWild $wild $Secrets $Config $Recursive) { return $true }
            # links on the way to the wildcard, and links it meets
            $parent = Get-WildParent $wild
            if ($parent) {
                $real = Resolve-RealPath $parent
                if (-not $real -or $real.StartsWith('\\')) { return $true }
                if ($real -ine $parent -and $wild.Length -gt $parent.Length -and (Test-SecretWild ($real.TrimEnd('\') + $wild.Substring($parent.TrimEnd('\').Length)) $Secrets $Config $Recursive)) { return $true }
                if ([System.IO.Directory]::Exists($parent) -and (Test-WildLinks $wild)) { return $true }
            }
        }
        # a part no file name may have can be taken away by a ".." behind it (s"ub\..\..\x*)
        return ($wilds.Count -eq 0 -and $Word -match '(^|[\\/])\.\.([\\/]|$)')
    }
    $paths = @()
    if ($Tool -eq 'Bash') {
        $b = Resolve-BashPath $Word $Folder
        if ($odd -contains $b.kind) { return $true }
        if ($b.kind -eq 'file') { $paths += $b.full, $b.real }
    }
    $f = Get-PathFacts $Word $Folder
    if ($f.ok) { $paths += $f.full, $f.real }
    elseif ($Word -match '(^|[\\/])\.\.([\\/]|$)') { return $true }
    # C:\x\key:stream
    elseif ($Tool -ne 'Bash' -and $Word -match '^[a-zA-Z]:[\\/].*:') { return $true }
    foreach ($p in @($paths | Select-Object -Unique)) {
        if (Test-SecretFile $p $Config) { return $true }
        if ($Recursive -and (Test-HoldsSecrets $p $Config)) { return $true }
    }
    return $false
}

function Test-GuardFile([string]$Full, [string]$Cwd, $Config) {
    # True if a file belongs to the protection itself: single files always; the folders of the
    # program and of its state unless someone works inside them (on the program itself, or in
    # the work folder of the benchmark).
    foreach ($file in @(Get-ConfigPaths $Config 'guardFiles')) { if ($Full -ieq $file) { return $true } }
    foreach ($folder in @(Get-ConfigPaths $Config 'guardFolders')) {
        if (-not (Test-PathInside $Full $folder)) { continue }
        $area = $folder
        if (Test-PathInside $folder $script:ProjectRoot) { $area = $script:ProjectRoot }
        if ($Cwd -and (Test-PathInside $Cwd $area)) { continue }
        return $true
    }
    return $false
}

function Test-ProtectedFile([string]$Path, [string]$Cwd, $Config) {
    # True if a file of a project runs or is obeyed later by itself (git hooks, tasks of editors,
    # instructions, the check command, programs named like system programs): "protectedFiles" in
    # guard.json, patterns on the path below the project folder with forward slashes.
    if (-not $Config) { return $false }
    $f = Get-PathFacts $Path $Cwd
    if (-not $f.ok) { return $true }
    $root = $Cwd.TrimEnd('\')
    foreach ($p in @(@($f.full, $f.real) | Select-Object -Unique)) {
        $rel = $p
        if (Test-PathInside $p $root) { $rel = $p.Substring([Math]::Min($p.Length, $root.Length)).TrimStart('\') }
        $rel = $rel.Replace('\', '/').ToLowerInvariant()
        foreach ($pattern in @($Config.protectedFiles)) {
            $want = ([string]$pattern).ToLowerInvariant()
            # "/$rel/": the folder itself counts like what lies in it
            if ($rel -like $want -or "/$rel" -like "*/$want" -or "/$rel/" -like "*/$want") { return $true }
        }
    }
    return $false
}

function Test-ProtectedFolder([string]$Path, [string]$Cwd, $Config) {
    # True if a folder of this name could bring protected files along (.github with its workflows): a
    # folder that arrives there as a whole is not looked into.
    if (-not $Config) { return $false }
    $f = Get-PathFacts $Path $Cwd
    if (-not $f.ok) { return $true }
    foreach ($p in @(@($f.full, $f.real) | Select-Object -Unique)) {
        $rel = '/' + $p.Replace('\', '/').ToLowerInvariant().TrimEnd('/')
        foreach ($pattern in @($Config.protectedFiles)) {
            $parts = ([string]$pattern).ToLowerInvariant().Split('/')
            for ($n = 1; $n -lt $parts.Count; $n++) { if ($rel.EndsWith('/' + (@($parts[0..($n - 1)]) -join '/'), [StringComparison]::Ordinal)) { return $true } }
        }
    }
    return $false
}

function Test-FileAccess([string]$Path, [string]$Cwd, [bool]$Writes, $Config, [bool]$Searches = $false) {
    # Judges a path handed to Read, Edit, Write, Glob or Grep.
    if (-not $Path) { return }
    # no tool fills in %VARIABLES%, but a path that names a protected place that way asks as well
    $filled = [Environment]::ExpandEnvironmentVariables($Path)
    if ($filled -cne $Path) { Test-FileAccess $filled $Cwd $Writes $Config $Searches }
    $f = Get-PathFacts $Path $Cwd
    if ($f.kind -eq 'network') { Set-Verdict 'ask' 'network-path' "A path on another computer ($($f.full)): opening it can send your Windows sign-in, and the name itself, to that computer" }
    if (-not $f.ok) { Set-Verdict 'ask' 'odd-path' "A path with a special meaning ($Path): $($f.reason)"; return }
    foreach ($p in @(@($f.full, $f.real) | Select-Object -Unique)) {
        if (Test-SecretFile $p $Config) { Set-Verdict 'ask' 'secret-files' "Access to a key, password or credentials ($p)" }
        elseif ($Searches -and -not $script:GuardOwnTools -and (Test-HoldsSecrets $p $Config)) { Set-Verdict 'ask' 'secret-files' "A search through a folder that holds credentials ($p)" }
        if (-not $Writes) { continue }
        if (Test-GuardFile $p $Cwd $Config) { Set-Verdict 'ask' 'guard-files' "Change to the protection itself ($p)" }
        foreach ($entry in @(Get-ConfigPaths $Config 'autostartPaths')) {
            if (Test-PathInside $p $entry) { Set-Verdict 'ask' 'autostart' "A file that programs read or start by themselves ($p)" }
        }
    }
}

# --- one call -------------------------------------------------------------------------------

function Get-GuardRules {
    return (Get-Content -Raw -Path (Join-Path $script:ProjectRoot 'config\guard.json') -Encoding UTF8 | ConvertFrom-Json)
}

function Get-GuardSubject([string]$Tool, $ToolInput) {
    # What a call is about: the command, or the path it reads or writes.
    if ($Tool -eq 'Bash' -or $Tool -eq 'PowerShell') { return [string]$ToolInput.command }
    foreach ($field in 'file_path', 'path', 'notebook_path') {
        if ([string]$ToolInput.$field) { return [string]$ToolInput.$field }
    }
    return ''
}

function Invoke-GuardCheck([string]$Tool, $ToolInput, [string]$Cwd, $Config) {
    # The decision for one tool call: @{ decision = none|ask|deny; rule; reason }.
    # $ToolInput may be an object from ConvertFrom-Json or a dictionary.
    $script:Verdict = @{ decision = 'none'; rule = ''; reason = '' }
    try {
        if (-not $Config.enabled) { return $script:Verdict }
        $cwdFull = Get-NormalPath $Cwd
        if ($Tool -eq 'Bash' -or $Tool -eq 'PowerShell') {
            $command = [string]$ToolInput.command
            # "r""m" and "r''m" are rm for the shell
            $joined = [regex]::Replace($command, '(?<=\w)(""|'''')(?=\w)', '')
            foreach ($rule in $Config.commandRules) {
                if ([regex]::IsMatch($command, [string]$rule.pattern, 'IgnoreCase') -or ($joined -cne $command -and [regex]::IsMatch($joined, [string]$rule.pattern, 'IgnoreCase'))) {
                    Set-Verdict ([string]$rule.decision) ([string]$rule.id) ([string]$rule.reason)
                }
            }
            Test-RecursiveDelete $command $cwdFull $Config 0 '' $Tool
        } else {
            $writes = ($Tool -eq 'Edit' -or $Tool -eq 'Write' -or $Tool -eq 'NotebookEdit')
            $searches = ($Tool -eq 'Grep' -or $Tool -eq 'Glob')
            foreach ($field in 'file_path', 'path', 'notebook_path') {
                $value = [string]$ToolInput.$field
                if ($value) { Test-FileAccess $value $cwdFull $writes $Config $searches }
            }
            # Glob of Claude Code may carry the folder inside its pattern
            if ($Tool -eq 'Glob' -and -not $script:GuardOwnTools -and [string]$ToolInput.pattern -match '^([\\/]|[a-zA-Z]:[\\/]|~)') {
                $fixed = ([string]$ToolInput.pattern) -replace '[*?\[{].*$', ''
                if ($fixed) { Test-FileAccess $fixed $cwdFull $false $Config $true }
            }
        }
    } catch {
        # A broken guard must not pass silently and must not stop all work: let the user decide.
        Set-Verdict 'ask' 'guard-error' "The guard check failed ($($_.Exception.Message)); run scripts\Test-Setup.ps1"
    }
    return $script:Verdict
}

function Write-GuardLog([string]$Tool, [string]$Subject, $Verdict) {
    # One line per objection in <installRoot>\logs\guard.log.
    if ($Verdict.decision -eq 'none' -or -not $env:CLAUDE_LOCAL_ROOT) { return }
    try {
        $logDir = Join-Path $env:CLAUDE_LOCAL_ROOT 'logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        # no characters that would steer the terminal in which somebody reads the log
        $short = ($Subject -replace '\s+', ' ' -replace '[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2066-\u2069]', '?')
        if ($short.Length -gt 300) { $short = $short.Substring(0, 300) + ' ...' }
        Add-Content -Path (Join-Path $logDir 'guard.log') -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($Verdict.decision.ToUpper().PadRight(4))  $($Verdict.rule.PadRight(18))  $Tool  $short"
    } catch {}
}
