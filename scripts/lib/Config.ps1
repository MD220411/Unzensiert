# Reads the files in config\. Every script gets its settings through these functions,
# so no script contains paths, ports or model names of its own.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.

$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ConfigDir = Join-Path $script:ProjectRoot 'config'

function Read-JsonFile([string]$Path) {
    return (Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ServerConfig {
    # config\server.json plus the paths derived from it.
    $cfg = Read-JsonFile (Join-Path $script:ConfigDir 'server.json')
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
    return (Read-JsonFile (Join-Path $script:ConfigDir 'agent.json'))
}

function Get-ModelsConfig {
    return (Read-JsonFile (Join-Path $script:ConfigDir 'models.json'))
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
    #   name, description, path (full path of the GGUF file), args (ordered hashtable)
    # File names in args are turned into full paths.
    $cfg = Get-ModelsConfig
    $entry = $cfg.models.PSObject.Properties[$Name]
    if (-not $entry) { throw "Model profile '$Name' is not defined in config\models.json. Known: $((Get-ModelNames) -join ', ')" }
    $model = $entry.Value

    $modelArgs = [ordered]@{}
    if ($cfg.defaults) { foreach ($p in $cfg.defaults.PSObject.Properties) { $modelArgs[$p.Name] = $p.Value } }
    if ($model.args) { foreach ($p in $model.args.PSObject.Properties) { $modelArgs[$p.Name] = $p.Value } }
    # paths of chat templates are written relative to config\
    if ($modelArgs.Contains('chat-template-file')) {
        $modelArgs['chat-template-file'] = Join-Path $script:ConfigDir ([string]$modelArgs['chat-template-file'])
    }
    # the image encoder (mmproj) lies next to the model file
    if ($modelArgs.Contains('mmproj')) {
        $modelArgs['mmproj'] = Join-Path (Get-ServerConfig).modelsDir ([string]$modelArgs['mmproj'])
    }

    return [pscustomobject]@{
        name        = $Name
        description = [string]$model.description
        path        = Join-Path (Get-ServerConfig).modelsDir ([string]$model.file)
        args        = $modelArgs
    }
}

function Get-ModelContextSize([string]$Name) {
    # Context window of a profile in tokens, 0 if the profile does not set one.
    $modelArgs = (Get-ModelProfile $Name).args
    if ($modelArgs.Contains('ctx-size')) { return [int]$modelArgs['ctx-size'] }
    return 0
}
