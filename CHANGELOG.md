# Changelog

## 1.0.3

- corrigido erro de instalação `0xC000013A / -1073741510`;
- instalador elevado agora roda oculto e com `-STA`;
- instalação grava `install.result.json` e `install.log`;
- aplicativo valida o resultado real da instalação antes de exibir erro;
- painel não é mais aberto automaticamente durante a instalação;
- processo de upgrade encerra somente processos específicos do Guard;
- mantidos o novo ícone e o branding sem “Definitivo”.

## 1.0.2

- novo ícone aplicado também ao atalho, painel e ícone da bandeja;
- removido o nome antigo “Definitivo” da interface e da instalação;
- pasta local padronizada para `%LOCALAPPDATA%\SSDSystemGuard`;
- tarefa agendada padronizada para `SSD System Guard`;
- atualização limpa remove atalhos/tarefas legados e desfaz bloqueios registrados.

## 1.0.0

Primeira versão pública do aplicativo.

- interface WinForms .NET 8;
- instalador/atualizador dentro do aplicativo;
- motor de proteção PowerShell auditável e embutido;
- download protection;
- Steam/Epic baseline;
- detecção de jogo portátil;
- alerta de aplicativo desconhecido;
- logs, CSV, pausa e desinstalação segura;
- GitHub Actions para Build e Release.
