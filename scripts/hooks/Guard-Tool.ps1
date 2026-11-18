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
# install and projects folder of this machine, used by %CLAUDE_LOCAL_ROOT% and
# %CLAUDE_LOCAL_PROJECTS% in config\guard.json
. "$PSScriptRoot\HookEnvironment.ps1"
Initialize-HookEnvironment
. "$PSScriptRoot\GuardRules.ps1"

function Write-Verdict([string]$Tool, [string]$Subject) {
    # Prints the decision for Claude Code and notes it in the log. No output = go ahead.
    $v = $script:Verdict
    if ($v.decision -eq 'none') { return }
    $text = "Guard of claude-local (rule $($v.rule)): $($v.reason)."
    if ($v.decision -eq 'deny') { $text += ' Blocked. Do not work around it; tell the user what was planned and why.' }
    else { $text += ' The user decides.' }
    $out = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = $v.decision; permissionDecisionReason = $text } }
    [Console]::Out.Write(($out | ConvertTo-Json -Compress -Depth 4))
    Write-GuardLog $Tool $Subject $v
}

# --- main -------------------------------------------------------------------------------

$tool = ''
$subject = ''
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $call = $reader.ReadToEnd() | ConvertFrom-Json
    $tool = [string]$call.tool_name
    $subject = Get-GuardSubject $tool $call.tool_input
    $null = Invoke-GuardCheck $tool $call.tool_input ([string]$call.cwd) (Get-GuardRules)
} catch {
    # A broken guard must not pass silently and must not stop all work: let the user decide.
    Set-Verdict 'ask' 'guard-error' "The guard check failed ($($_.Exception.Message)); run scripts\Test-Setup.ps1"
}
Write-Verdict $tool $subject
exit 0
