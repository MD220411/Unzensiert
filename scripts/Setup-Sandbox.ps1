# Sets up the sandbox of Unzensiert on this computer, or takes it away again (docs\security.md,
# "Sandbox"): a hidden Windows account of its own for the commands of the model, its group, a
# firewall rule that lets the account reach no other computer, and the runner, a service of that
# account (built from scripts\sandbox\Runner.cs with the csc.exe of Windows) that starts the
# commands in a sign-in of its own; the account may sign in as a service and in no other way, and
# only this user may start and stop the service. Making the account, the rule and the service
# needs an administrator once: Windows asks (UAC). Repeatable: what is in order stays, and only a
# missing part asks for the administrator again (with a new password for the account, which only
# the service keeps). Names: "sandbox" in config\unzensiert.json; what this computer got:
# "sandbox" in config\machine.json.
#
#   powershell -ExecutionPolicy Bypass -File scripts\Setup-Sandbox.ps1              set up or repair
#   powershell -ExecutionPolicy Bypass -File scripts\Setup-Sandbox.ps1 -Plan        show what is missing
#   powershell -ExecutionPolicy Bypass -File scripts\Setup-Sandbox.ps1 -Repair      set everything up again
#   powershell -ExecutionPolicy Bypass -File scripts\Setup-Sandbox.ps1 -Remove      take everything away
#   powershell -ExecutionPolicy Bypass -File scripts\Setup-Sandbox.ps1 -AllowRead D:\Tools\go
#                                                   the account may also read and run this tool folder
#
# Exit code 0 = done (or nothing to do), 1 = it failed; the reason is printed.

param([switch]$Plan, [switch]$Repair, [switch]$Remove, [string[]]$AllowRead = @(), [string]$ElevatedLog = '', [string]$SecretFile = '', [string]$UserSid = '', [string]$RunnerPath = '')

. "$PSScriptRoot\_common.ps1"

$cfg = Get-SandboxSettings
$hideKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
# descriptions of local accounts and groups take at most 48 characters; accounts and groups share
# one namespace, so the group must not be called like the account
$userNote = 'Unzensiert: commands of the model (sandbox)'
$groupNote = 'Unzensiert: sandbox accounts'

function Get-SandboxParts {
    # What of the sandbox this computer has. The service counts when it starts this runner for
    # this user.
    $u = Get-LocalUser -Name $cfg.account -ErrorAction SilentlyContinue
    $g = Get-LocalGroup -Name $cfg.group -ErrorAction SilentlyContinue
    $rule = $null
    try { $rule = Get-NetFirewallRule -Name $cfg.firewallRule -ErrorAction SilentlyContinue } catch {}
    $member = $false
    if ($u -and $g) { $member = (@(Get-LocalGroupMember -Name $cfg.group -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq $u.SID.Value }).Count -gt 0) }
    $hidden = $false
    try { $hidden = ([int](Get-ItemProperty -Path $hideKey -Name $cfg.account -ErrorAction Stop).($cfg.account) -eq 0) } catch {}
    $service = $false
    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$($cfg.service)'" -ErrorAction Stop
        $service = $svc -and ([string]$svc.PathName -eq (Get-RunnerCommandLine)) -and ([string]$svc.StartName -match "\\$([regex]::Escape($cfg.account))$")
    } catch {}
    return @{ user = $u; group = $g; rule = $rule; member = $member; hidden = $hidden; service = $service }
}

function Get-RunnerCommandLine([string]$Sid = '', [string]$Runner = '') {
    # How the service starts the runner: for this user (the pipe only lets this user write). The
    # elevated step gets both from the user's part: an administrator of another account would find
    # another install folder under %LOCALAPPDATA%.
    if (-not $Sid) { $Sid = Get-CurrentUserSid }
    if (-not $Runner) { $Runner = (Get-SandboxSetup -Fresh).runner }
    return "`"$Runner`" --service --user $Sid --name $($cfg.service)"
}

function Set-AccountRights([string]$Sid, [string[]]$Add, [string[]]$Take) {
    # Gives the account logon rights or takes them away (local security policy, LSA).
    if (-not ('Unzensiert.LsaRights' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
namespace Unzensiert {
public static class LsaRights {
    [StructLayout(LayoutKind.Sequential)] struct LSA_UNICODE_STRING { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory, ObjectName; public int Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref LSA_OBJECT_ATTRIBUTES attributes, int access, out IntPtr policy);
    [DllImport("advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr policy, byte[] sid, LSA_UNICODE_STRING[] rights, int count);
    [DllImport("advapi32.dll")] static extern uint LsaRemoveAccountRights(IntPtr policy, byte[] sid, bool all, LSA_UNICODE_STRING[] rights, int count);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
    // 0 or a Windows error; taking away a right the account does not have is no error
    public static int Change(string sid, string right, bool add) {
        var attributes = new LSA_OBJECT_ATTRIBUTES { Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES)) };
        IntPtr policy;
        uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, 0x10 | 0x800, out policy);
        if (status != 0) return LsaNtStatusToWinError(status);
        var s = new SecurityIdentifier(sid);
        var bytes = new byte[s.BinaryLength];
        s.GetBinaryForm(bytes, 0);
        var name = new LSA_UNICODE_STRING { Length = (ushort)(right.Length * 2), MaximumLength = (ushort)(right.Length * 2 + 2), Buffer = Marshal.StringToHGlobalUni(right) };
        try {
            status = add ? LsaAddAccountRights(policy, bytes, new[] { name }, 1) : LsaRemoveAccountRights(policy, bytes, false, new[] { name }, 1);
            int e = status == 0 ? 0 : LsaNtStatusToWinError(status);
            return (!add && e == 2) ? 0 : e;
        } finally { Marshal.FreeHGlobal(name.Buffer); LsaClose(policy); }
    }
}
}
'@
    }
    foreach ($r in $Add) { $e = [Unzensiert.LsaRights]::Change($Sid, $r, $true); if ($e) { throw "giving $r failed (Windows error $e)" } }
    foreach ($r in $Take) { $e = [Unzensiert.LsaRights]::Change($Sid, $r, $false); if ($e) { throw "taking away $r failed (Windows error $e)" } }
}

# the account signs in as a service and in no other way (not at the screen, not over the network,
# not as a batch job): its password, which only the service keeps, opens nothing else
$script:DenyRights = @('SeDenyInteractiveLogonRight', 'SeDenyNetworkLogonRight', 'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight')

# --- the part that needs an administrator (this script, started again elevated) ---------------------
if ($ElevatedLog) {
    $log = New-Object System.Collections.Generic.List[string]
    $step = ''
    try {
        if ($Remove) {
            $step = 'service'
            if (Get-Service -Name $cfg.service -ErrorAction SilentlyContinue) {
                Stop-Service -Name $cfg.service -Force -ErrorAction SilentlyContinue
                $null = & (Get-SystemProgram 'sc') delete $cfg.service
            }
            $step = 'firewall rule'
            Get-NetFirewallRule -Name $cfg.firewallRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
            $step = 'account and its profile'
            $u = Get-LocalUser -Name $cfg.account -ErrorAction SilentlyContinue
            if ($u) {
                # the rights in the security policy name its SID and would stay behind
                Set-AccountRights $u.SID.Value @() (@('SeServiceLogonRight') + $script:DenyRights)
                Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $u.SID.Value } | Remove-CimInstance
                Remove-LocalUser -Name $cfg.account
            }
            $step = 'group'
            if (Get-LocalGroup -Name $cfg.group -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $cfg.group }
            $step = 'sign-in screen'
            if (Test-Path $hideKey) { Remove-ItemProperty -Path $hideKey -Name $cfg.account -ErrorAction SilentlyContinue }
            $log.Add('removed')
        } else {
            $step = 'password'
            $secret = ConvertTo-SecureString ([System.IO.File]::ReadAllText($SecretFile).Trim()) -AsPlainText -Force
            $step = 'group'
            if (-not (Get-LocalGroup -Name $cfg.group -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $cfg.group -Description $groupNote | Out-Null }
            $step = 'account'
            if (Get-LocalUser -Name $cfg.account -ErrorAction SilentlyContinue) { Set-LocalUser -Name $cfg.account -Password $secret }
            else { New-LocalUser -Name $cfg.account -Password $secret -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires -Description $userNote | Out-Null }
            $sid = (Get-LocalUser -Name $cfg.account).SID.Value
            $step = 'groups of the account'
            if (-not @(Get-LocalGroupMember -Name $cfg.group -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq $sid }).Count) { Add-LocalGroupMember -Name $cfg.group -Member $cfg.account }
            if (-not @(Get-LocalGroupMember -SID 'S-1-5-32-545' -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq $sid }).Count) { Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $cfg.account }
            $step = 'sign-in screen'
            if (-not (Test-Path $hideKey)) { New-Item -Path $hideKey -Force | Out-Null }
            New-ItemProperty -Path $hideKey -Name $cfg.account -Value 0 -PropertyType DWord -Force | Out-Null
            $step = 'firewall rule'
            Get-NetFirewallRule -Name $cfg.firewallRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
            # everything but this computer itself (127.0.0.0/8, ::1)
            New-NetFirewallRule -Name $cfg.firewallRule -DisplayName 'Unzensiert sandbox: no network' -Description "Commands of the model that run as $($cfg.account) reach no other computer." `
                -Direction Outbound -Action Block -Profile Any -LocalUser "O:LSD:(A;;CC;;;$sid)" `
                -RemoteAddress @('0.0.0.0-126.255.255.255', '128.0.0.0-255.255.255.255', '::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff') | Out-Null
            $step = 'logon rights'
            Set-AccountRights $sid (@('SeServiceLogonRight') + $script:DenyRights) @()
            $step = 'service'
            if (Get-Service -Name $cfg.service -ErrorAction SilentlyContinue) {
                Stop-Service -Name $cfg.service -Force -ErrorAction SilentlyContinue
                $null = & (Get-SystemProgram 'sc') delete $cfg.service
                # the service control manager removes it once nothing holds it any more
                for ($i = 0; $i -lt 50 -and (Get-Service -Name $cfg.service -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
            }
            $credential = New-Object System.Management.Automation.PSCredential(".\$($cfg.account)", $secret)
            if (-not $UserSid -or -not $RunnerPath) { throw 'the user and the runner were not handed over' }
            New-Service -Name $cfg.service -BinaryPathName (Get-RunnerCommandLine $UserSid $RunnerPath) -DisplayName 'Unzensiert sandbox' `
                -Description 'Runs the commands of the model of Unzensiert as a Windows account of their own; started by Unzensiert when needed.' `
                -StartupType Manual -Credential $credential | Out-Null
            # this user may start, stop and look at it, nobody else but the administrators and SYSTEM
            $sddl = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWRPWPLORC;;;$UserSid)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)"
            $out = & (Get-SystemProgram 'sc') sdset $cfg.service $sddl
            if ($LASTEXITCODE -ne 0) { throw "setting the rights of the service failed: $($out -join ' ')" }
            $log.Add('done')
        }
    } catch {
        $log.Add("ERROR in step '$step': $($_.Exception.Message)")
    }
    [System.IO.File]::WriteAllLines($ElevatedLog, $log)
    exit 0
}

function Invoke-Elevated([string[]]$Arguments) {
    # This script again with administrator rights; Windows asks. Returns the lines of its log.
    $logFile = Join-Path $env:TEMP ("unzensiert-sandbox-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.log')
    $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-ElevatedLog', "`"$logFile`"") + $Arguments
    try {
        $p = Start-Process -FilePath (Get-SystemProgram 'powershell') -ArgumentList $list -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        if (-not [System.IO.File]::Exists($logFile)) { return @("ERROR: the elevated step wrote nothing (exit code $($p.ExitCode))") }
        return @([System.IO.File]::ReadAllLines($logFile))
    } catch {
        return @("ERROR: administrator rights were not given ($($_.Exception.Message))")
    } finally {
        Remove-Item -Force -LiteralPath $logFile -ErrorAction SilentlyContinue
    }
}

function Test-SandboxRuns {
    # The service starts, and runs a command as the account: '' or what went wrong.
    $s = Get-SandboxSetup -Fresh
    if (-not $s.ready) { return "not ready ($($s.why))" }
    $bin = Split-Path -Parent $s.runner
    $fields = @('2', ($cfg.disableGroups -join ','), (Get-SystemProgram 'cmd'), '/c whoami', '', '', $bin, (Get-SandboxProjectSid $bin))
    try {
        $p = Start-SandboxProcess $null ([System.Text.Encoding]::UTF8.GetBytes(($fields -join [string][char]0)))
        if (-not $p.WaitForExit(30000)) { $p.Kill(); return 'the test command did not end' }
        $out = (ConvertFrom-OutputBytes $p.Output.ToArray()) + (ConvertFrom-OutputBytes $p.Errors.ToArray())
        $p.Dispose()
        if ($out -notmatch [regex]::Escape($cfg.account)) { return "the test command answered: $($out.Trim())" }
        return ''
    } catch { return $_.Exception.Message }
}

$parts = Get-SandboxParts
$dir = Get-SandboxFolder
# the password of the account is kept by the service alone since 2026-11-24
$oldSecret = Join-Path $dir 'account.dpapi'

if ($Plan) {
    $rows = @(
        @('account', $cfg.account, [bool]$parts.user), @('group', $cfg.group, [bool]$parts.group),
        @('account in the group', '', $parts.member), @('hidden from the sign-in screen', '', $parts.hidden),
        @('firewall rule', $cfg.firewallRule, [bool]$parts.rule), @('service for this user', $cfg.service, $parts.service),
        @('runner', (Get-SandboxSetup -Fresh).runner, [System.IO.File]::Exists((Get-SandboxSetup).runner)))
    foreach ($r in $rows) { "{0,-8} {1} {2}" -f $(if ($r[2]) { 'there' } else { 'missing' }), $r[0], $r[1] }
    foreach ($f in @(Get-SandboxToolFolders) + $AllowRead) { "tool folder to be readable for the account: $f" }
    exit 0
}

if ($Remove) {
    # the entries for the group in folders first, while its SID is known
    $sid = ''
    if ($parts.group) { $sid = $parts.group.SID.Value }
    $granted = Join-Path $dir 'granted.txt'
    if ($sid -and [System.IO.File]::Exists($granted)) {
        # Windows PowerShell 5.1 turns lines on stderr of a program into errors under 'Stop'
        $ErrorActionPreference = 'Continue'
        foreach ($line in @([System.IO.File]::ReadAllLines($granted) | Select-Object -Unique)) {
            $f = ($line -replace '^\S+\s+', '').Trim()
            if (-not $f -or -not [System.IO.Directory]::Exists($f)) { continue }
            # "may list" above a project: without walking through the user folder (lib\Sandbox.ps1)
            if ($line.StartsWith('L ')) { $null = Set-SandboxListEntry $f $sid -Remove }
            else {
                $null = & (Get-SystemProgram 'icacls') $f /remove:g "*$sid" /Q 2>&1
                if ($line.StartsWith('M ')) {
                    # the deny entries of the watch on .git and protected files of a project (Watch.cs),
                    # and the entry for the SID of the project (made up from its path)
                    $null = & (Get-SystemProgram 'icacls') $f /remove:d "*$sid" /T /C /Q 2>&1
                    $null = Grant-SandboxProjectSid $f -Remove
                }
            }
        }
        $ErrorActionPreference = 'Stop'
    }
    if ($parts.user -or $parts.group -or $parts.rule -or $parts.hidden -or (Get-Service -Name $cfg.service -ErrorAction SilentlyContinue)) {
        Write-Note 'Windows asks for administrator rights once now (service, account, group, firewall rule).'
        $log = @(Invoke-Elevated @('-Remove'))
        $log | ForEach-Object { Write-Note $_ }
        if (($log -join ' ') -match 'ERROR') { exit 1 }
    }
    if ([System.IO.Directory]::Exists($dir)) { Remove-Item -Recurse -Force -LiteralPath $dir }
    $machine = Get-MachineConfig
    if ($machine.PSObject.Properties['sandbox']) { $machine.PSObject.Properties.Remove('sandbox'); Save-MachineConfig $machine }
    'sandbox: removed'
    exit 0
}

# --- set up or repair -------------------------------------------------------------------------------------
# the runner first: the service is made for its program (an older build of the service stops)
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$problem = Update-SandboxRunner
if (-not $problem) { $problem = Update-SandboxWatch }
if ($problem) { "sandbox: $problem"; exit 1 }
$needAdmin = $Repair -or -not $parts.user -or -not $parts.group -or -not $parts.member -or -not $parts.hidden -or -not $parts.rule -or -not $parts.service
if ($needAdmin) {
    # A new password, which the elevated step sets for the account and gives to the service, the
    # only one that keeps it. It goes there once through a file in the temp folder of the user (only
    # the user and the administrators may read it), deleted right after.
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $plain = [Convert]::ToBase64String($bytes) + 'a1!'
    $tmp = Join-Path $env:TEMP ("unzensiert-sandbox-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    try {
        [System.IO.File]::WriteAllText($tmp, $plain)
        Write-Note 'Windows asks for administrator rights once now (account, group, firewall rule, service).'
        $log = @(Invoke-Elevated @('-SecretFile', "`"$tmp`"", '-UserSid', (Get-CurrentUserSid), '-RunnerPath', "`"$((Get-SandboxSetup -Fresh).runner)`""))
    } finally {
        Remove-Item -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
        $plain = $null
    }
    $log | ForEach-Object { Write-Note $_ }
    if (($log -join ' ') -notmatch '^done$|\bdone\b' -or ($log -join ' ') -match 'ERROR') { 'sandbox: not set up.'; exit 1 }
    $parts = Get-SandboxParts
}
if ([System.IO.File]::Exists($oldSecret)) { Remove-Item -Force -LiteralPath $oldSecret -ErrorAction SilentlyContinue }

# what needs no administrator: the values of this computer, the rights on the runner and the tool
# folders
Set-MachineValue 'sandbox' 'account' $cfg.account
Set-MachineValue 'sandbox' 'groupSid' $parts.group.SID.Value
$null = Get-SandboxSetup -Fresh
$why = Grant-SandboxFolder (Join-Path $dir 'bin') 'RX' $parts.group.SID.Value
if ($why) { "sandbox: the runner cannot be opened by the account: $why"; exit 1 }
foreach ($f in @(@(Get-SandboxToolFolders) + $AllowRead)) {
    $why = Grant-SandboxFolder $f 'RX' $parts.group.SID.Value
    if ($why) { Write-Warn "tool folder $f stays closed to the account: $why" } else { Write-Note "the account may read and run $f" }
}
$problem = Test-SandboxRuns
if ($problem) { "sandbox: the service does not run commands ($problem); try -Repair."; exit 1 }
"sandbox: ready - the commands of the model run as $($cfg.account) from the next start of unzensiert."
exit 0
