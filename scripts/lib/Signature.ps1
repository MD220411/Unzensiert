# Signed releases (docs\security.md, "Signed releases"). Every release carries release.json (the
# version, its tag, the public commit and its tree, name, size and SHA-256 of its ZIP) and
# release.json.sig, an RSA signature (SHA-256, PKCS#1 v1.5) over the exact bytes of release.json.
# The updater (lib\Update.ps1) and install.ps1 install a release only when that signature
# verifies with one of the public keys in config\release-keys.json and the files are the ones it
# names. The private key lies encrypted with a passphrase in a key file on a USB stick of the
# maintainer (scripts\New-ReleaseKey.ps1 makes it, scripts\New-Release.ps1 signs with it).
# Needs lib\Config.ps1 and lib\AgentApi.ps1 (JSON). Keep this file ASCII-only.

$script:ReleaseStatementFormat = 'unzensiert-release 1'
$script:ReleaseKeyFormat = 'unzensiert-release-key 1'
$script:ReleaseKeyFileName = 'unzensiert-release-key.json'
$script:ReleaseKeyIterations = 600000

# --- public keys and checking --------------------------------------------------------------------

function Get-ReleaseKeys {
    # The public keys a release may be signed with: @{ id; modulus; exponent } each, base64.
    # Only from config\release-keys.json: config\machine.json cannot add a key. Call it as
    # @(Get-ReleaseKeys): the keys come one by one, none is no key.
    $file = Join-Path $script:ConfigDir 'release-keys.json'
    if (-not (Test-Path -LiteralPath $file)) { return }
    $cfg = Read-JsonFile $file
    $cfg.keys | Where-Object { $_ -and $_.modulus -and $_.exponent } | ForEach-Object {
        @{ id = [string]$_.id; modulus = [string]$_.modulus; exponent = [string]$_.exponent }
    }
}

function Get-ReleaseKeyId([string]$Modulus, [string]$Exponent) {
    # The short name of a public key: 16 hex digits of SHA-256 over modulus and exponent.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes("$Modulus.$Exponent")) }
    finally { $sha.Dispose() }
    return (-join ($hash[0..7] | ForEach-Object { $_.ToString('x2') }))
}

function ConvertTo-ReleaseRsa([string]$Modulus, [string]$Exponent, $Private = $null) {
    # An RSA object (CNG) of a public key, with the private parts when $Private holds them
    # (d, p, q, dp, dq, inverseQ as base64).
    $p = New-Object System.Security.Cryptography.RSAParameters
    $p.Modulus = [Convert]::FromBase64String($Modulus)
    $p.Exponent = [Convert]::FromBase64String($Exponent)
    if ($Private) {
        $p.D = [Convert]::FromBase64String([string](Get-DictValue $Private 'd'))
        $p.P = [Convert]::FromBase64String([string](Get-DictValue $Private 'p'))
        $p.Q = [Convert]::FromBase64String([string](Get-DictValue $Private 'q'))
        $p.DP = [Convert]::FromBase64String([string](Get-DictValue $Private 'dp'))
        $p.DQ = [Convert]::FromBase64String([string](Get-DictValue $Private 'dq'))
        $p.InverseQ = [Convert]::FromBase64String([string](Get-DictValue $Private 'inverseQ'))
    }
    $rsa = New-Object System.Security.Cryptography.RSACng
    $rsa.ImportParameters($p)
    return $rsa
}

function Find-ReleaseSigner([byte[]]$Data, [string]$Signature, $Keys) {
    # The id of the key in $Keys whose signature $Signature (base64) is over $Data, '' if none.
    $sig = $null
    try { $sig = [Convert]::FromBase64String(([string]$Signature).Trim()) } catch { return '' }
    foreach ($k in @($Keys)) {
        $rsa = $null
        try {
            $rsa = ConvertTo-ReleaseRsa $k.modulus $k.exponent
            if ($rsa.VerifyData($Data, $sig, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) { return [string]$k.id }
        } catch {
        } finally { if ($rsa) { $rsa.Dispose() } }
    }
    return ''
}

function ConvertTo-ReleaseJsonText([string]$Text) {
    # A JSON string literal (the statement holds only names, versions and hex digits).
    return '"' + ($Text -replace '\\', '\\' -replace '"', '\"') + '"'
}

function New-ReleaseStatement([string]$Repository, [string]$Version, [string]$Commit, [string]$Tree, [string]$ZipName, [long]$ZipSize, [string]$ZipSha256) {
    # The bytes of release.json: UTF-8 without BOM, LF, always the same order.
    $signed = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $lines = @(
        '{'
        "  `"format`": $(ConvertTo-ReleaseJsonText $script:ReleaseStatementFormat),"
        "  `"repository`": $(ConvertTo-ReleaseJsonText $Repository),"
        "  `"version`": $(ConvertTo-ReleaseJsonText $Version),"
        "  `"tag`": $(ConvertTo-ReleaseJsonText "v$Version"),"
        "  `"commit`": $(ConvertTo-ReleaseJsonText $Commit.ToLowerInvariant()),"
        "  `"tree`": $(ConvertTo-ReleaseJsonText $Tree.ToLowerInvariant()),"
        "  `"zip`": { `"name`": $(ConvertTo-ReleaseJsonText $ZipName), `"size`": $ZipSize, `"sha256`": $(ConvertTo-ReleaseJsonText $ZipSha256.ToLowerInvariant()) },"
        "  `"signed`": $(ConvertTo-ReleaseJsonText $signed)"
        '}'
    )
    return , ([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
}

function ConvertFrom-ReleaseStatement([byte[]]$Bytes) {
    # release.json as @{ repository; version; tag; commit; tree; zipName; zipSize; zipSha256;
    # signed }; throws when a part is missing or has the wrong form.
    $o = $null
    try { $o = ConvertFrom-AgentJson ([System.Text.Encoding]::UTF8.GetString($Bytes)) } catch {}
    if (-not ($o -is [System.Collections.IDictionary])) { throw 'release.json is no JSON object' }
    if ([string](Get-DictValue $o 'format') -cne $script:ReleaseStatementFormat) { throw "release.json has an unknown format ('$(Get-DictValue $o 'format')')" }
    $zip = Get-DictValue $o 'zip'
    $s = @{
        repository = [string](Get-DictValue $o 'repository'); version = [string](Get-DictValue $o 'version')
        tag = [string](Get-DictValue $o 'tag'); commit = [string](Get-DictValue $o 'commit'); tree = [string](Get-DictValue $o 'tree')
        zipName = [string](Get-DictValue $zip 'name'); zipSize = [long](Get-DictValue $zip 'size'); zipSha256 = [string](Get-DictValue $zip 'sha256')
        signed = [string](Get-DictValue $o 'signed')
    }
    if ($s.version -notmatch '^\d+\.\d+\.\d+$' -or $s.tag -cne "v$($s.version)") { throw 'release.json names no valid version and tag' }
    if ($s.commit -cnotmatch '^[0-9a-f]{40}$' -or $s.tree -cnotmatch '^[0-9a-f]{40}$') { throw 'release.json names no valid commit and tree' }
    if ($s.zipName -notmatch '^[A-Za-z0-9._-]+\.zip$' -or $s.zipSize -le 0 -or $s.zipSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'release.json names no valid ZIP' }
    return $s
}

function Confirm-ReleaseStatement([byte[]]$Json, [string]$Signature, [string]$Repository, [string]$Tag, $Keys = $null) {
    # The statement of a release (ConvertFrom-ReleaseStatement, plus signer) when its signature
    # verifies with a key of config\release-keys.json (or $Keys) and it names this repository
    # and this tag; throws why not otherwise.
    if ($null -eq $Keys) { $Keys = @(Get-ReleaseKeys) }
    if (@($Keys).Count -eq 0) { throw 'config\release-keys.json names no key' }
    $signer = Find-ReleaseSigner $Json $Signature $Keys
    if (-not $signer) { throw 'its signature does not verify with the release keys of this program' }
    $s = ConvertFrom-ReleaseStatement $Json
    if ($s.repository -ne $Repository) { throw "it is signed for $($s.repository), not for $Repository" }
    if ($s.tag -cne $Tag) { throw "it is signed for $($s.tag), not for $Tag" }
    $s.signer = $signer
    return $s
}

# --- the copy of the keys in install.ps1 ----------------------------------------------------------
# install.ps1 runs before there is a config\ folder, so it carries the keys itself, between two
# marker lines; scripts\New-ReleaseKey.ps1 writes them, scripts\Test-Setup.ps1 compares them.

$script:InstallKeysPattern = '(?s)(# --- release keys:[^\r\n]*\r?\n)(.*?)(\s*# --- end of release keys ---)'

function Get-InstallScriptKeys([string]$Text) {
    # The release keys in the text of install.ps1, as @{ id; modulus; exponent }, one by one
    # (call it as @(Get-InstallScriptKeys ...)).
    $m = [regex]::Match($Text, $script:InstallKeysPattern)
    if (-not $m.Success) { return }
    [regex]::Matches($m.Groups[2].Value, "@\{ id = '([0-9a-f]+)'; modulus = '([A-Za-z0-9+/=]+)'; exponent = '([A-Za-z0-9+/=]+)' \}") | ForEach-Object {
        @{ id = $_.Groups[1].Value; modulus = $_.Groups[2].Value; exponent = $_.Groups[3].Value }
    }
}

function Set-InstallScriptKeys([string]$Text, $Keys) {
    # The text of install.ps1 with $Keys between its marker lines; throws without the markers.
    if (-not [regex]::IsMatch($Text, $script:InstallKeysPattern)) { throw 'install.ps1 has no marker lines for the release keys' }
    $nl = "`n"
    if ($Text.Contains("`r`n")) { $nl = "`r`n" }
    $body = "    `$releaseKeys = @($nl"
    foreach ($k in @($Keys)) { $body += "        @{ id = '$($k.id)'; modulus = '$($k.modulus)'; exponent = '$($k.exponent)' }$nl" }
    $body += '    )'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + $body + $m.Groups[3].Value }
    return [regex]::Replace($Text, $script:InstallKeysPattern, $evaluator)
}

# --- the private key (maintainers only) -----------------------------------------------------------

function ConvertTo-Base64Bytes([byte[]]$Bytes) { return [Convert]::ToBase64String($Bytes) }

function Get-PassphraseKeys([string]$Passphrase, [byte[]]$Salt, [int]$Iterations) {
    # 64 bytes from the passphrase (PBKDF2 with SHA-256): 32 for AES, 32 for the HMAC.
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Passphrase, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $bytes = $kdf.GetBytes(64) } finally { $kdf.Dispose() }
    return , $bytes
}

function Get-ReleaseKeyFileMac([byte[]]$MacKey, $File) {
    # The HMAC-SHA256 over every part of a key file but the HMAC itself, base64.
    $text = @('format', 'id', 'modulus', 'exponent', 'kdf', 'iterations', 'salt', 'iv', 'data' | ForEach-Object { [string]$File.$_ }) -join '|'
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 (, $MacKey)
    try { return [Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($text))) }
    finally { $hmac.Dispose() }
}

function Test-SameBytes([byte[]]$A, [byte[]]$B) {
    # Equal, in a time that does not depend on where they differ.
    if ($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $diff = $diff -bor ($A[$i] -bxor $B[$i]) }
    return ($diff -eq 0)
}

function New-RandomBytes([int]$Count) {
    $bytes = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return , $bytes
}

function Protect-ReleaseKey($Rsa, [string]$Passphrase, [int]$Iterations = $script:ReleaseKeyIterations) {
    # The key file (a PSCustomObject for ConvertTo-Json) of the private key of $Rsa: the public
    # key in the clear, the private parts encrypted with AES-256-CBC under the passphrase and an
    # HMAC-SHA256 over everything.
    $p = $Rsa.ExportParameters($true)
    $private = ConvertTo-AgentJson @{
        d = ConvertTo-Base64Bytes $p.D; p = ConvertTo-Base64Bytes $p.P; q = ConvertTo-Base64Bytes $p.Q
        dp = ConvertTo-Base64Bytes $p.DP; dq = ConvertTo-Base64Bytes $p.DQ; inverseQ = ConvertTo-Base64Bytes $p.InverseQ
    }
    $salt = New-RandomBytes 16
    $iv = New-RandomBytes 16
    $keys = Get-PassphraseKeys $Passphrase $salt $Iterations
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = [byte[]]$keys[0..31]
        $aes.IV = $iv
        $plain = [System.Text.Encoding]::UTF8.GetBytes($private)
        $enc = $aes.CreateEncryptor()
        try { $cipher = $enc.TransformFinalBlock($plain, 0, $plain.Length) } finally { $enc.Dispose() }
        [Array]::Clear($plain, 0, $plain.Length)
    } finally { $aes.Dispose() }
    $modulus = ConvertTo-Base64Bytes $p.Modulus
    $exponent = ConvertTo-Base64Bytes $p.Exponent
    $file = [pscustomobject][ordered]@{
        format = $script:ReleaseKeyFormat; id = (Get-ReleaseKeyId $modulus $exponent)
        created = [DateTime]::UtcNow.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        modulus = $modulus; exponent = $exponent
        kdf = 'PBKDF2-SHA256'; iterations = $Iterations; salt = (ConvertTo-Base64Bytes $salt); iv = (ConvertTo-Base64Bytes $iv)
        data = (ConvertTo-Base64Bytes $cipher); mac = ''
    }
    $file.mac = Get-ReleaseKeyFileMac ([byte[]]$keys[32..63]) $file
    [Array]::Clear($keys, 0, $keys.Length)
    return $file
}

function Read-ReleaseKeyFile([string]$Path) {
    # A key file as PSCustomObject; throws when it is none.
    $file = $null
    try { $file = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch {}
    if (-not $file -or [string]$file.format -cne $script:ReleaseKeyFormat -or -not $file.modulus -or -not $file.data) { throw "$Path is no release key file" }
    return $file
}

function Unprotect-ReleaseKey($File, [string]$Passphrase) {
    # The RSA object with the private key of a key file; throws on a wrong passphrase or a
    # damaged file.
    if ([string]$File.kdf -cne 'PBKDF2-SHA256' -or [int]$File.iterations -lt 100000) { throw 'the key file uses an unknown or weak key derivation' }
    if ((Get-ReleaseKeyId ([string]$File.modulus) ([string]$File.exponent)) -cne [string]$File.id) { throw 'the key file is damaged (its id does not match its public key)' }
    $keys = Get-PassphraseKeys $Passphrase ([Convert]::FromBase64String([string]$File.salt)) ([int]$File.iterations)
    try {
        $mac = Get-ReleaseKeyFileMac ([byte[]]$keys[32..63]) $File
        if (-not (Test-SameBytes ([System.Text.Encoding]::ASCII.GetBytes($mac)) ([System.Text.Encoding]::ASCII.GetBytes([string]$File.mac)))) { throw 'wrong passphrase, or the key file is damaged' }
        $aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key = [byte[]]$keys[0..31]
            $aes.IV = [Convert]::FromBase64String([string]$File.iv)
            $cipher = [Convert]::FromBase64String([string]$File.data)
            $dec = $aes.CreateDecryptor()
            try { $plain = $dec.TransformFinalBlock($cipher, 0, $cipher.Length) } finally { $dec.Dispose() }
        } finally { $aes.Dispose() }
    } finally { [Array]::Clear($keys, 0, $keys.Length) }
    $private = ConvertFrom-AgentJson ([System.Text.Encoding]::UTF8.GetString($plain))
    [Array]::Clear($plain, 0, $plain.Length)
    return (ConvertTo-ReleaseRsa ([string]$File.modulus) ([string]$File.exponent) $private)
}

function New-ReleaseSignature($Rsa, [byte[]]$Data) {
    # The signature of $Data with the private key of $Rsa, base64.
    return [Convert]::ToBase64String($Rsa.SignData($Data, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1))
}

function Find-ReleaseKeyFile([string]$Path = '') {
    # The key file to sign with: $Path; else the one noted for this machine (config\machine.json,
    # release.keyFile); else unzensiert-release-key.json at the root of a removable drive.
    # '' when there is none (the stick is not plugged in).
    if ($Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Resolve-Path -LiteralPath $Path).Path }; return '' }
    $m = (Get-MachineConfig).PSObject.Properties['release']
    if ($m -and $m.Value.keyFile -and (Test-Path -LiteralPath ([string]$m.Value.keyFile) -PathType Leaf)) { return [string]$m.Value.keyFile }
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne [System.IO.DriveType]::Removable -or -not $d.IsReady) { continue }
        $f = Join-Path $d.RootDirectory.FullName $script:ReleaseKeyFileName
        if (Test-Path -LiteralPath $f -PathType Leaf) { return $f }
    }
    return ''
}

function Read-ReleasePassphrase([string]$Text, [string]$Title = 'Unzensiert: release key') {
    # Asks for the passphrase in a window of its own (the release scripts may run without a
    # console to type into). Returns '' when the window is closed or cancelled.
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(460, 150)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.SetBounds(12, 12, 436, 48)
    $box = New-Object System.Windows.Forms.TextBox
    $box.UseSystemPasswordChar = $true
    $box.SetBounds(12, 66, 436, 24)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.SetBounds(292, 108, 75, 28)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.SetBounds(373, 108, 75, 28)
    $form.Controls.AddRange(@($label, $box, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Add_Shown({ $form.Activate(); $box.Focus() })
    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return '' }
        return [string]$box.Text
    } finally { $form.Dispose() }
}
