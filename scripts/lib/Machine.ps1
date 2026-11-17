# This machine: graphics cards, memory, disk space, the programs claude-local needs, and
# which setup (model, context size) fits the graphics memory (config\setups.json).
# Used by the installer and by claude-local. Needs lib\Config.ps1. Keep this file ASCII-only.

# --- graphics cards ----------------------------------------------------------------------

function Get-NvidiaGpus {
    # NVIDIA cards as nvidia-smi reports them: name, memoryMiB, driver. Empty without
    # nvidia-smi (it comes with the NVIDIA driver).
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return @() }
    $rows = @(& nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>$null)
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($rows | Where-Object { $_ -match ',' } | ForEach-Object {
            $f = $_ -split ',\s*'
            [pscustomobject]@{ name = $f[0].Trim(); memoryMiB = [int]$f[1]; driver = $f[2].Trim() }
        })
}

function Get-DisplayAdapters {
    # Names of the display adapters Windows knows (also integrated graphics).
    return @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Name })
}

function Get-GpuVendors {
    # Makers of the display adapters Windows knows: nvidia, amd, intel.
    $names = @(Get-DisplayAdapters)
    $vendors = @()
    if ($names -match 'NVIDIA') { $vendors += 'nvidia' }
    if ($names -match 'AMD|Radeon') { $vendors += 'amd' }
    if ($names -match 'Intel') { $vendors += 'intel' }
    return $vendors
}

function Get-LlamaPackageCandidates {
    # llama.cpp packages to try on this machine, best first ("packages" in config\server.json).
    $packages = (Get-ServerConfig).packages
    $vendors = @(Get-GpuVendors)
    if ($vendors -contains 'nvidia') { return @([string]$packages.nvidia, [string]$packages.nvidiaFallback, [string]$packages.other) }
    if ($vendors -contains 'amd' -or $vendors -contains 'intel') { return @([string]$packages.other) }
    return @([string]$packages.cpu)
}

function ConvertFrom-DeviceList([string[]]$Lines) {
    # Reads the output of "llama-server --list-devices", lines such as
    #   CUDA0: NVIDIA GeForce RTX 5070 Ti (16275 MiB, 12196 MiB free)
    $devices = @()
    foreach ($line in $Lines) {
        if ($line -match '^\s*([A-Za-z]+\d+):\s*(.+?)\s*\((\d+)\s*MiB,\s*(\d+)\s*MiB free\)') {
            $devices += [pscustomobject]@{ id = $Matches[1]; name = $Matches[2].Trim(); memoryMiB = [int]$Matches[3]; freeMiB = [int]$Matches[4] }
        }
    }
    return $devices
}

function Get-LlamaDevices([string]$Exe) {
    # The graphics cards llama.cpp itself can use. Empty if llama.cpp is not installed or
    # sees no card.
    if (-not $Exe) { $Exe = (Get-ServerConfig).exe }
    if (-not (Test-Path $Exe)) { return @() }
    $lines = @(& cmd /c "`"$Exe`" --list-devices 2>&1")
    return @(ConvertFrom-DeviceList $lines)
}

function Get-UsableDevices($Devices) {
    # Leaves out integrated graphics ("ignoreDevices" in config\setups.json): it shares the
    # main memory and would make the graphics memory look larger than it is.
    $pattern = [string](Read-JsonFile (Join-Path $script:ConfigDir 'setups.json')).ignoreDevices
    # "$null | Where-Object" would let one empty entry through
    return @(@($Devices) | Where-Object { $_ -and (-not $pattern -or $_.name -notmatch $pattern) })
}

# --- memory and disks ---------------------------------------------------------------------

function Get-SystemMemoryGiB {
    return [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
}

function Get-FreeSpaceGiB([string]$Path) {
    # Free space on the drive that holds $Path (the folder need not exist yet).
    $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    return [math]::Round((New-Object System.IO.DriveInfo($root)).AvailableFreeSpace / 1GB, 1)
}

function Get-RoomiestDrive {
    # Root of the local fixed drive with the most free space, e.g. "E:\".
    $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })
    return [string]($drives | Sort-Object AvailableFreeSpace -Descending | Select-Object -First 1).RootDirectory.FullName
}

# --- programs ------------------------------------------------------------------------------

function Find-GitBash {
    # Path of Git Bash (bash.exe of Git for Windows), '' if missing. Claude Code needs it for
    # its Bash tool; without it the agent works with the PowerShell tool instead.
    if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path $env:CLAUDE_CODE_GIT_BASH_PATH)) { return $env:CLAUDE_CODE_GIT_BASH_PATH }
    $candidates = @()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $candidates += (Join-Path (Split-Path -Parent (Split-Path -Parent $git.Source)) 'bin\bash.exe') }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe') }
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return ''
}

function Start-ChildProcess([System.Diagnostics.ProcessStartInfo]$Psi) {
    # Process.Start with a redirected stdin writes the byte order mark of the console input
    # encoding into that pipe at once; on a UTF-8 console the child reads three stray
    # characters before its input (a hook then fails to read its JSON). The process is
    # started with a UTF-8 encoding without that mark instead.
    $saved = $null
    try {
        if ($Psi.RedirectStandardInput -and [Console]::InputEncoding.GetPreamble().Length -gt 0) {
            $saved = [Console]::InputEncoding
            [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
        }
    } catch { $saved = $null }
    try { return [System.Diagnostics.Process]::Start($Psi) }
    finally { if ($saved) { try { [Console]::InputEncoding = $saved } catch {} } }
}

function Find-ClaudeCode {
    # Path of the claude command, '' if Claude Code is not installed. The native installer
    # puts it into %USERPROFILE%\.local\bin, which a terminal opened before the install does
    # not have on its PATH yet.
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $native = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path $native) { return $native }
    return ''
}

function Get-AgentTools([string]$Tools, [string]$GitBash = (Find-GitBash)) {
    # The tool list for Claude Code (--tools). Without Git Bash the Bash tool cannot work,
    # so it is swapped for the PowerShell tool.
    if (-not $Tools -or $Tools -notmatch '(^|,)\s*Bash\s*(,|$)') { return $Tools }
    if ($GitBash) { return $Tools }
    return (($Tools -split ',' | ForEach-Object { $t = $_.Trim(); if ($t -eq 'Bash') { 'PowerShell' } else { $t } }) -join ',')
}

# --- which setup fits ----------------------------------------------------------------------

function Get-Setups {
    return @((Read-JsonFile (Join-Path $script:ConfigDir 'setups.json')).setups)
}

function Select-Setup([int]$VramMiB, [double]$RamGiB) {
    # The first setup in config\setups.json whose needs this machine meets. The list runs
    # from the largest to the smallest, so this is the best one that fits.
    foreach ($setup in (Get-Setups)) {
        if ($VramMiB -ge [int]$setup.minVramMiB -and $RamGiB -ge [double]$setup.minRamGiB) { return $setup }
    }
    return $null
}

function Set-MachineSetup([string]$ModelName, $Setup) {
    # Notes in config\machine.json: claude-local starts with $ModelName, and the "args" of
    # the setup (context size, ...) apply to that profile. A value this machine already has
    # for the profile stays: it was set by hand or measured here.
    Set-MachineValue 'agent' 'model' $ModelName
    if (-not $Setup -or -not $Setup.args) { return }
    $machine = Get-MachineConfig
    if (-not $machine.PSObject.Properties['models']) { $machine | Add-Member -NotePropertyName models -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $machine.models.PSObject.Properties[$ModelName]) { $machine.models | Add-Member -NotePropertyName $ModelName -NotePropertyValue ([pscustomobject]@{}) }
    $entry = $machine.models.$ModelName
    if (-not $entry.PSObject.Properties['args']) { $entry | Add-Member -NotePropertyName args -NotePropertyValue ([pscustomobject]@{}) }
    foreach ($p in $Setup.args.PSObject.Properties) {
        if (-not $entry.args.PSObject.Properties[$p.Name]) { $entry.args | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    Save-MachineConfig $machine
}

function Get-MissingDownloadBytes([string]$ModelName) {
    # Bytes still to download for a profile: its files that are not there yet.
    $total = [long]0
    foreach ($file in @(Get-ModelFiles $ModelName)) {
        if (-not (Test-ModelFilePresent $file)) { $total += [long]$file.size }
    }
    return $total
}
