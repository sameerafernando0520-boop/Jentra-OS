param([string]$OutputName = 'source-manifest.json')
$ErrorActionPreference = 'Stop'
$employeeRepo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$employeePaths = & rg --files (Join-Path $employeeRepo 'apps/jentra_employee') (Join-Path $employeeRepo 'packages/jentra_domain/lib') (Join-Path $employeeRepo 'packages/jentra_platform/lib') (Join-Path $employeeRepo 'packages/jentra_design_system/lib') (Join-Path $employeeRepo 'packages/jentra_design_system/assets')
if ($LASTEXITCODE -ne 0) { throw 'Source enumeration failed.' }
$employeePaths += (Join-Path $employeeRepo 'pubspec.yaml'), (Join-Path $employeeRepo 'pubspec.lock')
$employeeSources = foreach ($employeePath in ($employeePaths | Sort-Object -Unique)) {
    $employeeRelative = [IO.Path]::GetRelativePath($employeeRepo, $employeePath).Replace('\', '/')
    if ($employeeRelative -match '\.env\.' -or $employeeRelative -match '(^|/)(build|\.dart_tool)/') { continue }
    $employeeFile = Get-Item -LiteralPath $employeePath
    [pscustomobject]@{path=$employeeRelative; bytes=$employeeFile.Length; sha256=(Get-FileHash -LiteralPath $employeePath -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$employeeEvidence = [ordered]@{captured_at_utc=[DateTime]::UtcNow.ToString('o'); sdk='Flutter 3.47.5 / Dart 3.13.4'; files=@($employeeSources)}
$employeeOutput = Join-Path $PSScriptRoot $OutputName
[IO.File]::WriteAllText($employeeOutput, ($employeeEvidence | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Manifest=$employeeOutput; SourceFiles=$employeeSources.Count}
