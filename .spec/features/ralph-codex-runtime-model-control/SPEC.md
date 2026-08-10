# Ralph Codex Runtime Model Control

## Status

Slice e `PHASES.md` aprovados explicitamente em 2026-08-10. O planejamento está liberado para commit e para o bootstrap controlado com Codex `gpt-5.6-luna`/`xhigh`; o Ralph atual não deve executar esta própria feature porque ainda não garante modelo e reasoning nas sessões mutáveis.

## Objetivo

Permitir que cada sessão Codex de implementação e correção iniciada pelo `scripts/ralph.sh` receba modelo e reasoning explícitos, com precedência determinística, validação de preflight e observabilidade do runtime efetivo. A primeira configuração operacional aprovada é `gpt-5.6-luna` com reasoning `xhigh`.

## AS IS

- O Ralph aceita `--verify-model` e `--verify-reasoning` apenas para o verificador independente do Gate 3.
- Sessões Codex de implementação e correção executam `rtk codex exec` sem `--model` nem `model_reasoning_effort`, herdando a configuração global do Codex.
- O run interrompido de `plataforma-simuladores` registrou `gpt-5.6-sol` com reasoning `high` na sessão de implementação, divergindo da nova decisão operacional.
- Em `--quiet`, o runtime efetivo do Codex é espelhado no terminal somente durante o Gate 3; sessões de implementação preservam o cabeçalho no log, mas não expõem modelo/reasoning no resumo operacional.
- Os controles do Gate 3 são independentes e já possuem a precedência flag sobre variável de ambiente sobre herança.

## TO BE

- `scripts/ralph.sh` aceita `--model MODEL` e `--reasoning EFFORT` para sessões de implementação e correção.
- As variáveis `RALPH_MODEL` e `RALPH_REASONING` fornecem o fallback operacional quando as flags não forem passadas.
- A precedência é `flag > variável de ambiente > configuração herdada do engine`.
- Os controles existentes `--verify-model`, `--verify-reasoning`, `RALPH_VERIFY_MODEL` e `RALPH_VERIFY_REASONING` continuam independentes e sem regressão.
- Cada sessão Codex de implementação/correção recebe os argumentos efetivos solicitados e registra antes da execução: modo, engine, modelo/reasoning solicitados, sandbox e caminho do log.
- Em `--quiet`, o terminal espelha do cabeçalho Codex somente `model:` e `reasoning effort:` também nas sessões de implementação/correção; o log continua completo.
- A execução operacional aprovada usa explicitamente Luna/xhigh tanto na implementação/correção quanto no Gate 3.

## Requisitos rígidos

### R1 — Contrato de CLI

O help deve documentar:

- `--model MODEL` para implementação e correção;
- `--reasoning EFFORT` para implementação e correção Codex;
- `RALPH_MODEL` e `RALPH_REASONING`;
- precedência e separação em relação aos controles `--verify-*`.

### R2 — Precedência determinística

Para implementação/correção:

1. flag explícita;
2. variável de ambiente correspondente;
3. herança do engine quando nenhum override existir.

Um valor vazio passado explicitamente por flag deve falhar no preflight antes da primeira sessão.

### R3 — Compatibilidade por engine

- Codex aceita modelo e reasoning configurados.
- Reasoning Codex aceita somente os esforços já suportados pelo contrato atual do harness: `minimal`, `low`, `medium`, `high` ou `xhigh`.
- Claude pode receber modelo explícito para implementação, mas qualquer `--reasoning`/`RALPH_REASONING` deve falhar no preflight por incompatibilidade.
- A mudança não pode alterar sandboxes, política de aprovação, allowlist ou guardrails existentes.

### R4 — Cobertura de todas as sessões mutáveis

Modelo e reasoning de implementação devem chegar à sessão inicial e a todo ciclo de correção. Retry da mesma sessão após limite de uso deve preservar os mesmos argumentos.

### R5 — Gate 3 independente

Os controles do verificador permanecem independentes. Para executar todas as sessões com Luna/xhigh, o comando operacional deve usar os pares de implementação e verificação:

```bash
scripts/ralph.sh --engine codex \
  --model gpt-5.6-luna --reasoning xhigh \
  --verify-model gpt-5.6-luna --verify-reasoning xhigh \
  <PHASES.md>
```

### R6 — Observabilidade

Antes de cada sessão de implementação/correção, o Ralph deve informar configuração solicitada, modo, sandbox e log. No Codex, o cabeçalho do CLI continua sendo a fonte do runtime efetivo. Em `--quiet`, apenas modelo e reasoning efetivos são espelhados; o cabeçalho completo permanece no log do ciclo.

### R7 — Regressão do harness

Testes com engine mock devem provar:

- precedência de flag sobre ambiente;
- fallback em ambiente;
- herança sem override;
- propagação à implementação inicial e ao ciclo corretivo;
- rejeição de reasoning inválido/incompatível antes do engine;
- independência dos controles do Gate 3;
- observabilidade quiet e preservação do log completo;
- preservação dos perfis e sandboxes existentes.

### R8 — Documentação bilíngue

`README.md`, `README.pt-BR.md` e o help embutido em `scripts/ralph.sh` devem descrever o mesmo contrato.

## Requisitos flexíveis

- Nomes internos de variáveis e helpers podem seguir o padrão já usado pelos controles do verificador.
- A mensagem exata de preflight pode variar, desde que identifique valor, sessão afetada e valores aceitos.
- Casos de teste podem ser agrupados na suite existente desde que cada critério rígido possua assert verificável.

## Critérios de aceite binários

- [ ] `scripts/ralph.sh --help` lista flags, variáveis e precedência de implementação.
- [ ] Flags de implementação prevalecem sobre `RALPH_MODEL`/`RALPH_REASONING`.
- [ ] Variáveis de ambiente são usadas quando flags não existem.
- [ ] Sem override, o Codex continua herdando modelo e reasoning.
- [ ] Modelo/reasoning configurados alcançam a sessão inicial e pelo menos um ciclo de correção em teste.
- [ ] Controles do Gate 3 continuam independentes e funcionais.
- [ ] Reasoning inválido no Codex e qualquer reasoning no Claude falham no preflight sem sessão de engine.
- [ ] `--quiet` mostra modelo/reasoning efetivos da implementação e mantém o cabeçalho completo no log.
- [ ] A suite `scripts/test-ralph.sh` passa integralmente.
- [ ] `scripts/check-shell.sh` passa.
- [ ] README em inglês, README em PT-BR e help estão sincronizados.

## Exclusões explícitas

- Não alterar modelos padrão globais do Codex nem arquivos pessoais de configuração.
- Não hard-code `gpt-5.6-luna` ou `xhigh` como default universal do projeto open source.
- Não alterar o comportamento de commits, progresso, Gate 2, Gate 3, estagnação, limite de uso ou detecção de Sail além do necessário para propagar/logar a configuração.
- Não executar o Ralph contra `plataforma-simuladores` nesta feature.
- Não modificar código, dependências, banco ou documentação de produto de `plataforma-simuladores`.
- Não fazer push, merge, deploy ou release.

## Riscos

- Uma flag global ambígua poderia substituir silenciosamente o modelo econômico do Gate 3; por isso os controles `--verify-*` permanecem separados.
- Argumentos inconsistentes entre sessão inicial e correção quebrariam a decisão operacional; a suite precisa observar ambas.
- Filtrar demais o output em `--quiet` pode esconder a evidência do runtime; o log completo e as duas linhas efetivas devem permanecer.
- Passar reasoning ao Claude produziria contrato falso; o preflight deve falhar antes de consumir uma sessão.

## Gates

- Gate de contrato: help e documentação bilíngue concordam.
- Gate mecânico: `scripts/check-shell.sh` verde.
- Gate de regressão: `scripts/test-ralph.sh` integralmente verde.
- Gate operacional: árvore do `bc-harness-codex` limpa antes do handoff.
- Gate humano: aprovação explícita deste `PHASES.md`, concluída em 2026-08-10.
