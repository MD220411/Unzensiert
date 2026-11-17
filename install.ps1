# One-line installer for Unzensiert. In a PowerShell window:
#
#   irm https://raw.githubusercontent.com/MD220411/Unzensiert/main/install.ps1 | iex
#
# Puts the program files of the newest release (or of the main branch while there is no
# release) into %LOCALAPPDATA%\Programs\claude-local - with git if it is installed,
# otherwise as a ZIP from GitHub - and starts the installer there, scripts\Install.ps1.
# Running the line again first brings the program files to the newest release, so it is
# also the way to update by hand; unzensiert itself does it automatically unless that is
# switched off (config\updates.json). Started as a file from a copy that is already on the
# disk, it runs that copy's installer directly.
#
# This file runs before there is a config\ folder, so the address of the repository is
# written here. It is pasted into the user's own PowerShell session: everything happens in
# a script block, without exit, so the window and its variables stay as they were.
# Keep this file ASCII-only.

& {
    param([string]$Here)
    $ErrorActionPreference = 'Stop'
    $repository = 'https://github.com/MD220411/Unzensiert'
    $latestRelease = 'https://api.github.com/repos/MD220411/Unzensiert/releases/latest'
    $app = Join-Path $env:LOCALAPPDATA 'Programs\claude-local'

    if ($Here -and (Test-Path (Join-Path $Here 'scripts\Install.ps1'))) {
        $app = $Here
    } else {
        # the newest release; without one, or without an answer from GitHub, the main branch
        $ref = 'main'
        $kind = 'heads'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod -Uri $latestRelease -TimeoutSec 15 -UseBasicParsing -Headers @{ 'User-Agent' = 'unzensiert-installer' }
            if ($release.tag_name -and -not $release.draft -and -not $release.prerelease) { $ref = [string]$release.tag_name; $kind = 'tags' }
        } catch {}
        Write-Host "Unzensiert: program files ($ref) go to $app" -ForegroundColor Cyan
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($git -and (Test-Path (Join-Path $app '.git'))) {
            # an earlier install with git: update it, unless files in it were changed by hand
            $changed = @(& git -C $app status --porcelain --untracked-files=no)
            if ($changed.Count -gt 0) {
                Write-Host "Files in $app were changed by hand; they are not updated." -ForegroundColor Yellow
            } elseif ($kind -eq 'tags') {
                & git -C $app fetch --quiet --depth 1 --no-tags origin tag $ref
                if ($LASTEXITCODE -ne 0) { throw "Fetching $ref with git failed." }
                & git -C $app checkout --quiet --detach "refs/tags/$ref"
                if ($LASTEXITCODE -ne 0) { throw "Switching $app to $ref failed." }
            } else {
                & git -C $app pull --ff-only --quiet
                if ($LASTEXITCODE -ne 0) { throw "Updating $app with git failed." }
            }
        } elseif ($git -and -not (Test-Path $app)) {
            & git clone --quiet --depth 1 --branch $ref "$repository.git" $app
            if ($LASTEXITCODE -ne 0) { throw "Downloading $repository with git failed." }
        } else {
            # without git, or over an install that came as a ZIP: the ZIP is laid over the
            # folder; config\machine.json is not part of it and stays
            $zip = Join-Path $env:TEMP "unzensiert-$PID.zip"
            $unpacked = Join-Path $env:TEMP "unzensiert-$PID"
            & curl.exe -sSL --fail -o $zip "$repository/archive/refs/$kind/$ref.zip"
            if ($LASTEXITCODE -ne 0) { throw "Downloading $repository failed." }
            Expand-Archive -Path $zip -DestinationPath $unpacked -Force
            $top = Get-ChildItem -Path $unpacked -Directory | Select-Object -First 1
            New-Item -ItemType Directory -Force -Path $app | Out-Null
            Copy-Item -Path (Join-Path $top.FullName '*') -Destination $app -Recurse -Force
            Remove-Item -Recurse -Force -Path $zip, $unpacked
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'scripts\Install.ps1')
} $PSScriptRoot
