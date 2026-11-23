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
    $lines = @(& (Get-SystemProgram 'cmd') /c "`"$Exe`" --list-devices 2>&1")
    return @(ConvertFrom-DeviceList $lines)
}

function Get-UsableDevices($Devices) {
    # Leaves out integrated graphics ("ignoreDevices" in config\setups.json): it shares the
    # main memory and would make the graphics memory look larger than it is.
    $pattern = [string](Read-JsonFile (Join-Path $script:ConfigDir 'setups.json')).ignoreDevices
    # "$null | Where-Object" would let one empty entry through
    return @(@($Devices) | Where-Object { $_ -and (-not $pattern -or $_.name -notmatch $pattern) })
}

# --- which cards llama.cpp may use (/gpu in unzensiert) ------------------------------------

function Get-DeviceChoice {
    # The ids of the cards llama.cpp may use on this machine ("devices" in config\server.json,
    # set in config\machine.json by /gpu); empty = every usable card. How much goes on which
    # of them the planner decides (docs\planner.md).
    return [string[]]@(@((Get-ServerConfig).devices) | Where-Object { $_ } | ForEach-Object { [string]$_ })
}

function Resolve-DeviceChoice($Devices, [string[]]$Ids) {
    # Splits $Devices into the chosen cards and the ones left out. Without a choice every card
    # is chosen. Chosen ids no card has any more (another llama.cpp package, a card taken out)
    # come back in missing; if none of the chosen cards is there, every card is used again.
    $all = @(@($Devices) | Where-Object { $_ })
    $wanted = @(@($Ids) | Where-Object { $_ })
    $known = @($all | ForEach-Object { [string]$_.id })
    $chosen = $all
    $missing = @()
    if ($wanted.Count -gt 0) {
        $chosen = @($all | Where-Object { $wanted -contains [string]$_.id })
        $missing = @($wanted | Where-Object { $known -notcontains $_ })
        if ($chosen.Count -eq 0) { $chosen = $all }
    }
    $chosenIds = @($chosen | ForEach-Object { [string]$_.id })
    $left = @($all | Where-Object { $chosenIds -notcontains [string]$_.id })
    return @{ devices = $chosen; left = $left; missing = $missing }
}

function ConvertFrom-DeviceSelection([string]$Text, $Devices) {
    # What the user typed after /gpu: numbers of the list ("1 2", "1,2"), ids ("CUDA1") or
    # "all". Returns @{ ids (in the order of the list); all (every card); bad (a word that
    # names no card, '' if none) }.
    $all = @(@($Devices) | Where-Object { $_ })
    $result = @{ ids = @(); all = $false; bad = '' }
    $picked = @()
    foreach ($word in @($Text -split '[\s,;]+' | Where-Object { $_ })) {
        $n = 0
        if ($word -in 'all', 'alle', '*') { $picked = @($all | ForEach-Object { [string]$_.id }); continue }
        if ([int]::TryParse($word, [ref]$n) -and $n -ge 1 -and $n -le $all.Count) { $picked += [string]$all[$n - 1].id; continue }
        $hit = @($all | Where-Object { [string]$_.id -eq $word })
        if ($hit.Count -gt 0) { $picked += [string]$hit[0].id; continue }
        $result.bad = $word
        return $result
    }
    $result.ids = @($all | ForEach-Object { [string]$_.id } | Where-Object { $picked -contains $_ })
    $result.all = ($all.Count -gt 0 -and $result.ids.Count -eq $all.Count)
    return $result
}

function Set-DeviceChoice([string[]]$Ids) {
    # Saves which cards llama.cpp may use on this machine. No ids = every card: the key is
    # taken out of config\machine.json, so a card added later is used as well.
    $wanted = @(@($Ids) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    if ($wanted.Count -gt 0) { Set-MachineValue 'server' 'devices' ([string[]]$wanted); return }
    $machine = Get-MachineConfig
    if ($machine.PSObject.Properties['server'] -and $machine.server.PSObject.Properties['devices']) {
        $machine.server.PSObject.Properties.Remove('devices')
        Save-MachineConfig $machine
    }
}

# --- memory and disks ---------------------------------------------------------------------

function Get-SystemMemoryGiB {
    # Main memory Windows can use. It is a little less than what is installed: firmware and
    # integrated graphics keep a part (32 GB of modules give about 31.7 GB). The planner
    # works with this value.
    return [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
}

function Resolve-InstalledMemoryGiB([double]$ModuleBytes, [double]$UsableGiB) {
    # Installed main memory from the sum of the memory modules. Without that sum (some
    # virtual machines report no modules) the usable value rounded up to whole GB.
    if ($ModuleBytes -le 0) { return [math]::Ceiling($UsableGiB) }
    return [math]::Max([math]::Round($ModuleBytes / 1GB, 1), $UsableGiB)
}

function Get-InstalledMemoryGiB {
    # Installed main memory, as the tiers in config\setups.json count it ("32 GB").
    $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $bytes = [double](($modules | Measure-Object -Property Capacity -Sum).Sum)
    return Resolve-InstalledMemoryGiB $bytes (Get-SystemMemoryGiB)
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
    $git = Get-GitExe
    if ($git) { $candidates += (Join-Path (Split-Path -Parent (Split-Path -Parent $git)) 'bin\bash.exe') }
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

function Stop-ProcessTree([int]$Id) {
    # Ends a process with everything it started (taskkill of Windows, by its full path).
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = & (Get-SystemProgram 'taskkill') /PID $Id /T /F 2>$null } catch {} finally { $ErrorActionPreference = $saved }
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
    # from the largest to the smallest, so this is the best one that fits. $RamGiB is the
    # installed main memory (Get-InstalledMemoryGiB).
    foreach ($setup in (Get-Setups)) {
        if ($VramMiB -ge [int]$setup.minVramMiB -and $RamGiB -ge [double]$setup.minRamGiB) { return $setup }
    }
    return $null
}

function Get-LeastRamGiB([int]$VramMiB) {
    # The least main memory a setup asks for that this much graphics memory allows.
    $fitting = @(Get-Setups | Where-Object { $VramMiB -ge [int]$_.minVramMiB })
    if ($fitting.Count -eq 0) { return 0 }
    return [double]($fitting | Measure-Object -Property minRamGiB -Minimum).Minimum
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
