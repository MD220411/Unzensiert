# Adds the project's bin\ folder to the USER PATH so `claude-local` works in every
# terminal. Idempotent. New terminals (and a restarted VS Code) pick the change up.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Install-Path.ps1

. "$PSScriptRoot\_common.ps1"

$bin = Join-Path $script:ProjectRoot 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ })
if ($parts -contains $bin) {
    "already on PATH: $bin"
} else {
    [Environment]::SetEnvironmentVariable('Path', (($parts + $bin) -join ';'), 'User')
    "added to user PATH: $bin"
}
