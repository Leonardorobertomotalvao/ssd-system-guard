# Contributing

Contribuições são bem-vindas.

## Antes de enviar um PR

- não adicione telemetria;
- não adicione download automático de executáveis;
- não desative Defender, SmartScreen, UAC ou Windows Update;
- evite bloqueios genéricos no `C:\`;
- toda ACL criada deve ter caminho de reversão;
- mantenha launchers permitidos separados das regras de bloqueio de downloads;
- documente novos falsos positivos conhecidos.

## Testes mínimos

Valide:

1. alerta vermelho de teste;
2. alerta amarelo de teste;
3. `C:\Windows\System32\conhost.exe` não gera alerta;
4. Steam abre normalmente;
5. Epic abre normalmente;
6. arquivo vazio `Steam_Test_Guard.exe` em Downloads é detectado;
7. desativar proteção não deixa ACLs do Guard presas;
8. desinstalação remove a tarefa agendada.
