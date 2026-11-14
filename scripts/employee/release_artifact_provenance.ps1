# Pure release-file helpers. No signing material, build command or network access.
function Initialize-EmployeeGradleWrapper {
    param([string]$AndroidDirectory,[string]$FlutterSdk)
    $wrapperCache = Join-Path $FlutterSdk 'bin/cache/artifacts/gradle_wrapper'
    foreach ($relative in @('gradlew','gradlew.bat','gradle/wrapper/gradle-wrapper.jar')) {
        $destination = Join-Path $AndroidDirectory $relative
        if (Test-Path -LiteralPath $destination -PathType Leaf) { continue }
        $source = Join-Path $wrapperCache $relative
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Flutter Gradle wrapper cache is unavailable.' }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        [IO.File]::Copy($source,$destination,$false)
    }
}

function New-EmployeeReleaseDirectory {
    param([string]$DeliverablesRoot,[string]$Version,[int]$BuildNumber,[string]$Stamp)
    if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $BuildNumber -lt 1) { throw 'Explicit release version and build number are required.' }
    if (!$Stamp) { $Stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N') }
    if ($Stamp -notmatch '^[A-Za-z0-9-]+$') { throw 'Invalid release directory stamp.' }
    $root = [IO.Path]::GetFullPath($DeliverablesRoot)
    if (!(Test-Path -LiteralPath $root -PathType Container)) { New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null }
    $target = Join-Path $root "$Version-$BuildNumber-signed-production-identity-$Stamp"
    # Directory.CreateDirectory (also used by New-Item) can report success to
    # two concurrent callers. Reserve the name with an exclusive file first.
    $reservation = [IO.FileStream]::new($target + '.reserve',
        [IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None,
        1,[IO.FileOptions]::DeleteOnClose)
    try {
        if (Test-Path -LiteralPath $target) { throw 'Release directory already exists.' }
        New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
        return $target
    } finally { $reservation.Dispose() }
}

function Get-EmployeeReleaseSourceFiles {
    param([string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    $relativeFiles = New-Object 'Collections.Generic.List[string]'
    $required = @('pubspec.yaml','pubspec.lock','apps/jentra_employee/pubspec.yaml',
        '.dart_tool/package_config.json','scripts/employee/build_production_release.ps1',
        'scripts/employee/release_artifact_provenance.ps1')
    foreach ($relative in $required) {
        if (!(Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) { throw 'Required release provenance input is unavailable.' }
        $relativeFiles.Add($relative)
    }
    if (Test-Path -LiteralPath (Join-Path $root 'analysis_options.yaml') -PathType Leaf) { $relativeFiles.Add('analysis_options.yaml') }
    $directories = New-Object 'Collections.Generic.Stack[string]'
    foreach ($relative in @('apps/jentra_employee/lib','apps/jentra_employee/android')) {
        $directory = Join-Path $root $relative
        if (!(Test-Path -LiteralPath $directory -PathType Container)) { throw 'Required employee source directory is unavailable.' }
        $directories.Push($directory)
    }
    foreach ($package in @(Get-ChildItem -LiteralPath (Join-Path $root 'packages') -Directory -ErrorAction Stop)) {
        $manifest = Join-Path $package.FullName 'pubspec.yaml'
        if (Test-Path -LiteralPath $manifest -PathType Leaf) { $relativeFiles.Add($manifest.Substring($root.Length + 1).Replace('\','/')) }
        foreach ($name in @('lib','assets','fonts','android')) {
            $directory = Join-Path $package.FullName $name
            if (Test-Path -LiteralPath $directory -PathType Container) { $directories.Push($directory) }
        }
    }
    while ($directories.Count -gt 0) {
        $directory = Get-Item -LiteralPath $directories.Pop() -Force
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Release source links are forbidden.' }
        foreach ($item in @(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction Stop)) {
            $relative = $item.FullName.Substring($root.Length + 1).Replace('\','/')
            if ($relative -match '(^|/)(build|\.gradle|\.kotlin|\.dart_tool|\.cxx)(/|$)' -or
                $relative -match '(^|/)(hs_err_pid[0-9]+\.log|replay_pid[0-9]+\.log|java_pid[0-9]+\.hprof)$' -or
                $relative -match '(^|/)(local\.properties|key\.properties|\.env[^/]*|[^/]*firebase-adminsdk[^/]*|[^/]*service[_-]?account[^/]*|[^/]*private[_-]?key[^/]*)$' -or
                $relative -match '\.(jks|keystore|p12|pfx|pem|key)$' -or
                $relative -match '/io/flutter/plugins/GeneratedPluginRegistrant\.java$') { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Release source links are forbidden.' }
            if ($item.PSIsContainer) { $directories.Push($item.FullName) } else { $relativeFiles.Add($relative) }
        }
    }
    foreach ($relative in @($relativeFiles | Sort-Object -Unique)) {
        $file = Get-Item -LiteralPath (Join-Path $root $relative) -Force
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Release source links are forbidden.' }
        [ordered]@{path=$relative;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
}

function Get-EmployeeReleaseTextHash {
    param([string]$Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function New-EmployeeReleaseProvenance {
    param([string]$RepositoryRoot,[string]$ConfigurationPath,[Collections.IDictionary]$ToolchainPaths)
    $files = @(Get-EmployeeReleaseSourceFiles $RepositoryRoot)
    $tools = @(foreach ($entry in @($ToolchainPaths.GetEnumerator() | Sort-Object Key)) {
        $file = Get-Item -LiteralPath $entry.Value -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Release tool must be a regular file.' }
        [ordered]@{tool=[string]$entry.Key;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    if ($tools.Count -eq 0) { throw 'Release toolchain provenance is required.' }
    [ordered]@{schemaVersion=1;sourceHashMethod='SHA-256 of sorted source path:sha256 LF records';
        sourceSha256=(Get-EmployeeReleaseTextHash (($files | ForEach-Object { $_.path + ':' + $_.sha256 + "`n" }) -join ''));
        sourceFiles=$files;configurationSha256=(Get-FileHash -LiteralPath $ConfigurationPath -Algorithm SHA256).Hash.ToLowerInvariant();
        toolchainSha256=(Get-EmployeeReleaseTextHash (($tools | ForEach-Object { $_.tool + ':' + $_.sha256 + "`n" }) -join ''));
        toolchain=$tools}
}

function Assert-EmployeeReleaseInputsUnchanged {
    param($Provenance,[string]$RepositoryRoot,[string]$ConfigurationPath,[Collections.IDictionary]$ToolchainPaths)
    $current = New-EmployeeReleaseProvenance $RepositoryRoot $ConfigurationPath $ToolchainPaths
    if ($current.sourceSha256 -ne $Provenance.sourceSha256 -or $current.configurationSha256 -ne $Provenance.configurationSha256 -or
        $current.toolchainSha256 -ne $Provenance.toolchainSha256) { throw 'Release inputs changed during the build; do not publish these artifacts.' }
}

function Copy-EmployeeReleaseArtifact {
    param([string]$Source,[string]$Destination)
    $before = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::Copy($Source,$Destination,$false)
    $copied = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($copied -ne $before -or (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $before) {
        throw 'Release artifact changed during copying; do not publish this directory.'
    }
    [ordered]@{path=$Destination;bytes=(Get-Item -LiteralPath $Destination).Length;sha256=$copied}
}

function Write-EmployeeReleaseManifest {
    param([string]$Path,$Report)
    $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Report | ConvertTo-Json -Depth 10) + "`n")
        $stream.Write($bytes,0,$bytes.Length)
    } finally { $stream.Dispose() }
}
