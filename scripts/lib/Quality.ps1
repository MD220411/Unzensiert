# Working method of the local model in claude-local sessions: the closing check (a Stop
# hook of Claude Code, scripts\hooks\Check-Stop.ps1, settings "stopCheck" and "review" in
# config\agent.json) and the fixed procedures /feature, /bugfix, /review (a plugin folder,
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
        command = (Get-SystemProgram 'powershell')
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

function Invoke-StopHook([string]$SessionId, [string]$Transcript, [string]$Cwd, [bool]$Active, [scriptblock]$ShouldStop, [bool]$RunCheck = $true) {
    # Asks the closing check the way Claude Code does. Returns decision ('' or 'block'),
    # reason, systemMessage and cancelled. Used by the agent Unzensiert (lib\AgentLoop.ps1)
    # and Test-Setup.ps1. ShouldStop ($true = stop) lets a person at the terminal break off
    # a long check; the hook and everything it started are ended then. RunCheck: whether the
    # check command of the project may run (lib\Trust.ps1, Test-CheckAllowed).
    $call = [ordered]@{ hook_event_name = 'Stop'; session_id = $SessionId; transcript_path = $Transcript; cwd = $Cwd; stop_hook_active = $Active; run_check = $RunCheck }
    # characters beyond ASCII escaped: the pipe to the hook uses the console code page
    $json = [regex]::Replace(($call | ConvertTo-Json -Compress), '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-SystemProgram 'powershell'
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Get-StopCheckScript) + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Cwd -and (Test-Path -LiteralPath $Cwd)) { $psi.WorkingDirectory = $Cwd }
    $result = [ordered]@{ decision = ''; reason = ''; systemMessage = ''; cancelled = $false }
    $proc = Start-ChildProcess $psi
    $proc.StandardInput.Write($json)
    $proc.StandardInput.Close()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $null = $proc.StandardError.ReadToEndAsync()
    while (-not $proc.WaitForExit(100)) {
        if ($ShouldStop -and (& $ShouldStop)) {
            Stop-ProcessTree $proc.Id
            $result.cancelled = $true
            return $result
        }
    }
    $null = $outTask.Wait(5000)
    $text = ([string]$outTask.Result).Trim()
    if ($text) {
        $answer = $text | ConvertFrom-Json
        $result.decision = [string]$answer.decision
        $result.reason = [string]$answer.reason
        $result.systemMessage = [string]$answer.systemMessage
    }
    return $result
}
