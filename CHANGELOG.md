# Changelog

## 1.2.3

### Correção da causa restante do popup .NET/PowerShell
O stack trace real mostrou `PSEnumerableBinder`,
`PSToObjectArrayBinder` e `System.Windows.Forms.Timer.OnTick`.

O painel já era nativo .NET 8, porém o `GuardCore.ps1` continuava usando
WinForms Timer para executar callbacks PowerShell.

Também havia em `Get-ProcessSnapshot` um retorno de
`System.Collections.Generic.List[object]` por `@($result)`, construção que pode
acionar o binder dinâmico do Windows PowerShell 5.1.

### Alterações
- removidos todos os WinForms Timers do GuardCore;
- removidos callbacks `.Add_Tick({...})`;
- scheduler periódico agora é síncrono no thread principal;
- `Application.DoEvents()` mantém apenas o tray responsivo;
- cada etapa periódica possui `try/catch` independente;
- `Get-ProcessSnapshot` agora retorna `$result.ToArray()`;
- demais retornos `$result` não usam mais `@($result)`;
- CI impede o retorno dessas construções;
- painel continua 100% nativo .NET 8.
