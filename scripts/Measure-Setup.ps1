# Measures one hardware setup on this machine, to fill in "measured" in config\setups.json
# and to compare placements. Runs a model profile the way a machine with fewer or smaller
# graphics cards would: llama.cpp sees only some cards (CUDA_VISIBLE_DEVICES) and may keep
# memory free on them. The profile gets either the portable settings of config\models.json
# (llama.cpp places it by itself, --fit) or, with -Planned, the placement Plan-Models.ps1
# computes for exactly these cards; never the values tuned for this machine in
# config\machine.json. Stops the server before and after, so run it only while nobody else
# uses claude-local.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Measure-Setup.ps1 -Model local-fast -Cards 0 -CtxSize 65536
#   ... -Cards 1 -FitTargetMiB 4096     card 1 with 4 GB kept free, like a smaller card
#   ... -Cards none                      no graphics card: processor only
#   ... -Cards all                       every card (default)
#   ... -Planned                         placement by the planner (with -CtxSize: only that context)
#
# Prints the result of Test-Model.ps1, the prompt speed and the main memory the model process
# takes, and appends them to logs\model-tests.log under a header line that names the setup.

param(
    [Parameter(Mandatory = $true)][string]$Model,
    [string]$Cards = 'all',
    [int]$CtxSize = 0,
    [int]$FitTargetMiB = 0,
    [switch]$Planned
)

. "$PSScriptRoot\_common.ps1"

$Model = Resolve-ModelName $Model
if (-not (Test-ModelInstalled $Model)) { throw "Model '$Model' is not installed." }

# settings for this run: the folders of this machine, the profile without tuning
$machine = Get-MachineConfig
$run = [ordered]@{}
foreach ($section in 'server', 'projects') { if ($machine.PSObject.Properties[$section]) { $run[$section] = $machine.$section } }
$modelArgs = [ordered]@{}
if ($Planned) {
    # the planner keeps the extra memory free itself and may use only the given context
    $planner = [ordered]@{ reserveMiB = [double](Get-PlannerConfig).reserveMiB + $FitTargetMiB }
    if ($CtxSize -gt 0) { $planner['ctxCandidates'] = @($CtxSize); $planner['minCtx'] = $CtxSize }
    $run['planner'] = $planner
} else {
    if ($CtxSize -gt 0) { $modelArgs['ctx-size'] = $CtxSize }
    if ($FitTargetMiB -gt 0) { $modelArgs['fit-target'] = $FitTargetMiB }
}
$run['models'] = [ordered]@{ $Model = [ordered]@{ args = $modelArgs } }
$runFile = Join-Path $env:TEMP "claude-local-measure-$PID.json"
[System.IO.File]::WriteAllText($runFile, ($run | ConvertTo-Json -Depth 6))

$how = 'no machine tuning (--fit)'
if ($Planned) { $how = 'placement by Plan-Models.ps1' }
$header = "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  setup measurement: model $Model, cards $Cards, ctx-size $(if ($CtxSize) { $CtxSize } else { 'profile' }), kept free $(if ($FitTargetMiB) { "$FitTargetMiB MiB" } else { 'default' }), $how"
$header
$savedMachineFile = $env:CLAUDE_LOCAL_MACHINE_FILE
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($header)
Stop-Server
try {
    $env:CLAUDE_LOCAL_MACHINE_FILE = $runFile
    if ($Cards -eq 'none') { $env:CUDA_VISIBLE_DEVICES = '-1' }
    elseif ($Cards -ne 'all') { $env:CUDA_VISIBLE_DEVICES = $Cards }
    if ($Planned) {
        $plan = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Plan-Models.ps1') -Model $Model 2>&1 | ForEach-Object { [string]$_ })
        foreach ($line in $plan) { "  $line"; $lines.Add("  $line") }
        if ($LASTEXITCODE -ne 0) { throw 'Plan-Models.ps1 failed (see above).' }
    }
    Start-Server
    $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-Model.ps1') -Model $Model -NoLog 2>&1 | ForEach-Object { [string]$_ })
    foreach ($line in $out) { $line; $lines.Add($line) }
    # Claude Code starts every session with a prompt of about 20k tokens: how long reading
    # it takes matters as much as the answer speed when layers sit in main memory
    $read = Measure-PromptSpeed $Model
    $text = "prompt: $($read.promptTps) tokens/s ($($read.promptTokens) tokens read in $([math]::Round($read.promptTokens / [math]::Max($read.promptTps, 0.1))) s)"
    $text
    $lines.Add($text)
    # the model runs in a child process of the router. "private" is what it allocated itself
    # (weights placed in main memory, buffers); "resident" also counts the pages of the
    # memory-mapped model file, even those whose weights went to the graphics card
    $biggest = Get-ServerProcess | Sort-Object PrivateMemorySize64 -Descending | Select-Object -First 1
    if ($biggest) {
        $ram = "main memory of the model process: $([math]::Round($biggest.PrivateMemorySize64 / 1GB, 1)) GB private, $([math]::Round($biggest.WorkingSet64 / 1GB, 1)) GB resident"
        $ram
        $lines.Add($ram)
    }
} finally {
    Stop-Server
    Remove-Item Env:CUDA_VISIBLE_DEVICES -ErrorAction SilentlyContinue
    $env:CLAUDE_LOCAL_MACHINE_FILE = $savedMachineFile
    Remove-Item -Force -Path $runFile -ErrorAction SilentlyContinue
}
$logDir = Join-Path $script:ProjectRoot 'logs'
Add-Content -Path (Join-Path $logDir 'model-tests.log') -Value $lines -Encoding utf8
