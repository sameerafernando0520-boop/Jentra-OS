function New-JentraNativeInstaller {
  param([string]$OutputDirectory,[string]$InstallerSourceRoot,[string]$IconPath)
  $identity=(Get-Content -LiteralPath (Join-Path $OutputDirectory 'source-manifest.json') -Raw | ConvertFrom-Json).identity
  $payload=Join-Path $OutputDirectory 'package\Payload'
  $manifestPath=Join-Path $payload 'release-manifest.json'
  $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $candidates=@(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  )
  $compiler=@($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
  if ($compiler.Count -ne 1) { throw 'INNO_SETUP_6_COMPILER_REQUIRED_ON_BUILD_PC' }
  $product=$identity.applicationProductName
  $folder='Jentra OS Administrator Development'
  $baseName='J-panel-'+$identity.releaseId+'-Setup'
  $definitions=[ordered]@{
    Channel=$identity.channel;ProductName=$product;InstallFolder=$folder;
    VersionName=$identity.versionName;FullVersion=$identity.version;BuildNumber=[string]$identity.buildNumber;
    ReleaseId=$identity.releaseId;IconPath=$IconPath;OutputDirectory=$OutputDirectory;OutputBaseName=$baseName;
    ManifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $lines=New-Object 'Collections.Generic.List[string]'
  foreach($item in $definitions.GetEnumerator()){
    if(([string]$item.Value).IndexOfAny([char[]]@('"',"`r","`n")) -ge 0){throw 'INVALID_NATIVE_INSTALLER_DEFINITION'}
    $lines.Add('#define '+$item.Key+' "'+$item.Value+'"')
  }
  $template=Join-Path $InstallerSourceRoot 'native-installer.iss'
  $lines.Add('#include "'+$template+'"')
  $lines.Add('[Files]')
  $inputFiles=@($manifest.files)+@([PSCustomObject]@{path='release-manifest.json';bytes=(Get-Item -LiteralPath $manifestPath).Length;sha256=$definitions.ManifestSha256})
  foreach($file in $inputFiles){
    $relative=([string]$file.path).Replace('/','\')
    if([IO.Path]::IsPathRooted($relative) -or $relative.Contains('..') -or $relative.Contains(':') -or $relative.Contains('"')){throw 'INVALID_NATIVE_INSTALLER_PATH'}
    $source=Join-Path $payload $relative
    if((Get-Item -LiteralPath $source).Length -ne $file.bytes -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw 'NATIVE_INSTALLER_INPUT_CHANGED'}
    $parent=[IO.Path]::GetDirectoryName($relative)
    $destination='{app}\releases\'+$identity.releaseId+$(if($parent){'\'+$parent}else{''})
    $literal=$relative.Replace("'","''")
    $lines.Add(('Source: "{0}"; DestDir: "{1}"; Flags: ignoreversion; AfterInstall: VerifyInstalledFile(''{2}'', ''{3}'')' -f $source,$destination,$literal,$file.sha256))
  }
  $script=Join-Path $OutputDirectory 'native-release.iss'
  [IO.File]::WriteAllLines($script,$lines,(New-Object Text.UTF8Encoding($true)))
  & $compiler[0] '/Q' $script | Out-Host
  if($LASTEXITCODE -ne 0){throw 'NATIVE_INSTALLER_COMPILATION_FAILED'}
  $installer=Join-Path $OutputDirectory ($baseName+'.exe')
  if(!(Test-Path -LiteralPath $installer -PathType Leaf)){throw 'NATIVE_INSTALLER_MISSING'}
  return $installer
}
