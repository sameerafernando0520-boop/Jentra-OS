param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.1.0', [ValidateRange(1,2147483647)][int]$BuildNumber=1)
$ErrorActionPreference = 'Stop'
$salesRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$salesStem = "Jentra-Sales-$Version-$BuildNumber-Development"
$salesDelivery = Join-Path $salesRoot ("dist/"+$salesStem)
$salesApk = Join-Path $salesRoot 'apps/jentra_sales/build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path -LiteralPath $salesApk -PathType Leaf)) { throw 'Build the Sales APK first.' }
if (Test-Path -LiteralPath $salesDelivery) { throw 'An existing release handoff will not be overwritten.' }
[IO.Directory]::CreateDirectory($salesDelivery) | Out-Null
$salesApkName = "$salesStem.apk"
$salesCopied = Join-Path $salesDelivery $salesApkName
Copy-Item -LiteralPath $salesApk -Destination $salesCopied
$salesZip = Join-Path $salesDelivery "$salesStem-APK.zip"
Compress-Archive -LiteralPath $salesCopied -DestinationPath $salesZip -CompressionLevel Optimal
$salesChecks = @($salesCopied, $salesZip) | ForEach-Object {
  $salesHash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
  '{0}  {1}' -f $salesHash.Hash.ToLowerInvariant(), [IO.Path]::GetFileName($_)
}
$salesChecks | Set-Content -LiteralPath (Join-Path $salesDelivery 'checksums.sha256') -Encoding utf8
@'
Jentra Sales 0.1.0+1 Development

Web: https://jentra-os-sales.web.app
Android identity: com.jentra.sales.dev
Architecture: ARM64 (modern 64-bit Android phones and tablets).

Install the APK on an Android device after reviewing its source and checksum.
The APK uses a local development signing identity; it is not a store release.
The ZIP contains the same APK for download/transfer.

Choose Explore the preview from the sign-in screen. Customers, products, orders,
amounts and delivery states are samples. Search, order review, fractional
quantities, discount requests and encrypted local drafts are available.
Preview visits and notes remain in the current session. Saved local order
drafts expire after 24 hours and are never submitted automatically.

Company sign-in does not open real business data in this first release. Live
customer portfolios, server-governed order submission, independent discount
approval and verified customer/delivery email responses need the reviewed
backend rollout. English is available; Sinhala and Tamil are pending.
Physical-device and real-company acceptance remain separate.
'@.Replace('Jentra Sales 0.1.0+1 Development',"Jentra Sales $Version+$BuildNumber Development") | Set-Content -LiteralPath (Join-Path $salesDelivery 'READ-ME.txt') -Encoding utf8
$salesMetadata = @{name='Jentra Sales';version="$Version+$BuildNumber";channel='development';mode='interactive-preview';liveSalesEnabled=$false;apkFilename=$salesApkName;archiveFilename=[IO.Path]::GetFileName($salesZip);backendProject='xpdoufauvrbdmxgngetv'}
$salesMetadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $salesDelivery 'release.json') -Encoding utf8
Write-Output "Sales delivery: $salesDelivery"
Write-Output ($salesChecks -join [Environment]::NewLine)
