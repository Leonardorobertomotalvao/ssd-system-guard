namespace SSDSystemGuard;

internal static class GuardPaths
{
    public static string InstallDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SSDSystemGuardDefinitive");

    public static string GuardCore => Path.Combine(InstallDirectory, "GuardCore.ps1");
    public static string Panel => Path.Combine(InstallDirectory, "Panel.ps1");
    public static string Config => Path.Combine(InstallDirectory, "config.json");
    public static string Log => Path.Combine(InstallDirectory, "guard.log");
    public static string Detections => Path.Combine(InstallDirectory, "detections.csv");

    public const string ScheduledTaskName = "SSD System Guard Definitivo";
}
