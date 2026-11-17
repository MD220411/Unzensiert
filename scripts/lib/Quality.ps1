# Working method of the local model in claude-local sessions: the closing check (a Stop
# hook of Claude Code, scripts\hooks\Check-Stop.ps1, settings "stopCheck" and "review" in
# config\agent.json) and the fixed procedures /feature, /bugfix, /pruefen (a plugin folder,
# "pluginDir" in config\agent.json). Needs lib\Config.ps1. Keep this file ASCII-only.
# Description: docs\agent.md.

function Get-StopCheckScript {
    return (Join-Path $script:ProjectRoot 'scripts\hooks\Check-Stop.ps1')
}

function Get-QualitySettings {
    # Settings for Claude Code (--settings) that run the closing check whenever the model
    # wants to end an answer. Empty if "stopCheck" is missing or switched off.
    $cfg = (Get-AgentConfig).stopCheck
    if (-not $cfg -or -not $cfg.enabled) { return [ordered]@{} }
    $hook = [ordered]@{
        type    = 'command'
        command = 'powershell.exe'
        args    = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Get-StopCheckScript))
        # the check command of the project and the second look run inside the hook
        timeout = [int]$cfg.timeoutSeconds + 30
    }
    $review = (Get-AgentConfig).review
    if ($review -and $review.enabled) { $hook.timeout += [int]$review.timeoutSeconds + 60 }
    return [ordered]@{ hooks = [ordered]@{ Stop = @([ordered]@{ hooks = @($hook) }) } }
}

function Get-PluginDir {
    # Folder with the commands of claude-local, or '' if none is configured or present.
    $name = [string](Get-AgentConfig).pluginDir
    if (-not $name) { return '' }
    $dir = Join-Path $script:ConfigDir $name
    if (Test-Path (Join-Path $dir '.claude-plugin\plugin.json')) { return $dir }
    return ''
}

function Merge-Settings($Target, $Source) {
    # Adds the keys of $Source to the ordered hashtable $Target. Hooks of different
    # events (PreToolUse, Stop) are merged instead of overwritten.
    foreach ($key in $Source.Keys) {
        if ($key -eq 'hooks' -and $Target.Contains('hooks')) {
            foreach ($event in $Source.hooks.Keys) { $Target.hooks[$event] = $Source.hooks[$event] }
        } else {
            $Target[$key] = $Source[$key]
        }
    }
}

function Invoke-StopHook([string]$SessionId, [string]$Transcript, [string]$Cwd, [bool]$Active) {
    # Asks the closing check the way Claude Code does. Returns decision ('' or 'block')
    # and reason. Used by Test-Setup.ps1.
    $call = [ordered]@{ hook_event_name = 'Stop'; session_id = $SessionId; transcript_path = $Transcript; cwd = $Cwd; stop_hook_active = $Active }
    $json = $call | ConvertTo-Json -Compress
    $out = $json | & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Get-StopCheckScript)
    $result = [ordered]@{ decision = ''; reason = '' }
    $text = (@($out) -join '').Trim()
    if ($text) {
        $answer = $text | ConvertFrom-Json
        $result.decision = [string]$answer.decision
        $result.reason = [string]$answer.reason
    }
    return $result
}
