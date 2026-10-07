# Changelog

## 1.1.8

### CI / Release hotfix
- corrige falso positivo em `Validate project invariants`;
- o `quality-check.ps1` usava `-like` para procurar marcadores literais;
- `[pscustomobject]` era interpretado como expressão wildcard pelo PowerShell;
- verificações de presença passam a usar `String.Contains()`;
- restaura documentos históricos que apareceram como removidos no commit anterior;
- mantém integralmente as correções funcionais da v1.1.7.

### Importante
A falha vista no GitHub Actions da v1.1.7 não indicava erro de compilação do
painel. A validação falhou antes do estágio `Publish` por causa do próprio
script de qualidade.

