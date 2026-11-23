# Closing check for claude-local sessions: a Stop hook of Claude Code. It runs when the
# local model wants to end its answer. If the model changed files since the last look, the
# hook
#   1. runs the check command of the project (first existing file of "commands", for
#      example scripts\Check.ps1) and hands a failure back to the model, and
#   2. once per answer reminds the model of the steps it tends to forget (test, README,
#      settings in the configuration file): config\closing-check.md. A point is left out when
#      the files changed in this answer show that it is done ("reminderPoints"); if no
#      point is open, there is no reminder.
#   3. once per answer, when nothing else is open and the uncommitted change is large
#      enough, a second local model reviews it (scripts\Invoke-Review.ps1, "review" in
#      config\agent.json); errors it finds go back to the model.
# The model then continues instead of reporting "done". Nothing happens after answers
# that changed no file.
#
#   input     the hook JSON of Claude Code on stdin (session_id, transcript_path, cwd,
#             stop_hook_active); Unzensiert adds run_check: whether the user lets the check
#             command run. Without it only a command the user confirmed (TrustRules.ps1) runs.
#   output    nothing = the model may stop, or {"decision":"block","reason":...}
#   settings  "stopCheck" in config\agent.json     docs  docs\agent.md
#   state     <installRoot>\run\stop\<session>.json (edits seen, failures handed back)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\hooks\Check-Stop.ps1 < call.json
#
# Self-contained on purpose (no _common.ps1), like Guard-Tool.ps1. Any error inside the
# hook lets the model stop: a broken hook must never trap a session. ASCII-only.

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# install folder of this machine as $env:CLAUDE_LOCAL_ROOT (state files live there)
. "$PSScriptRoot\HookEnvironment.ps1"
Initialize-HookEnvironment
. "$PSScriptRoot\TrustRules.ps1"
# no program from the folder of the project instead of the real one (lib\Git.ps1)
$env:NoDefaultCurrentDirectoryInExePath = '1'
$script:PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:TaskkillExe = Join-Path $env:SystemRoot 'System32\taskkill.exe'
# the agent that asks: claude-local (Claude Code) or Unzensiert, which sets this variable
$script:AgentName = 'claude-local'
if ($env:CLAUDE_LOCAL_AGENT) { $script:AgentName = $env:CLAUDE_LOCAL_AGENT }

function Read-Json([string]$Path) {
    return (Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json)
}

function Get-EditedFiles([string]$Transcript) {
    # Paths of the file-changing tool calls in the transcript of the session, in order,
    # one entry per call ('' if the path cannot be read). Only real calls count: newer
    # versions of Claude Code also write the tool descriptions into the transcript
    # ({"name":"Edit","description":...}) and repeat earlier messages with every request,
    # so a call is a "tool_use" block and each call id counts once.
    if (-not $Transcript -or -not (Test-Path $Transcript)) { return @() }
    $text = [System.IO.File]::ReadAllText($Transcript)
    $files = @()
    $ids = @{}
    $pattern = '"type"\s*:\s*"tool_use"\s*,\s*(?:"id"\s*:\s*"([^"]*)"\s*,\s*)?"name"\s*:\s*"(Edit|Write|NotebookEdit)"'
    foreach ($match in [regex]::Matches($text, $pattern)) {
        $id = $match.Groups[1].Value
        if ($id) {
            if ($ids.ContainsKey($id)) { continue }
            $ids[$id] = $true
        }
        $window = $text.Substring($match.Index, [Math]::Min(600, $text.Length - $match.Index))
        $path = [regex]::Match($window, '"(file_path|notebook_path)"\s*:\s*"((?:[^"\\]|\\.)*)"')
        if ($path.Success) { $files += ($path.Groups[2].Value -replace '\\\\', '\' -replace '\\/', '/') } else { $files += '' }
    }
    return @($files)
}

function Select-Reminder([string]$Text, $Points, $Files) {
    # The reminder text without the points that the changed files show as done. A point is
    # a line of the form "- [name] text". Points listed in $Points are open unless one of
    # $Files matches their "doneWhenEdited"; with "codeOnly" they are open only if a file
    # was changed that matches no pattern at all (program code). Points not listed in
    # $Points stay only if a listed point is open. Returns '' if no listed point is open.
    $patterns = @($Points | ForEach-Object { [string]$_.doneWhenEdited } | Where-Object { $_ })
    $code = $false
    foreach ($file in $Files) {
        $known = $false
        foreach ($pattern in $patterns) { if ($file -match $pattern) { $known = $true } }
        if (-not $known) { $code = $true }
    }
    $open = @{}
    foreach ($point in @($Points)) {
        $done = $false
        foreach ($file in $Files) { if ($point.doneWhenEdited -and $file -match [string]$point.doneWhenEdited) { $done = $true } }
        if ($point.codeOnly -and -not $code) { $done = $true }
        $open[[string]$point.name] = (-not $done)
    }
    if (@($open.Values | Where-Object { $_ }).Count -eq 0) { return '' }
    $kept = @()
    $number = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $tag = [regex]::Match($line, '^- \[([^\]]+)\]\s*(.*)$')
        if (-not $tag.Success) { $kept += $line; continue }
        $name = $tag.Groups[1].Value
        if ($open.ContainsKey($name) -and -not $open[$name]) { continue }
        $number++
        $kept += "$number. $($tag.Groups[2].Value)"
    }
    return ($kept -join "`n").Trim()
}

function Find-CheckCommand([string]$Folder, $Candidates) {
    # The check script of the project in $Folder, or $null.
    foreach ($candidate in @($Candidates)) {
        $path = Join-Path $Folder ([string]$candidate)
        if (Test-Path $path -PathType Leaf) { return $path }
    }
    return $null
}

function Invoke-CheckCommand([string]$Script, [string]$Folder, [int]$TimeoutSeconds) {
    # Runs the check script in $Folder. Returns ok, timeout and the end of its output.
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    try {
        $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script`""
        $process = Start-Process -FilePath $script:PowerShellExe -ArgumentList $arguments -WorkingDirectory $Folder `
            -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
        $null = $process.Handle          # without this, Windows PowerShell 5.1 loses the exit code
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $finished) { & $script:TaskkillExe /T /F /PID $process.Id 2>$null | Out-Null }
        $lines = @(Get-Content -Path $out -Encoding UTF8) + @(Get-Content -Path $err -Encoding UTF8)
        $tail = (@($lines | Select-Object -Last 40) -join "`n")
        if ($tail.Length -gt 3000) { $tail = $tail.Substring($tail.Length - 3000) }
        return @{ ok = ($finished -and $process.ExitCode -eq 0); timeout = (-not $finished); output = $tail }
    } finally {
        Remove-Item -Path $out, $err -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SecondLook([string]$Folder, [string]$Transcript, $Settings) {
    # Runs scripts\Invoke-Review.ps1 for $Folder and returns its JSON result, or $null if
    # it did not finish in time or gave no answer.
    $script = Join-Path $script:ProjectRoot 'scripts\Invoke-Review.ps1'
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    try {
        $arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -Folder `"$Folder`" -Transcript `"$Transcript`" -MinLines $([int]$Settings.minChangedLines) -Json"
        $process = Start-Process -FilePath $script:PowerShellExe -ArgumentList $arguments -WorkingDirectory $Folder `
            -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
        $null = $process.Handle
        if (-not $process.WaitForExit(([int]$Settings.timeoutSeconds + 30) * 1000)) {
            & $script:TaskkillExe /T /F /PID $process.Id 2>$null | Out-Null
            return $null
        }
        $text = ([System.IO.File]::ReadAllText($out)).Trim()
        if (-not $text) { return $null }
        return ($text | ConvertFrom-Json)
    } finally {
        Remove-Item -Path $out, $err -Force -ErrorAction SilentlyContinue
    }
}

function Write-HookAnswer($Answer) {
    # JSON for Claude Code, with everything beyond ASCII escaped so that no console
    # code page can damage it.
    $json = $Answer | ConvertTo-Json -Compress -Depth 4
    $json = [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    [Console]::Out.Write($json)
}

try {
    $call = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $agent = Read-Json (Join-Path $script:ProjectRoot 'config\agent.json')
    $settings = $agent.stopCheck
    if (-not $settings -or -not $settings.enabled) { exit 0 }
    $review = $agent.review

    if (-not $env:CLAUDE_LOCAL_ROOT) { exit 0 }
    $stateDir = Join-Path $env:CLAUDE_LOCAL_ROOT 'run\stop'
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $stateFile = Join-Path $stateDir ("$($call.session_id)" -replace '[^\w-]', '_')
    $stateFile = "$stateFile.json"
    $state = @{ seen = 0; blocks = 0; answerEdited = $false; reviewDone = $false }
    if (Test-Path $stateFile) {
        $saved = Read-Json $stateFile
        $state.seen = [int]$saved.seen
        $state.blocks = [int]$saved.blocks
        $state.answerEdited = [bool]$saved.answerEdited
        $state.reviewDone = [bool]$saved.reviewDone
    }
    # the first stop of an answer: the model is not continuing because of this hook
    if (-not $call.stop_hook_active) { $state.answerEdited = $false; $state.reviewDone = $false }

    $files = @(Get-EditedFiles ([string]$call.transcript_path))
    $edits = $files.Count
    $reviewDue = ($review -and $review.enabled -and -not $state.reviewDone)
    # nothing changed since the last look, and no second look is waiting for this answer
    if ($edits -eq $state.seen -and -not ($reviewDue -and $state.answerEdited)) {
        [System.IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Compress))
        exit 0
    }

    $folder = [string]$call.cwd
    if (-not $folder) { $folder = (Get-Location).Path }
    $parts = @()
    $warning = ''
    $checkFailed = $false
    $remind = $false

    if ($edits -ne $state.seen) {
        $state.answerEdited = $true
        $newFiles = @()
        if ($edits -gt $state.seen) { $newFiles = @($files[$state.seen..($edits - 1)]) } else { $newFiles = $files }

        # 1. the check command of the project
        $check = Find-CheckCommand $folder $settings.commands
        if ($check) {
            $mayRun = $false
            if ($null -ne $call.PSObject.Properties['run_check']) { $mayRun = [bool]$call.run_check }
            else { $mayRun = Test-CheckTrusted $folder $settings.commands }
            if (-not $mayRun) {
                if ($null -eq $call.PSObject.Properties['run_check']) { $warning = "$($script:AgentName): the check command $($check.Substring($folder.TrimEnd('\').Length + 1)) was not run, because it is not confirmed for this folder. Start $($script:AgentName) once in a terminal here and say yes to it." }
                $check = $null
            }
        }
        if ($check) {
            $name = $check.Substring($folder.TrimEnd('\').Length + 1)
            $result = Invoke-CheckCommand $check $folder ([int]$settings.timeoutSeconds)
            if (-not $result.ok) {
                $why = 'failed'
                if ($result.timeout) { $why = "ran longer than $($settings.timeoutSeconds) s and was stopped" }
                if ($state.blocks -lt [int]$settings.maxBlocks) {
                    $checkFailed = $true
                    $state.blocks++
                    $parts += "The project check ($name) $why. Fix the cause and check again before you report the task as done. End of the output:`n$($result.output)"
                } else {
                    $warning = "$($script:AgentName): the project check ($name) $why, also after $($settings.maxBlocks) attempts of the model. Please look at it yourself."
                }
            } else {
                $state.blocks = 0
                $parts += "The project check ($name) passed."
            }
        }

        # 2. the reminder comes once per answer: not when the model is already continuing
        # because of this hook
        $reminderFile = Join-Path $script:ProjectRoot "config\$($settings.reminderFile)"
        if (-not $call.stop_hook_active -and $settings.reminderFile -and (Test-Path $reminderFile)) {
            $reminder = (Get-Content -Raw -Path $reminderFile -Encoding UTF8).Trim()
            if ($settings.reminderPoints) { $reminder = Select-Reminder $reminder $settings.reminderPoints $newFiles }
            if ($reminder) {
                $remind = $true
                $parts += $reminder
            }
        }
        if (-not $checkFailed) { $state.seen = $edits }
    }

    # 3. the second look, once per answer, when nothing else is open
    $reviewBlock = $false
    if ($reviewDue -and $state.answerEdited -and -not $checkFailed -and -not $remind -and -not $warning) {
        $state.reviewDone = $true
        $found = Invoke-SecondLook $folder ([string]$call.transcript_path) $review
        if (-not $found) {
            $warning = "$($script:AgentName): the second look did not answer within $($review.timeoutSeconds) s."
        } elseif ($found.status -eq 'error') {
            $warning = "$($script:AgentName): the second look did not run: $($found.reason)"
        } elseif (@($found.errors).Count -gt 0) {
            $reviewBlock = $true
            $list = @(@($found.errors) | ForEach-Object { "- ERROR | $_" }) + @(@($found.hints) | ForEach-Object { "- HINT | $_" })
            $parts = @("Second look: a second model ($($found.model)) checked the uncommitted change in a fresh context and reports:`n" + ($list -join "`n") + "`n`nCheck every finding against the code; the reviewer sees only the diff and can be wrong. Fix what is right and check again afterwards. Name what is not right in your answer to the user, with a short reason.")
        } elseif (@($found.hints).Count -gt 0) {
            $warning = "$($script:AgentName), second look ($($found.model)), hints without errors:`n" + ((@($found.hints) | ForEach-Object { "- $_" }) -join "`n")
        }
    }

    [System.IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Compress))
    # state files of sessions that ended long ago
    Get-ChildItem -Path $stateDir -Filter '*.json' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if ($checkFailed -or $remind -or $reviewBlock) {
        Write-HookAnswer @{ decision = 'block'; reason = "Closing check of $($script:AgentName). " + ($parts -join "`n`n") }
    } elseif ($warning) {
        Write-HookAnswer @{ systemMessage = $warning }
    }
} catch {
    # set CLAUDE_LOCAL_HOOK_DEBUG=1 to see why the hook gave up
    if ($env:CLAUDE_LOCAL_HOOK_DEBUG) { [Console]::Error.WriteLine("Check-Stop: $($_.Exception.Message) ($($_.InvocationInfo.ScriptLineNumber))") }
    exit 0
}
exit 0
