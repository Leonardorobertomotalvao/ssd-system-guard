namespace SSDSystemGuard;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // The same WinExe is used as a console-less host.
        if (args.Length == 1 && args[0] == "--background")
            return BackgroundHost.RunBackground(GuardPaths.GuardCore);

        if (args.Length == 1 && args[0] == "--panel")
            return BackgroundHost.RunPanel(GuardPaths.Panel);

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
        return 0;
    }
}
