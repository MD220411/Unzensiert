# Puts a GGUF model file into the models folder (modelsDir in config\server.json) under a
# readable name. Afterwards add a profile for it to config\models.json.
#
#   From a downloaded file:
#     powershell -ExecutionPolicy Bypass -File scripts\Add-Model.ps1 -Path D:\dl\model.gguf -Name my-model-Q4_K_M.gguf
#   From a model that Ollama has already downloaded (no second download):
#     powershell -ExecutionPolicy Bypass -File scripts\Add-Model.ps1 -FromOllama qwen3-coder:30b -Name qwen3-coder-30b-Q4_K_M.gguf
#
# If source and models folder are on the same drive, the file is hard-linked: it shows up
# under both names but uses the disk space only once, and it stays when the other name is
# deleted (for example with "ollama rm"). Otherwise it is copied.

param(
    [string]$Path,
    [string]$FromOllama,
    [Parameter(Mandatory = $true)][string]$Name
)

. "$PSScriptRoot\_common.ps1"

function Get-OllamaModelBlob([string]$model) {
    # Finds the GGUF blob of an Ollama model through its manifest.
    $root = $env:OLLAMA_MODELS
    if (-not $root) { $root = Join-Path $env:USERPROFILE '.ollama\models' }
    $parts = $model.Split(':')
    $tag = 'latest'
    if ($parts.Count -gt 1) { $tag = $parts[1] }
    $repo = $parts[0]
    if ($repo -notmatch '/') { $repo = "library/$repo" }
    $manifest = Join-Path $root "manifests\registry.ollama.ai\$($repo -replace '/', '\')\$tag"
    if (-not (Test-Path $manifest)) {
        # Models created locally (ollama create) are stored differently. For those use -Path
        # with the blob named in the FROM line of: ollama show <model> --modelfile
        throw "No Ollama manifest for '$model' at $manifest. For a locally created model pass its blob with -Path (see 'ollama show $model --modelfile')."
    }
    $layer = (Read-JsonFile $manifest).layers | Where-Object { $_.mediaType -like '*ollama.image.model' } | Select-Object -First 1
    if (-not $layer) { throw "The manifest of '$model' names no model file." }
    return (Join-Path $root "blobs\$($layer.digest -replace ':', '-')")
}

if ($FromOllama) { $Path = Get-OllamaModelBlob $FromOllama }
if (-not $Path) { throw 'Give either -Path <file.gguf> or -FromOllama <model>.' }
if (-not (Test-Path $Path)) { throw "File not found: $Path" }
if ($Name -notlike '*.gguf') { $Name = "$Name.gguf" }

$stream = [System.IO.File]::OpenRead($Path)
try {
    $magic = New-Object byte[] 4
    $null = $stream.Read($magic, 0, 4)
} finally { $stream.Dispose() }
if ([System.Text.Encoding]::ASCII.GetString($magic) -ne 'GGUF') { throw "$Path is not a GGUF file." }

$modelsDir = (Get-ServerConfig).modelsDir
New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null
$target = Join-Path $modelsDir $Name
if (Test-Path $target) { "already there: $target"; exit 0 }

$sameDrive = ([System.IO.Path]::GetPathRoot((Resolve-Path $Path).Path) -eq [System.IO.Path]::GetPathRoot($modelsDir))
if ($sameDrive) {
    New-Item -ItemType HardLink -Path $target -Target (Resolve-Path $Path).Path | Out-Null
    "linked: $target  ->  $Path (no extra disk space)"
} else {
    "copying to $target ..."
    Copy-Item -Path $Path -Destination $target
    "copied: $target"
}
"Next: add a profile with `"file`": `"$Name`" to config\models.json, then run scripts\Restart-Server.ps1."
