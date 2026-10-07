using System.Diagnostics;
using System.Text;

namespace SSDSystemGuard;

internal static class BackgroundHost
{
    public static int RunBackground(string script)
    {
        if (!File.Exists(script))
            return 2;

        try
        {
            using var process = Process.Start(CreatePowerShellStartInfo(script));
            return process is null ? 3 : 0;
        }
        catch (Exception ex)
        {
            WriteHostLog("startup_errors.log", ex.ToString());
            return 4;
        }
    }

    private static ProcessStartInfo CreatePowerShellStartInfo(string script)
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
            WindowStyle = ProcessWindowStyle.Hidden
        };

        psi.ArgumentList.Add("-NoLogo");
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-NonInteractive");
        psi.ArgumentList.Add("-STA");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-WindowStyle");
        psi.ArgumentList.Add("Hidden");
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
        catch { }
    }
}
