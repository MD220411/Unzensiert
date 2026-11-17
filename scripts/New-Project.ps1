# Creates a new project from the templates in templates\projekt\: README, CLAUDE.md,
# docs\ with a folder for decisions, config\, tests\, CHANGELOG.md, .gitignore, the check
# command scripts\Check.ps1, a git repository with a pre-commit hook and the first commit.
# The new project passes its own check command right away.
#
#   powershell -ExecutionPolicy Bypass -File scripts\New-Project.ps1 -Name mein-tool
#   ... -Name mein-tool -Language powershell -Purpose "Raeumt Protokolldateien auf."
#   ... -Name mein-tool -Path D:\Arbeit        (parent folder, default: projectsRoot)
#   ... -Name mein-tool -NoGit                 (no repository, no commit)
#
# Languages and folders: config\projects.json. An existing folder is never touched.
# Description: docs\projekte.md.

param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Language,
    [string]$Path,
    [string]$Purpose = 'Zweck des Projekts in ein bis zwei Saetzen.',
    [switch]$NoGit
)

. "$PSScriptRoot\_common.ps1"

$cfg = Get-ProjectsConfig
if (-not $Language) { $Language = [string]$cfg.defaultLanguage }
$known = @($cfg.languages.PSObject.Properties | ForEach-Object { $_.Name })
if ($known -notcontains $Language) {
    [Console]::Error.WriteLine("Unknown language '$Language'. Known: $($known -join ', ')")
    exit 1
}
if ($Name -notmatch '^[\w][\w .-]*$') {
    [Console]::Error.WriteLine("The name '$Name' may only contain letters, digits, space, dot, hyphen and underscore.")
    exit 1
}
if (-not $Path) { $Path = Get-ProjectsRoot }
$target = Join-Path $Path $Name
if (Test-Path $target) {
    [Console]::Error.WriteLine("Folder already exists, nothing changed: $target")
    exit 1
}

New-ProjectFromTemplate $Name $Language $target $Purpose
"created   $target  ($Language)"

$check = Invoke-ProjectCheck $target
$check.output | ForEach-Object { "  $_" }
if (-not $check.ok) {
    [Console]::Error.WriteLine('The new project fails its own check. Run scripts\Test-Templates.ps1 to see what is wrong with the template.')
    exit 1
}

if (-not $NoGit) {
    $problem = Initialize-ProjectRepository $target
    if ($problem) { "note      no first commit: $problem" } else { 'git       repository created, first commit made, pre-commit hook runs the check' }
}

''
"Next:  cd `"$target`"  and start  claude-local"
'       Describe the purpose in README.md first; the model reads README.md and CLAUDE.md.'
