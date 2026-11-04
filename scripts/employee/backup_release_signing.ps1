#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.jentra/signing/employee'),
    [string]$Keytool = 'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe'
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\','/')
$target = [IO.Path]::GetFullPath($Destination)
if ($target.StartsWith($repository + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetExtension($target) -ne '.p12' -or (Test-Path -LiteralPath $target)) {
    throw 'Choose a new .p12 backup file outside this repository. Existing files are never overwritten.'
}
$source = Join-Path $SigningDirectory 'jentra-employee-release.p12'
$metadataPath = Join-Path $SigningDirectory 'signing.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.alias -ne 'jentra-employee' -or $metadata.certificateSha256 -notmatch '^[a-f0-9]{64}$') {
    throw 'Unexpected release-key metadata.'
}
if (!(Test-Path -LiteralPath (Split-Path -Parent $target) -PathType Container)) {
    throw 'Create the private backup destination directory first.'
}
# Run this interactively. The portable backup password is never saved or printed.
$backupSecret = Read-Host 'New portable backup password (at least 16 characters)' -AsSecureString
$backupRepeat = Read-Host 'Repeat portable backup password' -AsSecureString
$sourceSecret = Get-Content -LiteralPath (Join-Path $SigningDirectory 'password.dpapi') -Raw | ConvertTo-SecureString
$sourcePointer = [IntPtr]::Zero; $backupPointer = [IntPtr]::Zero; $repeatPointer = [IntPtr]::Zero
$oldSource = $env:JENTRA_BACKUP_SOURCE_PASSWORD; $oldTarget = $env:JENTRA_BACKUP_TARGET_PASSWORD
try {
    $sourcePointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sourceSecret)
    $backupPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($backupSecret)
    $repeatPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($backupRepeat)
    $backupPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($backupPointer)
    $repeatPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($repeatPointer)
    if ($backupPassword.Length -lt 16 -or $backupPassword -cne $repeatPassword) { throw 'Backup passwords must match and contain at least 16 characters.' }
    $env:JENTRA_BACKUP_SOURCE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($sourcePointer)
    $env:JENTRA_BACKUP_TARGET_PASSWORD = $backupPassword
    & $Keytool -importkeystore -srckeystore $source -srcstoretype PKCS12 -srcalias jentra-employee -srcstorepass:env JENTRA_BACKUP_SOURCE_PASSWORD -srckeypass:env JENTRA_BACKUP_SOURCE_PASSWORD -destkeystore $target -deststoretype PKCS12 -destalias jentra-employee -deststorepass:env JENTRA_BACKUP_TARGET_PASSWORD -destkeypass:env JENTRA_BACKUP_TARGET_PASSWORD -noprompt 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Backup export failed. Preserve any partial file for inspection.' }
    $certificate = & $Keytool '-J-Duser.language=en' -list -v -keystore $target -storetype PKCS12 -alias jentra-employee -storepass:env JENTRA_BACKUP_TARGET_PASSWORD 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Backup certificate could not be verified.' }
    $fingerprint = [regex]::Match(($certificate -join "`n"),'SHA256:\s*([A-Fa-f0-9:]+)').Groups[1].Value.Replace(':','').ToLowerInvariant()
    if ($fingerprint -ne $metadata.certificateSha256) { throw 'Backup certificate differs from the original release key.' }
    # Generating a public CSR also proves that the exported private key unlocks.
    & $Keytool -certreq -alias jentra-employee -keystore $target -storetype PKCS12 -storepass:env JENTRA_BACKUP_TARGET_PASSWORD -keypass:env JENTRA_BACKUP_TARGET_PASSWORD 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Backup private-key recovery check failed.' }
    $metadata.portableBackupVerified = $true
    $metadata | Add-Member -NotePropertyName portableBackupVerifiedAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    [IO.File]::WriteAllText($metadataPath,($metadata | ConvertTo-Json) + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    [ordered]@{backup=$target;certificateSha256=$fingerprint;privateKeyUnlockVerified=$true;offDeviceRetentionConfirmed=$false} | ConvertTo-Json
} finally {
    $env:JENTRA_BACKUP_SOURCE_PASSWORD = $oldSource; $env:JENTRA_BACKUP_TARGET_PASSWORD = $oldTarget
    $backupPassword=$null; $repeatPassword=$null
    foreach ($pointer in @($sourcePointer,$backupPointer,$repeatPointer)) {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
    $sourceSecret.Dispose(); $backupSecret.Dispose(); $backupRepeat.Dispose()
}
