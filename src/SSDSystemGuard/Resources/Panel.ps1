#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Base = Join-Path $env:ProgramData "SSDSystemGuard"
$Data = Join-Path $Base "Data"
$PanelErrorLog = Join-Path $Data "panel_errors.log"

function Write-PanelError {
    param([string]$Message)

    try {
        New-Item -ItemType Directory -Path $Data -Force | Out-Null
        Add-Content -LiteralPath $PanelErrorLog `
            -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Message) `
            -Encoding UTF8
    } catch {}
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Evita o diálogo genérico e repetitivo do .NET Framework quando uma
    # exceção acontece dentro de um evento WinForms. O erro é registrado em
    # panel_errors.log para diagnóstico.
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
        [System.Windows.Forms.UnhandledExceptionMode]::CatchException
    )

    $script:PanelThreadExceptionHandler =
        [System.Threading.ThreadExceptionEventHandler]{
            param($sender,$eventArgs)

            try {
                $message = if ($eventArgs.Exception) {
                    $eventArgs.Exception.ToString()
                }
                else {
                    "ThreadException sem objeto Exception."
                }

                Write-PanelError ("WinForms ThreadException: " + $message)
            } catch {}
        }

    try {
        [System.Windows.Forms.Application]::add_ThreadException(
            $script:PanelThreadExceptionHandler
        )
    } catch {}

    # Best effort DPI awareness for the PowerShell-hosted WinForms panel.
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SSDGuardDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
"@ -ErrorAction SilentlyContinue

        [void][SSDGuardDpi]::SetProcessDpiAwarenessContext([IntPtr](-4))
    } catch {}

    try {
        $SidKey = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value.Replace("-","_")
    } catch {
        $SidKey = "unknown"
    }

    $ConfigPath = Join-Path $Data "config.json"
    $StatePath = Join-Path $Data ("state-" + $SidKey + ".json")
    $LogPath = Join-Path $Data "guard.log"
    $DetectionsPath = Join-Path $Data "detections.csv"
    $CorePath = Join-Path $Base "GuardCore.ps1"
    $HostExe = Join-Path $Base "SSDSystemGuard.exe"
        $TestRedFlag = Join-Path $Data ("test_red-" + $SidKey + ".flag")
    $TestYellowFlag = Join-Path $Data ("test_yellow-" + $SidKey + ".flag")
    $IconPath = Join-Path $Base "SSDSystemGuard.ico"

    function Get-Cfg {
        try {
            Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 |
                ConvertFrom-Json
        } catch {
            $null
        }
    }

    function Save-Cfg {
        param($cfg)

        try {
            $cfg |
                ConvertTo-Json -Depth 12 |
                Set-Content -LiteralPath $ConfigPath -Encoding UTF8
        } catch {
            Write-PanelError ("Save-Cfg: " + $_.Exception.Message)
        }
    }

    function Get-State {
        try {
            Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 |
                ConvertFrom-Json
        } catch {
            $null
        }
    }

    function Save-State {
        param($state)

        try {
            $state |
                ConvertTo-Json -Depth 15 |
                Set-Content -LiteralPath $StatePath -Encoding UTF8
        } catch {
            Write-PanelError ("Save-State: " + $_.Exception.Message)
        }
    }

    function Ensure-CoreRunning {
        $running = $false

        try {
            $running = @(
                Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
                Where-Object {
                    $_.CommandLine -like "*SSDSystemGuard*GuardCore.ps1*"
                }
            ).Count -gt 0
        } catch {}

        if (-not $running -and (Test-Path -LiteralPath $HostExe)) {
            Start-Process `
                -FilePath $HostExe `
                -ArgumentList "--background" `
                -WindowStyle Hidden
        }
    }

    function Remove-GuardACL {
        param([string]$Path)

        if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
            return
        }

        try {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $acl = Get-Acl -LiteralPath $Path
            $changed = $false

            foreach ($rule in @($acl.Access)) {
                if (
                    $rule.IdentityReference.Value -eq $identity -and
                    $rule.AccessControlType -eq
                        [System.Security.AccessControl.AccessControlType]::Deny
                ) {
                    [void]$acl.RemoveAccessRuleSpecific($rule)
                    $changed = $true
                }
            }

            if ($changed) {
                Set-Acl -LiteralPath $Path -AclObject $acl
            }
        } catch {
            Write-PanelError ("Remove-GuardACL: " + $_.Exception.Message)
        }
    }

    function Unblock-All {
        $state = Get-State

        if (-not $state) {
            return
        }

        foreach ($item in @($state.BlockedPaths)) {
            if ($item.Path) {
                Remove-GuardACL ([string]$item.Path)
            }
        }

        $state.BlockedPaths = @()
        Save-State $state
    }

    function Get-Counts {
        $red = 0
        $yellow = 0

        if (Test-Path -LiteralPath $DetectionsPath) {
            try {
                $rows = Import-Csv -LiteralPath $DetectionsPath

                foreach ($row in @($rows)) {
                    $rowStatus = [string]$row.Status

                    if ($rowStatus -like "*BLOQUEADO*") {
                        $red++
                    }

                    if ($rowStatus -like "*SUSPEITO*") {
                        $yellow++
                    }
                }
            } catch {
                Write-PanelError (
                    "Get-Counts: " +
                    $_.Exception.ToString()
                )
            }
        }

        return [pscustomobject]@{
            Blocked = [int]$red
            Alerts = [int]$yellow
        }
    }

    function New-ActionButton {
        param(
            [string]$Text,
            [int]$Height = 46
        )

        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Height = $Height
        $button.Width = 330
        $button.Margin = New-Object System.Windows.Forms.Padding(5)
        $button.AutoSize = $false
        return $button
    }

    function Show-PanelTestAlert {
        param(
            [ValidateSet("Red","Yellow")]
            [string]$Kind
        )

        $isRed = $Kind -eq "Red"

        $testForm = New-Object System.Windows.Forms.Form
        $testForm.Text = "SSD System Guard - Teste"
        $testForm.StartPosition = "CenterParent"
        $testForm.FormBorderStyle = "Sizable"
        $testForm.MinimizeBox = $true
        $testForm.MaximizeBox = $true
        $testForm.MinimumSize = New-Object System.Drawing.Size(420,360)
        $testForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
        $testForm.TopMost = $true

        $workingArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
        $testForm.Width = [Math]::Min(760,[Math]::Max(460,$workingArea.Width - 100))
        $testForm.Height = [Math]::Min(600,[Math]::Max(420,$workingArea.Height - 120))

        if (Test-Path -LiteralPath $IconPath) {
            try {
                $testForm.Icon = New-Object System.Drawing.Icon($IconPath)
            } catch {}
        }

        $root = New-Object System.Windows.Forms.TableLayoutPanel
        $root.Dock = "Fill"
        $root.AutoScroll = $true
        $root.ColumnCount = 1
        $root.RowCount = 4
        $root.Padding = New-Object System.Windows.Forms.Padding(0)
        [void]$root.ColumnStyles.Add(
            (New-Object System.Windows.Forms.ColumnStyle(
                [System.Windows.Forms.SizeType]::Percent,
                100
            ))
        )
        [void]$root.RowStyles.Add(
            (New-Object System.Windows.Forms.RowStyle(
                [System.Windows.Forms.SizeType]::AutoSize
            ))
        )
        [void]$root.RowStyles.Add(
            (New-Object System.Windows.Forms.RowStyle(
                [System.Windows.Forms.SizeType]::Percent,
                100
            ))
        )
        [void]$root.RowStyles.Add(
            (New-Object System.Windows.Forms.RowStyle(
                [System.Windows.Forms.SizeType]::AutoSize
            ))
        )
        [void]$root.RowStyles.Add(
            (New-Object System.Windows.Forms.RowStyle(
                [System.Windows.Forms.SizeType]::AutoSize
            ))
        )
        $testForm.Controls.Add($root)

        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = "Top"
        $header.Height = 115

        if ($isRed) {
            $header.BackColor = [System.Drawing.Color]::FromArgb(160,25,25)
            $statusText = "BLOQUEADO"
            $categoryText = "TESTE - jogo/download"
            $riskText = "ALTO"
            $nameText = "Steam_Game_Test.exe"
            $pathText = "C:\Users\Teste\Downloads\Steam_Game_Test.exe"
            $reasonText = "Alerta vermelho de teste do SSD System Guard."
        }
        else {
            $header.BackColor = [System.Drawing.Color]::FromArgb(190,120,0)
            $statusText = "SUSPEITO / REQUER VALIDAÇÃO"
            $categoryText = "TESTE - aplicativo desconhecido"
            $riskText = "MÉDIO"
            $nameText = "Programa_Desconhecido.exe"
            $pathText = "C:\Users\Teste\Downloads\Programa_Desconhecido.exe"
            $reasonText = "Alerta amarelo de teste do SSD System Guard."
        }

        $headerFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $headerFlow.Dock = "Fill"
        $headerFlow.FlowDirection = "TopDown"
        $headerFlow.WrapContents = $false
        $headerFlow.Padding = New-Object System.Windows.Forms.Padding(22,14,14,8)

        $testTitle = New-Object System.Windows.Forms.Label
        $testTitle.Text = $statusText
        $testTitle.ForeColor = [System.Drawing.Color]::White
        $testTitle.Font = New-Object System.Drawing.Font(
            "Segoe UI",
            19,
            [System.Drawing.FontStyle]::Bold
        )
        $testTitle.AutoSize = $true

        $testSubtitle = New-Object System.Windows.Forms.Label
        $testSubtitle.Text = (
            $categoryText +
            "   |   Risco: " +
            $riskText +
            "   |   Origem: Teste interno"
        )
        $testSubtitle.ForeColor = [System.Drawing.Color]::White
        $testSubtitle.Font = New-Object System.Drawing.Font("Segoe UI",9)
        $testSubtitle.AutoSize = $true
        $testSubtitle.MaximumSize = New-Object System.Drawing.Size(650,0)

        [void]$headerFlow.Controls.Add($testTitle)
        [void]$headerFlow.Controls.Add($testSubtitle)
        $header.Controls.Add($headerFlow)

        $details = New-Object System.Windows.Forms.TableLayoutPanel
        $details.Dock = "Fill"
        $details.AutoSize = $true
        $details.AutoSizeMode = "GrowAndShrink"
        $details.ColumnCount = 1
        $details.Padding = New-Object System.Windows.Forms.Padding(22,16,22,12)
        [void]$details.ColumnStyles.Add(
            (New-Object System.Windows.Forms.ColumnStyle(
                [System.Windows.Forms.SizeType]::Percent,
                100
            ))
        )

        function Add-TestDetail {
            param(
                [string]$Label,
                [string]$Value,
                [bool]$Multiline = $false
            )

            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $Label
            $lbl.Font = New-Object System.Drawing.Font(
                "Segoe UI",
                9,
                [System.Drawing.FontStyle]::Bold
            )
            $lbl.AutoSize = $true
            $lbl.Margin = New-Object System.Windows.Forms.Padding(3,7,3,3)
            [void]$details.Controls.Add($lbl)

            $box = New-Object System.Windows.Forms.TextBox
            $box.Text = $Value
            $box.ReadOnly = $true
            $box.Dock = "Top"
            $box.Multiline = $Multiline
            if ($Multiline) {
                $box.Height = 64
                $box.ScrollBars = "Vertical"
            }
            $box.Margin = New-Object System.Windows.Forms.Padding(3,0,3,4)
            [void]$details.Controls.Add($box)
        }

        Add-TestDetail "Item detectado:" $nameText
        Add-TestDetail "Caminho:" $pathText
        Add-TestDetail "Motivo:" $reasonText $true
        Add-TestDetail "Ação:" "Nenhum arquivo real foi alterado. Este é apenas um teste visual." $true

        $notice = New-Object System.Windows.Forms.Label
        $notice.Text = "MODO DE TESTE — nenhuma proteção real foi acionada."
        $notice.Font = New-Object System.Drawing.Font(
            "Segoe UI",
            9,
            [System.Drawing.FontStyle]::Bold
        )
        $notice.AutoSize = $true
        $notice.Dock = "Top"
        $notice.Padding = New-Object System.Windows.Forms.Padding(22,4,22,4)

        $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttons.Dock = "Top"
        $buttons.AutoSize = $true
        $buttons.FlowDirection = "RightToLeft"
        $buttons.Padding = New-Object System.Windows.Forms.Padding(12,4,18,14)

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = "OK"
        $ok.Width = 120
        $ok.Height = 38
        $ok.Add_Click({
            $testForm.Close()
        })
        [void]$buttons.Controls.Add($ok)

        [void]$root.Controls.Add($header,0,0)
        [void]$root.Controls.Add($details,0,1)
        [void]$root.Controls.Add($notice,0,2)
        [void]$root.Controls.Add($buttons,0,3)

        try {
            [System.Media.SystemSounds]::Exclamation.Play()
        } catch {}

        [void]$testForm.ShowDialog($form)

        try {
            if ($testForm.Icon) {
                $testForm.Icon.Dispose()
            }
        } catch {}
    }

    function Invoke-PanelSafe {
        param(
            [string]$Context,
            [scriptblock]$Action
        )

        try {
            & $Action
            return $true
        }
        catch {
            Write-PanelError (
                $Context +
                ": " +
                $_.Exception.ToString() +
                [Environment]::NewLine +
                $_.ScriptStackTrace
            )

            return $false
        }
    }

    # ---------------- UI ----------------

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "SSD System Guard"
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "Sizable"
    $form.MinimizeBox = $true
    $form.MaximizeBox = $true
    $form.MinimumSize = New-Object System.Drawing.Size(380,420)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $working = [System.Windows.Forms.Screen]::FromPoint(
        [System.Windows.Forms.Cursor]::Position
    ).WorkingArea

    $form.Width = [Math]::Min(900,[Math]::Max(420,$working.Width - 80))
    $form.Height = [Math]::Min(820,[Math]::Max(500,$working.Height - 80))

    if (Test-Path -LiteralPath $IconPath) {
        try {
            $form.Icon = New-Object System.Drawing.Icon($IconPath)
        } catch {}
    }

    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Dock = "Fill"
    $scroll.AutoScroll = $true
    $form.Controls.Add($scroll)

    $content = New-Object System.Windows.Forms.TableLayoutPanel
    $content.Dock = "Top"
    $content.AutoSize = $true
    $content.AutoSizeMode = "GrowAndShrink"
    $content.ColumnCount = 1
    $content.RowCount = 0
    $content.Padding = New-Object System.Windows.Forms.Padding(18)
    $content.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$content.ColumnStyles.Add(
        (New-Object System.Windows.Forms.ColumnStyle(
            [System.Windows.Forms.SizeType]::Percent,
            100
        ))
    )
    $scroll.Controls.Add($content)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "SSD SYSTEM GUARD"
    $title.Font = New-Object System.Drawing.Font(
        "Segoe UI",
        19,
        [System.Drawing.FontStyle]::Bold
    )
    $title.AutoSize = $true
    $title.Dock = "Top"
    $title.Margin = New-Object System.Windows.Forms.Padding(3,3,3,5)

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = "Proteção do SSD C: para todas as contas locais deste computador."
    $desc.Font = New-Object System.Drawing.Font("Segoe UI",10)
    $desc.AutoSize = $true
    $desc.Dock = "Top"
    $desc.Margin = New-Object System.Windows.Forms.Padding(3,0,3,16)

    $status = New-Object System.Windows.Forms.Label
    $status.Font = New-Object System.Drawing.Font(
        "Segoe UI",
        12,
        [System.Drawing.FontStyle]::Bold
    )
    $status.AutoSize = $true
    $status.Dock = "Top"
    $status.Margin = New-Object System.Windows.Forms.Padding(3,0,3,7)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $summary.AutoSize = $true
    $summary.Dock = "Top"
    $summary.Margin = New-Object System.Windows.Forms.Padding(3,0,3,14)

    $checks = New-Object System.Windows.Forms.GroupBox
    $checks.Text = "Proteções"
    $checks.Dock = "Top"
    $checks.AutoSize = $true
    $checks.AutoSizeMode = "GrowAndShrink"
    $checks.Padding = New-Object System.Windows.Forms.Padding(12)
    $checks.Margin = New-Object System.Windows.Forms.Padding(3,0,3,14)

    $checkFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $checkFlow.Dock = "Top"
    $checkFlow.AutoSize = $true
    $checkFlow.AutoSizeMode = "GrowAndShrink"
    $checkFlow.FlowDirection = "TopDown"
    $checkFlow.WrapContents = $false
    $checkFlow.Padding = New-Object System.Windows.Forms.Padding(4)

    $cbDownloads = New-Object System.Windows.Forms.CheckBox
    $cbDownloads.Text = "Bloquear downloads de risco no C:"
    $cbDownloads.AutoSize = $true

    $cbSteam = New-Object System.Windows.Forms.CheckBox
    $cbSteam.Text = "Bloquear NOVOS jogos Steam baixados no C:"
    $cbSteam.AutoSize = $true

    $cbEpic = New-Object System.Windows.Forms.CheckBox
    $cbEpic.Text = "Bloquear NOVOS jogos Epic instalados no C:"
    $cbEpic.AutoSize = $true

    $cbPortable = New-Object System.Windows.Forms.CheckBox
    $cbPortable.Text = "Bloquear jogo portátil executado de Downloads"
    $cbPortable.AutoSize = $true

    $cbUnknown = New-Object System.Windows.Forms.CheckBox
    $cbUnknown.Text = "Alertar sobre aplicativos desconhecidos"
    $cbUnknown.AutoSize = $true

    $btnSave = New-ActionButton "Salvar proteções" 38

    foreach ($control in @(
        $cbDownloads,
        $cbSteam,
        $cbEpic,
        $cbPortable,
        $cbUnknown,
        $btnSave
    )) {
        $control.Margin = New-Object System.Windows.Forms.Padding(5,4,5,4)
        [void]$checkFlow.Controls.Add($control)
    }

    $checks.Controls.Add($checkFlow)

    $actions = New-Object System.Windows.Forms.FlowLayoutPanel
    $actions.Dock = "Top"
    $actions.AutoSize = $true
    $actions.AutoSizeMode = "GrowAndShrink"
    $actions.FlowDirection = "LeftToRight"
    $actions.WrapContents = $true
    $actions.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)

    $btnOn = New-ActionButton "ATIVAR / RETOMAR"
    $btnOff = New-ActionButton "DESATIVAR PROTEÇÃO"
    $btnPause = New-ActionButton "Pausar por 1 hora"
    $btnUnblock = New-ActionButton "Desbloquear pastas Steam/Epic"
    $btnTestRed = New-ActionButton "Testar alerta vermelho"
    $btnTestYellow = New-ActionButton "Testar alerta amarelo"
    $btnLog = New-ActionButton "Abrir log"
    $btnDetections = New-ActionButton "Abrir detecções"
    $btnQuarantine = New-ActionButton "Abrir quarentena"
    $btnBaseline = New-ActionButton "Refazer base Steam/Epic"
    $btnFolder = New-ActionButton "Abrir pasta do Guard"
    $btnExit = New-ActionButton "Fechar painel (proteção continua)"

    $actionButtons = @(
        $btnOn,
        $btnOff,
        $btnPause,
        $btnUnblock,
        $btnTestRed,
        $btnTestYellow,
        $btnLog,
        $btnDetections,
        $btnQuarantine,
        $btnBaseline,
        $btnFolder,
        $btnExit
    )

    foreach ($button in $actionButtons) {
        [void]$actions.Controls.Add($button)
    }

    $note = New-Object System.Windows.Forms.Label
    $note.Text = (
        "Steam e Epic podem abrir normalmente. O Guard bloqueia apenas " +
        "novas instalações/downloads no C:. Fechar esta janela NÃO encerra " +
        "a proteção; use DESATIVAR PROTEÇÃO para desligar o bloqueio."
    )
    $note.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $note.AutoSize = $true
    $note.Dock = "Top"
    $note.Margin = New-Object System.Windows.Forms.Padding(3,4,3,12)

    foreach ($control in @(
        $title,
        $desc,
        $status,
        $summary,
        $checks,
        $actions,
        $note
    )) {
        [void]$content.Controls.Add($control)
    }

    function Update-ResponsiveLayout {
        $clientWidth = [Math]::Max(320,$scroll.ClientSize.Width - 10)
        $content.Width = $clientWidth

        $inner = [Math]::Max(270,$clientWidth - 50)

        foreach ($label in @(
            $title,
            $desc,
            $status,
            $summary,
            $note
        )) {
            $label.MaximumSize = New-Object System.Drawing.Size -ArgumentList @(
                [int]$inner,
                [int]0
            )
        }

        foreach ($checkBox in @(
            $cbDownloads,
            $cbSteam,
            $cbEpic,
            $cbPortable,
            $cbUnknown
        )) {
            $checkBox.MaximumSize = New-Object System.Drawing.Size -ArgumentList @(
                [int][Math]::Max(220,$inner - 25),
                [int]0
            )
        }

        $columns = if ($inner -ge 720) { 2 } else { 1 }

        if ($columns -eq 2) {
            $buttonWidth = [Math]::Max(
                260,
                [int](($inner - 30) / 2)
            )
        }
        else {
            $buttonWidth = [Math]::Max(250,$inner - 12)
        }

        foreach ($button in $actionButtons) {
            $button.Width = $buttonWidth
        }

        $btnSave.Width = [Math]::Min(
            [Math]::Max(230,$inner - 20),
            420
        )
    }

    # ---------------- Events ----------------

    function Refresh-UI {
        $cfg = Get-Cfg

        if (-not $cfg) {
            $status.Text = "Status: erro ao ler configuração"
            $status.ForeColor = [System.Drawing.Color]::DarkRed
            return
        }

        $paused = $false

        if ($null -ne $cfg.PauseUntil) {
            $pauseText = [string]$cfg.PauseUntil

            if (-not [string]::IsNullOrWhiteSpace($pauseText)) {
                try {
                    $until = [datetime]::Parse($pauseText)

                    if ((Get-Date) -lt $until) {
                        $paused = $true
                    }
                } catch {
                    Write-PanelError (
                        "Refresh-UI PauseUntil: " +
                        $_.Exception.Message
                    )
                }
            }
        }

        $enabled = $false
        try {
            $enabled = [System.Convert]::ToBoolean($cfg.Enabled)
        } catch {}

        if (-not $enabled) {
            $status.Text = "Status: DESATIVADO"
            $status.ForeColor = [System.Drawing.Color]::DarkRed
        }
        elseif ($paused) {
            $status.Text = "Status: PAUSADO"
            $status.ForeColor = [System.Drawing.Color]::DarkOrange
        }
        else {
            $status.Text = "Status: ATIVO"
            $status.ForeColor = [System.Drawing.Color]::DarkGreen
        }

        $counts = Get-Counts

        $q = "sem quarentena externa"
        if ($null -ne $cfg.QuarantinePath) {
            $qCandidate = [string]$cfg.QuarantinePath

            if (-not [string]::IsNullOrWhiteSpace($qCandidate)) {
                $q = $qCandidate
            }
        }

        $summary.Text = (
            "Bloqueios registrados: {0}   |   Alertas: {1}   |   Quarentena: {2}" -f
            [int]$counts.Blocked,
            [int]$counts.Alerts,
            $q
        )

        try {
            $cbDownloads.Checked = [System.Convert]::ToBoolean(
                $cfg.DownloadProtection
            )
        } catch { $cbDownloads.Checked = $false }

        try {
            $cbSteam.Checked = [System.Convert]::ToBoolean(
                $cfg.SteamProtection
            )
        } catch { $cbSteam.Checked = $false }

        try {
            $cbEpic.Checked = [System.Convert]::ToBoolean(
                $cfg.EpicProtection
            )
        } catch { $cbEpic.Checked = $false }

        try {
            $cbPortable.Checked = [System.Convert]::ToBoolean(
                $cfg.PortableGameProtection
            )
        } catch { $cbPortable.Checked = $false }

        try {
            $cbUnknown.Checked = [System.Convert]::ToBoolean(
                $cfg.UnknownAppAlerts
            )
        } catch { $cbUnknown.Checked = $false }
    }

    $btnSave.Add_Click({
        $cfg = Get-Cfg

        if ($cfg) {
            $cfg.DownloadProtection = $cbDownloads.Checked
            $cfg.SteamProtection = $cbSteam.Checked
            $cfg.EpicProtection = $cbEpic.Checked
            $cfg.PortableGameProtection = $cbPortable.Checked
            $cfg.UnknownAppAlerts = $cbUnknown.Checked
            Save-Cfg $cfg
            Refresh-UI
        }
    })

    $btnOn.Add_Click({
        $cfg = Get-Cfg

        if ($cfg) {
            $cfg.Enabled = $true
            $cfg.PauseUntil = $null
            Save-Cfg $cfg
            Ensure-CoreRunning
            Refresh-UI
        }
    })

    $btnOff.Add_Click({
        $cfg = Get-Cfg

        if ($cfg) {
            $cfg.Enabled = $false
            $cfg.PauseUntil = $null
            Save-Cfg $cfg
            Unblock-All
            Refresh-UI
        }
    })

    $btnPause.Add_Click({
        $cfg = Get-Cfg

        if ($cfg) {
            $cfg.Enabled = $true
            $cfg.PauseUntil = (Get-Date).AddHours(1).ToString("o")
            Save-Cfg $cfg
            Refresh-UI
        }
    })

    $btnUnblock.Add_Click({
        Unblock-All

        [System.Windows.Forms.MessageBox]::Show(
            "Todos os bloqueios de pasta criados pelo Guard foram removidos.",
            "SSD System Guard",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    })

    $btnTestRed.Add_Click({
        Show-PanelTestAlert "Red"
    })

    $btnTestYellow.Add_Click({
        Show-PanelTestAlert "Yellow"
    })

    $btnLog.Add_Click({
        if (-not (Test-Path -LiteralPath $LogPath)) {
            "" | Set-Content -LiteralPath $LogPath
        }

        Start-Process notepad.exe -ArgumentList "`"$LogPath`""
    })

    $btnDetections.Add_Click({
        if (-not (Test-Path -LiteralPath $DetectionsPath)) {
            'Timestamp,Status,Category,Risk,Source,Name,Path,Reason,Action' |
                Set-Content -LiteralPath $DetectionsPath -Encoding UTF8
        }

        Start-Process notepad.exe -ArgumentList "`"$DetectionsPath`""
    })

    $btnQuarantine.Add_Click({
        $cfg = Get-Cfg

        if ($cfg -and $cfg.QuarantinePath) {
            New-Item `
                -ItemType Directory `
                -Path $cfg.QuarantinePath `
                -Force |
                Out-Null

            Start-Process explorer.exe -ArgumentList "`"$($cfg.QuarantinePath)`""
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Nenhum disco alternativo foi definido para quarentena.",
                "SSD System Guard",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $btnBaseline.Add_Click({
        $ans = [System.Windows.Forms.MessageBox]::Show(
            (
                "Isso fará o Guard considerar os jogos Steam/Epic que " +
                "existem AGORA no C: como permitidos. Continuar?"
            ),
            "Refazer base",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
            Unblock-All

            $state = Get-State

            if ($state) {
                $state.Initialized = $false
                $state.SteamBaselineAppIds = @()
                $state.EpicBaselineLocations = @()
                $state.BlockedPaths = @()
                $state.LastBaseline = $null
                Save-State $state

                [System.Windows.Forms.MessageBox]::Show(
                    "A base será recriada automaticamente pelo Guard.",
                    "SSD System Guard",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
    })

    $btnFolder.Add_Click({
        Start-Process explorer.exe -ArgumentList "`"$Base`""
    })

    $btnExit.Add_Click({
        $form.Close()
    })

    $scroll.Add_SizeChanged({
        [void](Invoke-PanelSafe "SizeChanged" {
            Update-ResponsiveLayout
        })
    })

    $form.Add_Shown({
        [void](Invoke-PanelSafe "Form.Shown" {
            Update-ResponsiveLayout
            Ensure-CoreRunning
            Refresh-UI
        })
    })

    $script:RefreshFailureCount = 0

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.Add_Tick({
        $ok = Invoke-PanelSafe "Timer.Refresh-UI" {
            Refresh-UI
        }

        if ($ok) {
            $script:RefreshFailureCount = 0
        }
        else {
            $script:RefreshFailureCount++

            # Evita um loop permanente caso uma máquina tenha um problema
            # específico de WinForms/PowerShell. O painel continua utilizável.
            if ($script:RefreshFailureCount -ge 3) {
                $timer.Stop()
                Write-PanelError (
                    "Timer de atualização automática desativado após " +
                    "3 falhas consecutivas."
                )
            }
        }
    })
    $timer.Start()

    [void]$form.ShowDialog()

    try {
        $timer.Stop()
        $timer.Dispose()
    } catch {}

    try {
        if ($form.Icon) {
            $form.Icon.Dispose()
        }
    } catch {}

    try {
        if ($script:PanelThreadExceptionHandler) {
            [System.Windows.Forms.Application]::remove_ThreadException(
                $script:PanelThreadExceptionHandler
            )
        }
    } catch {}

    exit 0
}
catch {
    $details = (
        $_.Exception.ToString() +
        [Environment]::NewLine +
        $_.ScriptStackTrace
    )

    Write-PanelError $details

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

        [System.Windows.Forms.MessageBox]::Show(
            (
                "O painel do SSD System Guard não conseguiu abrir." +
                [Environment]::NewLine +
                [Environment]::NewLine +
                "Um log foi criado em:" +
                [Environment]::NewLine +
                $PanelErrorLog
            ),
            "SSD System Guard",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {}

    exit 1
}
