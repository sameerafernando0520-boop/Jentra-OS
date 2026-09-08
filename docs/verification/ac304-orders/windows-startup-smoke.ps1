$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$executable = Join-Path $workspace 'apps/jentra_desktop/build/windows/x64/runner/Debug/jentra_desktop.exe'
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class OrderSmokeWindows {
  public delegate bool EnumProc(IntPtr window, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr data);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  public static IntPtr[] OwnedBy(uint process) {
    var windows = new List<IntPtr>();
    EnumWindows((window, data) => { uint owner; GetWindowThreadProcessId(window, out owner); if (owner == process) windows.Add(window); return true; }, IntPtr.Zero);
    return windows.ToArray();
  }
}
'@
$launched = Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'windows-launch-stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'windows-launch-stderr.log')
try {
  Start-Sleep -Seconds 10
  $launched.Refresh()
  if ($launched.HasExited) { throw 'The built application exited before the startup check.' }
  $ownedWindows = [OrderSmokeWindows]::OwnedBy($launched.Id)
  $stdout = Get-Content (Join-Path $PSScriptRoot 'windows-launch-stdout.log') -Raw
  $serviceUrl = [regex]::Match($stdout, 'http://127\.0\.0\.1:\d+/[^\s]+/').Value
  if (-not $serviceUrl) { throw 'No local Dart VM service was observed.' }
  $vm = Invoke-RestMethod -Uri ($serviceUrl + 'getVM') -TimeoutSec 10
  $isolate = $vm.result.isolates | Where-Object name -eq 'main' | Select-Object -First 1
  if (-not $isolate) { throw 'No main Dart isolate was returned.' }
  $tree = Invoke-RestMethod -Uri ($serviceUrl + 'ext.flutter.debugDumpApp?isolateId=' + [uri]::EscapeDataString($isolate.id)) -TimeoutSec 10
  $tree | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $PSScriptRoot 'windows-widget-tree.json') -Encoding utf8
  $hasFlutterTree = $tree.result.data -match 'JentraApp'
  $result = [ordered]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    configuration = 'Windows debug, unconfigured backend preview'
    observedSeconds = 10
    exitedEarly = $launched.HasExited
    responding = $launched.Responding
    windowCreated = $ownedWindows.Count -gt 0
    windowVisible = @($ownedWindows | Where-Object { [OrderSmokeWindows]::IsWindowVisible($_) }).Count -gt 0
    flutterTreeReturned = $hasFlutterTree
    pid = $launched.Id
    executable = $executable
  }
  $result | ConvertTo-Json | Tee-Object -FilePath (Join-Path $PSScriptRoot 'windows-launch.json')
  if (-not $hasFlutterTree -or -not $ownedWindows.Count -or -not $launched.Responding) { throw 'Startup assertions failed.' }
}
finally {
  $launched.Refresh()
  if (-not $launched.HasExited) { Stop-Process -Id $launched.Id }
}
