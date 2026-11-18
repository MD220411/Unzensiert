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

    # --- 9. planner (lib\Planner.ps1) with a made-up memory model instead of llama.cpp -------------
    # The stand-in follows the rules of llama.cpp: the first layers stay on the host, the
    # offloaded ones go to the cards in --device order, the output layer is one more unit and
    # goes to the last card only when every layer is offloaded, the experts of the first N
    # layers stay on the host (--n-cpu-moe). Sizes like the real models (docs\planner.md).
    $script:FakeSpec = $null
    $script:FitEstimator = {
        param($Model, $Ctx, $Order, $Counts, $Ncmoe)
        $s = $script:FakeSpec
        if ("$Ctx" -eq 'meta') { return @{ nLayerAll = $s.layers; nExpert = $s.experts; nExpertUsed = $s.used } }
        $n = $s.layers
        $ngl = 0
        foreach ($c in $Counts) { $ngl += $c }
        $cpuLayers = $n - [math]::Min($ngl, $n)
        $outputOnCard = $ngl -gt $n
        $kv = $s.kvPer1k * [int]$Ctx / 1024.0
        $last = -1
        for ($j = $Counts.Count - 1; $j -ge 0; $j--) { if ($Counts[$j] -gt 0) { $last = $j; break } }
        $result = @{}
        $start = $cpuLayers
        for ($j = 0; $j -lt $Counts.Count; $j++) {
            $layers = $Counts[$j]
            if ($outputOnCard -and $j -eq $last) { $layers -= 1 }
            $end = $start + $layers
            $withExperts = [math]::Max(0, $end - [math]::Max($start, $Ncmoe))
            $weights = $layers * $s.denseMiB + $withExperts * $s.expertMiB
            if ($outputOnCard -and $j -eq $last) { $weights += $s.outputMiB }
            $compute = 0.0
            if ($Counts[$j] -gt 0) { $compute = $s.computeMiB }
            $result[[string]$Order[$j]] = [pscustomobject]@{ model = $weights; context = $layers * $kv; compute = $compute; total = $weights + $layers * $kv + $compute }
            $start = $end
        }
        $hostExperts = [math]::Min($n, [math]::Max($cpuLayers, $Ncmoe))
        $hostWeights = $s.embdMiB + $cpuLayers * $s.denseMiB + $hostExperts * $s.expertMiB
        if (-not $outputOnCard) { $hostWeights += $s.outputMiB }
        $result['Host'] = [pscustomobject]@{ model = $hostWeights; context = $cpuLayers * $kv; compute = 600.0; total = $hostWeights + $cpuLayers * $kv + 600.0 }
        return $result
    }
    $dense = @{ layers = 65; experts = 0; used = 0; denseMiB = 248.0; expertMiB = 0.0; outputMiB = 994.0; embdMiB = 682.0; kvPer1k = 0.55; computeMiB = 1200.0 }
    $moe = @{ layers = 41; experts = 256; used = 8; denseMiB = 27.0; expertMiB = 498.0; outputMiB = 335.0; embdMiB = 335.0; kvPer1k = 0.12; computeMiB = 800.0 }
    $pcfg = Get-PlannerConfig
    $speed = @{ Host = 20.0; FAST = 1.4; SLOW = 3.5 }

    # two cards, dense model: the fast card is filled first and stands last (output layer)
    $script:FakeSpec = $dense; $script:FitCache = @{}
    $m = Get-PlannerModel 'local-coder' @([pscustomobject]@{ id = 'FAST' })
    Assert-That ($m.nLayerAll -eq 65 -and $m.hostBaseMiB -eq 682 -and $m.expertMiB -eq 0 -and $m.mtpMiB -gt 0) 'planner: model facts (layers, host share never read, MTP draft)'
    $m.mmprojMiB = 1100
    $cards = @([pscustomobject]@{ id = 'FAST'; name = 'fast'; capMiB = 14000.0; usPerMiB = 1.4 }, [pscustomobject]@{ id = 'SLOW'; name = 'slow'; capMiB = 12500.0; usPerMiB = 3.5 })
    $plan = New-ModelPlan $m $cards $speed $pcfg 100000
    $fast = [array]::IndexOf($plan.order, 'FAST')
    Assert-That ($plan.order[-1] -eq 'FAST' -and $plan.allOnCards -and $plan.ncmoe -eq 0) "planner: two cards - fast card last, every layer on a card (order $($plan.order -join ','), units $($plan.counts -join ','))"
    $more = [int[]]$plan.counts.Clone(); $more[$fast] += 1; $more[1 - $fast] -= 1
    $needFast = Get-CardNeed $m $plan.estimate $plan.order $plan.counts $fast
    Assert-That ($needFast -le 14000 -and (Get-CardNeed $m (Invoke-FitEstimate $m $plan.ctx $plan.order $more 0) $plan.order $more $fast) -gt 14000) "planner: the fast card is as full as possible (needs $([int]$needFast) of 14000 MiB, one unit more would not fit)"
    Assert-That ($plan.ctx -eq 131072) "planner: two cards - the largest context (got $($plan.ctx))"
    $roomSlow = 12500 - (Get-CardNeed $m $plan.estimate $plan.order $plan.counts (1 - $fast))
    Assert-That (($roomSlow -ge 1100 -and $plan.mmproj -eq 'SLOW') -or ($roomSlow -lt 1100 -and $plan.mmproj -eq 'cpu')) "planner: image encoder where room is left ($($plan.mmproj), $([int]$roomSlow) MiB free on the slow card)"

    # one card of 12 GB, dense model: part of the layers stays on the host, and of the
    # context sizes the largest one within the tolerance is taken
    $script:FitCache = @{}
    $one = @([pscustomobject]@{ id = 'SLOW'; name = 'slow'; capMiB = 11000.0; usPerMiB = 3.5 })
    $plan = New-ModelPlan $m $one $speed $pcfg 100000
    $pool = @($plan.candidates | Where-Object { $_.ctx -ge [int]$pcfg.minCtx })
    $best = ($pool | Measure-Object -Property ms -Minimum).Minimum
    $bigger = @($pool | Where-Object { $_.ctx -gt $plan.ctx -and $_.ms -le $best * (1 + [double]$pcfg.speedTolerance) })
    Assert-That (-not $plan.allOnCards -and $plan.counts[0] -gt 0 -and $plan.ctx -ge [int]$pcfg.minCtx) "planner: one small card - some layers on the host ($($plan.counts[0]) units on the card, context $($plan.ctx))"
    Assert-That ($plan.ms -le $best * (1 + [double]$pcfg.speedTolerance) -and $bigger.Count -eq 0) 'planner: the largest context within the speed tolerance'
    Assert-That ($plan.mmproj -eq 'cpu') 'planner: image encoder on the processor when the card is full'

    # mixture of experts on one card: experts move to the host, the layers stay on the card
    $script:FakeSpec = $moe; $script:FitCache = @{}
    $mm = Get-PlannerModel 'local-fast' @([pscustomobject]@{ id = 'SLOW' })
    Assert-That ($mm.nExpert -eq 256 -and [math]::Abs($mm.expertMiB - 498) -lt 1 -and [math]::Abs($mm.activeFraction - 8 / 256.0) -lt 1e-9) 'planner: experts per layer and the active share are found'
    $plan = New-ModelPlan $mm $one $speed $pcfg 100000
    Assert-That ($plan.allOnCards -and $plan.ncmoe -gt 0 -and $plan.counts[0] -eq 42) "planner: mixture of experts - experts of $($plan.ncmoe) layers on the host, every layer on the card"
    $fewer = Find-Placement $mm $one $plan.ctx ($plan.ncmoe - 1)
    Assert-That (-not $fewer.allOnCards) 'planner: as few experts on the host as possible'
    $reads = Get-PlacementReads $mm $plan.order $plan.counts $plan.ncmoe $plan.estimate
    $expectedHost = $plan.ncmoe * 498.0 * (8 / 256.0)
    Assert-That ([math]::Abs($reads['Host'] - $expectedHost) -lt 1) "planner: from the host only the active experts are read per token ($([int]$reads['Host']) MiB)"

    # options for the server
    $a = ConvertTo-PlanArgs $plan
    Assert-That ($a['fit'] -eq 'off' -and $a['gpu-layers'] -eq 42 -and $a['device'] -eq 'SLOW' -and $a['n-cpu-moe'] -eq $plan.ncmoe -and $a.Contains('mmproj-offload')) 'planner: options for llama-server (fit off, layers, device, n-cpu-moe)'

    # calibration: known times per MiB come back out of made-up measurements
    $cpuRun = @{ reads = @{ Host = 15000.0 }; tps = 1e6 / (15000 * 20.0) }
    $runA = @{ reads = @{ FAST = 10000.0; SLOW = 5000.0; Host = 0.0 }; tps = 1e6 / (10000 * 1.4 + 5000 * 3.5) }
    $runB = @{ reads = @{ FAST = 6000.0; SLOW = 9000.0; Host = 300.0 }; tps = 1e6 / (6000 * 1.4 + 9000 * 3.5 + 300 * 20.0) }
    $solved = ConvertFrom-CalibrationRuns $cpuRun @($runA, $runB) @('FAST', 'SLOW')
    Assert-That ([math]::Abs($solved.speed['Host'] - 20) -lt 0.01 -and [math]::Abs($solved.speed['FAST'] - 1.4) -lt 0.01 -and [math]::Abs($solved.speed['SLOW'] - 3.5) -lt 0.01 -and $solved.uncertain.Count -eq 0) 'calibration: times per MiB are solved from the measured runs'
    $bad = @{ reads = @{ FAST = 100.0; Host = 14000.0 }; tps = 1e6 / (14000 * 20.0 - 100) }
    $solved = ConvertFrom-CalibrationRuns $cpuRun @($bad) @('FAST')
    Assert-That ($solved.uncertain -contains 'FAST' -and [math]::Abs($solved.speed['FAST'] - 20 / 12.0) -lt 0.01) 'calibration: a card hidden behind the host part gets a fallback value and is marked'
    $script:FitEstimator = $null; $script:FitCache = @{}
} finally {
    $env:CLAUDE_LOCAL_MACHINE_FILE = $savedMachineFile
    Remove-Item -Recurse -Force -Path $scratch -ErrorAction SilentlyContinue
}

if ($script:Failures -gt 0) { "install: $script:Failures check(s) failed."; exit 1 }
'install: all checks passed.'
