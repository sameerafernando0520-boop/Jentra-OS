$ErrorActionPreference = 'Stop'
$employeeRepo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$employeeBaseline = [IO.Path]::GetFullPath((Join-Path $employeeRepo 'apps/jentra_employee/build/review-baseline'))
$employeeLines = [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'review-package.txt'))
$employeeRelative = $null
$employeeBody = [Collections.Generic.List[string]]::new()
$employeeCount = 0
function Save-EmployeeBaseline {
    if ($null -eq $script:employeeRelative) { return }
    $employeeTarget = [IO.Path]::GetFullPath((Join-Path $script:employeeBaseline $script:employeeRelative))
    if (-not $employeeTarget.StartsWith($script:employeeBaseline + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Review path escaped baseline directory.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($employeeTarget)) | Out-Null
    [IO.File]::WriteAllLines($employeeTarget, $script:employeeBody, [Text.UTF8Encoding]::new($false))
    $script:employeeCount++
}
foreach ($employeeLine in $employeeLines) {
    if ($employeeLine.StartsWith('diff --git ')) {
        Save-EmployeeBaseline
        $employeeRelative = $null
        $employeeBody.Clear()
    } elseif ($employeeLine.StartsWith('+++ b/apps/jentra_employee/')) {
        $employeeRelative = $employeeLine.Substring('+++ b/'.Length)
    } elseif ($null -ne $employeeRelative -and $employeeLine.StartsWith('+')) {
        $employeeBody.Add($employeeLine.Substring(1))
    }
}
Save-EmployeeBaseline
[pscustomobject]@{Baseline=$employeeBaseline; Sources=$employeeCount}
