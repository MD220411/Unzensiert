# Shared by the hooks (Guard-Tool.ps1, Check-Stop.ps1), which do not load scripts\lib\ so
# that they start fast. Makes sure the install folder and the projects folder of this
# machine are known as $env:CLAUDE_LOCAL_ROOT and $env:CLAUDE_LOCAL_PROJECTS.
# Normally scripts\_common.ps1 has set both before Claude Code started the hook; read from
# config\machine.json and the defaults only when a hook is started by hand.
# Keep this file ASCII-only.

function Get-HookSetting([string]$Section, [string]$Key) {
    # The value of this machine (config\machine.json) or the default (config\<Section>.json),
    # with %VARIABLES% expanded; '' if neither has it.
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $machineFile = $env:CLAUDE_LOCAL_MACHINE_FILE
    if (-not $machineFile) { $machineFile = Join-Path $root 'config\machine.json' }
    $value = ''
    try {
        if (Test-Path $machineFile) {
            $machine = Get-Content -Raw -Path $machineFile -Encoding UTF8 | ConvertFrom-Json
            if ($machine.$Section -and $machine.$Section.$Key) { $value = [string]$machine.$Section.$Key }
        }
        if (-not $value) {
            $defaults = Get-Content -Raw -Path (Join-Path $root "config\$Section.json") -Encoding UTF8 | ConvertFrom-Json
            $value = [string]$defaults.$Key
        }
    } catch { return '' }
    return [Environment]::ExpandEnvironmentVariables($value)
}

function Initialize-HookEnvironment {
    if (-not $env:CLAUDE_LOCAL_ROOT) { $env:CLAUDE_LOCAL_ROOT = Get-HookSetting 'server' 'installRoot' }
    if (-not $env:CLAUDE_LOCAL_PROJECTS) { $env:CLAUDE_LOCAL_PROJECTS = Get-HookSetting 'projects' 'projectsRoot' }
}
