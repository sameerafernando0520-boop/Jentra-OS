$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'archive.ps1')
$archiveFixture=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) ('build\archive-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $archiveFixture 'package\Payload\data\assets') -Force | Out-Null
$fixtureContent=[Text.Encoding]::UTF8.GetBytes('Synthetic archive verification only')
[IO.File]::WriteAllBytes((Join-Path $archiveFixture 'package\Payload\data\assets\sample file.txt'),$fixtureContent)
$fixtureZip=Join-Path $archiveFixture 'fixture.zip'
New-JentraReleaseArchive -SourceDirectory (Join-Path $archiveFixture 'package') -DestinationPath $fixtureZip
$readArchive=[IO.Compression.ZipFile]::OpenRead($fixtureZip)
try {
  $entry=$readArchive.GetEntry('Payload/data/assets/sample file.txt')
  if (!$entry -or $entry.Length -ne $fixtureContent.Length) { throw 'FORWARD_SLASH_ENTRY_VERIFICATION_FAILED' }
  $stream=$entry.Open()
  $memory=New-Object IO.MemoryStream
  try { $stream.CopyTo($memory); if ([Convert]::ToBase64String($memory.ToArray()) -ne [Convert]::ToBase64String($fixtureContent)) { throw 'ARCHIVE_BYTE_VERIFICATION_FAILED' } }
  finally { $stream.Dispose(); $memory.Dispose() }
} finally { $readArchive.Dispose() }
$overwriteRefused=$false
try { New-JentraReleaseArchive -SourceDirectory (Join-Path $archiveFixture 'package') -DestinationPath $fixtureZip }
catch { $overwriteRefused=$true }
if (!$overwriteRefused) { throw 'EXISTING_ARCHIVE_WAS_OVERWRITTEN' }
[pscustomobject]@{passed=3;canonicalPaths=$true;exactBytes=$true;overwriteRefused=$true;fixture=$archiveFixture} | ConvertTo-Json
