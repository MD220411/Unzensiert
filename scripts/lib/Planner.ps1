# Computes how a model is best spread over the graphics cards and the main memory of this
# machine. Used by scripts\Plan-Models.ps1; tested without a graphics card by
# scripts\Test-Install.ps1. Details: docs\planner.md.
#
#   memory  For one placement, llama.cpp itself estimates how many MiB of weights, context
#           and compute buffers land on every device (llama-fit-params --fit-print). The
#           planner adds the image encoder and keeps "reserveMiB" free (config\planner.json).
#   speed   Every generated token reads all weights once (of a mixture-of-experts model only
#           the active experts), so the time per token is about
#               t = sum over devices of (MiB read there x microseconds per MiB of the device)
#           The microseconds per MiB are measured once per model with llama-bench and solved
#           from a small linear system (calibration).
#   search  Per context size: fill the fastest card first, then the next one. The fastest
#           card stands last in the device list, so it also gets the output layer. Of a
#           mixture-of-experts model, experts move to main memory before whole layers do.
#           Of all context sizes the largest is taken that is at most "speedTolerance"
#           slower than the fastest one.
#
# A placement is: order (device ids, slowest first, as for --device), counts (units per
# device in that order: one unit per layer, the output layer is one more unit at the end),
# ncmoe (the experts of the first N layers stay in main memory). Needs lib\Config.ps1 and
# lib\Machine.ps1. Keep this file ASCII-only.

$script:FitCache = @{}
# Tests put a script block here that stands in for llama-fit-params:
#   & $FitEstimator $Model $Ctx $Order $Counts $Ncmoe  ->  same result as Invoke-FitEstimate
$script:FitEstimator = $null

function Get-PlannerConfig {
    return (Read-Config 'planner')
}

function Get-LlamaTool([string]$Name) {
    # A program of the installed llama.cpp build, e.g. llama-fit-params.
    return (Join-Path (Get-ServerConfig).binDir "$Name.exe")
}

function Invoke-NativeLines([string]$Exe, [string[]]$Arguments, [switch]$WithErrors) {
    # Output lines of a native program. Windows PowerShell 5.1 turns stderr lines into
    # errors that stop the script under 'Stop', hence 'Continue' around the call.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($WithErrors) { $lines = @(& $Exe @Arguments 2>&1 | ForEach-Object { [string]$_ }) }
        else { $lines = @(& $Exe @Arguments 2>$null | ForEach-Object { [string]$_ }) }
    } finally {
        $ErrorActionPreference = $saved
    }
    return $lines
}

# --- what llama.cpp says about a model -----------------------------------------------------

function ConvertFrom-FitPrint([string[]]$Lines) {
    # Reads lines such as "CUDA0 8576 2540 1234" (device, model, context, compute in MiB).
    $result = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\s*(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $model = [double]$Matches[2]; $context = [double]$Matches[3]; $compute = [double]$Matches[4]
            $result[$Matches[1]] = [pscustomobject]@{ model = $model; context = $context; compute = $compute; total = $model + $context + $compute }
        }
    }
    return $result
}

function ConvertFrom-ModelMeta([string[]]$Lines) {
    # Layers and experts from the verbose output of llama.cpp ("print_info: n_layer_all = 65").
    $meta = @{ nLayerAll = 0; nExpert = 0; nExpertUsed = 0 }
    foreach ($line in $Lines) {
        if ($line -match 'print_info: n_layer_all\s*=\s*(\d+)') { $meta.nLayerAll = [int]$Matches[1] }
        elseif ($line -match 'print_info: n_layer\s*=\s*(\d+)' -and $meta.nLayerAll -eq 0) { $meta.nLayerAll = [int]$Matches[1] }
        elseif ($line -match 'print_info: n_expert\s*=\s*(\d+)') { $meta.nExpert = [int]$Matches[1] }
        elseif ($line -match 'print_info: n_expert_used\s*=\s*(\d+)') { $meta.nExpertUsed = [int]$Matches[1] }
    }
    return $meta
}

function Get-EstimateTotal($Estimate, [string]$Id) {
    if ($Estimate.ContainsKey($Id)) { return [double]$Estimate[$Id].total }
    return 0.0
}

function Invoke-FitEstimate($Model, [int]$Ctx, [string[]]$Order, [int[]]$Counts, [int]$Ncmoe) {
    # Estimated MiB per device for one placement: @{ CUDA0 = {model, context, compute, total};
    # Host = {...} }. Results are kept, every call of llama-fit-params takes about half a second.
    $ngl = 0
    foreach ($c in $Counts) { $ngl += $c }
    $key = '{0}|{1}|{2}|{3}|{4}|{5}' -f $Model.file, $Ctx, ($Order -join ','), ($Counts -join ','), $Ncmoe, ($Model.memArgs -join ' ')
    if ($script:FitCache.ContainsKey($key)) { return $script:FitCache[$key] }
    if ($script:FitEstimator) {
        $result = & $script:FitEstimator $Model $Ctx $Order $Counts $Ncmoe
    } else {
        $a = @('-m', $Model.file, '-fit', 'off', '-c', [string]$Ctx, '--fit-print', 'on') + @($Model.memArgs)
        if ($ngl -gt 0) { $a += @('-ngl', [string]$ngl, '-dev', ($Order -join ','), '-ts', ($Counts -join ',')) }
        else { $a += @('-ngl', '0') }
        if ($Ncmoe -gt 0) { $a += @('-ncmoe', [string]$Ncmoe) }
        $result = ConvertFrom-FitPrint (Invoke-NativeLines (Get-LlamaTool 'llama-fit-params') $a)
        if (-not $result.ContainsKey('Host')) { throw "llama-fit-params gave no estimate for $($Model.name) ($($a -join ' '))." }
    }
    $script:FitCache[$key] = $result
    return $result
}

function Get-PlannerModel([string]$Name, $Devices) {
    # What the planner needs to know about a profile: the file, the options that change the
    # memory (taken from the profile, so the plan matches what the server starts), layers,
    # experts, the size of the image encoder, the expert MiB per layer and the MiB the host
    # always keeps but never reads per token (the token embedding).
    $prof = Get-ModelProfile $Name
    $memArgs = @()
    foreach ($pair in @(@('flash-attn', '-fa'), @('cache-type-k', '-ctk'), @('cache-type-v', '-ctv'), @('parallel', '-np'))) {
        if ($prof.args.Contains($pair[0])) { $memArgs += @($pair[1], [string]$prof.args[$pair[0]]) }
    }
    $cfg = Get-PlannerConfig
    $model = [pscustomobject]@{
        name = $Name; file = $prof.path; memArgs = $memArgs
        nLayerAll = 0; nExpert = 0; nExpertUsed = 0; activeFraction = 1.0
        expertMiB = 0.0; hostBaseMiB = 0.0; mmprojMiB = 0.0; mtpMiB = 0.0; draftMiB = 0.0; ubatch = 0
    }
    if ($prof.args.Contains('mmproj') -and (Test-Path $prof.args['mmproj'])) {
        $model.mmprojMiB = [math]::Ceiling((Get-Item $prof.args['mmproj']).Length / 1MB) + [double]$cfg.mmprojExtraMiB
    }
    # guessing ahead with the MTP layer needs memory of its own on the card with the last layers
    if ($prof.args.Contains('spec-type') -and [string]$prof.args['spec-type'] -match 'mtp') { $model.mtpMiB = [double]$cfg.mtpReserveMiB }
    # an MTP head in a file of its own (spec-draft-model) goes to that card as well
    if ($prof.args.Contains('spec-draft-model') -and (Test-Path $prof.args['spec-draft-model'])) {
        $model.draftMiB = [math]::Ceiling((Get-Item $prof.args['spec-draft-model']).Length / 1MB)
        $model.mtpMiB += $model.draftMiB
    }
    if ($script:FitEstimator) { $meta = & $script:FitEstimator $model 'meta' $null $null 0 }
    else { $meta = ConvertFrom-ModelMeta (Invoke-NativeLines (Get-LlamaTool 'llama-fit-params') @('-m', $prof.path, '-c', '512', '-fit', 'off', '-ngl', '0', '--fit-print', 'on', '-v') -WithErrors) }
    if ($meta.nLayerAll -le 0) { throw "llama-fit-params did not report the layers of $($prof.path)." }
    $model.nLayerAll = $meta.nLayerAll
    $model.nExpert = $meta.nExpert
    $model.nExpertUsed = $meta.nExpertUsed
    if ($meta.nExpert -gt 0 -and $meta.nExpertUsed -gt 0) { $model.activeFraction = $meta.nExpertUsed / [double]$meta.nExpert }
    $cards = @($Devices)
    if ($cards.Count -gt 0) {
        # everything on one card (whether it fits does not matter for an estimate): what the
        # host keeps then is never read per token; moving all experts to the host shows
        # their size per layer
        $id = [string]$cards[0].id
        $units = $model.nLayerAll + 1
        $all = Invoke-FitEstimate $model 4096 @($id) @($units) 0
        $model.hostBaseMiB = [double]$all['Host'].model
        if ($model.nExpert -gt 0) {
            $noExperts = Invoke-FitEstimate $model 4096 @($id) @($units) $model.nLayerAll
            $model.expertMiB = [math]::Max(0.0, ([double]$noExperts['Host'].model - $model.hostBaseMiB) / $model.nLayerAll)
        }
    }
    return $model
}

# --- where the layers are and what is read per token -------------------------------------

function Get-PlacementLayout($Model, [int[]]$Counts, [int]$Ncmoe) {
    # llama.cpp keeps the first layers on the host and hands the offloaded ones to the cards
    # in --device order. The output layer is one more unit at the end and goes to a card
    # only if every layer is offloaded. Returns how many layers keep their experts on each
    # card and on the host.
    $n = $Model.nLayerAll
    $ngl = 0
    foreach ($c in $Counts) { $ngl += $c }
    $outputOnCard = $ngl -gt $n
    $cpuLayers = $n - [math]::Min($ngl, $n)
    $lastCard = -1
    for ($j = $Counts.Count - 1; $j -ge 0; $j--) { if ($Counts[$j] -gt 0) { $lastCard = $j; break } }
    $experts = New-Object int[] $Counts.Count
    $start = $cpuLayers
    for ($j = 0; $j -lt $Counts.Count; $j++) {
        $layers = $Counts[$j]
        if ($outputOnCard -and $j -eq $lastCard) { $layers -= 1 }
        $end = $start + $layers
        $experts[$j] = [math]::Max(0, $end - [math]::Max($start, $Ncmoe))
        $start = $end
    }
    return @{ cpuLayers = $cpuLayers; outputOnCard = $outputOnCard; expertsByDevice = $experts; expertsHost = [math]::Min($n, [math]::Max($cpuLayers, $Ncmoe)) }
}

function Get-PlacementReads($Model, [string[]]$Order, [int[]]$Counts, [int]$Ncmoe, $Estimate) {
    # MiB read per generated token on every device ('Host' = main memory): the weights there,
    # less the experts that are not active and less what the host only stores.
    $layout = Get-PlacementLayout $Model $Counts $Ncmoe
    $idle = (1.0 - $Model.activeFraction) * $Model.expertMiB
    $reads = @{}
    for ($j = 0; $j -lt $Order.Count; $j++) {
        if ($Counts[$j] -gt 0 -and $Estimate.ContainsKey($Order[$j])) {
            $reads[$Order[$j]] = [math]::Max(0.0, [double]$Estimate[$Order[$j]].model - $idle * $layout.expertsByDevice[$j])
        }
    }
    $reads['Host'] = [math]::Max(0.0, [double]$Estimate['Host'].model - $Model.hostBaseMiB - $idle * $layout.expertsHost)
    return $reads
}

function Get-PlacementMs($Reads, $Speed) {
    # Predicted milliseconds per token: MiB read per device times microseconds per MiB.
    $us = 0.0
    foreach ($id in $Reads.Keys) {
        if ($Speed.ContainsKey($id)) { $us += [double]$Reads[$id] * [double]$Speed[$id] }
    }
    return $us / 1000.0
}

# --- search --------------------------------------------------------------------------------

function Get-LastCardIndex([int[]]$Counts) {
    # The card with the last layers: it also holds the MTP layer (and the output layer, if
    # every layer is offloaded).
    for ($j = $Counts.Count - 1; $j -ge 0; $j--) { if ($Counts[$j] -gt 0) { return $j } }
    return -1
}

function Get-CardNeed($Model, $Estimate, [string[]]$Ids, [int[]]$Counts, [int]$Index, [int]$DraftIndex = -1) {
    # MiB a card needs for a placement: the estimate of llama.cpp, plus the MTP draft: on the
    # card with the last layers when the MTP layer is part of the model, on card $DraftIndex
    # (the fastest) when it is a file of its own. The image encoder comes later
    # (Select-MmprojDevice).
    $need = Get-EstimateTotal $Estimate $Ids[$Index]
    $at = Get-LastCardIndex $Counts
    if ($Model.PSObject.Properties['draftMiB'] -and $Model.draftMiB -gt 0 -and $DraftIndex -ge 0) { $at = $DraftIndex }
    if ($Model.mtpMiB -gt 0 -and $Index -eq $at) { $need += $Model.mtpMiB }
    return $need
}

function Test-CardFits($Model, $Estimate, $Order, [int[]]$Counts, [int]$Index, [int]$DraftIndex = -1) {
    $ids = [string[]]@($Order | ForEach-Object { [string]$_.id })
    return ((Get-CardNeed $Model $Estimate $ids $Counts $Index $DraftIndex) -le [double]$Order[$Index].capMiB)
}

function Find-Placement($Model, $Cards, [int]$Ctx, [int]$Ncmoe, [bool]$FastFirst = $false) {
    # Fills the fastest card first. Cards: objects with id, capMiB, usPerMiB. The fastest card
    # stands last in the device order, so it also gets the output layer and the MTP layer;
    # with $FastFirst it stands first and takes the first layers, those whose experts stay in
    # main memory (Plan-Models.ps1 measures which order is faster). Returns order, counts,
    # ncmoe, allOnCards (every layer and the output layer on a card), fastFirst and
    # draftIndex (the fastest card, which takes a draft model of its own).
    $order = @(@($Cards) | Sort-Object -Property @{ Expression = { [double]$_.usPerMiB }; Descending = (-not $FastFirst) }, @{ Expression = { [string]$_.id } })
    $ids = [string[]]@($order | ForEach-Object { [string]$_.id })
    $n = $order.Count
    if ($n -eq 0) { return [pscustomobject]@{ order = [string[]]@(); counts = [int[]]@(); ncmoe = 0; allOnCards = $false; fastFirst = $FastFirst; draftIndex = -1 } }
    $units = $Model.nLayerAll + 1
    # positions in the device order from the fastest card to the slowest
    $bySpeed = @(($n - 1)..0)
    if ($FastFirst) { $bySpeed = @(0..($n - 1)) }
    $fastest = $bySpeed[0]
    $rest = $bySpeed[-1]

    # A: every unit on a card. The cards from the fastest on take as many as fit while the
    # rest waits on the slowest card; only the slowest card can then be too full.
    $counts = New-Object int[] $n
    $left = $units
    foreach ($i in $bySpeed) {
        if ($i -eq $rest) { continue }
        $lo = 0; $hi = $left
        while ($lo -lt $hi) {
            $mid = [int][math]::Ceiling(($lo + $hi) / 2.0)
            $try = [int[]]$counts.Clone()
            $try[$i] = $mid
            $try[$rest] = $left - $mid
            if (Test-CardFits $Model (Invoke-FitEstimate $Model $Ctx $ids $try $Ncmoe) $order $try $i $fastest) { $lo = $mid } else { $hi = $mid - 1 }
        }
        $counts[$i] = $lo
        $left -= $lo
    }
    $counts[$rest] = $left
    $estimate = Invoke-FitEstimate $Model $Ctx $ids $counts $Ncmoe
    $fits = $true
    for ($j = 0; $j -lt $n; $j++) { if (-not (Test-CardFits $Model $estimate $order $counts $j $fastest)) { $fits = $false } }
    if ($fits) { return [pscustomobject]@{ order = $ids; counts = [int[]]$counts; ncmoe = $Ncmoe; allOnCards = $true; fastFirst = $FastFirst; draftIndex = $fastest } }

    # B: not everything fits. The output layer and the first layers stay on the host; the
    # cards take layers from the fastest on, each as many as fit.
    $counts = New-Object int[] $n
    $left = $Model.nLayerAll
    foreach ($i in $bySpeed) {
        $lo = 0; $hi = $left
        while ($lo -lt $hi) {
            $mid = [int][math]::Ceiling(($lo + $hi) / 2.0)
            $try = [int[]]$counts.Clone()
            $try[$i] = $mid
            if (Test-CardFits $Model (Invoke-FitEstimate $Model $Ctx $ids $try $Ncmoe) $order $try $i $fastest) { $lo = $mid } else { $hi = $mid - 1 }
        }
        $counts[$i] = $lo
        $left -= $lo
    }
    return [pscustomobject]@{ order = $ids; counts = [int[]]$counts; ncmoe = $Ncmoe; allOnCards = $false; fastFirst = $FastFirst; draftIndex = $fastest }
}

function Find-BestPlacement($Model, $Cards, [int]$Ctx, [bool]$FastFirst = $false) {
    # Dense model: Find-Placement. Mixture of experts: the fewest layers whose experts go to
    # the host so that every layer itself stays on a card; reading the few active experts
    # from main memory costs far less than reading whole layers from there.
    $plain = Find-Placement $Model $Cards $Ctx 0 $FastFirst
    if ($plain.allOnCards -or $Model.expertMiB -le 0 -or @($Cards).Count -eq 0) { return $plain }
    $most = Find-Placement $Model $Cards $Ctx $Model.nLayerAll $FastFirst
    if (-not $most.allOnCards) { return $most }
    $lo = 1; $hi = $Model.nLayerAll
    while ($lo -lt $hi) {
        $mid = [int][math]::Floor(($lo + $hi) / 2.0)
        if ((Find-Placement $Model $Cards $Ctx $mid $FastFirst).allOnCards) { $hi = $mid } else { $lo = $mid + 1 }
    }
    return (Find-Placement $Model $Cards $Ctx $lo $FastFirst)
}

function Select-MmprojDevice($Model, $Cards, $Placement, $Estimate) {
    # The image encoder goes to the card with the most room left, if it fits there next to
    # the model; otherwise to the host ('cpu'). '' if the profile has none.
    if ($Model.mmprojMiB -le 0) { return '' }
    $best = ''
    $bestRoom = -1.0
    for ($j = 0; $j -lt $Placement.order.Count; $j++) {
        $card = @($Cards | Where-Object { $_.id -eq $Placement.order[$j] })[0]
        $room = [double]$card.capMiB - (Get-CardNeed $Model $Estimate $Placement.order $Placement.counts $j ([int]$Placement.draftIndex))
        if ($room -ge $Model.mmprojMiB -and $room -gt $bestRoom) { $best = [string]$card.id; $bestRoom = $room }
    }
    if ($best) { return $best }
    return 'cpu'
}

function Get-PlanNeeds($Model, $Plan) {
    # MiB every card needs for a finished plan, image encoder included (for the report).
    $needs = @{}
    for ($j = 0; $j -lt $Plan.order.Count; $j++) {
        $need = Get-CardNeed $Model $Plan.estimate $Plan.order $Plan.counts $j ([int]$Plan.draftIndex)
        if ($Plan.mmproj -eq $Plan.order[$j]) { $need += $Model.mmprojMiB }
        $needs[$Plan.order[$j]] = $need
    }
    return $needs
}

function New-ModelPlan($Model, $Cards, $Speed, $Cfg, [double]$HostCapMiB, [bool]$FastFirst = $false) {
    # The plan for one model: every context size from ctxCandidates is placed and timed;
    # among those of at least minCtx (or, if none fits, all) the largest one is taken whose
    # time is at most speedTolerance above the fastest. $null if nothing fits. $FastFirst: the
    # fastest card first in the device order (Find-Placement). The batch size the model was
    # estimated with ($Model.ubatch, 0 = the default of llama.cpp) goes into the plan.
    $found = @()
    foreach ($ctx in @($Cfg.ctxCandidates | ForEach-Object { [int]$_ } | Sort-Object -Descending)) {
        $p = Find-BestPlacement $Model $Cards $ctx $FastFirst
        $est = Invoke-FitEstimate $Model $ctx $p.order $p.counts $p.ncmoe
        if ((Get-EstimateTotal $est 'Host') -gt $HostCapMiB) { continue }
        $reads = Get-PlacementReads $Model $p.order $p.counts $p.ncmoe $est
        $found += [pscustomobject]@{
            ctx = $ctx; order = $p.order; counts = $p.counts; ncmoe = $p.ncmoe; allOnCards = $p.allOnCards
            fastFirst = $p.fastFirst; draftIndex = $p.draftIndex
            estimate = $est; reads = $reads; ms = (Get-PlacementMs $reads $Speed); mmproj = ''
        }
    }
    if ($found.Count -eq 0) { return $null }
    $pool = @($found | Where-Object { $_.ctx -ge [int]$Cfg.minCtx })
    if ($pool.Count -eq 0) { $pool = $found }
    $fastest = ($pool | Measure-Object -Property ms -Minimum).Minimum
    $plan = @($pool | Where-Object { $_.ms -le $fastest * (1.0 + [double]$Cfg.speedTolerance) } | Sort-Object ctx -Descending)[0]
    $plan.mmproj = Select-MmprojDevice $Model $Cards $plan $plan.estimate
    # a draft model of its own goes to the fastest card
    $draftDevice = ''
    if ($Model.PSObject.Properties['draftMiB'] -and $Model.draftMiB -gt 0 -and $plan.draftIndex -ge 0) { $draftDevice = [string]$plan.order[$plan.draftIndex] }
    $ubatch = 0
    if ($Model.PSObject.Properties['ubatch']) { $ubatch = [int]$Model.ubatch }
    $plan | Add-Member -NotePropertyName draftDevice -NotePropertyValue $draftDevice
    $plan | Add-Member -NotePropertyName ubatch -NotePropertyValue $ubatch
    $plan | Add-Member -NotePropertyName candidates -NotePropertyValue $found
    return $plan
}

function Copy-PlannerModel($Model, [int]$Ubatch) {
    # The same model, estimated and measured with another batch size for reading the prompt
    # (ubatch-size and batch-size); 0 = the default of llama.cpp.
    $copy = $Model.PSObject.Copy()
    $memArgs = @()
    for ($i = 0; $i -lt @($Model.memArgs).Count; $i += 2) {
        if (@('-ub', '-b') -notcontains $Model.memArgs[$i]) { $memArgs += @($Model.memArgs[$i], $Model.memArgs[$i + 1]) }
    }
    if ($Ubatch -gt 0) { $memArgs += @('-ub', [string]$Ubatch, '-b', [string]$Ubatch) }
    $copy.memArgs = $memArgs
    if ($copy.PSObject.Properties['ubatch']) { $copy.ubatch = $Ubatch } else { $copy | Add-Member -NotePropertyName ubatch -NotePropertyValue $Ubatch }
    return $copy
}

function Select-PlanVariant($Variants, [double]$ReadPerWritten) {
    # The variant with the least time per written token, counting the tokens read with it:
    # 1/writing + ReadPerWritten/reading (tokens per second as llama-bench measured them).
    $best = $null
    $bestScore = [double]::MaxValue
    foreach ($v in @($Variants)) {
        if ($v.tg -le 0 -or $v.pp -le 0) { continue }
        $score = 1.0 / [double]$v.tg + $ReadPerWritten / [double]$v.pp
        if ($score -lt $bestScore) { $best = $v; $bestScore = $score }
    }
    return $best
}

function Get-CacheRamMiB($Plan, $Cfg, [double]$HostCapMiB, [int]$ModelsMax) {
    # Limit of the cache of earlier conversations in main memory (--cache-ram) for a plan:
    # what is left of the main memory after the model's own share there, shared by the
    # models that can be loaded at once, at most cacheRamMaxGiB, in whole GiB. 0 if that is
    # not more than the llama.cpp default of 8 GiB: then the option stays out.
    $maxMiB = 0.0
    if ($Cfg.PSObject.Properties['cacheRamMaxGiB']) { $maxMiB = [double]$Cfg.cacheRamMaxGiB * 1024.0 }
    $freeMiB = ($HostCapMiB - (Get-EstimateTotal $Plan.estimate 'Host')) / [math]::Max(1, $ModelsMax)
    $mib = [math]::Floor([math]::Min($freeMiB, $maxMiB) / 1024.0) * 1024
    if ($mib -le 8192) { return 0 }
    return [int]$mib
}

function Clear-ModelPlan([string]$Name) {
    # Takes the options of a plan out of config\machine.json again, so llama.cpp places the
    # model by itself (--fit); the context size stays. Used when a plan does not work.
    $values = [ordered]@{}
    foreach ($key in 'fit', 'gpu-layers', 'device', 'tensor-split', 'n-cpu-moe', 'mmproj-device', 'mmproj-offload', 'cache-ram', 'spec-draft-device', 'spec-draft-ngl', 'ubatch-size', 'batch-size') { $values[$key] = $null }
    Set-MachineModelArgs $Name $values
    $machine = Get-MachineConfig
    if ($machine.PSObject.Properties['plans'] -and $machine.plans.PSObject.Properties[$Name]) {
        $machine.plans.PSObject.Properties.Remove($Name)
        Save-MachineConfig $machine
    }
}

function ConvertTo-PlanArgs($Plan) {
    # The llama-server options of a plan, for config\machine.json. $null removes an option
    # a former plan or a hand-made setting had set. "fit = off": the server must not move
    # anything on its own, the plan already accounts for the memory.
    $ngl = 0
    foreach ($c in $Plan.counts) { $ngl += $c }
    $a = [ordered]@{ 'ctx-size' = [int]$Plan.ctx; 'fit' = 'off'; 'gpu-layers' = $ngl }
    if ($ngl -gt 0) { $a['device'] = ($Plan.order -join ','); $a['tensor-split'] = ($Plan.counts -join ',') }
    else { $a['device'] = $null; $a['tensor-split'] = $null }
    if ($Plan.ncmoe -gt 0) { $a['n-cpu-moe'] = [int]$Plan.ncmoe } else { $a['n-cpu-moe'] = $null }
    if ($Plan.mmproj -eq 'cpu') { $a['mmproj-device'] = $null; $a['mmproj-offload'] = $false }
    elseif ($Plan.mmproj) { $a['mmproj-device'] = $Plan.mmproj; $a['mmproj-offload'] = $null }
    else { $a['mmproj-device'] = $null; $a['mmproj-offload'] = $null }
    if ($Plan.PSObject.Properties['cacheRamMiB'] -and [int]$Plan.cacheRamMiB -gt 0) { $a['cache-ram'] = [int]$Plan.cacheRamMiB } else { $a['cache-ram'] = $null }
    if ($Plan.PSObject.Properties['draftDevice'] -and $Plan.draftDevice) { $a['spec-draft-device'] = [string]$Plan.draftDevice; $a['spec-draft-ngl'] = 'all' }
    else { $a['spec-draft-device'] = $null; $a['spec-draft-ngl'] = $null }
    if ($Plan.PSObject.Properties['ubatch'] -and [int]$Plan.ubatch -gt 0) { $a['ubatch-size'] = [int]$Plan.ubatch; $a['batch-size'] = [int]$Plan.ubatch }
    else { $a['ubatch-size'] = $null; $a['batch-size'] = $null }
    return $a
}

# --- calibration ---------------------------------------------------------------------------

function Invoke-BenchSpeed($Model, [string[]]$Order, [int[]]$Counts, [int]$Ncmoe, [int]$Tokens, [int]$Repetitions) {
    # Tokens per second llama-bench measures for one placement (generation only, no MTP).
    $ngl = 0
    foreach ($c in $Counts) { $ngl += $c }
    $a = @('-m', $Model.file, '-p', '0', '-n', [string]$Tokens, '-r', [string]$Repetitions, '-o', 'jsonl')
    for ($i = 0; $i -lt $Model.memArgs.Count; $i += 2) {
        if ($Model.memArgs[$i] -ne '-np') { $a += @($Model.memArgs[$i], $Model.memArgs[$i + 1]) }
    }
    if ($ngl -gt 0) { $a += @('-ngl', [string]$ngl, '-dev', ($Order -join '/'), '-ts', ($Counts -join '/')) }
    else { $a += @('-ngl', '0') }
    if ($Ncmoe -gt 0) { $a += @('-ncmoe', [string]$Ncmoe) }
    foreach ($line in (Invoke-NativeLines (Get-LlamaTool 'llama-bench') $a)) {
        if ($line -match '^\s*\{') {
            $r = $line | ConvertFrom-Json
            if ($r.avg_ts) { return [double]$r.avg_ts }
        }
    }
    throw "llama-bench gave no result for $($Model.name) ($($a -join ' '))."
}

function Invoke-BenchPair($Model, [string[]]$Order, [int[]]$Counts, [int]$Ncmoe, [int]$Tokens, [int]$PromptTokens, [int]$Repetitions) {
    # Writing and reading speed llama-bench measures for one placement, with the batch sizes
    # of $Model (Copy-PlannerModel): @{ tg; pp } in tokens per second (no MTP).
    $ngl = 0
    foreach ($c in $Counts) { $ngl += $c }
    $a = @('-m', $Model.file, '-p', [string]$PromptTokens, '-n', [string]$Tokens, '-r', [string]$Repetitions, '-o', 'jsonl')
    for ($i = 0; $i -lt @($Model.memArgs).Count; $i += 2) {
        if ($Model.memArgs[$i] -ne '-np') { $a += @($Model.memArgs[$i], $Model.memArgs[$i + 1]) }
    }
    if ($ngl -gt 0) { $a += @('-ngl', [string]$ngl, '-dev', ($Order -join '/'), '-ts', ($Counts -join '/')) }
    else { $a += @('-ngl', '0') }
    if ($Ncmoe -gt 0) { $a += @('-ncmoe', [string]$Ncmoe) }
    $result = @{ tg = 0.0; pp = 0.0 }
    foreach ($line in (Invoke-NativeLines (Get-LlamaTool 'llama-bench') $a)) {
        if ($line -notmatch '^\s*\{') { continue }
        $r = $line | ConvertFrom-Json
        if (-not $r.avg_ts) { continue }
        if ([int]$r.n_prompt -gt 0 -and [int]$r.n_gen -eq 0) { $result.pp = [double]$r.avg_ts }
        elseif ([int]$r.n_gen -gt 0) { $result.tg = [double]$r.avg_ts }
    }
    if ($result.tg -le 0 -or $result.pp -le 0) { throw "llama-bench gave no result for $($Model.name) ($($a -join ' '))." }
    return $result
}

function Solve-LinearSystem([double[][]]$A, [double[]]$B) {
    # Gaussian elimination with pivoting for the few unknowns of the calibration.
    $n = $B.Count
    $m = @()
    for ($r = 0; $r -lt $n; $r++) { $m += , ([double[]]($A[$r] + @($B[$r]))) }
    for ($c = 0; $c -lt $n; $c++) {
        $pivot = $c
        for ($r = $c + 1; $r -lt $n; $r++) { if ([math]::Abs($m[$r][$c]) -gt [math]::Abs($m[$pivot][$c])) { $pivot = $r } }
        if ([math]::Abs($m[$pivot][$c]) -lt 1e-12) { return $null }
        $tmp = $m[$c]; $m[$c] = $m[$pivot]; $m[$pivot] = $tmp
        for ($r = 0; $r -lt $n; $r++) {
            if ($r -eq $c) { continue }
            $f = $m[$r][$c] / $m[$c][$c]
            for ($k = $c; $k -le $n; $k++) { $m[$r][$k] -= $f * $m[$c][$k] }
        }
    }
    $x = New-Object double[] $n
    for ($r = 0; $r -lt $n; $r++) { $x[$r] = $m[$r][$n] / $m[$r][$r] }
    return $x
}

function ConvertFrom-CalibrationRuns($CpuRun, $CardRuns, [string[]]$Ids) {
    # Microseconds per MiB of every device from measured runs.
    #   CpuRun:   @{ reads = @{ Host = MiB }; tps = tokens/s }  (everything on the host)
    #   CardRuns: one per card, @{ reads = @{ <id> = MiB; Host = MiB }; tps }
    # The host comes from the first run; for the cards, every run is one equation
    #   sum over cards (MiB read on the card x unknown) = time per token - host part
    # Values that make no sense (a card slower than the host, or below zero, which happens
    # when the host part hides the card) fall back to a twelfth of the host value.
    $hostUs = (1e6 / [double]$CpuRun.tps) / [math]::Max(1.0, [double]$CpuRun.reads['Host'])
    $speed = @{ Host = $hostUs }
    $uncertain = @()
    $n = $Ids.Count
    if ($n -gt 0) {
        $rows = @(); $rhs = @()
        foreach ($run in $CardRuns) {
            $row = New-Object double[] $n
            for ($j = 0; $j -lt $n; $j++) { if ($run.reads.ContainsKey($Ids[$j])) { $row[$j] = [double]$run.reads[$Ids[$j]] } }
            $hostPart = 0.0
            if ($run.reads.ContainsKey('Host')) { $hostPart = [double]$run.reads['Host'] * $hostUs }
            $rows += , $row
            $rhs += (1e6 / [double]$run.tps) - $hostPart
        }
        $x = Solve-LinearSystem ([double[][]]$rows) ([double[]]$rhs)
        for ($j = 0; $j -lt $n; $j++) {
            $v = 0.0
            if ($x) { $v = [double]$x[$j] }
            if ($v -le 0 -or $v -ge $hostUs) { $v = $hostUs / 12.0; $uncertain += $Ids[$j] }
            $speed[$Ids[$j]] = $v
        }
    }
    return @{ speed = $speed; uncertain = $uncertain }
}

function New-SpeedCalibration($Model, $Cards, $Cfg, [double]$HostCapMiB) {
    # Measures the model with llama-bench: once on the host alone, then once per card with
    # that card filled first (placement as Find-BestPlacement would make it, with a small
    # context). Returns @{ speed = @{ Host = us; <id> = us }; uncertain; runs }.
    $bench = $Cfg.bench
    $runs = @()
    $est = Invoke-FitEstimate $Model 4096 @() @() 0
    $cpuReads = Get-PlacementReads $Model @() @() 0 $est
    if ((Get-EstimateTotal $est 'Host') -le $HostCapMiB) {
        $tps = Invoke-BenchSpeed $Model @() @() 0 ([int]$bench.cpuTokens) 1
    } else {
        # the model does not fit into main memory: assume a typical value instead (docs\planner.md)
        $tps = 1e6 / (25.0 * [math]::Max(1.0, [double]$cpuReads['Host']))
    }
    $cpuRun = @{ reads = $cpuReads; tps = $tps }
    $runs += [pscustomobject]@{ devices = 'host'; counts = ''; ncmoe = 0; tokensPerSecond = [math]::Round($tps, 2) }
    $ids = [string[]]@(@($Cards) | ForEach-Object { [string]$_.id })
    $cardRuns = @()
    for ($j = 0; $j -lt $ids.Count; $j++) {
        # pretend card j is the fastest, so that it is filled first
        $pretend = @()
        for ($k = 0; $k -lt $ids.Count; $k++) {
            $us = 2.0 + $k
            if ($k -eq $j) { $us = 1.0 }
            $pretend += [pscustomobject]@{ id = $ids[$k]; capMiB = @($Cards)[$k].capMiB; usPerMiB = $us }
        }
        $p = Find-BestPlacement $Model $pretend 4096
        $e = Invoke-FitEstimate $Model 4096 $p.order $p.counts $p.ncmoe
        $reads = Get-PlacementReads $Model $p.order $p.counts $p.ncmoe $e
        $t = Invoke-BenchSpeed $Model $p.order $p.counts $p.ncmoe ([int]$bench.tokens) ([int]$bench.repetitions)
        $cardRuns += @{ reads = $reads; tps = $t }
        $runs += [pscustomobject]@{ devices = ($p.order -join ','); counts = ($p.counts -join ','); ncmoe = $p.ncmoe; tokensPerSecond = [math]::Round($t, 2) }
    }
    $solved = ConvertFrom-CalibrationRuns $cpuRun $cardRuns $ids
    return @{ speed = $solved.speed; uncertain = $solved.uncertain; runs = $runs }
}
