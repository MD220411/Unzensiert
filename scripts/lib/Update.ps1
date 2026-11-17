# Automatic updates of the program files from the releases of the project on GitHub
# (config\updates.json). At most every "checkHours" hours, unzensiert asks GitHub for the
# newest release; if it is newer than the file VERSION, the program folder is brought to it:
# with git (fetch the tag, check it out) or as a ZIP laid over the folder, where
# config\machine.json stays. Then the llama.cpp build of the new version is installed.
# Work in progress on main never arrives, and copies someone works on (changed files, a full
# git clone that is not on a release) are never touched. Needs lib\Config.ps1,
# lib\AgentApi.ps1 (JSON) and lib\Review.ps1 (Invoke-Git). Keep this file ASCII-only.
# Description: docs\einrichtung.md.

function Get-ProgramVersion {
    $file = Join-Path $script:ProjectRoot 'VERSION'
    if (-not (Test-Path $file)) { return '0.0.0' }
    return ([System.IO.File]::ReadAllText($file)).Trim()
}

function ConvertTo-ProgramVersion([string]$Text) {
    # "v1.2.3" or "1.2.3" as [version]; $null if it is none.
    $v = $null
    if ([version]::TryParse(([string]$Text).Trim().TrimStart('v', 'V'), [ref]$v)) { return $v }
    return $null
}

function Test-NewerVersion([string]$Candidate, [string]$Current) {
    $a = ConvertTo-ProgramVersion $Candidate
    $b = ConvertTo-ProgramVersion $Current
    if (-not $a -or -not $b) { return $false }
    return ($a -gt $b)
}

function Get-UpdateConfig {
    return (Read-Config 'updates')
}

function Set-UpdatesEnabled([bool]$Enabled) {
    # unzensiert --updates on|off: noted for this machine in config\machine.json.
    Set-MachineValue 'updates' 'enabled' $Enabled
}

function ConvertFrom-ReleaseInfo($Release, [string]$Repository) {
    # The parts of a GitHub release that count: @{ tag; version; url; zip }, or $null for a
    # draft, a pre-release or a tag that is no version.
    $tag = [string](Get-DictValue $Release 'tag_name')
    if (-not $tag -or (Get-DictValue $Release 'draft') -or (Get-DictValue $Release 'prerelease')) { return $null }
    if (-not (ConvertTo-ProgramVersion $tag)) { return $null }
    return @{
        tag = $tag; version = $tag.TrimStart('v', 'V'); url = [string](Get-DictValue $Release 'html_url')
        zip = "https://github.com/$Repository/archive/refs/tags/$tag.zip"
    }
}

function Get-LatestRelease($Cfg) {
    # The newest published release, $null if there is none or GitHub does not answer in time.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $request = [System.Net.HttpWebRequest]::Create("https://api.github.com/repos/$($Cfg.repository)/releases/latest")
        $request.UserAgent = 'unzensiert-update-check'
        $request.Accept = 'application/vnd.github+json'
        $request.Timeout = [int]$Cfg.timeoutSeconds * 1000
        $request.ReadWriteTimeout = [int]$Cfg.timeoutSeconds * 1000
        $response = $request.GetResponse()
        try {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $release = ConvertFrom-AgentJson $reader.ReadToEnd()
        } finally { $response.Close() }
        return (ConvertFrom-ReleaseInfo $release ([string]$Cfg.repository))
    } catch {
        return $null
    }
}

function Get-InstallKind {
    # git: a copy made with git; zip: unpacked from a ZIP (the installer without git).
    if (Test-Path (Join-Path $script:ProjectRoot '.git')) { return 'git' }
    return 'zip'
}

function Get-UpdateBlocker([switch]$IgnoreSwitch) {
    # Why this copy is not updated, '' if it may be. A git copy is updated only when nothing
    # in it was changed by hand and it is a copy of the installer (shallow) or sits on a
    # release (detached at a tag); a development clone is left alone.
    $cfg = Get-UpdateConfig
    if (-not $IgnoreSwitch -and -not $cfg.enabled) { return 'automatic updates are switched off (unzensiert --updates on)' }
    if ((Get-InstallKind) -ne 'git') { return '' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return 'git is not installed' }
    $changes = Invoke-Git $script:ProjectRoot @('status', '--porcelain', '--untracked-files=no')
    if ($changes.code -ne 0) { return 'git cannot read the program folder' }
    if (@($changes.lines | Where-Object { "$_".Trim() }).Count -gt 0) { return 'files of the program were changed by hand' }
    $shallow = ((Invoke-Git $script:ProjectRoot @('rev-parse', '--is-shallow-repository')).lines -join '').Trim() -eq 'true'
    $detached = (Invoke-Git $script:ProjectRoot @('symbolic-ref', '-q', 'HEAD')).code -ne 0
    $atTag = (Invoke-Git $script:ProjectRoot @('describe', '--tags', '--exact-match', 'HEAD')).code -eq 0
    if (-not $shallow -and -not ($detached -and $atTag)) { return 'this is a development copy (a git clone that is not on a release)' }
    return ''
}

function Update-ProgramFiles($Release) {
    # Brings the program folder to the release. Returns '' or what went wrong.
    if ((Get-InstallKind) -eq 'git') {
        $r = Invoke-Git $script:ProjectRoot @('fetch', '--quiet', '--depth', '1', '--no-tags', 'origin', 'tag', $Release.tag)
        if ($r.code -ne 0) { return "git could not fetch $($Release.tag)" }
        $r = Invoke-Git $script:ProjectRoot @('checkout', '--quiet', '--detach', "refs/tags/$($Release.tag)")
        if ($r.code -ne 0) { return "git could not switch to $($Release.tag)" }
        return ''
    }
    $tmp = Join-Path $env:TEMP "unzensiert-update-$PID"
    $zip = "$tmp.zip"
    try {
        & curl.exe -sSL --fail -o $zip $Release.zip
        if ($LASTEXITCODE -ne 0) { return "the download of $($Release.zip) failed" }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $top = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
        if (-not $top -or -not (Test-Path (Join-Path $top.FullName 'scripts\unzensiert.ps1'))) { return 'the downloaded release has an unexpected layout' }
        # config\machine.json is not part of the ZIP and stays as it is
        Copy-Item -Path (Join-Path $top.FullName '*') -Destination $script:ProjectRoot -Recurse -Force
        return ''
    } finally {
        Remove-Item -Recurse -Force -Path $zip, $tmp -ErrorAction SilentlyContinue
    }
}

function Complete-ProgramUpdate([string]$BuildBefore) {
    # After new program files: the llama.cpp build the new version names (does nothing if it
    # is there), and a restart of the server when the build changed and no session uses it.
    $scripts = Join-Path $script:ProjectRoot 'scripts'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'Install-LlamaCpp.ps1') | ForEach-Object { "  $_" }
    $buildAfter = [string](Read-JsonFile (Join-Path $script:ConfigDir 'server.json')).build
    if ($buildAfter -ne $BuildBefore -and (Test-ServerUp) -and @(Get-OtherAgentSessions).Count -eq 0) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'Restart-Server.ps1') | ForEach-Object { "  $_" }
    }
}

$script:ProgramUpdated = $false

function Invoke-UpdateCheck([switch]$Force) {
    # Checks for a newer release and installs it. Without -Force only if updates are on and
    # the last check is older than "checkHours"; -Force (unzensiert --update) checks now,
    # also when the automatic updates are off. Returns the lines to show; afterwards
    # $script:ProgramUpdated says whether the files changed (the caller then starts again).
    $script:ProgramUpdated = $false
    $cfg = Get-UpdateConfig
    $current = Get-ProgramVersion
    $stateFile = Join-Path (Get-ServerConfig).runDir 'update-check.json'
    if (-not $Force) {
        if (-not $cfg.enabled) { return }
        if (Test-Path $stateFile) {
            try {
                $last = [datetime]::Parse([string](Read-JsonFile $stateFile).checked, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                if (((Get-Date) - $last).TotalHours -lt [double]$cfg.checkHours) { return }
            } catch {}
        }
    }
    $release = Get-LatestRelease $cfg
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stateFile) | Out-Null
        $latest = ''
        if ($release) { $latest = $release.tag }
        [System.IO.File]::WriteAllText($stateFile, (ConvertTo-AgentJson @{ checked = (Get-Date).ToString('o'); latest = $latest; current = $current }))
    } catch {}
    if (-not $release) {
        if ($Force) { "unzensiert: no release found on GitHub ($($cfg.repository)), or GitHub did not answer." }
        return
    }
    if (-not (Test-NewerVersion $release.version $current)) {
        if ($Force) { "unzensiert: version $current is the newest." }
        return
    }
    $blocker = Get-UpdateBlocker -IgnoreSwitch:$Force
    if ($blocker) {
        "unzensiert: version $($release.version) is available ($($release.url)), but $blocker."
        return
    }
    "unzensiert: updating from $current to $($release.version) ..."
    $buildBefore = [string](Read-JsonFile (Join-Path $script:ConfigDir 'server.json')).build
    $problem = Update-ProgramFiles $release
    if ($problem) {
        "unzensiert: the update failed: $problem. The program stays at $current."
        return
    }
    Complete-ProgramUpdate $buildBefore
    "unzensiert: now at version $($release.version). Changes: $($release.url)"
    "unzensiert: switch automatic updates off with: unzensiert --updates off"
    $script:ProgramUpdated = $true
}
