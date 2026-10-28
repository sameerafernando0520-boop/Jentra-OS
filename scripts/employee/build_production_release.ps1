#requires -Version 5.1
param(
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.jentra/signing/employee'),
    [string]$ConfigurationFile = '.env.employee-development.json',
    [string]$FlutterSdk = 'C:/src/flutter',
    [string]$AndroidSdk = "$env:LOCALAPPDATA/Android/Sdk",
    [string]$JavaExecutable = 'C:/Program Files/Android/Android Studio/jbr/bin/java.exe'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$appRoot = Join-Path $repoRoot 'apps/jentra_employee'
$signingRoot = [IO.Path]::GetFullPath($SigningDirectory)
if ($signingRoot.TrimEnd('\','/').Equals($repoRoot.TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase) -or
    $signingRoot.StartsWith($repoRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Release signing material must remain outside the repository.'
}
$keyPath = Join-Path $signingRoot 'jentra-employee-release.p12'
$passwordPath = Join-Path $signingRoot 'password.dpapi'
$metadataPath = Join-Path $signingRoot 'signing.json'
$configurationPath = [IO.Path]::GetFullPath((Join-Path $appRoot $ConfigurationFile))
$dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutter = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $buildTools) { throw 'Android build tools are required.' }
$apksigner = Join-Path $buildTools.FullName 'lib/apksigner.jar'
$aapt = Join-Path $buildTools.FullName 'aapt2.exe'
$zipalign = Join-Path $buildTools.FullName 'zipalign.exe'
$keytool = Join-Path ([IO.Path]::GetDirectoryName($JavaExecutable)) 'keytool.exe'
$jarsigner = Join-Path ([IO.Path]::GetDirectoryName($JavaExecutable)) 'jarsigner.exe'
foreach ($required in @($keyPath,$passwordPath,$metadataPath,$configurationPath,$dart,$flutter,$apksigner,$aapt,$zipalign,$JavaExecutable,$keytool,$jarsigner)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Release input is unavailable: $required" }
}
. (Join-Path $PSScriptRoot 'release_artifact_provenance.ps1')
# Resolve exactly the locked dependency graph before signing credentials enter
# the process. Offline resolution neither upgrades dependencies nor uses network.
Push-Location -LiteralPath $repoRoot
try {
    & $dart $flutter --suppress-analytics pub get --offline --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked offline release dependencies could not be resolved.' }
} finally { Pop-Location }
$provenanceTools = [ordered]@{dart=$dart;flutterTool=$flutter;java=$JavaExecutable;apksigner=$apksigner;
    aapt2=$aapt;zipalign=$zipalign;keytool=$keytool;jarsigner=$jarsigner}
$provenance = New-EmployeeReleaseProvenance $repoRoot $configurationPath $provenanceTools
$publicConfiguration = Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json
if (@($publicConfiguration.PSObject.Properties.Name | Where-Object { $_ -notin @('SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY') }).Count -gt 0 -or
    $publicConfiguration.SUPABASE_URL -ne 'https://xpdoufauvrbdmxgngetv.supabase.co' -or
    $publicConfiguration.SUPABASE_PUBLISHABLE_KEY -notmatch '^sb_publishable_[A-Za-z0-9_-]+$') {
    throw 'Release build requires the approved project and its public publishable key only.'
}
$publicConfiguration = $null
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.alias -ne 'jentra-employee' -or $metadata.applicationId -ne 'com.jentra.employee' -or $metadata.certificateSha256 -notmatch '^[a-f0-9]{64}$') { throw 'Unexpected release-key identity.' }
$pubspec = Get-Content -LiteralPath (Join-Path $appRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9.]+)\+([0-9]+)\s*$') { throw 'Explicit app version is required.' }
$version = $Matches[1]
$buildNumber = [int]$Matches[2]
Assert-EmployeeReleaseInputsUnchanged $provenance $repoRoot $configurationPath $provenanceTools
$output = New-EmployeeReleaseDirectory (Join-Path $appRoot 'build/deliverables') $version $buildNumber
$securePassword = Get-Content -LiteralPath $passwordPath -Raw | ConvertTo-SecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
$oldKey = $env:JENTRA_EMPLOYEE_KEYSTORE
$oldPassword = $env:JENTRA_EMPLOYEE_SIGNING_PASSWORD
$oldGradleOpts = $env:GRADLE_OPTS
try {
    $env:JENTRA_EMPLOYEE_KEYSTORE = $keyPath
    $env:JENTRA_EMPLOYEE_SIGNING_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    # Do not retain signing credentials in a reusable Gradle daemon.
    $env:GRADLE_OPTS = '-Dorg.gradle.daemon=false'
    Push-Location -LiteralPath $appRoot
    try {
        & $dart $flutter build appbundle --release --no-pub --android-project-arg=jentraProductionSigning=true --target-platform=android-arm,android-arm64 "--dart-define-from-file=$configurationPath"
        if ($LASTEXITCODE -ne 0) { throw 'Signed Android bundle build failed.' }
        & $dart $flutter build apk --release --no-pub --android-project-arg=jentraProductionSigning=true --target-platform=android-arm64 "--dart-define-from-file=$configurationPath"
        if ($LASTEXITCODE -ne 0) { throw 'Signed ARM64 APK build failed.' }
    } finally { Pop-Location }
    Assert-EmployeeReleaseInputsUnchanged $provenance $repoRoot $configurationPath $provenanceTools
    $apk = Join-Path $appRoot 'build/app/outputs/flutter-apk/app-release.apk'
    $bundle = Join-Path $appRoot 'build/app/outputs/bundle/release/app-release.aab'
    $signatureLog = Join-Path $output 'apk-signature.log'
    & $JavaExecutable -jar $apksigner verify --verbose --print-certs $apk *> $signatureLog
    if ($LASTEXITCODE -ne 0) { throw 'Production-identity APK signature verification failed.' }
    $signature = Get-Content -LiteralPath $signatureLog -Raw
    $fingerprint = [regex]::Match($signature,'certificate SHA-256 digest: ([a-f0-9]+)').Groups[1].Value
    if ($fingerprint -ne $metadata.certificateSha256 -or $signature -match 'CN=Android Debug') { throw 'APK signer differs from the owner release key.' }
    & $zipalign -c -P 16 -v 4 $apk *> (Join-Path $output 'apk-alignment.log')
    if ($LASTEXITCODE -ne 0) { throw 'APK alignment verification failed.' }
    $badging = & $aapt dump badging $apk
    if ($LASTEXITCODE -ne 0 -or ($badging -join "`n") -notmatch "package: name='com\.jentra\.employee' versionCode='$buildNumber' versionName='$([regex]::Escape($version))'" -or ($badging -join "`n") -match 'application-debuggable') { throw 'Unexpected APK version or identity.' }
    $bundleSignatureLog = Join-Path $output 'bundle-signature.log'
    & $jarsigner '-J-Duser.language=en' -verify $bundle *> $bundleSignatureLog
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $bundleSignatureLog -Raw) -notmatch 'jar verified\.') {
        throw 'Bundle signature integrity verification failed.'
    }
    $bundleCert = & $keytool '-J-Duser.language=en' -printcert -jarfile $bundle 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Bundle signer certificate could not be read.' }
    $bundleFingerprint = [regex]::Match(($bundleCert -join "`n"),'SHA256:\s*([A-Fa-f0-9:]+)').Groups[1].Value.Replace(':','').ToLowerInvariant()
    if ($bundleFingerprint -ne $metadata.certificateSha256) { throw 'Bundle signer differs from the owner release key.' }
    $artifacts = foreach ($item in @(@($apk,"Jentra-Employee-$version-arm64-signed.apk"),@($bundle,"Jentra-Employee-$version-signed.aab"))) {
        $destination = Join-Path $output $item[1]
        Copy-EmployeeReleaseArtifact $item[0] $destination
    }
    Assert-EmployeeReleaseInputsUnchanged $provenance $repoRoot $configurationPath $provenanceTools
    $report = [ordered]@{builtAtUtc=[DateTime]::UtcNow.ToString('o');version=$version;buildNumber=$buildNumber;applicationId='com.jentra.employee';certificateSha256=$fingerprint;configuration='owner-approved Supabase project; hosted activation and acceptance remain separate';provenance=$provenance;artifacts=@($artifacts);storePublication=$false;actualDeviceAcceptance=$false;portableKeyBackupVerified=$metadata.portableBackupVerified}
    Write-EmployeeReleaseManifest (Join-Path $output 'release-manifest.json') $report
    $report | ConvertTo-Json -Depth 10
} finally {
    $env:JENTRA_EMPLOYEE_KEYSTORE = $oldKey
    $env:JENTRA_EMPLOYEE_SIGNING_PASSWORD = $oldPassword
    $env:GRADLE_OPTS = $oldGradleOpts
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $securePassword.Dispose()
}
