namespace SSDSystemGuard;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--background")
            return BackgroundHost.RunBackground(GuardPaths.GuardCore);

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        if (args.Length == 1 && args[0] == "--panel")
        {
            Application.Run(new AdvancedPanelForm());
            return 0;
        }

        Application.Run(new MainForm());
        return 0;
    }
}
