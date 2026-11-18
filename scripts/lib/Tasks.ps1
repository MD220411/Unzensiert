# Benchmark tasks (benchmark\tasks\<name>\): work copies and running the hidden check.

function Get-TaskOverlayDir([string]$Name) {
    # Folder of a benchmark overlay (benchmark\overlays\<name>), '' for no overlay.
    if (-not $Name) { return '' }
    $dir = Join-Path $script:ProjectRoot "benchmark\overlays\$Name"
    if (-not (Test-Path (Join-Path $dir 'overlay.json'))) { throw "Unknown overlay '$Name': $dir\overlay.json is missing." }
    return $dir
}

function New-TaskWorkCopy([string]$TaskDir, [string]$WorkDir, [switch]$WithSolution, [string]$Overlay, [switch]$Git) {
    # Creates a fresh work folder with the task files, optionally with the reference
    # solution laid over them and with an overlay (project notes and check command that
    # the plain task lacks, see overlay.json in the overlay folder). Compiled Python files are left out: Python would trust them
    # for a source file that kept its size and second of change, and answer from old code.
    # With -Git the folder becomes a repository with the task files as first commit, so
    # that the second look of the closing check sees the agent's change as a diff.
    if (Test-Path $WorkDir) { Remove-Item -Path $WorkDir -Recurse -Force -Confirm:$false }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Copy-Item -Path (Join-Path $TaskDir 'files\*') -Destination $WorkDir -Recurse
    if ($WithSolution) { Copy-Item -Path (Join-Path $TaskDir 'solution\*') -Destination $WorkDir -Recurse -Force }
    $overlayDir = Get-TaskOverlayDir $Overlay
    if ($overlayDir) {
        foreach ($file in @((Read-JsonFile (Join-Path $overlayDir 'overlay.json')).shared)) {
            $target = Join-Path $WorkDir ([string]$file.to)
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -Path (Join-Path $script:ProjectRoot ([string]$file.from)) -Destination $target -Force
        }
        $own = Join-Path $overlayDir (Split-Path -Leaf $TaskDir)
        if (Test-Path $own) { Copy-Item -Path (Join-Path $own '*') -Destination $WorkDir -Recurse -Force }
    }
    Get-ChildItem -Path $WorkDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -Confirm:$false
    if ($Git) {
        $null = Invoke-Git $WorkDir @('init', '-q')
        [System.IO.File]::WriteAllText((Join-Path $WorkDir '.git\info\exclude'), "__pycache__/`n*.pyc`n_check_*`n")
        $null = Invoke-Git $WorkDir @('add', '-A')
        $commit = Invoke-Git $WorkDir @('-c', 'user.name=benchmark', '-c', 'user.email=benchmark@localhost', '-c', 'core.autocrlf=false', 'commit', '-q', '-m', 'Initial state of the task')
        if ($commit.code -ne 0) { throw "git commit in $WorkDir failed" }
    }
}

function Invoke-TaskCheck([string]$TaskDir, [string]$WorkDir) {
    # Runs the task's check.py on a work folder. Returns pass, the rule results (from the
    # line "RULES {json}", $null if the task checks no rules) and the remaining output.
    $lines = @(& cmd /c "python -I `"$(Join-Path $TaskDir 'check.py')`" `"$WorkDir`" 2>&1")
    $pass = ($LASTEXITCODE -eq 0)
    $rules = $null
    $rest = @()
    foreach ($line in $lines) {
        if ("$line".StartsWith('RULES ')) { try { $rules = "$line".Substring(6) | ConvertFrom-Json } catch {} }
        else { $rest += "$line" }
    }
    return @{ pass = $pass; rules = $rules; output = ($rest -join "`n").Trim() }
}
