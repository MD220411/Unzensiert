# What a command line is made of, for the rights of a session: which parts it has, whether it
# only reads (config\readonly.json, "readOnlyCommands" and "readOnlyGit" in
# config\unzensiert.json), whether it only changes files inside the project ("fileCommands"), and
# whether a rule such as Bash(python:*) covers it. The principle: nothing is searched for that is
# forbidden. A line counts only when all of it is understood - Bash by a small reader that
# follows the rules of the shell, PowerShell by its own parser - and everything in it is allowed;
# otherwise the user is asked. Used by lib\AgentLoop.ps1. Needs lib\Config.ps1,
# hooks\PathRules.ps1 and hooks\GuardRules.ps1 (secrets). Keep this file ASCII-only.
# Description: docs\security.md.

$script:ReadOnlyTable = $null

function Get-ReadOnlyTable {
    # config\readonly.json with the section "readonly" of machine.json, read once per run.
    if ($null -eq $script:ReadOnlyTable) { $script:ReadOnlyTable = Read-Config 'readonly' }
    return $script:ReadOnlyTable
}

function Get-TableEntry($Table, [string]$Name) {
    # An entry of a parsed JSON object by its exact name (also "?" and "%"), or $null.
    if ($null -eq $Table) { return $null }
    foreach ($p in $Table.PSObject.Properties) { if ($p.Name -ceq $Name) { return $p.Value } }
    return $null
}

# --- Bash -----------------------------------------------------------------------------------------

# a variable this reader follows: a plain name or a special one, no ${x@P}, ${x:=y}, ${!x}
$script:BashVariable = '^\$(?:[A-Za-z_]\w*|\{[A-Za-z_]\w*\}|[0-9?#@*$!-])'

$script:PwdMark = [string][char]0xE020

function Read-BashLine([string]$Command, [bool]$Strict) {
    # The simple commands of a Bash line, in order: @(@{ words; text; writes; vars }) - the words as
    # the shell sees them, the text as written, the files it writes to, whether it uses variables
    # ($PWD is the folder itself and $? a number, they do not count). $null when the line holds
    # something this reader does not follow: command substitution, process substitution, here
    # documents, groups, $'...', ${...} beyond a plain name, characters nobody sees. With $Strict
    # (does it only read?) also output into files and background commands are refused.
    $commands = New-Object System.Collections.ArrayList
    $words = New-Object System.Collections.ArrayList
    $writes = New-Object System.Collections.ArrayList
    $word = New-Object System.Text.StringBuilder
    $inWord = $false
    $vars = $false
    $target = ''                                                  # 'out' or 'in': the next word belongs to a redirection
    $s = $Command.Replace("`r`n", "`n")
    # private characters: some stand for others in file names of Git Bash (U+F02D is a dash)
    if ($s -match '[\uE000-\uF8FF]') { return $null }
    $n = $s.Length
    $i = 0
    $begin = 0

    # ends the current word
    $endWord = {
        if ($inWord) {
            $done = $word.ToString()
            if ($done.IndexOf($script:PwdMark) -ge 0) {
                # $PWD is the folder itself at the start of a path, anywhere else a variable
                if ($done -match ('^' + $script:PwdMark + '(/|$)')) { $done = '.' + $done.Substring(1) }
                if ($done.IndexOf($script:PwdMark) -ge 0) { $done = $done.Replace($script:PwdMark, '$PWD'); $vars = $true }
            }
            if ($target -eq 'out') { $null = $writes.Add($done) }
            elseif ($target -ne 'in') { $null = $words.Add($done) }
            $target = ''
            $null = $word.Clear()
            $inWord = $false
        }
    }
    # ends the current command; $until is the position after its text
    $endCommand = {
        param($until)
        if ($words.Count -gt 0) {
            $null = $commands.Add(@{ words = [string[]]$words.ToArray(); text = $s.Substring($begin, $until - $begin).Trim(); writes = [string[]]$writes.ToArray(); vars = $vars })
        }
        $vars = $false
        $words = New-Object System.Collections.ArrayList
        $writes = New-Object System.Collections.ArrayList
    }

    while ($i -lt $n) {
        $c = [string]$s[$i]
        if ($c -ceq "'") {
            $end = $s.IndexOf("'", $i + 1, [StringComparison]::Ordinal)
            if ($end -lt 0) { return $null }
            $null = $word.Append($s.Substring($i + 1, $end - $i - 1))
            $inWord = $true
            $i = $end + 1
            continue
        }
        if ($c -ceq '"') {
            $i++
            while ($true) {
                if ($i -ge $n) { return $null }
                $d = [string]$s[$i]
                if ($d -ceq '"') { $i++; break }
                if ($d -ceq '`') { return $null }
                if ($d -ceq '$') {
                    # a line that goes on right behind it would join what follows to a variable or command
                    if ($i + 2 -lt $n -and [string]$s[$i + 1] -ceq '\' -and [int]$s[$i + 2] -eq 10) { return $null }
                    # a dollar sign before anything else than a name is only a dollar sign here
                    if ($i + 1 -lt $n -and [string]$s[$i + 1] -notmatch '[A-Za-z0-9_({?#@*$!-]') { $null = $word.Append('$'); $i++; continue }
                    $m = [regex]::Match($s.Substring($i), $script:BashVariable)
                    if (-not $m.Success) { return $null }
                    if ($m.Value -cmatch '^\$\{?PWD\}?$') { $null = $word.Append($script:PwdMark) } else { $null = $word.Append($m.Value); if ($m.Value -cne '$?') { $vars = $true } }
                    $i += $m.Length
                    continue
                }
                if ($d -ceq '\' -and $i + 1 -lt $n -and [int]$s[$i + 1] -eq 10) { $i += 2; continue }
                if ($d -ceq '\' -and $i + 1 -lt $n -and '$`"\'.IndexOf($s[$i + 1]) -ge 0) { $null = $word.Append($s[$i + 1]); $i += 2; continue }
                $null = $word.Append($d)
                $i++
            }
            $inWord = $true
            continue
        }
        if ($c -ceq '\') {
            if ($i + 1 -ge $n) { return $null }
            if ([int]$s[$i + 1] -eq 10) { $i += 2; continue }
            $null = $word.Append($s[$i + 1])
            $inWord = $true
            $i += 2
            continue
        }
        if ($c -ceq '#' -and -not $inWord) {
            $end = $s.IndexOf([char]10, $i)
            if ($end -lt 0) { $end = $n }
            $i = $end
            continue
        }
        if ($c -ceq ' ' -or $c -ceq "`t") { . $endWord; $i++; continue }
        # redirections
        if ($c -ceq '>' -or ($c -ceq '&' -and $i + 1 -lt $n -and [string]$s[$i + 1] -ceq '>')) {
            $rest = $s.Substring($i)
            $number = ''
            if ($inWord) {
                # 2>file: the number belongs to the redirection; any other word ends here
                if ($word.ToString() -match '^\d$' -and [int]$s[$i - 1] -ne 34 -and [int]$s[$i - 1] -ne 39) { $number = $word.ToString(); $null = $word.Clear(); $inWord = $false }
                elseif ($c -ceq '&') { . $endWord }
                else { . $endWord }
            }
            if ($target) { return $null }
            $m = [regex]::Match($rest, '^>&(?:[0-9]|-)(?=$|[\s;|&)])')
            if ($m.Success) { $i += $m.Length; continue }
            $m = [regex]::Match($rest, '^&?>>?\s*/dev/null(?=$|[\s;|&)])')
            if ($m.Success) { $i += $m.Length; continue }
            if ($Strict) { return $null }
            $m = [regex]::Match($rest, '^(?:&>>|&>|>>|>\||>&|>)')
            if ($rest.Length -gt $m.Length -and $rest[$m.Length] -eq [char]'(') { return $null }
            $i += $m.Length
            $target = 'out'
            continue
        }
        if ($c -ceq '<') {
            if ($Strict) { return $null }
            if ($i + 1 -lt $n -and '<(>&'.IndexOf($s[$i + 1]) -ge 0) { return $null }
            if ($inWord -and $word.ToString() -match '^\d$') { $null = $word.Clear(); $inWord = $false }
            . $endWord
            if ($target) { return $null }
            $target = 'in'
            $i++
            continue
        }
        # separators
        $sep = 0
        if ([int]$s[$i] -eq 10 -or $c -ceq ';') { $sep = 1 }
        elseif ($c -ceq '|') { $sep = 1; if ($i + 1 -lt $n -and ([string]$s[$i + 1] -ceq '|' -or [string]$s[$i + 1] -ceq '&')) { $sep = 2 } }
        elseif ($c -ceq '&') {
            $sep = 1
            if ($i + 1 -lt $n -and [string]$s[$i + 1] -ceq '&') { $sep = 2 } elseif ($Strict) { return $null }
        }
        if ($sep -gt 0) {
            . $endWord
            if ($target) { return $null }
            . $endCommand $i
            $i += $sep
            $begin = $i
            continue
        }
        if ($c -ceq '$') {
            $m = [regex]::Match($s.Substring($i), $script:BashVariable)
            if (-not $m.Success) { return $null }
            if ($m.Value -cmatch '^\$\{?PWD\}?$') { $null = $word.Append($script:PwdMark) } else { $null = $word.Append($m.Value); if ($m.Value -cne '$?') { $vars = $true } }
            $inWord = $true
            $i += $m.Length
            continue
        }
        if ($c -ceq '`' -or $c -ceq '(' -or $c -ceq ')') { return $null }
        if (($c -ceq '{' -or $c -ceq '}') -and ($Strict -or -not $inWord)) { return $null }
        if ($c -ceq '!' -and -not $inWord -and $words.Count -eq 0) { return $null }
        # characters that change what a line looks like
        $code = [int]$s[$i]
        if ([char]::IsControl($s[$i]) -or ($code -ge 0x200B -and $code -le 0x200F) -or ($code -ge 0x2028 -and $code -le 0x202E) -or ($code -ge 0x2060 -and $code -le 0x206F) -or $code -eq 0xFEFF -or ($code -ge 0xE000 -and $code -le 0xF8FF) -or ($code -ge 0xDB40 -and $code -le 0xDB43)) { return $null }
        $null = $word.Append($s[$i])
        $inWord = $true
        $i++
    }
    . $endWord
    if ($target) { return $null }
    . $endCommand $n
    return , $commands.ToArray()
}

# --- PowerShell -----------------------------------------------------------------------------------

$script:PsPlainNodes = @('ScriptBlockAst', 'NamedBlockAst', 'PipelineAst', 'CommandAst', 'CommandParameterAst', 'StringConstantExpressionAst', 'ConstantExpressionAst',
    'ArrayLiteralAst', 'CommandExpressionAst', 'MergingRedirectionAst', 'FileRedirectionAst', 'VariableExpressionAst')
$script:PsBlockNodes = @('ScriptBlockExpressionAst', 'ScriptBlockAst', 'NamedBlockAst', 'PipelineAst', 'CommandExpressionAst', 'BinaryExpressionAst', 'UnaryExpressionAst',
    'ParenExpressionAst', 'MemberExpressionAst', 'VariableExpressionAst', 'StringConstantExpressionAst', 'ConstantExpressionAst', 'ArrayLiteralAst')

function Test-PsBlock($Block) {
    # True if a { } only looks at values: properties of $_, comparisons, constants.
    foreach ($node in $Block.FindAll({ $true }, $true)) {
        $kind = $node.GetType().Name
        if ($script:PsBlockNodes -notcontains $kind) { return $false }
        if ($kind -eq 'VariableExpressionAst' -and @('_', 'psitem', 'null', 'true', 'false') -notcontains $node.VariablePath.UserPath.ToLowerInvariant()) { return $false }
        if ($kind -eq 'MemberExpressionAst' -and $node.Static) { return $false }
        # $_.Attributes++ writes
        if ($kind -eq 'UnaryExpressionAst' -and @('Not', 'Exclaim', 'Minus', 'Plus', 'Bnot') -notcontains [string]$node.TokenKind) { return $false }
    }
    return $true
}

function Get-PsText($Node) {
    # The texts a constant argument stands for, with its quotes and backticks taken away as PowerShell
    # does it; for a variable or a number the text as written.
    if ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return @([string]$Node.Value) }
    if ($Node -is [System.Management.Automation.Language.ArrayLiteralAst]) { return @($Node.Elements | ForEach-Object { Get-PsText $_ }) }
    return @($Node.Extent.Text.Trim('"', "'"))
}

function Read-PowerShellLine([string]$Command, [bool]$Strict) {
    # The commands of a PowerShell line as Read-BashLine gives those of Bash, plus params (names
    # of parameters), args (constant arguments) and blocks (the { } among the arguments). $null for
    # everything that is more than commands in pipelines: expressions, assignments, method calls,
    # sub-expressions, keywords. $Strict: no variables except $null, $true, $false, $pwd, no
    # output into files, no call operator.
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { return $null }
    if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $ast.DynamicParamBlock) { return $null }
    # "#requires -modules x" loads a module before anything runs
    if ($ast.ScriptRequirements) { return $null }
    $blocks = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true))
    $commands = New-Object System.Collections.ArrayList
    foreach ($node in $ast.FindAll({ $true }, $true)) {
        # what stands inside a { } is judged by Test-PsBlock
        $inBlock = $false
        foreach ($b in $blocks) { if ($node -ne $b -and $node.Extent.StartOffset -ge $b.Extent.StartOffset -and $node.Extent.EndOffset -le $b.Extent.EndOffset) { $inBlock = $true; break } }
        if ($inBlock) { continue }
        $kind = $node.GetType().Name
        if ($kind -eq 'ScriptBlockExpressionAst') { if (-not (Test-PsBlock $node)) { return $null }; continue }
        if ($kind -eq 'ExpandableStringExpressionAst') { if ($Strict -or @($node.NestedExpressions | Where-Object { $_ -isnot [System.Management.Automation.Language.VariableExpressionAst] }).Count -gt 0) { return $null }; continue }
        if ($script:PsPlainNodes -notcontains $kind) { return $null }
        if ($kind -eq 'VariableExpressionAst') {
            $name = $node.VariablePath.UserPath.ToLowerInvariant()
            if ($Strict -and @('null', 'true', 'false', 'pwd') -notcontains $name) { return $null }
            if ($node.Splatted) { return $null }
        }
        if ($kind -eq 'CommandAst') {
            $op = $node.InvocationOperator
            if ($op -eq [System.Management.Automation.Language.TokenKind]::Dot) { return $null }
            if ($Strict -and $op -ne [System.Management.Automation.Language.TokenKind]::Unknown) { return $null }
            $name = $node.GetCommandName()
            if (-not $name) { return $null }
            $words = @($name)
            $params = @()
            $arguments = @()
            $writes = @()
            $own = @()
            foreach ($e in @($node.CommandElements | Select-Object -Skip 1)) {
                if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $params += [string]$e.ParameterName
                    $words += '-' + $e.ParameterName
                    if ($e.Argument) { foreach ($v in @(Get-PsText $e.Argument)) { $arguments += $v; $words += $v } }
                } elseif ($e -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $own += $e; $words += $e.Extent.Text }
                else { foreach ($v in @(Get-PsText $e)) { $arguments += $v; $words += $v } }
            }
            foreach ($r in $node.Redirections) {
                if ($r -is [System.Management.Automation.Language.FileRedirectionAst]) {
                    if ($r.Location.Extent.Text -ieq '$null') { continue }
                    if ($Strict) { return $null }
                    $writes += @(Get-PsText $r.Location)
                }
            }
            # what comes in through a pipe: the names of the commands before, "?" for anything else
            $before = @()
            if ($node.Parent -is [System.Management.Automation.Language.PipelineAst]) {
                foreach ($p in $node.Parent.PipelineElements) {
                    if ($p -eq $node) { break }
                    if ($p -is [System.Management.Automation.Language.CommandAst] -and $p.GetCommandName()) { $before += , @($p.GetCommandName(), @($p.CommandElements | Select-Object -Skip 1)) } else { $before += , @('?', @()) }
                }
            }
            $null = $commands.Add(@{ words = [string[]]$words; text = $node.Extent.Text; writes = [string[]]$writes; params = [string[]]$params; args = [string[]]$arguments; blocks = $own; before = $before })
        }
        if ($kind -eq 'CommandExpressionAst') {
            # 'text' > file writes without any command
            foreach ($r in $node.Redirections) {
                if ($r -is [System.Management.Automation.Language.FileRedirectionAst] -and $r.Location.Extent.Text -ine '$null') { return $null }
            }
            # a lone constant ("text" or 1) is harmless, a lone variable is not read here
            if ($Strict -and $node.Expression -isnot [System.Management.Automation.Language.ConstantExpressionAst]) { return $null }
        }
    }
    return , $commands.ToArray()
}

function Read-CommandLine([string]$Tool, [string]$Command, [bool]$Strict) {
    # The commands of a line for the tool Bash or PowerShell; $null when it is not understood.
    try {
        if ($Tool -eq 'PowerShell') { $list = Read-PowerShellLine $Command $Strict } else { $list = Read-BashLine $Command $Strict }
    } catch { return $null }
    if ($null -eq $list) { return $null }
    return , @($list)
}

# --- does it only read? ------------------------------------------------------------------------------

function Test-PlainArgument([string]$Word) {
    # False for network and device paths, web addresses and the places of the shell that hold more
    # than files (/proc, /dev): they are questions of their own.
    if ($Word -match '^[\\/]{2}' -or $Word -match '^\\?\\\?\?\\' -or $Word -match '[=,:;][\\/]{2}') { return $false }
    if ($Word -match '^[a-zA-Z][a-zA-Z0-9+.-]+://') { return $false }
    if ($Word -match '^/(proc|sys)(/|$)' -or $Word -match '^/dev/(?!null$)') { return $false }
    return $true
}

function Test-NativeWords($Command) {
    # False if Windows PowerShell 5.1 would hand other arguments to a real program than it reads: it
    # does not escape quotes (git log 'a" --output=x "b'), a backslash before the closing quote opens
    # it again, empty arguments vanish, a { } becomes -encodedCommand.
    if (@($Command.blocks).Count -gt 0) { return $false }
    foreach ($w in @($Command.words)) {
        if (-not $w -or $w.IndexOf('"') -ge 0 -or ($w -match '\s' -and $w.EndsWith('\'))) { return $false }
    }
    return $true
}

function Test-PipeInput($Command, [string]$Name, $Aliases, $State) {
    # False if a command of PowerShell that opens paths would get them through a pipe from anywhere
    # else than a listing (gc list.txt | gi | gc opens what stands in the list).
    $before = @($Command.before)
    if ($before.Count -eq 0) { return $true }
    $opens = @('get-content', 'get-item', 'get-childitem', 'test-path', 'resolve-path', 'get-filehash', 'split-path', 'join-path', 'set-location')
    if ($opens -notcontains $Name -and $Name -ne 'select-string') { return $true }
    $listed = $false
    $recurse = $false
    $folders = @()
    for ($i = 0; $i -lt $before.Count; $i++) {
        $n = ([string]$before[$i][0]).ToLowerInvariant()
        $alias = Get-TableEntry $Aliases $n
        if ($alias) { $n = [string]$alias }
        $elements = @($before[$i][1])
        if ($i -eq 0 -and ($n -eq 'get-childitem' -or $n -eq 'get-item')) {
            $listed = $true
            foreach ($e in $elements) {
                if ($e -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if ($e.ParameterName -match '^(r|re|rec\w*|dep\w*)$') { $recurse = $true }
                    if ($e.Argument) { $folders += @(Get-PsText $e.Argument) }
                } else { $folders += @(Get-PsText $e) }
            }
            continue
        }
        if ($n -eq 'get-item' -or $n -eq 'get-childitem' -or $n -eq 'where-object' -or $n -eq 'sort-object') { continue }
        # Select-Object hands on the files themselves only with -First, -Last, -Skip, -Unique
        if ($n -eq 'select-object') {
            $plain = $true
            foreach ($e in $elements) {
                if ($e -is [System.Management.Automation.Language.CommandParameterAst]) { if ($e.ParameterName -notmatch '^(f\w*|l\w*|sk\w*|u\w*|index|wait)$') { $plain = $false } }
                elseif ($e -isnot [System.Management.Automation.Language.ConstantExpressionAst] -or $e.StaticType -ne [int]) { $plain = $false }
            }
            if ($plain) { continue }
        }
        # Select-String takes strings as text, not as paths
        if ($Name -eq 'select-string' -and -not $listed) { continue }
        return $false
    }
    if (-not $listed) { return ($Name -eq 'select-string') }
    # a link among the listed files leads elsewhere
    if ($folders.Count -eq 0) { $folders = @('.') }
    foreach ($f in $folders) {
        $facts = Get-PathFacts ($f -replace '[\\/]*[^\\/]*[*?\[][^\\/]*$', '.') $State.folder
        if (-not $facts.ok) { if ($f -match '[\\/]') { return $false } else { continue } }
        if ([System.IO.Directory]::Exists($facts.full) -and (Test-TreeLinks $facts.full $recurse)) { return $false }
    }
    return $true
}

function Test-AllowedOptions([string[]]$Words, [int]$From, $Entry) {
    # True if every option among the words is listed in the entry of config\readonly.json and the
    # number of other words is allowed. Words after "--" are looked at as well: an option before it
    # may take the "--" as its value (git log -L -- --output=x).
    $short = [string]$Entry.short
    $long = @(([string]$Entry.long).Split(',') | Where-Object { $_ })
    $any = ([string]$Entry.long -eq '*')
    $operands = 0
    for ($i = $From; $i -lt $Words.Count; $i++) {
        $w = $Words[$i]
        if (-not (Test-PlainArgument $w)) { return $false }
        if ($Entry.plus -and $w.StartsWith('+')) { continue }
        if ($w -ceq '-' -or -not $w.StartsWith('-')) { $operands++; continue }
        if ($w -ceq '--') { continue }
        if ($w.StartsWith('--')) {
            if ($any) { $operands++; continue }
            if ($long -cnotcontains $w.Substring(2).Split('=')[0]) { return $false }
            continue
        }
        foreach ($ch in $w.Substring(1).ToCharArray()) {
            if ($short.IndexOf($ch) -ge 0) { continue }
            # echo prints what it does not know; a value glued to an option (-d, or -k2) ends the letters
            if ($any) { break }
            if ([char]::IsLetter($ch)) { return $false }
            break
        }
    }
    if ($null -ne $Entry.operands -and $operands -gt [int]$Entry.operands) { return $false }
    return $true
}

function Test-GlobOption([string[]]$Words, [string]$Folder) {
    # True if a wildcard at the start of a word could become an option: the folder holds a file whose
    # name starts with a dash (sort *.txt with a file -oX.txt, git grep x * with -O./x.sh).
    $open = $false
    for ($i = 1; $i -lt $Words.Count; $i++) { if ($Words[$i] -match '^[*?\[]') { $open = $true; break } }
    if (-not $open) { return $false }
    try {
        foreach ($e in [System.IO.Directory]::EnumerateFileSystemEntries($Folder)) {
            $first = $e[$e.LastIndexOf('\') + 1]
            if ($first -eq [char]'-' -or ([int]$first -band 0xFF00) -eq 0xF000) { return $true }
        }
    } catch { return $true }
    return $false
}

function Test-ReadsProtected([string[]]$Words, [string]$Folder, [bool]$Recursive, $Guard, [string]$Tool) {
    # True if one of the words names something under the protection of "secretPaths" or
    # "secretFileNames" (config\guard.json), also with wildcards, or - for a command that walks
    # through folders - a folder that holds such a place.
    if (-not $Guard -or -not $Guard.enabled) { return $false }
    $secrets = @(Get-SecretPaths $Guard)
    $named = $false
    for ($i = 1; $i -lt $Words.Count; $i++) {
        $w = $Words[$i]
        if ($w.StartsWith('-') -and $w.IndexOf('=') -lt 0) { continue }
        if ($w.StartsWith('-')) { $w = $w.Substring($w.IndexOf('=') + 1) }
        if (-not $w) { continue }
        if (Test-SecretSpelling $w $Folder $secrets $Guard $Recursive $Tool) { return $true }
        $named = $true
    }
    if ($Recursive -and -not $named -and (Test-SecretSpelling '.' $Folder $secrets $Guard $true $Tool)) { return $true }
    return $false
}

function New-ReadState([string]$Cwd) {
    # Where the shell stands while the commands of a line are looked at one after the other. folders:
    # everywhere it may stand, because a "cd" that fails leaves it where it was; changed: something
    # before may have taken a folder away.
    return @{ folder = $Cwd; folders = @($Cwd); moved = $false; changed = $false }
}

function Test-ReadOnlyPart($Command, [string]$Tool, $State, [string]$Cwd, $Guard) {
    # True if one command of a line only reads, in every folder the line may stand in by then.
    $folders = @($State.folders)
    if ($folders.Count -le 1) { return (Test-ReadOnlyOne $Command $Tool $State $Cwd $Guard) }
    $after = @()
    foreach ($f in $folders) {
        $one = @{ folder = $f; folders = @($f); moved = $State.moved; changed = $State.changed }
        if (-not (Test-ReadOnlyOne $Command $Tool $one $Cwd $Guard)) { return $false }
        $after += @($one.folders)
    }
    $State.folders = @($after | Select-Object -Unique)
    $State.folder = $State.folders[0]
    $State.moved = (@($State.folders | Where-Object { $_ -ine $Cwd.TrimEnd([char]92) }).Count -gt 0)
    return $true
}

function Test-ReadOnlyOne($Command, [string]$Tool, $State, [string]$Cwd, $Guard) {
    # True if one command of a line only reads. "cd" is followed ($State); it may not leave the
    # project folder, and git asks after a "cd" into another folder (git runs what the folder it
    # stands in configures).
    $cfg = Get-AgentSettings
    $table = Get-ReadOnlyTable
    $names = @($cfg.readOnlyCommands | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $recursive = @($table.recursive)
    $w = [string[]]$Command.words
    $first = $w[0]
    if (-not $State.folder -or @($Command.writes).Count -gt 0) { return $false }
    # a variable may hold anything (an option, a path); only echo may print one, and the
    # environment of the commands holds no keys (Remove-SecretVariables)
    if ($Command.vars -and -not ($Tool -eq 'Bash' -and $first -ceq 'echo')) { return $false }
    if ($first -ceq 'git') {
        if ($State.moved -or ($Tool -eq 'PowerShell' -and -not (Test-NativeWords $Command))) { return $false }
        # %G? in a format lets git start the program that checks signatures
        if (@($w | Where-Object { $_ -cmatch '%G' }).Count -gt 0) { return $false }
        $at = 1
        while ($at -lt $w.Count -and $w[$at] -ceq '--no-pager') { $at++ }
        if ($at -ge $w.Count -or @($cfg.readOnlyGit | ForEach-Object { [string]$_ }) -cnotcontains $w[$at]) { return $false }
        $longs = Get-TableEntry $table.git $w[$at]
        if ($null -eq $longs) { return $false }
        $shorts = Get-TableEntry $table.gitShort $w[$at]
        if ($null -eq $shorts) { $shorts = Get-TableEntry $table.gitShort 'default' }
        if (-not (Test-AllowedOptions $w ($at + 1) @{ short = $shorts; long = $longs })) { return $false }
        if ($Tool -eq 'Bash' -and (Test-GlobOption $w $State.folder)) { return $false }
        if (Test-ReadsProtected $w $State.folder $false $Guard $Tool) { return $false }
        return (Test-GitTrusted $Cwd)
    }
    if ($Tool -eq 'PowerShell') {
        $name = $first.ToLowerInvariant()
        if ($names -notcontains $name) { return $false }
        $alias = Get-TableEntry $table.aliases $name
        if ($alias) { $name = [string]$alias }
        $allowed = Get-TableEntry $table.powershell $name
        if ($null -eq $allowed) { return $false }
        $list = @(([string]$allowed).Split(',') | Where-Object { $_ })
        foreach ($p in @($Command.params)) {
            $given = $p.ToLowerInvariant()
            if (@($list | Where-Object { $_.StartsWith($given, [StringComparison]::Ordinal) }).Count -eq 0) { return $false }
        }
        if (@($Command.blocks).Count -gt 0 -and @($table.blocks) -notcontains $name) { return $false }
        # ForEach-Object Delete calls the method of that name
        if ($name -eq 'foreach-object' -and @($Command.args).Count -gt 0) { return $false }
        if ($name -eq 'whoami' -and -not (Test-NativeWords $Command)) { return $false }
        if (-not (Test-PipeInput $Command $name $table.aliases $State)) { return $false }
        foreach ($a in @($Command.args)) {
            if (-not (Test-PlainArgument $a)) { return $false }
            # other drives of PowerShell (env:, HKCU:, function: ...) and providers are no files
            if ($a -match '^[a-zA-Z]{2,}:' -or $a.Contains('::')) { return $false }
        }
        if ($name -eq 'set-location') {
            if (@($Command.args).Count -ne 1) { return $false }
            return (Move-ReadState $State ([string]$Command.args[0]) $Cwd $Tool)
        }
        $walks = ($recursive -contains $name -and @($Command.params | Where-Object { $_ -match '^(r|re|rec\w*|dep\w*)$' }).Count -gt 0)
        return (-not (Test-ReadsProtected (@($name) + @($Command.args)) $State.folder $walks $Guard $Tool))
    }
    if ($first -cne $first.ToLowerInvariant() -or $names -notcontains $first) { return $false }
    if ($first -cne 'echo' -and (Test-GlobOption $w $State.folder)) { return $false }
    if ($first -ceq 'find') {
        $tests = @(([string]$table.find).Split(','))
        $places = @('find')
        $inPlaces = $true
        foreach ($x in @($w | Select-Object -Skip 1)) {
            if (-not (Test-PlainArgument $x)) { return $false }
            if ($x.StartsWith('-') -and $x.Length -gt 1 -and $x -notmatch '^-\d') {
                $inPlaces = $false
                if ($tests -cnotcontains $x.Substring(1)) { return $false }
            } elseif ($x -ceq '(' -or $x -ceq '!') { $inPlaces = $false }
            elseif ($inPlaces) { $places += $x }
        }
        return (-not (Test-ReadsProtected $places $State.folder $true $Guard $Tool))
    }
    $entry = Get-TableEntry $table.bash $first
    if ($null -eq $entry) { return $false }
    if (-not (Test-AllowedOptions $w 1 $entry)) { return $false }
    if ($first -ceq 'cd') {
        if ($w.Count -ne 2) { return $false }
        return (Move-ReadState $State $w[1] $Cwd $Tool)
    }
    if ($first -ceq 'echo' -or $first -ceq 'true') { return $true }
    $walks = ($recursive -contains $first)
    if (@('ls', 'dir') -contains $first) { $walks = (@($w | Where-Object { $_ -cmatch '^-[a-zA-Z0-9]*R|^--recursive$' }).Count -gt 0) }
    elseif ($first -ceq 'grep' -or $first -ceq 'diff') { $walks = (@($w | Where-Object { $_ -cmatch '^-[a-zA-Z0-9]*[rR]|^--recursive$' }).Count -gt 0) }
    $check = $w
    if ($first -ceq 'grep' -or $first -ceq 'rg') {
        # their first word is the pattern, not a file
        $check = @($first)
        $seen = (@($w | Where-Object { $_ -cmatch '^-[a-zA-Z]*e$|^--regexp' }).Count -gt 0)
        for ($i = 1; $i -lt $w.Count; $i++) {
            if (-not $seen -and -not $w[$i].StartsWith('-')) { $seen = $true; continue }
            $check += $w[$i]
        }
    }
    return (-not (Test-ReadsProtected $check $State.folder $walks $Guard $Tool))
}

function Move-ReadState($State, [string]$Word, [string]$Cwd, [string]$Tool) {
    # Follows a "cd"; $false when it leaves the project folder or cannot be followed.
    $to = Resolve-StepFolder $Word $State.folder $Cwd $Tool
    if (-not $to) { return $false }
    # the folder is there and nothing in the line can have taken it away: the "cd" works
    if ([System.IO.Directory]::Exists($to) -and -not $State.changed) { $State.folders = @($to) }
    else { $State.folders = @((@($to) + @($State.folders)) | Select-Object -Unique) }
    $State.folder = $to
    $State.moved = (@($State.folders | Where-Object { $_ -ine $Cwd.TrimEnd([char]92) }).Count -gt 0)
    return $true
}

function Test-ReadOnlyList($Commands, [string]$Tool, [string]$Cwd, $Guard) {
    # True if every command of the list only reads.
    $state = New-ReadState $Cwd
    foreach ($command in @($Commands)) { if (-not (Test-ReadOnlyPart $command $Tool $state $Cwd $Guard)) { return $false } }
    return $true
}

function Resolve-StepFolder([string]$Word, [string]$From, [string]$Cwd, [string]$Tool) {
    # Where a "cd" leads: a folder inside the project, or '' (then the line is no reading one).
    if (-not $Cwd -or $Word -match '[*?\[\]]' -or $Word -eq '-') { return '' }
    $f = Get-ShellPath $Tool $Word $From
    if (-not $f.ok -or $f.kind -ne 'file') { return '' }
    $home0 = Get-PathFacts $Cwd $Cwd
    if (-not (Test-PathInside $f.real $home0.real)) { return '' }
    return $f.full
}

function Test-ReadOnlyCommand([string]$Command, [string]$Tool = 'Bash', [string]$Cwd = '', $Guard = $null) {
    # True if the line only reads: it runs in every mode without a question.
    $list = Read-CommandLine $Tool $Command $true
    if ($null -eq $list -or @($list).Count -eq 0) { return $false }
    if (-not $Cwd) { $Cwd = (Get-Location -PSProvider FileSystem).ProviderPath }
    return [bool](Test-ReadOnlyList $list $Tool $Cwd $Guard)
}

# --- file changes inside the project (mode edits) --------------------------------------------------------

$script:FileCommandOptions = '^-(r|R|f|i|v|p|n|a|u|rf|fr|Rf|rfv|pv|vp|ra|ar|rv|vr|m\d*)$|^--(recursive|force|verbose|parents|no-clobber|interactive|update|archive)$'
$script:FileCommandParams = 'path,literalpath,destination,itemtype,name,newname,force,recurse,verbose,erroraction,confirm'

function Test-ProjectFileCommand($Part, [string]$Tool, [string]$Cwd, [string]$Base, $Guard) {
    # True if the command, run in the folder $Base, only creates, copies, moves or deletes files
    # strictly inside the project folder ("fileCommands" in config\unzensiert.json) and none of them is protected
    # ("protectedFiles" in config\guard.json): in mode edits that is a file change like Edit.
    $w = [string[]]$Part.words
    if ($w.Count -lt 2 -or @($Part.writes).Count -gt 0) { return $false }
    if (@((Get-AgentSettings).fileCommands) -notcontains $w[0].ToLowerInvariant()) { return $false }
    $targets = @()
    if ($Tool -eq 'PowerShell') {
        $list = @($script:FileCommandParams.Split(','))
        foreach ($p in @($Part.params)) { if (@($list | Where-Object { $_.StartsWith($p.ToLowerInvariant(), [StringComparison]::Ordinal) }).Count -eq 0) { return $false } }
        if (@($Part.blocks).Count -gt 0) { return $false }
        $values = @('file', 'directory', 'silentlycontinue', 'stop', 'continue', 'ignore')
        $targets = @(@($Part.args) | Where-Object { $values -notcontains $_.ToLowerInvariant() })
    } else {
        foreach ($x in @($w | Select-Object -Skip 1)) {
            if ($x.StartsWith('-')) { if ($x -cnotmatch $script:FileCommandOptions) { return $false }; continue }
            # switches of the commands of cmd (/s, /q)
            if ($x -match '^/[a-zA-Z?]$' -and @('del', 'erase', 'rd', 'rmdir', 'md', 'copy', 'move', 'ren') -contains $w[0]) { continue }
            $targets += $x
        }
    }
    if ($targets.Count -eq 0) { return $false }
    if ($Tool -eq 'Bash' -and (Test-GlobOption $w $Base)) { return $false }
    if (@('cp', 'copy', 'mv', 'move', 'copy-item', 'cpi', 'move-item', 'mi') -contains $w[0].ToLowerInvariant()) {
        # what arrives in a folder keeps its name: it must not become a protected file there
        if ($targets.Count -lt 2) { return $false }
        $to = Get-ShellPath $Tool $targets[$targets.Count - 1] $Base
        if (-not $to.ok) { return $false }
        foreach ($t in $targets[0..($targets.Count - 2)]) {
            if ($t -match '[*?\[]') { return $false }
            $leaf = $t.TrimEnd('/', '\').Replace('/', '\')
            $leaf = $leaf.Substring($leaf.LastIndexOf('\') + 1)
            if (-not $leaf -or (Test-ProtectedFile ([System.IO.Path]::Combine($to.full, $leaf)) $Cwd $Guard)) { return $false }
            # a folder arrives with everything in it, under its own name or the new one
            $from = Get-ShellPath $Tool $t $Base
            if (-not $from.ok) { return $false }
            if (-not [System.IO.File]::Exists($from.full)) {
                if ((Test-ProtectedFolder $to.full $Cwd $Guard) -or (Test-ProtectedFolder ([System.IO.Path]::Combine($to.full, $leaf)) $Cwd $Guard)) { return $false }
                # PowerShell copies what a link in it leads to
                if ($Tool -eq 'PowerShell' -and [System.IO.Directory]::Exists($from.full) -and (Test-TreeLinks $from.full $true)) { return $false }
            }
        }
    }
    # renaming a folder
    if (@('ren', 'rename', 'rename-item', 'rni') -contains $w[0].ToLowerInvariant()) {
        foreach ($t in @($targets | Select-Object -Skip 1)) { if (Test-ProtectedFolder $t $Cwd $Guard) { return $false } }
    }
    foreach ($t in $targets) {
        if ($t -match '[$%`<>|;&]' -or $t.StartsWith('~') -or -not (Test-PlainArgument $t)) { return $false }
        $plain = $t
        if ($t -match '[*?\[]') {
            # a wildcard: the folder before it has to lie in the project, and nothing may lead out
            if ($t -match '\.\.') { return $false }
            $cut = $t.IndexOfAny([char[]]'*?[')
            $slash = [Math]::Max($t.LastIndexOf('/', $cut), $t.LastIndexOf('\', $cut))
            $plain = '.'
            if ($slash -gt 0) { $plain = $t.Substring(0, $slash) } elseif ($slash -eq 0) { return $false }
            if (-not (Test-InProject $plain $Cwd $true $Base $Tool)) { return $false }
            if (Test-ProtectedFile ((Get-ShellPath $Tool $plain $Base).full.TrimEnd('\') + '\x') $Cwd $Guard) { return $false }
            # what it meets: no link that leads elsewhere, no protected file
            $met = Expand-WildPath ((Get-ShellPath $Tool $plain $Base).full.TrimEnd('\') + '\' + ($t.Substring($slash + 1).Replace('/', '\') -replace '\[[!^]?\]?[^\]]*\]?', '?'))
            if (-not $met.ok -or $met.links) { return $false }
            foreach ($m in $met.paths) { if (Test-ProtectedFile $m $Cwd $Guard) { return $false } }
            continue
        }
        if (-not (Test-InProject $plain $Cwd $false $Base $Tool)) { return $false }
        if (Test-ProtectedFile ((Get-ShellPath $Tool $plain $Base).full) $Cwd $Guard) { return $false }
    }
    return $true
}

function Test-InProject([string]$Path, [string]$Cwd, [bool]$OrItself, [string]$Base = '', [string]$Tool = '') {
    # True if $Path (relative to $Base, normally the project folder) lies below the project folder,
    # as written and with links followed; $Tool: the shell that reads the path.
    if (-not $Base) { $Base = $Cwd }
    $f = Get-ShellPath $Tool $Path $Base
    if (-not $f.ok -or $f.kind -ne 'file') { return $false }
    $top = Get-PathFacts $Cwd $Cwd
    foreach ($pair in @(@($f.full, $top.full), @($f.real, $top.real))) {
        if (-not (Test-PathInside $pair[0] $pair[1])) { return $false }
        if (-not $OrItself -and $pair[0] -ieq $pair[1]) { return $false }
    }
    return $true
}

# --- rules such as Bash(python:*) ------------------------------------------------------------------------

function Test-CommandPattern($Part, [string]$Spec) {
    # A rule like "python:*" or "git log:*" (these words and anything after them) or an exact
    # command. $Part is a command of Read-CommandLine.
    if ($Spec.EndsWith(':*')) { $prefix = $Spec.Substring(0, $Spec.Length - 2) }
    elseif ($Spec.EndsWith('*')) { $prefix = $Spec.Substring(0, $Spec.Length - 1) }
    else { return ([string]$Part.text -ceq $Spec) }
    $want = @($prefix.Trim() -split '\s+' | Where-Object { $_ })
    $words = [string[]]$Part.words
    if ($want.Count -eq 0 -or $words.Count -lt $want.Count) { return $false }
    for ($i = 0; $i -lt $want.Count; $i++) { if ($words[$i] -ine $want[$i]) { return $false } }
    return $true
}

function Get-CommandRule($Part, [string]$Tool) {
    # The rule an "always" answer makes of one command: its program, with the subcommand for git,
    # npm and the like ("twoWordPrograms"); an interpreter ("interpreters") only with the script
    # or module it runs, and for code on the command line only exactly this line.
    $cfg = Get-AgentSettings
    $w = [string[]]$Part.words
    $name = ($w[0] -replace '^.*[\\/]', '' -replace '(?i)\.exe$', '').ToLowerInvariant()
    if ($w[0] -match '\s') { return "$Tool($($Part.text))" }
    if (@($cfg.interpreters) -contains $name) {
        if ($w.Count -ge 3 -and $w[1] -ceq '-m' -and $w[2] -match '^[\w.-]+$') { return "$Tool($($w[0]) -m $($w[2]):*)" }
        if ($w.Count -ge 2 -and $w[1] -notmatch '^[-/]' -and $w[1] -match '^[\w./\\-]+\.\w+$') { return "$Tool($($w[0]) $($w[1]):*)" }
        return "$Tool($($Part.text))"
    }
    if (@($cfg.twoWordPrograms) -contains $name) {
        if ($w.Count -gt 1 -and $w[1] -match '^[\w:.-]+$' -and -not $w[1].StartsWith('-')) { return "$Tool($($w[0]) $($w[1]):*)" }
        # an option before the subcommand (git -c ...): not all of git, only this line
        return "$Tool($($Part.text))"
    }
    return "$Tool($($w[0]):*)"
}
