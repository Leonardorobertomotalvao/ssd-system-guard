using System.Diagnostics;
using System.Text;

namespace SSDSystemGuard;

/// <summary>
/// Hosts the PowerShell resources without exposing a console.
/// Background mode detaches immediately so the .NET launcher does not stay
/// resident beside the Guard. Panel mode remains attached for diagnostics.
/// </summary>
internal static class BackgroundHost
{
    public static int RunBackground(string script)
    {
        if (!File.Exists(script))
            return 2;

        try
        {
            using var process = Process.Start(
                CreatePowerShellStartInfo(script, panelMode: false));

            return process is null ? 3 : 0;
        }
        catch (Exception ex)
        {
            WriteHostLog("startup_errors.log", ex.ToString());
            return 4;
        }
    }

    public static int RunPanel(string script)
    {
        if (!File.Exists(script))
            return 2;

        try
        {
            var psi = CreatePowerShellStartInfo(script, panelMode: true);
            psi.RedirectStandardError = true;
            psi.RedirectStandardOutput = true;

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
                    "panel_host_errors.log",
                    $"ExitCode={proc.ExitCode}{Environment.NewLine}" +
                    $"STDERR:{Environment.NewLine}{stderr}{Environment.NewLine}" +
                    $"STDOUT:{Environment.NewLine}{stdout}");
            }

            return proc.ExitCode;
        }
        catch (Exception ex)
        {
            WriteHostLog("panel_host_errors.log", ex.ToString());
            return 4;
        }
    }

    private static ProcessStartInfo CreatePowerShellStartInfo(
        string script,
        bool panelMode)
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
            WindowStyle = panelMode
                ? ProcessWindowStyle.Normal
                : ProcessWindowStyle.Hidden
        };

        psi.ArgumentList.Add("-NoLogo");
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-NonInteractive");
        psi.ArgumentList.Add("-STA");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");

        if (!panelMode)
        {
            psi.ArgumentList.Add("-WindowStyle");
            psi.ArgumentList.Add("Hidden");
        }

        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(script);

        return psi;
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
