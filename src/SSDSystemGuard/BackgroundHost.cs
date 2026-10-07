using System.Diagnostics;
using System.Text;

namespace SSDSystemGuard;

/// <summary>
/// Hosts the existing PowerShell protection logic without exposing a console.
/// Background mode stays fully hidden; panel mode suppresses only the console
/// while allowing WinForms windows created by the script to be visible.
/// </summary>
internal static class BackgroundHost
{
    public static int RunBackground(string script) =>
        RunPowerShell(script, panelMode: false);

    public static int RunPanel(string script) =>
        RunPowerShell(script, panelMode: true);

    private static int RunPowerShell(string script, bool panelMode)
    {
        if (!File.Exists(script))
            return 2;

        try
        {
            var powerShell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");

            var psi = new ProcessStartInfo
            {
                FileName = powerShell,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = GuardPaths.InstallDirectory,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            psi.ArgumentList.Add("-NoLogo");
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-STA");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");

            // Important: -WindowStyle Hidden is correct for the background
            // monitor but can also suppress the first WinForms window created
            // by PowerShell on some systems. Never use it for panel mode.
            if (!panelMode)
            {
                psi.ArgumentList.Add("-WindowStyle");
                psi.ArgumentList.Add("Hidden");
                psi.WindowStyle = ProcessWindowStyle.Hidden;
            }
            else
            {
                psi.WindowStyle = ProcessWindowStyle.Normal;
            }

            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(script);

            using var proc = Process.Start(psi);
            if (proc is null)
                return 3;

            var stderrTask = proc.StandardError.ReadToEndAsync();
            var stdoutTask = proc.StandardOutput.ReadToEndAsync();

            proc.WaitForExit();

            var stderr = stderrTask.GetAwaiter().GetResult();
            var stdout = stdoutTask.GetAwaiter().GetResult();

            if (proc.ExitCode != 0 || !string.IsNullOrWhiteSpace(stderr))
            {
                WriteHostLog(
                    panelMode ? "panel_host_errors.log" : "startup_errors.log",
                    $"ExitCode={proc.ExitCode}{Environment.NewLine}" +
                    $"STDERR:{Environment.NewLine}{stderr}{Environment.NewLine}" +
                    $"STDOUT:{Environment.NewLine}{stdout}");
            }

            return proc.ExitCode;
        }
        catch (Exception ex)
        {
            WriteHostLog(
                panelMode ? "panel_host_errors.log" : "startup_errors.log",
                ex.ToString());

            return 4;
        }
    }

    private static void WriteHostLog(string fileName, string text)
    {
        try
        {
            Directory.CreateDirectory(GuardPaths.DataDirectory);

            File.AppendAllText(
                Path.Combine(GuardPaths.DataDirectory, fileName),
                $"[{DateTimeOffset.Now:O}]{Environment.NewLine}" +
                text +
                Environment.NewLine +
                Environment.NewLine,
                Encoding.UTF8);
        }
        catch
        {
            // Diagnostics must never crash the Guard.
        }
    }
}
