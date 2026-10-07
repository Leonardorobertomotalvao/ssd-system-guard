# Changelog

## 1.2.1

### Correção estrutural definitiva do painel
- remove o `Panel.ps1` do runtime;
- `--panel` executa somente `AdvancedPanelForm` em C#/.NET 8;
- `BackgroundHost` não possui mais `RunPanel`;
- `ResourceInstaller` não extrai `Panel.ps1`;
- o `.csproj` não usa mais wildcard `Resources\*.ps1`;
- `GuardManager.OpenPanel()` abre o EXE que o usuário está executando no momento,
  impedindo que um EXE novo chame um host instalado antigo;
- durante a atualização, o instalador encerra processos antigos que estejam
  rodando `Panel.ps1`;
- o instalador remove `C:\ProgramData\SSDSystemGuard\Panel.ps1`;
- o painel exibe claramente `Painel: .NET 8 nativo`;
- alertas de teste também são nativos .NET;
- PowerShell permanece apenas no núcleo, comandos de ACL e instalação.

### Diagnóstico que motivou a mudança
O stack trace real mostrou `PSEnumerableBinder` e `Timer.OnTick`, provando que o
erro recorrente vinha da interface hospedada no Windows PowerShell 5.1.
