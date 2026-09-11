$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$executable = Join-Path $workspace 'apps\jentra_desktop\build\windows\x64\runner\Release\jentra_desktop.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Build the Windows release first.' }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StockOpeningWindowProbe {
  private delegate bool EnumCallback(IntPtr window, IntPtr parameter);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumCallback callback, IntPtr parameter);
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  public static int CountFor(int processId) {
    int count = 0;
    EnumWindows((window, parameter) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner == (uint)processId) count++;
      return true;
    }, IntPtr.Zero);
    return count;
  }
}
'@
$probeProcess = Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent $executable) -WindowStyle Hidden -PassThru
$result = $null
try {
  Start-Sleep -Seconds 10
  $probeProcess.Refresh()
  if ($probeProcess.HasExited) { throw 'Release exited during startup observation.' }
  $windows = [StockOpeningWindowProbe]::CountFor($probeProcess.Id)
  $result = [ordered]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    configuration = 'Ordinary Windows release; unconfigured backend'
    target = 'lib/main.dart'
    observedSeconds = 10
    responding = $probeProcess.Responding
    processOwnedWindowCount = $windows
    pid = $probeProcess.Id
    executable = $executable
    executableSha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
    authenticatedWorkflowVerified = $false
    openingProcessKillRecoveryVerified = $false
    stoppedByProbe = $false
  }
  if (-not $result.responding -or $windows -lt 1) { throw 'Release did not expose a responsive native window.' }
}
finally {
  $probeProcess.Refresh()
  if (-not $probeProcess.HasExited) {
    Stop-Process -Id $probeProcess.Id
    if ($null -ne $result) { $result.stoppedByProbe = $true }
  }
  if ($null -ne $result) {
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'native-release-smoke.json') -Encoding utf8
  }
}
$result | ConvertTo-Json -Depth 4
