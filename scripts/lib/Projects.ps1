# New projects from the templates in templates\projekt\ (settings: config\projects.json).
# Used by New-Project.ps1 and Test-Templates.ps1. Needs lib\Config.ps1. ASCII-only.
# Description: docs\projekte.md.

function Get-ProjectsConfig {
    return (Read-JsonFile (Join-Path $script:ConfigDir 'projects.json'))
}

function Get-TemplateDir([string]$Name) {
    # Full path of one template folder (a language or the shared one).
    return (Join-Path (Join-Path $script:ProjectRoot ([string](Get-ProjectsConfig).templateDir)) $Name)
}

function ConvertTo-PackageName([string]$Name) {
    # "Mein-Tool 2" -> "mein_tool_2": a name Python accepts for a package.
    $package = ($Name.ToLower() -replace '[^a-z0-9]+', '_').Trim('_')
    if ($package -match '^[0-9]') { $package = "p_$package" }
    return $package
}

function New-ProjectFromTemplate([string]$Name, [string]$Language, [string]$Target, [string]$Purpose) {
    # Copies the shared and the language template to $Target and fills in the
    # placeholders {{NAME}}, {{PAKET}}, {{ZWECK}}, {{DATUM}}. Folders named __PAKET__ get
    # the package name. $Target must not exist yet.
    if (Test-Path $Target) { throw "Folder already exists: $Target" }
    $cfg = Get-ProjectsConfig
    $languageDir = Get-TemplateDir $Language
    if (-not (Test-Path $languageDir)) { throw "No template for language '$Language' in $($cfg.templateDir)." }
    $package = ConvertTo-PackageName $Name
    if (-not $package) { throw "The name '$Name' contains no letter or digit." }

    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    foreach ($source in (Get-TemplateDir ([string]$cfg.sharedTemplate)), $languageDir) {
        # -Force also copies files and folders whose names start with a dot
        Get-ChildItem -Path $source -Force | Copy-Item -Destination $Target -Recurse -Force
    }
    Get-ChildItem -Path $Target -Recurse -Directory -Filter '__PAKET__' | Rename-Item -NewName $package

    $values = [ordered]@{ '{{NAME}}' = $Name; '{{PAKET}}' = $package; '{{ZWECK}}' = $Purpose; '{{DATUM}}' = (Get-Date -Format 'yyyy-MM-dd') }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($file in @(Get-ChildItem -Path $Target -Recurse -File -Force)) {
        $text = [System.IO.File]::ReadAllText($file.FullName, $utf8)
        if ($text -notmatch '\{\{[A-Z]+\}\}') { continue }
        foreach ($key in $values.Keys) { $text = $text.Replace($key, [string]$values[$key]) }
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8)
    }
}

function Invoke-ProjectCheck([string]$Folder) {
    # Runs the check command of a project. Returns ok and the output lines.
    $script = Join-Path $Folder ([string](Get-ProjectsConfig).checkCommand)
    $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script 2>&1 | ForEach-Object { "$_" })
    return @{ ok = ($LASTEXITCODE -eq 0); output = $lines }
}

function Initialize-ProjectRepository([string]$Folder) {
    # git init, hook folder, first commit. Returns '' or the reason why there is no commit.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return 'git is not installed' }
    $message = [string](Get-ProjectsConfig).firstCommitMessage
    $null = & cmd /c "git -C `"$Folder`" init -q 2>&1"
    $null = & cmd /c "git -C `"$Folder`" config core.hooksPath .githooks 2>&1"
    # without a global git identity the new repository gets the one of this repository,
    # so the first commit works and carries the address the user chose for commits
    foreach ($key in 'user.name', 'user.email') {
        $own = @(& git -C $Folder config $key 2>$null) -join ''
        if ($own.Trim()) { continue }
        $value = (@(& git -C $script:ProjectRoot config $key 2>$null) -join '').Trim()
        if ($value) { & git -C $Folder config $key $value }
    }
    $null = & cmd /c "git -C `"$Folder`" add -A 2>&1"
    $out = @(& cmd /c "git -C `"$Folder`" commit -q -m `"$message`" 2>&1")
    if ($LASTEXITCODE -ne 0) { return "git commit failed: $(($out | Select-Object -Last 3) -join ' ')" }
    return ''
}
