# Keeps track of the running claude-local sessions, so that the last one to end can free
# the GPU memory. Needs lib\Config.ps1, lib\Server.ps1 and lib\Measure.ps1.
# Keep this file ASCII-only.
#
# Every session writes a marker file <installRoot>\run\sessions\<pid>.json. A session that
# ended without cleaning up (closed terminal window) leaves its file behind; the file is
# ignored and deleted as soon as its process is gone.

function Get-SessionDir {
    return (Join-Path (Get-ServerConfig).runDir 'sessions')
}

function Register-AgentSession([string]$Model) {
    # Marks this process as a running session.
    $dir = Get-SessionDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $info = [ordered]@{
        pid     = $PID
        # the start time tells this process from a later one that got the same number
        started = (Get-Process -Id $PID).StartTime.ToString('o')
        model   = $Model
    }
    [System.IO.File]::WriteAllText((Join-Path $dir "$PID.json"), ($info | ConvertTo-Json))
}

function Unregister-AgentSession {
    Remove-Item -Path (Join-Path (Get-SessionDir) "$PID.json") -Force -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-OtherAgentSessions {
    # Sessions of other processes that are still running. Deletes markers of dead ones.
    $alive = @()
    foreach ($file in @(Get-ChildItem -Path (Get-SessionDir) -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $info = $null
        try { $info = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json } catch {}
        if ($info -and [int]$info.pid -eq $PID) { continue }
        $process = $null
        if ($info) { $process = Get-Process -Id ([int]$info.pid) -ErrorAction SilentlyContinue }
        if ($process -and $process.StartTime.ToString('o') -eq [string]$info.started) { $alive += $info }
        else { Remove-Item -Path $file.FullName -Force -Confirm:$false -ErrorAction SilentlyContinue }
    }
    return $alive
}

function Complete-AgentSession([string]$Action, [string[]]$Models) {
    # Called when a session ends. Removes its marker and, if it was the last session,
    # frees the GPU memory. Returns one line that says what happened.
    #   unload  unload $Models, the server keeps running (other models stay loaded)
    #   stop    stop the server and with it every model
    #   keep    leave everything as it is
    Unregister-AgentSession
    if ($Action -eq 'keep') { return 'models stay loaded (onExit = keep).' }
    if ($Action -ne 'unload' -and $Action -ne 'stop') {
        return "WARNING - unknown onExit value '$Action' in config\agent.json (unload, stop or keep). Models stay loaded."
    }
    $others = @(Get-OtherAgentSessions)
    if ($others.Count -gt 0) { return "models stay loaded, $($others.Count) other session(s) still running." }
    if (-not (Test-ServerUp)) { return 'server is not running, nothing to free.' }
    try {
        if ($Action -eq 'stop') { Stop-Server; $done = 'server stopped' }
        else { Stop-Models $Models; $done = 'models unloaded' }
        return "$done, GPU memory used now (MiB): $(Get-GpuMemory)"
    } catch {
        return "WARNING - could not free the GPU memory: $($_.Exception.Message) Run scripts\Stop-Server.ps1."
    }
}
