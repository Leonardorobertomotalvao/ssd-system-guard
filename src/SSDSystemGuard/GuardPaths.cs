namespace SSDSystemGuard;

internal static class GuardPaths
{
    public static string InstallDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "SSDSystemGuard");

    public static string DataDirectory =>
        Path.Combine(InstallDirectory, "Data");

    public static string GuardCore => Path.Combine(InstallDirectory, "GuardCore.ps1");
    public static string Panel => Path.Combine(InstallDirectory, "Panel.ps1");
    public static string Config => Path.Combine(DataDirectory, "config.json");
    public static string Log => Path.Combine(DataDirectory, "guard.log");
    public static string Detections => Path.Combine(DataDirectory, "detections.csv");

    public static string CurrentSidKey
    {
        get
        {
            try
            {
                return System.Security.Principal.WindowsIdentity
                    .GetCurrent().User?.Value.Replace('-', '_') ?? "unknown";
            }
            catch
            {
                return "unknown";
            }
        }
    }

    public static string StopFlag =>
        Path.Combine(DataDirectory, $"stop-{CurrentSidKey}.flag");

    public const string ScheduledTaskName = "SSD System Guard";
}
