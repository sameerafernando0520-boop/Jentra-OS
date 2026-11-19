# Use only the redistributable CRT shipped with the Visual Studio instance that
# compiled this bundle. Never copy developer/debug DLLs or download DLLs.
function Get-JentraVcRuntimeFiles([string]$VisualStudioInstance) {
  $instance = [IO.Path]::GetFullPath($VisualStudioInstance)
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (!(Test-Path -LiteralPath $vswhere)) { throw 'VISUAL_STUDIO_INSTALLATION_DISCOVERY_REQUIRED' }
  $installed = @((& $vswhere -all -products '*' -format json | Out-String | ConvertFrom-Json) | Where-Object { [IO.Path]::GetFullPath($_.installationPath) -eq $instance })
  if ($installed.Count -ne 1) { throw 'BUILD_VISUAL_STUDIO_INSTANCE_NOT_INSTALLED' }
  $versionFile = Join-Path $instance 'VC\Auxiliary\Build\Microsoft.VCRedistVersion.default.txt'
  $redistVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
  if ($redistVersion -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw 'VISUAL_CPP_REDISTRIBUTABLE_VERSION_INVALID' }
  $redistRoot = Join-Path $instance ('VC\Redist\MSVC\' + $redistVersion + '\x64')
  $crtDirectories = @(Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object { $_.Name -match '^Microsoft\.VC\d+\.CRT$' })
  if ($crtDirectories.Count -ne 1 -or ($crtDirectories[0].Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'VISUAL_CPP_X64_CRT_REDISTRIBUTABLE_REQUIRED' }
  $files = @(Get-ChildItem -LiteralPath $crtDirectories[0].FullName -File -Filter '*.dll' | Sort-Object Name)
  foreach ($required in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    if (@($files | Where-Object { $_.Name -eq $required }).Count -ne 1) { throw 'VISUAL_CPP_RUNTIME_FILE_MISSING' }
  }
  foreach ($file in $files) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.VersionInfo.CompanyName -ne 'Microsoft Corporation') { throw 'VISUAL_CPP_REDISTRIBUTABLE_FILE_INVALID' }
  }
  return [PSCustomObject]@{visualStudioInstance=$instance;version=$redistVersion;redistDirectory=$crtDirectories[0].FullName;files=$files}
}
