using System.Diagnostics;
using System.Text.Json;

namespace SSDSystemGuard;

internal sealed class GuardManager
{
    private static string InstallResultPath =>
        Path.Combine(GuardPaths.InstallDirectory, "install.result.json");

    private static string InstallLogPath =>
        Path.Combine(GuardPaths.InstallDirectory, "install.log");

    public bool IsInstalled =>
        File.Exists(GuardPaths.GuardCore) &&
        File.Exists(GuardPaths.Panel) &&
        File.Exists(GuardPaths.Config);

    public async Task<bool> ScheduledTaskExistsAsync()
    {
        try
        {
            var result = await ProcessHelper.RunAsync(
                "schtasks.exe",
                $"/Query /TN \"{GuardPaths.ScheduledTaskName}\"");

            return result.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    public async Task InstallOrUpdateAsync(IntPtr ownerHandle)
    {
        var staging = ResourceInstaller.CreateStagingDirectory();
        var installScript = Path.Combine(staging, "Install.ps1");

        try
        {
            // Remove confirmation from a previous install so we never mistake
            // an old success marker for the current attempt.
            try
            {
                if (File.Exists(InstallResultPath))
                    File.Delete(InstallResultPath);
            }
            catch
            {
                // Best effort only. The installer writes a timestamped result.
            }

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments =
                    "-NoProfile -NonInteractive -STA " +
                    "-ExecutionPolicy Bypass -WindowStyle Hidden " +
                    $"-File \"{installScript}\"",
                UseShellExecute = true,
                Verb = "runas",
                WorkingDirectory = staging,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            using var process = Process.Start(psi)
                ?? throw new InvalidOperationException(
                    "Não foi possível iniciar o instalador.");

            await process.WaitForExitAsync();

            var result = ReadInstallResult();

            // A success marker is authoritative. This also handles the rare
            // Windows 0xC000013A case where PowerShell is interrupted only
            // after all critical installation steps have completed.
            if (result?.Success == true)
                return;

            if (process.ExitCode == 0)
                return;

            var unsignedExit = unchecked((uint)process.ExitCode);
            var hex = $"0x{unsignedExit:X8}";

            if (unsignedExit == 0xC000013A)
            {
                throw new InvalidOperationException(
                    "O instalador do SSD System Guard foi interrompido " +
                    $"pelo Windows ({hex}).\n\n" +
                    "A instalação não foi confirmada como concluída.\n" +
                    $"Log: {InstallLogPath}");
            }

            var detail = string.IsNullOrWhiteSpace(result?.Message)
                ? ""
                : $"\n\nDetalhe: {result.Message}";

            throw new InvalidOperationException(
                $"O instalador terminou com código {process.ExitCode} ({hex})." +
                detail +
                $"\n\nLog: {InstallLogPath}");
        }
        finally
        {
            TryDeleteDirectory(staging);
        }
    }

    public void OpenPanel()
    {
        if (!File.Exists(GuardPaths.Panel))
            throw new FileNotFoundException(
                "O painel do Guard não foi encontrado.",
                GuardPaths.Panel);

        ProcessHelper.StartHiddenPowerShell(GuardPaths.Panel);
    }

    public void StartGuard()
    {
        if (!File.Exists(GuardPaths.GuardCore))
            throw new FileNotFoundException(
                "O núcleo do Guard não foi encontrado.",
                GuardPaths.GuardCore);

        ProcessHelper.StartHiddenPowerShell(GuardPaths.GuardCore);
    }

    public void StopUntilNextLogin()
    {
        Directory.CreateDirectory(GuardPaths.InstallDirectory);
        File.WriteAllText(
            Path.Combine(GuardPaths.InstallDirectory, "stop.flag"),
            "stop");
    }

    public void PauseOneHour()
    {
        UpdateConfig(cfg =>
        {
            cfg["Enabled"] = true;
            cfg["PauseUntil"] = DateTime.Now.AddHours(1).ToString("O");
        });
    }

    public void Resume()
    {
        UpdateConfig(cfg =>
        {
            cfg["Enabled"] = true;
            cfg["PauseUntil"] = null;
        });

        StartGuard();
    }

    public void DisableProtection()
    {
        UpdateConfig(cfg =>
        {
            cfg["Enabled"] = false;
            cfg["PauseUntil"] = null;
        });
    }

    public async Task UninstallAsync()
    {
        if (!File.Exists(
                Path.Combine(GuardPaths.InstallDirectory, "Uninstall.ps1")))
        {
            var staging = ResourceInstaller.CreateStagingDirectory();

            Directory.CreateDirectory(GuardPaths.InstallDirectory);

            File.Copy(
                Path.Combine(staging, "Uninstall.ps1"),
                Path.Combine(
                    GuardPaths.InstallDirectory,
                    "Uninstall.ps1"),
                true);

            TryDeleteDirectory(staging);
        }

        var uninstallScript = Path.Combine(
            GuardPaths.InstallDirectory,
            "Uninstall.ps1");

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments =
                "-NoProfile -STA -ExecutionPolicy Bypass " +
                $"-File \"{uninstallScript}\"",
            UseShellExecute = true,
            Verb = "runas"
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException(
                "Não foi possível iniciar o desinstalador.");

        await process.WaitForExitAsync();
    }

    public void OpenLogs()
    {
        Directory.CreateDirectory(GuardPaths.InstallDirectory);

        if (!File.Exists(GuardPaths.Log))
            File.WriteAllText(GuardPaths.Log, string.Empty);

        Process.Start(new ProcessStartInfo
        {
            FileName = "notepad.exe",
            Arguments = $"\"{GuardPaths.Log}\"",
            UseShellExecute = true
        });
    }

    public void OpenDetections()
    {
        Directory.CreateDirectory(GuardPaths.InstallDirectory);

        if (!File.Exists(GuardPaths.Detections))
            File.WriteAllText(
                GuardPaths.Detections,
                "Timestamp,Status,Category,Risk,Source,Name,Path,Reason,Action" +
                Environment.NewLine);

        Process.Start(new ProcessStartInfo
        {
            FileName = "notepad.exe",
            Arguments = $"\"{GuardPaths.Detections}\"",
            UseShellExecute = true
        });
    }

    public GuardPublicConfig? ReadPublicConfig()
    {
        try
        {
            if (!File.Exists(GuardPaths.Config))
                return null;

            using var doc = JsonDocument.Parse(
                File.ReadAllText(GuardPaths.Config));

            var root = doc.RootElement;

            return new GuardPublicConfig(
                root.TryGetProperty("Enabled", out var enabled)
                    && enabled.GetBoolean(),
                root.TryGetProperty("SystemDrive", out var drive)
                    ? drive.GetString() ?? "C:"
                    : "C:",
                root.TryGetProperty("DownloadProtection", out var dp)
                    && dp.GetBoolean(),
                root.TryGetProperty("SteamProtection", out var sp)
                    && sp.GetBoolean(),
                root.TryGetProperty("EpicProtection", out var ep)
                    && ep.GetBoolean(),
                root.TryGetProperty("PortableGameProtection", out var pp)
                    && pp.GetBoolean(),
                root.TryGetProperty("UnknownAppAlerts", out var ua)
                    && ua.GetBoolean(),
                root.TryGetProperty("QuarantinePath", out var qp)
                    ? qp.GetString() ?? string.Empty
                    : string.Empty,
                root.TryGetProperty("PauseUntil", out var pause)
                    && pause.ValueKind == JsonValueKind.String
                        ? pause.GetString()
                        : null
            );
        }
        catch
        {
            return null;
        }
    }

    private static InstallResult? ReadInstallResult()
    {
        try
        {
            if (!File.Exists(InstallResultPath))
                return null;

            return JsonSerializer.Deserialize<InstallResult>(
                File.ReadAllText(InstallResultPath),
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
        }
        catch
        {
            return null;
        }
    }

    private static void UpdateConfig(
        Action<Dictionary<string, object?>> update)
    {
        if (!File.Exists(GuardPaths.Config))
            throw new FileNotFoundException(
                "Configuração do Guard não encontrada.",
                GuardPaths.Config);

        using var doc = JsonDocument.Parse(
            File.ReadAllText(GuardPaths.Config));

        var dict = new Dictionary<string, object?>(
            StringComparer.OrdinalIgnoreCase);

        foreach (var property in doc.RootElement.EnumerateObject())
            dict[property.Name] = JsonElementToObject(property.Value);

        update(dict);

        var json = JsonSerializer.Serialize(
            dict,
            new JsonSerializerOptions { WriteIndented = true });

        File.WriteAllText(GuardPaths.Config, json);
    }

    private static object? JsonElementToObject(JsonElement element) =>
        element.ValueKind switch
        {
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number when element.TryGetInt64(out var i) => i,
            JsonValueKind.Number => element.GetDouble(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null => null,
            JsonValueKind.Array =>
                element.EnumerateArray()
                    .Select(JsonElementToObject)
                    .ToArray(),
            JsonValueKind.Object =>
                element.EnumerateObject()
                    .ToDictionary(
                        p => p.Name,
                        p => JsonElementToObject(p.Value)),
            _ => element.ToString()
        };

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
                Directory.Delete(path, true);
        }
        catch
        {
            // Staging cleanup is best-effort only.
        }
    }

    private sealed record InstallResult(
        bool Success,
        string? Message,
        string? Timestamp);
}

internal sealed record GuardPublicConfig(
    bool Enabled,
    string SystemDrive,
    bool DownloadProtection,
    bool SteamProtection,
    bool EpicProtection,
    bool PortableGameProtection,
    bool UnknownAppAlerts,
    string QuarantinePath,
    string? PauseUntil);
