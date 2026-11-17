# Checks the logic of the installer without downloading anything and without a graphics
# card: how config\machine.json is laid over config\, how the device list of llama.cpp is
# read, which setup is chosen for which machine, which tools the agent gets without Git
# Bash, that every download entry is complete, a dry run of the installer (Install.ps1
# -Plan) for an empty example machine, and that the one-line installer never ends the
# user's PowerShell session. Takes about half a minute.
# Run it after changes to Install.ps1, Uninstall.ps1, install.ps1, lib\Config.ps1,
# lib\Machine.ps1, lib\Download.ps1, config\setups.json or a "download" entry in
# config\models.json.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Install.ps1
#
# Exit code 0 = all checks passed, 1 = at least one failed.

. "$PSScriptRoot\_common.ps1"

$script:Failures = 0
function Assert-That([bool]$Condition, [string]$What) {
    if ($Condition) { "ok    $What" } else { $script:Failures++; "FAIL  $What" }
}

$scratch = Join-Path $env:TEMP "claude-local-install-test-$PID"
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$savedMachineFile = $env:CLAUDE_LOCAL_MACHINE_FILE
try {
    # --- 1. defaults without a machine file ----------------------------------------------
    $env:CLAUDE_LOCAL_MACHINE_FILE = Join-Path $scratch 'machine.json'
    $server = Get-ServerConfig
    Assert-That ($server.installRoot -eq (Join-Path $env:LOCALAPPDATA 'claude-local')) "default install folder is %LOCALAPPDATA%\claude-local ($($server.installRoot))"
    Assert-That ($server.modelsDir -eq (Join-Path $server.installRoot 'models')) 'default models folder is <installRoot>\models'
    Assert-That ((Get-ProjectsRoot) -eq (Join-Path $env:USERPROFILE 'Projects')) 'default projects folder is %USERPROFILE%\Projects'
    Assert-That ((Get-BenchmarkConfig).workDir -eq (Join-Path $server.installRoot 'bench-work')) 'default benchmark folder is <installRoot>\bench-work'
    $portable = $true
    foreach ($name in (Get-ModelNames)) {
        $a = (Get-ModelProfile $name).args
        if ($a.Contains('tensor-split') -or $a.Contains('device') -or $a.Contains('mmproj-device') -or $a.Contains('gpu-layers')) { $portable = $false }
    }
    Assert-That $portable 'config\models.json names no GPU split, device or layer count (llama.cpp fits the model itself)'

    # --- 2. a machine file laid over the defaults ------------------------------------------
    $root = Join-Path $scratch 'root'
    $machine = [ordered]@{
        server        = [ordered]@{ installRoot = $root }
        modelDefaults = [ordered]@{ 'gpu-layers' = 999 }
        models        = [ordered]@{
            'local-coder' = [ordered]@{ args = [ordered]@{ 'tensor-split' = '70,30'; 'ctx-size' = 32768; temp = $null } }
            'extra'       = [ordered]@{ role = 'agent'; file = 'extra.gguf'; args = [ordered]@{} }
        }
        agent         = [ordered]@{ model = 'local-fast'; review = [ordered]@{ model = 'local-coder' } }
    }
    [System.IO.File]::WriteAllText($env:CLAUDE_LOCAL_MACHINE_FILE, ($machine | ConvertTo-Json -Depth 6))
    $server = Get-ServerConfig
    Assert-That ($server.installRoot -eq $root -and $server.modelsDir -eq (Join-Path $root 'models')) 'machine.json: install folder, models folder follows it'
    $coder = Get-ModelProfile 'local-coder'
    Assert-That ($coder.args['gpu-layers'] -eq 999 -and $coder.args['tensor-split'] -eq '70,30' -and $coder.args['ctx-size'] -eq 32768) 'machine.json: modelDefaults and profile args are added or replaced'
    Assert-That (-not $coder.args.Contains('temp') -and $coder.args.Contains('top-k')) 'machine.json: null removes one arg, the others stay'
    Assert-That ($coder.args['mmproj'] -eq (Join-Path (Join-Path $root 'models') 'qwen3.6-27b-mmproj-BF16.gguf')) 'machine.json: image encoder is looked for in the models folder of this machine'
    Assert-That ((Get-ModelContextSize 'local-fast') -eq 131072) 'machine.json: other profiles keep their values'
    Assert-That ((Get-ModelNames) -contains 'extra') 'machine.json: a profile of this machine only is added'
    $agent = Get-AgentConfig
    Assert-That ($agent.model -eq 'local-fast' -and $agent.review.model -eq 'local-coder' -and $agent.review.enabled -eq $true -and $agent.review.minChangedLines -gt 0) 'machine.json: agent settings are merged key by key'
    Set-MachineValue 'server' 'package' 'win-vulkan-x64'
    $server = Get-ServerConfig
    Assert-That ($server.package -eq 'win-vulkan-x64' -and $server.installRoot -eq $root) 'Set-MachineValue adds a value and keeps the others'
    $setupA = [pscustomobject]@{ args = [pscustomobject]@{ 'ctx-size' = 65536 } }
    $setupB = [pscustomobject]@{ args = [pscustomobject]@{ 'ctx-size' = 32768 } }
    Set-MachineSetup 'local-fast' $setupA
    Set-MachineSetup 'local-fast' $setupB
    Assert-That ((Get-AgentConfig).model -eq 'local-fast' -and (Get-ModelContextSize 'local-fast') -eq 65536) 'Set-MachineSetup notes the model and keeps a value the machine already has'
    Assert-That ((Get-ModelContextSize 'local-coder') -eq 32768) 'Set-MachineSetup leaves the other profiles alone'

    # --- 3. device list of llama.cpp ----------------------------------------------------------
    $lines = @(
        'ggml_cuda_init: found 2 CUDA devices:',
        'Available devices:',
        '  CUDA0: NVIDIA GeForce RTX 5070 Ti (16275 MiB, 12196 MiB free)',
        '  CUDA1: NVIDIA GeForce RTX 3060 (12287 MiB, 9188 MiB free)',
        '  Vulkan0: AMD Radeon RX 7900 XTX (24560 MiB, 24000 MiB free)',
        '  Vulkan1: Intel(R) UHD Graphics 770 (16000 MiB, 16000 MiB free)')
    $devices = @(ConvertFrom-DeviceList $lines)
    Assert-That ($devices.Count -eq 4 -and $devices[0].id -eq 'CUDA0' -and $devices[1].memoryMiB -eq 12287 -and $devices[2].name -eq 'AMD Radeon RX 7900 XTX') 'device list: four cards with id, name and memory'
    $usable = @(Get-UsableDevices $devices)
    Assert-That ($usable.Count -eq 3 -and @($usable | Where-Object { $_.name -match 'UHD' }).Count -eq 0) 'device list: integrated graphics does not count'
    Assert-That (@(Get-UsableDevices (ConvertFrom-DeviceList @('no devices'))).Count -eq 0 -and @(Get-UsableDevices $null).Count -eq 0) 'device list: no card gives an empty list'

    # --- 4. which setup for which machine -------------------------------------------------------
    $cases = @(
        @(28562, 127, '26gb'), @(24576, 32, '22gb'), @(16384, 32, '15gb'), @(12288, 32, '11gb'),
        @(8192, 32, '7gb'), @(0, 64, 'cpu'), @(16384, 8, ''))
    foreach ($c in $cases) {
        $setup = Select-Setup $c[0] $c[1]
        $got = ''
        if ($setup) { $got = [string]$setup.name }
        Assert-That ($got -eq $c[2]) "setup for $($c[0]) MiB graphics and $($c[1]) GB main memory: '$($c[2])' (got '$got')"
    }

    # --- 5. tools of the agent ------------------------------------------------------------------
    Assert-That ((Get-AgentTools 'Bash,Read,Edit' 'C:\Git\bin\bash.exe') -eq 'Bash,Read,Edit') 'tools: Bash stays with Git Bash'
    Assert-That ((Get-AgentTools 'Bash,Read,Edit' '') -eq 'PowerShell,Read,Edit') 'tools: Bash becomes PowerShell without Git Bash'
    Assert-That ((Get-AgentTools 'Read,Edit' '') -eq 'Read,Edit') 'tools: a list without Bash stays as it is'

    # --- 6. download entries ----------------------------------------------------------------------
    Remove-Item -Force -Path $env:CLAUDE_LOCAL_MACHINE_FILE
    foreach ($name in (Get-ModelNames)) {
        $files = @(Get-ModelFiles $name)
        $ok = $files.Count -gt 0
        foreach ($f in $files) {
            if ($f.url -notmatch '^https://huggingface\.co/[\w.-]+/[\w.-]+/resolve/[0-9a-f]{40}/[\w.-]+\.gguf$') { $ok = $false }
        }
        Assert-That $ok "downloads of $name`: pinned Hugging Face addresses"
    }
    Assert-That (@(Get-ModelFiles 'local-coder-rb0')[0].name -eq (Get-ModelProfile 'local-coder').file) 'downloads: a profile can share the files of another one'

    # --- 7. installer dry run on an empty machine -----------------------------------------------
    $planRoot = Join-Path $scratch 'plan-root'
    $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install.ps1') -Plan -InstallRoot $planRoot 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    Assert-That ($code -eq 0 -and ($out -match 'Plan finished').Count -gt 0) "Install.ps1 -Plan runs through (exit code $code)"
    Assert-That (($out -match 'would download').Count -gt 0 -and ($out -match 'setup for this machine').Count -gt 0) 'Install.ps1 -Plan names a setup and the download'
    Assert-That (-not (Test-Path $planRoot) -and -not (Test-Path $env:CLAUDE_LOCAL_MACHINE_FILE)) 'Install.ps1 -Plan creates no folder and no machine file'
    if ($code -ne 0) { $out | Select-Object -Last 15 | ForEach-Object { "      $_" } }

    # --- 8. the one-line installer ----------------------------------------------------------------
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:ProjectRoot 'install.ps1'), [ref]$tokens, [ref]$errors)
    $exits = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
    Assert-That ($errors.Count -eq 0 -and $exits.Count -eq 0) 'install.ps1 parses and has no exit (it runs inside the user''s PowerShell window)'
    foreach ($cmd in 'Install.cmd', 'Uninstall.cmd') {
        $text = Get-Content -Raw -Path (Join-Path $script:ProjectRoot $cmd)
        $target = [regex]::Match($text, '%~dp0(scripts\\[\w-]+\.ps1)').Groups[1].Value
        Assert-That ($target -and (Test-Path (Join-Path $script:ProjectRoot $target))) "$cmd starts $target"
    }
} finally {
    $env:CLAUDE_LOCAL_MACHINE_FILE = $savedMachineFile
    Remove-Item -Recurse -Force -Path $scratch -ErrorAction SilentlyContinue
}

if ($script:Failures -gt 0) { "install: $script:Failures check(s) failed."; exit 1 }
'install: all checks passed.'
