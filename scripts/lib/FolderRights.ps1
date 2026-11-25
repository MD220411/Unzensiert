# Who may open the install folder and the program folder: only the user, SYSTEM and the
# administrators. On a drive other than the system drive Windows lets every account of the
# computer change new folders ("Authenticated Users: Modify"); another account, such as the
# account a sandbox runs commands as, could then change llama-server.exe or the scripts and so run
# code as the user, or read the conversations, the copies of /undo and the key of the server.
# Inside the user folder the rights are like this already and nothing changes. Description:
# docs\security.md ("Install and program folder"). Needs lib\Config.ps1. Keep this file ASCII-only.

# SYSTEM, Administrators, and the placeholders CREATOR OWNER and OWNER RIGHTS, which give nobody
# else anything
$script:OwnFolderSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-3-0', 'S-1-3-4')

function Get-CurrentUserSid {
    return [string][System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Get-SandboxGroupSid {
    # The group of the sandbox on this computer ("sandbox" in config\machine.json), or ''.
    try {
        $m = (Get-MachineConfig).PSObject.Properties['sandbox']
        if ($m -and $m.Value.groupSid) { return [string]$m.Value.groupSid }
    } catch {}
    return ''
}

function Test-ListOnlyRule($Rule) {
    # The entry the sandbox puts on folders above a project (lib\Sandbox.ps1, Grant-SandboxParents):
    # may list the names in this folder, nothing inside, passed on to nothing.
    $listOnly = [int][System.Security.AccessControl.FileSystemRights]'ListDirectory, ReadAttributes, ReadExtendedAttributes, Traverse, ReadPermissions, Synchronize'
    if ($Rule.IsInherited -or [int]$Rule.InheritanceFlags -ne 0) { return $false }
    return (([int]$Rule.FileSystemRights -band (-bnot $listOnly)) -eq 0)
}

function Get-FolderStrangers([string]$Folder) {
    # Accounts and groups besides the user, SYSTEM and the administrators the folder lets in,
    # whether to read or to change, as names; $null if its rights cannot be read (a drive without
    # them, such as FAT). The group of the sandbox may list the names in it (it needs that on the way
    # to a project below), nothing more. Assign the result to a variable: an empty list stays a list.
    try { $acl = Get-Acl -LiteralPath $Folder } catch { return $null }
    $me = Get-CurrentUserSid
    $sandbox = Get-SandboxGroupSid
    $names = @()
    foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        $sid = [string]$rule.IdentityReference.Value
        if ($sid -eq $me -or $script:OwnFolderSids -contains $sid) { continue }
        if ($sandbox -and $sid -eq $sandbox -and (Test-ListOnlyRule $rule)) { continue }
        $name = $sid
        try { $name = [string]$rule.IdentityReference.Translate([System.Security.Principal.NTAccount]).Value } catch {}
        if ($names -notcontains $name) { $names += $name }
    }
    return , $names
}

function Test-FolderProtectable([string]$Folder) {
    # '' if the rights of the folder may be changed; never those of a drive, a folder on another
    # computer, the user folder, the folder of all user folders or a folder of Windows.
    if (-not $Folder) { return 'no folder' }
    $full = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\')
    if ($full.Length -le 2 -or $full.StartsWith('\\')) { return 'a drive or a folder on another computer' }
    $profiles = ''
    if ($env:USERPROFILE) { $profiles = Split-Path -Parent $env:USERPROFILE }
    foreach ($v in @($env:USERPROFILE, $profiles, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA)) {
        if ($v -and $full -ieq ([string]$v).TrimEnd('\')) { return 'a folder of Windows or of all users' }
    }
    if (-not [System.IO.Directory]::Exists($full)) { return 'the folder does not exist' }
    return ''
}

function Set-FolderPrivate([string]$Folder) {
    # Only the user, SYSTEM and the administrators, with full rights that pass on to everything in
    # the folder; whatever else was allowed on it goes, and Windows passes the change on to the files
    # inside. Returns '' or what went wrong.
    $why = Test-FolderProtectable $Folder
    if ($why) { return $why }
    try {
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($sid in @((Get-CurrentUserSid), 'S-1-5-18', 'S-1-5-32-544')) {
            $id = New-Object System.Security.Principal.SecurityIdentifier($sid)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($id, [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)
            $sec.AddAccessRule($rule)
        }
        [System.IO.Directory]::SetAccessControl([System.IO.Path]::GetFullPath($Folder), $sec)
        return ''
    } catch {
        return $_.Exception.Message
    }
}

function Get-ProgramFolders {
    # The install folder (config\server.json, machine.json) and the program folder.
    $list = @()
    try { $list += [string](Get-ServerConfig).installRoot } catch {}
    $list += [string]$script:ProjectRoot
    return @($list | Where-Object { $_ })
}

function Protect-ProgramFolders([string[]]$Folders = @()) {
    # Closes the install folder and the program folder to every account but the user's (above).
    # Returns notes for what changed or could not be changed; none when all was in order.
    if ($Folders.Count -eq 0) { $Folders = @(Get-ProgramFolders) }
    $notes = @()
    foreach ($f in $Folders) {
        if (-not $f -or -not [System.IO.Directory]::Exists($f)) { continue }
        $strangers = Get-FolderStrangers $f
        if ($null -eq $strangers -or @($strangers).Count -eq 0) { continue }
        $problem = Set-FolderPrivate $f
        $who = @($strangers) -join ', '
        if ($problem) { $notes += "the folder $f stays open to $who ($problem)" }
        else { $notes += "the folder $f is now only for you (before also for $who)" }
    }
    # no comma: an empty list must give nothing at @(...) of the caller, not one empty entry
    return $notes
}
