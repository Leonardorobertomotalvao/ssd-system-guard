using System.Reflection;

namespace SSDSystemGuard;

internal static class ResourceInstaller
{
    private static readonly string[] ScriptNames =
    {
        "GuardCore.ps1",
        "Panel.ps1",
        "Install.ps1",
        "Uninstall.ps1"
    };

    public static string CreateStagingDirectory()
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            "SSDSystemGuard",
            Guid.NewGuid().ToString("N"));

        Directory.CreateDirectory(root);

        foreach (var script in ScriptNames)
            ExtractScript(script, Path.Combine(root, script));

        return root;
    }

    private static void ExtractScript(string fileName, string destination)
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = $"SSDSystemGuard.Resources.{fileName}";

        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Embedded resource not found: {resourceName}");

        using var output = File.Create(destination);
        stream.CopyTo(output);
    }
}
