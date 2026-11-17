# Checks the project templates without a model: for every language in
# config\projects.json a project is created in a scratch folder. It must pass its own
# check command, the first commit must go through the pre-commit hook, and planted
# errors (a copy that contradicts facts\facts.json, a fact without source, a failing
# test) must make the check command fail. Takes about 30 seconds; run it
# after every change to templates\ or to New-Project.ps1.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Test-Templates.ps1
#
# Exit code 0 = all templates sound, 1 = at least one problem.

. "$PSScriptRoot\_common.ps1"

$script:Failures = 0
function Assert-That([bool]$Condition, [string]$What) {
    # Prints one result line; only failures are counted.
    if ($Condition) { "ok    $What" } else { $script:Failures++; "FAIL  $What" }
}

# what to append to which file so that a test fails, per language
$plant = @{
    python     = @{ file = 'tests\test_config.py'; text = "`n`nclass PlantedTest(unittest.TestCase):`n    def test_planted(self):`n        self.fail('planted')`n" }
    powershell = @{ file = 'tests\Test-Config.ps1'; text = "`nexit 1`n" }
}

$cfg = Get-ProjectsConfig
$scratch = Join-Path $env:TEMP "claude-local-templates-$PID"
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    foreach ($language in @($cfg.languages.PSObject.Properties | ForEach-Object { $_.Name })) {
        $target = Join-Path $scratch "Probe-$language"
        New-ProjectFromTemplate "Probe-$language" $language $target 'Probe der Vorlage.'
        $left = @(Get-ChildItem -Path $target -Recurse -File -Force | Where-Object { (Get-Content -Raw -Path $_.FullName) -match '\{\{[A-Z]+\}\}' -or $_.FullName -match '__PAKET__' })
        Assert-That ($left.Count -eq 0) "$language`: all placeholders filled in $($left.Name -join ', ')"
        foreach ($needed in 'README.md', 'CLAUDE.md', 'CHANGELOG.md', '.gitignore', 'docs\architektur.md', 'docs\entscheidungen\0000-vorlage.md', 'config\check.json', 'scripts\Check.ps1', '.githooks\pre-commit', 'facts\facts.json', 'facts\README.md', 'facts\boards\esp32.json', 'scripts\check_facts.py') {
            Assert-That (Test-Path (Join-Path $target $needed)) "$language`: has $needed"
        }
        $check = Invoke-ProjectCheck $target
        Assert-That $check.ok "$language`: new project passes its own check"
        if (-not $check.ok) { $check.output | ForEach-Object { "      $_" } }

        $problem = Initialize-ProjectRepository $target
        Assert-That (-not $problem) "$language`: first commit goes through the pre-commit hook $problem"

        # A fact and a copy of it that disagrees: the check must fail, and pass once fixed.
        $factsFile = Join-Path $target 'facts\facts.json'
        $factsBefore = [System.IO.File]::ReadAllText($factsFile)
        $copyFile = Join-Path $target 'docs\probe-fakt.md'
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($factsFile, '{ "facts": [ { "id": "probe.limit", "value": 10, "code": ["PROBE_LIMIT"], "source": "Test-Templates.ps1" } ] }', $utf8)
        [System.IO.File]::WriteAllText($copyFile, "PROBE_LIMIT = 12`n", $utf8)
        $check = Invoke-ProjectCheck $target
        Assert-That ((-not $check.ok) -and (($check.output -join "`n") -match 'PROBE_LIMIT = 12, facts say 10')) "$language`: a copy that contradicts facts\facts.json makes the check fail"
        [System.IO.File]::WriteAllText($copyFile, "PROBE_LIMIT = 10`n", $utf8)
        $check = Invoke-ProjectCheck $target
        Assert-That $check.ok "$language`: the check passes once the copy agrees with the fact"
        [System.IO.File]::WriteAllText($factsFile, '{ "facts": [ { "id": "probe.guess", "value": 3 } ] }', $utf8)
        $check = Invoke-ProjectCheck $target
        Assert-That (-not $check.ok) "$language`: a fact without source and without status annahme makes the check fail"
        [System.IO.File]::WriteAllText($factsFile, $factsBefore, $utf8)
        Remove-Item -Path $copyFile -Force

        if ($plant.Contains($language)) {
            Add-Content -Path (Join-Path $target $plant[$language].file) -Value $plant[$language].text -Encoding ASCII
            $check = Invoke-ProjectCheck $target
            Assert-That (-not $check.ok) "$language`: a failing test makes the check fail"
            $out = @(& cmd /c "git -C `"$target`" commit -q -a -m planted 2>&1")
            Assert-That ($LASTEXITCODE -ne 0) "$language`: the pre-commit hook refuses the commit"
        } else {
            Assert-That $false "$language`: Test-Templates.ps1 knows no planted error for this language"
        }
    }
} finally {
    Remove-Item -Path $scratch -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

if ($script:Failures -gt 0) { "templates: $script:Failures problem(s)."; exit 1 }
'templates: all sound.'
