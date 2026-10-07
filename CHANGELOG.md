# Changelog

## 1.1.1 — Multiusuário + interface adaptável + inicialização silenciosa

- Inclui as mudanças multiusuário da 1.1.0: instalação em ProgramData, atalho público, tarefa de logon por grupo e estado individual por SID.
- A tarefa de logon executa o próprio `SSDSystemGuard.exe --background` (aplicação sem console), não `powershell.exe`.
- `--panel` abre o painel avançado sem janela de console.
- Reorganização da interface principal por largura e escala DPI.
- Melhorias no painel e alertas para notebooks, escalas elevadas e 4K.
- Atualização do instalador para copiar a interface WinExe para ProgramData e proteger os arquivos executáveis.
- Mantém os recursos de bloqueio e a desinstalação multiusuário.

**Importante:** a proteção é iniciada por sessão após o logon. Não é um serviço de Windows antes do login; tarefas não elevam contas comuns a administradores.
