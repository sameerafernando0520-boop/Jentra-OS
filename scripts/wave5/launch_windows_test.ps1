param(
 [Parameter(Mandatory=$true)][ValidateSet('Preview','Connected')][string]$Mode,
 [switch]$Capture,
 [switch]$UseRunning
)
$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testEvidence=Join-Path $testRoot ('docs/verification/wave5/windows-test-' + $Mode.ToLowerInvariant() + '-package-20261009.json')
$testBuild=Get-Content -LiteralPath $testEvidence -Raw | ConvertFrom-Json
$testExe=$testBuild.executable
$testVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($testExe)
if ($testVersion.CompanyName -ne 'com.jentra.test' -or
    $testVersion.ProductName -ne ('JentraOS_WindowsTest_20261009_' + $Mode)) { throw 'ISOLATED_APP_IDENTITY_REQUIRED' }
foreach($testFile in $testBuild.releaseFiles) {
 $testLocation=[IO.Path]::GetFullPath((Join-Path $testBuild.packageDirectory $testFile.path))
 if(-not $testLocation.StartsWith($testBuild.packageDirectory + '\',[StringComparison]::OrdinalIgnoreCase) -or
    (Get-FileHash -LiteralPath $testLocation -Algorithm SHA256).Hash.ToLowerInvariant() -ne $testFile.sha256) {throw 'PACKAGE_HASH_CHANGED'}
}
if($UseRunning) {
 $testProcess=@(Get-Process -Name 'Jentra_OS' -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $testExe})
 if($testProcess.Count -ne 1) {throw 'ONE_OWN_TEST_PROCESS_REQUIRED'}
 $testProcess=$testProcess[0]
 if($testProcess.Path -ne $testExe) {throw 'OWN_TEST_PROCESS_REQUIRED'}
} else {
 $testProcess=Start-Process -FilePath $testExe -WorkingDirectory $testBuild.packageDirectory -WindowStyle Normal -PassThru
}
$testDeadline=[DateTime]::UtcNow.AddSeconds(30)
do {
 Start-Sleep -Milliseconds 250
 $testProcess.Refresh()
 if($testProcess.HasExited) {throw 'NATIVE_APP_EXITED_BEFORE_WINDOW'}
} while ($testProcess.MainWindowHandle -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $testDeadline)
if($testProcess.MainWindowHandle -eq [IntPtr]::Zero) {throw 'NATIVE_WINDOW_NOT_READY'}
$testCapturePath=$null
if($Capture) {
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class JentraTestWindow {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out Rect bounds);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window,ref Point point);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window,IntPtr deviceContext,uint flags);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int command);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
 Add-Type -AssemblyName System.Drawing
 $testPreviousDpi=[JentraTestWindow]::SetThreadDpiAwarenessContext([IntPtr](-4))
 if($testPreviousDpi -eq [IntPtr]::Zero) {throw 'PHYSICAL_PIXEL_CAPTURE_CONTEXT_REQUIRED'}
 [JentraTestWindow]::ShowWindow($testProcess.MainWindowHandle,3) | Out-Null
 [JentraTestWindow]::SetForegroundWindow($testProcess.MainWindowHandle) | Out-Null
 Start-Sleep -Seconds 3
 if([JentraTestWindow]::GetForegroundWindow() -ne $testProcess.MainWindowHandle) {
  $testShell=New-Object -ComObject WScript.Shell
  $testShell.AppActivate($testProcess.Id) | Out-Null
  Start-Sleep -Seconds 1
 }
 $testOwnForeground=[JentraTestWindow]::GetForegroundWindow() -eq $testProcess.MainWindowHandle
 $testBounds=New-Object JentraTestWindow+Rect
 if(-not [JentraTestWindow]::GetClientRect($testProcess.MainWindowHandle,[ref]$testBounds)) {throw 'OWN_APP_BOUNDS_UNAVAILABLE'}
 $testOrigin=New-Object JentraTestWindow+Point
 if(-not [JentraTestWindow]::ClientToScreen($testProcess.MainWindowHandle,[ref]$testOrigin)) {throw 'OWN_APP_CLIENT_ORIGIN_UNAVAILABLE'}
 $testBitmap=[Drawing.Bitmap]::new(($testBounds.Right-$testBounds.Left),($testBounds.Bottom-$testBounds.Top))
 $testGraphics=[Drawing.Graphics]::FromImage($testBitmap)
 try {
  if($testOwnForeground) {
   $testGraphics.CopyFromScreen($testOrigin.X,$testOrigin.Y,0,0,$testBitmap.Size)
   $testCaptureMethod='Own foreground client pixels'
  } else {
   $testDeviceContext=$testGraphics.GetHdc()
   try {
    if(-not [JentraTestWindow]::PrintWindow($testProcess.MainWindowHandle,$testDeviceContext,3)) {throw 'OWN_APP_PRINT_CAPTURE_FAILED'}
   } finally {$testGraphics.ReleaseHdc($testDeviceContext)}
   $testCaptureMethod='PrintWindow of own client; no screen pixels read'
  }
  $testCapturePath=Join-Path $testRoot ('docs/verification/wave5/windows-test-' + $Mode.ToLowerInvariant() + '-native-20261009.png')
  $testBitmap.Save($testCapturePath,[Drawing.Imaging.ImageFormat]::Png)
 } finally {$testGraphics.Dispose();$testBitmap.Dispose();[JentraTestWindow]::SetThreadDpiAwarenessContext($testPreviousDpi) | Out-Null}
}
$testLaunch=[pscustomobject]@{launchedAt=[DateTime]::UtcNow.ToString('o');mode=$Mode;pid=$testProcess.Id;executable=$testExe;company=$testVersion.CompanyName;product=$testVersion.ProductName;windowTitle=$testProcess.MainWindowTitle;capture=$testCapturePath;captureScope='Own maximized app client area';captureMethod=$testCaptureMethod;reusedProcess=[bool]$UseRunning;nativeLaunched=$true;authenticatedAcceptance=$false;formalRuntimeProfileProvisioned=$false}
$testLaunch | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot ('docs/verification/wave5/windows-test-' + $Mode.ToLowerInvariant() + '-launch-20261009.json'))
$testLaunch | ConvertTo-Json
