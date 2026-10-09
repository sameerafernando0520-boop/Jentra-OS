param([ValidatePattern('^[a-z][a-z0-9]{1,10}$')][string]$Revision='r2')
$ErrorActionPreference='Stop'
$probeRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$probeManifest=Get-Content -LiteralPath (Join-Path $probeRoot "docs/verification/wave5/windows-test-preview-package-20261009-$Revision.json") -Raw | ConvertFrom-Json
$probeProcess=@(Get-Process -Name Jentra_OS -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $probeManifest.executable})
if($probeProcess.Count -ne 1) {throw 'ONE_OWN_PREVIEW_PROCESS_REQUIRED'}
$probeProcess=$probeProcess[0]
$probeVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($probeManifest.executable)
if($probeVersion.ProductName -ne "JentraOS_WindowsTest_20261009-$Revision`_Preview") {throw 'ISOLATED_PREVIEW_IDENTITY_REQUIRED'}
$probeFile=$probeManifest.releaseFiles | Where-Object {$_.path -eq 'Jentra_OS.exe'}
if((Get-FileHash -LiteralPath $probeManifest.executable -Algorithm SHA256).Hash.ToLowerInvariant() -ne $probeFile.sha256) {throw 'OWN_BINARY_HASH_CHANGED'}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W5KeyboardWindow {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out Rect rect);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window,IntPtr context,uint flags);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
Add-Type -AssemblyName System.Drawing
$probeShell=New-Object -ComObject WScript.Shell
function Send-OwnKeys([string]$keys) {
 [W5KeyboardWindow]::SetForegroundWindow($probeProcess.MainWindowHandle) | Out-Null
 $probeShell.AppActivate($probeProcess.Id) | Out-Null
 Start-Sleep -Milliseconds 400
 if([W5KeyboardWindow]::GetForegroundWindow() -ne $probeProcess.MainWindowHandle) {throw 'OWN_PREVIEW_FOCUS_REQUIRED_NO_KEYS_SENT'}
 $probeShell.SendKeys($keys)
 Start-Sleep -Milliseconds 700
}
function Capture-OwnClient([string]$name) {
 $previousDpi=[W5KeyboardWindow]::SetThreadDpiAwarenessContext([IntPtr](-4))
 if($previousDpi -eq [IntPtr]::Zero){throw 'PHYSICAL_PIXEL_CONTEXT_REQUIRED'}
 $rect=New-Object W5KeyboardWindow+Rect
 if(-not [W5KeyboardWindow]::GetClientRect($probeProcess.MainWindowHandle,[ref]$rect)){throw 'OWN_CLIENT_BOUNDS_REQUIRED'}
 $bitmap=[Drawing.Bitmap]::new(($rect.Right-$rect.Left),($rect.Bottom-$rect.Top));$graphics=[Drawing.Graphics]::FromImage($bitmap)
 $target=Join-Path $probeRoot "docs/verification/wave5/windows-test-preview-$name-20261009-$Revision.png"
 try {
  $device=$graphics.GetHdc()
  try {if(-not [W5KeyboardWindow]::PrintWindow($probeProcess.MainWindowHandle,$device,3)){throw 'OWN_CLIENT_CAPTURE_FAILED'}}
  finally {$graphics.ReleaseHdc($device)}
  $bitmap.Save($target,[Drawing.Imaging.ImageFormat]::Png)
 } finally {$graphics.Dispose();$bitmap.Dispose();[W5KeyboardWindow]::SetThreadDpiAwarenessContext($previousDpi)|Out-Null}
 return $target
}
Send-OwnKeys '^k'
Send-OwnKeys '{UP}'
$palette=Capture-OwnClient 'palette'
Send-OwnKeys '{ENTER}'
$destination=Capture-OwnClient 'keyboard-destination'
[pscustomobject]@{recordedAt=[DateTime]::UtcNow.ToString('o');pid=$probeProcess.Id;executable=$probeProcess.Path;keys=@('Ctrl+K','Up','Enter');palette=$palette;destination=$destination;captureScope='Only the verified Preview client';authenticated=$false;formalAcceptance=$false} |
 ConvertTo-Json | Set-Content -LiteralPath (Join-Path $probeRoot "docs/verification/wave5/windows-test-preview-keyboard-20261009-$Revision.json")
