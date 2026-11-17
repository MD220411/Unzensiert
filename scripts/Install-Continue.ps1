# Sets up the VS Code extension "Continue" for local chat and tab autocomplete.
#
#   1. installs the extension through the "code" command line (if missing)
#   2. copies config\continue.config.yaml to %USERPROFILE%\.continue\config.yaml,
#      backing up an existing, different file as config.yaml.bak-<timestamp>, and fills
#      in the key of the server (run again after the key file was deleted or replaced)
#   3. checks that every model named in the file is a profile in config\models.json
#
#   powershell -ExecutionPolicy Bypass -File scripts\Install-Continue.ps1

. "$PSScriptRoot\_common.ps1"

$source = Join-Path $script:ProjectRoot 'config\continue.config.yaml'
$targetDir = Join-Path $env:USERPROFILE '.continue'
$target = Join-Path $targetDir 'config.yaml'
$extensionId = 'continue.continue'

# 1. extension
$code = Get-Command code -ErrorAction SilentlyContinue
if (-not $code) { throw 'The "code" command was not found. Install VS Code or add it to PATH.' }
$installed = @(& cmd /c "code --list-extensions 2>nul") | ForEach-Object { $_.Trim().ToLower() }
if ($installed -contains $extensionId) {
    "extension: $extensionId already installed"
} else {
    & cmd /c "code --install-extension $extensionId >nul 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "Installing $extensionId failed." }
    "extension: $extensionId installed"
}

# 2. configuration
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
$new = Get-Content -Raw -Path $source
# the server's key is a secret and therefore not in the repository file
$key = Get-ServerApiKey
if (-not $key) { $key = 'local' }
$new = $new.Replace('__LLAMA_API_KEY__', $key)
$write = $true
if (Test-Path $target) {
    $old = Get-Content -Raw -Path $target
    if ($old -eq $new) {
        "config: $target is up to date"
        $write = $false
    } else {
        $backup = "$target.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $target -Destination $backup
        "config: old file backed up to $backup"
    }
}
if ($write) {
    # UTF-8 without BOM: Continue's YAML parser does not need the BOM
    [System.IO.File]::WriteAllText($target, $new, (New-Object System.Text.UTF8Encoding($false)))
    "config: written to $target"
}

# 3. every model must be a profile of the llama.cpp server
$known = Get-ModelNames
foreach ($m in [regex]::Matches($new, '(?m)^\s+model:\s*(\S+)\s*$')) {
    $name = $m.Groups[1].Value
    if ($known -contains $name) { "model: $name is a profile in config\models.json" }
    else { Write-Warning "model '$name' is not a profile in config\models.json. Continue will get an error for it." }
}
'Done. Restart VS Code once so Continue picks up the configuration.'
'The llama.cpp server must be running for Continue: scripts\Start-Server.ps1'
