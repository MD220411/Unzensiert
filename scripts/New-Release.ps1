# Publishes a new version of Unzensiert: writes VERSION, runs the checks, commits, tags
# vX.Y.Z, pushes and creates the release on GitHub. Installs with automatic updates
# (config\updates.json) install it the next time they look, at most a day later. Only for
# the maintainers of the repository; needs git and the GitHub CLI (gh, logged in).
#
#   powershell -ExecutionPolicy Bypass -File scripts\New-Release.ps1 -Version 1.1.0 -Notes "What changed"
#   ... -NotesFile notes.md       the text of the release from a file
#   ... -DryRun                   check everything and show what would happen, change nothing
#   ... -SkipTests                without the checks (only to repeat a release that failed late)
#
# Without notes the release lists the commit subjects since the last release. The steps run
# in an order that publishes nothing half: the tag is pushed after the commit, the release
# is created after the tag. Exit code 0 = released (or dry run fine), 1 = stopped.

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Notes = '',
    [string]$NotesFile = '',
    [switch]$DryRun,
    [switch]$SkipTests
)

. "$PSScriptRoot\_common.ps1"

function Stop-Release([string]$Why) {
    Write-Host "release stopped: $Why" -ForegroundColor Red
    exit 1
}

function Invoke-ReleaseGit([string[]]$Arguments, [string]$What) {
    # git in the repository; stops the release if it fails.
    $r = Invoke-Git $script:ProjectRoot $Arguments
    if ($r.code -ne 0) { Stop-Release "$What failed (git $($Arguments -join ' '))" }
    return $r.lines
}

$Version = $Version.Trim().TrimStart('v', 'V')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Stop-Release "'$Version' is no version of the form 1.2.3" }
$tag = "v$Version"
$current = Get-ProgramVersion
$repo = $script:ProjectRoot

# --- checks before anything changes ------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Release 'git is not installed' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Stop-Release 'the GitHub CLI (gh) is not installed: winget install GitHub.cli' }
$saved = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& gh auth status *> $null
$ghOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $saved
if (-not $ghOk) { Stop-Release 'gh is not logged in: gh auth login' }
if (@(Invoke-ReleaseGit @('status', '--porcelain') 'reading the state').Count -gt 0) { Stop-Release 'there are uncommitted changes; commit or stash them first' }
$branch = (@(Invoke-ReleaseGit @('rev-parse', '--abbrev-ref', 'HEAD') 'reading the branch') -join '').Trim()
if ($branch -ne 'main') { Stop-Release "releases are made from main, not from '$branch'" }
$null = Invoke-ReleaseGit @('fetch', '--quiet', '--tags', 'origin') 'fetching from GitHub'
$behind = (@(Invoke-ReleaseGit @('rev-list', '--count', 'HEAD..origin/main') 'comparing with GitHub') -join '').Trim()
if ($behind -ne '0') { Stop-Release "main is $behind commit(s) behind origin/main; pull first" }
if ((Invoke-Git $repo @('rev-parse', '-q', '--verify', "refs/tags/$tag")).code -eq 0) { Stop-Release "the tag $tag exists already" }
$newer = Test-NewerVersion $Version $current
if (-not $newer -and $Version -ne $current) { Stop-Release "$Version is older than the version in VERSION ($current)" }

# --- release notes -------------------------------------------------------------------------
if ($NotesFile) {
    if (-not (Test-Path $NotesFile)) { Stop-Release "notes file $NotesFile not found" }
    $Notes = [System.IO.File]::ReadAllText((Resolve-Path $NotesFile).Path)
}
if (-not $Notes.Trim()) {
    $lastTag = (Invoke-Git $repo @('describe', '--tags', '--abbrev=0')).lines -join ''
    $range = @('log', '--pretty=format:- %s', '--no-merges')
    if ($lastTag) { $range += "$($lastTag.Trim())..HEAD" }
    $Notes = "Unzensiert $Version`n`n" + ((Invoke-Git $repo $range).lines -join "`n")
}

Write-Host "release $tag (VERSION now $current), from main at $((Invoke-Git $repo @('rev-parse', '--short', 'HEAD')).lines -join '')" -ForegroundColor Cyan

# --- checks of the project -------------------------------------------------------------------
if (-not $SkipTests) {
    foreach ($test in 'Test-Setup.ps1', 'Test-Guard.ps1', 'Test-Agent.ps1', 'Test-Install.ps1', 'Test-Templates.ps1', 'Test-Tasks.ps1') {
        Write-Host "  $test ..."
        if ((Invoke-ProjectScript $test @() -OnlyProblems) -ne 0) { Stop-Release "$test failed" }
    }
}

if ($DryRun) {
    Write-Host 'dry run: would write VERSION, commit, tag, push and create the release with these notes:' -ForegroundColor Yellow
    $Notes
    exit 0
}

# --- publish -------------------------------------------------------------------------------------
if ($Version -ne $current) {
    [System.IO.File]::WriteAllText((Join-Path $repo 'VERSION'), "$Version`n", (New-Object System.Text.UTF8Encoding($false)))
    $null = Invoke-ReleaseGit @('add', 'VERSION') 'staging VERSION'
    $null = Invoke-ReleaseGit @('commit', '--quiet', '-m', "Version $Version") 'committing VERSION'
}
$null = Invoke-ReleaseGit @('tag', '-a', $tag, '-m', "Unzensiert $Version") 'creating the tag'
$null = Invoke-ReleaseGit @('push', '--quiet', 'origin', 'main') 'pushing main'
$null = Invoke-ReleaseGit @('push', '--quiet', 'origin', $tag) 'pushing the tag'
$notesPath = Join-Path $env:TEMP "unzensiert-release-$PID.md"
[System.IO.File]::WriteAllText($notesPath, $Notes, (New-Object System.Text.UTF8Encoding($false)))
try {
    & gh release create $tag --title "Unzensiert $Version" --notes-file $notesPath --verify-tag
    if ($LASTEXITCODE -ne 0) { Stop-Release "gh could not create the release; the tag $tag is pushed, run: gh release create $tag" }
} finally {
    Remove-Item -Force -Path $notesPath -ErrorAction SilentlyContinue
}
Write-Host "released $tag" -ForegroundColor Green
exit 0
