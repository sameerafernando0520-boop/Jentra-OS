$ErrorActionPreference = 'Stop'
$employeeRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$deliveryDir = Join-Path $employeeRepo 'apps/jentra_employee/build/deliverables/0.3.1-optimized-development'
$manifest = Get-Content -LiteralPath (Join-Path $deliveryDir 'apk-manifest.json') -Raw | ConvertFrom-Json
$baseline = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baseline-apk.json') -Raw | ConvertFrom-Json
$baselineSignature = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baseline-signature.log') -Raw
$baselineCert = [regex]::Match($baselineSignature, 'certificate SHA-256 digest: ([a-f0-9]+)').Groups[1].Value
if (!$baselineCert) { throw 'Baseline certificate is missing.' }

$javaBinary = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
$androidTools = 'C:\Users\sheha\AppData\Local\Android\sdk\build-tools\37.0.0'
$apkSignerJar = Join-Path $androidTools 'lib/apksigner.jar'
$aaptBinary = Join-Path $androidTools 'aapt2.exe'
$zipalignBinary = Join-Path $androidTools 'zipalign.exe'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$inspections = foreach ($artifact in $manifest.artifacts) {
    $abi = $artifact.abi
    $apk = Get-Item -LiteralPath $artifact.path
    $artifactHash = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($artifactHash -ne $artifact.sha256) { throw "APK drift: $abi" }

    $signatureLog = Join-Path $PSScriptRoot "signature-$abi.log"
    & $javaBinary -jar $apkSignerJar verify --verbose --print-certs $apk.FullName *> $signatureLog
    if ($LASTEXITCODE -ne 0) { throw "APK signature invalid: $abi" }
    $signature = Get-Content -LiteralPath $signatureLog -Raw
    $cert = [regex]::Match($signature, 'certificate SHA-256 digest: ([a-f0-9]+)').Groups[1].Value
    if ($cert -ne $baselineCert) { throw "The development signer changed: $abi" }
    if ($signature -notmatch 'Verified using v2 scheme[^\r\n]*: true') { throw "APK v2 signature missing: $abi" }

    $badgingLog = Join-Path $PSScriptRoot "badging-$abi.log"
    & $aaptBinary dump badging $apk.FullName *> $badgingLog
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect Android manifest: $abi" }
    $badging = Get-Content -LiteralPath $badgingLog -Raw
    if ($badging -notmatch "package: name='com\.jentra\.employee\.dev' versionCode='([0-9]+)' versionName='0\.3\.1'") {
        throw "Unexpected package/version: $abi"
    }
    $versionCode = [int]$Matches[1]
    if ($versionCode -le 4) { throw "Version code cannot update the prior development APK: $abi" }
    if ($badging -match 'application-debuggable') { throw "APK remains debuggable: $abi" }

    $alignmentLog = Join-Path $PSScriptRoot "alignment-$abi.log"
    & $zipalignBinary -c -P 16 4 $apk.FullName *> $alignmentLog
    if ($LASTEXITCODE -ne 0) { throw "APK ZIP alignment failed: $abi" }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($apk.FullName)
    try {
        $nativeAbis = @($archive.Entries.FullName | Where-Object { $_ -match '^lib/([^/]+)/' } | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
        if ($nativeAbis.Count -ne 1 -or $nativeAbis[0] -ne $abi) { throw "Mixed architectures: $abi" }
        $kernelPresent = $null -ne $archive.GetEntry('assets/flutter_assets/kernel_blob.bin')
        $validationPresent = @($archive.Entries | Where-Object { $_.FullName -like '*libVkLayer_khronos_validation*' }).Count -gt 0
        if ($kernelPresent -or $validationPresent) { throw "Debug files present: $abi" }
        $icons = $archive.GetEntry('assets/flutter_assets/fonts/MaterialIcons-Regular.otf')
        if ($null -eq $icons -or $icons.Length -ge 1645184) { throw "Icon font was not reduced: $abi" }
        $fonts = @($archive.Entries.FullName | Where-Object { $_ -like '*assets/fonts/*.ttf' })
        foreach ($family in @('Manrope', 'NotoSansSinhala', 'NotoSansTamil')) {
            if (@($fonts | Where-Object { $_ -like "*$family*" }).Count -eq 0) { throw "Required font family missing: $family" }
        }
        [ordered]@{
            path=$apk.FullName
            abi=$abi
            bytes=$apk.Length
            mib=[Math]::Round($apk.Length/1MB,2)
            reduction_percent=[Math]::Round((1-$apk.Length/$baseline.bytes)*100,2)
            sha256=$artifactHash
            package_id='com.jentra.employee.dev'
            version='0.3.1'
            version_code=$versionCode
            debuggable=$false
            certificate_sha256=$cert
            same_signer_as_previous_apk=$true
            v2_signature_verified=$true
            zip_alignment_verified=$true
            kernel_blob_present=$kernelPresent
            graphics_validation_library_present=$validationPresent
            native_architectures=$nativeAbis
            material_icon_font_bytes=$icons.Length
            bundled_fonts=$fonts
            top_entries=@($archive.Entries | Sort-Object Length -Descending | Select-Object -First 15 FullName,Length,CompressedLength)
        }
    } finally { $archive.Dispose() }
}
$report = [ordered]@{inspected_at_utc=[DateTime]::UtcNow.ToString('o');baseline_bytes=$baseline.bytes;artifacts=@($inspections);installed_on_device=$false;authenticated_native_acceptance=$false}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'apk-inspection.json'),($report | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$inspections | ForEach-Object { Write-Output ("{0}: {1} MiB, {2}% smaller; signature, identity and alignment verified" -f $_.abi, $_.mib, $_.reduction_percent) }
