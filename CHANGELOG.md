# Changelog

## 1.2.0

### Painel avançado reescrito em C#/.NET 8
- remove o painel WinForms em PowerShell do runtime;
- `--panel` agora abre `AdvancedPanelForm`, compilado junto com o executável;
- elimina a dependência do `PSEnumerableBinder`/binder dinâmico do Windows
  PowerShell para a interface;
- corrige de forma estrutural o popup repetitivo:
  `Microsoft .NET Framework - Os tipos de argumento não correspondem`;
- alertas vermelho e amarelo agora são janelas nativas .NET 8;
- layout continua responsivo para notebook, 4K e DPI alto;
- atualização visual continua em 5 segundos;
- erros do painel nativo são gravados em `native_panel_errors.log`.

### PowerShell permanece somente onde faz sentido
- `GuardCore.ps1`: monitor/proteção em segundo plano;
- `GuardCommands.ps1`: desbloqueio de ACL e reconstrução de baseline;
- `Install.ps1` / `Uninstall.ps1`: instalação e remoção.

### Migração
- o instalador remove `C:\ProgramData\SSDSystemGuard\Panel.ps1`;
- o executável deixa de embutir o antigo Panel.ps1;
- o painel avançado passa a fazer parte diretamente do `SSDSystemGuard.exe`.

