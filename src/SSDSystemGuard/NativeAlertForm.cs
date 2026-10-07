using System.Drawing;

namespace SSDSystemGuard;

internal sealed class NativeAlertForm : Form
{
    private NativeAlertForm(
        bool blocked,
        string category,
        string name,
        string path,
        string reason)
    {
        Text = "SSD System Guard 1.2.3 - Teste";
        StartPosition = FormStartPosition.CenterParent;
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimizeBox = true;
        MaximizeBox = true;
        MinimumSize = new Size(430, 370);
        Font = new Font("Segoe UI", 9.5f);

        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
        catch { }

        var work = Screen.FromPoint(Cursor.Position).WorkingArea;
        Width = Math.Min(760, Math.Max(460, work.Width - 120));
        Height = Math.Min(590, Math.Max(430, work.Height - 140));

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            AutoScroll = true,
            Padding = Padding.Empty
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 108,
            BackColor = blocked
                ? Color.FromArgb(160, 25, 25)
                : Color.FromArgb(190, 120, 0)
        };

        var headerFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(22, 15, 12, 8)
        };

        var title = new Label
        {
            AutoSize = true,
            ForeColor = Color.White,
            Font = new Font("Segoe UI", 19, FontStyle.Bold),
            Text = blocked ? "BLOQUEADO" : "SUSPEITO / REQUER VALIDAÇÃO"
        };

        var subtitle = new Label
        {
            AutoSize = true,
            ForeColor = Color.White,
            MaximumSize = new Size(680, 0),
            Text = $"{category}   |   Risco: {(blocked ? "ALTO" : "MÉDIO")}   |   Origem: Teste interno"
        };

        headerFlow.Controls.Add(title);
        headerFlow.Controls.Add(subtitle);
        header.Controls.Add(headerFlow);

        var details = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1,
            Padding = new Padding(22, 14, 22, 12)
        };
        details.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        AddDetail(details, "Item detectado:", name, false);
        AddDetail(details, "Caminho:", path, false);
        AddDetail(details, "Motivo:", reason, true);
        AddDetail(
            details,
            "Ação:",
            "Nenhum arquivo real foi alterado. Este é apenas um teste visual.",
            true);

        var notice = new Label
        {
            Text = "MODO DE TESTE — nenhuma proteção real foi acionada.",
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            AutoSize = true,
            Dock = DockStyle.Top,
            Padding = new Padding(22, 4, 22, 4)
        };

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.RightToLeft,
            Padding = new Padding(12, 4, 18, 14)
        };

        var ok = new Button
        {
            Text = "OK",
            Width = 120,
            Height = 38
        };
        ok.Click += (_, _) => Close();
        buttons.Controls.Add(ok);

        root.Controls.Add(header, 0, 0);
        root.Controls.Add(details, 0, 1);
        root.Controls.Add(notice, 0, 2);
        root.Controls.Add(buttons, 0, 3);
    }

    private static void AddDetail(
        TableLayoutPanel parent,
        string caption,
        string value,
        bool multiline)
    {
        var label = new Label
        {
            Text = caption,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            AutoSize = true,
            Margin = new Padding(3, 7, 3, 3)
        };

        var box = new TextBox
        {
            Text = value,
            ReadOnly = true,
            Dock = DockStyle.Top,
            Multiline = multiline,
            Height = multiline ? 64 : 28,
            ScrollBars = multiline ? ScrollBars.Vertical : ScrollBars.None,
            Margin = new Padding(3, 0, 3, 4)
        };

        parent.Controls.Add(label);
        parent.Controls.Add(box);
    }

    public static void ShowRed(IWin32Window owner)
    {
        using var form = new NativeAlertForm(
            true,
            "TESTE - jogo/download",
            "Steam_Game_Test.exe",
            @"C:\Users\Teste\Downloads\Steam_Game_Test.exe",
            "Alerta vermelho de teste do SSD System Guard.");

        System.Media.SystemSounds.Exclamation.Play();
        form.ShowDialog(owner);
    }

    public static void ShowYellow(IWin32Window owner)
    {
        using var form = new NativeAlertForm(
            false,
            "TESTE - aplicativo desconhecido",
            "Programa_Desconhecido.exe",
            @"C:\Users\Teste\Downloads\Programa_Desconhecido.exe",
            "Alerta amarelo de teste do SSD System Guard.");

        System.Media.SystemSounds.Exclamation.Play();
        form.ShowDialog(owner);
    }
}
