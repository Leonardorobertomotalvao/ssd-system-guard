# Security Policy

## Supported versions

Apenas a versão mais recente publicada em **Releases** recebe correções.

## Reportando uma vulnerabilidade

Se o repositório tiver **Private vulnerability reporting** habilitado no GitHub, prefira esse canal.

Caso contrário, abra uma issue sem incluir dados pessoais, caminhos privados, tokens, senhas ou outros segredos.

## Princípios do projeto

O SSD System Guard deve:

- operar apenas no computador local;
- não coletar telemetria;
- não ocultar persistência;
- usar uma única tarefa agendada identificável;
- não aplicar bloqueios ao `C:\` inteiro;
- manter uma lista das ACLs criadas para poder revertê-las;
- não apagar a quarentena durante desinstalação sem confirmação;
- não tratar componentes oficiais de `C:\Windows` como jogo;
- manter Steam/Epic e outros launchers oficiais utilizáveis.

## Builds

Para reduzir risco de binários adulterados:

1. builds oficiais são gerados pelo GitHub Actions;
2. cada release inclui `SHA256.txt`;
3. o código-fonte usado no build fica na tag da release.

Assinatura Authenticode não está incluída por padrão porque exige um certificado de code signing do mantenedor.
