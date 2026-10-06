using System.Diagnostics;

namespace SSDSystemGuard;

public sealed class MainForm : Form
{
    private readonly GuardManager _guard = new();
    private readonly Label _status = new();
    private readonly Label _details = new();
    private readonly Button _installButton = new();
    private readonly Button _panelButton = new();
    private readonly Button _resumeButton = new();
    private readonly Button _pauseButton = new();
    private readonly Button _disableButton = new();
    private readonly Button _stopButton = new();
    private readonly Button _logsButton = new();
    private readonly Button _detectionsButton = new();
    private readonly Button _folderButton = new();
    private readonly Button _uninstallButton = new();
    private readonly System.Windows.Forms.Timer _timer = new();

    public MainForm()
    {
        Text = "SSD System Guard";

        var appIcon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        if (appIcon is not null)
            Icon = appIcon;

        Width = 760;
        Height = 610;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;

        var title = new Label
        {
            Text = "SSD SYSTEM GUARD",
            Font = new Font("Segoe UI", 24, FontStyle.Bold),
            AutoSize = true,
            Left = 30,
            Top = 25
        };

        var subtitle = new Label
        {
            Text = "Proteção local para downloads, Steam/Epic e jogos portáteis no SSD do sistema.",
            Font = new Font("Segoe UI", 10),
            AutoSize = true,
            Left = 33,
            Top = 78
        };

        _status.Font = new Font("Segoe UI", 12, FontStyle.Bold);
        _status.AutoSize = true;
        _status.Left = 33;
        _status.Top = 125;

        _details.Font = new Font("Segoe UI", 9);
        _details.AutoSize = false;
        _details.Left = 33;
        _details.Top = 160;
        _details.Width = 670;
        _details.Height = 70;

        ConfigureButton(_installButton, "INSTALAR / ATUALIZAR", 33, 245, InstallClicked);
        ConfigureButton(_panelButton, "ABRIR PAINEL AVANÇADO", 385, 245, PanelClicked);

        ConfigureButton(_resumeButton, "ATIVAR / RETOMAR", 33, 310, ResumeClicked);
        ConfigureButton(_pauseButton, "PAUSAR 1 HORA", 385, 310, PauseClicked);

        ConfigureButton(_disableButton, "DESATIVAR PROTEÇÃO", 33, 375, DisableClicked);
        ConfigureButton(_stopButton, "ENCERRAR ATÉ O PRÓXIMO LOGIN", 385, 375, StopClicked);

        ConfigureButton(_logsButton, "ABRIR LOG", 33, 440, (_, _) => SafeAction(_guard.OpenLogs));
        ConfigureButton(_detectionsButton, "ABRIR DETECÇÕES", 385, 440, (_, _) => SafeAction(_guard.OpenDetections));

        ConfigureButton(_folderButton, "ABRIR PASTA DO GUARD", 33, 505, (_, _) =>
        {
            Directory.CreateDirectory(GuardPaths.InstallDirectory);
            ProcessHelper.OpenInExplorer(GuardPaths.InstallDirectory);
        });

        ConfigureButton(_uninstallButton, "DESINSTALAR", 385, 505, UninstallClicked);
        _uninstallButton.BackColor = Color.MistyRose;

        Controls.AddRange(new Control[]
        {
            title, subtitle, _status, _details,
            _installButton, _panelButton, _resumeButton, _pauseButton,
            _disableButton, _stopButton, _logsButton, _detectionsButton,
            _folderButton, _uninstallButton
        });

        _timer.Interval = 2000;
        _timer.Tick += async (_, _) => await RefreshStatusAsync();
        _timer.Start();

        Shown += async (_, _) => await RefreshStatusAsync();
        FormClosed += (_, _) => _timer.Dispose();
    }

    private static void ConfigureButton(
        Button button,
        string text,
        int left,
        int top,
        EventHandler handler)
    {
        button.Text = text;
        button.Left = left;
        button.Top = top;
        button.Width = 320;
        button.Height = 48;
        button.Click += handler;
    }

    private async void InstallClicked(object? sender, EventArgs e)
    {
        ToggleUi(false);

        try
        {
            await _guard.InstallOrUpdateAsync(Handle);

            MessageBox.Show(
                "SSD System Guard instalado/atualizado com sucesso.",
                "SSD System Guard",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            MessageBox.Show(
                "A instalação foi cancelada no UAC.",
                "SSD System Guard",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            ShowError(ex);
        }
        finally
        {
            ToggleUi(true);
            await RefreshStatusAsync();
        }
    }

    private void PanelClicked(object? sender, EventArgs e) =>
        SafeAction(_guard.OpenPanel);

    private void ResumeClicked(object? sender, EventArgs e)
    {
        SafeAction(_guard.Resume);
        _ = RefreshStatusAsync();
    }

    private void PauseClicked(object? sender, EventArgs e)
    {
        SafeAction(_guard.PauseOneHour);
        _ = RefreshStatusAsync();
    }

    private void DisableClicked(object? sender, EventArgs e)
    {
        SafeAction(_guard.DisableProtection);
        _ = RefreshStatusAsync();
    }

    private void StopClicked(object? sender, EventArgs e)
    {
        SafeAction(_guard.StopUntilNextLogin);
        MessageBox.Show(
            "O Guard recebeu o comando para encerrar até o próximo login.",
            "SSD System Guard",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    private async void UninstallClicked(object? sender, EventArgs e)
    {
        var answer = MessageBox.Show(
            "Desinstalar o SSD System Guard? O desinstalador também desfaz as regras de bloqueio criadas pelo programa.",
            "SSD System Guard",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);

        if (answer != DialogResult.Yes)
            return;

        ToggleUi(false);

        try
        {
            await _guard.UninstallAsync();

            MessageBox.Show(
                "Desinstalação concluída.",
                "SSD System Guard",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            ShowError(ex);
        }
        finally
        {
            ToggleUi(true);
            await RefreshStatusAsync();
        }
    }

    private async Task RefreshStatusAsync()
    {
        try
        {
            var installed = _guard.IsInstalled;
            var taskExists = installed && await _guard.ScheduledTaskExistsAsync();
            var cfg = installed ? _guard.ReadPublicConfig() : null;

            if (!installed)
            {
                _status.Text = "Status: NÃO INSTALADO";
                _status.ForeColor = Color.DarkRed;
                _details.Text =
                    "Clique em INSTALAR / ATUALIZAR. O aplicativo pedirá permissão de Administrador apenas quando necessário.";
                return;
            }

            if (cfg is null)
            {
                _status.Text = "Status: INSTALADO — configuração indisponível";
                _status.ForeColor = Color.DarkOrange;
                _details.Text = $"Tarefa de início automático: {(taskExists ? "OK" : "não encontrada")}";
                return;
            }

            var pauseText = "não";
            if (DateTime.TryParse(cfg.PauseUntil, out var pauseUntil) && pauseUntil > DateTime.Now)
                pauseText = $"até {pauseUntil:HH:mm}";

            _status.Text = cfg.Enabled ? "Status: ATIVO" : "Status: DESATIVADO";
            _status.ForeColor = cfg.Enabled ? Color.DarkGreen : Color.DarkRed;

            _details.Text =
                $"Disco protegido: {cfg.SystemDrive}\r\n" +
                $"Downloads: {YesNo(cfg.DownloadProtection)}   Steam: {YesNo(cfg.SteamProtection)}   Epic: {YesNo(cfg.EpicProtection)}   Portáteis: {YesNo(cfg.PortableGameProtection)}\r\n" +
                $"Apps desconhecidos: {YesNo(cfg.UnknownAppAlerts)}   Pausado: {pauseText}   Inicialização: {(taskExists ? "OK" : "não configurada")}\r\n" +
                $"Quarentena: {(string.IsNullOrWhiteSpace(cfg.QuarantinePath) ? "não configurada" : cfg.QuarantinePath)}";
        }
        catch
        {
            _status.Text = "Status: não foi possível verificar";
            _status.ForeColor = Color.DarkOrange;
        }
    }

    private static string YesNo(bool value) => value ? "ON" : "OFF";

    private void ToggleUi(bool enabled)
    {
        foreach (Control control in Controls)
            if (control is Button button)
                button.Enabled = enabled;
    }

    private static void SafeAction(Action action)
    {
        try
        {
            action();
        }
        catch (Exception ex)
        {
            ShowError(ex);
        }
    }

    private static void ShowError(Exception ex)
    {
        MessageBox.Show(
            ex.Message,
            "SSD System Guard — erro",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }
}
