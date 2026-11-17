# Removes claude-local from this machine, asking before each part:
#   1. stops llama-server
#   2. takes the command claude-local off the PATH
#   3. removes the look "Nachtschicht", if it is installed (Install-Style.ps1 -Remove)
#   4. deletes what the installer put into the install folder: llama.cpp, the model files
#      named in config\models.json, run state, logs, downloads, benchmark work folder.
#      Other files in that folder stay, and so does the folder if anything is left in it.
#   5. deletes config\machine.json
# Claude Code, Git for Windows and the settings of the VS Code extension Continue stay:
# they are programs of their own; how to remove them is printed at the end. The program
# folder itself can be deleted by hand afterwards.
#
#   Uninstall.cmd (double-click)  or  powershell -ExecutionPolicy Bypass -File scripts\Uninstall.ps1
#   ... -Yes          no questions
#   ... -KeepModels   keep the model files (for a later install)

param([switch]$Yes, [switch]$KeepModels)

. "$PSScriptRoot\_common.ps1"

$script:AssumeYes = [bool]$Yes
$steps = 5
Assert-CanAsk
$server = Get-ServerConfig
$root = $server.installRoot
Write-Host 'claude-local uninstaller' -ForegroundColor Cyan

Write-Step 'llama-server' $steps
Stop-Server
Write-Note 'stopped'

Write-Step 'The command claude-local' $steps
$bin = Join-Path $script:ProjectRoot 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @($userPath -split ';' | Where-Object { $_ })
if ($parts -contains $bin) {
    [Environment]::SetEnvironmentVariable('Path', (($parts | Where-Object { $_ -ne $bin }) -join ';'), 'User')
    Write-Note "removed from the user PATH: $bin"
} else {
    Write-Note 'was not on the PATH'
}

Write-Step 'Look "Nachtschicht"' $steps
if (Test-StyleInstalled) {
    if ((Invoke-ProjectScript 'Install-Style.ps1' @('-Remove')) -ne 0) { Write-Warn 'could not be removed completely (see above)' }
} else {
    Write-Note 'not installed'
}

Write-Step "Install folder $root" $steps
# Only what the installer made: llama.cpp builds (folders bNNNNN with llama-server.exe), the
# files of the profiles, and the folders for state and logs. Never the whole folder blindly.
$targets = @()
foreach ($dir in @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^b\d+$' -and (Test-Path (Join-Path $_.FullName 'llama-server.exe')) })) { $targets += $dir.FullName }
foreach ($name in 'run', 'logs', 'downloads', 'bench-work') {
    $dir = Join-Path $root $name
    if (Test-Path $dir) { $targets += $dir }
}
$modelFiles = @()
if (-not $KeepModels) {
    foreach ($profileName in (Get-ModelNames)) {
        $prof = Get-ModelProfile $profileName
        $candidates = @($prof.path) + @(Get-ModelFiles $profileName | ForEach-Object { $_.path })
        if ($prof.args.Contains('mmproj')) { $candidates += [string]$prof.args['mmproj'] }
        foreach ($c in $candidates) {
            foreach ($f in @($c, "$c.part")) { if ((Test-Path $f) -and $modelFiles -notcontains $f) { $modelFiles += $f } }
        }
    }
}
$bytes = [long]0
foreach ($t in $targets) { $bytes += [long]((Get-ChildItem -Recurse -File -Path $t -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) }
foreach ($f in $modelFiles) { $bytes += (Get-Item $f).Length }
if ($targets.Count -eq 0 -and $modelFiles.Count -eq 0) {
    Write-Note 'nothing of claude-local is in it'
} else {
    foreach ($t in $targets) { Write-Note "folder $t" }
    foreach ($f in $modelFiles) { Write-Note "file   $f" }
    if (Confirm-Step "Delete these ($([math]::Round($bytes / 1GB, 1)) GB)?") {
        foreach ($t in $targets) { Remove-Item -Recurse -Force -Path $t }
        foreach ($f in $modelFiles) { Remove-Item -Force -Path $f }
        # the models folder and the install folder only if nothing else is left in them
        foreach ($dir in @($server.modelsDir, $root)) {
            if ((Test-Path $dir) -and -not (Get-ChildItem -Force -Path $dir)) { Remove-Item -Force -Path $dir }
        }
        Write-Note 'deleted'
        if (Test-Path $root) { Write-Note "Other files are left in $root; they were not made by claude-local." }
    } else {
        Write-Note 'kept'
    }
}

Write-Step 'Settings of this machine' $steps
$machineFile = Get-MachineFile
if ((Test-Path $machineFile) -and (Confirm-Step "Delete $machineFile?")) { Remove-Item -Force -Path $machineFile; Write-Note 'deleted' }
else { Write-Note 'kept' }

Write-Host ''
Write-Host 'claude-local is removed.' -ForegroundColor Green
Write-Note "The program folder can now be deleted: $script:ProjectRoot"
Write-Note 'Claude Code stays installed. To remove it: https://code.claude.com/docs/en/setup#uninstall-claude-code'
Write-Note 'Git for Windows stays installed: Windows Settings > Apps.'
Write-Note 'Continue (VS Code), if you set it up: its settings are in %USERPROFILE%\.continue'
exit 0
