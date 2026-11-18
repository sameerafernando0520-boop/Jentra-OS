function New-JentraReleaseArchive {
  param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$DestinationPath)
  $archiveRoot=[IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
  $archivePath=[IO.Path]::GetFullPath($DestinationPath)
  $entries=@(Get-ChildItem -LiteralPath $archiveRoot -Recurse -Force)
  if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { throw 'ARCHIVE_REPARSE_POINT' }
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archiveStream=[IO.File]::Open($archivePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $releaseArchive=$null
  try {
    $releaseArchive=New-Object IO.Compression.ZipArchive($archiveStream,[IO.Compression.ZipArchiveMode]::Create,$true)
    foreach ($entryFile in @($entries | Where-Object { !$_.PSIsContainer })) {
      $entryName=$entryFile.FullName.Substring($archiveRoot.Length+1).Replace('\','/')
      if ([string]::IsNullOrWhiteSpace($entryName) -or $entryName.StartsWith('/') -or $entryName.Contains('../')) { throw 'ARCHIVE_PATH_INVALID' }
      [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($releaseArchive,$entryFile.FullName,$entryName,[IO.Compression.CompressionLevel]::Optimal)
    }
  } finally {
    if ($null -ne $releaseArchive) { $releaseArchive.Dispose() }
    $archiveStream.Dispose()
  }
}
