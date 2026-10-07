# SSD System Guard — Relatório de desenvolvimento até v1.1.4

## 1. Objetivo do projeto

O SSD System Guard foi desenvolvido para impedir que novos jogos, downloads de
risco e executáveis de jogos sejam gravados ou executados indevidamente no SSD
de sistema (normalmente C:), mantendo launchers conhecidos utilizáveis e
permitindo que o usuário escolha outro SSD/HD para jogos.

O projeto evoluiu de um conjunto de scripts PowerShell para um aplicativo
WinForms em .NET 8 que instala e gerencia o mecanismo de proteção.

---

## 2. Arquitetura atual

- Aplicativo principal: C# / .NET 8 WinForms.
- Núcleo de proteção: Windows PowerShell 5.1.
- Instalação compartilhada: `C:\ProgramData\SSDSystemGuard`.
- Dados compartilhados: `C:\ProgramData\SSDSystemGuard\Data`.
- Estado individual por conta: `state-<SID>.json`.
- Inicialização: tarefa agendada no logon das contas locais.
- Painel avançado: PowerShell WinForms aberto somente quando solicitado.
- Monitor em segundo plano: PowerShell oculto.
- Releases: GitHub Actions gera `SSDSystemGuard.exe`, SHA256 e desinstalador.

---

## 3. Histórico das principais alterações

### Primeira geração
- monitoramento da pasta Downloads;
- detecção de extensões de risco e arquivos parciais;
- quarentena em outro disco quando disponível;
- proteção Steam e Epic;
- detecção de executáveis/jogos portáteis iniciados em Downloads;
- whitelist de launchers conhecidos;
- painel, tray icon, log e CSV de detecções;
- ACLs de bloqueio registradas no estado para remoção segura.

### v1.0.1
- integração do ícone próprio do SSD System Guard no aplicativo.

### v1.0.2
- padronização do nome para `SSD System Guard`;
- remoção da marca antiga "Definitivo" da interface;
- atalho e ícone próprios;
- compatibilidade de limpeza com instalações antigas.

### v1.0.3
- correção do instalador que podia retornar `0xC000013A`;
- `install.log` e `install.result.json`;
- instalador mais silencioso;
- confirmação de sucesso por arquivo de resultado.

### v1.0.4
- desinstalador independente em `.bat`;
- remoção de tarefas, atalhos, instalação e ACLs registradas;
- opção separada para remover quarentena;
- desinstalador incluído nas Releases.

### v1.0.5
- opção de iniciar o Guard com o Windows;
- preservação da preferência durante atualização;
- gerenciamento por tarefa agendada.

### v1.0.6
- correção do popup repetitivo da Steam;
- comparação correta do caminho já bloqueado;
- confirmação de que a ACL de negação ainda existe;
- limpeza de entradas de estado obsoletas.

### v1.0.7
- novo alerta somente quando a Steam faz uma tentativa real de `Retomar`;
- leitura recente de `Steam\logs\content_log.txt`;
- mesma tentativa não gera várias janelas.

### v1.1.0
- desenho da instalação multiusuário;
- instalação migrada para `ProgramData`;
- estado separado por SID;
- atalho público;
- melhorias iniciais para notebook e janela pequena.

A base v1.1.0 foi posteriormente incorporada ao pacote consolidado v1.1.1.

### v1.1.1
- consolidação multiusuário;
- inicialização pelo próprio EXE;
- remoção da janela preta de console no logon;
- interface principal responsiva;
- suporte aprimorado a DPI/4K/notebooks;
- rolagem, minimizar, maximizar e redimensionar;
- validação de sintaxe PowerShell no GitHub Actions.

### v1.1.2
- correção de `ABRIR PAINEL AVANÇADO`;
- separação entre host oculto do monitor e host visual do painel;
- painel reconstruído com layout responsivo;
- `panel_errors.log` e `panel_host_errors.log`.

### v1.1.3
- correção dos botões de teste vermelho e amarelo;
- alertas de teste passaram a abrir diretamente pelo painel;
- testes não dependem do GuardCore nem de arquivos `.flag`;
- testes não alteram arquivos ou ACLs reais.

### v1.1.4
- host .NET do monitor deixa de ficar residente;
- cache de configuração/estado;
- cache da Steam;
- retirada da consulta WMI periódica de processos;
- snapshot de processos via `System.Diagnostics.Process`;
- prioridade `BelowNormal`;
- intervalos de verificação ajustados;
- rotação simples do `guard.log`;
- checagem automática de invariantes do projeto antes do Build/Release.

---

## 4. Proteções atuais

### Downloads
O Guard usa `FileSystemWatcher`, portanto a detecção principal é orientada a
evento e não depende de ficar varrendo todo o disco.

São considerados de risco, entre outros:
`.exe`, `.msi`, `.iso`, `.zip`, `.rar`, `.7z`, `.apk`, `.torrent`,
`.bat`, `.cmd`, `.ps1` e `.vbs`.

Também são tratados arquivos parciais como:
`.crdownload`, `.part`, `.download` e `.tmp`.

### Steam
- Steam pode abrir normalmente.
- Jogos que já existiam durante a criação da baseline são permitidos.
- Novo AppID em `steamapps\downloading` no C: pode ser bloqueado.
- O Guard esvazia a pasta nova e aplica ACL de negação ao usuário atual.
- A mesma pasta bloqueada não deve gerar popup periódico.
- Uma nova tentativa real de Retomar pode gerar um novo alerta.

### Epic Games
- Epic Games Launcher continua permitido.
- Instalações existentes entram na baseline.
- Nova estrutura `.egstore` no C: pode ser bloqueada.

### Jogos portáteis / executáveis
- executáveis em áreas protegidas são classificados;
- launchers oficiais conhecidos são ignorados;
- caminhos oficiais do Windows são ignorados;
- jogos da baseline Steam/Epic são ignorados;
- executável com forte padrão de jogo em Downloads pode ser encerrado;
- aplicativo desconhecido pode gerar alerta amarelo.

---

## 5. Multiusuário

A instalação atual é do computador, não somente do usuário que clicou em
Instalar.

Os arquivos ficam em:

`C:\ProgramData\SSDSystemGuard`

Cada sessão usa seu próprio estado por SID para evitar misturar baseline e
bloqueios entre usuários.

A proteção é iniciada no logon das contas locais por tarefa agendada.

Importante: não é um serviço kernel nem um serviço anterior ao logon. O monitor
começa na sessão depois que o usuário entra no Windows.

---

## 6. Interface

Foram adicionados:

- AutoScale/DPI;
- suporte a `PerMonitorV2` no executável;
- layout adaptativo;
- uma ou duas colunas conforme largura;
- rolagem;
- minimizar/maximizar;
- tamanho mínimo;
- painel responsivo;
- alertas redimensionáveis;
- melhor funcionamento em notebook, 1080p, 1440p e 4K.

---

## 7. Otimizações da v1.1.4

A v1.1.4 concentra as maiores otimizações de execução até agora.

### Processo a menos
Anteriormente:

`SSDSystemGuard.exe --background` -> `powershell.exe GuardCore.ps1`

O EXE ficava esperando o PowerShell durante toda a sessão.

Agora ele inicia o processo oculto e encerra imediatamente. Na operação normal
fica somente o processo responsável pela proteção.

### Menos acesso a disco
`config.json` e `state-<SID>.json` agora são mantidos em cache e só são lidos
novamente quando o arquivo realmente muda.

### Sem WMI periódico
A leitura de processos não usa mais `Get-CimInstance Win32_Process` a cada
ciclo. A v1.1.4 usa `System.Diagnostics.Process`.

### Frequências
- eventos/pendências: ~1,5 s;
- Steam/Epic: ~3 s;
- processos portáteis: ~5 s.

Downloads continuam usando FileSystemWatcher para reação orientada a evento.

### Prioridade
O núcleo solicita prioridade `BelowNormal`, ajudando Windows/jogos a terem
preferência por CPU.

---

## 8. Controles contra regressões

O projeto possui:

- Git;
- branch de backup usada durante rebase da v1.1.1;
- GitHub Actions;
- validação de sintaxe dos scripts PowerShell;
- compilação Release em Windows;
- SHA256 do executável;
- `quality-check.ps1` para verificar:
  - arquivos obrigatórios;
  - consistência da versão;
  - funções críticas Steam/Epic;
  - proteção de processos;
  - testes vermelho/amarelo;
  - host de background e painel.

Logs de diagnóstico incluem:
- `install.log`;
- `startup_errors.log`;
- `panel_errors.log`;
- `panel_host_errors.log`;
- `guard.log`;
- `detections.csv`.

---

## 9. Limitações conhecidas

Não é tecnicamente correto prometer consumo "zero" ou ausência total de bugs.

O Guard ainda mantém um processo PowerShell em segundo plano porque a lógica de
proteção atual está implementada nele. A v1.1.4 reduz processos extras, I/O e
consultas pesadas, mas o consumo exato de RAM varia conforme Windows, versão do
PowerShell, quantidade de processos, Steam/Epic e quantidade de pastas
monitoradas.

Uma futura versão 2.x poderia portar o GuardCore integralmente para C# e remover
o PowerShell residente. Essa seria a mudança com maior potencial de redução de
RAM, mas também é uma reescrita grande e deve ser feita com testes extensos para
não perder proteções existentes.

---

## 10. Checklist recomendado antes de cada Release

1. Build e Release verdes no GitHub Actions.
2. Instalação limpa.
3. Atualização sobre versão anterior.
4. Reiniciar Windows e confirmar ausência de console preto.
5. Abrir painel.
6. Testar alerta vermelho.
7. Testar alerta amarelo.
8. Steam: iniciar novo download no C:.
9. Steam: clicar Retomar e conferir apenas um alerta por tentativa.
10. Epic: testar nova instalação em pasta do C:.
11. Testar download de arquivo de risco.
12. Testar executável desconhecido em Downloads.
13. Testar Pause/Retomar.
14. Testar Desativar e remoção das ACLs.
15. Testar segunda conta Windows.
16. Testar 100%, 150% e 200% de escala.
17. Testar notebook/tela pequena.
18. Testar desinstalador.
19. Conferir logs por erros inesperados.
20. Medir RAM/CPU após 5 minutos em idle e durante download.

