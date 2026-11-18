# Second look: a second local model (default local-qwen38, "review" in config\agent.json)
# checks the uncommitted change of a git project in a fresh context and lists errors and
# hints. The closing check of claude-local starts it after larger changes; it also works
# by hand. Changes nothing in the project. Description: docs\agent.md.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Invoke-Review.ps1 -Folder E:\Projekte\mein-tool
#   ... -Task "What the change was meant to do"     (otherwise taken from -Transcript)
#   ... -Model local-coder                           (another reviewer)
#   ... -Json                                        (one JSON object, for the hook)
#
# Exit code 0 = no error found (or nothing to review), 1 = at least one error found,
# 2 = the review could not run (server, model, timeout). Every review is logged in
# <installRoot>\logs\review.log.

param(
    [string]$Folder = (Get-Location).Path,
    [string]$Task,
    [string]$Transcript,
    [string]$Model,
    [int]$MinLines = 0,
    [switch]$Json
)

. "$PSScriptRoot\_common.ps1"

if (-not (Get-ReviewSettings)) {
    [Console]::Error.WriteLine('No "review" block in config\agent.json.')
    exit 2
}
$Folder = (Resolve-Path $Folder).Path
if (-not $Task -and $Transcript) { $Task = Get-LastUserPrompt $Transcript }
if ($Model) { $Model = Resolve-ModelName $Model }

$result = Invoke-Review $Folder $Task $Model $MinLines

if ($Json) {
    $text = $result | ConvertTo-Json -Compress -Depth 4
    # ASCII only, so that no console code page can damage the answer
    [Console]::Out.Write([regex]::Replace($text, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value }))
} else {
    "review    $($result.status)  ($($result.model), $($result.lines) changed lines, $($result.seconds) s)"
    if ($result.reason) { "reason    $($result.reason)" }
    foreach ($e in $result.errors) { "ERROR     $e" }
    foreach ($h in $result.hints) { "HINT      $h" }
}

if ($result.status -eq 'error') { exit 2 }
if ($result.errors.Count -gt 0) { exit 1 }
exit 0
