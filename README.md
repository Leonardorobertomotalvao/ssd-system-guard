# SSD System Guard

**Proteção local para manter novos downloads, instaladores e jogos fora do SSD do sistema (`C:`).**

> **Atualização v1.1.8:** correção do pipeline de validação/Release, mantendo as correções do painel da v1.1.7 e a proteção contínua da v1.1.6.

## Sobre o projeto

O **SSD System Guard** é um aplicativo open source para Windows criado para ajudar a evitar que o SSD do sistema seja preenchido por novos jogos, instaladores e arquivos baixados no local errado.

O objetivo é permitir que launchers como **Steam** e **Epic Games** continuem funcionando normalmente, enquanto novas instalações e downloads direcionados ao `C:` podem ser detectados e bloqueados.

> **Importante:** o SSD System Guard não é antivírus, EDR, firewall ou controle parental. Ele não substitui o Microsoft Defender nem outras soluções de segurança.

---

## Principais recursos

- monitora pastas de **Downloads** protegidas;
- detecta arquivos de risco e arquivos parciais de download;
- pode mover arquivos bloqueados para uma **quarentena em outro disco**;
- permite abrir Steam e Epic Games normalmente;
- cria uma base dos jogos Steam/Epic que já existiam;
- bloqueia novas tentativas de instalação/download de jogos no `C:`;
- detecta executáveis e jogos portáteis iniciados diretamente de Downloads;
- pode alertar sobre aplicativos desconhecidos;
- ignora caminhos oficiais do Windows antes das heurísticas;
- mantém logs e histórico em CSV;
- possui painel avançado;
- funciona em múltiplas contas locais do Windows;
- possui interface adaptável para notebook, Full HD, 1440p, 4K e DPI alto;
- inicia silenciosamente em segundo plano;
- possui recuperação automática caso o monitor seja encerrado inesperadamente;
- pode ser desativado e desinstalado pelo próprio aplicativo.

---

## Proteção contínua e recuperação automática — v1.1.6

A partir da **v1.1.6**, a interface deixa de ser o processo responsável pela proteção.

Isso significa que:

- fechar a janela principal **não desativa** o Guard;
- fechar o painel avançado **não encerra** a proteção;
- a antiga opção **Encerrar nesta conta** foi removida;
- o menu da bandeja não permite mais desligar diretamente o monitor;
- se o processo de proteção terminar inesperadamente, o **Agendador de Tarefas do Windows** tenta iniciá-lo novamente;
- múltiplas instâncias do monitor são evitadas;
- a forma normal de interromper os bloqueios é usar **Desativar Proteção** dentro do aplicativo;
- para remover completamente o sistema, use **Desinstalar do computador**.

A recuperação automática foi criada para evitar que a proteção fique permanentemente desligada após um encerramento acidental do processo.

### Limite administrativo

Um administrador do Windows ainda pode parar a tarefa agendada, alterar permissões ou desinstalar o aplicativo.

O SSD System Guard utiliza mecanismos normais do Windows e não tenta impedir o administrador do computador de controlar o próprio sistema.

---

## Múltiplas contas

A instalação atual é feita para o computador e utiliza:

```text
C:\ProgramData\SSDSystemGuard
```

A proteção pode iniciar após o logon de diferentes contas locais.

O estado individual de cada usuário é separado por SID para evitar misturar informações de sessão, baseline e bloqueios entre contas.

Também é criado um atalho público para facilitar o acesso ao aplicativo em outras contas do computador.

> O monitor inicia após o logon do usuário. O SSD System Guard não é um driver nem um serviço de proteção anterior ao login do Windows.

---

## Steam

O Guard foi desenvolvido para não bloquear a Steam simplesmente por ela estar aberta.

Com a proteção ativa:

1. jogos já existentes podem entrar na baseline;
2. uma nova tentativa de download no `C:` pode ser detectada;
3. o novo diretório pode receber uma regra de bloqueio;
4. a Steam continua aberta;
5. o usuário pode escolher outra biblioteca em outro SSD ou HD.

O Guard também possui tratamento para evitar que o mesmo caminho bloqueado fique gerando popup continuamente.

Quando uma **nova tentativa real de Retomar** é detectada, um novo aviso pode ser exibido.

---

## Epic Games

O Epic Games Launcher também pode continuar aberto normalmente.

Instalações existentes podem entrar na baseline, enquanto novas estruturas de instalação no `C:` podem ser detectadas e bloqueadas.

---

## Downloads e executáveis

O monitor trabalha com extensões consideradas de risco, incluindo exemplos como:

```text
.exe
.msi
.iso
.zip
.rar
.7z
.apk
.torrent
.bat
.cmd
.ps1
.vbs
```

Também pode acompanhar arquivos parciais, como:

```text
.crdownload
.part
.download
.tmp
```

Downloads utilizam monitoramento orientado a eventos com `FileSystemWatcher`, evitando a necessidade de varrer constantemente todo o disco.

---

## Interface

A interface foi ajustada para diferentes tamanhos e escalas de tela.

Melhorias recentes incluem:

- DPI PerMonitorV2 no aplicativo principal;
- janelas redimensionáveis;
- minimizar e maximizar;
- rolagem em telas pequenas;
- reorganização de botões conforme a largura disponível;
- suporte melhor a notebooks;
- melhorias para 100%, 125%, 150%, 175% e 200% de escala;
- correções para monitores 4K;
- painel avançado responsivo;
- alertas vermelho e amarelo responsivos.

---

## Desempenho

As versões recentes também receberam otimizações para diminuir o impacto em segundo plano.

Entre as mudanças:

- redução de processos auxiliares residentes;
- cache de configuração e estado;
- cache de informações da Steam;
- redução de leituras repetidas de disco;
- remoção de consultas WMI periódicas para a varredura normal de processos;
- uso de `System.Diagnostics.Process`;
- prioridade de execução de fundo reduzida;
- intervalos de verificação ajustados;
- manutenção do arquivo de log para evitar crescimento indefinido.

O consumo exato de RAM e CPU varia de acordo com a versão do Windows, PowerShell, quantidade de processos e pastas monitoradas.

---

## Aplicativo

A interface principal é desenvolvida em **C# / .NET 8 WinForms**.

O núcleo atual de proteção utiliza **Windows PowerShell 5.1**.

Os scripts ficam incorporados ao executável e são instalados localmente no computador, mantendo o projeto auditável no repositório.

Modos internos do executável:

```text
--background
```

Inicia o monitor em segundo plano.

```text
--panel
```

Abre o painel avançado.

---

## Diagnóstico

Os arquivos de diagnóstico ficam em:

```text
C:\ProgramData\SSDSystemGuard\Data
```

Arquivos úteis podem incluir:

```text
guard.log
detections.csv
install.log
startup_errors.log
panel_errors.log
panel_host_errors.log
heartbeat-<SID>.txt
```

Quando o monitor está saudável, o arquivo `heartbeat-<SID>.txt` é atualizado periodicamente.

O `guard.log` também pode registrar a inicialização dos watchers de Downloads.

---

## Testes internos

O painel possui:

- **Testar alerta vermelho**
- **Testar alerta amarelo**

Esses testes são visuais e não precisam bloquear ou alterar arquivos reais.

---

## Requisitos

- Windows 10 ou Windows 11 64-bit;
- Windows PowerShell 5.1;
- permissão para aceitar UAC durante instalação/desinstalação;
- `.NET 8` é publicado de forma self-contained no executável;
- espaço suficiente para os arquivos do aplicativo e logs.

---

## Como baixar

Abra a seção **Releases** deste repositório e baixe:

```text
SSDSystemGuard.exe
```

A Release também pode incluir:

```text
SHA256.txt
UNINSTALL_SSD_SYSTEM_GUARD.bat
```

O arquivo `SHA256.txt` pode ser usado para conferir a integridade do executável baixado.

---

## Desenvolvimento local

Com o **.NET 8 SDK** instalado:

```powershell
.\scripts\build.ps1
```

O executável é publicado em:

```text
dist\win-x64\SSDSystemGuard.exe
```

---

## GitHub Actions

O repositório possui automações para Build e Release.

Antes da publicação, o projeto também executa verificações de estabilidade, incluindo:

- compilação Release;
- validação de arquivos obrigatórios;
- consistência de versão;
- funções críticas do Guard;
- validação dos recursos PowerShell;
- validação real com **Windows PowerShell 5.1 Desktop**;
- geração do SHA256.

Exemplo de publicação:

```powershell
git tag v1.1.6
git push origin v1.1.6
```

---

## Histórico recente

### v1.1.8

- corrige falso positivo no `quality-check.ps1`;
- validações de marcadores agora usam comparação literal;
- evita que textos com `[` e `]`, como `[pscustomobject]`, sejam interpretados como wildcards;
- restaura documentação histórica removida acidentalmente;
- mantém todas as correções funcionais da v1.1.7.

### v1.1.7

- corrige popup repetitivo do Microsoft .NET Framework;
- adiciona proteção de eventos WinForms;
- captura exceções da interface em `panel_errors.log`;
- reduz a frequência de atualização visual do painel.

### v1.1.6

- proteção contínua;
- recuperação automática do monitor;
- fechar a interface não desliga mais o Guard;
- remoção do encerramento direto pelo painel/tray;
- tarefa agendada com recuperação;
- melhorias na desinstalação.

### v1.1.5

- hotfix do bloqueio de downloads;
- correção de compatibilidade com Windows PowerShell 5.1;
- heartbeat de diagnóstico;
- validação correta de PowerShell 5.1 no CI.

### v1.1.4

- otimizações de CPU, RAM e I/O;
- cache de configuração/estado;
- otimizações da Steam;
- redução de consultas pesadas.

### v1.1.3

- correção dos testes de alerta vermelho e amarelo.

### v1.1.2

- correção da abertura do painel avançado;
- logs específicos do painel.

### v1.1.1

- interface responsiva;
- notebook/4K/DPI;
- inicialização silenciosa;
- consolidação do suporte multiusuário.

---

## Segurança

O projeto procura evitar alterações amplas e desnecessárias no Windows.

Princípios utilizados:

- não aplicar bloqueio no `C:\` inteiro;
- ignorar componentes oficiais de `C:\Windows`;
- não bloquear Steam/Epic apenas por estarem abertos;
- registrar caminhos nos quais o Guard aplicou regras;
- permitir reversão das regras criadas pelo próprio Guard;
- manter a proteção focada em novos downloads e instalações;
- não utilizar telemetria.

Consulte também:

[`SECURITY.md`](SECURITY.md)

---

## Limitações

Nenhum monitor em espaço de usuário consegue garantir que absolutamente zero bytes sejam transferidos antes da detecção.

O foco do SSD System Guard é impedir ou reduzir o armazenamento e a instalação indevida de novos conteúdos no SSD do sistema.

O projeto também não promete ausência total de bugs. Novas versões são testadas e recebem verificações automáticas para reduzir regressões.

---

## Privacidade

O SSD System Guard não envia a lista de arquivos, processos ou jogos para servidores externos.

Logs e configurações permanecem localmente no computador.

---

## Licença

MIT.

Consulte:

[`LICENSE`](LICENSE)
