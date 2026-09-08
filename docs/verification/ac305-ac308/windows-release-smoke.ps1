$ErrorActionPreference = 'Stop'
$receivableWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$receivableExecutable = Join-Path $receivableWorkspace 'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe'
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ReceivableSmokeWindows {
  public delegate bool EnumProc(IntPtr window, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr data);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
  public static int Count(uint process) {
    int count = 0;
    EnumWindows((window, data) => {uint owner;GetWindowThreadProcessId(window,out owner);if(owner==process)count++;return true;},IntPtr.Zero);
    return count;
  }
}
'@
$receivableProcess = Start-Process -FilePath $receivableExecutable -WorkingDirectory (Split-Path $receivableExecutable) -WindowStyle Hidden -PassThru
try {
  Start-Sleep -Seconds 10
  $receivableProcess.Refresh()
  if ($receivableProcess.HasExited) { throw 'Release application exited during startup.' }
  $receivableWindowCount = [ReceivableSmokeWindows]::Count($receivableProcess.Id)
  [ordered]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    configuration = 'Windows release; unconfigured backend preview'
    observedSeconds = 10
    responding = $receivableProcess.Responding
    processOwnedWindowCount = $receivableWindowCount
    pid = $receivableProcess.Id
    executable = $receivableExecutable
    authenticatedWorkflowVerified = $false
  } | ConvertTo-Json
  if (-not $receivableProcess.Responding -or $receivableWindowCount -lt 1) { throw 'Release startup assertions failed.' }
}
finally {
  $receivableProcess.Refresh()
  if (-not $receivableProcess.HasExited) { Stop-Process -Id $receivableProcess.Id }
}
