# Arquitetura

```text
SSDSystemGuard.exe
        |
        +-- instala/atualiza os recursos PowerShell auditáveis
        |
        +-- %LOCALAPPDATA%\SSDSystemGuardDefinitive
                |
                +-- GuardCore.ps1
                +-- Panel.ps1
                +-- config.json
                +-- state.json
                +-- guard.log
                +-- detections.csv
```

## Camadas

### Aplicativo .NET

Responsável por:

- experiência de instalação;
- solicitar UAC apenas quando necessário;
- abrir o painel;
- ativar, pausar e desativar;
- mostrar status básico;
- abrir logs/detecções;
- desinstalar.

### GuardCore.ps1

Responsável pelo monitoramento:

- FileSystemWatcher em Downloads;
- retries para arquivos ainda bloqueados pelo navegador;
- baseline Steam;
- baseline Epic;
- detecção de processos portáteis;
- quarentena;
- alertas;
- regras ACL localizadas.

### Tarefa agendada

Nome:

```text
SSD System Guard Definitivo
```

A tarefa inicia apenas o `GuardCore.ps1` no logon do usuário.

## Filosofia de segurança

O Guard não tenta virar um driver de kernel ou antivírus. A intenção é manter a solução compreensível, auditável e reversível.
