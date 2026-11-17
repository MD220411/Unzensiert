# Sets up claude-local on this machine, step by step:
#   1. checks Windows, graphics cards and main memory
#   2. chooses the install folder (llama.cpp, models, logs: about 20 to 25 GB)
#   3. Claude Code (from Anthropic) and Git for Windows, if missing - after asking
#   4. llama.cpp in the package that fits the graphics card
#   5. the model that fits the graphics memory (config\setups.json) - after asking
#   6. the command claude-local on the PATH
#   7. a test: the settings, then the model once
# What this machine needs to remember goes into config\machine.json. Values already there
# are kept, so running the installer again repairs an install without undoing changes.
#
#   Install.cmd (double-click)   or   powershell -ExecutionPolicy Bypass -File scripts\Install.ps1
#   ... -Yes                 take every suggested answer without asking
#   ... -InstallRoot D:\ai   use this install folder
#   ... -Model local-fast    this model instead of the suggested one (Get-Model.ps1 -List)
#   ... -Plan                only show what would happen: nothing is installed, downloaded
#                            or changed (config\machine.json is left as it is)
#
# Exit code 0 = ready to use, 1 = something failed (the message says what to do).

param([switch]$Yes, [string]$InstallRoot, [string]$Model, [switch]$Plan)

. "$PSScriptRoot\_common.ps1"

$script:AssumeYes = ($Yes -or $Plan)     # lib\Dialog.ps1: take the suggested answers
$steps = 7
Assert-CanAsk
if ($Plan) {
    # A plan works on a copy of the machine settings, so it can show the decisions without
    # changing anything.
    $copy = Join-Path $env:TEMP "claude-local-plan-$PID.json"
    $source = Get-MachineFile
    if (Test-Path $source) { Copy-Item -Force -Path $source -Destination $copy } else { Remove-Item -Force -Path $copy -ErrorAction SilentlyContinue }
    $env:CLAUDE_LOCAL_MACHINE_FILE = $copy
}

Write-Host 'claude-local installer' -ForegroundColor Cyan
Write-Host "Program folder: $script:ProjectRoot"
if ($Plan) { Write-Host 'PLAN ONLY: nothing is installed, downloaded or changed.' -ForegroundColor Yellow }

try {
    # --- 1. this machine ---------------------------------------------------------------
    Write-Step 'Checking this machine' $steps
    $os = [Environment]::OSVersion.Version
    if (-not [Environment]::Is64BitOperatingSystem -or $os.Major -lt 10 -or ($os.Major -eq 10 -and $os.Build -lt 17763)) {
        throw 'claude-local needs 64-bit Windows 10 (version 1809) or newer.'
    }
    $ram = Get-SystemMemoryGiB
    Write-Note "Windows build $($os.Build), $ram GB main memory"
    $nvidia = @(Get-NvidiaGpus)
    foreach ($g in $nvidia) { Write-Note "graphics card: $($g.name), $($g.memoryMiB) MiB, driver $($g.driver)" }
    foreach ($name in @(Get-DisplayAdapters | Where-Object { $_ -notmatch 'NVIDIA' })) { Write-Note "display adapter: $name" }
    $vendors = @(Get-GpuVendors)
    if ($vendors -notcontains 'nvidia') {
        if ($vendors -contains 'amd' -or $vendors -contains 'intel') {
            Write-Warn 'No NVIDIA card. AMD and Intel cards run through Vulkan: experimental, not tested.'
        } else {
            Write-Warn 'No graphics card found. The model would run on the processor only, which is very slow.'
        }
    }

    # --- 2. install folder -------------------------------------------------------------
    Write-Step 'Install folder' $steps
    $machine = Get-MachineConfig
    $kept = ''
    if ($machine.PSObject.Properties['server'] -and $machine.server.installRoot) { $kept = Expand-SettingPath ([string]$machine.server.installRoot) }
    if ($InstallRoot) {
        $root = $InstallRoot
    } elseif ($kept) {
        $root = $kept
        Write-Note 'kept from the last install (config\machine.json)'
    } else {
        $drive = Get-RoomiestDrive
        $suggest = Join-Path $drive 'claude-local'
        if ($drive -ieq "$env:SystemDrive\") { $suggest = Join-Path $env:LOCALAPPDATA 'claude-local' }
        Write-Note 'llama.cpp, the model files (about 20 GB per model) and the logs go into one folder.'
        $root = Read-Answer 'Install folder' $suggest
    }
    $root = [System.IO.Path]::GetFullPath((Expand-SettingPath $root)).TrimEnd('\')
    if ($root.Length -le 3) { $root = Join-Path $root 'claude-local' }    # never a whole drive
    if ($root.StartsWith($script:ProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The install folder must not lie inside the program folder ($script:ProjectRoot)."
    }
    Write-Note "install folder: $root ($(Get-FreeSpaceGiB $root) GB free on that drive)"
    if (-not $Plan) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
    Set-MachineValue 'server' 'installRoot' $root
    Publish-ConfigEnvironment

    # --- 3. Claude Code and Git ----------------------------------------------------------
    Write-Step 'Claude Code and Git for Windows' $steps
    $claude = Find-ClaudeCode
    if ($claude) {
        Write-Note "Claude Code: $claude"
    } else {
        Write-Note 'Claude Code (made by Anthropic) is the agent claude-local runs on. It is not installed.'
        if (Confirm-Step 'Install it now with the official installer from https://claude.ai/install.ps1?') {
            if ($Plan) {
                Write-Note 'would install Claude Code'
            } else {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' | ForEach-Object { Write-Note $_ }
                $claude = Find-ClaudeCode
                if ($claude) { Write-Note "Claude Code: $claude" }
                else { Write-Warn 'Claude Code could not be installed. See https://code.claude.com/docs/en/setup' }
            }
        } else {
            Write-Warn 'claude-local cannot start without Claude Code. Install it later and run this installer again.'
        }
    }
    $bash = Find-GitBash
    if ($bash) {
        Write-Note "Git Bash: $bash"
    } else {
        Write-Note 'Git for Windows gives the agent its Bash tool and lets you undo its changes with git.'
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget -and (Confirm-Step 'Install Git for Windows now (with winget)?')) {
            if ($Plan) {
                Write-Note 'would install Git for Windows'
            } else {
                & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements | ForEach-Object { Write-Note $_ }
                # winget does not update the PATH of this window
                $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
                $bash = Find-GitBash
            }
        }
        if (-not $bash -and -not $Plan) { Write-Warn 'Without Git for Windows the agent runs its commands in PowerShell. Get Git later from https://git-scm.com/downloads/win' }
    }

    # --- 4. llama.cpp -----------------------------------------------------------------------
    Write-Step 'llama.cpp (runs the models)' $steps
    $server = Get-ServerConfig
    if ($Plan) {
        if (Test-Path $server.exe) { Write-Note "installed: $($server.binDir)" }
        else { Write-Note "would install llama.cpp $($server.build), trying: $((Get-LlamaPackageCandidates) -join ', ')" }
    } else {
        if ((Invoke-ProjectScript 'Install-LlamaCpp.ps1') -ne 0) { throw 'llama.cpp could not be installed (see above).' }
    }

    # --- 5. model -----------------------------------------------------------------------------
    Write-Step 'Model' $steps
    $devices = @(Get-UsableDevices (Get-LlamaDevices))
    if ($devices.Count -gt 0) {
        $vram = [int](($devices | Measure-Object -Property memoryMiB -Sum).Sum)
        foreach ($d in $devices) { Write-Note "llama.cpp uses $($d.id): $($d.name), $($d.memoryMiB) MiB" }
    } else {
        # before llama.cpp is there (plan), the driver's numbers have to do
        $vram = [int](($nvidia | Measure-Object -Property memoryMiB -Sum).Sum)
    }
    Write-Note "graphics memory $vram MiB, main memory $ram GB"
    $setup = Select-Setup $vram $ram
    $machine = Get-MachineConfig
    $chosen = ''
    if ($Model) {
        $chosen = Resolve-ModelName $Model
        $null = Get-ModelProfile $chosen
    } elseif ($machine.PSObject.Properties['agent'] -and $machine.agent.model -and (Test-ModelInstalled ([string]$machine.agent.model))) {
        $chosen = [string]$machine.agent.model
        Write-Note "kept from the last install: $chosen"
    } elseif ($setup) {
        $chosen = [string]$setup.model
    }
    if (-not $chosen) {
        $least = (Get-Setups | Measure-Object -Property minRamGiB -Minimum).Minimum
        throw "This machine has too little memory for the models of claude-local (at least $least GB main memory). See docs\einrichtung.md."
    }
    $prof = Get-ModelProfile $chosen
    Write-Note "model: $chosen - $($prof.description)"
    if ($setup) {
        Write-Note "setup for this machine: $($setup.name), context $($setup.args.'ctx-size') tokens"
        if ($setup.measured) { Write-Note "measured on: $($setup.measured)" }
        else { Write-Note 'not measured on such a machine yet (estimate)' }
        if ($setup.slow) { Write-Warn 'Most of the model runs on the processor: answers will be slow.' }
        if ($setup.PSObject.Properties['alternative'] -and -not $Model) {
            Write-Note "other choice: run the installer with -Model $($setup.alternative) (see the measurement above)"
        }
    }
    $bytes = Get-MissingDownloadBytes $chosen
    $haveModel = $false
    if ($bytes -eq 0) {
        Write-Note 'model files are already there'
        $haveModel = $true
    } else {
        $gb = [math]::Round($bytes / 1GB, 1)
        $free = Get-FreeSpaceGiB $root
        if ($free -lt $gb + 1) { throw "Not enough disk space: the model needs $gb GB, $free GB are free on the drive of $root." }
        if (Confirm-Step "Download $chosen now ($gb GB from Hugging Face)?") {
            if ($Plan) {
                Write-Note "would download $gb GB"
            } else {
                Set-MachineSetup $chosen $setup
                if ((Invoke-ProjectScript 'Get-Model.ps1' @('-Model', $chosen)) -ne 0) { throw 'The download failed (see above). Run the installer again to continue where it stopped.' }
                $haveModel = $true
            }
        } else {
            Write-Warn "No model downloaded. Later: $(Join-Path $PSScriptRoot 'Get-Model.ps1') -Model $chosen"
        }
    }
    Set-MachineSetup $chosen $setup

    # --- 6. command ---------------------------------------------------------------------------
    Write-Step 'The command claude-local' $steps
    if ($Plan) { Write-Note "would add $(Join-Path $script:ProjectRoot 'bin') to the user PATH" }
    elseif ((Invoke-ProjectScript 'Install-Path.ps1') -ne 0) { throw 'claude-local could not be put on the PATH.' }

    # --- 7. test ---------------------------------------------------------------------------------
    Write-Step 'Test' $steps
    if ($Plan) {
        Write-Note 'would run Test-Setup.ps1 and Test-Model.ps1'
    } else {
        if ((Invoke-ProjectScript 'Test-Setup.ps1' -OnlyProblems) -ne 0) { throw 'The settings check failed (see above).' }
        if ($haveModel -and (Confirm-Step 'Load the model once to test it? (up to a minute)')) {
            if ((Invoke-ProjectScript 'Test-Model.ps1' @('-Model', $chosen, '-NoLog')) -ne 0) { throw "The model test failed (see above). Log: $($server.logFile)" }
        }
    }
} catch {
    Write-Host ''
    Write-Host "Install stopped: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'You can run the installer again at any time; it continues where it stopped.'
    exit 1
} finally {
    if ($Plan) { Remove-Item -Force -Path $env:CLAUDE_LOCAL_MACHINE_FILE -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($Plan) { Write-Host 'Plan finished. Run without -Plan to install.' -ForegroundColor Green; exit 0 }
Write-Host 'claude-local is ready.' -ForegroundColor Green
Write-Note 'Open a NEW terminal window (it needs the new PATH), go to a project folder and type:'
Write-Host ''
Write-Host '          claude-local' -ForegroundColor White
Write-Host ''
Write-Note 'The first start of Claude Code asks for a colour theme and whether you trust the folder.'
Write-Note "More models:   $(Join-Path $PSScriptRoot 'Get-Model.ps1') -List"
Write-Note "Remove again:  $(Join-Path $script:ProjectRoot 'Uninstall.cmd')"
exit 0
