# Deletes that would cost the user more than the project: the part of the guard that reads a
# command line for them (rm -r, rd /s, Remove-Item, find -delete, Get-ChildItem | Remove-Item,
# xargs rm, loops, robocopy /mir, rsync --delete, moving a user folder away). A net for the
# accidents of a model in the spellings it uses, not a wall against code that hides a delete.
# Loaded by GuardRules.ps1, which holds Set-Verdict and the paths. Keep this file ASCII-only.
# Description: docs\security.md.

# signs that separate commands, kept apart while they stand between quotes
$script:KeptSigns = @{ ';' = [string][char]0xE010; '|' = [string][char]0xE011; '&' = [string][char]0xE012; "`r" = [string][char]0xE013; "`n" = [string][char]0xE014 }
# a switch that stands for "with everything below"
$script:RecursiveFlag = '^--r(e(c(u(r(s(i(ve?)?)?)?)?)?)?)?$|^-(r|re|rec|recu|recur|recurs|recurse)(:\$?(true|1))?$|^/s$'
# variables the shells set by themselves
$script:BashOwnVariables = '^(_|BASH\w*|COMP_\w+|DIRSTACK|EPOCH\w+|EUID|FUNCNAME|GROUPS|HISTCMD|HOME|HOSTNAME|HOSTTYPE|IFS|LINENO|MACHTYPE|MSYS\w*|MINGW\w*|OLDPWD|OPT\w+|OSTYPE|PATH|PIPESTATUS|PPID|PS[0-9]|PWD|RANDOM|REPLY|SECONDS|SHELL\w*|SHLVL|SRANDOM|TERM|UID|USER|WINDIR)$'
$script:PowerShellOwnVariables = '^(_|args|input|this|home|pwd|pid|profile|host|error|matches|null|true|false|event\w*|foreach|switch|stacktrace|nestedpromptlevel|lastexitcode|executioncontext|myinvocation|outputencoding|is\w+|ps\w+|\w*preference|maximum\w+|shellid|consolefilename|enabledexperimentalfeatures|env|script|global|local|private|using|variable|function)$'

# the words a line needs to be looked at; most lines hold none of them
$script:DeleteWords = '(?i)\b(rm|del|erase|rd|rmdir|ri|Remove-Item|unlink|shred|truncate|Clear-Content|clc|robocopy|rsync|forfiles|find|mv|move|mi|ren|rename|rni|Move-Item|Rename-Item|Set-Content|Out-File|Add-Content)\b|\.(Delete|MoveTo)\s*\('

# --- words ------------------------------------------------------------------------------

function Get-CommandTokens([string]$Text) {
    # The words of a command as written; what touches quotes belongs to the same word ("$DIR"/*).
    return @([regex]::Matches($Text, '(?:"[^"]*"|''[^'']*''|[^\s"''])+') | ForEach-Object { $_.Value })
}

function Remove-Quotes([string]$Word) { return $Word.Replace('"', '').Replace("'", '') }

function Remove-GroupEnd([string]$Word) {
    # The last word of a group, "~)" or "x}", without the sign that closes the group; ${HOME} stays.
    $w = $Word
    foreach ($pair in @('(', ')'), @('{', '}')) {
        while ($w.EndsWith($pair[1]) -and $w.Split($pair[1][0]).Count -gt $w.Split($pair[0][0]).Count) { $w = $w.Substring(0, $w.Length - 1) }
    }
    return $w
}

function Get-ProgramName([string]$Token) {
    # The name of a program in a command line without path, .exe, quotes and the signs shells
    # skip (r""m, \rm, r\m, "(rm", Microsoft.PowerShell.Management\Remove-Item).
    $plain = ($Token -replace '["''`^]', '').TrimStart('(', '{', '!', '&', '@')
    $bare = $plain.Replace('\', '')
    if ($bare -match '^(rm|rmdir|find)$') { return $bare }
    return ($plain -replace '^.*[\\/]', '' -replace '(?i)\.exe$', '')
}

function Expand-Braces([string]$Word) {
    # ~/{Documents,Pictures} -> two words (one pair of braces, no nesting).
    $m = [regex]::Match($Word, '^(.*?)\{([^{}]*,[^{}]*)\}(.*)$')
    if (-not $m.Success) { return @($Word) }
    return @($m.Groups[2].Value.Split(',') | ForEach-Object { $m.Groups[1].Value + $_ + $m.Groups[3].Value })
}

function Get-ListedFolders($Words, [bool]$Power) {
    # The folders a listing names: Get-ChildItem [-Path] a,b -Filter x; ls a b. None means here.
    $named = @()
    $free = @()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $w = [string]$Words[$i]
        if ($w -match '^-(Path|Pat|Pa|LiteralPath|Lit\w*|LP|PSPath)(:(.+))?$') {
            if ($Matches[3]) { $named += $Matches[3] } elseif ($i + 1 -lt $Words.Count) { $i++; $named += [string]$Words[$i] }
            continue
        }
        if ($w -match '^-(Fi\w*|Inc\w*|Exc\w*|De\w*|At\w*|ErrorAction|EA)$') { $i++; continue }
        if ($w -match '^[-{|}]') { if ($w -match '^[{|}]') { break }; continue }
        $free += $w
    }
    if ($named.Count -eq 0 -and $free.Count -gt 0) { if ($Power) { $named = @($free[0]) } else { $named = $free } }
    if ($Power) { $named = @($named | ForEach-Object { $_.Split(',') } | Where-Object { $_ }) }
    if ($named.Count -eq 0) { $named = @('.') }
    return $named
}

# --- variables of the line --------------------------------------------------------------

function Get-ValueWords([string]$Value, [string]$Kind) {
    # What the right side of an assignment (or the list of a loop) stands for, as far as it can be
    # read: words, Join-Path, Resolve-Path and Get-Item, folders of the user, a listing.
    $v = $Value.Trim()
    if ($Kind -eq 'sh') { return @(Get-CommandTokens $v | ForEach-Object { Remove-Quotes $_ }) }
    $v = $v.TrimEnd(')', ' ')
    if ($v.StartsWith('@(')) { $v = $v.Substring(2) }
    $v = $v.TrimStart('(', ' ')
    $word = '("[^"]*"|''[^'']*''|[^\s,()]+)'
    $m = [regex]::Match($v, '^(?i)(?:Resolve-Path|Convert-Path|Get-Item|gi)\s+(?:-\w+\s+)*' + $word)
    if ($m.Success) { return @(Remove-Quotes $m.Groups[1].Value) }
    $m = [regex]::Match($v, '^(?i)\[(?:System\.)?Environment\]::GetFolderPath\(\s*["'']?(?:\[[\w.+]+\]::)?(\w+)')
    if ($m.Success) { try { $f = [Environment]::GetFolderPath($m.Groups[1].Value); if ($f) { return @($f) } } catch {}; return @() }
    $m = [regex]::Match($v, '^(?i)(?:Get-ChildItem|gci|dir|ls)\b(.*)$')
    if ($m.Success) { return @(Get-ListedFolders @(Get-CommandTokens $m.Groups[1].Value | ForEach-Object { Remove-Quotes $_ }) $true) }
    if ($v -match '^("[^"]*"|''[^'']*''|[^\s,()]+)(\s*,\s*("[^"]*"|''[^'']*''|[^\s,()]+))*$') { return @($v.Split(',') | ForEach-Object { (Remove-Quotes $_).Trim() } | Where-Object { $_ }) }
    return @()
}

function Get-LineVariables([string]$Command) {
    # What a command line says about its own variables: name -> the words it may stand for. Simple
    # assignments (X=..., $x = ...) and loops (for X in ..., foreach ($x in ...), for %i in (...)).
    $vars = @{}
    $add = {
        param([string]$name, $words)
        if (-not $vars.ContainsKey($name)) { $vars[$name] = New-Object System.Collections.ArrayList }
        foreach ($w in @($words)) { if ($vars[$name].Count -lt 20) { $null = $vars[$name].Add([string]$w) } }
    }
    if ($Command.Contains('=')) {
        foreach ($m in [regex]::Matches($Command, '(?<![\w$%./\\:-])([A-Za-z_]\w*)=((?:"[^"]*"|''[^'']*''|[^\s;&|()"''])*)')) { & $add $m.Groups[1].Value @(Remove-Quotes $m.Groups[2].Value) }
        foreach ($m in [regex]::Matches($Command, '(?i)\$(?:(?:script|global|local|private):)?([A-Za-z_]\w*)\s*=(?!=)\s*((?:"[^"]*"|''[^'']*''|[^;|\r\n"''])+)')) { & $add $m.Groups[1].Value @(Get-ValueWords $m.Groups[2].Value 'ps') }
    }
    if ($Command -match '\bfor') {
        foreach ($m in [regex]::Matches($Command, '\bfor\s+([A-Za-z_]\w*)\s+in\s+([^;\r\n]*)')) { & $add $m.Groups[1].Value @(Get-ValueWords $m.Groups[2].Value 'sh') }
        foreach ($m in [regex]::Matches($Command, '(?i)\bforeach\s*\(\s*\$(\w+)\s+in\s+([^{]*?)\)\s*\{')) { & $add $m.Groups[1].Value @(Get-ValueWords $m.Groups[2].Value 'ps') }
        foreach ($m in [regex]::Matches($Command, '(?i)\bfor\s+(?:/[a-z]\s+)?(?:"[^"]*"\s+)?%{1,2}([a-z])\s+in\s+\(([^)]*)\)\s+do\b')) { & $add ('%' + $m.Groups[1].Value) @(Get-ValueWords $m.Groups[2].Value 'sh') }
    }
    return $vars
}

function Expand-LineVariables([string]$Word, $Vars, [int]$Depth = 0) {
    # A word with the variables of its own line filled in: every word it may stand for.
    if ($Depth -ge 3 -or $Vars.Count -eq 0) { return @($Word) }
    foreach ($m in [regex]::Matches($Word, '\$\{?([A-Za-z_]\w*)(?:[:%#/^,@][^}]*)?\}?|%%?([A-Za-z])(?![\w%])')) {
        $name = $m.Groups[1].Value
        if (-not $name) { $name = '%' + $m.Groups[2].Value }
        if (-not $Vars.ContainsKey($name)) { continue }
        # $x.FullName is the same file; a property that is none of these says nothing
        $after = $Word.Substring($m.Index + $m.Length) -replace '^\.(FullName|Name|Path|PSPath|ProviderPath)\b', ''
        $out = @()
        foreach ($v in $Vars[$name]) { $out += @(Expand-LineVariables ($Word.Substring(0, $m.Index) + $v + $after) $Vars ($Depth + 1)) }
        return $out
    }
    return @($Word)
}

function Remove-UnsetVariables([string]$Raw, [string]$Word, [string]$Command, $Vars, [string]$Tool) {
    # Every command has a shell of its own: a variable that neither the line nor the environment
    # sets is empty there, and "$DIR/*" means /*. Returns @{ word; names }; names is empty when
    # there is no such variable (or it cannot be told).
    $r = @{ word = $Word; names = @() }
    if ($Word.IndexOf('$') -lt 0) { return $r }
    # text that goes into a file, '$X' is no variable, another script may set it
    if ($Command -match '<<|@["'']\s*[\r\n]' -or $Raw -match '''[^'']*\$[^'']*''') { return $r }
    if ($Command -match '(^|[\s;&|({])(source|eval|\.|Import-Module|ipmo|iex|Invoke-Expression)\s') { return $r }
    $own = $script:BashOwnVariables
    if ($Tool -eq 'PowerShell') { $own = $script:PowerShellOwnVariables }
    foreach ($m in @([regex]::Matches($Word, '(?<![\\`])\$(?:\{([A-Za-z_]\w*)\}|([A-Za-z_]\w*)(?![\w:(\[]))'))[-1..-20]) {
        if ($null -eq $m) { continue }
        $name = $m.Groups[1].Value + $m.Groups[2].Value
        if ($Vars.ContainsKey($name) -or $name -match $own) { continue }
        if ($Tool -eq 'PowerShell') {
            # $x = 1; param($x); foreach ($x in ...); $x, $y = ...; -OutVariable x
            if ([regex]::IsMatch($Command, '(?i)\$(\w+:)?' + $name + '\s*(=|\+=|,|\)|in\b)|\[ref\]\s*\$' + $name + '\b|(?<![\w$:{.])' + $name + '(?!\w)')) { continue }
            if ($Word.Substring($m.Index + $m.Length) -match '^\.') { continue }
        } else {
            if ([Environment]::GetEnvironmentVariable($name)) { continue }
            # read X, for X in, X+=, printf -v X
            if ([regex]::IsMatch($Command, '(?<![\w${])' + $name + '(?!\w)')) { continue }
        }
        $r.word = $r.word.Remove($m.Index, $m.Length)
        $r.names += $name
    }
    return $r
}

# --- one target -------------------------------------------------------------------------

function Get-DeleteLists($Config) {
    return @{ critical = @(Get-ConfigPaths $Config 'criticalPaths'); system = @(Get-ConfigPaths $Config 'systemPaths'); free = @(Get-ConfigPaths $Config 'freeDeleteRoots') }
}

function Test-DeleteTarget([string]$Raw, [string]$Dir, [string]$Cwd, $Lists, [string]$What = 'Recursive delete', [string]$Level = 'all') {
    # Judges one target of a command that deletes, overwrites or moves away. $Level: all (a folder
    # with everything below), some (only files of certain names), files (single files, not the
    # folders). Only "all" is refused in system folders and whole user folders; the others ask.
    foreach ($word in @(Expand-Braces (Remove-Quotes $Raw))) {
        $word = Remove-DevicePrefix $word
        # "dir/*" and "dir/." mean the whole content of dir
        $target = $word -replace '[\\/]+(\*|\.\*|\*\.\*|\.)$', ''
        if ($target -in @('*', '.*', '*.*', '.')) { $target = '.' }
        if ($target -match '^[a-zA-Z]:$') { $target += '\' }
        if (-not $target) { $target = '/' }
        if (-not $Dir -and -not ($target -match '^([a-zA-Z]:|[\\/~$%])')) {
            # relative, the folder is not known here: only "everything" asks
            if ($target -eq '.' -and $Level -eq 'all') { Set-Verdict 'ask' 'delete-outside' "$What of everything in a folder that is not known here ($word)" }
            continue
        }
        $found = @(Get-CommandPaths $target $Dir)
        # a variable or expression stays free (normal work), Env:X and addresses are no files
        if ($found.Count -eq 0 -and $Level -eq 'all' -and $target -notmatch '[$%`(){}<>*?]|^\w{2,}:') { Set-Verdict 'ask' 'delete-outside' "$What of a target that cannot be read ($target)" }
        foreach ($path in $found) { Test-DeletePath $path $target $Cwd $Lists $What $Level }
    }
}

function Test-DeletePath([string]$Path, [string]$Target, [string]$Cwd, $Lists, [string]$What, [string]$Level) {
    # Judges one full path of a delete (it may hold wildcards).
    $hard = 'deny'
    if ($Level -ne 'all') { $hard = 'ask' }
    if ($Path -like '<shell-root>*') { Set-Verdict $hard 'delete-system' "$What in the root folder of the shell ($Target)"; return }
    if ($Path -match '^\\\\\.\\\w+$') { return }                                # a file called nul: a device, nothing to lose
    $inner = $false
    if ($Path -match '[*?]') {
        $hit = @($Lists.critical | Where-Object { $_ -like $Path -or $_ -like "$Path\*" }) | Select-Object -First 1
        if ($hit -and $Level -ne 'files') {
            if ($Level -eq 'some') { Set-Verdict 'ask' 'delete-outside' "$What in $hit ($Target)" } else { Set-Verdict 'deny' 'delete-system' "$What of $Target (contains $hit)" }
            return
        }
        # the folder of the project itself, or one above it, among what the wildcard meets
        if ($Cwd -and ($Cwd -like $Path -or $Cwd -like "$Path\*")) { Set-Verdict 'ask' 'delete-project' "$What of the whole project folder ($Target)"; return }
        $Path = Get-WildParent $Path
        if (-not $Path) { return }
        $inner = $true
    }
    # what a junction or link really points to counts as well
    $real = $null
    if ($Path -match '^[a-zA-Z]:\\') { $real = Resolve-RealPath $Path }
    foreach ($p in @(@($Path, $real) | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not $inner) {
            if ($p -match '^[a-zA-Z]:\\?$' -or $p -match '^\\\\[^\\]+\\[^\\]+\\?$') {
                Set-Verdict $hard 'delete-system' "$What of a whole drive ($p)"; continue
            }
            $hit = @($Lists.critical | Where-Object { Test-PathInside $_ $p }) | Select-Object -First 1
            if ($hit) {
                if ($Level -ne 'all') { Set-Verdict 'ask' 'delete-outside' "$What in $p" } else { Set-Verdict 'deny' 'delete-system' "$What of $p (contains or is $hit)" }
                continue
            }
        }
        $hit = @($Lists.system | Where-Object { Test-PathInside $p $_ }) | Select-Object -First 1
        if ($hit) { Set-Verdict $hard 'delete-system' "$What in a system folder ($p)"; continue }
        # the project as a whole, also when it lies in the temp folder
        if ($Cwd -and -not $inner -and (Test-PathInside $Cwd $p) -and -not ($p -ieq $Cwd -and $Level -eq 'files')) {
            Set-Verdict 'ask' 'delete-project' "$What of the whole project folder ($p)"; continue
        }
        if (@($Lists.free | Where-Object { Test-PathInside $p $_ }).Count -gt 0) { continue }
        if ($Cwd -and (Test-PathInside $p $Cwd)) {
            if ($p -match '\\\.git$') { Set-Verdict 'ask' 'delete-project' "Deleting the git history ($p)" }
            continue
        }
        Set-Verdict 'ask' 'delete-outside' "$What outside the project folder ($p)"
    }
}

function Test-ListedTargets($Listed, [string]$Dir, [string]$Cwd, $Lists, [string]$Command, $Vars, [string]$What, [string]$Level = 'all') {
    # The content of listed folders goes (find ... -delete, Get-ChildItem ... | Remove-Item). Files
    # of certain names below the project are normal work.
    $some = ($Command -match '(?i)\s-(Filter|Include|name|iname|path|ipath|regex|newer|[acm]time|[acm]min|size|empty)\b|\bWhere-Object\b|\|\s*(\?|where|grep|head|tail|Select-Object)\s')
    if ($some -and $Level -eq 'all') { $Level = 'some' }
    foreach ($x in @($Listed)) {
        foreach ($word in @(Expand-LineVariables $x $Vars)) {
            if ($Dir -and ($some -or $word -match '[*?]') -and ((Resolve-CommandPath ($word -replace '[\\/]*[^\\/]*[*?][^\\/]*$', '') $Dir) -ieq $Cwd)) { continue }
            Test-DeleteTarget $word $Dir $Cwd $Lists $What $Level
        }
    }
}

# --- a command line ---------------------------------------------------------------------

function Test-RecursiveDelete([string]$Command, [string]$Cwd, $Config, [int]$Depth = 0, [string]$StartDir = '', [string]$Tool = 'Bash', $Lists = $null, $Vars = $null) {
    # Finds the deletes of a command line and judges each target: system folders and whole user
    # folders are denied, anything else outside the project needs the user's yes, everything
    # below the project folder is free.
    if ($Command -notmatch $script:DeleteWords -and ($Command -replace '["''`^\\]', '') -notmatch $script:DeleteWords) { return }
    if ($null -eq $Lists) { $Lists = Get-DeleteLists $Config }
    # a line that goes on in the next one; "$($_.FullName)"; (Join-Path a b)
    $Command = [regex]::Replace($Command, '[\\`^]\r?\n', ' ')
    $Command = [regex]::Replace($Command, '\$\(\s*(\$[\w.]+)\s*\)', '$1')
    for ($i = 0; $i -lt 3 -and $Command -match '(?i)\bJoin-Path\b'; $i++) {
        $Command = [regex]::Replace($Command, '(?i)\(?\s*\bJoin-Path\s+(?:-Path\s+)?("[^"]*"|''[^'']*''|[^\s,()]+)\s+(?:-ChildPath\s+)?("[^"]*"|''[^'']*''|[^\s,();|]+)\s*\)?',
            [System.Text.RegularExpressions.MatchEvaluator] { param($m) ' "' + (Remove-Quotes $m.Groups[1].Value).TrimEnd('\', '/') + '\' + (Remove-Quotes $m.Groups[2].Value) + '" ' })
    }
    if ($null -eq $Vars) { $Vars = Get-LineVariables $Command }
    Test-DeleteLine $Command $Cwd $Config $Depth $StartDir $Tool $Lists $Vars
    # once more with the signs between quotes as text: rm -rf "a;b" ~
    if ($Command -match '"[^"]*[;|&\r\n][^"]*"|''[^'']*[;|&\r\n][^'']*''') {
        $kept = [regex]::Replace($Command, '"[^"]*"|''[^'']*''', [System.Text.RegularExpressions.MatchEvaluator] {
                param($m)
                $t = $m.Value
                foreach ($k in $script:KeptSigns.Keys) { $t = $t.Replace($k, $script:KeptSigns[$k]) }
                $t
            })
        Test-DeleteLine $kept $Cwd $Config $Depth $StartDir $Tool $Lists $Vars
    }
}

function Test-DeleteLine([string]$Command, [string]$Cwd, $Config, [int]$Depth, [string]$StartDir, [string]$Tool, $Lists, $Vars) {
    # $Cwd is the project folder; $dir follows "cd" inside the command. A "cd" that fails leaves the line
    # where it was: cd build; rm -rf * empties the project when there is no build (with && it does not).
    $dir = $Cwd
    if ($Depth -gt 0) { $dir = $StartDir }
    $others = @()                                             # folders the line stands in if a cd failed
    $waiting = @()                                            # the same, once the chain of && has ended
    $touched = $false                                         # something before may have taken a folder away
    $pipe = @{ listed = @(); items = @() }                    # what a listing before a pipe named; what $_ stands for
    $separator = ''
    # output joined to another stream holds an & that separates nothing
    $Command = [regex]::Replace($Command, '\d?>&\d', ' ')
    foreach ($segment in [regex]::Split($Command, '(\|\||&&|[;|&\r\n])')) {
        if ($segment -match '^(\|\||&&|[;|&\r\n])$') { $separator = $segment; continue }
        foreach ($k in $script:KeptSigns.Keys) { $segment = $segment.Replace($script:KeptSigns[$k], $k) }
        # redirections such as "2>/dev/null" are not targets
        $segment = [regex]::Replace($segment, '(^|\s)\d*(>>?|<)\s*("[^"]*"|''[^'']*''|\S+)', ' ')
        # r""m: the shell joins what stands next to empty quotes
        $segment = [regex]::Replace($segment, '(?<=\w)(""|'''')(?=\w)', '')
        $tokens = @(Get-CommandTokens $segment)
        if ($tokens.Count -eq 0) { continue }
        $words = @($tokens | ForEach-Object { Remove-Quotes $_ })
        $piped = ($separator -eq '|')
        if ($separator -ne '&&') { $others = @((@($others) + $waiting) | Select-Object -Unique); $waiting = @() }
        $separator = ''
        if (-not $piped) { $pipe.listed = @() }
        $places = @(@($dir) + $others)
        # a quoted command line, as in: cmd /c "rd /s /q C:\x", bash -c 'rm -rf ~'
        if ($Depth -lt 2) {
            $inside = @([regex]::Matches($segment, '"([^"]*\s[^"]*)"|''([^'']*\s[^'']*)''') | ForEach-Object { $_.Groups[1].Value + $_.Groups[2].Value })
            # cmd takes the outermost quotes away, others may stand between them
            $m = [regex]::Match($segment, '(?i)\bcmd(?:\.exe)?\s+(?:/\w+\s+)*/[ck]\s+"(.*".*)"')
            if ($m.Success) { $inside += $m.Groups[1].Value }
            foreach ($line in $inside) { foreach ($place in $places) { Test-RecursiveDelete $line $Cwd $Config ($Depth + 1) $place $Tool $Lists $Vars } }
        }
        # follow "cd" so that relative targets are judged from the right folder
        for ($i = 0; $i -lt $words.Count - 1; $i++) {
            if ((Get-ProgramName $tokens[$i]) -match '^(cd|chdir|pushd|Set-Location|sl)$' -and $words[$i + 1] -notmatch '^[-/][a-zA-Z]$') {
                $next = $null
                if ($dir) { $next = Resolve-CommandPath (@(Expand-LineVariables $words[$i + 1] $Vars)[0]) $dir }
                if ($next -and $next -like '<shell-root>*') { $next = $null }
                if (-not $next -or $touched -or -not [System.IO.Directory]::Exists($next)) { $waiting += $dir }
                $dir = $next
            }
        }
        # "cd" alone goes to the user folder in Bash
        if ($tokens.Count -eq 1 -and $tokens[0] -ceq 'cd' -and $Tool -eq 'Bash') { $dir = $env:USERPROFILE }
        if ($segment -match '(?i)\b(rm|rmdir|rd|del|ri|Remove-Item|mv|move|mi|Move-Item|ren|Rename-Item)\b') { $touched = $true }
        # find ... | while read f; do rm "$f"
        if ($piped -and @($pipe.listed).Count -gt 0) {
            $m = [regex]::Match($segment, '\bread\s+(?:-\w+\s+(?:""|''''|\$''[^'']*'')?\s*)*([A-Za-z_]\w*)\s*$')
            if ($m.Success -and -not $Vars.ContainsKey($m.Groups[1].Value)) { $Vars[$m.Groups[1].Value] = @($pipe.listed) }
        }
        $found = $null
        foreach ($place in @(@($dir) + $others)) {
            $own = @{ listed = $pipe.listed; items = $pipe.items }
            Test-DeleteSegment $segment $tokens $words $place $own $piped $Command $Cwd $Depth $Tool $Lists $Vars
            if (-not $found) { $found = $own }
        }
        $pipe = $found
    }
}

function Test-DeleteSegment([string]$segment, $tokens, $words, [string]$dir, $pipe, [bool]$piped, [string]$Command, [string]$Cwd, [int]$Depth, [string]$Tool, $Lists, $Vars) {
    # One command of a line, run in the folder $dir ('' = not known). $pipe: listed and items, see
    # Test-DeleteLine; what the command lists itself is written into it.
    $listed = @($pipe.listed)
    $items = @($pipe.items)
    # the script block of ForEach-Object calls a method of what comes in
    if ($items.Count -gt 0 -and $segment -match '\$(_|PSItem)\.(Delete|MoveTo)\s*\(') { Test-ListedTargets $items $dir $Cwd $Lists $Command $Vars 'Deleting the listed content' }
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        # x=rm; $x -rf ~
        if ($Vars.Count -gt 0 -and $words[$i] -match '^\$\{?([A-Za-z_]\w*)\}?$' -and $Vars.ContainsKey($Matches[1]) -and $Vars[$Matches[1]].Count -gt 0) { $token = [string]$Vars[$Matches[1]][0] }
        $name = Get-ProgramName $token
        if ($name -notmatch '^[A-Za-z][\w.-]*$') { continue }
        $rest = @()
        $restRaw = @()
        for ($j = $i + 1; $j -lt $tokens.Count; $j++) {
            $w = Remove-GroupEnd $words[$j]
            if ($w) { $rest += $w; $restRaw += $tokens[$j] }
        }

        if ($name -match '^(Get-ChildItem|gci|dir|ls|Get-Item|gi)$') {
            $listed = @(Get-ListedFolders $rest ($Tool -eq 'PowerShell'))
            $items = $listed
            continue
        }
        if ($name -ceq 'find' -and $Tool -eq 'Bash') {
            $places = @()
            foreach ($x in $rest) { if ($x -match '^[-(!\\]') { break }; $places += $x }
            if ($places.Count -eq 0) { $places = @('.') }
            $listed = $places
            $items = $places
            if ($segment -match '\s-delete(\s|$|\))' -or $segment -match '\s-(exec(dir)?|ok(dir)?)\s+(\S*[\\/])?(rm|shred|unlink)\b') {
                Test-ListedTargets $places $dir $Cwd $Lists $segment $Vars 'Deleting with find'
            } elseif ($segment -match '\s-(exec(dir)?|ok(dir)?)\s+(\S*[\\/])?(sh|bash|dash|zsh|truncate|mv|dd|tee|sed|perl|python\w*|chmod|cp)\b') {
                # commands on files of other folders; below the project they are free
                foreach ($x in $places) {
                    foreach ($word in @(Expand-LineVariables $x $Vars)) {
                        $p = $null
                        if ($dir -or $word -match '^([a-zA-Z]:|[\\/~$%])') { $p = Resolve-CommandPath $word $dir }
                        if ($p -and -not ($Cwd -and (Test-PathInside $p $Cwd))) { Test-DeleteTarget $word $dir $Cwd $Lists 'Changing the files found' 'some' }
                    }
                }
            }
            continue
        }
        if ($name -match '^robocopy$' -and $segment -match '(?i)\s/(mir|purge|move|mov)\b') {
            $names = @($rest | Where-Object { $_ -notmatch '^/[a-zA-Z]+(:|$)' })
            # the source goes with /move, the rest of the target with /mir and /purge
            $at = 1
            if ($segment -notmatch '(?i)\s/(mir|purge)\b') { $at = 0 }
            if ($names.Count -gt $at) { foreach ($word in @(Expand-LineVariables $names[$at] $Vars)) { Test-DeleteTarget $word $dir $Cwd $Lists 'Mirroring over the folder' } }
            continue
        }
        if ($name -match '^rsync$' -and $segment -match '\s--(delete|del)') {
            $names = @($rest | Where-Object { $_ -notmatch '^-' })
            if ($names.Count -ge 2) { foreach ($word in @(Expand-LineVariables $names[$names.Count - 1] $Vars)) { Test-DeleteTarget $word $dir $Cwd $Lists 'Mirroring over the folder' } }
            continue
        }
        if ($name -match '^forfiles$' -and $segment -match '(?i)\b(del|erase|rd|rmdir)\b') {
            $at = [array]::FindIndex([string[]]$rest, [Predicate[string]] { param($x) $x -match '^(?i)/p$' })
            $place = '.'
            if ($at -ge 0 -and $at + 1 -lt $rest.Count) { $place = $rest[$at + 1] }
            Test-DeleteTarget $place $dir $Cwd $Lists 'Deleting with forfiles' 'some'
            continue
        }
        if ($name -match '^(mv|move|Move-Item|mi|ren|rename|Rename-Item|rni)$') {
            $names = @($rest | Where-Object { $_ -notmatch '^-' -and $_ -notmatch '^/[a-zA-Z]$' })
            if ($names.Count -gt 1) { $names = @($names[0..($names.Count - 2)]) }
            if ($items.Count -gt 0 -and @($rest | Where-Object { $_ -match '^\$(_|PSItem)\b' }).Count -gt 0) { $names = $items }
            foreach ($x in @($names | ForEach-Object { Expand-LineVariables $_ $Vars } | ForEach-Object { Expand-Braces $_ })) {
                foreach ($p in @(Get-CommandPaths (Remove-DevicePrefix $x) $dir)) {
                    $hit = @($Lists.critical | Where-Object { if ($p -match '[*?]') { $_ -like $p -or $_ -like "$p\*" } else { Test-PathInside $_ $p } })
                    if ($hit.Count -gt 0) { Set-Verdict 'ask' 'delete-outside' "Moving away a main folder ($p)" }
                }
            }
            continue
        }
        # overwriting everything a listing found
        if ($name -match '^(Set-Content|Clear-Content|clc|Out-File|Add-Content)$' -and $items.Count -gt 0 -and @($rest | Where-Object { $_ -match '^\$(_|PSItem)\b' }).Count -gt 0) {
            foreach ($x in $items) {
                $p = Resolve-CommandPath (@(Expand-LineVariables $x $Vars)[0]) $dir
                if ($p -and -not ($Cwd -and (Test-PathInside $p $Cwd))) { Test-DeleteTarget $x $dir $Cwd $Lists 'Overwriting the files found' 'some' }
            }
            continue
        }
        if ($name -notmatch '^(rm|del|erase|rd|rmdir|Remove-Item|ri|unlink|shred|truncate|Clear-Content|clc)$') { continue }
        $power = ($Tool -eq 'PowerShell' -or $name -match '^(Remove-Item|ri|Clear-Content|clc)$')
        # cmd commands take /s as a switch; for the others "/c" is a path (drive C in Git Bash)
        $flagPattern = '^-'
        if ($name -match '^(del|erase|rd|rmdir)$') { $flagPattern = '^(-|/[a-zA-Z?](:\S*)?$)' }
        $recursive = $false
        foreach ($f in @($rest | Where-Object { $_ -match $flagPattern })) {
            if ($f -match $script:RecursiveFlag) { $recursive = $true }
            # clustered short options of the Unix rm: -rf, -fr, -Rfv
            if ($name -eq 'rm' -and $f -cmatch '^-[rRfivdI]+$' -and $f -match 'r') { $recursive = $true }
        }
        # without /s they only take empty folders away
        if (-not $recursive -and $name -match '^(rd|rmdir)$') { continue }
        $level = 'files'
        $what = 'Deleting'
        if ($recursive) { $level = 'all'; $what = 'Recursive delete' }
        $targets = @()
        for ($j = 0; $j -lt $rest.Count; $j++) {
            $x = $rest[$j]
            if ($x -match '^-(Path|Pat|Pa|LiteralPath|Literal\w*|Lit\w*|LP|PSPath):(.+)$') { $x = $Matches[2] }
            elseif ($x -match $flagPattern) { continue }
            # lists of PowerShell: a,b
            $parts = @($x)
            if ($power) { $parts = @($x.Split(',') | Where-Object { $_ }) }
            foreach ($part in $parts) { $targets += , @($part, $restRaw[$j]) }
        }
        $fromItems = @($targets | Where-Object { $_[0] -match '^\$(_|PSItem)\b|^\{\}$' }).Count -gt 0
        if (($targets.Count -eq 0 -and $piped -and $listed.Count -gt 0) -or ($fromItems -and $items.Count -gt 0)) {
            # what comes through the pipe goes
            $source = $listed
            if ($fromItems) { $source = $items }
            # Remove-Item without -Recurse takes single files; from find and Get-ChildItem -Recurse that is everything
            Test-ListedTargets $source $dir $Cwd $Lists $Command $Vars 'Deleting the listed content'
            if ($fromItems) { continue }
        }
        foreach ($target in $targets) {
            foreach ($word in @(Expand-LineVariables $target[0] $Vars)) {
                $note = $what
                if ($Depth -eq 0) {
                    $unset = Remove-UnsetVariables $target[1] $word $Command $Vars $Tool
                    if (@($unset.names).Count -gt 0) {
                        if (-not $unset.word) { continue }
                        $word = $unset.word
                        $note = "$what (nothing in this command sets the variable $(@($unset.names) -join ', '), so it is empty)"
                    }
                }
                Test-DeleteTarget $word $dir $Cwd $Lists $note $level
            }
        }
    }
    $pipe.listed = $listed
    $pipe.items = $items
}
