# Changelog

## 1.1.5

### HOTFIX crítico
- corrige regressão da v1.1.4 que podia impedir o `GuardCore.ps1` de iniciar no
  Windows PowerShell 5.1;
- restaura bloqueio de downloads e exibição dos avisos;
- mantém as otimizações da v1.1.4 após corrigir a sintaxe incompatível;
- adiciona heartbeat por usuário em `Data\heartbeat-<SID>.txt`;
- registra quantos watchers de Downloads foram iniciados;
- GitHub Actions agora valida os scripts com **Windows PowerShell 5.1 Desktop**,
  não somente PowerShell 7;
- adiciona uma verificação específica contra a regressão de member access
  quebrado após `.`.

