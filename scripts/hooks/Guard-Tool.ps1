# Safety guard for claude-local sessions: a PreToolUse hook of Claude Code that looks at
# every tool call of the local model before it runs. It protects this machine and the
# user's own data (disks, system folders, secrets, unsaved git work). It does not judge
# what the model works on, and everything inside the project folder stays allowed.
#
#   input   the hook JSON of Claude Code on stdin (tool_name, tool_input, cwd)
#   output  nothing = no objection, or a JSON decision "deny" / "ask" with the reason
#   rules   config\guard.json           log   <installRoot>\logs\guard.log
#   check   scripts\Test-Guard.ps1      docs  docs\sicherheit.md
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\hooks\Guard-Tool.ps1 < call.json
#
# Self-contained on purpose (no _common.ps1): it runs before every tool call and must
# start fast. A pattern guard is not a sandbox: it stops mistakes and plain attempts, not
# a command that is deliberately disguised. Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Rank = @{ none = 0; ask = 1; deny = 2 }
$script:Verdict = @{ decision = 'none'; rule = ''; reason = '' }

# --- verdict and output -----------------------------------------------------------------

function Set-Verdict([string]$Decision, [string]$Rule, [string]$Reason) {
    # Keeps the strictest decision seen so far.
    if ($script:Rank[$Decision] -gt $script:Rank[$script:Verdict.decision]) {
        $script:Verdict = @{ decision = $Decision; rule = $Rule; reason = $Reason }
    }
}

function Write-Verdict([string]$Tool, [string]$Subject) {
    # Prints the decision for Claude Code and notes it in the log. No output = go ahead.
    $v = $script:Verdict
    if ($v.decision -eq 'none') { return }
    $text = "Schutz von claude-local (Regel $($v.rule)): $($v.reason)."
    if ($v.decision -eq 'deny') { $text += ' Gesperrt. Nicht umgehen; dem Nutzer sagen, was geplant war und warum.' }
    else { $text += ' Der Nutzer entscheidet.' }
    $out = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = $v.decision; permissionDecisionReason = $text } }
    [Console]::Out.Write(($out | ConvertTo-Json -Compress -Depth 4))
    try {
        $server = Get-Content -Raw -Path (Join-Path $script:ProjectRoot 'config\server.json') -Encoding UTF8 | ConvertFrom-Json
        $logDir = Join-Path $server.installRoot 'logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $short = ($Subject -replace '\s+', ' ')
        if ($short.Length -gt 300) { $short = $short.Substring(0, 300) + ' ...' }
        Add-Content -Path (Join-Path $logDir 'guard.log') -Encoding UTF8 -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($v.decision.ToUpper().PadRight(4))  $($v.rule.PadRight(18))  $Tool  $short"
    } catch {}
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
        $tokens = Get-CommandTokens $segment
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
                    Set-Verdict 'deny' 'delete-system' "Rekursives Loeschen im Wurzelverzeichnis der Shell ($raw)"; continue
                }
                if ($path -match '^[a-zA-Z]:\\?$' -or $path -match '^\\\\[^\\]+\\[^\\]+\\?$') {
                    Set-Verdict 'deny' 'delete-system' "Rekursives Loeschen eines ganzen Laufwerks ($path)"; continue
                }
                $hit = $critical | Where-Object { Test-PathInside $_ $path } | Select-Object -First 1
                if ($hit) { Set-Verdict 'deny' 'delete-system' "Rekursives Loeschen von $path (enthaelt oder ist $hit)"; continue }
                $hit = $system | Where-Object { Test-PathInside $path $_ } | Select-Object -First 1
                if ($hit) { Set-Verdict 'deny' 'delete-system' "Rekursives Loeschen in einem Systemordner ($path)"; continue }
                if ($free | Where-Object { Test-PathInside $path $_ }) { continue }
                if ($Cwd -and (Test-PathInside $Cwd $path)) {
                    Set-Verdict 'ask' 'delete-project' "Rekursives Loeschen des ganzen Projektordners ($path)"; continue
                }
                if ($Cwd -and (Test-PathInside $path $Cwd)) {
                    if ($path -match '\\\.git$') { Set-Verdict 'ask' 'delete-project' "Loeschen des Git-Verlaufs ($path)" }
                    continue
                }
                Set-Verdict 'ask' 'delete-outside' "Rekursives Loeschen ausserhalb des Projektordners ($path)"
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
            if ($secret -and (Test-PathInside $full $secret)) { Set-Verdict 'ask' 'secret-files' "Zugriff auf Zugangsdaten ($full)" }
        }
        foreach ($pattern in $Config.secretFileNames) {
            if ($leaf -like $pattern) { Set-Verdict 'ask' 'secret-files' "Zugriff auf eine Schluessel- oder Passwortdatei ($full)" }
        }
    }
    if ($Writes) {
        foreach ($entry in $Config.guardFiles) {
            $file = Expand-ConfigPath $entry
            if ($file -and $full -ieq $file) { Set-Verdict 'ask' 'guard-files' "Aenderung an den Schutzregeln selbst ($full)" }
        }
    }
}

# --- main -------------------------------------------------------------------------------

$tool = ''
$subject = ''
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $call = $reader.ReadToEnd() | ConvertFrom-Json
    $config = Get-Content -Raw -Path (Join-Path $script:ProjectRoot 'config\guard.json') -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.enabled) { exit 0 }

    $tool = [string]$call.tool_name
    $cwd = Get-NormalPath ([string]$call.cwd)
    $in = $call.tool_input

    if ($tool -eq 'Bash' -or $tool -eq 'PowerShell') {
        $subject = [string]$in.command
        foreach ($rule in $config.commandRules) {
            if ([regex]::IsMatch($subject, [string]$rule.pattern, 'IgnoreCase')) { Set-Verdict ([string]$rule.decision) ([string]$rule.id) ([string]$rule.reason) }
        }
        Test-RecursiveDelete $subject $cwd $config
    } else {
        $writes = ($tool -eq 'Edit' -or $tool -eq 'Write' -or $tool -eq 'NotebookEdit')
        foreach ($field in 'file_path', 'path', 'notebook_path') {
            $value = [string]$in.$field
            if ($value) { $subject = $value; Test-FileAccess $value $cwd $writes $config }
        }
    }
} catch {
    # A broken guard must not pass silently and must not stop all work: let the user decide.
    Set-Verdict 'ask' 'guard-error' "Die Schutzpruefung ist fehlgeschlagen ($($_.Exception.Message)); scripts\Test-Setup.ps1 ausfuehren"
}
Write-Verdict $tool $subject
exit 0
