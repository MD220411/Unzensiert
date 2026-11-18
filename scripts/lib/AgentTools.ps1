# The tools of the agent Unzensiert: Bash, PowerShell, Read, Edit, Write, Glob, Grep. Names
# and parameters are those the guard (scripts\hooks\GuardRules.ps1) checks and local models
# know from other agents. Used by lib\AgentLoop.ps1. Needs lib\Config.ps1, lib\Machine.ps1.
# Keep this file ASCII-only.
#
# A tool returns @{ text; error; image = @{ mime; data } or $null; changed = path or ''; diff }
#   text     what the model gets back
#   changed  a file the tool wrote (for the closing check)
#   diff     old and new text of an edit, for the terminal

$script:ImageTypes = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.bmp' = 'image/bmp' }
$script:SkipFolders = @('.git', 'node_modules', '__pycache__', '.venv', 'venv', '.mypy_cache', '.pytest_cache', '.idea', '.vs')

$script:AgentSettings = $null

function Get-AgentSettings {
    # config\unzensiert.json with the section "unzensiert" of machine.json, read once per run.
    if ($null -eq $script:AgentSettings) { $script:AgentSettings = Read-Config 'unzensiert' }
    return $script:AgentSettings
}

function Get-AgentToolSchemas([string]$GitBash) {
    # Descriptions for the model (OpenAI function format) of the tools listed in "tools" of
    # config\agent.json, the same set claude-local gives Claude Code; without Git Bash the
    # Bash tool becomes the PowerShell tool (lib\Machine.ps1, Get-AgentTools).
    $cfg = Get-AgentSettings
    $wanted = @(([string](Get-AgentTools ([string](Get-AgentConfig).tools) $GitBash)) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($wanted.Count -eq 0) { $wanted = @('Bash', 'PowerShell', 'Read', 'Edit', 'Write', 'Glob', 'Grep') }
    $t = [int]$cfg.commandTimeoutSeconds
    $max = [int]$cfg.commandMaxSeconds
    $tools = @()
    $cmdProps = @{
        command     = @{ type = 'string'; description = 'The command line.' }
        timeout     = @{ type = 'integer'; description = "Seconds before the command is stopped (default $t, at most $max)." }
        description = @{ type = 'string'; description = 'What the command does, in a few words.' }
    }
    if ($GitBash -and $wanted -contains 'Bash') {
        $tools += @{ type = 'function'; function = @{ name = 'Bash'; description = "Runs a command in Git Bash (POSIX shell) in the project folder and returns stdout and stderr. Chain steps with &&. Do not start programs that wait for input or never end."; parameters = @{ type = 'object'; properties = $cmdProps; required = @('command') } } }
    }
    $tools += @{ type = 'function'; function = @{ name = 'PowerShell'; description = "Runs a command in Windows PowerShell 5.1 in the project folder and returns its output. Do not start programs that wait for input or never end."; parameters = @{ type = 'object'; properties = $cmdProps; required = @('command') } } }
    $tools += @{ type = 'function'; function = @{ name = 'Read'; description = "Reads a file. Text comes back with line numbers (number, tab, line); for long files read parts with offset (first line, from 1) and limit (number of lines, default $($cfg.readLines)). Images (png, jpg, gif, webp, bmp) are shown to you. Read a file before you change it."; parameters = @{ type = 'object'; properties = @{ file_path = @{ type = 'string'; description = 'Path of the file.' }; offset = @{ type = 'integer'; description = 'First line to read, from 1.' }; limit = @{ type = 'integer'; description = 'Number of lines.' } }; required = @('file_path') } } }
    $tools += @{ type = 'function'; function = @{ name = 'Edit'; description = 'Replaces text in a file that you have read. old_string must occur exactly once (or set replace_all), with the same spaces and indentation and without the line numbers Read shows; take enough surrounding lines to make it unique.'; parameters = @{ type = 'object'; properties = @{ file_path = @{ type = 'string' }; old_string = @{ type = 'string'; description = 'The exact text to replace.' }; new_string = @{ type = 'string'; description = 'The text to put there.' }; replace_all = @{ type = 'boolean'; description = 'Replace every occurrence.' } }; required = @('file_path', 'old_string', 'new_string') } } }
    $tools += @{ type = 'function'; function = @{ name = 'Write'; description = 'Creates a file, or replaces the whole content of a file you have read. For changes to an existing file use Edit.'; parameters = @{ type = 'object'; properties = @{ file_path = @{ type = 'string' }; content = @{ type = 'string'; description = 'The complete new content.' } }; required = @('file_path', 'content') } } }
    $tools += @{ type = 'function'; function = @{ name = 'Glob'; description = 'Finds files by name pattern, such as **/*.py or src/**/test_*.ps1 (newest first, at most 100).'; parameters = @{ type = 'object'; properties = @{ pattern = @{ type = 'string' }; path = @{ type = 'string'; description = 'Folder to search, default the project folder.' } }; required = @('pattern') } } }
    $tools += @{ type = 'function'; function = @{ name = 'Grep'; description = 'Searches the content of files with a regular expression (.NET syntax) and returns path:line:text (at most 200 lines).'; parameters = @{ type = 'object'; properties = @{ pattern = @{ type = 'string' }; path = @{ type = 'string'; description = 'Folder or file, default the project folder.' }; glob = @{ type = 'string'; description = 'Only files whose name matches, such as *.cs.' }; ignore_case = @{ type = 'boolean' }; files_only = @{ type = 'boolean'; description = 'Only the names of the files that match.' } }; required = @('pattern') } } }
    return @($tools | Where-Object { $wanted -contains $_.function.name })
}

# --- helpers --------------------------------------------------------------------------------

function New-ToolResult([string]$Text, [bool]$IsError = $false) {
    # info: facts for the terminal (lines, files, exit code ...); the model reads only text
    return @{ text = $Text; error = $IsError; image = $null; changed = ''; diff = $null; summary = ''; userStop = $false; info = $null }
}

function Resolve-AgentPath([string]$Path, [string]$Cwd) {
    # A path as the model writes it, as a full Windows path: relative to the project
    # folder, ~ for the user folder, /c/... of Git Bash.
    $p = ([string]$Path).Trim().Trim('"', "'")
    if ($p -eq '~' -or $p.StartsWith('~/') -or $p.StartsWith('~\')) { $p = $env:USERPROFILE + $p.Substring(1) }
    if ($p -match '^/([a-zA-Z])(/.*)?$') { $p = $Matches[1] + ':' + [string]$Matches[2] }
    $p = $p.Replace('/', '\')
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $Cwd $p }
    return [System.IO.Path]::GetFullPath($p)
}

function Get-DisplayPath([string]$Full, [string]$Cwd) {
    # Short form for the terminal and the model: relative inside the project folder.
    $root = $Cwd.TrimEnd('\') + '\'
    if ($Full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $Full.Substring($root.Length) }
    return $Full
}

function Limit-Text([string]$Text, [int]$Max) {
    # Long output keeps its beginning and its end, which usually hold the error.
    if ($Text.Length -le $Max) { return $Text }
    $head = [int]($Max * 0.6)
    $tail = $Max - $head
    return $Text.Substring(0, $head) + "`n... [$($Text.Length - $Max) characters left out] ...`n" + $Text.Substring($Text.Length - $tail)
}

function Read-TextFile([string]$Path) {
    # Content of a text file and how to write it back: @{ text; encoding; bom; crlf; binary }.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $probe = [math]::Min($bytes.Length, 8000)
    for ($i = 0; $i -lt $probe; $i++) { if ($bytes[$i] -eq 0) { return @{ binary = $true } } }
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $start = 0
    if ($bom) { $start = 3 }
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $text = $strict.GetString($bytes, $start, $bytes.Length - $start)
        $encoding = 'utf8'
    } catch {
        $text = [System.Text.Encoding]::Default.GetString($bytes)
        $encoding = 'ansi'
    }
    return @{ text = $text; encoding = $encoding; bom = $bom; crlf = $text.Contains("`r`n"); binary = $false }
}

function Write-TextFile([string]$Path, [string]$Text, $Like) {
    # Writes like the file was before (encoding, byte order mark); new files as UTF-8.
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($Like -and $Like.encoding -eq 'ansi') { $enc = [System.Text.Encoding]::Default }
    else { $enc = New-Object System.Text.UTF8Encoding([bool]($Like -and $Like.bom)) }
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Test-ReadFirst($Session, [string]$Path) {
    # '' if the file was read in this session and has not changed since, else the reason.
    if (-not $Session.reads.ContainsKey($Path)) { return 'Read the file first (Read), then change it.' }
    if ((Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks -ne $Session.reads[$Path]) {
        return 'The file has changed since you read it. Read it again before you change it.'
    }
    return ''
}

function Get-LineNumberAt([string]$Text, [int]$Index) {
    # Line (from 1) of a position in $Text; IndexOf runs in .NET, not in a PowerShell loop per character.
    $n = 1
    $pos = $Text.IndexOf("`n")
    while ($pos -ge 0 -and $pos -lt $Index) { $n++; $pos = $Text.IndexOf("`n", $pos + 1) }
    return $n
}

function Get-SnippetLines([string]$Text, [int]$FromLine, [int]$Count) {
    # Lines of $Text with numbers, as Read shows them.
    $lines = $Text.Replace("`r`n", "`n").Split("`n")
    $first = [math]::Max(1, $FromLine)
    $last = [math]::Min($lines.Count, $FromLine + $Count - 1)
    $out = New-Object System.Text.StringBuilder
    for ($n = $first; $n -le $last; $n++) { $null = $out.Append(('{0,6}' -f $n) + "`t" + $lines[$n - 1] + "`n") }
    return $out.ToString().TrimEnd("`n")
}

# --- the tools ------------------------------------------------------------------------------

function Invoke-ToolRead($Session, $A) {
    $path = Resolve-AgentPath (Get-DictValue $A 'file_path') $Session.cwd
    if (Test-Path -LiteralPath $path -PathType Container) { return (New-ToolResult "$path is a folder. Use Glob to list files." $true) }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-ToolResult "File not found: $path" $true) }
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ($script:ImageTypes.ContainsKey($ext)) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -gt 10MB) { return (New-ToolResult "Image too large ($([int]($bytes.Length / 1MB)) MB)." $true) }
        $r = New-ToolResult "Image $(Get-DisplayPath $path $Session.cwd) ($([int]($bytes.Length / 1KB)) KB), shown below."
        $r.image = @{ mime = $script:ImageTypes[$ext]; data = [Convert]::ToBase64String($bytes) }
        $r.info = @{ image = $true }
        return $r
    }
    $file = Read-TextFile $path
    if ($file.binary) { return (New-ToolResult "$path is a binary file and cannot be shown as text." $true) }
    $cfg = Get-AgentSettings
    $lines = $file.text.Replace("`r`n", "`n").Split("`n")
    if ($lines.Count -gt 1 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
    $offset = [math]::Max(1, [int](Get-DictValue $A 'offset'))
    $limit = [int](Get-DictValue $A 'limit')
    if ($limit -le 0) { $limit = [int]$cfg.readLines }
    if ($offset -gt $lines.Count) { return (New-ToolResult "The file has only $($lines.Count) lines." $true) }
    $last = [math]::Min($lines.Count, $offset + $limit - 1)
    $out = New-Object System.Text.StringBuilder
    for ($n = $offset; $n -le $last; $n++) {
        $line = $lines[$n - 1]
        if ($line.Length -gt 2000) { $line = $line.Substring(0, 2000) + ' ...' }
        $null = $out.Append(('{0,6}' -f $n) + "`t" + $line + "`n")
    }
    $Session.reads[$path] = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
    $text = $out.ToString()
    if ($lines.Count -eq 0 -or ($lines.Count -eq 1 -and $lines[0] -eq '')) { $text = '(empty file)' }
    elseif ($last -lt $lines.Count -or $offset -gt 1) { $text += "(lines $offset to $last of $($lines.Count); read more with offset)" }
    $r = New-ToolResult $text
    $r.summary = "$($last - $offset + 1) lines"
    $r.info = @{ lines = ($last - $offset + 1); total = $lines.Count }
    return $r
}

function Invoke-ToolEdit($Session, $A) {
    $path = Resolve-AgentPath (Get-DictValue $A 'file_path') $Session.cwd
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-ToolResult "File not found: $path. To create a file use Write." $true) }
    $why = Test-ReadFirst $Session $path
    if ($why) { return (New-ToolResult $why $true) }
    $file = Read-TextFile $path
    if ($file.binary) { return (New-ToolResult "$path is a binary file." $true) }
    $old = [string](Get-DictValue $A 'old_string')
    $new = [string](Get-DictValue $A 'new_string')
    if ($old -eq '') { return (New-ToolResult 'old_string is empty. To create a file use Write.' $true) }
    if ($old -eq $new) { return (New-ToolResult 'old_string and new_string are the same; nothing to change.' $true) }
    if ($file.crlf) {
        # the model writes line breaks as \n; the file keeps its own
        $old = $old.Replace("`r`n", "`n").Replace("`n", "`r`n")
        $new = $new.Replace("`r`n", "`n").Replace("`n", "`r`n")
    }
    $text = $file.text
    $count = 0
    $at = $text.IndexOf($old, [StringComparison]::Ordinal)
    $first = $at
    while ($at -ge 0) { $count++; $at = $text.IndexOf($old, $at + $old.Length, [StringComparison]::Ordinal) }
    if ($count -eq 0) {
        $hint = ''
        $firstLine = ($old.Replace("`r", '').Split("`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($firstLine -and $text.IndexOf($firstLine.Trim(), [StringComparison]::Ordinal) -ge 0) {
            $hint = ' Its first line occurs in the file, so spaces, indentation or line breaks differ: read the place again and copy it exactly.'
        }
        return (New-ToolResult "old_string was not found in $(Get-DisplayPath $path $Session.cwd).$hint" $true)
    }
    $all = [bool](Get-DictValue $A 'replace_all')
    if ($count -gt 1 -and -not $all) { return (New-ToolResult "old_string occurs $count times. Add surrounding lines to make it unique, or set replace_all." $true) }
    if ($all) { $updated = $text.Replace($old, $new) }
    else { $updated = $text.Substring(0, $first) + $new + $text.Substring($first + $old.Length) }
    Write-TextFile $path $updated $file
    $Session.reads[$path] = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
    $line = Get-LineNumberAt $updated $first
    $newLines = ($new.Split("`n")).Count
    $r = New-ToolResult ("Changed $(Get-DisplayPath $path $Session.cwd) ($count place(s)). Now:`n" + (Get-SnippetLines $updated ([math]::Max(1, $line - 2)) ($newLines + 4)))
    $r.changed = $path
    $r.diff = @{ old = $old.Replace("`r", ''); new = $new.Replace("`r", ''); line = $line }
    return $r
}

function Invoke-ToolWrite($Session, $A) {
    $path = Resolve-AgentPath (Get-DictValue $A 'file_path') $Session.cwd
    $content = [string](Get-DictValue $A 'content')
    $like = $null
    $existed = Test-Path -LiteralPath $path -PathType Leaf
    if ($existed) {
        $why = Test-ReadFirst $Session $path
        if ($why) { return (New-ToolResult $why $true) }
        $like = Read-TextFile $path
        if ($like.crlf) { $content = $content.Replace("`r`n", "`n").Replace("`n", "`r`n") }
    }
    Write-TextFile $path $content $like
    $Session.reads[$path] = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
    $count = ($content.TrimEnd("`r", "`n").Split("`n")).Count
    $verb = 'Created'
    if ($existed) { $verb = 'Replaced' }
    $r = New-ToolResult "$verb $(Get-DisplayPath $path $Session.cwd) ($count lines)."
    $r.changed = $path
    $r.summary = "$count lines"
    $r.info = @{ lines = $count; created = (-not $existed) }
    return $r
}

function ConvertTo-GlobRegex([string]$Pattern) {
    # A glob (**, *, ?, {a,b}) as a regular expression on paths with forward slashes.
    $p = $Pattern.Replace('\', '/')
    while ($p.StartsWith('./')) { $p = $p.Substring(2) }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('^')
    $i = 0
    while ($i -lt $p.Length) {
        $c = $p[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $p.Length -and $p[$i + 1] -eq '*') {
                if ($i + 2 -lt $p.Length -and $p[$i + 2] -eq '/') { $null = $sb.Append('(?:.*/)?'); $i += 3; continue }
                $null = $sb.Append('.*'); $i += 2; continue
            }
            $null = $sb.Append('[^/]*')
        } elseif ($c -eq '?') { $null = $sb.Append('[^/]')
        } elseif ($c -eq '{') { $null = $sb.Append('(?:')
        } elseif ($c -eq '}') { $null = $sb.Append(')')
        } elseif ($c -eq ',') { $null = $sb.Append('|')
        } else { $null = $sb.Append([regex]::Escape([string]$c)) }
        $i++
    }
    $null = $sb.Append('$')
    return New-Object System.Text.RegularExpressions.Regex($sb.ToString(), 'IgnoreCase')
}

function Get-ProjectFiles([string]$Root, [int]$Max = 200000) {
    # Every file below $Root as @{ full; rel } (rel with forward slashes), without the
    # folders of tools and caches. Folders that cannot be read are skipped.
    $out = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0 -and $out.Count -lt $Max) {
        $dir = $stack.Pop()
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) {
                $null = $out.Add(@{ full = $f; rel = $f.Substring($Root.TrimEnd('\').Length + 1).Replace('\', '/') })
            }
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
                if ($script:SkipFolders -notcontains (Split-Path -Leaf $d)) { $stack.Push($d) }
            }
        } catch {}
    }
    return $out
}

function Invoke-ToolGlob($Session, $A) {
    $base = $Session.cwd
    $given = [string](Get-DictValue $A 'path')
    if ($given) { $base = Resolve-AgentPath $given $Session.cwd }
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return (New-ToolResult "Folder not found: $base" $true) }
    $regex = ConvertTo-GlobRegex ([string](Get-DictValue $A 'pattern'))
    $hits = @(Get-ProjectFiles $base | Where-Object { $regex.IsMatch($_.rel) } |
            Sort-Object { [System.IO.File]::GetLastWriteTimeUtc($_.full) } -Descending)
    if ($hits.Count -eq 0) { $r = New-ToolResult 'No files found.'; $r.info = @{ files = 0 }; return $r }
    $shown = @($hits | Select-Object -First 100 | ForEach-Object { Get-DisplayPath $_.full $Session.cwd })
    $text = $shown -join "`n"
    if ($hits.Count -gt 100) { $text += "`n($($hits.Count) files, the 100 newest shown; narrow the pattern)" }
    $r = New-ToolResult $text
    $r.summary = "$($hits.Count) files"
    $r.info = @{ files = $hits.Count }
    return $r
}

function Invoke-ToolGrep($Session, $A) {
    $base = $Session.cwd
    $given = [string](Get-DictValue $A 'path')
    if ($given) { $base = Resolve-AgentPath $given $Session.cwd }
    $options = [System.Text.RegularExpressions.RegexOptions]::Multiline
    if ([bool](Get-DictValue $A 'ignore_case')) { $options = $options -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    try { $regex = New-Object System.Text.RegularExpressions.Regex([string](Get-DictValue $A 'pattern'), $options) }
    catch { return (New-ToolResult "Invalid regular expression: $($_.Exception.InnerException.Message)" $true) }
    if (Test-Path -LiteralPath $base -PathType Leaf) { $files = @(@{ full = $base; rel = (Split-Path -Leaf $base) }) }
    elseif (Test-Path -LiteralPath $base -PathType Container) { $files = @(Get-ProjectFiles $base) }
    else { return (New-ToolResult "Not found: $base" $true) }
    $glob = [string](Get-DictValue $A 'glob')
    $globRegex = $null
    if ($glob) {
        if ($glob.Contains('/')) { $globRegex = ConvertTo-GlobRegex $glob } else { $globRegex = ConvertTo-GlobRegex ('**/' + $glob) }
    }
    $filesOnly = [bool](Get-DictValue $A 'files_only')
    $out = New-Object System.Collections.ArrayList
    $matchedFiles = 0
    foreach ($f in $files) {
        if ($globRegex -and -not $globRegex.IsMatch($f.rel)) { continue }
        try { if ((New-Object System.IO.FileInfo($f.full)).Length -gt 5MB) { continue } } catch { continue }
        $file = $null
        try { $file = Read-TextFile $f.full } catch { continue }
        if ($file.binary) { continue }
        $text = $file.text
        $found = $regex.Matches($text)
        if ($found.Count -eq 0) { continue }
        $matchedFiles++
        $shown = Get-DisplayPath $f.full $Session.cwd
        if ($filesOnly) { $null = $out.Add($shown); if ($out.Count -ge 200) { break }; continue }
        $lastLine = -1
        # matches come in order: count the line breaks once, from one match to the next
        $lineNo = 1
        $pos = $text.IndexOf("`n")
        foreach ($m in $found) {
            while ($pos -ge 0 -and $pos -lt $m.Index) { $lineNo++; $pos = $text.IndexOf("`n", $pos + 1) }
            if ($lineNo -eq $lastLine) { continue }
            $lastLine = $lineNo
            $startIdx = $text.LastIndexOf("`n", [math]::Max(0, $m.Index - 1)) + 1
            if ($m.Index -eq 0) { $startIdx = 0 }
            $endIdx = $text.IndexOf("`n", $m.Index)
            if ($endIdx -lt 0) { $endIdx = $text.Length }
            $lineText = $text.Substring($startIdx, $endIdx - $startIdx).TrimEnd("`r")
            if ($lineText.Length -gt 300) { $lineText = $lineText.Substring(0, 300) + ' ...' }
            $null = $out.Add("${shown}:${lineNo}:$lineText")
            if ($out.Count -ge 200) { break }
        }
        if ($out.Count -ge 200) { break }
    }
    if ($out.Count -eq 0) { $r = New-ToolResult 'No matches.'; $r.info = @{ files = 0; lines = 0 }; return $r }
    $text = ($out -join "`n")
    if ($out.Count -ge 200) { $text += "`n(first 200 shown; narrow the pattern or path)" }
    $r = New-ToolResult $text
    $r.summary = "$($out.Count) lines in $matchedFiles files"
    if ($filesOnly) { $r.summary = "$($out.Count) files" }
    $r.info = @{ lines = $out.Count; files = $matchedFiles; filesOnly = $filesOnly }
    return $r
}

function Invoke-ToolShell($Session, [string]$Kind, $A, [scriptblock]$ShouldStop) {
    # Runs a command from a temporary script file (no quoting trouble) with a time limit;
    # Esc or Ctrl+C at the terminal stops it with all its child processes.
    $cfg = Get-AgentSettings
    $command = [string](Get-DictValue $A 'command')
    if (-not $command.Trim()) { return (New-ToolResult 'The command is empty.' $true) }
    $timeout = [int](Get-DictValue $A 'timeout')
    if ($timeout -le 0) { $timeout = [int]$cfg.commandTimeoutSeconds }
    $timeout = [math]::Min($timeout, [int]$cfg.commandMaxSeconds)
    $dir = Join-Path $env:TEMP 'unzensiert'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($Kind -eq 'Bash') {
        $script = Join-Path $dir ("cmd-" + [guid]::NewGuid().ToString('N').Substring(0, 10) + '.sh')
        [System.IO.File]::WriteAllText($script, $command.Replace("`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
        $psi.FileName = $Session.gitBash
        $psi.Arguments = '"' + $script.Replace('\', '/') + '"'
    } else {
        $script = Join-Path $dir ("cmd-" + [guid]::NewGuid().ToString('N').Substring(0, 10) + '.ps1')
        $prefix = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; `$OutputEncoding = [System.Text.Encoding]::UTF8; `$ProgressPreference = 'SilentlyContinue'`r`n"
        # the exit code of the last program the command called, as a terminal would show it
        $suffix = "`r`nif (`$LASTEXITCODE) { exit `$LASTEXITCODE }`r`n"
        [System.IO.File]::WriteAllText($script, $prefix + $command + $suffix, (New-Object System.Text.UTF8Encoding($true)))
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script + '"'
    }
    $psi.WorkingDirectory = $Session.cwd
    # Python writes its output as UTF-8 even into a pipe (otherwise in the code page of
    # Windows, where printing other characters fails)
    $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stopped = ''
    try {
        $proc = Start-ChildProcess $psi
        $proc.StandardInput.Close()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.WaitForExit(100)) {
            if ($watch.Elapsed.TotalSeconds -ge $timeout) { $stopped = "[stopped after $timeout s: time limit]"; break }
            if ($ShouldStop -and (& $ShouldStop)) { $stopped = '[stopped by the user]'; break }
        }
        if ($stopped) {
            & cmd /c "taskkill /PID $($proc.Id) /T /F >nul 2>&1"
            $null = $proc.WaitForExit(5000)
        }
        $null = $outTask.Wait(5000); $null = $errTask.Wait(5000)
        $output = [string]$outTask.Result
        $errors = [string]$errTask.Result
        $code = 0
        if (-not $stopped) { $code = $proc.ExitCode }
    } finally {
        Remove-Item -Force -Path $script -ErrorAction SilentlyContinue
    }
    $text = $output.Replace("`r`n", "`n").TrimEnd()
    if ($errors.Trim()) { $text = ($text + "`n" + $errors.Replace("`r`n", "`n").TrimEnd()).Trim() }
    $text = Limit-Text $text ([int]$cfg.toolResultChars)
    $info = @{ exit = $code; seconds = $watch.Elapsed.TotalSeconds; stopped = $stopped; output = $text }
    if (-not $text) { $text = '(no output)' }
    if ($stopped) { $text += "`n$stopped" }
    elseif ($code -ne 0) { $text += "`n[exit code $code]" }
    $r = New-ToolResult $text ([bool]$stopped)
    $r.summary = "exit code $code, $([math]::Round($watch.Elapsed.TotalSeconds, 1)) s"
    if ($stopped) { $r.summary = $stopped.Trim('[', ']') }
    $r.userStop = ($stopped -eq '[stopped by the user]')
    $r.info = $info
    return $r
}

function Invoke-AgentTool($Session, [string]$Name, $A, [scriptblock]$ShouldStop) {
    # Runs one tool; errors inside a tool go back to the model as text.
    try {
        switch ($Name) {
            'Read' { return (Invoke-ToolRead $Session $A) }
            'Edit' { return (Invoke-ToolEdit $Session $A) }
            'Write' { return (Invoke-ToolWrite $Session $A) }
            'Glob' { return (Invoke-ToolGlob $Session $A) }
            'Grep' { return (Invoke-ToolGrep $Session $A) }
            'Bash' {
                if (-not $Session.gitBash) { return (New-ToolResult 'Git Bash is not installed; use the PowerShell tool.' $true) }
                return (Invoke-ToolShell $Session 'Bash' $A $ShouldStop)
            }
            'PowerShell' { return (Invoke-ToolShell $Session 'PowerShell' $A $ShouldStop) }
            default { return (New-ToolResult "There is no tool '$Name'. Tools: Bash, PowerShell, Read, Edit, Write, Glob, Grep." $true) }
        }
    } catch {
        return (New-ToolResult "The tool $Name failed: $($_.Exception.Message)" $true)
    }
}
