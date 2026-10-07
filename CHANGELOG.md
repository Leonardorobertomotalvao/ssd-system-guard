# Changelog

## 1.1.7

### Hotfix do painel
- corrige o popup repetitivo do Microsoft .NET Framework:
  `Os tipos de argumento não correspondem`;
- eventos periódicos do WinForms agora são executados dentro de proteção
  `try/catch`;
- adiciona captura global de `Application.ThreadException`;
- falhas passam a ser gravadas em `panel_errors.log` em vez de abrir diálogos
  infinitos;
- contadores de bloqueios/alertas deixam de retornar um array ambíguo e passam
  a usar um objeto com propriedades `Blocked` e `Alerts`;
- conversões de booleanos do JSON passam a ser explícitas;
- criação dinâmica de `System.Drawing.Size` usa argumentos tipados;
- timer visual alterado de 1,5 s para 5 s;
- após três falhas consecutivas do refresh automático, somente o timer visual é
  parado; a proteção em segundo plano não é afetada;
- mantém toda a proteção contínua e auto-recuperação da v1.1.6.
