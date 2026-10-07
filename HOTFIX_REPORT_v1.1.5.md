# Relatório do hotfix v1.1.5

## Sintoma
Na v1.1.4 o monitor podia deixar de:
- bloquear downloads;
- gerar alertas;
- processar os timers de proteção.

## Causa encontrada
A função nova `Get-FileStamp` possuía member access dividido após um ponto:

```powershell
return (Get-Item ...).
    LastWriteTimeUtc.Ticks
```

Esse padrão foi introduzido durante a otimização de cache. O Guard executa seus
recursos com Windows PowerShell 5.1, portanto uma incompatibilidade de parsing
nesse arquivo impede todo o `GuardCore.ps1` de chegar à inicialização dos
watchers, timers e alertas.

Isso explica por que bloqueio e avisos pararam juntos.

## Por que o CI não impediu
O workflow chamava `scripts/validate-powershell.ps1` usando `shell: pwsh`.
Logo, o parser efetivamente usado era PowerShell 7, embora o nome da etapa
dissesse PowerShell 5.1.

## Correção
- member access reescrito sem quebra após o ponto;
- validação de scripts alterada para `shell: powershell`;
- script de validação falha caso não esteja no Windows PowerShell 5.1 Desktop;
- adicionado heartbeat para comprovar que o núcleo entrou no loop;
- `guard.log` registra `DOWNLOAD WATCHERS READY` e a quantidade de watchers.

## Diagnóstico após instalar
Arquivos úteis:

`C:\ProgramData\SSDSystemGuard\Data\guard.log`

`C:\ProgramData\SSDSystemGuard\Data\heartbeat-<SID>.txt`

Quando o Guard está saudável, o heartbeat deve ser atualizado aproximadamente
a cada 20 segundos.

