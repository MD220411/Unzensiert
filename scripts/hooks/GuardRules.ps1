# Rules of the safety guard (config\guard.json): what a tool call of the local model may
# do. Shared by the hook for Claude Code (Guard-Tool.ps1, a process per call) and by the
# agent Unzensiert (scripts\lib\AgentLoop.ps1), which calls Invoke-GuardCheck in its own
# process. Needs $script:ProjectRoot and the folders of HookEnvironment.ps1 (or _common.ps1).
# Description: docs\security.md. Keep this file ASCII-only.

$script:Rank = @{ none = 0; ask = 1; deny = 2 }
$script:Verdict = @{ decision = 'none'; rule = ''; reason = '' }

# --- verdict ------------------------------------------------------------------------------

function Set-Verdict([string]$Decision, [string]$Rule, [string]$Reason) {
    # Keeps the strictest decision seen so far.
    if ($script:Rank[$Decision] -gt $script:Rank[$script:Verdict.decision]) {
        $script:Verdict = @{ decision = $Decision; rule = $Rule; reason = $Reason }
    }
}

# --- paths ----------------------------------------------------------------------------

function Expand-ConfigPath([string]$Path) {
    # A path from guard.json: %VARIABLES% expanded, relative paths taken from the project.
    $p = [Environment]::ExpandEnvironmentVariables($Path)
    if ($p -match '%') { return $null }                      # variable unknown on this machine
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $script:ProjectRoot $p }
    return (Get-NormalPath $p)
}

function Get-NormalPath([string]$Path) {
    # Full path without trailing separator; $null if it cannot be a path.
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
        return $full
    } catch { return $null }
}

function Test-PathInside([string]$Path, [string]$Root) {
    # True if $Path is $Root or lies below it.
    if (-not $Path -or -not $Root) { return $false }
    if ($Path -ieq $Root) { return $true }
    return $Path.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-CommandPath([string]$Token, [string]$BaseDir) {
    # Turns a path as written in a shell command into a full Windows path. Understands
    # quotes, ~, $HOME, %VAR%, $env:VAR and the /c/... form of Git Bash. Returns $null if
    # the token still holds a variable or expression that cannot be known here.
    $t = $Token.Trim().Trim('"', "'", '`').Trim()
    if (-not $t) { return $null }
    $t = $t -replace '^\$\{?env:(\w+)\}?', '%$1%'            # $env:TEMP
    $t = $t -replace '^\$\{?(HOME|USERPROFILE|TEMP|TMP|APPDATA|LOCALAPPDATA|SystemRoot|windir|ProgramFiles|ProgramData|SystemDrive|HOMEDRIVE)\}?(?![\w])', '%$1%'
    $t = $t -replace '^%HOME%', '%USERPROFILE%'
    if ($t -eq '~' -or $t -match '^~[\\/]') { $t = '%USERPROFILE%' + $t.Substring(1) }
    $t = [Environment]::ExpandEnvironmentVariables($t)
    if ($t -match '[$%`]|\$\(') { return $null }
    $t = $t.Replace('/', '\')
    if ($t -match '^\\([a-zA-Z])(\\.*)?$') { $t = $Matches[1].ToUpper() + ':\' + ([string]$Matches[2]).TrimStart('\') }   # /c/Users
    elseif ($t -match '^\\tmp(\\.*)?$') { $t = $env:TEMP + [string]$Matches[1] }
    elseif ($t -match '^\\(cygdrive|mnt)\\([a-zA-Z])(\\.*)?$') { $t = $Matches[2].ToUpper() + ':\' + ([string]$Matches[3]).TrimStart('\') }
    elseif ($t -match '^\\[^\\]' -or $t -eq '\') { return '<shell-root>' + $t.TrimEnd('\') }   # /, /usr, /etc: the shell's own root
    if ($t -match '^[a-zA-Z]:$') { $t += '\' }
    if (-not [System.IO.Path]::IsPathRooted($t)) { $t = Join-Path $BaseDir $t }
    return (Get-NormalPath $t)
}

# --- recursive deletes ------------------------------------------------------------------

function Get-CommandTokens([string]$Text) {
    return @([regex]::Matches($Text, '"[^"]*"|''[^'']*''|[^\s"'']+') | ForEach-Object { $_.Value })
}

function Test-RecursiveDelete([string]$Command, [string]$Cwd, $Config, [int]$Depth = 0, [string]$StartDir = '') {
    # Finds recursive deletes (rm -r, rd /s, del /s, Remove-Item -Recurse) and judges each
    # target: system folders and whole user folders are denied, anything else outside the
    # project needs the user's yes, everything below the project folder is free.
    $critical = @($Config.criticalPaths | ForEach-Object { Expand-ConfigPath $_ } | Where-Object { $_ })
    $system = @($Config.systemPaths | ForEach-Object { Expand-ConfigPath $_ } | Where-Object { $_ })
    $free = @($Config.freeDeleteRoots | ForEach-Object { Expand-ConfigPath $_ } | Where-Object { $_ })
    # $Cwd is the project folder; $dir follows "cd" inside the command
    $dir = $Cwd
    if ($Depth -gt 0) { $dir = $StartDir }
    foreach ($segment in ($Command -split '\|\||&&|[;|\r\n]')) {
        # redirections such as "2>/dev/null" are not targets
        $segment = [regex]::Replace($segment, '(^|\s)\d*(>>?|<)\s*(&\d|"[^"]*"|''[^'']*''|\S+)', ' ')
        # @(): a segment of one word would otherwise be a string, and $tokens[0] a character
        $tokens = @(Get-CommandTokens $segment)
        if ($tokens.Count -eq 0) { continue }
        # a quoted command line, as in: cmd /c "rd /s /q C:\x", bash -c 'rm -rf ~'
        if ($Depth -lt 2) {
            foreach ($t in $tokens) {
                if ($t -match '^["''].*\s.*["'']$') { Test-RecursiveDelete $t.Substring(1, $t.Length - 2) $Cwd $Config ($Depth + 1) $dir }
            }
        }
        # follow "cd" so that relative targets are judged from the right folder
        for ($i = 0; $i -lt $tokens.Count - 1; $i++) {
            if ($tokens[$i].Trim('"', "'") -match '^(cd|chdir|pushd|Set-Location|sl)$' -and $tokens[$i + 1] -notmatch '^[-/][a-zA-Z]$') {
                $next = $null
                if ($dir) { $next = Resolve-CommandPath $tokens[$i + 1] $dir }
                if ($next -and $next -notlike '<shell-root>*') { $dir = $next } else { $dir = $null }
            }
        }
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $name = $tokens[$i].Trim('"', "'") -replace '^.*[\\/]', '' -replace '\.exe$', ''
            if ($name -notmatch '^(rm|del|erase|rd|rmdir|Remove-Item|ri)$') { continue }
            $rest = @($tokens[($i + 1)..($tokens.Count)] | Where-Object { $_ })
            # cmd commands take /s as a switch; for the others "/c" is a path (drive C in Git Bash)
            $flagPattern = '^-'
            if ($name -match '^(del|erase|rd|rmdir)$') { $flagPattern = '^(-|/[a-zA-Z?]$)' }
            $recursive = $false
            foreach ($f in ($rest | Where-Object { $_ -match $flagPattern })) {
                if ($f -match '^--recursive$|^-(r|rec|recu|recur|recurs|recurse)$|^/s$') { $recursive = $true }
                # clustered short options of the Unix rm: -rf, -fr, -Rfv
                if ($name -eq 'rm' -and $f -cmatch '^-[rRfivdI]+$' -and $f -match 'r') { $recursive = $true }
            }
            if (-not $recursive) { continue }
            foreach ($target in ($rest | Where-Object { $_ -notmatch $flagPattern })) {
                $raw = $target.Trim('"', "'")
                # "dir/*" and "dir/." mean the whole content of dir
                $raw = $raw -replace '[\\/](\*|\.\*|\*\.\*|\.)$', ''
                if ($raw -in @('*', '.*', '*.*', '.')) { $raw = '.' }
                if (-not $dir -and -not ($raw -match '^([a-zA-Z]:|[\\/~$%])')) { continue }   # relative, folder unknown
                $path = Resolve-CommandPath $raw $dir
                if (-not $path) { continue }
                if ($path -like '<shell-root>*') {
                    Set-Verdict 'deny' 'delete-system' "Recursive delete in the root folder of the shell ($raw)"; continue
                }
                if ($path -match '^[a-zA-Z]:\\?$' -or $path -match '^\\\\[^\\]+\\[^\\]+\\?$') {
                    Set-Verdict 'deny' 'delete-system' "Recursive delete of a whole drive ($path)"; continue
                }
                $hit = $critical | Where-Object { Test-PathInside $_ $path } | Select-Object -First 1
                if ($hit) { Set-Verdict 'deny' 'delete-system' "Recursive delete of $path (contains or is $hit)"; continue }
                $hit = $system | Where-Object { Test-PathInside $path $_ } | Select-Object -First 1
                if ($hit) { Set-Verdict 'deny' 'delete-system' "Recursive delete in a system folder ($path)"; continue }
                if ($free | Where-Object { Test-PathInside $path $_ }) { continue }
                if ($Cwd -and (Test-PathInside $Cwd $path)) {
                    Set-Verdict 'ask' 'delete-project' "Recursive delete of the whole project folder ($path)"; continue
                }
                if ($Cwd -and (Test-PathInside $path $Cwd)) {
                    if ($path -match '\\\.git$') { Set-Verdict 'ask' 'delete-project' "Deleting the git history ($path)" }
                    continue
                }
                Set-Verdict 'ask' 'delete-outside' "Recursive delete outside the project folder ($path)"
            }
        }
    }
}

# --- secrets and guard files --------------------------------------------------------------

function Test-FileAccess([string]$Path, [string]$Cwd, [bool]$Writes, $Config) {
    # Judges a path handed to Read, Edit, Write, Glob or Grep.
    if (-not $Path) { return }
    $full = Resolve-CommandPath $Path $Cwd
    if (-not $full -or $full -like '<shell-root>*') { return }
    $leaf = Split-Path -Leaf $full
    $excepted = $false
    foreach ($pattern in $Config.secretExceptions) { if ($leaf -like $pattern) { $excepted = $true } }
    if (-not $excepted) {
        foreach ($entry in $Config.secretPaths) {
            $secret = Expand-ConfigPath $entry
            if ($secret -and (Test-PathInside $full $secret)) { Set-Verdict 'ask' 'secret-files' "Access to credentials ($full)" }
        }
        foreach ($pattern in $Config.secretFileNames) {
            if ($leaf -like $pattern) { Set-Verdict 'ask' 'secret-files' "Access to a key or password file ($full)" }
        }
    }
    if ($Writes) {
        foreach ($entry in $Config.guardFiles) {
            $file = Expand-ConfigPath $entry
            if ($file -and $full -ieq $file) { Set-Verdict 'ask' 'guard-files' "Change to the guard rules themselves ($full)" }
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
            foreach ($rule in $Config.commandRules) {
                if ([regex]::IsMatch($command, [string]$rule.pattern, 'IgnoreCase')) { Set-Verdict ([string]$rule.decision) ([string]$rule.id) ([string]$rule.reason) }
            }
            Test-RecursiveDelete $command $cwdFull $Config
        } else {
            $writes = ($Tool -eq 'Edit' -or $Tool -eq 'Write' -or $Tool -eq 'NotebookEdit')
            foreach ($field in 'file_path', 'path', 'notebook_path') {
                $value = [string]$ToolInput.$field
                if ($value) { Test-FileAccess $value $cwdFull $writes $Config }
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
        $short = ($Subject -replace '\s+', ' ')
        if ($short.Length -gt 300) { $short = $short.Substring(0, 300) + ' ...' }
        Add-Content -Path (Join-Path $logDir 'guard.log') -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($Verdict.decision.ToUpper().PadRight(4))  $($Verdict.rule.PadRight(18))  $Tool  $short"
    } catch {}
}
