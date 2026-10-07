using System.Diagnostics;
using System.Drawing;

namespace SSDSystemGuard;

internal sealed class AdvancedPanelForm : Form
{
    private readonly GuardManager _guard = new();

    private readonly Label _status = new();
    private readonly Label _summary = new();

    private readonly CheckBox _downloads = new();
    private readonly CheckBox _steam = new();
    private readonly CheckBox _epic = new();
    private readonly CheckBox _portable = new();
    private readonly CheckBox _unknown = new();

    private readonly FlowLayoutPanel _actions = new();
    private readonly Button[] _actionButtons;
    private readonly System.Windows.Forms.Timer _timer = new();

    private bool _refreshing;

    public AdvancedPanelForm()
    {
        Text = "SSD System Guard 1.2.3 - Painel nativo .NET 8";
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimizeBox = true;
        MaximizeBox = true;
        MinimumSize = new Size(390, 430);
        Font = new Font("Segoe UI", 9.5f);

        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
        catch { }

        var work = Screen.FromPoint(Cursor.Position).WorkingArea;
        var desiredW = (int)Math.Round(900.0 * DeviceDpi / 96.0);
        var desiredH = (int)Math.Round(800.0 * DeviceDpi / 96.0);

        Size = new Size(
            Math.Min(desiredW, Math.Max(410, work.Width - 60)),
            Math.Min(desiredH, Math.Max(470, work.Height - 60)));

        var scroll = new Panel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true
        };
        Controls.Add(scroll);

        var content = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1,
            Padding = new Padding(18),
            Margin = Padding.Empty
        };
        content.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        scroll.Controls.Add(content);

        var heading = new Label
        {
            Text = "SSD SYSTEM GUARD 1.2.3",
            Font = new Font("Segoe UI", 21, FontStyle.Bold),
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 7)
        };

        var nativeBadge = new Label
        {
            Text = "Painel: .NET 8 nativo (PowerShell não é usado para esta interface)",
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            ForeColor = Color.DarkSlateBlue,
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 10)
        };

        var subtitle = new Label
        {
            Text = "Proteção do SSD C: para todas as contas locais deste computador.",
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 16)
        };

        _status.Text = "Status: verificando...";
        _status.Font = new Font("Segoe UI", 12, FontStyle.Bold);
        _status.AutoSize = true;
        _status.Dock = DockStyle.Top;
        _status.Margin = new Padding(0, 0, 0, 7);

        _summary.AutoSize = true;
        _summary.Dock = DockStyle.Top;
        _summary.Margin = new Padding(0, 0, 0, 14);

        var protections = new GroupBox
        {
            Text = "Proteções",
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 14)
        };

        var protectionFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(4)
        };

        ConfigureCheck(_downloads, "Bloquear downloads de risco no C:");
        ConfigureCheck(_steam, "Bloquear NOVOS jogos Steam baixados no C:");
        ConfigureCheck(_epic, "Bloquear NOVOS jogos Epic instalados no C:");
        ConfigureCheck(_portable, "Bloquear jogo portátil executado de Downloads");
        ConfigureCheck(_unknown, "Alertar sobre aplicativos desconhecidos");

        var save = NewButton("SALVAR PROTEÇÕES");
        save.Click += (_, _) => SafeUi(() =>
        {
            _guard.SaveProtectionSettings(
                _downloads.Checked,
                _steam.Checked,
                _epic.Checked,
                _portable.Checked,
                _unknown.Checked);

            RefreshUi();
        });

        protectionFlow.Controls.Add(_downloads);
        protectionFlow.Controls.Add(_steam);
        protectionFlow.Controls.Add(_epic);
        protectionFlow.Controls.Add(_portable);
        protectionFlow.Controls.Add(_unknown);
        protectionFlow.Controls.Add(save);
        protections.Controls.Add(protectionFlow);

        _actions.Dock = DockStyle.Top;
        _actions.AutoSize = true;
        _actions.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        _actions.FlowDirection = FlowDirection.LeftToRight;
        _actions.WrapContents = true;
        _actions.Margin = new Padding(0, 0, 0, 12);

        var activate = NewButton("ATIVAR / RETOMAR");
        activate.Click += (_, _) => SafeUi(() =>
        {
            _guard.Resume();
            RefreshUi();
        });

        var disable = NewButton("DESATIVAR PROTEÇÃO");
        disable.Click += (_, _) => SafeUi(() =>
        {
            _guard.DisableProtection();
            RefreshUi();
        });

        var pause = NewButton("PAUSAR POR 1 HORA");
        pause.Click += (_, _) => SafeUi(() =>
        {
            _guard.PauseOneHour();
            RefreshUi();
        });

        var unblock = NewButton("DESBLOQUEAR PASTAS STEAM/EPIC");
        unblock.Click += async (_, _) => await SafeUiAsync(async () =>
        {
            await _guard.UnblockAllAsync();

            MessageBox.Show(
                this,
                "Os bloqueios de pasta registrados para esta conta foram removidos.",
                "SSD System Guard",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);

            RefreshUi();
        });

        var testRed = NewButton("TESTAR ALERTA VERMELHO");
        testRed.Click += (_, _) => NativeAlertForm.ShowRed(this);

        var testYellow = NewButton("TESTAR ALERTA AMARELO");
        testYellow.Click += (_, _) => NativeAlertForm.ShowYellow(this);

        var log = NewButton("ABRIR LOG");
        log.Click += (_, _) => SafeUi(_guard.OpenLogs);

        var detections = NewButton("ABRIR DETECÇÕES");
        detections.Click += (_, _) => SafeUi(_guard.OpenDetections);

        var quarantine = NewButton("ABRIR QUARENTENA");
        quarantine.Click += (_, _) => SafeUi(_guard.OpenQuarantine);

        var baseline = NewButton("REFAZER BASE STEAM/EPIC");
        baseline.Click += async (_, _) =>
        {
            if (MessageBox.Show(
                    this,
                    "Isso fará o Guard considerar os jogos Steam/Epic que existem AGORA no C: como permitidos. Continuar?",
                    "Refazer base",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question) != DialogResult.Yes)
            {
                return;
            }

            await SafeUiAsync(async () =>
            {
                await _guard.RebuildBaselineAsync();

                MessageBox.Show(
                    this,
                    "A base será recriada automaticamente pelo Guard.",
                    "SSD System Guard",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);

                RefreshUi();
            });
        };

        var folder = NewButton("ABRIR PASTA DO GUARD");
        folder.Click += (_, _) =>
            ProcessHelper.OpenInExplorer(GuardPaths.InstallDirectory);

        var close = NewButton("FECHAR PAINEL (PROTEÇÃO CONTINUA)");
        close.Click += (_, _) => Close();

        _actionButtons =
        [
            activate,
            disable,
            pause,
            unblock,
            testRed,
            testYellow,
            log,
            detections,
            quarantine,
            baseline,
            folder,
            close
        ];

        foreach (var button in _actionButtons)
            _actions.Controls.Add(button);

        var note = new Label
        {
            Text =
                "Steam e Epic podem abrir normalmente. Fechar esta janela NÃO " +
                "encerra a proteção; use DESATIVAR PROTEÇÃO para desligar o bloqueio.",
            AutoSize = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 4, 0, 12)
        };

        content.Controls.Add(heading);
        content.Controls.Add(nativeBadge);
        content.Controls.Add(subtitle);
        content.Controls.Add(_status);
        content.Controls.Add(_summary);
        content.Controls.Add(protections);
        content.Controls.Add(_actions);
        content.Controls.Add(note);

        void ResizeLayout()
        {
            var available = Math.Max(
                250,
                scroll.ClientSize.Width - content.Padding.Horizontal - 8);

            content.Width = Math.Max(280, scroll.ClientSize.Width);

            foreach (var label in new[]
                     {
                         heading, nativeBadge, subtitle, _status, _summary, note
                     })
            {
                label.MaximumSize = new Size(available, 0);
            }

            foreach (var check in new[]
                     {
                         _downloads, _steam, _epic, _portable, _unknown
                     })
            {
                check.MaximumSize = new Size(
                    Math.Max(230, available - 30),
                    0);
            }

            var cols =
                available >= (int)Math.Round(720.0 * DeviceDpi / 96.0)
                    ? 2
                    : 1;

            var width = cols == 2
                ? Math.Max(270, (available - 30) / 2)
                : Math.Max(250, available - 12);

            foreach (var button in _actionButtons)
                button.Width = width;
        }

        scroll.SizeChanged += (_, _) => ResizeLayout();

        Shown += (_, _) =>
        {
            ResizeLayout();
            RefreshUi();
        };

        _timer.Interval = 5000;
        _timer.Tick += (_, _) => RefreshUi();
        _timer.Start();

        FormClosed += (_, _) => _timer.Dispose();
    }

    private static void ConfigureCheck(CheckBox check, string text)
    {
        check.Text = text;
        check.AutoSize = true;
        check.Margin = new Padding(5, 4, 5, 4);
    }

    private static Button NewButton(string text) =>
        new()
        {
            Text = text,
            Width = 330,
            Height = 46,
            AutoSize = false,
            Margin = new Padding(5)
        };

    private void RefreshUi()
    {
        if (_refreshing || IsDisposed)
            return;

        _refreshing = true;

        try
        {
            var cfg = _guard.ReadPublicConfig();

            if (cfg is null)
            {
                _status.Text = "Status: configuração indisponível";
                _status.ForeColor = Color.DarkOrange;
                return;
            }

            var paused =
                DateTime.TryParse(cfg.PauseUntil, out var until) &&
                until > DateTime.Now;

            _status.Text = !cfg.Enabled
                ? "Status: DESATIVADO"
                : paused
                    ? "Status: PAUSADO"
                    : "Status: ATIVO";

            _status.ForeColor = !cfg.Enabled
                ? Color.DarkRed
                : paused
                    ? Color.DarkOrange
                    : Color.DarkGreen;

            var counts = _guard.GetDetectionCounts();

            _summary.Text =
                $"Bloqueios registrados: {counts.Blocked}   |   " +
                $"Alertas: {counts.Alerts}   |   " +
                "Quarentena: " +
                (string.IsNullOrWhiteSpace(cfg.QuarantinePath)
                    ? "sem quarentena externa"
                    : cfg.QuarantinePath);

            _downloads.Checked = cfg.DownloadProtection;
            _steam.Checked = cfg.SteamProtection;
            _epic.Checked = cfg.EpicProtection;
            _portable.Checked = cfg.PortableGameProtection;
            _unknown.Checked = cfg.UnknownAppAlerts;
        }
        catch (Exception ex)
        {
            _status.Text = "Status: erro ao atualizar painel";
            _status.ForeColor = Color.DarkRed;
            WriteUiError("RefreshUi", ex);
        }
        finally
        {
            _refreshing = false;
        }
    }

    private void SafeUi(Action action)
    {
        try
        {
            action();
        }
        catch (Exception ex)
        {
            WriteUiError("Ação do painel", ex);

            MessageBox.Show(
                this,
                ex.Message,
                "SSD System Guard",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private async Task SafeUiAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            WriteUiError("Ação assíncrona do painel", ex);

            MessageBox.Show(
                this,
                ex.Message,
                "SSD System Guard",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static void WriteUiError(string context, Exception ex)
    {
        try
        {
            Directory.CreateDirectory(GuardPaths.DataDirectory);

            File.AppendAllText(
                Path.Combine(
                    GuardPaths.DataDirectory,
                    "native_panel_errors.log"),
                $"[{DateTimeOffset.Now:O}] {context}{Environment.NewLine}" +
                ex +
                Environment.NewLine +
                Environment.NewLine);
        }
        catch { }
    }
}
