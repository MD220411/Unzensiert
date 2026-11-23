# Which folders the user trusts, and with what: the instructions of a project (AGENTS.md,
# CLAUDE.md), its check command (scripts\Check.ps1) and programs its git configuration names.
# A folder that brings none of these needs no question. What was confirmed is kept with its
# SHA-256 in <installRoot>\trust.json, so a change asks again. Used by the agent Unzensiert
# (lib\Trust.ps1), the closing check (Check-Stop.ps1) and the prompt of the style (lib\Style.ps1).
# Loads PathRules.ps1, GitRules.ps1 (what a repository would start) and HookEnvironment.ps1. Keep
# this file ASCII-only. Description: docs\security.md.

. (Join-Path $PSScriptRoot 'HookEnvironment.ps1')
. (Join-Path $PSScriptRoot 'PathRules.ps1')
. (Join-Path $PSScriptRoot 'GitRules.ps1')

$script:TrustFolder = $null

function Get-TrustFolder {
    # The install folder; the prompt of the style does not have it in its environment.
    if ($env:CLAUDE_LOCAL_ROOT) { return $env:CLAUDE_LOCAL_ROOT }
    if ($null -eq $script:TrustFolder) { $script:TrustFolder = [string](Get-HookSetting 'server' 'installRoot') }
    return $script:TrustFolder
}

function Get-TrustFile {
    $folder = Get-TrustFolder
    if (-not $folder) { return '' }
    return (Join-Path $folder 'trust.json')
}

function Get-TrustRoot([string]$Folder) {
    # What trust is given to: the repository, or the folder itself outside of one.
    $root = Find-GitRoot $Folder
    if (-not $root) { $root = $Folder }
    if ($root.Length -gt 3) { $root = $root.TrimEnd('\') }
    return $root
}

function Get-ContentHash([string]$Path) {
    # SHA-256 of a file, '' if it cannot be read.
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } catch { return '' }
}

function Get-TextSha([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

# --- what a folder brings along -----------------------------------------------------------------

function New-TrustItem([string]$Kind, [string]$Name, [string]$Path, [string]$Hash, [string]$Detail) {
    return @{ kind = $Kind; name = $Name; path = $Path; hash = $Hash; detail = $Detail; key = "${Kind}:$($Name.ToLowerInvariant())" }
}

function Get-TrustHash([string]$Path) {
    # The hash of a file of the folder; '' (never confirmed) for a link that leads to another computer.
    if (-not $Path.StartsWith('\\') -and (Test-FarPath $Path)) { return '' }
    return (Get-ContentHash $Path)
}

function Get-TrustItems([string]$Folder, $InstructionNames, $CheckCommands) {
    # What Unzensiert would obey or start in $Folder: instructions from the repository down to
    # the folder (per folder the first of $InstructionNames), the check command with its list of
    # steps, programs of the git configuration. Hashtables, see New-TrustItem.
    $items = New-Object System.Collections.ArrayList
    $root = Get-TrustRoot $Folder
    $dirs = New-Object System.Collections.ArrayList
    $dir = $Folder
    while ($dir) {
        $dirs.Insert(0, $dir)
        if ($dir.TrimEnd('\') -ieq $root.TrimEnd('\')) { break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    foreach ($d in $dirs) {
        foreach ($name in @($InstructionNames)) {
            $file = Join-Path $d ([string]$name)
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $null = $items.Add((New-TrustItem 'instructions' $file.Substring($root.TrimEnd('\').Length).TrimStart('\') $file (Get-TrustHash $file) ''))
            break
        }
    }
    foreach ($candidate in @($CheckCommands)) {
        $file = Join-Path $Folder ([string]$candidate)
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $null = $items.Add((New-TrustItem 'check' $file.Substring($root.TrimEnd('\').Length).TrimStart('\') $file (Get-TrustHash $file) ''))
        # the steps of the check command of the project templates
        $steps = Join-Path $Folder 'config\check.json'
        if (Test-Path -LiteralPath $steps -PathType Leaf) { $null = $items.Add((New-TrustItem 'check' $steps.Substring($root.TrimEnd('\').Length).TrimStart('\') $steps (Get-TrustHash $steps) '')) }
        break
    }
    $programs = @(Get-GitPrograms $root)
    if ($programs.Count -gt 0) { $null = $items.Add((New-TrustItem 'git' '.git' (Join-Path $root '.git') (Get-TextSha ($programs -join "`n")) ($programs -join "`n"))) }
    return $items.ToArray()
}

# --- the record -----------------------------------------------------------------------------------

function Read-TrustStore {
    $file = Get-TrustFile
    if ($file -and (Test-Path -LiteralPath $file -PathType Leaf)) {
        try { return (Get-Content -Raw -LiteralPath $file -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{ projects = [pscustomobject]@{} }
}

function Get-TrustRecord([string]$Root) {
    # What the user confirmed for $Root: an object with items (key -> hash) and check, or $null.
    $store = Read-TrustStore
    if (-not $store.projects) { return $null }
    $p = $store.projects.PSObject.Properties[$Root.ToLowerInvariant()]
    if ($p) { return $p.Value }
    return $null
}

function Get-TrustCopy([string]$Hash) {
    # Where the confirmed text with this hash is kept.
    return (Join-Path (Get-TrustFolder) "trust\$Hash.txt")
}

function Update-TrustCopies($Store, $Items) {
    # Keeps a copy of confirmed instructions and check commands, so that the next question can show
    # what has changed; copies nothing refers to any more go.
    try {
        $dir = Split-Path -Parent (Get-TrustCopy 'x')
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        foreach ($i in @($Items)) {
            if (-not $i -or -not $i.hash -or $i.kind -eq 'git') { continue }
            $copy = Get-TrustCopy $i.hash
            if (Test-Path -LiteralPath $copy) { continue }
            if ((New-Object System.IO.FileInfo([string]$i.path)).Length -gt 256KB) { continue }
            [System.IO.File]::Copy([string]$i.path, $copy, $true)
            # the file may have changed in the meantime
            if ((Get-ContentHash $copy) -cne $i.hash) { [System.IO.File]::Delete($copy) }
        }
        $used = @{}
        foreach ($p in $Store.projects.PSObject.Properties) { foreach ($q in $p.Value.items.PSObject.Properties) { $used[[string]$q.Value] = $true } }
        foreach ($f in (New-Object System.IO.DirectoryInfo($dir)).GetFiles('*.txt')) { if (-not $used[$f.BaseName]) { $f.Delete() } }
    } catch {}
}

function Save-TrustRecord([string]$Root, $Items, [bool]$Check) {
    # Confirms $Items for $Root (items confirmed earlier and not among them are forgotten).
    $file = Get-TrustFile
    if (-not $file) { return }
    $store = Read-TrustStore
    if (-not $store.PSObject.Properties['projects'] -or -not $store.projects) { $store = [pscustomobject]@{ projects = [pscustomobject]@{} } }
    $list = [ordered]@{}
    foreach ($i in @($Items)) { if ($i) { $list[[string]$i.key] = [string]$i.hash } }
    $record = [pscustomobject]@{ at = (Get-Date).ToString('yyyy-MM-dd HH:mm'); check = $Check; items = [pscustomobject]$list }
    $store.projects | Add-Member -Force -NotePropertyName $Root.ToLowerInvariant() -NotePropertyValue $record
    foreach ($name in @($store.projects.PSObject.Properties.Name)) {
        # folders that are gone, on drives that are there
        if ($name -match '^[a-z]:\\' -and (Test-Path -LiteralPath $name.Substring(0, 3)) -and -not (Test-Path -LiteralPath $name)) { $store.projects.PSObject.Properties.Remove($name) }
    }
    $dir = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
    $tmp = "$file.$PID.tmp"
    [System.IO.File]::WriteAllText($tmp, ($store | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    try {
        if (Test-Path -LiteralPath $file) { [System.IO.File]::Replace($tmp, $file, $null) } else { [System.IO.File]::Move($tmp, $file) }
    } catch {
        [System.IO.File]::Copy($tmp, $file, $true)
        [System.IO.File]::Delete($tmp)
    }
    Update-TrustCopies $store $Items
}

function Test-TrustItem($Record, $Item) {
    # True if exactly this state of the item was confirmed.
    if (-not $Record -or -not $Record.items -or -not $Item.hash) { return $false }
    $p = $Record.items.PSObject.Properties[[string]$Item.key]
    return ($null -ne $p -and [string]$p.Value -ceq [string]$Item.hash)
}

function Get-ProjectTrust([string]$Folder, $InstructionNames, $CheckCommands) {
    # The state of $Folder: @{ root; items; open (not confirmed or changed); record; trusted }.
    $root = Get-TrustRoot $Folder
    $items = @(Get-TrustItems $Folder $InstructionNames $CheckCommands)
    $record = Get-TrustRecord $root
    $open = @($items | Where-Object { -not (Test-TrustItem $record $_) })
    return @{ root = $root; items = $items; open = $open; record = $record; trusted = ($open.Count -eq 0) }
}

function Test-CheckTrusted([string]$Folder, $CheckCommands) {
    # True if the check command of $Folder may run without a question: the user said so for
    # exactly this script and its list of steps.
    $record = Get-TrustRecord (Get-TrustRoot $Folder)
    if (-not $record -or -not $record.check) { return $false }
    foreach ($item in @(Get-TrustItems $Folder @() $CheckCommands | Where-Object { $_.kind -eq 'check' })) {
        if (-not (Test-TrustItem $record $item)) { return $false }
    }
    return $true
}

# folders trusted in this run only (unzensiert --trust)
$script:TrustOnceRoots = @()

function Set-TrustOnce([string]$Folder) {
    $script:TrustOnceRoots = @($script:TrustOnceRoots) + (Get-TrustRoot $Folder)
}

function Test-GitTrusted([string]$Folder) {
    # True if git may be called in $Folder by the program itself: the repository names no
    # programs, or the user confirmed exactly these.
    $root = Find-GitRoot $Folder
    if (-not $root) { return $true }
    if (@($script:TrustOnceRoots) -contains (Get-TrustRoot $Folder)) { return $true }
    $programs = @(Get-GitPrograms $root)
    if ($programs.Count -eq 0) { return $true }
    $item = New-TrustItem 'git' '.git' (Join-Path $root '.git') (Get-TextSha ($programs -join "`n")) ''
    return (Test-TrustItem (Get-TrustRecord (Get-TrustRoot $Folder)) $item)
}
