# Computes how each model is best spread over the graphics cards and the main memory of
# this machine and writes the result into config\machine.json (lib\Planner.ps1,
# docs\planer.md):
#   1. stops llama-server, so the cards are empty, and reads their free memory
#   2. calibration: measures every model once with llama-bench (about half a minute per
#      model); kept in machine.json and repeated only for other cards or with -Recalibrate
#   3. plan: context size, layers per card, experts in main memory, image encoder
#   4. with -Verify: loads every planned model and tests it (Test-Model.ps1); a model that
#      does not load is planned again with 1 GB more kept free per card
#
#   powershell -ExecutionPolicy Bypass -File scripts\Plan-Models.ps1              every installed agent model
#   ... -Model local-fast    only this profile (also a profile of another role)
#   ... -Recalibrate         measure again although a calibration is there
#   ... -Verify              load and test every planned model afterwards
#   ... -Show                only show the plans that are in machine.json
#
# Stops a running llama-server: sessions of claude-local lose their model for a moment.

param([string]$Model, [switch]$Recalibrate, [switch]$Verify, [switch]$Show)

. "$PSScriptRoot\_common.ps1"

function Format-GB([double]$MiB) { return ('{0:N1} GB' -f ($MiB / 1024.0)) }

function ConvertTo-Hashtable($Object) {
    $h = @{}
    if ($Object) { foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value } }
    return $h
}

function Write-Plan([string]$Name, $Plan, $Cards, $Model) {
    # One block per model: context, every card with its layers and memory, the host.
    $tps = [math]::Round(1000.0 / [math]::Max(0.001, $Plan.ms), 1)
    "$Name`: context $($Plan.ctx) tokens, predicted $tps tokens/s (generation without MTP)"
    $needs = Get-PlanNeeds $Model $Plan
    $last = Get-LastCardIndex $Plan.counts
    for ($j = $Plan.order.Count - 1; $j -ge 0; $j--) {
        $card = @($Cards | Where-Object { $_.id -eq $Plan.order[$j] })[0]
        $note = ''
        if ($j -eq $last -and $Plan.allOnCards) { $note += ' + output layer' }
        if ($j -eq $last -and $Model.mtpMiB -gt 0) { $note += ' + MTP draft' }
        if ($Plan.mmproj -eq $card.id) { $note += ' + image encoder' }
        '  {0,-7} {1,-30} {2,3} units  {3,8} of {4,8}{5}' -f $card.id, $card.name, $Plan.counts[$j], (Format-GB $needs[$card.id]), (Format-GB $card.capMiB), $note
    }
    $layout = Get-PlacementLayout $Model $Plan.counts $Plan.ncmoe
    $hostNote = "$($layout.cpuLayers) layers"
    if (-not $Plan.allOnCards) { $hostNote += ' + output layer' }
    if ($Plan.ncmoe -gt 0) { $hostNote += ", experts of $($Plan.ncmoe) layers" }
    if ($Plan.mmproj -eq 'cpu') { $hostNote += ', image encoder' }
    '  {0,-7} {1,-30} {2}  {3,8}' -f 'host', 'main memory', $hostNote, (Format-GB (Get-EstimateTotal $Plan.estimate 'Host'))
    $others = @($Plan.candidates | Where-Object { $_.ctx -ne $Plan.ctx } | ForEach-Object { '{0}: {1} t/s' -f $_.ctx, [math]::Round(1000.0 / [math]::Max(0.001, $_.ms), 1) })
    if ($others) { "  other context sizes: $($others -join ', ')" }
}

$cfg = Get-PlannerConfig
if ($Model) { $targets = @(Resolve-ModelName $Model) }
else { $targets = @(Get-InstalledModelNames | Where-Object { (Get-ModelProfile $_).role -eq 'agent' }) }
if ($targets.Count -eq 0) { throw 'No agent model is installed. Download one first: scripts\Get-Model.ps1' }

# The models of the /model picker share one context window per session: claude-local takes
# the smallest of them, so that switching cannot overflow a model. The default model is
# therefore planned first, and the other picker models get at least its context if they
# can (docs\planer.md).
$defaultModel = Get-DefaultAgentModel
$pickerModels = @(@((Get-AgentConfig).picker) | ForEach-Object { [string]$_.model })
$targets = @(@($targets | Where-Object { $_ -eq $defaultModel }) + @($targets | Where-Object { $_ -ne $defaultModel }))

function Get-SessionContext {
    # Context of the default model's plan, 0 if there is none.
    $plans = (Get-MachineConfig).PSObject.Properties['plans']
    if ($defaultModel -and $plans -and $plans.Value.PSObject.Properties[$defaultModel]) { return [int]$plans.Value.$defaultModel.ctx }
    return 0
}

if ($Show) {
    $plans = (Get-MachineConfig).PSObject.Properties['plans']
    foreach ($name in $targets) {
        if ($plans -and $plans.Value.PSObject.Properties[$name]) { "$name`: $($plans.Value.$name | ConvertTo-Json -Compress)" }
        else { "$name`: no plan yet" }
    }
    exit 0
}

$server = Get-ServerConfig
if (-not (Test-Path $server.exe)) { throw 'llama.cpp is not installed (scripts\Install-LlamaCpp.ps1).' }
if (Get-ServerProcess) { 'stopping llama-server, so that the cards are empty ...'; Stop-Server }

$devices = @(Get-UsableDevices (Get-LlamaDevices))
$ramGiB = Get-SystemMemoryGiB
$hostCap = ($ramGiB - [double]$cfg.ramReserveGiB) * 1024.0
foreach ($d in $devices) { "card $($d.id): $($d.name), $($d.freeMiB) MiB free of $($d.memoryMiB)" }
if ($devices.Count -eq 0) { 'no graphics card llama.cpp can use: the models run on the processor' }
"main memory: $ramGiB GB, of which the planner uses at most $(Format-GB $hostCap)"
$signature = ($devices | ForEach-Object { "$($_.id)=$($_.name)" }) -join ';'

function Get-Cards($Speed, [double]$Reserve) {
    return @($devices | ForEach-Object {
            $us = 1.0
            if ($Speed -and $Speed.ContainsKey([string]$_.id)) { $us = [double]$Speed[[string]$_.id] }
            [pscustomobject]@{ id = [string]$_.id; name = [string]$_.name; capMiB = [double]$_.freeMiB - $Reserve; usPerMiB = $us }
        })
}

function Invoke-Planning([string]$Name, [double]$Reserve) {
    # Calibrates if needed, plans, writes machine.json, prints the plan. Sets
    # $script:PlanMade (printed lines would mix into a return value).
    $script:PlanMade = $false
    ''
    if (-not (Test-ModelInstalled $Name)) { Write-Warning "$Name is not installed, skipped."; return }
    $info = Get-PlannerModel $Name $devices
    $saved = (Get-MachineConfig).PSObject.Properties['calibration']
    $cal = $null
    if (-not $Recalibrate -and $saved -and $saved.Value.PSObject.Properties[$Name] -and $saved.Value.$Name.devices -eq $signature) { $cal = $saved.Value.$Name }
    if (-not $cal) {
        "$Name`: calibrating with llama-bench (about half a minute) ..."
        $c = New-SpeedCalibration $info (Get-Cards $null $Reserve) $cfg $hostCap
        $cal = [pscustomobject]@{ date = (Get-Date -Format 's'); devices = $signature; dense = ($info.nExpert -eq 0); speed = [pscustomobject]$c.speed; uncertain = @($c.uncertain); runs = @($c.runs) }
        Set-MachineValue 'calibration' $Name $cal
        foreach ($r in $c.runs) { "  measured: $($r.devices) $($r.counts) -> $($r.tokensPerSecond) tokens/s" }
        if ($c.uncertain.Count -gt 0) { Write-Warning "calibration of $($c.uncertain -join ', ') unclear, assumed a twelfth of the main memory time per MiB" }
    }
    $speed = ConvertTo-Hashtable $cal.speed
    # The speed of a card is a property of the card. A mixture-of-experts model measures it
    # badly (its runs are bound by computing more than by memory), so the values a dense
    # model measured on the same cards are used if there are any (docs\planer.md).
    if ($info.nExpert -gt 0) {
        $all = (Get-MachineConfig).PSObject.Properties['calibration']
        foreach ($p in @($all.Value.PSObject.Properties)) {
            $other = $p.Value
            if ($p.Name -eq $Name -or -not $other.dense -or $other.devices -ne $signature) { continue }
            foreach ($d in $devices) {
                if ($other.speed.PSObject.Properties[[string]$d.id] -and @($other.uncertain) -notcontains [string]$d.id) { $speed[[string]$d.id] = [double]$other.speed.([string]$d.id) }
            }
            "  card speeds from the calibration of $($p.Name) (dense model, same cards)"
            break
        }
    }
    $speedText = @($speed.Keys | Sort-Object | ForEach-Object { '{0} {1:N2} us/MiB' -f $_, $speed[$_] }) -join ', '
    "  time per MiB read: $speedText"
    $cards = Get-Cards $speed $Reserve
    $planCfg = $cfg
    $session = Get-SessionContext
    if ($Name -ne $defaultModel -and $pickerModels -contains $Name -and $session -gt [int]$cfg.minCtx) {
        # at least the context of the default model, else every session would shrink to this one
        $planCfg = $cfg | ConvertTo-Json -Depth 5 | ConvertFrom-Json
        $planCfg.minCtx = $session
        "  context at least $session like $defaultModel (one window per session for all models of /model)"
    }
    $plan = New-ModelPlan $info $cards $speed $planCfg $hostCap
    if (-not $plan) { Write-Warning "$Name`: no placement fits into the graphics and main memory of this machine."; return }
    Set-MachineModelArgs $Name (ConvertTo-PlanArgs $plan)
    Set-MachineValue 'plans' $Name ([pscustomobject][ordered]@{
            date = (Get-Date -Format 's'); ctx = $plan.ctx; devices = ($plan.order -join ','); counts = ($plan.counts -join ',')
            ncmoe = $plan.ncmoe; mmproj = $plan.mmproj; allOnCards = $plan.allOnCards; reserveMiB = $Reserve
            predictedTokensPerSecond = [math]::Round(1000.0 / [math]::Max(0.001, $plan.ms), 1)
        })
    Write-Plan $Name $plan $cards $info
    $script:PlanMade = $true
}

$reserve = [double]$cfg.reserveMiB
$planned = @()
foreach ($name in $targets) {
    Invoke-Planning $name $reserve
    if ($script:PlanMade) { $planned += $name }
}

$failed = $targets.Count - $planned.Count
if ($Verify) {
    foreach ($name in $planned) {
        $myReserve = $reserve
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            ''
            "$name`: loading and testing the plan ..."
            Stop-Server
            $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-Model.ps1') -Model $name -NoLog 2>&1 | ForEach-Object { [string]$_ })
            $code = $LASTEXITCODE
            foreach ($line in $out) { "  $line" }
            $tps = @($out | Where-Object { $_ -match '^speed:\s*([\d.]+)' } | ForEach-Object { [double]$Matches[1] })
            if ($code -eq 0) {
                if ($tps) {
                    $plans = (Get-MachineConfig).plans
                    Set-ConfigValue $plans.$name 'measuredTokensPerSecond' $tps[0]
                    Set-MachineValue 'plans' $name $plans.$name
                }
                break
            }
            # A model that does not load, or whose process dies under a request (the server
            # answers 500), had too little memory: the estimate was too tight or something
            # else took memory at that moment. A wrong answer of the model is no memory matter.
            $memory = (@($out | Where-Object { $_ -match '^load:' }).Count -eq 0) -or (@($out | Where-Object { $_ -match '\(500\)' }).Count -gt 0)
            if (-not $memory -or $attempt -eq 3) { Write-Warning "$name`: the test failed (see above)."; $failed++; break }
            $myReserve += 1024
            Write-Warning "$name did not run stably; planning again with $myReserve MiB kept free per card."
            Stop-Server
            Set-MachineValue 'planner' 'reserveMiB' $myReserve
            Invoke-Planning $name $myReserve
        }
    }
    Stop-Server
}
if ($failed -gt 0) { exit 1 }
