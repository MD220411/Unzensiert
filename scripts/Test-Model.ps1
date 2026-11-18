# Quick check of one model profile: does it load, how fast is it, does tool calling work,
# can it read images, how much GPU memory does it take. Results are printed and appended to logs\model-tests.log.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Model.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Model.ps1 -Model schnell
#   ... -NoLog     do not append to logs\model-tests.log (the installer uses this: the log is
#                  part of the repository, and a changed file would block a later git pull)

param([string]$Model, [switch]$NoLog)

. "$PSScriptRoot\_common.ps1"

if (-not $Model) { $Model = Get-DefaultAgentModel }
if (-not $Model) { throw 'No model is installed. Run the installer or scripts\Get-Model.ps1 first.' }
$Model = Resolve-ModelName $Model
Start-Server

$lines = New-Object System.Collections.Generic.List[string]
function Out-Result([string]$text) { $lines.Add($text); $text }

Out-Result "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  model: $Model  (llama.cpp $((Get-ServerConfig).build), Claude Code $(Get-ClaudeCodeVersion))"

$loadSec = Wait-ModelLoaded $Model
Out-Result "load: $loadSec s"

$gen = Measure-Generation $Model
$mtp = 'off'
if ($null -ne $gen.draftAcceptance) { $mtp = "on, $([int]($gen.draftAcceptance * 100)) % of drafted tokens accepted" }
Out-Result "speed: $($gen.genTps) tokens/s  ($($gen.tokens) tokens, MTP $mtp)"
Out-Result "answer contains code: $($gen.hasCode)"

$tool = Test-ToolCall $Model
$word = 'FAILED'
if ($tool.ok) { $word = 'OK' }
Out-Result "tool calling: $word  ($($tool.detail))"

if ((Get-ModelProfile $Model).args.Contains('mmproj')) {
    $image = Test-ImageInput $Model
    $word = 'FAILED'
    if ($image.ok) { $word = 'OK' }
    Out-Result "image input: $word  ($($image.detail))"
} else {
    Out-Result 'image input: not configured  (profile has no mmproj, see docs\models.md)'
}

Out-Result "GPU memory used (MiB): $(Get-GpuMemory)"

$failed = @($lines | Where-Object { $_ -match ': FAILED' }).Count
if (-not $NoLog) {
    $logDir = Join-Path $script:ProjectRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Add-Content -Path (Join-Path $logDir 'model-tests.log') -Value $lines -Encoding utf8
}
if ($failed -gt 0) { exit 1 }
