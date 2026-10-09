$ErrorActionPreference = 'Stop'
$employeeRepo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$employeeApp = Join-Path $employeeRepo 'apps/jentra_employee'
$employeeBaseline = Join-Path $employeeApp 'build/review-baseline'
$employeePackage = [Text.StringBuilder]::new()
[void]$employeePackage.AppendLine('# Scoped employee review fix wave')
[void]$employeePackage.AppendLine('Baseline is the additive source snapshot reviewed in review-package.txt. No commits or Git index changes were made. Only new-app source/config fixes are included; ignored connection configuration and generated artifacts are excluded.')
$employeeFiles = & rg --files $employeeApp -g '*.dart' -g '*.yaml' -g '*.kt' -g '*.swift' -g '*Manifest.xml' -g '*.kts' -g '*.properties' -g '*.plist' -g 'project.pbxproj' -g 'README.md' -g '*.html' -g '*.json'
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate app files.' }
$employeeChanged = 0
foreach ($employeeFile in ($employeeFiles | Sort-Object)) {
    $employeeRelative = [IO.Path]::GetRelativePath($employeeRepo, $employeeFile)
    $employeeOriginal = Join-Path $employeeBaseline $employeeRelative
    if (-not (Test-Path -LiteralPath $employeeOriginal)) {
        $employeeLines = [IO.File]::ReadAllLines($employeeFile)
        [void]$employeePackage.AppendLine("diff --git a/$employeeRelative b/$employeeRelative")
        [void]$employeePackage.AppendLine('new file mode 100644')
        [void]$employeePackage.AppendLine('--- /dev/null')
        [void]$employeePackage.AppendLine("+++ b/$employeeRelative")
        [void]$employeePackage.AppendLine("@@ -0,0 +1,$($employeeLines.Length) @@")
        foreach ($employeeLine in $employeeLines) { [void]$employeePackage.AppendLine('+' + $employeeLine) }
        $employeeChanged++
        continue
    }
    $employeeDiff = & git --no-pager diff --no-index --no-ext-diff -- $employeeOriginal $employeeFile 2>$null
    if ($LASTEXITCODE -gt 1) { throw "Diff failed for $employeeRelative" }
    if ($LASTEXITCODE -eq 1) {
        $employeeChanged++
        foreach ($employeeLine in $employeeDiff) { [void]$employeePackage.AppendLine($employeeLine) }
    }
}
$employeeOutput = Join-Path $PSScriptRoot 'review-fix-package.txt'
[IO.File]::WriteAllText($employeeOutput, $employeePackage.ToString(), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{Package=$employeeOutput; ChangedFiles=$employeeChanged; Bytes=(Get-Item -LiteralPath $employeeOutput).Length}
