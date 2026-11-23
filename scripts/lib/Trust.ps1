# Trust in a project folder, for the agent Unzensiert: what the folder brings along that would be
# obeyed or started - instructions, the check command, programs its git configuration names - is
# only used after the user confirmed it once (rules and record: hooks\TrustRules.ps1). The
# question at the start, the question before the first run of the check command, and what a
# session may use. Needs lib\Config.ps1, lib\AgentUi*.ps1. Keep this file ASCII-only.
# Description: docs\security.md.

function Get-TrustNames {
    # What counts as instructions and as check command (config\unzensiert.json, config\agent.json).
    return @{ instructions = @((Get-AgentSettings).projectFiles); checks = @((Get-AgentConfig).stopCheck.commands) }
}

function Get-FolderTrust([string]$Folder) {
    $names = Get-TrustNames
    return (Get-ProjectTrust $Folder $names.instructions $names.checks)
}

function Get-SessionTrustItems($Session, [string]$Kind, [bool]$Trusted) {
    # The items of a kind (instructions, check, git) in the folder of the session that are
    # confirmed, or those that are not.
    $trust = Get-FolderTrust $Session.cwd
    $out = @()
    foreach ($item in @($trust.items)) {
        if ($item.kind -ne $Kind) { continue }
        # without a hash: a link to another computer, never used (hooks\TrustRules.ps1)
        $ok = ([bool]$item.hash -and ([bool]$Session.trustOnce -or (Test-TrustItem $trust.record $item)))
        if ($ok -eq $Trusted) { $out += , $item }
    }
    return $out
}

function Set-FolderTrusted([string]$Folder, [bool]$Check) {
    # Confirms everything the folder brings along now (New-Project.ps1 for a project it has just
    # created, the benchmark for its work folders).
    $trust = Get-FolderTrust $Folder
    Save-TrustRecord $trust.root $trust.items $Check
}

function Update-TrustAfterWrite($Session, [string]$Path, [bool]$Whole) {
    # The user has just approved a change to instructions or the check command: the new state counts
    # as confirmed if they saw all of it ($Whole, a Write) or if the state before was confirmed.
    # (Changes by commands or in mode all do not count; they are asked about again.)
    $trust = Get-FolderTrust $Session.cwd
    $touched = @($trust.items | Where-Object { $_.kind -ne 'git' -and $_.path -ieq $Path })
    if ($touched.Count -eq 0) { return }
    $known = $null
    if ($trust.record) { $known = $trust.record.items.PSObject.Properties[[string]$touched[0].key] }
    if (-not $Whole -and -not $known) { return }
    $keep = @($trust.items | Where-Object { (Test-TrustItem $trust.record $_) -or $_.path -ieq $Path })
    Save-TrustRecord $trust.root $keep ([bool]($trust.record -and $trust.record.check))
}

# --- the question at the start ------------------------------------------------------------------------

function Get-TrustRows($Trust) {
    # What the question lists: one text per thing that is new or has changed.
    $rows = @()
    foreach ($item in @($Trust.open)) {
        $state = Get-UiText 'trust.new'
        if ($Trust.record -and $Trust.record.items.PSObject.Properties[[string]$item.key]) { $state = Get-UiText 'trust.changed' }
        if ($item.kind -eq 'instructions') {
            $lines = 0
            try { $lines = @([System.IO.File]::ReadAllLines($item.path)).Count } catch {}
            $text = Get-UiText 'trust.instructions' $item.name (Get-UiCount $lines 'lines')
            try {
                $odd = Get-InvisibleCount ([System.IO.File]::ReadAllText($item.path))
                if ($odd -gt 0) { $text += '; ' + (Get-UiText 'permission.invisible' $odd) }
            } catch {}
            $rows += , @($text, $state)
        } elseif ($item.kind -eq 'check') { $rows += , @((Get-UiText 'trust.check' $item.name), $state) }
        else {
            $lines = @(([string]$item.detail).Split("`n"))
            foreach ($line in @($lines | Select-Object -First 12)) { $rows += , @((Get-UiText 'trust.git' $line), $state) }
            if ($lines.Count -gt 12) { $rows += , @((Get-UiText 'trust.more' ($lines.Count - 12)), $state) }
        }
        if (-not $item.hash) { $rows += , @((Get-UiText 'trust.unreadable' $item.name), '') }
    }
    return , $rows
}

function Show-UiTrustDetails($Trust, $Items) {
    # What the question is about, complete: each file with line numbers, or what changed in it
    # since it was confirmed; every git setting.
    $mode = $script:Ui.mode
    $inner = (Get-UiWidth) - 4
    foreach ($item in @($Items)) {
        $rows = New-Object System.Collections.ArrayList
        $title = [string]$item.name
        $old = ''
        if ($item.kind -ne 'git' -and $Trust.record) {
            $p = $Trust.record.items.PSObject.Properties[[string]$item.key]
            if ($p) { try { $old = [System.IO.File]::ReadAllText((Get-TrustCopy ([string]$p.Value))) } catch {} }
        }
        if ($item.kind -eq 'git') {
            foreach ($l in ([string]$item.detail).Split("`n")) { foreach ($r in (Split-UiSpans @(New-UiSpan $l $mode.foreground) $inner)) { $null = $rows.Add((Format-UiSpans $r)) } }
        } elseif (-not $item.hash) {
            $null = $rows.Add((Format-UiInk (Get-UiText 'trust.unreadable' $item.name) $mode.dim -Italic))
        } else {
            $text = ''
            try { $text = [System.IO.File]::ReadAllText([string]$item.path).Replace("`r`n", "`n").TrimEnd("`n") } catch {}
            $lines = @($text.Split("`n"))
            if ($text.Length -gt 256KB -or $lines.Count -gt 3000) {
                $null = $rows.Add((Format-UiInk (Get-UiText 'trust.tooLong' (Get-UiCount $lines.Count 'lines')) $script:Ui.ink.warn -Italic))
            } elseif ($old) {
                $title += '  ' + (Get-UiText 'trust.changed')
                foreach ($r in (Get-UiDiffRows $old.Replace("`r`n", "`n").TrimEnd("`n") $text 1 ([string]$item.path) 6000 $inner).rows) { $null = $rows.Add($r) }
            } else {
                $lang = Get-UiCodeLang ([System.IO.Path]::GetExtension([string]$item.path))
                $pad = ([string]$lines.Count).Length
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $number = ([string]($i + 1)).PadLeft($pad)
                    foreach ($r in (Get-UiCodeRows $lines[$i] $lang ($inner - $pad - 2))) { $null = $rows.Add((Format-UiInk $number $mode.faint) + '  ' + $r); $number = ' ' * $pad }
                }
            }
        }
        Write-UiOut ("`n  " + (Format-UiInk (ConvertTo-UiSafe $title) $script:Ui.ink.warn -Bold) + "`n")
        Write-UiOut ((@($rows | ForEach-Object { '  ' + $_ }) -join "`n") + "`n")
    }
}

function Show-UiTrust($Trust) {
    # The question in a frame: the folder, what it brings along, the keys.
    $mode = $script:Ui.mode
    $hex = $script:Ui.ink.warn
    $inner = (Get-UiWidth) - 6
    $side = '  ' + (Format-UiInk (Get-UiBox 3) $hex) + ' '
    Write-UiOut "`n"
    Write-UiFrameTop '!' (Get-UiText 'trust.title') $hex
    $out = New-Object System.Collections.ArrayList
    foreach ($l in (Format-UiWrapped @(New-UiSpan $Trust.root $mode.foreground 'b') '' '' 0 $inner)) { $null = $out.Add($side + $l) }
    foreach ($l in (Format-UiWrapped @(New-UiSpan (Get-UiText 'trust.explain') $mode.dim) '' '' 0 $inner)) { $null = $out.Add($side + $l) }
    foreach ($row in (Get-TrustRows $Trust)) {
        $spans = @((New-UiSpan ([string]$row[0]) $mode.foreground), (New-UiSpan ('  ' + [string]$row[1]) $hex 'i'))
        foreach ($l in (Format-UiWrapped $spans '- ' '  ' 2 $inner)) { $null = $out.Add($side + $l) }
    }
    Write-UiOut ((@($out) -join "`n") + "`n")
    Write-UiFrameBottom $hex
    $items = @(@('y', (Get-UiText 'trust.yes')), @('v', (Get-UiText 'trust.view')), @('n', (Get-UiText 'trust.no')), @('Esc', (Get-UiText 'trust.quit')))
    Write-UiOut (Format-UiKeyLine $items $hex)
}

function Confirm-ProjectTrust($Session) {
    # Asks about what is new or has changed in the folder of the session, before anything of it
    # is used. Returns 'ok' (nothing to ask, or confirmed), 'limited' (the session goes on without
    # these things) or 'quit'. Without a terminal it never asks.
    if ($Session.trustOnce) { return 'ok' }
    $trust = Get-FolderTrust $Session.cwd
    if ($trust.trusted) { return 'ok' }
    if (-not $script:Ui.on) { return 'limited' }
    Show-UiTrust $trust
    Clear-UiKeys
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [string]$k.KeyChar
        if ($k.Key -eq [ConsoleKey]::Escape -or ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control))) { Write-UiChoiceAnswer 'error' (Get-UiText 'trust.left'); return 'quit' }
        if ($c -eq 'y' -or $c -eq 'j') {
            # the check command is asked about before its first run; a yes from earlier stays
            # only while nothing of it changed
            $check = [bool]($trust.record -and $trust.record.check -and @($trust.open | Where-Object { $_.kind -eq 'check' }).Count -eq 0)
            Save-TrustRecord $trust.root $trust.items $check
            Write-UiChoiceAnswer 'ok' (Get-UiText 'trust.confirmed')
            return 'ok'
        }
        if ($c -eq 'v') {
            Show-UiTrustDetails $trust $trust.open
            Show-UiTrust $trust
            Clear-UiKeys
        }
        if ($c -eq 'n') {
            # a check command that was declined does not run in this session, in no mode
            if (@($trust.open | Where-Object { $_.kind -eq 'check' }).Count -gt 0) { $Session.checkAnswer = @{ hash = (Get-CheckState $Session).hash; yes = $false } }
            Write-UiChoiceAnswer 'warn' (Get-UiText 'trust.limited')
            return 'limited'
        }
    }
}

# --- the check command --------------------------------------------------------------------------------

function Get-CheckState($Session) {
    # The check command of the folder: @{ items; hash } of the script and its list of steps.
    $names = Get-TrustNames
    $items = @(Get-TrustItems $Session.cwd @() $names.checks | Where-Object { $_.kind -eq 'check' })
    return @{ items = $items; hash = (@($items | ForEach-Object { [string]$_.hash }) -join '+') }
}

function Test-CheckAllowed($Session) {
    # True if the closing check may run the check command of the project now. It runs code of the
    # project, also code the model has just written, so it is asked about: always in this project
    # (while the script and its steps stay as they are), this session, or not at all. Mode all
    # and --trust need no question; without a terminal only a yes from earlier counts.
    $state = Get-CheckState $Session
    if (@($state.items).Count -eq 0) { return $true }
    if (@($state.items | Where-Object { -not $_.hash }).Count -gt 0) { return $false }
    if ($Session.trustOnce -or (Test-CheckTrusted $Session.cwd (Get-TrustNames).checks)) { return $true }
    if ($Session.checkAnswer -and $Session.checkAnswer.hash -ceq $state.hash) { return [bool]$Session.checkAnswer.yes }
    if ($Session.mode -eq 'all') { return $true }
    if (-not $script:Ui.on) { return $false }
    $reply = Read-UiCheckQuestion $Session $state.items
    if ($reply -eq 'always') {
        $trust = Get-FolderTrust $Session.cwd
        $keep = @($trust.items | Where-Object { $_.kind -eq 'check' -or (Test-TrustItem $trust.record $_) })
        Save-TrustRecord $trust.root $keep $true
        return $true
    }
    $Session.checkAnswer = @{ hash = $state.hash; yes = ($reply -eq 'yes') }
    return ($reply -eq 'yes')
}

function Show-UiCheckQuestion([string]$Name) {
    $mode = $script:Ui.mode
    $hex = $script:Ui.ink.warn
    $inner = (Get-UiWidth) - 6
    $side = '  ' + (Format-UiInk (Get-UiBox 3) $hex) + ' '
    Write-UiFrameTop '?' (Get-UiText 'trust.checkTitle') $hex
    $out = @()
    foreach ($l in (Format-UiWrapped @(New-UiSpan $Name $mode.foreground 'b') '' '' 0 $inner)) { $out += $side + $l }
    foreach ($l in (Format-UiWrapped @(New-UiSpan (Get-UiText 'trust.checkExplain') $mode.dim) '' '' 0 $inner)) { $out += $side + $l }
    Write-UiOut (($out -join "`n") + "`n")
    Write-UiFrameBottom $hex
    Write-UiOut (Format-UiKeyLine @(@('y', (Get-UiText 'trust.checkYes')), @('a', (Get-UiText 'trust.checkAlways')), @('v', (Get-UiText 'trust.view')), @('n', (Get-UiText 'trust.checkNo'))) $hex)
}

function Read-UiCheckQuestion($Session, $Items) {
    # yes (this session), always (this project) or no.
    $name = [string]@($Items)[0].name
    Stop-UiActivity
    Show-UiCheckQuestion $name
    Set-UiProgress 0
    Clear-UiKeys
    while ($true) {
        $k = [Console]::ReadKey($true)
        $c = [string]$k.KeyChar
        if ($c -eq 'v') {
            Show-UiTrustDetails (Get-FolderTrust $Session.cwd) $Items
            Show-UiCheckQuestion $name
            Clear-UiKeys
        }
        if ($c -eq 'y' -or $c -eq 'j') { Write-UiChoiceAnswer 'ok' (Get-UiText 'trust.checkYes'); return 'yes' }
        if ($c -eq 'a' -or $c -eq 'i') { Write-UiChoiceAnswer 'ok' (Get-UiText 'trust.checkAlways'); return 'always' }
        if ($c -eq 'n' -or $k.Key -eq [ConsoleKey]::Escape) { Write-UiChoiceAnswer 'warn' (Get-UiText 'trust.checkNo'); return 'no' }
    }
}
