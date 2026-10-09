param([string]$OutputName = 'review-package.txt')
$ErrorActionPreference = 'Stop'
$employeeRepo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$employeeApp = Join-Path $employeeRepo 'apps/jentra_employee'
$files = & rg --files $employeeApp -g '*.dart' -g '*.yaml' -g '*.kt' -g '*.swift' -g '*Manifest.xml' -g '*.kts' -g '*.properties' -g '*.plist' -g 'project.pbxproj' -g 'README.md' -g '*.html' -g '*.json'
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate the owned app sources.' }
$package = [Text.StringBuilder]::new()
[void]$package.AppendLine('# Employee app additive source review')
[void]$package.AppendLine('No commit was made. This package represents new owned files plus the one root workspace entry. Unrelated checkout changes and ignored public connection configuration are excluded.')
[void]$package.AppendLine('Base HEAD: ' + (& git -C $employeeRepo rev-parse HEAD))
[void]$package.AppendLine('Root workspace diff:')
foreach ($line in (& git -C $employeeRepo diff -- pubspec.yaml pubspec.lock)) { [void]$package.AppendLine($line) }
foreach ($file in ($files | Sort-Object)) {
    $relative = [IO.Path]::GetRelativePath($employeeRepo, $file).Replace('\', '/')
    $lines = [IO.File]::ReadAllLines($file)
    [void]$package.AppendLine("diff --git a/$relative b/$relative")
    [void]$package.AppendLine('new file mode 100644')
    [void]$package.AppendLine('--- /dev/null')
    [void]$package.AppendLine("+++ b/$relative")
    [void]$package.AppendLine("@@ -0,0 +1,$($lines.Length) @@")
    foreach ($line in $lines) { [void]$package.AppendLine('+' + $line) }
}
$output = Join-Path $PSScriptRoot $OutputName
[IO.File]::WriteAllText($output, $package.ToString(), [Text.UTF8Encoding]::new($false))
Get-Item -LiteralPath $output | Select-Object FullName, Length
