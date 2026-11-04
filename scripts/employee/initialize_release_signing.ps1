#requires -Version 5.1
param(
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.jentra/signing/employee'),
    [string]$Keytool = 'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe',
    [switch]$VerifyExisting
)
$ErrorActionPreference = 'Stop'
$releaseRoot = [IO.Path]::GetFullPath($SigningDirectory)
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($releaseRoot.TrimEnd('\','/').Equals($repositoryRoot.TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase) -or
    $releaseRoot.StartsWith($repositoryRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Release signing material must be stored outside the repository.'
}
if (!(Test-Path -LiteralPath $Keytool -PathType Leaf)) { throw 'Installed Android JDK keytool is required.' }
$keyPath = Join-Path $releaseRoot 'jentra-employee-release.p12'
$passwordPath = Join-Path $releaseRoot 'password.dpapi'
$metadataPath = Join-Path $releaseRoot 'signing.json'
if ($VerifyExisting -and (!(Test-Path -LiteralPath $keyPath) -or !(Test-Path -LiteralPath $passwordPath) -or (Test-Path -LiteralPath $metadataPath))) {
    throw 'Verification recovery needs the existing key and protected password, without existing metadata.'
}
if (!$VerifyExisting -and @($keyPath, $passwordPath, $metadataPath | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
    throw 'Signing material already exists. Preserve it; this command never rotates or overwrites an existing key.'
}
if (!$VerifyExisting) {
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.SetOwner($owner)
foreach ($sid in @($owner, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $releaseRoot -AclObject $acl
$passwordBytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $random.GetBytes($passwordBytes) } finally { $random.Dispose() }
$password = [Convert]::ToBase64String($passwordBytes)
[Array]::Clear($passwordBytes, 0, $passwordBytes.Length)
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
$protectedPassword = ConvertFrom-SecureString -SecureString $securePassword
[IO.File]::WriteAllText($passwordPath, $protectedPassword, [Text.UTF8Encoding]::new($false))
} else {
    $securePassword = Get-Content -LiteralPath $passwordPath -Raw | ConvertTo-SecureString
    $recoveryPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($recoveryPointer)
}
$previousPassword = $env:JENTRA_EMPLOYEE_SIGNING_PASSWORD
try {
    $env:JENTRA_EMPLOYEE_SIGNING_PASSWORD = $password
    if (!$VerifyExisting) {
        & $Keytool -genkeypair -keystore $keyPath -storetype PKCS12 -alias jentra-employee -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -validity 10000 -dname 'CN=Jentra Employee Release' -storepass:env JENTRA_EMPLOYEE_SIGNING_PASSWORD -noprompt 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Release-key generation failed; preserve the private directory for inspection.' }
    }
    $certificate = & $Keytool '-J-Duser.language=en' -list -v -keystore $keyPath -storetype PKCS12 -alias jentra-employee -storepass:env JENTRA_EMPLOYEE_SIGNING_PASSWORD 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Generated release-key verification failed.' }
    $fingerprint = [regex]::Match(($certificate -join "`n"), 'SHA256:\s*([A-Fa-f0-9:]+)').Groups[1].Value.Replace(':','').ToLowerInvariant()
    if ($fingerprint.Length -ne 64) { throw 'Generated certificate fingerprint is unavailable.' }
    $metadata = [ordered]@{schema=1;alias='jentra-employee';createdAtUtc=[DateTime]::UtcNow.ToString('o');keystore=$keyPath;passwordProtection='Windows DPAPI CurrentUser';certificateSha256=$fingerprint;applicationId='com.jentra.employee';portableBackupVerified=$false}
    [IO.File]::WriteAllText($metadataPath, ($metadata | ConvertTo-Json) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $metadata | ConvertTo-Json
} finally {
    $env:JENTRA_EMPLOYEE_SIGNING_PASSWORD = $previousPassword
    $password = $null
    if ($VerifyExisting) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($recoveryPointer) }
    $securePassword.Dispose()
}
