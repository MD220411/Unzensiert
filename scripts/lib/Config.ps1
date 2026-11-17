# Reads the files in config\. Every script gets its settings through these functions,
# so no script contains paths, ports or model names of its own.
#
# Two layers:
#   config\*.json         the project's defaults, the same on every machine (in git)
#   config\machine.json   what is true for THIS machine only: folders, graphics cards,
#                         installed models. Written by scripts\Install.ps1, not in git.
# A section of machine.json overrides the file of the same name: "server" -> server.json,
# "agent" -> agent.json, "projects" -> projects.json, "benchmark" -> benchmark.json.
# Profiles are special: "models" -> the profiles in models.json, "modelDefaults" -> their
# "defaults" (see Get-ModelsConfig). Objects are merged key by key, a value null removes
# the key. Paths may use %VARIABLES% such as %LOCALAPPDATA%.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.

$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ConfigDir = Join-Path $script:ProjectRoot 'config'

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json)
}

function Test-JsonObject($Value) {
    return ($Value -is [System.Management.Automation.PSCustomObject])
}

function Merge-ConfigObject($Base, $Overlay) {
    # A copy of $Base with $Overlay laid over it. Objects are merged key by key, any other
    # value (number, text, list) replaces the old one, null removes the key.
    if (-not (Test-JsonObject $Base) -or -not (Test-JsonObject $Overlay)) { return $Overlay }
    $result = [pscustomobject]@{}
    foreach ($p in $Base.PSObject.Properties) { $result | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    foreach ($p in $Overlay.PSObject.Properties) {
        if ($p.Name -eq '_comment') { continue }
        $old = $result.PSObject.Properties[$p.Name]
        if ($null -eq $p.Value) {
            if ($old) { $result.PSObject.Properties.Remove($p.Name) }
        } elseif ($old) {
            $old.Value = Merge-ConfigObject $old.Value $p.Value
        } else {
            $result | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
        }
    }
    return $result
}

function Set-ConfigValue($Object, [string]$Name, $Value) {
    # Sets a key of a JSON object, adding it if missing.
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# --- this machine ------------------------------------------------------------------

function Get-MachineFile {
    # CLAUDE_LOCAL_MACHINE_FILE: lets the tests use a machine file of their own.
    if ($env:CLAUDE_LOCAL_MACHINE_FILE) { return $env:CLAUDE_LOCAL_MACHINE_FILE }
    return (Join-Path $script:ConfigDir 'machine.json')
}

function Get-MachineConfig {
    # config\machine.json, or an empty object if this machine has none yet.
    $file = Get-MachineFile
    if (Test-Path $file) { return (Read-JsonFile $file) }
    return [pscustomobject]@{}
}

function Save-MachineConfig($Machine) {
    # Writes config\machine.json (UTF-8 without BOM). The comment always comes first.
    $out = [ordered]@{ '_comment' = 'Settings of THIS machine, written by scripts\Install.ps1. Not in git. Overrides config\*.json (see scripts\lib\Config.ps1). Install.ps1 keeps values you set here.' }
    foreach ($p in $Machine.PSObject.Properties) { if ($p.Name -ne '_comment') { $out[$p.Name] = $p.Value } }
    $file = Get-MachineFile
    [System.IO.File]::WriteAllText($file, ($out | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
}

function Set-MachineValue([string]$Section, [string]$Key, $Value) {
    # Sets one value of this machine, e.g. Set-MachineValue 'server' 'installRoot' 'D:\x'.
    $machine = Get-MachineConfig
    if (-not $machine.PSObject.Properties[$Section]) { $machine | Add-Member -NotePropertyName $Section -NotePropertyValue ([pscustomobject]@{}) }
    Set-ConfigValue $machine.$Section $Key $Value
    Save-MachineConfig $machine
}

function Set-MachineModelArgs([string]$Name, $Values) {
    # Lays $Values (name -> value) over models.<Name>.args of this machine. A value $null
    # stays in the file as null and removes that option from the profile (Merge-ConfigObject).
    $machine = Get-MachineConfig
    if (-not $machine.PSObject.Properties['models']) { $machine | Add-Member -NotePropertyName models -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $machine.models.PSObject.Properties[$Name]) { $machine.models | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) }
    $entry = $machine.models.$Name
    if (-not $entry.PSObject.Properties['args']) { $entry | Add-Member -NotePropertyName args -NotePropertyValue ([pscustomobject]@{}) }
    foreach ($key in @($Values.Keys)) { Set-ConfigValue $entry.args ([string]$key) $Values[$key] }
    Save-MachineConfig $machine
}

function Read-Config([string]$Name) {
    # config\<Name>.json with the section <Name> of config\machine.json laid over it.
    $cfg = Read-JsonFile (Join-Path $script:ConfigDir "$Name.json")
    $section = (Get-MachineConfig).PSObject.Properties[$Name]
    if ($section) { $cfg = Merge-ConfigObject $cfg $section.Value }
    return $cfg
}

function Expand-SettingPath([string]$Path) {
    # %VARIABLES% in a path from the settings, e.g. %LOCALAPPDATA%\claude-local.
    if (-not $Path) { return '' }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

# --- server, agent, projects ---------------------------------------------------------

function Get-ServerConfig {
    # config\server.json plus the paths derived from it.
    $cfg = Read-Config 'server'
    $cfg.installRoot = Expand-SettingPath ([string]$cfg.installRoot)
    $modelsDir = Expand-SettingPath ([string]$cfg.modelsDir)
    if (-not $modelsDir) { $modelsDir = Join-Path $cfg.installRoot 'models' }
    Set-ConfigValue $cfg 'modelsDir' $modelsDir
    $cfg | Add-Member -NotePropertyName binDir -NotePropertyValue (Join-Path $cfg.installRoot $cfg.build)
    $cfg | Add-Member -NotePropertyName exe -NotePropertyValue (Join-Path $cfg.installRoot "$($cfg.build)\llama-server.exe")
    $cfg | Add-Member -NotePropertyName runDir -NotePropertyValue (Join-Path $cfg.installRoot 'run')
    $cfg | Add-Member -NotePropertyName logFile -NotePropertyValue (Join-Path $cfg.installRoot 'logs\server.log')
    # the key clients must send; outside the repository because it is a secret
    $cfg | Add-Member -NotePropertyName apiKeyFile -NotePropertyValue (Join-Path $cfg.installRoot 'run\api-key.txt')
    $cfg | Add-Member -NotePropertyName baseUrl -NotePropertyValue "http://$($cfg.host):$($cfg.port)"
    return $cfg
}

function Get-AgentConfig {
    return (Read-Config 'agent')
}

function Get-ProjectsRoot {
    # Where New-Project.ps1 creates projects; the guard protects this folder as a whole.
    return (Expand-SettingPath ([string](Read-Config 'projects').projectsRoot))
}

function Get-BenchmarkConfig {
    # config\benchmark.json; an empty workDir means <installRoot>\bench-work.
    $cfg = Read-Config 'benchmark'
    $work = Expand-SettingPath ([string]$cfg.workDir)
    if (-not $work) { $work = Join-Path (Get-ServerConfig).installRoot 'bench-work' }
    Set-ConfigValue $cfg 'workDir' $work
    return $cfg
}

function Publish-ConfigEnvironment {
    # The hooks in scripts\hooks\ run as processes of their own (started by Claude Code)
    # and do not load these files; the folders they protect reach them through the
    # environment, and config\guard.json refers to them as %CLAUDE_LOCAL_ROOT% and
    # %CLAUDE_LOCAL_PROJECTS%.
    $env:CLAUDE_LOCAL_ROOT = (Get-ServerConfig).installRoot
    $env:CLAUDE_LOCAL_PROJECTS = Get-ProjectsRoot
}

# --- model profiles ------------------------------------------------------------------

function Get-ModelsConfig {
    # config\models.json. From config\machine.json, "modelDefaults" is laid over "defaults"
    # and "models".<profile> over that profile (another "file", more or other "args"); a
    # profile that exists only in machine.json is added.
    $cfg = Read-JsonFile (Join-Path $script:ConfigDir 'models.json')
    $machine = Get-MachineConfig
    if ($machine.PSObject.Properties['modelDefaults']) { $cfg.defaults = Merge-ConfigObject $cfg.defaults $machine.modelDefaults }
    if ($machine.PSObject.Properties['models']) {
        foreach ($p in $machine.models.PSObject.Properties) {
            $entry = $cfg.models.PSObject.Properties[$p.Name]
            if ($entry) { $entry.Value = Merge-ConfigObject $entry.Value $p.Value }
            elseif (Test-JsonObject $p.Value) { $cfg.models | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
        }
    }
    return $cfg
}

function Get-ModelNames {
    return @((Get-ModelsConfig).models.PSObject.Properties | ForEach-Object { $_.Name })
}

function Resolve-ModelName([string]$NameOrAlias) {
    # Maps a short name from config\agent.json ("schnell") to a profile name ("local-fast").
    $agent = Get-AgentConfig
    if ($agent.aliases -and $agent.aliases.PSObject.Properties[$NameOrAlias]) {
        return [string]$agent.aliases.PSObject.Properties[$NameOrAlias].Value
    }
    return $NameOrAlias
}

function Get-ModelProfile([string]$Name) {
    # Returns one profile from config\models.json with defaults merged in:
    #   name, description, role, path (full path of the GGUF file), args (ordered hashtable),
    #   download (where the files come from, see Get-Model.ps1)
    # File names in args are turned into full paths. An arg set to null in a profile
    # removes the default of the same name.
    $cfg = Get-ModelsConfig
    $entry = $cfg.models.PSObject.Properties[$Name]
    if (-not $entry) { throw "Model profile '$Name' is not defined in config\models.json. Known: $((Get-ModelNames) -join ', ')" }
    $model = $entry.Value
    $modelsDir = (Get-ServerConfig).modelsDir

    $modelArgs = [ordered]@{}
    foreach ($source in @($cfg.defaults, $model.args)) {
        if (-not $source) { continue }
        foreach ($p in $source.PSObject.Properties) {
            if ($null -eq $p.Value) { $modelArgs.Remove($p.Name) } else { $modelArgs[$p.Name] = $p.Value }
        }
    }
    # paths of chat templates are written relative to config\
    if ($modelArgs.Contains('chat-template-file')) {
        $modelArgs['chat-template-file'] = Join-Path $script:ConfigDir ([string]$modelArgs['chat-template-file'])
    }
    # the image encoder (mmproj) lies next to the model file
    if ($modelArgs.Contains('mmproj')) {
        $modelArgs['mmproj'] = Join-Path $modelsDir ([string]$modelArgs['mmproj'])
    }

    return [pscustomobject]@{
        name        = $Name
        description = [string]$model.description
        role        = [string]$model.role
        file        = [string]$model.file
        path        = Join-Path $modelsDir ([string]$model.file)
        args        = $modelArgs
        download    = $model.download
    }
}

function Test-ModelInstalled([string]$Name) {
    # True if the model file of a profile is in the models folder.
    try { return (Test-Path (Get-ModelProfile $Name).path) } catch { return $false }
}

function Get-InstalledModelNames {
    return @(Get-ModelNames | Where-Object { Test-ModelInstalled $_ })
}

function Get-ModelContextSize([string]$Name) {
    # Context window of a profile in tokens, 0 if the profile does not set one.
    $modelArgs = (Get-ModelProfile $Name).args
    if ($modelArgs.Contains('ctx-size')) { return [int]$modelArgs['ctx-size'] }
    return 0
}

function Resolve-StartModel([string]$Requested) {
    # The model a session starts with: the requested short name or profile, else the default
    # of config\agent.json. Returns @{ model; problem }; problem says why it cannot start.
    if ($Requested) {
        $name = Resolve-ModelName $Requested
        try { $null = Get-ModelProfile $name } catch { return @{ model = ''; problem = $_.Exception.Message } }
        if (-not (Test-ModelInstalled $name)) {
            return @{ model = ''; problem = "the model '$name' is not installed. Download it with: powershell -ExecutionPolicy Bypass -File `"$(Join-Path $script:ProjectRoot 'scripts\Get-Model.ps1')`" -Model $name" }
        }
        return @{ model = $name; problem = '' }
    }
    $name = Get-DefaultAgentModel
    if (-not $name) { return @{ model = ''; problem = "no model is installed yet. Run the installer: $(Join-Path $script:ProjectRoot 'Install.cmd')" } }
    return @{ model = $name; problem = '' }
}

function Get-DefaultAgentModel {
    # The model claude-local starts with: "model" in config\agent.json if it is installed,
    # otherwise the first installed model of the picker, otherwise ''.
    $agent = Get-AgentConfig
    $wanted = Resolve-ModelName ([string]$agent.model)
    if (Test-ModelInstalled $wanted) { return $wanted }
    foreach ($row in @($agent.picker)) {
        if ($row -and (Test-ModelInstalled ([string]$row.model))) { return [string]$row.model }
    }
    return ''
}
