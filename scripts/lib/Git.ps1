# git for the scripts of this project: found once by its full path, and called so that a
# repository cannot start programs through its configuration; programs of Windows by their full
# path. Needs nothing else. Used by almost everything, also by lib\Style.ps1 without _common.ps1.
# Keep this file ASCII-only. Description: docs\security.md.

$script:GitExe = $null

# Settings for every git the program starts: no file monitor of the repository, and no
# repository that lies hidden in a subfolder of another one. (Programs in filter.* and diff.* and
# whatever submodules name cannot be switched off this way: hooks\GitRules.ps1 finds them and
# lib\Trust.ps1 asks.)
$script:GitSafeConfig = [ordered]@{ 'core.fsmonitor' = 'false'; 'safe.bareRepository' = 'explicit' }

function Get-SystemProgram([string]$Name) {
    # Full path of a program of Windows itself: powershell, cmd, taskkill, curl.
    $system = Join-Path $env:SystemRoot 'System32'
    if ($Name -eq 'powershell') { return (Join-Path $system 'WindowsPowerShell\v1.0\powershell.exe') }
    return (Join-Path $system "$Name.exe")
}

function Get-GitExe {
    # Full path of git from PATH, '' if it is not installed. A git.exe in the current folder or
    # below it does not count.
    if ($null -eq $script:GitExe) {
        $script:GitExe = ''
        $here = ''
        try { $here = (Get-Location -PSProvider FileSystem).ProviderPath.TrimEnd('\') + '\' } catch {}
        foreach ($c in @(Get-Command git -CommandType Application -All -ErrorAction SilentlyContinue)) {
            $path = [string]$c.Source
            if (-not $path -or -not [System.IO.Path]::IsPathRooted($path) -or $path.StartsWith('\\')) { continue }
            if ($here -and $path.StartsWith($here, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $script:GitExe = $path
            break
        }
    }
    return $script:GitExe
}

function Get-GitSafeArguments {
    # Options before the subcommand.
    $list = @('--no-optional-locks')
    foreach ($key in $script:GitSafeConfig.Keys) { $list += @('-c', "$key=$($script:GitSafeConfig[$key])") }
    return $list
}

function Invoke-Git([string]$Folder, [string[]]$Arguments) {
    # Runs git in $Folder and returns its output lines as UTF-8 (Windows PowerShell 5.1
    # would decode them with the console code page), plus the exit code.
    $exe = Get-GitExe
    if (-not $exe) { return @{ code = 127; lines = @() } }
    $before = [Console]::OutputEncoding
    # with 'Stop', Windows PowerShell 5.1 turns any git warning on stderr into an error
    $ErrorActionPreference = 'Continue'
    $safe = @(Get-GitSafeArguments)
    # a diff never through programs the repository names; what submodules changed is not looked at
    # (git would start in each of them, with their configuration)
    if ($Arguments.Count -gt 0) {
        $more = @()
        if (@('diff', 'show', 'log') -contains $Arguments[0]) { $more = @('--no-ext-diff', '--no-textconv') }
        if (@('diff', 'status') -contains $Arguments[0]) { $more += '--ignore-submodules=all' }
        if ($more.Count -gt 0) { $Arguments = @($Arguments[0]) + $more + @($Arguments | Select-Object -Skip 1) }
    }
    # objects that are missing are not fetched for a look
    $lazy = $env:GIT_NO_LAZY_FETCH
    if ($Arguments.Count -gt 0 -and @('fetch', 'checkout', 'clone', 'pull') -notcontains $Arguments[0]) { $env:GIT_NO_LAZY_FETCH = '1' }
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $lines = @(& $exe -C $Folder -c core.quotepath=off @safe @Arguments 2>$null)
        return @{ code = $LASTEXITCODE; lines = $lines }
    } finally {
        [Console]::OutputEncoding = $before
        $env:GIT_NO_LAZY_FETCH = $lazy
    }
}

function Add-GitConfig($Environment, [string]$Key, [string]$Value) {
    # A git setting for a child process through its environment (GIT_CONFIG_COUNT,
    # GIT_CONFIG_KEY_n, GIT_CONFIG_VALUE_n): it comes before every file and is written nowhere.
    # Settings already passed this way stay; ours come after them.
    $n = 0
    $given = [string]$Environment['GIT_CONFIG_COUNT']
    if ($given -match '^\d+$') { $n = [int]$given }
    $Environment["GIT_CONFIG_KEY_$n"] = $Key
    $Environment["GIT_CONFIG_VALUE_$n"] = $Value
    $Environment['GIT_CONFIG_COUNT'] = [string]($n + 1)
}

function Set-GitSafety($Environment) {
    # The same settings for the git of a command of the model.
    foreach ($key in $script:GitSafeConfig.Keys) { Add-GitConfig $Environment $key ([string]$script:GitSafeConfig[$key]) }
}
