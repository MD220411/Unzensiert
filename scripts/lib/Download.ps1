# Downloads that can be resumed and are checked before use: the llama.cpp archives, the model
# files and the font. A file is downloaded as <name>.part and only renamed to its real name after
# size and SHA-256 match, so a file under its real name is always complete. Every download goes
# over https only, also where a server sends it on (docs\security.md).
# Needs lib\Config.ps1 and lib\Git.ps1 (Get-SystemProgram). Keep this file ASCII-only.

# curl may follow a server only to https
$script:CurlHttpsOnly = @('--proto', '=https', '--proto-redir', '=https')

function Test-FileDigest([string]$Path, [long]$Size, [string]$Sha256) {
    # Whether the file has this size and SHA-256 (hex, any case).
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ($Size -gt 0 -and (Get-Item -LiteralPath $Path).Length -ne $Size) { return $false }
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Sha256.ToUpperInvariant())
}

function Save-HttpsFile([string]$Url, [string]$Target, [long]$MaxBytes = 0) {
    # Downloads $Url to $Target without output, over https only; throws when it fails. For
    # small files whose content is checked afterwards (the signature of a release, a release).
    $a = @('-sSL', '--fail') + $script:CurlHttpsOnly + @('--connect-timeout', '30', '-o', $Target)
    if ($MaxBytes -gt 0) { $a += @('--max-filesize', [string]$MaxBytes) }
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = & (Get-SystemProgram 'curl') @a $Url 2>&1 }
    finally { $ErrorActionPreference = $saved }
    if ($LASTEXITCODE -ne 0) { throw "the download of $Url failed (curl exit code $LASTEXITCODE)" }
}

function Save-VerifiedDownload([string]$Url, [string]$Target, [long]$Size, [string]$Sha256) {
    # Downloads $Url to $Target. An interrupted download goes on where it stopped (the
    # .part file stays). Throws if the file does not match $Size or $Sha256; without a SHA-256
    # nothing is downloaded.
    if ($Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "No SHA-256 for $Url in config\: nothing is downloaded without one." }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    $part = "$Target.part"
    if ($Size -gt 0 -and (Test-Path $part) -and (Get-Item $part).Length -gt $Size) { Remove-Item -Force $part }

    # curl.exe ships with Windows, resumes (-C -) and is much faster than Invoke-WebRequest.
    # The progress bar only makes sense for a person watching.
    $show = '--progress-bar'
    if ([Console]::IsErrorRedirected) { $show = '-sS' }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if ($Size -gt 0 -and (Test-Path $part) -and (Get-Item $part).Length -eq $Size) { break }
        & (Get-SystemProgram 'curl') -L --fail $show $script:CurlHttpsOnly -C - --retry 3 --retry-delay 5 --connect-timeout 30 -o $part $Url
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -eq 5) { throw "Download failed (curl exit code $LASTEXITCODE): $Url" }
        "  connection lost, trying again ($attempt of 4) ..."
        Start-Sleep -Seconds (5 * $attempt)
    }

    $have = (Get-Item $part).Length
    if ($Size -gt 0 -and $have -ne $Size) { throw "Download of $Url has $have bytes instead of $Size." }
    "  checking $(Split-Path -Leaf $Target) ($([math]::Round($have / 1GB, 1)) GB) ..."
    if (-not (Test-FileDigest $part 0 $Sha256)) {
        Remove-Item -Force $part
        throw "Checksum of $(Split-Path -Leaf $Target) does not match. The damaged file was deleted; run the installer again."
    }
    Move-Item -Force -Path $part -Destination $Target
}

# --- model files ---------------------------------------------------------------------------

function Get-ModelFiles([string]$Name) {
    # The files a profile needs, from its "download" entry in config\models.json:
    #   name (file in the models folder), path (full path), url, size, sha256
    # A "download" that is just a profile name means: the same files as that profile.
    $model = Get-ModelProfile $Name
    $download = $model.download
    $seen = @($Name)
    while ($download -is [string]) {
        if ($seen -contains $download) { throw "Profile '$Name': the download entries refer to each other in a circle." }
        $seen += $download
        $download = (Get-ModelProfile $download).download
    }
    if (-not $download) { return @() }
    $modelsDir = (Get-ServerConfig).modelsDir
    return @($download.files | ForEach-Object {
            [pscustomobject]@{
                name   = [string]$_.name
                path   = Join-Path $modelsDir ([string]$_.name)
                url    = "https://huggingface.co/$($download.repo)/resolve/$($download.revision)/$($_.source)"
                size   = [long]$_.size
                sha256 = [string]$_.sha256
            }
        })
}

function Test-ModelFilePresent($File) {
    # A file counts as present if it has the expected size. Files under their real name
    # were checked when they were downloaded (Save-VerifiedDownload); Get-Model.ps1 -Verify
    # checks them again.
    return ((Test-Path $File.path) -and (Get-Item $File.path).Length -eq $File.size)
}
