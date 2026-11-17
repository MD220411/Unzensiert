# Downloads and unpacks the llama.cpp build named in config\server.json ("build"), in the
# package that fits this machine. "package": "auto" picks it by graphics card ("packages"
# in config\server.json): with an NVIDIA card the CUDA package, and if llama.cpp then sees
# no card (driver too old), the older CUDA package; AMD and Intel get Vulkan. The package
# that works is noted in config\machine.json. The files go to <installRoot>\<build>\, so an
# update is: change "build", run this script, run Restart-Server.ps1.
# Idempotent: an installed build is left alone unless -Force is given.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Install-LlamaCpp.ps1
#   ... -Force                       download and unpack again
#   ... -Package win-vulkan-x64      this package instead of the automatic choice
#
# Downloads come from the GitHub releases of ggml-org/llama.cpp and are checked against
# the SHA-256 digests that GitHub publishes for them.

param([switch]$Force, [string]$Package)

. "$PSScriptRoot\_common.ps1"

$server = Get-ServerConfig
$marker = Join-Path $server.binDir 'package.txt'

function Get-InstalledPackage {
    # The package in binDir: from package.txt, or for an install made before that file
    # existed, the package this machine names in config\machine.json.
    if (Test-Path $marker) { return ([System.IO.File]::ReadAllText($marker)).Trim() }
    if ((Test-Path $server.exe) -and [string]$server.package -ne 'auto') { return [string]$server.package }
    return ''
}

function Install-Package([string]$Name, $Release) {
    # Unpacks one package (and for CUDA its runtime libraries) into an empty binDir: files
    # of another package left behind would load a second backend for the same card.
    $wanted = @("llama-$($server.build)-bin-$Name.zip")
    if ($Name -like '*cuda*') { $wanted += "cudart-llama-bin-$Name.zip" }
    # binDir is <installRoot>\<build>; without a build name it would be the install folder
    # itself, with the models in it
    if ([string]$server.build -notmatch '^b\d+$') { throw "config\server.json: 'build' must look like b12433, not '$($server.build)'." }
    if (Test-Path $server.binDir) { Remove-Item -Recurse -Force -Path $server.binDir }
    New-Item -ItemType Directory -Force -Path $server.binDir | Out-Null
    foreach ($file in $wanted) {
        $asset = $Release.assets | Where-Object { $_.name -eq $file }
        if (-not $asset) { throw "Release $($server.build) has no file '$file'. Check 'packages' in config\server.json." }
        $zip = Join-Path (Join-Path $server.installRoot 'downloads') $file
        $sha = ([string]$asset.digest) -replace '^sha256:', ''
        $done = (Test-Path $zip) -and ((Get-FileHash -Path $zip -Algorithm SHA256).Hash -eq $sha.ToUpper())
        if (-not $done) {
            "downloading $file ($([math]::Round($asset.size / 1MB)) MB) ..."
            Save-VerifiedDownload $asset.browser_download_url $zip ([long]$asset.size) $sha
        }
        "unpacking $file"
        Expand-Archive -Path $zip -DestinationPath $server.binDir -Force
    }
    if (-not (Test-Path $server.exe)) { throw "Unpacking finished, but $($server.exe) is missing." }
    [System.IO.File]::WriteAllText($marker, $Name)
}

# which packages come into question, best first
if ($Package) { $candidates = @($Package) }
elseif ([string]$server.package -ne 'auto') { $candidates = @([string]$server.package) }
else { $candidates = @(Get-LlamaPackageCandidates) }

$installed = Get-InstalledPackage
if (-not $Force -and (Test-Path $server.exe) -and $installed -and $candidates -contains $installed) {
    if (-not (Test-Path $marker)) { [System.IO.File]::WriteAllText($marker, $installed) }
    if ([string]$server.package -ne $installed) { Set-MachineValue 'server' 'package' $installed }
    "llama.cpp $($server.build) ($installed) is already installed in $($server.binDir)"
    exit 0
}

# a running server holds its files open; it is started again on the next use
if (Get-ServerProcess) { 'stopping llama-server for the update ...'; Stop-Server }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$($server.build)" -Headers @{ 'User-Agent' = 'llama-cpp-installer' } -TimeoutSec 60

foreach ($name in $candidates) {
    "llama.cpp $($server.build), package $name"
    Install-Package $name $release
    $devices = @(Get-LlamaDevices $server.exe)
    if ($name -like '*cpu*' -or $devices.Count -gt 0) {
        Set-MachineValue 'server' 'package' $name
        & $server.exe --version
        "Installed in $($server.binDir). Graphics cards llama.cpp can use:"
        if ($devices.Count -eq 0) { '  none (runs on the processor only)' }
        foreach ($d in $devices) { "  $($d.id): $($d.name), $($d.memoryMiB) MiB" }
        exit 0
    }
    "llama.cpp with package $name sees no graphics card."
}
throw "No llama.cpp package could use the graphics card. Update the graphics driver (NVIDIA: https://www.nvidia.com/drivers) and run the installer again."
