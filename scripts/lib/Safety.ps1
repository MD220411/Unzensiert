# Protection of the user's machine in claude-local sessions: switches the safety guard on
# (a hook of Claude Code, scripts\hooks\Guard-Tool.ps1 with the rules in config\guard.json)
# and reminds of git as the way back. Needs lib\Config.ps1. Keep this file ASCII-only.
# Description: docs\security.md.

function Get-GuardConfig {
    return (Read-JsonFile (Join-Path $script:ConfigDir 'guard.json'))
}

function Get-GuardScript {
    return (Join-Path $script:ProjectRoot 'scripts\hooks\Guard-Tool.ps1')
}

function Get-SafetySettings {
    # Settings for Claude Code (--settings) that run the guard before every tool call.
    # Empty if the guard is switched off in config\guard.json.
    if (-not (Get-GuardConfig).enabled) { return [ordered]@{} }
    $hook = [ordered]@{
        type    = 'command'
        # exec form: started directly, so no shell can mangle the path
        command = 'powershell.exe'
        args    = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Get-GuardScript))
        timeout = 20
    }
    $entry = [ordered]@{ matcher = 'Bash|PowerShell|Read|Edit|Write|NotebookEdit|Glob|Grep'; hooks = @($hook) }
    return [ordered]@{ hooks = [ordered]@{ PreToolUse = @($entry) } }
}

function Invoke-GuardHook([string]$Tool, $ToolInput, [string]$Cwd) {
    # Asks the guard about one tool call, the way Claude Code does. Returns decision
    # (none, ask, deny), rule and reason. Used by Test-Guard.ps1 and Test-Setup.ps1.
    $call = [ordered]@{ hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = $ToolInput; cwd = $Cwd }
    $json = $call | ConvertTo-Json -Compress -Depth 5
    $out = $json | & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Get-GuardScript)
    $result = [ordered]@{ decision = 'none'; rule = ''; reason = '' }
    $text = (@($out) -join '').Trim()
    if ($text) {
        $answer = ($text | ConvertFrom-Json).hookSpecificOutput
        $result.decision = [string]$answer.permissionDecision
        $result.reason = [string]$answer.permissionDecisionReason
        if ($result.reason -match '\(Regel ([\w-]+)\)') { $result.rule = $Matches[1] }
    }
    return $result
}

function Get-GitSafetyNote([string]$Folder) {
    # One line of advice if the model's changes in $Folder could not be undone with git,
    # or '' if all is well.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return '' }
    $inside = & cmd /c "git -C `"$Folder`" rev-parse --is-inside-work-tree 2>nul"
    if ("$inside".Trim() -ne 'true') {
        return 'NOTE - this folder is not a git repository. Changes of the model cannot be undone; "git init" and a first commit give you a way back.'
    }
    $changes = @(& cmd /c "git -C `"$Folder`" status --porcelain 2>nul").Count
    if ($changes -gt 0) {
        return "NOTE - $changes uncommitted change(s) in this repository. Commit first, then the model's changes stay separate and can be undone."
    }
    return ''
}
