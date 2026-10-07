# Changelog

## 1.1.9

### CI / quality-check hotfix
- corrige falso positivo `GuardCore.ps1 voltou a usar StopFlag`;
- o validador usava `Contains("$StopFlag")`;
- dentro do próprio `quality-check.ps1`, `$StopFlag` não existe e era expandido
  para string vazia;
- `String.Contains("")` retorna verdadeiro, fazendo o CI falhar sempre;
- a busca agora usa o literal `'$StopFlag'`;
- os marcadores restantes de auto-recuperação também passam a usar
  `String.Contains()` em vez de padrões `-like`;
- adicionados self-tests do próprio validador para:
  - colchetes, como `[pscustomobject]`;
  - cifrão/variável literal, como `$StopFlag`;
  - ausência de marcadores inexistentes;
- mantém integralmente as correções funcionais da v1.1.7/v1.1.8.

### Importante
O erro visto no Build da v1.1.8 era novamente do script de validação, e não
uma confirmação de que o `GuardCore.ps1` havia voltado a usar `StopFlag`.

