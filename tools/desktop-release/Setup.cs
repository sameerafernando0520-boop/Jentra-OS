using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class Setup {
  [STAThread]
  private static int Main(string[] args) {
    bool quiet = false;
    string installRoot = null;
    foreach (string arg in args) {
      if (arg == "/quiet") quiet = true;
      else if (arg.StartsWith("/staging-root=", StringComparison.OrdinalIgnoreCase)) installRoot = arg.Substring(14);
      else { MessageBox.Show("Unknown setup option.", "Jentra OS Setup"); return 2; }
    }
    string stage = Path.Combine(Path.GetTempPath(), "JentraOS-Setup-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(stage);
    try {
      string zip = Path.Combine(stage, "package.zip");
      using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream("JentraPackage"))
      using (FileStream target = File.Create(zip)) {
        if (source == null) throw new InvalidOperationException("Embedded package is missing.");
        source.CopyTo(target);
      }
      string extracted = Path.Combine(stage, "package");
      ZipFile.ExtractToDirectory(zip, extracted);
      string command = "-NoProfile -ExecutionPolicy Bypass -File " + Quote(Path.Combine(extracted, "Install.ps1")) + " -PackageRoot " + Quote(extracted);
      if (installRoot != null) command += " -InstallRoot " + Quote(Path.GetFullPath(installRoot)) + " -NoShortcuts -NoRegistration";
      var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"), command);
      start.UseShellExecute = false;
      start.CreateNoWindow = true;
      start.RedirectStandardOutput = true;
      start.RedirectStandardError = true;
      // Let Windows PowerShell build its own module search path rather than
      // inheriting PowerShell 7's incompatible module directories from a build shell.
      start.EnvironmentVariables.Remove("PSModulePath");
      using (Process process = Process.Start(start)) {
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        process.WaitForExit();
        string output = outputTask.Result;
        string error = errorTask.Result;
        File.WriteAllText(Path.Combine(stage, "install.log"), output + Environment.NewLine + error);
        if (process.ExitCode != 0) {
          if (!quiet) MessageBox.Show("Installation could not finish. No running app was stopped. Details: " + Path.Combine(stage, "install.log"), "Jentra OS Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
          return process.ExitCode;
        }
      }
      if (!quiet) MessageBox.Show("Jentra OS is installed. Open its Start menu shortcut to use the updated build. Existing app data and previous releases were retained.", "Jentra OS Setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
      return 0;
    } catch (Exception error) {
      File.WriteAllText(Path.Combine(stage, "setup-error.log"), error.ToString());
      if (!quiet) MessageBox.Show("Installation could not finish. Details: " + Path.Combine(stage, "setup-error.log"), "Jentra OS Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
      return 1;
    }
  }

  private static string Quote(string value) {
    if (value.IndexOf('"') >= 0 || value.IndexOf('\r') >= 0 || value.IndexOf('\n') >= 0) throw new ArgumentException("Invalid setup path.");
    return "\"" + value + "\"";
  }
}
