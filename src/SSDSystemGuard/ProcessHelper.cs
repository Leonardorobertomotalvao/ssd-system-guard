using System.Diagnostics;
using System.Text;

namespace SSDSystemGuard;

internal static class ProcessHelper
{
    public static async Task<(int ExitCode, string StdOut, string StdErr)> RunAsync(
        string fileName,
        string arguments,
        bool hidden = true,
        bool useShellExecute = false,
        string? verb = null)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = useShellExecute,
            CreateNoWindow = hidden && !useShellExecute,
            WindowStyle = hidden ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal
        };

        if (!string.IsNullOrWhiteSpace(verb))
            psi.Verb = verb;

        if (!useShellExecute)
        {
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
        }

        using var process = new Process { StartInfo = psi };
        process.Start();

        if (useShellExecute)
        {
            await process.WaitForExitAsync();
            return (process.ExitCode, string.Empty, string.Empty);
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();

        await process.WaitForExitAsync();

        return (
            process.ExitCode,
            await stdoutTask,
            await stderrTask);
    }

    public static void StartHiddenPowerShell(string scriptPath)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments =
                $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{scriptPath}\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        Process.Start(psi);
    }

    public static void OpenInExplorer(string path)
    {
        if (File.Exists(path))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{path}\"",
                UseShellExecute = true
            });
        }
        else if (Directory.Exists(path))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = path,
                UseShellExecute = true
            });
        }
    }
}
