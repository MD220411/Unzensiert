# Downloads and unpacks the llama.cpp build named in config\server.json ("build", "package").
# The files go to <installRoot>\<build>\, so several builds can sit side by side and an
# update is: change "build" in config\server.json, run this script, run Restart-Server.ps1.
# Idempotent: an installed build is left alone unless -Force is given.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Install-LlamaCpp.ps1
#   ... -Force     download and unpack again
#
# Downloads come from the GitHub releases of ggml-org/llama.cpp and are checked against
# the SHA-256 digests that GitHub publishes for them.

param([switch]$Force)

. "$PSScriptRoot\_common.ps1"

$server = Get-ServerConfig
if ((Test-Path $server.exe) -and -not $Force) {
    "llama.cpp $($server.build) is already installed in $($server.binDir)"
    exit 0
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$($server.build)" -Headers @{ 'User-Agent' = 'llama-cpp-installer' } -TimeoutSec 60

# two archives: the programs, and the CUDA runtime libraries they need
$cudaPart = $server.package -replace '^win-', ''          # win-cuda-13.5-x64 -> cuda-13.5-x64
$wanted = @("llama-$($server.build)-bin-$($server.package).zip")
if ($server.package -like '*cuda*') { $wanted += "cudart-llama-bin-win-$cudaPart.zip" }

$downloadDir = Join-Path $server.installRoot 'downloads'
New-Item -ItemType Directory -Force -Path $downloadDir, $server.binDir | Out-Null

foreach ($name in $wanted) {
    $asset = $release.assets | Where-Object { $_.name -eq $name }
    if (-not $asset) { throw "Release $($server.build) has no file '$name'. Check 'package' in config\server.json." }
    $zip = Join-Path $downloadDir $name
    $expected = ([string]$asset.digest) -replace '^sha256:', ''

    $haveGoodFile = $false
    if (Test-Path $zip) { $haveGoodFile = ((Get-FileHash -Path $zip -Algorithm SHA256).Hash -eq $expected) }
    if (-not $haveGoodFile) {
        "downloading $name ($([math]::Round($asset.size / 1MB)) MB) ..."
        # curl.exe ships with Windows and is much faster than Invoke-WebRequest
        & curl.exe -sSL --fail -o $zip $asset.browser_download_url
        if ($LASTEXITCODE -ne 0) { throw "Download of $name failed." }
        if ((Get-FileHash -Path $zip -Algorithm SHA256).Hash -ne $expected) { throw "Checksum of $name does not match the one published by GitHub." }
    }
    "unpacking $name"
    Expand-Archive -Path $zip -DestinationPath $server.binDir -Force
}

if (-not (Test-Path $server.exe)) { throw "Unpacking finished, but $($server.exe) is missing." }
& $server.exe --version
"Installed in $($server.binDir). GPUs seen by llama.cpp:"
& $server.exe --list-devices
