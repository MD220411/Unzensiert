# Sets up Unzensiert on this machine, step by step:
#   1. checks Windows, graphics cards and main memory
#   2. chooses the install folder (llama.cpp, models, logs: about 20 to 25 GB)
#   3. Git for Windows, if missing - after asking; Claude Code (from Anthropic) only for
#      the comparison command claude-local, offered but not suggested
#   4. llama.cpp in the package that fits the graphics card
#   5. the model that fits the graphics memory (config\setups.json) - after asking; then
#      the best distribution over cards and main memory is computed from measurements and
#      tested (Plan-Models.ps1, docs\planner.md)
#   6. the commands unzensiert and claude-local on the PATH, and whether new releases are
#      installed automatically (config\updates.json, asked once)
#   7. a test: the settings (and the model once, if planning did not test it already)
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

Write-Host "Unzensiert installer, version $(Get-ProgramVersion)" -ForegroundColor Cyan
Write-Host "Program folder: $script:ProjectRoot"
if ($Plan) { Write-Host 'PLAN ONLY: nothing is installed, downloaded or changed.' -ForegroundColor Yellow }

try {
    # --- 1. this machine ---------------------------------------------------------------
    Write-Step 'Checking this machine' $steps
    $os = [Environment]::OSVersion.Version
    if (-not [Environment]::Is64BitOperatingSystem -or $os.Major -lt 10 -or ($os.Major -eq 10 -and $os.Build -lt 17763)) {
        throw 'Unzensiert needs 64-bit Windows 10 (version 1809) or newer.'
    }
    # installed main memory decides the tier; Windows can use a little less of it
    $ram = Get-InstalledMemoryGiB
    Write-Note "Windows build $($os.Build), $ram GB main memory ($(Get-SystemMemoryGiB) GB usable)"
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
    # install folder and program folder only for this account, SYSTEM and the administrators
    # (lib\FolderRights.ps1): on another drive every account of the computer may change them
    if ($Plan) {
        foreach ($f in @($root, $script:ProjectRoot)) {
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $strangers = Get-FolderStrangers $f
            if ($strangers -and @($strangers).Count -gt 0) { Write-Note "would close $f to $(@($strangers) -join ', ')" }
        }
    } else {
        foreach ($n in @(Protect-ProgramFolders @($root, $script:ProjectRoot))) { Write-Note $n }
    }

    # --- 3. Git and (for comparison) Claude Code ---------------------------------------------
    Write-Step 'Git for Windows and Claude Code' $steps
    $claude = Find-ClaudeCode
    if ($claude) {
        Write-Note "Claude Code: $claude (for the comparison command claude-local)"
    } else {
        Write-Note 'Unzensiert needs no other agent. Claude Code (made by Anthropic) is only needed for the'
        Write-Note 'comparison command claude-local, which runs Claude Code against the same local models.'
        if (Confirm-Step 'Install Claude Code for the comparison with the official installer from https://claude.ai/install.ps1?' $false) {
            if ($Plan) {
                Write-Note 'would install Claude Code'
            } else {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' | ForEach-Object { Write-Note $_ }
                $claude = Find-ClaudeCode
                if ($claude) { Write-Note "Claude Code: $claude" }
                else { Write-Warn 'Claude Code could not be installed. See https://code.claude.com/docs/en/setup' }
            }
        } else {
            Write-Note 'not installed; claude-local works after installing Claude Code and running this installer again.'
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
    # only the cards chosen with /gpu in unzensiert, if a choice was made on this machine
    $choice = Resolve-DeviceChoice (Get-UsableDevices (Get-LlamaDevices)) @(Get-DeviceChoice)
    $devices = @($choice.devices)
    if ($devices.Count -gt 0) {
        $vram = [int](($devices | Measure-Object -Property memoryMiB -Sum).Sum)
        foreach ($d in $devices) { Write-Note "llama.cpp uses $($d.id): $($d.name), $($d.memoryMiB) MiB" }
        foreach ($d in $choice.left) { Write-Note "not used (chosen with /gpu): $($d.id): $($d.name)" }
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
        throw "This machine has too little memory for the models of Unzensiert: $ram GB main memory installed, with $vram MiB graphics memory at least $(Get-LeastRamGiB $vram) GB are needed. See docs\setup.md."
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

    # how the model is best spread over the cards and main memory of this machine, computed
    # from measurements (Plan-Models.ps1, docs\planner.md); a plan from an earlier run stays
    $verified = $false
    if ($haveModel -or $Plan) {
        $plans = (Get-MachineConfig).PSObject.Properties['plans']
        if ($plans -and $plans.Value.PSObject.Properties[$chosen]) {
            Write-Note 'distribution over cards and main memory: kept from the last install (scripts\Plan-Models.ps1 computes it again)'
        } elseif ($Plan) {
            Write-Note 'would compute the best distribution over cards and main memory and test it (Plan-Models.ps1, one to two minutes)'
        } else {
            Write-Note 'computing the best distribution over cards and main memory and testing it (one to two minutes) ...'
            if ((Invoke-ProjectScript 'Plan-Models.ps1' @('-Model', $chosen, '-Verify')) -eq 0) {
                $verified = $true
            } else {
                Clear-ModelPlan $chosen
                Write-Warn 'The distribution could not be computed or tested; llama.cpp now places the model by itself (--fit).'
            }
        }
    }

    # --- 6. commands and updates ----------------------------------------------------------------
    Write-Step 'The commands unzensiert and claude-local, updates' $steps
    if ($Plan) { Write-Note "would add $(Join-Path $script:ProjectRoot 'bin') to the user PATH" }
    elseif ((Invoke-ProjectScript 'Install-Path.ps1') -ne 0) { throw 'The commands could not be put on the PATH.' }
    # asked once; the answer stays in config\machine.json (unzensiert --updates on|off)
    $machine = Get-MachineConfig
    if ($machine.PSObject.Properties['updates'] -and $machine.updates.PSObject.Properties['enabled']) {
        $state = 'off'
        if ($machine.updates.enabled) { $state = 'on' }
        Write-Note "automatic updates: $state (change with: unzensiert --updates on|off)"
    } else {
        Write-Note 'New versions are published as releases on GitHub. Unzensiert can install them by itself'
        Write-Note '(it looks at most once a day when it starts; config\machine.json stays as it is).'
        $on = Confirm-Step 'Install new releases automatically?'
        Set-UpdatesEnabled $on
        if (-not $on) { Write-Note 'switched off; switch on later with: unzensiert --updates on' }
    }
    # the sandbox (lib\Sandbox.ps1): the commands of the model as a Windows account of their own;
    # Windows asks for an administrator once, so not without a person at the terminal
    if ($Plan) { Write-Note 'would offer the sandbox (scripts\Setup-Sandbox.ps1)' }
    elseif ((Get-SandboxSetup -Fresh).ready) { Write-Note 'sandbox: set up' }
    elseif ($Yes) { Write-Note 'sandbox: not set up without a person to answer the administrator question (later: scripts\Setup-Sandbox.ps1)' }
    else {
        Write-Note 'The commands of the model can run as a Windows account of their own: it may change files only'
        Write-Note 'in the project folder, cannot read your user folder and reaches no other computer.'
        if (Confirm-Step 'Set up this sandbox now? (Windows asks once for administrator rights)') {
            if ((Invoke-ProjectScript 'Setup-Sandbox.ps1') -ne 0) { Write-Warn 'the sandbox is not set up; later: scripts\Setup-Sandbox.ps1' }
        } else { Write-Note 'not set up; later: scripts\Setup-Sandbox.ps1' }
    }

    # --- 7. test ---------------------------------------------------------------------------------
    Write-Step 'Test' $steps
    if ($Plan) {
        Write-Note 'would run Test-Setup.ps1 and Test-Model.ps1'
    } else {
        if ((Invoke-ProjectScript 'Test-Setup.ps1' -OnlyProblems) -ne 0) { throw 'The settings check failed (see above).' }
        if ($verified) {
            Write-Note 'the model was loaded and tested while its distribution was computed'
        } elseif ($haveModel -and (Confirm-Step 'Load the model once to test it? (up to a minute)')) {
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
Write-Host 'Unzensiert is ready.' -ForegroundColor Green
Write-Note 'Open a NEW terminal window (it needs the new PATH), go to a project folder and type:'
Write-Host ''
Write-Host '          unzensiert' -ForegroundColor White
Write-Host ''
Write-Note 'Inside: /help lists the commands, Esc stops the model, /exit ends.'
if ($claude) { Write-Note 'For comparison the same models with Claude Code: claude-local' }
Write-Note "More models:   $(Join-Path $PSScriptRoot 'Get-Model.ps1') -List"
Write-Note "Remove again:  $(Join-Path $script:ProjectRoot 'Uninstall.cmd')"
exit 0
