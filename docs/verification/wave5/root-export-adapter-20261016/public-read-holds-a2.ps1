# Embedded verbatim in the reviewed adapters. These functions read public files only.
$taskPublicHolds = [Collections.Generic.List[IO.FileStream]]::new()
$taskPublicHeldPaths = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-TaskReviewedReadHold([string]$Base, [string]$Relative, [string]$ExpectedSha256) {
    if ($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$' -or $Relative -cnotmatch '^[a-zA-Z0-9_./-]+$' -or
        $Relative.StartsWith('/') -or @($Relative.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' }).Count -ne 0) {
        throw 'EXACT_REVIEWED_PUBLIC_FILE_REQUIRED'
    }
    $taskBasePath = [IO.Path]::GetFullPath($Base).TrimEnd('\')
    $taskAbsolutePath = [IO.Path]::GetFullPath((Join-Path $taskBasePath $Relative))
    if (-not $taskAbsolutePath.StartsWith($taskBasePath + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'REVIEWED_FILE_OUTSIDE_BOUND_ROOT' }
    $taskCursor = $taskBasePath
    $taskBaseItem = Get-Item -LiteralPath $taskCursor -Force
    if (-not $taskBaseItem.PSIsContainer -or ($taskBaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'REVIEWED_ROOT_REDIRECTION_FORBIDDEN' }
    $taskParts = $Relative.Split('/')
    for ($taskIndex = 0; $taskIndex -lt $taskParts.Length; $taskIndex++) {
        $taskCursor = Join-Path $taskCursor $taskParts[$taskIndex]
        $taskItem = Get-Item -LiteralPath $taskCursor -Force
        if (($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($taskIndex -lt $taskParts.Length - 1 -and -not $taskItem.PSIsContainer)) { throw 'REVIEWED_FILE_REDIRECTION_FORBIDDEN' }
    }
    if ($taskItem.PSIsContainer -or $taskItem.Length -gt 2097152) { throw 'BOUNDED_REVIEWED_PUBLIC_FILE_REQUIRED' }
    if ($taskPublicHeldPaths.ContainsKey($taskAbsolutePath)) {
        if ($taskPublicHeldPaths[$taskAbsolutePath] -cne $ExpectedSha256) { throw 'REVIEWED_FILE_HASH_COLLISION' }
        return
    }
    $taskReadHandle = $null
    try {
        $taskReadHandle = [IO.File]::Open($taskAbsolutePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if ($taskReadHandle.Length -gt 2097152) { throw 'BOUNDED_REVIEWED_PUBLIC_FILE_REQUIRED' }
        $taskHasher = [Security.Cryptography.SHA256]::Create()
        try { $taskHeldHash = [Convert]::ToHexString($taskHasher.ComputeHash($taskReadHandle)).ToLowerInvariant() }
        finally { $taskHasher.Dispose() }
        if ($taskHeldHash -cne $ExpectedSha256) { throw 'REVIEWED_FILE_HASH_CHANGED' }
        $taskReadHandle.Position = 0
        $taskPublicHolds.Add($taskReadHandle)
        $taskPublicHeldPaths.Add($taskAbsolutePath,$ExpectedSha256)
        $taskReadHandle = $null
    } finally { if ($null -ne $taskReadHandle) { $taskReadHandle.Dispose() } }
}
function Close-TaskReviewedReadHolds {
    foreach ($taskHeldFile in $taskPublicHolds) { $taskHeldFile.Dispose() }
    $taskPublicHolds.Clear()
    $taskPublicHeldPaths.Clear()
}
