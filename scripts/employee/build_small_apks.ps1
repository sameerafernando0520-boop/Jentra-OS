param(
    [string]$FlutterSdk = 'C:\src\flutter',
    [string]$ConfigurationFile = '.env.employee-development.json',
    [string]$AndroidSdk = "$env:LOCALAPPDATA\Android\sdk",
    [string]$JavaExecutable = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe',
    [switch]$IncludeEmulator
)

$ErrorActionPreference = 'Stop'
$employeeRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$employeeApp = Join-Path $employeeRepo 'apps/jentra_employee'
$dartExecutable = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutterSnapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
$configurationPath = [IO.Path]::GetFullPath((Join-Path $employeeApp $ConfigurationFile))
$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $buildTools) { throw 'Android build tools are required for package verification.' }
$aaptExecutable = Join-Path $buildTools.FullName 'aapt2.exe'
$zipAlignExecutable = Join-Path $buildTools.FullName 'zipalign.exe'
$apkSignerJar = Join-Path $buildTools.FullName 'lib/apksigner.jar'
foreach ($requiredFile in @($dartExecutable, $flutterSnapshot, $configurationPath, $JavaExecutable, $aaptExecutable, $zipAlignExecutable, $apkSignerJar)) {
    if (!(Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required build input not found: $requiredFile"
    }
}

$pubspec = Get-Content -LiteralPath (Join-Path $employeeApp 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9.]+)\+([0-9]+)\s*$') {
    throw 'An explicit employee app version is required.'
}
$appVersion = $Matches[1]
$buildNumber = $Matches[2]
$deliveryDir = Join-Path $employeeApp "build/deliverables/$appVersion-optimized-development"
$symbolsDir = Join-Path $employeeApp "build/symbols/$appVersion-$buildNumber"
$targetPlatforms = if ($IncludeEmulator) { 'android-arm,android-arm64,android-x64' } else { 'android-arm,android-arm64' }
$abiNames = if ($IncludeEmulator) { @('arm64-v8a', 'armeabi-v7a', 'x86_64') } else { @('arm64-v8a', 'armeabi-v7a') }

# Pass the development opt-in directly to Gradle. Flutter's Java process
# environment may omit environment-based Gradle properties. Release compilation
# still disables debug services, while this identity can update the old APK.
Push-Location $employeeApp
try {
    Write-Output "Building optimized development APKs for $targetPlatforms"
    & $dartExecutable $flutterSnapshot build apk --release --no-pub --split-per-abi --android-project-arg=jentraDevelopmentRelease=true "--target-platform=$targetPlatforms" "--split-debug-info=$symbolsDir" "--dart-define-from-file=$configurationPath"
    if ($LASTEXITCODE -ne 0) { throw "Employee APK build failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$checkDir = Join-Path $employeeApp "build/apk-checks/$appVersion"
New-Item -ItemType Directory -Path $checkDir -Force | Out-Null
$baselineApk = Join-Path $employeeApp 'build/deliverables/Jentra-Employee-0.3.0-development.apk'
$baselineCert = $null
if (Test-Path -LiteralPath $baselineApk) {
    $baselineLog = Join-Path $checkDir 'baseline-signature.log'
    & $JavaExecutable -jar $apkSignerJar verify --print-certs $baselineApk *> $baselineLog
    if ($LASTEXITCODE -ne 0) { throw 'Previous development APK signature is invalid.' }
    $baselineCert = [regex]::Match((Get-Content -LiteralPath $baselineLog -Raw), 'certificate SHA-256 digest: ([a-f0-9]+)').Groups[1].Value
    if (!$baselineCert) { throw 'Cannot read the previous development signing certificate.' }
}
New-Item -ItemType Directory -Path $deliveryDir -Force | Out-Null
$artifacts = foreach ($abi in $abiNames) {
    $builtApk = Join-Path $employeeApp "build/app/outputs/flutter-apk/app-$abi-release.apk"
    $signatureLog = Join-Path $checkDir "signature-$abi.log"
    & $JavaExecutable -jar $apkSignerJar verify --verbose --print-certs $builtApk *> $signatureLog
    if ($LASTEXITCODE -ne 0) { throw "APK signature is invalid: $abi" }
    $alignmentLog = Join-Path $checkDir "alignment-16k-$abi.log"
    & $zipAlignExecutable -c -P 16 -v 4 $builtApk *> $alignmentLog
    if ($LASTEXITCODE -ne 0) { throw "APK native page alignment verification failed: $abi" }
    $signature = Get-Content -LiteralPath $signatureLog -Raw
    $cert = [regex]::Match($signature, 'certificate SHA-256 digest: ([a-f0-9]+)').Groups[1].Value
    if (!$cert -or ($baselineCert -and $cert -ne $baselineCert)) { throw "Unexpected development signer: $abi" }
    $badgingLog = Join-Path $checkDir "badging-$abi.log"
    & $aaptExecutable dump badging $builtApk *> $badgingLog
    if ($LASTEXITCODE -ne 0) { throw "Android manifest inspection failed: $abi" }
    $badging = Get-Content -LiteralPath $badgingLog -Raw
    if ($badging -notmatch "package: name='com\.jentra\.employee\.dev'" -or $badging -match 'application-debuggable') {
        throw "Unexpected development package identity or debug runtime: $abi"
    }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($builtApk)
    try {
        $nativeAbis = @($archive.Entries.FullName | Where-Object { $_ -match '^lib/([^/]+)/' } | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
        if ($nativeAbis.Count -ne 1 -or $nativeAbis[0] -ne $abi) { throw "Unexpected native architectures in $builtApk." }
        if ($archive.GetEntry('assets/flutter_assets/kernel_blob.bin') -or
            @($archive.Entries | Where-Object { $_.FullName -like '*libVkLayer_khronos_validation*' }).Count -gt 0) {
            throw "Debug runtime content found in $builtApk."
        }
    } finally { $archive.Dispose() }
    $apkFile = Get-Item -LiteralPath $builtApk
    if ($apkFile.Length -gt 40MB) { throw "Employee APK exceeds the 40 MiB development size budget: $abi." }
    $destination = Join-Path $deliveryDir "Jentra-Employee-$appVersion-$abi-optimized-development.apk"
    Copy-Item -LiteralPath $builtApk -Destination $destination
    [ordered]@{path=$destination;abi=$abi;bytes=$apkFile.Length;mib=[Math]::Round($apkFile.Length/1MB,2);sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant();certificate_sha256=$cert;signature_verified=$true;alignment_16k_verified=$true;package_identity_verified=$true}
}
$manifest = [ordered]@{
    built_at_utc=[DateTime]::UtcNow.ToString('o')
    version=$appVersion
    build_number=[int]$buildNumber
    build_mode='release'
    distribution='development'
    application_id='com.jentra.employee.dev'
    signing='local Android debug keystore; not store distribution signing'
    compiler_debug_symbols=$symbolsDir
    artifacts=@($artifacts)
}
[IO.File]::WriteAllText((Join-Path $deliveryDir 'apk-manifest.json'),($manifest | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$artifacts | ForEach-Object { Write-Output ("{0}: {1} MiB - {2}" -f $_.abi, $_.mib, $_.path) }
