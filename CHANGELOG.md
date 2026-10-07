# Changelog

## 1.1.6

- fechar janela principal ou painel não encerra a proteção;
- removido "Encerrar nesta conta";
- menu da bandeja não permite mais pausar/encerrar o Guard;
- removido mecanismo `stop-<SID>.flag`;
- tarefa agendada passa a supervisionar o Guard por um launcher invisível;
- `RestartCount 999` e `RestartInterval 1 minuto`;
- `MultipleInstances IgnoreNew`;
- prioridade 8 para tarefa de fundo;
- desinstalador remove a tarefa antes de encerrar os processos;
- proteção desativada pelo painel continua sendo a forma normal de desligar o bloqueio.
