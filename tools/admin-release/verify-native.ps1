[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReleaseDirectory)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$release=[IO.Path]::GetFullPath($ReleaseDirectory)
$delivery=Get-Content -LiteralPath (Join-Path $release 'delivery.json') -Raw | ConvertFrom-Json
if($delivery.installerKind -ne 'native-inno' -or $delivery.requiresDotNet -or $delivery.requiresPowerShell){throw 'NATIVE_INSTALLER_REQUIRED'}
$installer=[IO.Path]::GetFullPath($delivery.installer.path)
if(!(Test-Path -LiteralPath $installer -PathType Leaf) -or (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $delivery.installer.sha256){throw 'INSTALLER_HASH_CHANGED'}
$binary=[IO.File]::ReadAllBytes($installer)
$pe=[BitConverter]::ToInt32($binary,0x3c)
if([Text.Encoding]::ASCII.GetString($binary,$pe,4) -ne "PE`0`0"){throw 'INSTALLER_PE_REQUIRED'}
$optional=$pe+24
$magic=[BitConverter]::ToUInt16($binary,$optional)
$directory=if($magic -eq 0x10b){$optional+96}elseif($magic -eq 0x20b){$optional+112}else{throw 'UNSUPPORTED_PE_HEADER'}
if([BitConverter]::ToUInt32($binary,$directory+14*8) -ne 0){throw 'INSTALLER_HAS_CLR_DEPENDENCY'}
$fixture=Join-Path $repo ('build\admin-native-check-'+[Guid]::NewGuid().ToString('N'))
$install=Join-Path $fixture 'install'
if(!$install.StartsWith(($repo.TrimEnd('\')+'\build\'),[StringComparison]::OrdinalIgnoreCase)){throw 'WORKSPACE_STAGING_REQUIRED'}
New-Item -ItemType Directory -Path $fixture | Out-Null
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JentraOS-Administrator-'+$delivery.identity.channel+'_is1'
$registeredBefore=Test-Path -LiteralPath $key
$shortcut=Join-Path ([Environment]::GetFolderPath('Programs')) 'J panel.lnk'
$shortcutHash=if(Test-Path -LiteralPath $shortcut){(Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash}else{$null}
$log=Join-Path $fixture 'setup.log'
$arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS /STAGING=1 /DIR="'+$install+'" /LOG="'+$log+'"'
$process=Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if($process.ExitCode -ne 0){throw ('NATIVE_STAGING_FAILED_'+$process.ExitCode+'; inspect '+$log)}
$runtime=Join-Path $install ('releases\'+$delivery.identity.releaseId)
$manifestSource=Join-Path $release 'package\Payload\release-manifest.json'
$manifest=Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
$expected=@($manifest.files)+@([PSCustomObject]@{path='release-manifest.json';bytes=(Get-Item -LiteralPath $manifestSource).Length;sha256=(Get-FileHash -LiteralPath $manifestSource -Algorithm SHA256).Hash.ToLowerInvariant()})
foreach($file in $expected){
  $target=[IO.Path]::GetFullPath((Join-Path $runtime $file.path))
  if(!$target.StartsWith($runtime.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'INVALID_INSTALLED_PATH'}
  if((Get-Item -LiteralPath $target).Length -ne $file.bytes -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw 'NATIVE_INSTALLED_BYTES_CHANGED'}
}
if(@(Get-ChildItem -LiteralPath $install -File -Recurse).Count -ne $expected.Count){throw 'UNEXPECTED_NATIVE_STAGING_FILES'}
if((Test-Path -LiteralPath $key) -ne $registeredBefore){throw 'STAGING_CHANGED_REGISTRATION'}
$shortcutAfter=if(Test-Path -LiteralPath $shortcut){(Get-FileHash -LiteralPath $shortcut -Algorithm SHA256).Hash}else{$null}
if($shortcutAfter -ne $shortcutHash){throw 'STAGING_CHANGED_SHORTCUT'}
$report=[ordered]@{passed=$true;releaseId=$delivery.identity.releaseId;fixture=$fixture;verifiedFiles=$expected.Count;nativeBootstrap=$true;requiresDotNet=$false;requiresPowerShell=$false;userProfileInstalled=$false;registryChanged=$false;shortcutsChanged=$false;desktopAppLaunched=$false;otherPcAccepted=$false;backendChanged=$false;unsigned=$delivery.unsigned}
[IO.File]::WriteAllText((Join-Path $release 'native-staging-verification.json'),($report | ConvertTo-Json)+"`n",(New-Object Text.UTF8Encoding($false)))
$report | ConvertTo-Json
