# The sandbox of Unzensiert: the commands of the model (Bash, PowerShell) run as a hidden Windows
# account of their own, through a service of that account in a sign-in of its own (session 0), which
# scripts\Setup-Sandbox.ps1 sets up with one administrator question. The service (the runner,
# scripts\sandbox\Runner.cs) starts each command with a restricted token: a write must also be
# allowed to the SID of the project of the session (an entry on the project folder, next to the one
# for the group of the account that lets it read and change there), so the command changes nothing
# in other folders it was ever let into, nothing that only "Users" may change, and through
# "Authenticated Users" nothing on other drives; it shares no SID with the user's programs and sees
# no desktop of the user. Windows keeps the user folder closed to the account; a firewall rule lets
# it reach no other computer. Around every command a watch (scripts\sandbox\Watch.cs) keeps the
# repositories of the user and the protected files of the project read-only for the account,
# because git, editors and Explorer would run them as the user. Unzensiert talks to the service
# through scripts\sandbox\Client.cs (one DLL with the watch). Commands the user types (!) and
# commands with outside_sandbox, which ask every time, run as the user.
# Settings: "sandbox" in config\unzensiert.json; the account of this computer: "sandbox" in
# config\machine.json. Description: docs\security.md ("Sandbox"). Needs lib\Config.ps1,
# lib\FolderRights.ps1, lib\Git.ps1, lib\Machine.ps1, lib\AgentTools.ps1 (SkipFolders, the guard
# of a session), hooks\PathRules.ps1. Keep this file ASCII-only.

$script:SandboxSetup = $null
$script:SandboxIdentity = $null
# the SIDs the runner accepts as the SID of a project (scripts\sandbox\Runner.cs, ProjectPrefix)
$script:SandboxProjectPrefix = 'S-1-9-1101-1-'

function Get-SandboxSettings {
    # "sandbox" of config\unzensiert.json with defaults: use (auto = when it is set up, off),
    # account, group, firewallRule, service (the runner), disableGroups (SIDs that only count for
    # deny in a command).
    $r = @{ use = 'auto'; account = 'unzensiert-sandbox'; group = 'Unzensiert-Sandbox-Accounts'; firewallRule = 'Unzensiert-Sandbox-NoNetwork'; service = 'UnzensiertSandbox'; disableGroups = @('S-1-5-11', 'S-1-5-6') }
    $s = (Get-AgentSettings).sandbox
    if ($s) { foreach ($p in $s.PSObject.Properties) { if ($r.ContainsKey($p.Name)) { $r[$p.Name] = $p.Value } } }
    $r.disableGroups = @(@($r.disableGroups) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    return $r
}

function Get-SandboxFolder {
    # <installRoot>\sandbox: bin\ with the runner (the program of the service) and the DLL of the
    # watch and the client, granted.txt (the folders its group was let into).
    return [string](Join-Path (Get-ServerConfig).installRoot 'sandbox')
}

function Get-RunnerSource { return [string](Join-Path $script:ProjectRoot 'scripts\sandbox\Runner.cs') }

function Get-SandboxPipeName {
    # The pipe of the runner for this user (scripts\sandbox\Runner.cs makes it under this name).
    return "unzensiert-sandbox-$(Get-CurrentUserSid)"
}

function Get-SandboxSetup([switch]$Fresh) {
    # Whether the sandbox can be used on this computer, read once per run: @{ ready; account;
    # accountSid; groupSid; runner; service; why } (why: off, notSetUp, noService, broken).
    if ($script:SandboxSetup -and -not $Fresh) { return $script:SandboxSetup }
    $cfg = Get-SandboxSettings
    $dir = Get-SandboxFolder
    $r = @{ ready = $false; account = ''; accountSid = ''; groupSid = ''; runner = (Join-Path $dir 'bin\unzensiert-runner.exe'); service = [string]$cfg.service; why = '' }
    $m = (Get-MachineConfig).PSObject.Properties['sandbox']
    if ([string]$cfg.use -eq 'off') { $r.why = 'off' }
    elseif (-not $m -or -not $m.Value.account -or -not $m.Value.groupSid) { $r.why = 'notSetUp' }
    else {
        $r.account = [string]$m.Value.account
        $r.groupSid = [string]$m.Value.groupSid
        # the owner of what a command makes: the watch tells it from what the user owns
        try { $r.accountSid = [string](New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $r.account)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch {}
        # a setup from before the service (2026-11-24) has the account but not the service
        if (-not (Get-Service -Name $r.service -ErrorAction SilentlyContinue)) { $r.why = 'noService' }
        elseif (-not $r.accountSid -or -not [System.IO.File]::Exists($r.runner)) { $r.why = 'broken' }
        else { $r.ready = $true }
    }
    $script:SandboxSetup = $r
    return $r
}

function Get-SandboxProjectSid([string]$Folder) {
    # The SID of a project folder for the restricted token of its commands: made up from its full
    # path (the same folder always gets the same SID), under the prefix the runner accepts.
    $full = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\').ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($full)) }
    finally { $sha.Dispose() }
    $parts = @(0, 4, 8, 12 | ForEach-Object { [BitConverter]::ToUInt32($hash, $_) })
    return $script:SandboxProjectPrefix + ($parts -join '-')
}

function Grant-SandboxProjectSid([string]$Folder, [switch]$Remove) {
    # The entries a project folder needs for the restricted token of its commands, or taken away:
    # Modify for the SID of the project (without it a command may not write there), passed on to
    # everything inside; OWNER RIGHTS may only read the rights of a file (passed on to files only,
    # at every depth), so a file a command made gives it no right to change its rights, and through
    # that to write, when it runs in another project (the account is among the SIDs of its token);
    # folders it makes are handed to the user after each command instead (scripts\sandbox\Watch.cs),
    # because Windows refuses to make a folder with rights of its own (Python's tempfile.mkdtemp)
    # where its owner may not change rights; and full control for the user, who otherwise changed
    # the rights of their own files as their owner. Through .NET: icacls does not take a SID no
    # account has. Written at once, so Windows walks through the folder once. The first time the
    # folders the account made there earlier go to the user. '' or why not.
    $rights = [System.Security.AccessControl.FileSystemRights]
    $both = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $files = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    try {
        $project = New-Object System.Security.Principal.SecurityIdentifier (Get-SandboxProjectSid $Folder)
        $owner = New-Object System.Security.Principal.SecurityIdentifier 'S-1-3-4'
        $me = New-Object System.Security.Principal.SecurityIdentifier (Get-CurrentUserSid)
        $ds = [System.IO.Directory]::GetAccessControl($Folder, [System.Security.AccessControl.AccessControlSections]::Access)
        if ($Remove) {
            $ds.PurgeAccessRules($project)
            $ds.PurgeAccessRules($owner)
            [System.IO.Directory]::SetAccessControl($Folder, $ds)
            return ''
        }
        $want = @(
            @{ sid = $project; rights = $rights::Modify; inherit = $both },
            @{ sid = $owner; rights = $rights::ReadPermissions; inherit = $files },
            @{ sid = $me; rights = $rights::FullControl; inherit = $both })
        $changed = $false
        $first = $false
        foreach ($w in $want) {
            $there = $false
            foreach ($rule in $ds.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                if ($rule.IdentityReference -ne $w.sid -or $rule.AccessControlType -ne 'Allow') { continue }
                # an entry for OWNER RIGHTS that also reaches folders (before 2026-11-24 evening) goes
                if ($w.sid -eq $owner -and -not $rule.IsInherited -and $rule.InheritanceFlags -ne $files) { $ds.PurgeAccessRules($owner); $changed = $true; $there = $false; break }
                if ((($rule.FileSystemRights -band $w.rights) -eq $w.rights) -and (($rule.InheritanceFlags -band $w.inherit) -eq $w.inherit) -and -not ([int]$rule.PropagationFlags -band 2)) { $there = $true }
            }
            if ($there) { continue }
            $ds.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($w.sid, $w.rights, $w.inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)))
            $changed = $true
            if ($w.sid -eq $project) { $first = $true }
        }
        if ($changed) { [System.IO.Directory]::SetAccessControl($Folder, $ds) }
        if ($first -and ('Unzensiert.SandboxWatch' -as [type])) { [Unzensiert.SandboxWatch]::TakeFoldersOf($Folder, (Get-SandboxSetup).accountSid) }
        return ''
    } catch {
        return $_.Exception.Message
    }
}

function Test-SandboxGrant([string]$Folder, [string]$GroupSid, [string]$Rights) {
    # Does the folder let the group in with M (change) or RX (read and run), by an entry that
    # passes on to everything inside?
    $need = [System.Security.AccessControl.FileSystemRights]::Modify
    if ($Rights -eq 'RX') { $need = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
    try { $acl = Get-Acl -LiteralPath $Folder } catch { return $false }
    foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ([string]$rule.IdentityReference.Value -ne $GroupSid -or $rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        $both = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        if ((($rule.FileSystemRights -band $need) -eq $need) -and (($rule.InheritanceFlags -band $both) -eq $both)) { return $true }
    }
    return $false
}

function Test-SandboxProjectFolder([string]$Folder) {
    # '' if the sandbox may change $Folder, or why not: never the program folder or the install
    # folder of Unzensiert, a folder that holds one of them, or a folder inside the program folder
    # (its scripts run as the user; M19 closes these folders at every start anyway); inside the
    # install folder only below the folder of the benchmark tasks.
    $full = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\')
    $install = ''
    try { $install = [System.IO.Path]::GetFullPath([string](Get-ServerConfig).installRoot).TrimEnd('\') } catch {}
    $program = [System.IO.Path]::GetFullPath([string]$script:ProjectRoot).TrimEnd('\')
    foreach ($p in @($install, $program)) {
        if ($p -and (Test-PathInside $p $full)) { return 'it is or holds a folder of Unzensiert itself' }
    }
    if (Test-PathInside $full $program) { return 'it lies in the program folder of Unzensiert' }
    if ($install -and (Test-PathInside $full $install)) {
        $work = ''
        try { $work = [System.IO.Path]::GetFullPath([string](Get-BenchmarkConfig).workDir).TrimEnd('\') } catch {}
        if (-not $work -or $full -ieq $work -or -not (Test-PathInside $full $work)) { return 'it lies in the install folder of Unzensiert' }
    }
    return ''
}

function Grant-SandboxFolder([string]$Folder, [string]$Rights, [string]$GroupSid = '') {
    # Lets the group of the sandbox into $Folder: M (change: a project folder) or RX (read and run:
    # a tool folder). Never a drive, the user folder or a folder of Windows, and change never in a
    # folder of Unzensiert itself. A project folder also gets the entry for its own SID, without
    # which the restricted token of a command may not write there (scripts\sandbox\Runner.cs): the
    # entry for the group stays on every folder the sandbox was ever in, the SID is only in the
    # token of commands of this folder. The owner of a folder may do this without an
    # administrator. Returns '' or why not.
    if (-not $GroupSid) { $GroupSid = (Get-SandboxSetup).groupSid }
    $why = Test-FolderProtectable $Folder
    if (-not $why -and $Rights -eq 'M') { $why = Test-SandboxProjectFolder $Folder }
    if ($why) { return $why }
    if (-not (Test-SandboxGrant $Folder $GroupSid $Rights)) {
        $saved = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $out = @(& (Get-SystemProgram 'icacls') $Folder /grant "*${GroupSid}:(OI)(CI)$Rights" /Q 2>&1 | ForEach-Object { "$_" }) }
        finally { $ErrorActionPreference = $saved }
        if ($LASTEXITCODE -ne 0) { return (($out -join ' ').Trim()) }
    }
    if ($Rights -eq 'M') {
        $why = Grant-SandboxProjectSid $Folder
        if ($why) { return "the entry for the SID of the project: $why" }
    }
    # also an entry that was there already: Setup-Sandbox.ps1 -Remove takes away what is listed
    Add-SandboxGranted "$Rights $Folder"
    return ''
}

function Add-SandboxGranted([string]$Line) {
    # One line of granted.txt (the folders the group was let into), once.
    $file = Join-Path (Get-SandboxFolder) 'granted.txt'
    try {
        if ([System.IO.File]::Exists($file) -and @([System.IO.File]::ReadAllLines($file)) -contains $Line) { return }
        Add-Content -LiteralPath $file -Value $Line -Encoding UTF8
    } catch {}
}

function Set-SandboxListEntry([string]$Dir, [string]$GroupSid, [switch]$Remove) {
    # Adds (or removes) the entry "may list this folder" for the group, written with SetFileSecurity
    # of Windows: icacls and Set-Acl walk through everything below the folder when they change it,
    # which takes minutes in the user folder, and this entry passes on to nothing below anyway.
    # Returns '' or what went wrong.
    if (-not ('Unzensiert.FileSecurity' -as [type])) {
        Add-Type -Namespace Unzensiert -Name FileSecurity -MemberDefinition '[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool SetFileSecurityW(string name, uint info, byte[] descriptor);'
    }
    try {
        $sd = New-Object System.Security.AccessControl.RawSecurityDescriptor ((Get-Acl -LiteralPath $Dir).GetSecurityDescriptorSddlForm('Access'))
        $sid = New-Object System.Security.Principal.SecurityIdentifier $GroupSid
        $dacl = $sd.DiscretionaryAcl
        if ($Remove) {
            for ($i = $dacl.Count - 1; $i -ge 0; $i--) {
                $a = $dacl[$i]
                # (AceFlags is a byte enum: -band on it fails in Windows PowerShell 5.1, IsInherited does not)
                if ($a -is [System.Security.AccessControl.CommonAce] -and $a.SecurityIdentifier -eq $sid -and -not $a.IsInherited) { $dacl.RemoveAce($i) }
            }
        } else {
            $rights = [int]([System.Security.AccessControl.FileSystemRights]'ListDirectory, ReadAttributes, Traverse, Synchronize')
            $ace = New-Object System.Security.AccessControl.CommonAce ([System.Security.AccessControl.AceFlags]::None, [System.Security.AccessControl.AceQualifier]::AccessAllowed, $rights, $sid, $false, $null)
            # after the entries of the folder itself that deny, before all others (the order Windows expects)
            $at = 0
            while ($at -lt $dacl.Count -and -not $dacl[$at].IsInherited -and $dacl[$at].AceQualifier -eq [System.Security.AccessControl.AceQualifier]::AccessDenied) { $at++ }
            $dacl.InsertAce($at, $ace)
        }
        # keep the mark "passed on automatically" (AI): SetFileSecurity drops it unless it is asked
        # for (0x0400 SE_DACL_AUTO_INHERITED, 0x0100 SE_DACL_AUTO_INHERIT_REQ; ints, the enum is short)
        if ([int]$sd.ControlFlags -band 0x0400) { $sd.SetFlags([System.Security.AccessControl.ControlFlags]([int]$sd.ControlFlags -bor 0x0100)) }
        $bytes = New-Object byte[] $sd.BinaryLength
        $sd.GetBinaryForm($bytes, 0)
        # 4 = DACL_SECURITY_INFORMATION: only the list of entries is written
        if (-not [Unzensiert.FileSecurity]::SetFileSecurityW($Dir, 4, $bytes)) { return "Windows error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
        return ''
    } catch {
        return $_.Exception.Message
    }
}

function Test-SandboxCanList([string]$Dir, [string]$GroupSid) {
    # May a command of the sandbox list this folder? By an entry for its group, Users, Everyone or
    # INTERACTIVE; "Authenticated Users" does not count, the runner takes it away.
    $who = @($GroupSid, 'S-1-5-32-545', 'S-1-1-0', 'S-1-5-4')
    $list = [int][System.Security.AccessControl.FileSystemRights]::ListDirectory
    foreach ($rule in (Get-Acl -LiteralPath $Dir).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or $who -notcontains [string]$rule.IdentityReference.Value) { continue }
        # an entry only for what lies below does not count for the folder itself
        if ([int]$rule.PropagationFlags -band [int][System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if ([int]$rule.FileSystemRights -band $list) { return $true }
    }
    return $false
}

function Grant-SandboxParents([string]$Folder, [string]$GroupSid = '') {
    # Folders above a project that a command of the sandbox may not list (the user folder, the
    # install folder): its group may list them, names only, nothing inside them, nothing passed on.
    # PowerShell reads the names on the way to its current folder and would otherwise start in C:\
    # and refuse every path of the project. Drives stay as they are. '' or why not.
    if (-not $GroupSid) { $GroupSid = (Get-SandboxSetup).groupSid }
    $dir = Split-Path -Parent ([System.IO.Path]::GetFullPath($Folder).TrimEnd('\'))
    while ($dir -and $dir.TrimEnd('\').Length -gt 2) {
        try { $can = Test-SandboxCanList $dir $GroupSid } catch { return "$dir cannot be read" }
        if (-not $can) {
            $problem = Set-SandboxListEntry $dir $GroupSid
            if ($problem) { return "$dir`: $problem" }
            Add-SandboxGranted "L $dir"
        }
        $dir = Split-Path -Parent $dir
    }
    return ''
}

function Get-SandboxToolFolders {
    # Folders of PATH inside the user folder (Python, Node, tools installed for the user only):
    # the account cannot read them unless its group is let in.
    $home0 = ([string]$env:USERPROFILE).TrimEnd('\')
    $list = @()
    foreach ($p in @(([string]$env:PATH).Split(';'))) {
        $f = $p.Trim().Trim('"').TrimEnd('\')
        if (-not $f -or -not $home0 -or -not (Test-PathInside $f $home0) -or $f -ieq $home0) { continue }
        if (-not [System.IO.Directory]::Exists($f) -or $list -contains $f) { continue }
        $list += $f
    }
    return $list
}

function Initialize-SandboxSession($Session) {
    # Whether the commands of this session run in the sandbox. The first time in a folder its group
    # gets the right to change the project folder, and tools of PATH in the user folder the right to
    # be read. Sets $Session.sandbox and $Session.sandboxWhy ('' or why not).
    $Session.sandbox = $false
    $s = Get-SandboxSetup
    if (-not $s.ready) { $Session.sandboxWhy = $s.why; return }
    $problem = Update-SandboxRunner
    if (-not $problem) { $problem = Update-SandboxWatch }
    if (-not $problem) { $problem = Import-SandboxWatch }
    if ($problem) { $Session.sandboxWhy = $problem; return }
    $why = Grant-SandboxFolder $Session.cwd 'M'
    if (-not $why) { $why = Grant-SandboxParents $Session.cwd }
    if ($why) { $Session.sandboxWhy = "project folder: $why"; return }
    foreach ($f in @(Get-SandboxToolFolders)) { $null = Grant-SandboxFolder $f 'RX' }
    $Session.sandbox = $true
    $Session.sandboxWhy = ''
}

function Get-SandboxWhyText($Session) {
    # Why the session has no sandbox, in the words of config\unzensiert-texts.json (a message of
    # Windows or about the folder as it is).
    $why = [string]$Session.sandboxWhy
    if (-not $why) { return '' }
    $text = Get-UiText "sandbox.why.$why"
    if ($text -eq "sandbox.why.$why") { return $why }
    return $text
}

function Get-SandboxSourceHash([string[]]$Files) {
    # SHA-256 over the sources of the sandbox in scripts\sandbox: built again when they change.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $all = New-Object System.IO.MemoryStream
        foreach ($f in $Files) { $b = [System.IO.File]::ReadAllBytes((Join-Path $script:ProjectRoot "scripts\sandbox\$f")); $all.Write($b, 0, $b.Length) }
        return (-join ($sha.ComputeHash($all.ToArray()) | ForEach-Object { $_.ToString('x2') }))
    } finally { $sha.Dispose() }
}

function Get-SandboxCompiler {
    # The C# compiler of Windows (.NET Framework 4), or ''.
    foreach ($bits in 'Framework64', 'Framework') {
        $csc = Join-Path $env:WINDIR "Microsoft.NET\$bits\v4.0.30319\csc.exe"
        if ([System.IO.File]::Exists($csc)) { return $csc }
    }
    return ''
}

function Stop-SandboxService([int]$Seconds = 20) {
    # Stops the runner (the user may: the rights Setup-Sandbox.ps1 gave the service); running
    # commands end with it. '' or why not.
    $name = [string](Get-SandboxSettings).service
    try {
        $svc = Get-Service -Name $name -ErrorAction Stop
        if ($svc.Status -eq 'Stopped') { return '' }
        if ($svc.Status -ne 'StopPending') { $svc.Stop() }
        $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($Seconds))
        return ''
    } catch {
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { return '' }
        return "the sandbox service does not stop: $($_.Exception.Message)"
    }
}

function Update-SandboxRunner([switch]$Force) {
    # Builds bin\unzensiert-runner.exe (the program of the service) from scripts\sandbox\Runner.cs
    # with the csc.exe of Windows when it is missing or the source changed, after stopping the
    # service; bin\ may be read and run by the group of the sandbox, not changed. Returns '' or what
    # went wrong.
    $dir = Join-Path (Get-SandboxFolder) 'bin'
    $exe = Join-Path $dir 'unzensiert-runner.exe'
    $stamp = Join-Path $dir 'runner.sha256'
    $hash = Get-SandboxSourceHash @('Runner.cs')
    if (-not $Force -and [System.IO.File]::Exists($exe) -and [System.IO.File]::Exists($stamp) -and ([System.IO.File]::ReadAllText($stamp).Trim() -eq $hash)) { return '' }
    $csc = Get-SandboxCompiler
    if (-not $csc) { return 'the C# compiler of Windows (.NET Framework 4) is missing' }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # the running service holds its program: it ends first (an update of Runner.cs)
    $problem = Stop-SandboxService
    if ($problem) { return $problem }
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $csc /nologo /optimize /target:exe /platform:anycpu /r:System.ServiceProcess.dll "/out:$exe" (Get-RunnerSource) 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $saved }
    if ($LASTEXITCODE -ne 0 -or -not [System.IO.File]::Exists($exe)) { return "building the runner failed: $(($out | Select-Object -First 3) -join ' ')" }
    [System.IO.File]::WriteAllText($stamp, $hash)
    return ''
}

function Get-SandboxWatchFile {
    # The DLL of the watch and the client, named after the SHA-256 of scripts\sandbox\Watch.cs and
    # Client.cs: a session that has an older one loaded keeps it, a new one is built next to it.
    return [string](Join-Path (Get-SandboxFolder) "bin\unzensiert-sandbox-$((Get-SandboxSourceHash @('Watch.cs', 'Client.cs')).Substring(0, 12)).dll")
}

function Update-SandboxWatch {
    # Builds the DLL from scripts\sandbox\Watch.cs and Client.cs with the csc.exe of Windows when it is
    # missing, and removes older ones that are no longer loaded. Returns '' or what went wrong.
    $dll = Get-SandboxWatchFile
    if ([System.IO.File]::Exists($dll)) { return '' }
    $csc = Get-SandboxCompiler
    if (-not $csc) { return 'the C# compiler of Windows (.NET Framework 4) is missing' }
    $dir = Split-Path -Parent $dll
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $csc /nologo /optimize /target:library /platform:anycpu "/out:$dll" (Join-Path $script:ProjectRoot 'scripts\sandbox\Watch.cs') (Join-Path $script:ProjectRoot 'scripts\sandbox\Client.cs') 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $saved }
    if ($LASTEXITCODE -ne 0 -or -not [System.IO.File]::Exists($dll)) { return "building the watch failed: $(($out | Select-Object -First 3) -join ' ')" }
    foreach ($old in @(Get-ChildItem -LiteralPath $dir -Filter 'unzensiert-*.dll' -ErrorAction SilentlyContinue)) {
        if ($old.FullName -ne $dll) { Remove-Item -Force -LiteralPath $old.FullName -ErrorAction SilentlyContinue }
    }
    return ''
}

function Import-SandboxWatch {
    # Loads the watch and the client into this process once. Returns '' or what went wrong.
    if ('Unzensiert.SandboxCommand' -as [type]) { return '' }
    try { Add-Type -LiteralPath (Get-SandboxWatchFile) -ErrorAction Stop; return '' }
    catch { return "the watch cannot be loaded: $($_.Exception.Message)" }
}

function Start-SandboxWatch($Session) {
    # Before a command of the sandbox (scripts\sandbox\Watch.cs): the repositories of the user and
    # the protected files of the project ("protectedFiles" in config\guard.json) become read-only for
    # its group, and a watcher deals with what appears while it runs. Returns the watch; throws when
    # something cannot be protected, and the command must not run in the sandbox then.
    $s = Get-SandboxSetup
    $patterns = [string[]]@(@((Get-SessionGuard $Session).protectedFiles) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    # caches are not looked into; .idea and .vs are protected folders of editors
    $skip = [string[]]@($script:SkipFolders | Where-Object { @('.git', '.idea', '.vs') -notcontains $_ })
    $watch = New-Object Unzensiert.SandboxWatch -ArgumentList @([string]$Session.cwd, $patterns, $skip, [string]$s.groupSid, [string]$s.accountSid)
    $problem = $watch.Prepare()
    if ($problem) { $watch.Dispose(); throw "these cannot be made read-only for it: $problem" }
    $watch.Start()
    return $watch
}

function Stop-SandboxWatch($Watch) {
    # After the command: the watcher stops, the folder is checked once more. Returns what was removed
    # or renamed, as lines.
    try { return @($Watch.Finish()) } finally { $Watch.Dispose() }
}

function Get-SandboxIdentity {
    # Name and e-mail of the user for commits made in the sandbox (the account has no git
    # configuration of its own), read once.
    if ($null -eq $script:SandboxIdentity) {
        $script:SandboxIdentity = @{ name = ''; email = '' }
        foreach ($k in 'name', 'email') {
            $r = Invoke-Git $env:USERPROFILE @('config', '--global', "user.$k")
            if ($r.code -eq 0) { $script:SandboxIdentity[$k] = ((@($r.lines) -join '').Trim()) }
        }
    }
    return $script:SandboxIdentity
}

function New-SandboxPayload($Session, [string]$Kind, [string]$Command) {
    # What the runner gets through its pipe (scripts\sandbox\Runner.cs): program, arguments, the
    # script, the project folder and its SID, and the environment of the command (on top of the
    # environment of the account: PATH, git, Python), as UTF-8 bytes.
    if ($Kind -eq 'Bash') {
        $program = [string]$Session.gitBash
        $arguments = '"{script}"'
        $ext = '.sh'
        $text = $Command.Replace("`r`n", "`n") + "`n"
    } else {
        $program = Get-SystemProgram 'powershell'
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{script}"'
        $ext = '.ps1'
        $text = "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; `$OutputEncoding = [System.Text.Encoding]::UTF8; `$ProgressPreference = 'SilentlyContinue'`r`n" + $Command + "`r`nif (`$LASTEXITCODE) { exit `$LASTEXITCODE }`r`n"
    }
    $vars = [ordered]@{}
    $vars['PATH'] = [string]$env:PATH
    $vars['PYTHONIOENCODING'] = 'utf-8'
    $vars['NoDefaultCurrentDirectoryInExePath'] = '1'
    # git: the same safety as outside; repositories of the user count as safe for the account (it
    # is not their owner); commits carry the name of the user and the co-author line
    Set-GitSafety $vars
    Add-GitConfig $vars 'safe.directory' '*'
    # the repositories of the user are read-only for the account (Watch.cs): git status and the
    # like do not try to refresh the index there
    $vars['GIT_OPTIONAL_LOCKS'] = '0'
    $id = Get-SandboxIdentity
    if ($id.name) { $vars['GIT_AUTHOR_NAME'] = $id.name; $vars['GIT_COMMITTER_NAME'] = $id.name }
    if ($id.email) { $vars['GIT_AUTHOR_EMAIL'] = $id.email; $vars['GIT_COMMITTER_EMAIL'] = $id.email }
    $coAuthor = Get-CoAuthorSetup
    if ($coAuthor.hook) { Set-CoAuthorHook $vars $coAuthor.trailer }
    $fields = @('2', ((Get-SandboxSettings).disableGroups -join ','), $program, $arguments, $ext, $text, [string]$Session.cwd, (Get-SandboxProjectSid $Session.cwd))
    foreach ($k in $vars.Keys) { $fields += "$k=$($vars[$k])" }
    return , [System.Text.Encoding]::UTF8.GetBytes(($fields -join [string][char]0))
}

function Start-SandboxProcess($Session, [byte[]]$Payload) {
    # Hands the command to the runner (the service, started when it is stopped) after checking that
    # the process at the other end of its pipe is that service. Returns an Unzensiert.SandboxCommand
    # (scripts\sandbox\Client.cs): Output and Errors (bytes), WaitForExit, ExitCode, and Kill, which
    # ends the command with everything it started. Throws with the reason.
    $s = Get-SandboxSetup
    $problem = Import-SandboxWatch
    if ($problem) { throw $problem }
    return [Unzensiert.SandboxCommand]::Start($s.service, (Get-SandboxPipeName), $Payload, 20000)
}
