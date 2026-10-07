# SSD System Guard 1.1.0 — modo multiusuário

A instalação agora é local ao computador. Os arquivos protegidos ficam em `C:\ProgramData\SSDSystemGuard` e a tarefa `SSD System Guard` é disparada quando qualquer usuário local entra no Windows.

Cada usuário recebe sua própria instância interativa e seu próprio estado (`state-<SID>.json`). O arquivo de configuração, log e histórico de detecções são compartilhados no computador.

Para remover a proteção de todas as contas, use o botão **DESINSTALAR DO COMPUTADOR** ou `UNINSTALL_SSD_SYSTEM_GUARD.bat`.
