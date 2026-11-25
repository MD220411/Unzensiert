# One-line installer for Unzensiert. In a PowerShell window:
#
#   irm https://raw.githubusercontent.com/MD220411/Unzensiert/main/install.ps1 | iex
#
# Puts the program files of the newest release into %LOCALAPPDATA%\Programs\claude-local - with
# git if it is installed, otherwise as the ZIP of the release - and starts the installer there,
# scripts\Install.ps1. Only a release signed with a release key of Unzensiert is installed: its
# release.json names the commit, its tree and the SHA-256 of its ZIP, and its signature must
# verify with a key below (the same check as scripts\lib\Signature.ps1, docs\security.md).
# Without a release, or without an answer from GitHub, nothing is installed. Running the line
# again first brings the program files to the newest release, so it is also the way to update
# by hand; unzensiert itself does it automatically unless that is switched off
# (config\updates.json). Started as a file from a copy that is already on the disk, it runs that
# copy's installer directly.
#
# This file runs before there is a config\ folder, so the address of the repository and the
# release keys are written here. It is pasted into the user's own PowerShell session: everything
# happens in a script block, without exit, so the window and its variables stay as they were.
# Keep this file ASCII-only.

& {
    param([string]$Here)
    $ErrorActionPreference = 'Stop'
    $repositoryName = 'MD220411/Unzensiert'
    $repository = "https://github.com/$repositoryName"
    $latestRelease = "https://api.github.com/repos/$repositoryName/releases/latest"
    $app = Join-Path $env:LOCALAPPDATA 'Programs\claude-local'
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'

    # --- release keys: written by scripts\New-ReleaseKey.ps1 from config\release-keys.json ---
    $releaseKeys = @(
        @{ id = '271fc71b73012fb7'; modulus = '5RHCt/amDeoXq8UdpWnZH53rQ+64mk3vismreySjFGOW3e8QoEjnutt7HsmdbAmlxmwWydm0d0KWw/6UkMMJVWOQjMJmSx0MHjYLUC5z1vhGU2AT+hg/FyBECrbTi7N0eR0TtklMQ2zsR0fo4AOrvyMKNb15NMM1CKU8EC8CXzjKdqTNbPz4yFgh27ZQw0S3XnVPtJTw4r18cdSqMR1lRMhf3CXcpfBo7kzb8fiX7cHbsdooR5+QdqjZpG1SVuc6TAWx5MrobHcJ4TrETOVOm09+oYt5GqfrZaLYVX6EOinisDrkFc2uZHGAX6bIEwmfa3CmBuGHWsePOb5qPu6Uvf+SQV41XfNOVKYk0dZloX5H/PgzOXkGTZKWLsbe10lYSlVPXp5Jw8LPGdVqOfPnWBjPTvzApDy+8q3im25LnbppkgifDMpXdgPyVBusrtqY35Pxj7j+cujWr/zx/1NId/oBjrMMHN7Y6fhKp/CKdG9qHeHdsfy/TV9YW5e76sCV'; exponent = 'AQAB' }
    )
    # --- end of release keys ---

    function Confirm-UnzensiertRelease([byte[]]$Json, [string]$Signature, $Keys, [string]$Repository, [string]$Tag) {
        # The signed statement of a release: the RSA signature (SHA-256, PKCS#1 v1.5) over the
        # bytes of release.json must verify with one of $Keys, and the statement must name this
        # repository and this tag. Throws why not.
        $sig = $null
        try { $sig = [Convert]::FromBase64String($Signature.Trim()) } catch {}
        $signer = ''
        foreach ($k in @($Keys)) {
            if (-not $sig) { break }
            $rsa = New-Object System.Security.Cryptography.RSACng
            try {
                $p = New-Object System.Security.Cryptography.RSAParameters
                $p.Modulus = [Convert]::FromBase64String([string]$k.modulus)
                $p.Exponent = [Convert]::FromBase64String([string]$k.exponent)
                $rsa.ImportParameters($p)
                if ($rsa.VerifyData($Json, $sig, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) { $signer = [string]$k.id; break }
            } catch {
            } finally { $rsa.Dispose() }
        }
        if (-not $signer) { throw "The release $Tag is not signed with a release key of Unzensiert; it is not installed." }
        $s = [System.Text.Encoding]::UTF8.GetString($Json) | ConvertFrom-Json
        if ([string]$s.format -cne 'unzensiert-release 1' -or [string]$s.repository -ne $Repository -or [string]$s.tag -cne $Tag -or
            [string]$s.commit -cnotmatch '^[0-9a-f]{40}$' -or [string]$s.tree -cnotmatch '^[0-9a-f]{40}$' -or
            [string]$s.zip.name -notmatch '^[A-Za-z0-9._-]+\.zip$' -or [long]$s.zip.size -le 0 -or [string]$s.zip.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "The signed statement of $Tag does not fit this release; it is not installed."
        }
        return $s
    }

    function Save-UnzensiertFile([string]$Url, [string]$Target, [long]$MaxBytes) {
        # A download over https only, also where GitHub sends it on.
        & $curl -sSL --fail --proto =https --proto-redir =https --connect-timeout 30 --max-filesize $MaxBytes -o $Target $Url
        if ($LASTEXITCODE -ne 0) { throw "Downloading $Url failed." }
    }

    if ($Here -and (Test-Path (Join-Path $Here 'scripts\Install.ps1'))) {
        $app = $Here
    } else {
        # the newest release; never the unreleased work on the main branch
        $release = $null
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod -Uri $latestRelease -TimeoutSec 15 -UseBasicParsing -Headers @{ 'User-Agent' = 'unzensiert-installer' }
        } catch {}
        if (-not $release -or [string]$release.tag_name -notmatch '^v\d+\.\d+\.\d+$' -or $release.draft -or $release.prerelease) {
            throw "GitHub named no release of Unzensiert (or did not answer): $repository/releases. Nothing was installed; try again later."
        }
        $ref = [string]$release.tag_name
        $assets = @{}
        foreach ($a in @($release.assets)) {
            if ($a.name -and ([string]$a.browser_download_url) -match '^https://') { $assets[[string]$a.name] = [string]$a.browser_download_url }
        }
        if (-not $assets['release.json'] -or -not $assets['release.json.sig']) { throw "The release $ref is not signed; it is not installed." }
        $work = Join-Path $env:TEMP "unzensiert-$PID"
        if (Test-Path $work) { Remove-Item -Recurse -Force $work }
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        try {
            Save-UnzensiertFile $assets['release.json'] (Join-Path $work 'release.json') 65536
            Save-UnzensiertFile $assets['release.json.sig'] (Join-Path $work 'release.json.sig') 65536
            $signed = Confirm-UnzensiertRelease ([System.IO.File]::ReadAllBytes((Join-Path $work 'release.json'))) ([System.IO.File]::ReadAllText((Join-Path $work 'release.json.sig'))) $releaseKeys $repositoryName $ref
            Write-Host "Unzensiert: program files ($ref, signed) go to $app" -ForegroundColor Cyan
            $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($git -and ((Test-Path (Join-Path $app '.git')) -or -not (Test-Path $app))) {
                # git without programs of the repository
                $g = @('-c', 'core.fsmonitor=false', '-c', 'safe.bareRepository=explicit', '-C', $app)
                $fresh = -not (Test-Path $app)
                $update = $true
                if ($fresh) {
                    & $git.Source init --quiet $app
                    if ($LASTEXITCODE -ne 0) { throw "git could not make $app." }
                    & $git.Source @g remote add origin "$repository.git"
                } elseif (@(& $git.Source @g status --porcelain --untracked-files=no).Count -gt 0) {
                    Write-Host "Files in $app were changed by hand; they are not updated." -ForegroundColor Yellow
                    $update = $false
                }
                if ($update) {
                    & $git.Source @g fetch --quiet --depth 1 --no-tags origin tag $ref
                    $commit = ''
                    $tree = ''
                    if ($LASTEXITCODE -eq 0) {
                        $commit = [string](& $git.Source @g rev-parse --verify -q "refs/tags/$ref^{commit}")
                        $tree = [string](& $git.Source @g rev-parse --verify -q "$commit^{tree}")
                    }
                    if ($commit -cne [string]$signed.commit -or $tree -cne [string]$signed.tree) {
                        if ($fresh) { Remove-Item -Recurse -Force -Path $app }
                        throw "$ref on GitHub could not be fetched or is not the signed commit; nothing was installed."
                    }
                    & $git.Source @g checkout --quiet --detach ([string]$signed.commit)
                    if ($LASTEXITCODE -ne 0) { throw "Switching $app to $ref failed." }
                }
            } else {
                # without git, or over an install that came as a ZIP: the signed ZIP is laid over
                # the folder; config\machine.json is not part of it and stays
                $zipUrl = $assets[[string]$signed.zip.name]
                if (-not $zipUrl) { throw "The release $ref has no file $($signed.zip.name)." }
                $zip = Join-Path $work 'program.zip'
                Save-UnzensiertFile $zipUrl $zip ([long]$signed.zip.size + 1)
                if ((Get-Item $zip).Length -ne [long]$signed.zip.size -or (Get-FileHash -Path $zip -Algorithm SHA256).Hash -ne ([string]$signed.zip.sha256).ToUpperInvariant()) {
                    throw "The downloaded $($signed.zip.name) is not the signed file; nothing was installed."
                }
                $unpacked = Join-Path $work 'unpacked'
                Expand-Archive -Path $zip -DestinationPath $unpacked -Force
                $top = Get-ChildItem -Path $unpacked -Directory | Select-Object -First 1
                if (-not $top -or -not (Test-Path (Join-Path $top.FullName 'scripts\Install.ps1'))) { throw 'The downloaded release has an unexpected layout; nothing was installed.' }
                New-Item -ItemType Directory -Force -Path $app | Out-Null
                Copy-Item -Path (Join-Path $top.FullName '*') -Destination $app -Recurse -Force
            }
        } finally {
            Remove-Item -Recurse -Force -Path $work -ErrorAction SilentlyContinue
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'scripts\Install.ps1')
} $PSScriptRoot
