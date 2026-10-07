using System.Diagnostics;
using System.Drawing;

namespace SSDSystemGuard;

/// <summary>Fluid WinForms UI that does not rely on fixed pixel positions.</summary>
public sealed class MainForm : Form
{
    private readonly GuardManager _guard = new();
    private readonly Label _status = new();
    private readonly Label _details = new();
    private readonly Label _subtitle = new();
    private readonly Label _heading = new();
    private readonly TableLayoutPanel _actions = new();
    private readonly Button[] _buttons;
    private readonly System.Windows.Forms.Timer _timer = new();
    private bool _refreshing;
    private bool _busy;
    private int _columns;

    public MainForm()
    {
        Text = "SSD System Guard";
        try { Icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 9.5f);
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimizeBox = true;
        MaximizeBox = true;
        MinimumSize = new Size(330, 310);
        StartPosition = FormStartPosition.CenterScreen;

        var work = Screen.FromPoint(Cursor.Position).WorkingArea;
        int scale = Math.Max(1, DeviceDpi) ;
        int desiredW = (int)Math.Round(850.0 * scale / 96);
        int desiredH = (int)Math.Round(650.0 * scale / 96);
        Size = new Size(Math.Min(desiredW, Math.Max(340, work.Width - 48)),
                        Math.Min(desiredH, Math.Max(320, work.Height - 48)));

        var scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true };
        Controls.Add(scroll);
        var content = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1,
            Padding = new Padding(18, 18, 18, 22),
            Margin = Padding.Empty
        };
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        scroll.Controls.Add(content);

        _heading.Text = "SSD SYSTEM GUARD";
        _heading.Font = new Font("Segoe UI", 23f, FontStyle.Bold);
        _heading.AutoSize = true;
        _heading.Margin = new Padding(0, 0, 0, 8);
        _heading.Dock = DockStyle.Top;

        _subtitle.Text = "Proteção do SSD do sistema para todas as contas locais deste computador.";
        _subtitle.AutoSize = true;
        _subtitle.Margin = new Padding(0, 0, 0, 20);
        _subtitle.Dock = DockStyle.Top;

        _status.Text = "Verificando instalação...";
        _status.Font = new Font("Segoe UI", 12, FontStyle.Bold);
        _status.AutoSize = true;
        _status.Margin = new Padding(0, 0, 0, 8);
        _status.Dock = DockStyle.Top;

        _details.AutoSize = true;
        _details.Margin = new Padding(0, 0, 0, 20);
        _details.Dock = DockStyle.Top;

        _actions.Dock = DockStyle.Top;
        _actions.AutoSize = true;
        _actions.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        _actions.Margin = Padding.Empty;
        _actions.GrowStyle = TableLayoutPanelGrowStyle.AddRows;

        _buttons = new[]
        {
            NewButton("INSTALAR / ATUALIZAR", InstallClicked),
            NewButton("ABRIR PAINEL AVANÇADO", (_, _) => SafeAction(_guard.OpenPanel)),
            NewButton("ATIVAR / RETOMAR", (_, _) => { SafeAction(_guard.Resume); _ = RefreshStatusAsync(); }),
            NewButton("PAUSAR 1 HORA", (_, _) => { SafeAction(_guard.PauseOneHour); _ = RefreshStatusAsync(); }),
            NewButton("DESATIVAR PROTEÇÃO", (_, _) => { SafeAction(_guard.DisableProtection); _ = RefreshStatusAsync(); }),
            NewButton("ENCERRAR NESTA CONTA", StopClicked),
            NewButton("ABRIR LOG", (_, _) => SafeAction(_guard.OpenLogs)),
            NewButton("ABRIR DETECÇÕES", (_, _) => SafeAction(_guard.OpenDetections)),
            NewButton("ABRIR PASTA DO GUARD", (_, _) => ProcessHelper.OpenInExplorer(GuardPaths.InstallDirectory)),
            NewButton("DESINSTALAR DO COMPUTADOR", UninstallClicked),
        };
        _buttons[^1].BackColor = Color.MistyRose;

        content.Controls.Add(_heading);
        content.Controls.Add(_subtitle);
        content.Controls.Add(_status);
        content.Controls.Add(_details);
        content.Controls.Add(_actions);

        void ResizeLayout()
        {
            var available = Math.Max(230, scroll.ClientSize.Width - content.Padding.Horizontal - 6);
            content.Width = Math.Max(260, scroll.ClientSize.Width);
            _heading.MaximumSize = new Size(available, 0);
            _subtitle.MaximumSize = new Size(available, 0);
            _status.MaximumSize = new Size(available, 0);
            _details.MaximumSize = new Size(available, 0);
            var cols = available >= (int)Math.Round(600.0 * DeviceDpi / 96.0) ? 2 : 1;
            if (cols != _columns)
            {
                _columns = cols;
                _actions.SuspendLayout();
                _actions.Controls.Clear();
                _actions.ColumnStyles.Clear();
                _actions.RowStyles.Clear();
                _actions.ColumnCount = cols;
                _actions.RowCount = (_buttons.Length + cols - 1) / cols;
                for (int c = 0; c < cols; c++)
                    _actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / cols));
                for (int i = 0; i < _buttons.Length; i++)
                    _actions.Controls.Add(_buttons[i], i % cols, i / cols);
                _actions.ResumeLayout(true);
            }
        }
        scroll.SizeChanged += (_, _) => ResizeLayout();
        Shown += async (_, _) => { ResizeLayout(); await RefreshStatusAsync(); };
        _timer.Interval = 3000;
        _timer.Tick += async (_, _) => await RefreshStatusAsync();
        _timer.Start();
        FormClosed += (_, _) => _timer.Dispose();
    }

    private static Button NewButton(string text, EventHandler action)
    {
        var button = new Button
        {
            Text = text,
            Dock = DockStyle.Fill,
            AutoSize = false,
            Height = 48,
            MinimumSize = new Size(0, 44),
            Margin = new Padding(4, 4, 4, 8)
        };
        button.Click += action;
        return button;
    }

    private async void InstallClicked(object? sender, EventArgs e)
    {
        ToggleUi(false);
        try
        {
            await _guard.InstallOrUpdateAsync(Handle);
            MessageBox.Show("SSD System Guard instalado para as contas locais deste PC. " +
                "A proteção inicia na sessão de cada usuário após seu logon.",
                "SSD System Guard", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            MessageBox.Show("Operação cancelada no UAC.", "SSD System Guard", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex) { ShowError(ex); }
        finally { ToggleUi(true); await RefreshStatusAsync(); }
    }

    private void StopClicked(object? sender, EventArgs e)
    {
        SafeAction(_guard.StopUntilNextLogin);
        MessageBox.Show("O Guard será encerrado nesta conta até o próximo logon. As outras sessões continuam independentes.",
            "SSD System Guard", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private async void UninstallClicked(object? sender, EventArgs e)
    {
        if (MessageBox.Show("Desinstalar o Guard de todo o computador e remover as regras de bloqueio registradas?",
                "SSD System Guard", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
        ToggleUi(false);
        try { await _guard.UninstallAsync(); }
        catch (Exception ex) { ShowError(ex); }
        finally { ToggleUi(true); await RefreshStatusAsync(); }
    }

    private async Task RefreshStatusAsync()
    {
        if (_refreshing || IsDisposed) return;
        _refreshing = true;
        try
        {
            var installed = _guard.IsInstalled;
            var taskExists = installed && await _guard.ScheduledTaskExistsAsync();
            var cfg = installed ? _guard.ReadPublicConfig() : null;
            if (IsDisposed) return;
            if (!installed)
            {
                _status.Text = "Status: NÃO INSTALADO";
                _status.ForeColor = Color.DarkRed;
                _details.Text = "Clique em INSTALAR / ATUALIZAR para proteger as contas locais do computador.";
                return;
            }
            if (cfg is null)
            {
                _status.Text = "Status: configuração indisponível";
                _status.ForeColor = Color.DarkOrange;
                _details.Text = $"Inicialização geral: {(taskExists ? "OK" : "não configurada")}";
                return;
            }
            var paused = DateTime.TryParse(cfg.PauseUntil, out var until) && until > DateTime.Now;
            _status.Text = !cfg.Enabled ? "Status: DESATIVADO" : paused ? "Status: PAUSADO" : "Status: ATIVO";
            _status.ForeColor = !cfg.Enabled ? Color.DarkRed : paused ? Color.DarkOrange : Color.DarkGreen;
            _details.Text =
                $"Abrangência: contas locais | Disco: {cfg.SystemDrive} | Inicialização: {(taskExists ? "OK" : "NÃO CONFIGURADA")}\n" +
                $"Downloads: {YesNo(cfg.DownloadProtection)} | Steam: {YesNo(cfg.SteamProtection)} | Epic: {YesNo(cfg.EpicProtection)} | Portáteis: {YesNo(cfg.PortableGameProtection)}\n" +
                $"Apps desconhecidos: {YesNo(cfg.UnknownAppAlerts)} | Quarentena: " +
                (string.IsNullOrWhiteSpace(cfg.QuarantinePath) ? "sem disco externo" : cfg.QuarantinePath);
        }
        catch { if (!IsDisposed) _status.Text = "Status: falha ao consultar serviço"; }
        finally { _refreshing = false; }
    }
    private static string YesNo(bool value) => value ? "ON" : "OFF";
    private void ToggleUi(bool enabled)
    {
        _busy = !enabled;
        foreach (var b in _buttons) b.Enabled = enabled;
    }
    private static void SafeAction(Action action)
    {
        try { action(); } catch (Exception ex) { ShowError(ex); }
    }
    private static void ShowError(Exception ex) =>
        MessageBox.Show(ex.Message, "SSD System Guard — erro", MessageBoxButtons.OK, MessageBoxIcon.Error);
}
