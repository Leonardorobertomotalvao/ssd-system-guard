# Changelog

## 1.1.4

### Desempenho
- o host `.NET` do modo `--background` agora inicia o PowerShell e encerra imediatamente;
  antes ele permanecia residente durante toda a sessão ao lado do `powershell.exe`;
- cache de `config.json` e `state-<SID>.json`, reduzindo leitura e conversão JSON repetidas;
- cache do caminho e das bibliotecas Steam;
- substituição da varredura `Get-CimInstance Win32_Process` por snapshot via
  `System.Diagnostics.Process`, evitando consultas WMI periódicas;
- raízes de jogos/Downloads são calculadas uma vez por ciclo de processo;
- prioridade do núcleo em segundo plano definida como `BelowNormal`;
- timers ajustados para 1,5 s / 3 s / 5 s, mantendo FileSystemWatcher para downloads;
- manutenção do `guard.log` quando ultrapassa aproximadamente 2 MB;
- atualização visual da janela principal reduzida de 3 s para 5 s;
- configurações de GC/tiering voltadas a aplicação desktop leve.

### Estabilidade
- abertura do painel usa janela normal enquanto somente o monitor fica oculto;
- `quality-check.ps1` valida arquivos críticos, versão e funções essenciais;
- Build e Release executam a validação adicional antes de publicar;
- preservados os fixes de painel, DPI, multiusuário, alerta repetido da Steam e
  testes vermelho/amarelo diretos.

