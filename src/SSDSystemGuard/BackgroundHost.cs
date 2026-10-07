using System.Diagnostics;

namespace SSDSystemGuard;

/// <summary>Launches the existing PowerShell protection logic without a console window.</summary>
internal static class BackgroundHost
{
    public static int Run(string script)
    {
        if (!File.Exists(script))
            return 2;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                WorkingDirectory = GuardPaths.InstallDirectory
            };
            psi.ArgumentList.Add("-NoLogo");
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-STA");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-WindowStyle");
            psi.ArgumentList.Add("Hidden");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(script);
            using var proc = Process.Start(psi);
            if (proc is null) return 3;
            proc.WaitForExit();
            return proc.ExitCode;
        }
        catch (Exception ex)
        {
            try
            {
                Directory.CreateDirectory(GuardPaths.DataDirectory);
                File.AppendAllText(Path.Combine(GuardPaths.DataDirectory, "startup_errors.log"),
                    $"[{DateTimeOffset.Now:O}] {ex}{Environment.NewLine}");
            }
            catch { }
            return 4;
        }
    }
}
