namespace SSDSystemGuard;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // The same signed/packaged GUI binary is a windowless host when
        // launched by Task Scheduler. No powershell.exe console is created.
        if (args.Length == 1 && args[0] == "--background")
            return BackgroundHost.Run(GuardPaths.GuardCore);
        if (args.Length == 1 && args[0] == "--panel")
            return BackgroundHost.Run(GuardPaths.Panel);

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
        return 0;
    }
}
