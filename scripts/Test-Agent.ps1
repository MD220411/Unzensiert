# Checks the agent Unzensiert without a model: JSON, reading the answer stream, the tools in a
# folder of their own, permissions and guard, the detection of repeated calls, saved
# conversations, commands with a slash, the closing check, version numbers of the updates,
# and the terminal output. Takes about 20 seconds; run it after changes to
# scripts\lib\Agent*.ps1, scripts\lib\Update.ps1, scripts\unzensiert.ps1 or
# config\unzensiert.json. With -WithModel it also solves a small task with the model of
# config\agent.json (llama-server must be able to load it, about a minute).
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Agent.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Agent.ps1 -WithModel
#
# Exit code 0 = everything in order, 1 = at least one check failed.

param([switch]$WithModel)

. "$PSScriptRoot\_common.ps1"

$script:Failures = 0
function Assert-That([bool]$Condition, [string]$What) {
    # Prints one result line; only failures are counted.
    if ($Condition) { "ok    $What" } else { $script:Failures++; "FAIL  $What" }
}

$root = Join-Path $env:TEMP "unzensiert-test-$PID"
New-Item -ItemType Directory -Force -Path $root | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$umlauts = "$([char]0xE4)$([char]0xF6)$([char]0xFC)$([char]0xDF)"

function New-TestSession([string]$Folder, [string]$Mode = 'ask') {
    $s = New-AgentSession $Folder 'test-model'
    $s.mode = $Mode
    $s.file = Join-Path $root ("session-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.jsonl')
    $s.hookTranscript = $s.file -replace '\.jsonl$', '.hook.jsonl'
    return $s
}

try {
    Initialize-AgentUi $false $false

    # --- 1. JSON ------------------------------------------------------------------------------
    $d = ConvertFrom-AgentJson '{"a":[{"b":1}],"s":"x"}'
    $list = Get-DictValue $d 'a'
    Assert-That ($list -is [System.Array] -and $list.Count -eq 1) 'json: a list with one element stays a list'
    Assert-That ($null -eq (Get-DictValue $d 'missing')) 'json: a missing key is $null'
    $wrapped = @{ list = (New-Object System.Collections.ArrayList); when = (Get-Date); path = (Join-Path 'a' 'b') }
    $null = $wrapped.list.Add('x')
    $text = ConvertTo-AgentJson $wrapped
    Assert-That ($text -match '"list":\["x"\]' -and $text -match '"path":"a\\\\b"') 'json: values of cmdlets (PSObject) are unwrapped'

    # --- 2. the answer stream -------------------------------------------------------------------
    $lines = @(
        ': comment line of the server',
        'data: {"choices":[{"index":0,"delta":{"role":"assistant","content":null}}]}',
        'data: {"choices":[{"index":0,"delta":{"reasoning_content":"Let me "}}]}',
        'data: {"choices":[{"index":0,"delta":{"reasoning_content":"think."}}]}',
        'data: {"choices":[{"index":0,"delta":{"content":"Hello"}}]}',
        'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"Read","arguments":""}}]}}]}',
        'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"file_path\":"}}]}}]}',
        'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a.txt\"}"}}]}}]}',
        'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"id":"call_b","type":"function","function":{"name":"Glob","arguments":"{\"pattern\":\"*.py\"}"}}]}}]}',
        'data: {"choices":[{"finish_reason":"tool_calls","index":0,"delta":{}}]}',
        'data: {"choices":[],"usage":{"completion_tokens":42,"prompt_tokens":1000,"prompt_tokens_details":{"cached_tokens":900}},"timings":{"predicted_per_second":55.5,"prompt_ms":120.0}}',
        'data: [DONE]'
    )
    $events = New-Object System.Collections.ArrayList
    $state = New-ChatStreamState
    foreach ($l in $lines) { Update-ChatStreamState $state $l { param($k, $t) $null = $events.Add("$k=$t") } }
    $r = Complete-ChatStreamState $state
    Assert-That ($r.reasoning -eq 'Let me think.' -and $r.content -eq 'Hello') 'stream: thinking and answer are collected apart'
    Assert-That (@($r.toolCalls).Count -eq 2 -and $r.toolCalls[0].arguments -eq '{"file_path":"a.txt"}' -and $r.toolCalls[1].name -eq 'Glob') 'stream: two tool calls, arguments joined from pieces'
    Assert-That ($r.finish -eq 'tool_calls' -and $r.promptTokens -eq 1000 -and $r.cachedTokens -eq 900 -and $r.completionTokens -eq 42 -and $r.tokensPerSecond -eq 55.5) 'stream: finish reason, token counts and speed'
    Assert-That ($state.done -and $events.Count -eq 5 -and $events[0] -eq 'reasoning=Let me ') 'stream: events in order, [DONE] ends the stream'

    # --- 3. tools -------------------------------------------------------------------------------
    $proj = Join-Path $root 'proj'
    New-Item -ItemType Directory -Force -Path (Join-Path $proj 'src\deep'), (Join-Path $proj '.git'), (Join-Path $proj 'node_modules\x') | Out-Null
    $s = New-TestSession $proj 'all'
    $res = Invoke-AgentTool $s 'Write' @{ file_path = 'src/app.py'; content = "def add(a, b):`n    return a + b`n`nprint(add(2, 3))`n" }
    Assert-That (-not $res.error -and (Test-Path (Join-Path $proj 'src\app.py')) -and $res.changed) 'Write: creates a new file (relative path, / as separator)'
    $s2 = New-TestSession $proj 'all'
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'src\app.py'; old_string = 'a + b'; new_string = 'a - b' }
    Assert-That ($res.error -and $res.text -match 'Read the file first') 'Edit: refused before the file was read in this session'
    $res = Invoke-AgentTool $s2 'Write' @{ file_path = 'src\app.py'; content = 'x' }
    Assert-That ($res.error -and $res.text -match 'Read the file first') 'Write: an existing file is not overwritten unread'
    $res = Invoke-AgentTool $s2 'Read' @{ file_path = 'src\app.py' }
    Assert-That (-not $res.error -and $res.text -match '(?m)^\s+1\tdef add\(a, b\):' -and $res.text -match '(?m)^\s+4\tprint') 'Read: lines with numbers'
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'src\app.py'; old_string = 'a + b'; new_string = 'a - b' }
    Assert-That (-not $res.error -and ([System.IO.File]::ReadAllText((Join-Path $proj 'src\app.py'))).Contains('return a - b') -and $res.diff.line -eq 2) 'Edit: replaces after Read, reports the line'
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'src\app.py'; old_string = 'return  a - b'; new_string = 'x' }
    Assert-That ($res.error -and $res.text -match 'not found') 'Edit: text not in the file is an error'
    [System.IO.File]::WriteAllText((Join-Path $proj 'src\twice.txt'), "x = 1`nx = 1`n", $utf8)
    $null = Invoke-AgentTool $s2 'Read' @{ file_path = 'src\twice.txt' }
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'src\twice.txt'; old_string = 'x = 1'; new_string = 'y = 2' }
    Assert-That ($res.error -and $res.text -match 'occurs 2 times') 'Edit: an ambiguous text is refused'
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'src\twice.txt'; old_string = 'x = 1'; new_string = 'y = 2'; replace_all = $true }
    Assert-That (-not $res.error -and ([System.IO.File]::ReadAllText((Join-Path $proj 'src\twice.txt'))) -eq "y = 2`ny = 2`n") 'Edit: replace_all changes every place'
    Start-Sleep -Milliseconds 20
    [System.IO.File]::WriteAllText((Join-Path $proj 'src\twice.txt'), "changed outside`n", $utf8)
    (Get-Item (Join-Path $proj 'src\twice.txt')).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddSeconds(5)
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'src\twice.txt'; old_string = 'changed'; new_string = 'x' }
    Assert-That ($res.error -and $res.text -match 'changed since you read it') 'Edit: a file changed since Read must be read again'

    # line endings and byte order mark of a file stay as they were
    $crlf = Join-Path $proj 'win.txt'
    [System.IO.File]::WriteAllText($crlf, "first`r`nsecond $umlauts`r`nthird`r`n", (New-Object System.Text.UTF8Encoding($true)))
    $null = Invoke-AgentTool $s2 'Read' @{ file_path = 'win.txt' }
    $res = Invoke-AgentTool $s2 'Edit' @{ file_path = 'win.txt'; old_string = "first`nsecond $umlauts"; new_string = "first`nmiddle`nsecond $umlauts" }
    $bytes = [System.IO.File]::ReadAllBytes($crlf)
    $back = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    Assert-That (-not $res.error -and $bytes[0] -eq 0xEF -and $back -eq "first`r`nmiddle`r`nsecond $umlauts`r`nthird`r`n") 'Edit: CR LF, byte order mark and umlauts are kept'

    $res = Invoke-AgentTool $s2 'Read' @{ file_path = 'src\app.py'; offset = 2; limit = 2 }
    Assert-That ($res.text -match '(?m)^\s+2\t' -and $res.text -notmatch '(?m)^\s+1\t' -and $res.text -match 'lines 2 to 3 of 4') 'Read: offset and limit, with a note on the rest'
    $res = Invoke-AgentTool $s2 'Read' @{ file_path = 'nothing-here.txt' }
    Assert-That ($res.error -and $res.text -match 'not found') 'Read: a missing file is an error'
    $png = Join-Path $proj 'pic.png'
    [System.IO.File]::WriteAllBytes($png, [Convert]::FromBase64String((New-TestImageBase64 'AB')))
    $res = Invoke-AgentTool $s2 'Read' @{ file_path = 'pic.png' }
    Assert-That (-not $res.error -and $res.image -and $res.image.mime -eq 'image/png' -and $res.image.data.Length -gt 100) 'Read: an image comes back as picture'

    [System.IO.File]::WriteAllText((Join-Path $proj 'src\deep\util.py'), "# helper`nVALUE = 42`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $proj 'node_modules\x\skip.py'), "VALUE = 1`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $proj '.git\config.py'), "VALUE = 2`n", $utf8)
    $res = Invoke-AgentTool $s2 'Glob' @{ pattern = '**/*.py' }
    $found = @($res.text -split "`n")
    Assert-That ($found.Count -eq 2 -and ($found -contains 'src\app.py') -and ($found -contains 'src\deep\util.py')) 'Glob: ** finds nested files, skips .git and node_modules'
    $res = Invoke-AgentTool $s2 'Glob' @{ pattern = 'src/*.{py,txt}' }
    Assert-That (@($res.text -split "`n").Count -eq 2) 'Glob: {a,b} and one folder level'
    $res = Invoke-AgentTool $s2 'Grep' @{ pattern = 'VALUE\s*=\s*\d+' }
    Assert-That ($res.text -eq 'src\deep\util.py:2:VALUE = 42') 'Grep: path, line number and line of every match'
    $res = Invoke-AgentTool $s2 'Grep' @{ pattern = 'value'; ignore_case = $true; files_only = $true; glob = '*.py' }
    Assert-That ($res.text -eq 'src\deep\util.py') 'Grep: ignore_case, files_only and glob'
    $res = Invoke-AgentTool $s2 'Grep' @{ pattern = '([' }
    Assert-That ($res.error -and $res.text -match 'Invalid regular expression') 'Grep: a broken pattern is explained'

    $res = Invoke-AgentTool $s2 'PowerShell' @{ command = "Write-Output 'out $umlauts'; [Console]::Error.WriteLine('err'); exit 3" }
    Assert-That ($res.text -match "out $umlauts" -and $res.text -match 'err' -and $res.text -match '\[exit code 3\]') 'PowerShell: output, errors, umlauts and exit code'
    $res = Invoke-AgentTool $s2 'PowerShell' @{ command = '(Get-Location).Path' }
    Assert-That ($res.text.Trim() -eq $proj) 'PowerShell: runs in the project folder'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $res = Invoke-AgentTool $s2 'PowerShell' @{ command = 'Start-Sleep -Seconds 20'; timeout = 1 }
    Assert-That ($res.error -and $res.text -match 'time limit' -and $watch.Elapsed.TotalSeconds -lt 10) 'PowerShell: stopped at its time limit'
    # output that is not UTF-8: each such line is read in the OEM code page
    $oem = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    $uUml = [string][char]0xFC
    $aUml = [string][char]0xE4
    Assert-That ((ConvertFrom-OutputBytes ([System.Text.Encoding]::UTF8.GetBytes("a${aUml}`n"))) -ceq "a${aUml}`n") 'output: UTF-8 stays as it is'
    $oemLine = [byte[]](0x46, 0x81, 0x72, 0x0A)
    Assert-That ((ConvertFrom-OutputBytes $oemLine) -ceq $oem.GetString($oemLine)) 'output: a line in the console code page is read in the OEM code page'
    $mixed = [byte[]](@(0x61, 0xC3, 0xA4, 0x0A) + @(0x46, 0x81, 0x72, 0x0A))
    Assert-That ((ConvertFrom-OutputBytes $mixed) -ceq ("a${aUml}`n" + $oem.GetString($oemLine))) 'output: UTF-8 and code page lines mixed, each read on its own'
    Assert-That ((ConvertFrom-OutputBytes ([byte[]](0xEF, 0xBB, 0xBF, 0x68, 0x69))) -ceq 'hi') 'output: byte order mark of UTF-8 left out'
    Assert-That ((ConvertFrom-OutputBytes ([byte[]](0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00))) -ceq 'hi') 'output: UTF-16 with byte order mark'
    if ($s2.gitBash) {
        $res = Invoke-AgentTool $s2 'Bash' @{ command = "echo hi && pwd && exit 2" }
        Assert-That ($res.text -match 'hi' -and $res.text -match '\[exit code 2\]') 'Bash: output and exit code'
        if ($oem.GetString($oem.GetBytes($uUml)) -ceq $uUml) {
            # the real case: powershell.exe from Git Bash writes in the code page of the console
            $res = Invoke-AgentTool $s2 'Bash' @{ command = "printf 'a\xc3\xa4\n'; powershell -NoProfile -Command `"Write-Output ('F' + [char]0xFC + 'r')`"" }
            Assert-That ($res.text -cmatch "a${aUml}" -and $res.text -cmatch "F${uUml}r") 'Bash: umlauts of UTF-8 and of powershell.exe (console code page) both readable'
        }
    } else {
        'note  Git Bash is not installed, Bash tool not checked'
    }
    $names = @(Get-AgentToolSchemas $s2.gitBash | ForEach-Object { $_.function.name })
    $wanted = @(([string](Get-AgentTools ([string](Get-AgentConfig).tools) $s2.gitBash)) -split ',' | ForEach-Object { $_.Trim() })
    Assert-That ($names.Count -eq $wanted.Count -and @($wanted | Where-Object { $names -notcontains $_ }).Count -eq 0) "tools: the set of 'tools' in config\agent.json ($($names -join ', '))"
    $res = Invoke-AgentTool $s2 'Unknown' @{}
    Assert-That ($res.error -and $res.text -match 'There is no tool') 'an unknown tool is explained'

    # --- 4. permissions and guard ------------------------------------------------------------------
    $cases = @{
        'ls -la' = $true; 'git status' = $true; 'git log --oneline | head -5' = $true; 'ls 2>&1' = $true; 'ls > /dev/null' = $true
        'Get-ChildItem | Select-Object -First 3' = $true; 'git push' = $false; 'cat a > b' = $false; 'find . -delete' = $false
        'echo $(rm x)' = $false; 'rm x' = $false; 'python x.py' = $false; 'git diff --output=x.txt' = $false
    }
    foreach ($c in $cases.Keys) { Assert-That ((Test-ReadOnlyCommand $c) -eq $cases[$c]) "read-only: '$c' -> $($cases[$c])" }
    $p = New-TestSession $proj 'ask'
    $p.allowedTools = @(Split-ToolList 'Bash(python:*) PowerShell(python:*)')
    Assert-That ($p.allowedTools.Count -eq 2) 'allowedTools: split at spaces outside parentheses'
    Assert-That (Test-ToolAllowed $p 'Bash' @{ command = 'python x.py' }) 'allowed: Bash(python:*) covers python x.py'
    Assert-That (Test-ToolAllowed $p 'Bash' @{ command = 'cd src && python x.py' }) 'allowed: cd before it only reads'
    Assert-That (-not (Test-ToolAllowed $p 'Bash' @{ command = 'python x.py && rm -r build' })) 'allowed: a chained rm is not covered'
    Assert-That (-not (Test-ToolAllowed $p 'Bash' @{ command = 'pythonx run' })) 'allowed: the prefix must be a whole word'
    Assert-That (Test-ToolAllowed $p 'Bash' @{ command = 'python -c "import calc; print(calc.mul(6, 7))"' }) 'allowed: a ; inside quotes does not split the command'
    $splitLine = 'a && b || c; d | e' + [char]10 + 'f ''g;h'' x ' + [char]34 + 'i|j' + [char]34
    Assert-That ((@(Split-CommandParts $splitLine) -join ',') -eq ('a,b,c,d,e,f ''g;h'' x ' + [char]34 + 'i|j' + [char]34)) 'split: at && || ; | and line breaks, not inside quotes'
    $p.mode = 'edits'
    Assert-That (Test-ToolAllowed $p 'Bash' @{ command = 'mkdir -p tests && rm old.txt' }) 'mode edits: mkdir and rm inside the project run'
    Assert-That (Test-ToolAllowed $p 'PowerShell' @{ command = 'Remove-Item .\build\out.txt -Force' }) 'mode edits: Remove-Item inside the project runs'
    Assert-That (-not (Test-ToolAllowed $p 'Bash' @{ command = 'mv a.txt ../b.txt' })) 'mode edits: a target outside the project asks'
    Assert-That (-not (Test-ToolAllowed $p 'Bash' @{ command = 'rm $HOME/x' })) 'mode edits: a target in a variable asks'
    Assert-That (-not (Test-ToolAllowed $p 'Bash' @{ command = 'rm -r .' })) 'mode edits: the project folder itself asks'
    $p.mode = 'ask'
    Assert-That (-not (Test-ToolAllowed $p 'Bash' @{ command = 'mkdir tests' })) 'mode ask: mkdir asks'
    $guard = Get-GuardRules
    $dec = Get-CallDecision $p 'Edit' @{ file_path = 'src\app.py'; old_string = 'a'; new_string = 'b' } $guard
    Assert-That ($dec.action -eq 'ask') 'mode ask: a file change asks'
    $dec = Get-CallDecision $p 'Read' @{ file_path = 'src\app.py' } $guard
    Assert-That ($dec.action -eq 'run') 'mode ask: reading runs'
    $dec = Get-CallDecision $p 'Bash' @{ command = 'npm test' } $guard
    Assert-That ($dec.action -eq 'ask') 'mode ask: an unknown command asks'
    $p.mode = 'edits'
    $dec = Get-CallDecision $p 'Write' @{ file_path = 'new.txt'; content = 'x' } $guard
    Assert-That ($dec.action -eq 'run') 'mode edits: a file change runs'
    $dec = Get-CallDecision $p 'Write' @{ file_path = '..\outside.txt'; content = 'x' } $guard
    Assert-That ($dec.action -eq 'ask') 'mode edits: a file change outside the project asks'
    $p.mode = 'all'
    $dec = Get-CallDecision $p 'Bash' @{ command = 'npm test' } $guard
    Assert-That ($dec.action -eq 'run') 'mode all: a command runs'
    if ($guard.enabled) {
        $dec = Get-CallDecision $p 'Bash' @{ command = 'rm -rf /' } $guard
        Assert-That ($dec.action -eq 'deny' -and $dec.guard) 'guard: "rm -rf /" is denied also in mode all'
    }
    Assert-That ((@(Get-AlwaysRules 'Bash' @{ command = 'git commit -m x && ls' }) -join ',') -eq 'Bash(git commit:*)') 'always: a command allows its program and subcommand'
    Assert-That ((ConvertTo-PermissionMode 'acceptEdits') -eq 'edits' -and (ConvertTo-PermissionMode 'bypassPermissions') -eq 'all' -and (ConvertTo-PermissionMode 'x') -eq '') 'modes: names of Claude Code are understood'

    # --- 5. one round of tool calls without a terminal ------------------------------------------------
    $t = New-TestSession $proj 'ask'
    $calls = @(@{ id = 'c1'; name = 'Bash'; arguments = '{"command":"npm test"}' })
    $outcome = Invoke-ToolCalls $t $calls $guard
    $last = $t.messages[$t.messages.Count - 1]
    Assert-That ($outcome -eq 'ok' -and $last['role'] -eq 'tool' -and $last['content'] -match 'no one is at the terminal') 'no terminal: a question becomes a refusal for the model'
    $calls = @(@{ id = 'c2'; name = 'Read'; arguments = '{"file_path": "src/app.py"' })
    $null = Invoke-ToolCalls $t $calls $guard
    Assert-That ($t.messages[$t.messages.Count - 1]['content'] -match 'not valid JSON') 'broken arguments: explained to the model'
    $msg = New-AssistantCallMessage @{ content = ''; reasoning = '' } $calls
    Assert-That ($msg.tool_calls[0].function.arguments -eq '{}') 'broken arguments: stored as {} so the server takes the conversation'
    $t.fingerprints = @{}
    $notes = 0
    $outcome = 'ok'
    for ($i = 1; $i -le 6; $i++) {
        $outcome = Invoke-ToolCalls $t @(@{ id = "r$i"; name = 'Grep'; arguments = '{"pattern":"VALUE"}' }) $guard
        if ($t.messages[$t.messages.Count - 1]['content'] -match 'Note from Unzensiert') { $notes++ }
        if ($outcome -ne 'ok') { break }
    }
    Assert-That ($notes -eq 4 -and $outcome -eq 'loop' -and $i -eq 6) 'repeats: a note from the 3rd same call and result, stop at the 6th'

    # loops the old rule missed (vergleich2, refactor #1): a file written back and forth, run
    # times in a test output, edits and writes that change nothing
    Assert-That ((Get-ResultShape 'Ran 7 tests in 0.507s, <f at 0x1F2A>') -eq (Get-ResultShape 'Ran 7 tests in 0.493s, <f at 0x7FFE>')) 'repeats: run times and addresses in a result do not count'
    Assert-That ((Get-ResultShape 'line 12') -ne (Get-ResultShape 'line 13')) 'repeats: whole numbers in a result still count'
    $t = New-TestSession $proj 'all'
    $flip = Join-Path $proj 'src\flip.txt'
    $seen = @()
    for ($i = 1; $i -le 3; $i++) {
        $null = Invoke-ToolCalls $t @(@{ id = "fa$i"; name = 'Write'; arguments = '{"file_path":"src/flip.txt","content":"A\n"}' }) $guard
        $null = Invoke-ToolCalls $t @(@{ id = "fg$i"; name = 'Grep'; arguments = '{"pattern":"NOT_THERE_4711"}' }) $guard
        $seen += [bool]($t.messages[$t.messages.Count - 1]['content'] -match 'Note from Unzensiert')
        $null = Invoke-ToolCalls $t @(@{ id = "fb$i"; name = 'Write'; arguments = '{"file_path":"src/flip.txt","content":"B\n"}' }) $guard
    }
    Assert-That (-not $seen[0] -and -not $seen[1] -and $seen[2]) 'repeats: a file changed and changed back hides no loop (note at the 3rd same call in the same state)'
    $before = (Get-Item -LiteralPath $flip).LastWriteTimeUtc
    $res = Invoke-AgentTool $t 'Write' @{ file_path = 'src\flip.txt'; content = "B`n" }
    Assert-That ($res.noop -and -not $res.changed -and -not $res.error -and $res.text -match 'already has exactly this content' -and (Get-Item -LiteralPath $flip).LastWriteTimeUtc -eq $before) 'write: the same content again writes nothing and counts as no change'
    $res = Invoke-AgentTool $t 'Write' @{ file_path = 'src\flip.txt'; content = "b`n" }
    Assert-That ([bool]$res.changed -and -not $res.noop -and ([System.IO.File]::ReadAllText($flip)) -ceq "b`n") 'write: a change of upper and lower case is a change'
    $res = Invoke-AgentTool $t 'Edit' @{ file_path = 'src\flip.txt'; old_string = 'b'; new_string = 'B' }
    Assert-That ([bool]$res.changed -and ([System.IO.File]::ReadAllText($flip)) -ceq "B`n") 'edit: a change of upper and lower case is a change (true to True)'
    $t = New-TestSession $proj 'all'
    $null = Invoke-AgentTool $t 'Read' @{ file_path = 'src\flip.txt' }
    $notes = 0
    $outcome = 'ok'
    for ($i = 1; $i -le 6; $i++) {
        $outcome = Invoke-ToolCalls $t @(@{ id = "ne$i"; name = 'Edit'; arguments = ('{"file_path":"src/flip.txt","old_string":"word' + $i + '","new_string":"word' + $i + '"}') }) $guard
        if ($t.messages[$t.messages.Count - 1]['content'] -match 'Note from Unzensiert') { $notes++ }
        if ($outcome -ne 'ok') { break }
    }
    Assert-That ($notes -eq 4 -and $outcome -eq 'loop' -and $i -eq 6) 'no effect: different edits that change nothing, a note from the 3rd, stop at the 6th'
    $outcome = Invoke-ToolCalls $t @(@{ id = 'img'; name = 'Read'; arguments = '{"file_path":"pic.png"}' }) $guard
    $last = $t.messages[$t.messages.Count - 1]
    Assert-That ($last['role'] -eq 'user' -and @($last['content'])[1].type -eq 'image_url') 'images: sent to the model as a user message after the results'

    # --- 6. saved conversations and context -----------------------------------------------------------
    $c = New-TestSession $proj 'ask'
    Set-SessionSystemPrompt $c 'system text'
    Add-SessionMessage $c @{ role = 'user'; content = 'first request' }
    Add-SessionMessage $c @{ role = 'assistant'; content = 'answer'; reasoning_content = 'thinking' }
    Add-SessionMessage $c @{ role = 'user'; content = @(@{ type = 'text'; text = 'look' }, @{ type = 'image_url'; image_url = @{ url = 'data:image/png;base64,AAAA' } }) }
    $stored = Get-Content -Path $c.file
    Assert-That ($stored.Count -eq 3 -and $stored[2] -notmatch 'base64' -and $stored[2] -match 'left out') 'session file: one line per message, images left out, no system prompt'
    [System.IO.File]::AppendAllText($c.file, '{"compact":true}' + "`n" + '{"role":"user","content":"summary"}' + "`n")
    $back = New-TestSession $proj 'ask'
    Set-SessionSystemPrompt $back 'fresh system text'
    Import-AgentSession $back $c.file
    Assert-That ($back.messages.Count -eq 2 -and $back.messages[0]['content'] -eq 'fresh system text' -and $back.messages[1]['content'] -eq 'summary' -and $back.lastPrompt -eq 'summary') 'resume: starts after the last summary with a fresh system prompt'
    Clear-OldReasoning $c
    Assert-That (-not ([System.Collections.IDictionary]$c.messages[2]).Contains('reasoning_content')) 'thinking of earlier requests is dropped'
    $big = New-TestSession $proj 'ask'
    Set-SessionSystemPrompt $big 'sys'
    for ($i = 0; $i -lt 10; $i++) {
        Add-SessionMessage $big @{ role = 'assistant'; content = ''; tool_calls = @(@{ id = "x$i"; type = 'function'; function = @{ name = 'Read'; arguments = '{}' } }) }
        Add-SessionMessage $big @{ role = 'tool'; tool_call_id = "x$i"; content = ('x' * 5000) }
    }
    $big.promptTokens = 15000
    $big.charsAtPrompt = Get-SessionChars $big
    $before = Get-EstimatedTokens $big
    $saved = Compress-OldToolResults $big 6 1500
    $after = Get-EstimatedTokens $big
    Assert-That ($saved -gt 10000 -and $after -lt $before -and $big.messages[$big.messages.Count - 1]['content'].Length -eq 5000) 'context: old tool results are shortened, the last rounds stay, the estimate drops'

    # --- 7. system prompt and commands -------------------------------------------------------------------
    [System.IO.File]::WriteAllText((Join-Path $root 'AGENTS.md'), 'outer rule', $utf8)
    [System.IO.File]::WriteAllText((Join-Path $proj 'CLAUDE.md'), 'inner rule', $utf8)
    $sp = New-TestSession $proj 'ask'
    $prompt = New-AgentSystemPrompt $sp
    Assert-That ($prompt -notmatch '\{\{' -and $prompt.Contains($proj)) 'system prompt: all facts filled in'
    Assert-That ($prompt.IndexOf('outer rule') -ge 0 -and $prompt.IndexOf('outer rule') -lt $prompt.IndexOf('inner rule')) 'system prompt: instructions of the folders above first, the project last'
    $commands = Get-AgentCommands
    Assert-That ($commands.ContainsKey('feature') -and $commands.ContainsKey('bugfix') -and $commands.ContainsKey('review')) 'commands: /feature, /bugfix, /pruefen from config\befehle'
    $r = Invoke-SlashCommand $sp '/local:feature a login form'
    Assert-That ($r.prompt.Contains('a login form') -and -not $r.prompt.Contains('$ARGUMENTS') -and -not $r.exit) 'commands: /local:feature puts the arguments in'
    $r = Invoke-SlashCommand $sp '/mode edits'
    Assert-That ($sp.mode -eq 'edits' -and -not $r.prompt) 'commands: /mode edits'
    $r = Invoke-SlashCommand $sp '/mode'
    Assert-That ($sp.mode -eq 'all') 'commands: /mode without argument goes to the next mode'
    $r = Invoke-SlashCommand $sp '/exit'
    Assert-That ($r.exit) 'commands: /exit ends'
    $r = Invoke-SlashCommand $sp '/init'
    Assert-That ($r.prompt -match 'AGENTS\.md') 'commands: /init asks for AGENTS.md'
    $content = ConvertTo-UserContent "what is this? [image: $png]"
    Assert-That ($content -is [System.Array] -and @($content).Count -eq 2 -and $content[1].type -eq 'image_url') 'input: an image pasted with Alt+V goes along'
    $o = ConvertFrom-AgentArgs @('-Model', 'schnell', '-p', '--permission-mode', 'acceptEdits', '--allowedTools', 'Bash(python:*)', 'Bash(git log:*)', '--output-format', 'json', 'do', 'it')
    Assert-That ($o.model -eq 'schnell' -and $o.print -and $o.mode -eq 'acceptEdits' -and $o.allowed.Count -eq 2 -and $o.allowed[1] -eq 'Bash(git log:*)' -and $o.format -eq 'json' -and ($o.positional -join ' ') -eq 'do it') 'arguments: the flags of the benchmark'

    # --- 8. closing check with the transcript of Unzensiert ---------------------------------------------------
    $chk = Join-Path $root 'checked'
    New-Item -ItemType Directory -Force -Path (Join-Path $chk 'scripts') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $chk 'scripts\Check.ps1'), "Write-Output 'probe check failed'; exit 1`r`n", $utf8)
    $h = New-TestSession $chk 'all'
    $null = Invoke-AgentTool $h 'Write' @{ file_path = 'main.py'; content = 'print(1)' }
    Add-HookTranscript $h 'prompt' 'write main.py'
    Add-HookTranscript $h 'Write' (Join-Path $chk 'main.py') 'call_1'
    $env:CLAUDE_LOCAL_AGENT = 'Unzensiert'
    $answer = Invoke-StopHook ("test-" + $h.id) $h.hookTranscript $chk $false $null
    Assert-That ($answer.decision -eq 'block' -and $answer.reason -match 'probe check failed' -and $answer.reason -match 'Unzensiert') 'closing check: reads the transcript of Unzensiert and sends a failed check back'

    # --- 9. updates ---------------------------------------------------------------------------------------
    Assert-That ((Test-NewerVersion 'v1.2.0' '1.1.9') -and (Test-NewerVersion 'v1.10.0' '1.9.0') -and -not (Test-NewerVersion 'v1.0.0' '1.0.0') -and -not (Test-NewerVersion 'main' '1.0.0')) 'updates: versions compare as numbers'
    $rel = ConvertFrom-ReleaseInfo (ConvertFrom-AgentJson '{"tag_name":"v2.0.1","draft":false,"prerelease":false,"html_url":"https://example.invalid/r"}') 'owner/repo'
    Assert-That ($rel.version -eq '2.0.1' -and $rel.zip -eq 'https://github.com/owner/repo/archive/refs/tags/v2.0.1.zip') 'updates: a release gives version and ZIP address'
    Assert-That ($null -eq (ConvertFrom-ReleaseInfo (ConvertFrom-AgentJson '{"tag_name":"v3.0.0","draft":false,"prerelease":true}') 'o/r')) 'updates: pre-releases are not installed'
    Assert-That ((Get-ProgramVersion) -match '^\d+\.\d+\.\d+$') 'updates: VERSION holds a version number'
    if ((Get-InstallKind) -eq 'git' -and (Get-UpdateConfig).enabled) {
        Assert-That ([bool](Get-UpdateBlocker)) 'updates: this git copy is not updated automatically (development copy or changes)'
    }

    # --- 10. terminal output -------------------------------------------------------------------------------------
    $orig = [Console]::Out
    $sw = New-Object System.IO.StringWriter
    $uiError = ''
    try {
        [Console]::SetOut($sw)
        Initialize-AgentUi $true $false
        $script:Ui.on = $true
        Start-UiAnswer
        Add-UiReasoning 'some thinking'
        Add-UiContent "# Title`nA **bold** word and ``code``.`n- item`n``````python`nx = 1`n```````n"
        Complete-UiAnswer
        Write-UiToolStart 'Bash' @{ command = 'python -m pytest' } $proj
        Write-UiToolResult @{ error = $false; text = "line 1`nline 2"; diff = $null; summary = ''; info = @{ exit = 0; output = "line 1`nline 2"; stopped = '' } } 'Bash'
        Write-UiToolStart 'Edit' @{ file_path = 'src\app.py' } $proj
        Write-UiToolResult @{ error = $false; text = ''; diff = @{ old = 'a'; new = "b`nc"; line = 3 }; summary = '' } 'Edit'
        Write-UiNote 'a warning' 'warn'
        # not $ui: PowerShell names ignore case, that would be $script:Ui of lib\AgentUi.ps1
        $statusSession = New-TestSession $proj 'edits'
        $statusSession.model = Get-DefaultAgentModel
        if (-not $statusSession.model) { $statusSession.model = 'local-coder' }
        Write-UiStatus $statusSession
    } catch {
        $uiError = $_.Exception.Message + ' ' + $_.ScriptStackTrace
    } finally {
        [Console]::SetOut($orig)
        Initialize-AgentUi $false $false
    }
    # what a terminal shows: colours removed, a line rewritten after a carriage return
    $shown = (($sw.ToString() -replace "$([char]27)\[[0-9;]*[A-Za-z]", '') -split "`n" | ForEach-Object { $_.Substring($_.LastIndexOf("`r") + 1) }) -join "`n"
    Assert-That (-not $uiError) "terminal: answer, tools and status line render without error $uiError"
    Assert-That ($shown.Contains('Title') -and $shown.Contains('bold') -and $shown.Contains('x = 1') -and -not $shown.Contains('**')) 'terminal: Markdown is shown formatted'
    Assert-That ($shown.Contains((Get-UiText 'tools.at' 3)) -and $shown.Contains('+ c') -and $shown.Contains('edits')) 'terminal: diff of an edit and the rights in the status line'
    Assert-That (-not $shown.Contains('System.')) 'terminal: no list or object printed as its type name'

    # wrapping, diffs and the colours of code (lib\AgentUiMarkdown.ps1, lib\AgentUiTools.ps1)
    $script:Ui.on = $true
    $long = ConvertTo-UiInlineSpans ('A paragraph with **bold** and `code`, ' * 6) '#FFFFFF'
    $wrapped = Format-UiWrapped $long '  ' '  ' 2 40
    Assert-That ($wrapped.Count -ge 4 -and @($wrapped | Where-Object { (Measure-UiText $_) -gt 40 }).Count -eq 0) "terminal: a long paragraph is wrapped into $($wrapped.Count) lines of at most 40 columns"
    $steps = Get-UiLineDiff @('a', 'b', 'c', 'd') @('a', 'x', 'c', 'd')
    Assert-That ((@($steps | ForEach-Object { $_[0] }) -join '') -eq ' -+  ') 'terminal: the diff of two texts finds the one changed line'
    $range = Get-UiChangedRange '    return a + b' '    return a * b'
    Assert-That ($range -and $range[0] -eq 13 -and $range[1] -eq 14) 'terminal: inside a changed line only the changed character is marked'
    $lostChars = @()
    $samples = @{ python = 'def f(x):  # "q" ''s'' 0x1F'; powershell = '$a = Get-Item -Path "C:\x" # c'; js = 'const s = `t` + f(1) // c'; c = '#include <a.h> int main() { return 0; }'; json = '{"k": [1, true, null]}'; bash = 'echo "$HOME" | grep -v x # c'; generic = 'irgendwas 12 "x"' }
    foreach ($lang in $samples.Keys) {
        $script:Ui.codeState = ''
        $joined = (@(ConvertTo-UiCodeSpans $samples[$lang] $lang) | ForEach-Object { $_.t }) -join ''
        if ($joined -cne $samples[$lang]) { $lostChars += $lang }
    }
    $script:Ui.codeState = ''
    Assert-That ($lostChars.Count -eq 0) "terminal: the colours of code keep every character $($lostChars -join ', ')"
    $script:Ui.on = $false

    # every element of the look once, as scripts\Show-AgentDesign.ps1 shows it
    $designFile = Join-Path $root 'design.ans'
    $designOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Show-AgentDesign.ps1') -OutFile $designFile -Width 100 -Seed 1 2>&1
    $design = ''
    if (Test-Path $designFile) { $design = [System.IO.File]::ReadAllText($designFile) -replace "$([char]27)\[[0-9;]*m", '' }
    Assert-That ($LASTEXITCODE -eq 0 -and $design.Contains((Get-UiText 'permission.title')) -and $design.Contains((Get-UiText 'statusPanel.title')) -and -not $design.Contains('System.')) "terminal: the design preview shows every element $designOut"

    # --- 11. a task with the model ------------------------------------------------------------------------------
    if ($WithModel) {
        $work = Join-Path $root 'with-model'
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        $launcher = Join-Path $PSScriptRoot 'unzensiert.ps1'
        $promptFile = Join-Path $root 'prompt.txt'
        [System.IO.File]::WriteAllText($promptFile, "Create the file calc.py with a function mul(a, b) that returns a * b, and run python -c `"import calc; print(calc.mul(6, 7))`" to show that it works.", $utf8)
        $out = Join-Path $root 'out.txt'
        $proc = Start-Process -FilePath 'powershell.exe' -WorkingDirectory $work -RedirectStandardInput $promptFile -RedirectStandardOutput $out -RedirectStandardError (Join-Path $root 'err.txt') -WindowStyle Hidden -PassThru `
            -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -OnExit keep -p --permission-mode acceptEdits --allowedTools "Bash(python:*)" "PowerShell(python:*)" --output-format json' -f $launcher)
        $finished = $proc.WaitForExit(300000)
        if (-not $finished) { & cmd /c "taskkill /PID $($proc.Id) /T /F >nul 2>&1" }
        $json = Get-Content -Path $out -ErrorAction SilentlyContinue | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1
        $result = $null
        if ($json) { $result = $json | ConvertFrom-Json }
        Assert-That ($finished -and $result -and -not $result.is_error -and $result.num_turns -ge 2) "with model: -p run ends with a JSON result ($(if ($result) { "$($result.num_turns) turns, $([int]($result.duration_ms / 1000)) s" }))"
        $check = ''
        if (Test-Path (Join-Path $work 'calc.py')) { $check = (& cmd /c "cd /d `"$work`" && python -c `"import calc; print(calc.mul(6, 7))`" 2>&1") -join '' }
        Assert-That ($check.Trim() -eq '42') 'with model: calc.py is there and calc.mul(6, 7) gives 42'

        # summarising keeps what matters: the model writes the summary, the facts must survive
        $cs = New-TestSession $work 'all'
        $cs.model = Get-DefaultAgentModel
        Set-SessionSystemPrompt $cs 'You are a coding agent.'
        Add-SessionMessage $cs @{ role = 'user'; content = 'The build number is 4711 and the config lives in src/settings.toml. Add a function area(r) to geometry.py.' }
        Add-SessionMessage $cs @{ role = 'assistant'; content = 'Added area(r) to geometry.py; it returns 3.14159 * r * r.' }
        $cs.lastPrompt = 'Now write a test for area(r).'
        Add-SessionMessage $cs @{ role = 'user'; content = $cs.lastPrompt }
        $ok = Invoke-Compaction $cs ''
        $summary = [string]$cs.messages[$cs.messages.Count - 1]['content']
        Assert-That ($ok -and $cs.messages.Count -eq 2 -and $summary.Contains('4711') -and $summary.Contains('settings.toml') -and $summary.Contains('Now write a test for area(r).')) 'with model: a summary keeps the facts and the last request word for word'
        Assert-That ((Get-Content -Path $cs.file -Raw).Contains('{"compact":true}')) 'with model: the session file marks the summary'
    }
} finally {
    Remove-Item -Recurse -Force -Path $root -ErrorAction SilentlyContinue
}

if ($script:Failures -gt 0) { "agent: $script:Failures check(s) failed."; exit 1 }
'agent: all checks passed.'
