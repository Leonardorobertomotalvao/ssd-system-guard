# SSD System Guard

Aplicativo open source para Windows que ajuda a manter **downloads de risco e novas instalações de jogos fora do SSD do sistema (`C:`)**.

> **Importante:** este projeto não é antivírus e não substitui Microsoft Defender, EDR ou controle parental. O objetivo é evitar que usuários do mesmo PC encham o SSD do sistema com jogos, instaladores e pacotes baixados no local errado.

## O que ele faz

- monitora a pasta **Downloads** no `C:`;
- tenta remover arquivos parciais de downloads de risco (`.crdownload`, `.part`, `.download`);
- move arquivos finais bloqueados para uma **quarentena em outro disco**, quando disponível;
- permite abrir **Steam e Epic Games normalmente**;
- cria uma base dos jogos Steam/Epic que já existiam;
- bloqueia uma **nova** tentativa de download/instalação de jogo no `C:`;
- detecta jogo portátil executado diretamente de Downloads;
- alerta sobre executáveis desconhecidos;
- ignora `C:\Windows` antes das heurísticas para reduzir falsos positivos;
- mantém logs e uma tabela CSV de detecções;
- pode ser pausado, desativado e desinstalado com reversão das regras criadas pelo próprio Guard.

## Aplicativo

A interface principal é um aplicativo WinForms em **.NET 8**.

O motor de proteção usado nesta versão é o PowerShell que foi testado durante o desenvolvimento. Os scripts ficam **embutidos no EXE** e são instalados em:

```text
%LOCALAPPDATA%\SSDSystemGuardDefinitive
```

Isso deixa todo o código auditável no repositório e evita esconder comandos executados no computador.

## Requisitos

- Windows 10 ou Windows 11 64-bit;
- conta com permissão para aceitar UAC durante instalação/desinstalação;
- Windows PowerShell 5.1, incluído no Windows;
- aproximadamente 100 MB para o EXE self-contained do .NET, dependendo da versão do runtime publicada.

## Como baixar

Abra **Releases** no GitHub e baixe:

```text
SSDSystemGuard.exe
```

O arquivo `SHA256.txt` publicado junto permite conferir a integridade.

## Desenvolvimento local

Instale o [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) e execute:

```powershell
.\scripts\build.ps1
```

O executável será gerado em:

```text
dist\win-x64\SSDSystemGuard.exe
```

## GitHub Actions

O repositório já possui:

- `Build`: compila cada push/PR em Windows;
- `Release`: ao criar uma tag `v*`, gera o EXE, SHA256 e cria uma GitHub Release.

Exemplo:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

## Segurança

O programa foi projetado para:

- não alterar permissões do `C:\` inteiro;
- não bloquear componentes de `C:\Windows`;
- não encerrar Steam/Epic apenas por estarem abertos;
- registrar pastas às quais aplicou regras para poder revertê-las;
- manter o bloqueio focado em **novos downloads/instalações**;
- funcionar localmente, sem telemetria ou envio de dados.

Veja [`SECURITY.md`](SECURITY.md) antes de publicar builds para outras pessoas.

## Limitações

Nenhum monitor em espaço de usuário consegue garantir que **zero bytes** sejam transferidos antes da detecção. O Guard protege principalmente o **armazenamento/instalação no `C:`**.

Para impedir o primeiro byte da rede seria necessário integrar com cada navegador/launcher ou usar um driver/filtro de rede, abordagem propositalmente evitada nesta versão.

## Privacidade

O SSD System Guard não possui telemetria e não envia a lista de arquivos, processos ou jogos para servidores externos. Logs ficam no próprio computador.

## Licença

MIT. Consulte [`LICENSE`](LICENSE).
