# Downloads the files of a model profile (the model and its image encoder) from Hugging
# Face into the models folder, as named under "download" in config\models.json: pinned
# revision, resumable, checked by size and SHA-256. Files that are already there are
# skipped, so the script can run again after an interruption.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Get-Model.ps1 -List
#   powershell -ExecutionPolicy Bypass -File scripts\Get-Model.ps1 -Model local-fast
#   ... -Verify     also check the SHA-256 of files that are already there (about a minute
#                   per 20 GB); a file that does not match is reported, not deleted
#
# Afterwards: scripts\Restart-Server.ps1 if the server is running, so it knows the model.

param([string]$Model, [switch]$Verify, [switch]$List)

. "$PSScriptRoot\_common.ps1"

if ($List -or -not $Model) {
    # every profile with its download size and whether it is on this machine
    foreach ($name in (Get-ModelNames)) {
        $files = @(Get-ModelFiles $name)
        $gb = [math]::Round((($files | Measure-Object -Property size -Sum).Sum) / 1GB, 1)
        $state = 'not installed'
        if (Test-ModelInstalled $name) { $state = 'installed' }
        '{0,-26} {1,-13} {2,6} GB   {3}' -f $name, (Get-ModelProfile $name).role, $gb, $state
    }
    if (-not $Model) { ''; 'Download one with: Get-Model.ps1 -Model <name>' }
    exit 0
}

$Model = Resolve-ModelName $Model
$prof = Get-ModelProfile $Model
$files = @(Get-ModelFiles $Model)
if ($files.Count -eq 0) { throw "Profile '$Model' has no download entry in config\models.json." }
if (@($files | ForEach-Object { $_.name }) -notcontains $prof.file -and (Test-Path $prof.path)) {
    # config\machine.json gives this profile a file of this machine's own
    "Profile $Model uses the file $($prof.file) of this machine (config\machine.json), nothing to download."
    exit 0
}

$missing = @($files | Where-Object { -not (Test-ModelFilePresent $_) })
$bytes = [long](($missing | Measure-Object -Property size -Sum).Sum)
$modelsDir = (Get-ServerConfig).modelsDir
if ($bytes -gt 0) {
    $free = Get-FreeSpaceGiB $modelsDir
    $need = [math]::Round($bytes / 1GB + 1, 1)
    if ($free -lt $need) { throw "Not enough disk space in $modelsDir`: $need GB needed, $free GB free." }
    "Model $Model`: $([math]::Round($bytes / 1GB, 1)) GB to download into $modelsDir"
}

foreach ($file in $files) {
    if (Test-ModelFilePresent $file) {
        if (-not $Verify) { "  $($file.name): already there"; continue }
        "  $($file.name): checking ..."
        $hash = (Get-FileHash -Path $file.path -Algorithm SHA256).Hash
        if ($hash -eq $file.sha256.ToUpper()) { "  $($file.name): checksum OK" }
        else { Write-Warning "$($file.name) does not match its checksum. Delete it and run this script again." }
        continue
    }
    if (Test-Path $file.path) {
        throw "$($file.path) exists but has the wrong size. It was not made by this script; move it away and run again."
    }
    "  $($file.name) ($([math]::Round($file.size / 1GB, 1)) GB) ..."
    Save-VerifiedDownload $file.url $file.path $file.size $file.sha256
    "  $($file.name): done"
}
"Model $Model is ready."
