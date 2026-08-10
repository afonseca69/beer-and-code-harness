# Plano — Ralph Codex Runtime Model Control

## Resultado esperado

O Ralph passa a controlar de forma explícita e auditável o modelo e o reasoning das sessões Codex de implementação/correção, sem acoplar o harness a um modelo default específico e sem alterar os controles independentes do Gate 3.

## Estratégia

Implementar primeiro o contrato de entrada e a propagação determinística. Depois ampliar a observabilidade e fechar a documentação/regressão. Cada fase termina com a suite completa do harness verde para permanecer autonomamente commitável.

## Arquivos prováveis

- `scripts/ralph.sh`
- `scripts/test-ralph.sh`
- `README.md`
- `README.pt-BR.md`

Nenhum arquivo de `plataforma-simuladores` pertence ao escopo de implementação desta feature.

## Fase 1 — Controle determinístico das sessões mutáveis

1. Adicionar estado e parsing para `--model` e `--reasoning`, incluindo formas com `=`.
2. Resolver `MODEL`/`REASONING` com precedência flag sobre `RALPH_MODEL`/`RALPH_REASONING` sobre herança.
3. Validar valores vazios, esforços Codex aceitos e incompatibilidade de reasoning no Claude durante o preflight.
4. Propagar modelo/reasoning para todo `run_engine(..., impl)`, cobrindo implementação, correção e retries por limite de uso.
5. Preservar os argumentos e a precedência exclusivos do modo `verify`.
6. Estender o mock para registrar separadamente a configuração recebida por sessões mutáveis.
7. Adicionar casos red/green para flags, ambiente, herança, correção e preflight.
8. Rodar `scripts/check-shell.sh` e `scripts/test-ralph.sh`.

## Fase 2 — Runtime observável e documentação sincronizada

1. Registrar antes de cada implementação/correção: modo, engine, configuração solicitada, sandbox e log.
2. Ajustar o filtro `--quiet` do Codex para espelhar `model:` e `reasoning effort:` também no modo `impl`, sem expor o restante do cabeçalho.
3. Provar que o log de implementação preserva o cabeçalho completo.
4. Provar que Gate 3, perfis e sandboxes não regrediram.
5. Atualizar help, `README.md` e `README.pt-BR.md` com flags, variáveis, precedência, separação do Gate 3 e exemplo Luna/xhigh.
6. Rodar `scripts/check-shell.sh` e a suite integral `scripts/test-ralph.sh`.
7. Revisar `git diff --check` e o diff completo.

## Estratégia de testes

### Testes focados

- Novo caso para configuração da implementação Codex via flag e via ambiente.
- Novo cenário corretivo que confirme os mesmos argumentos em mais de uma chamada mutável.
- Casos de preflight sem chamadas do mock engine.
- Caso quiet que confirme duas linhas no terminal e cabeçalho integral no log.

### Regressão

- `scripts/check-shell.sh`
- `scripts/test-ralph.sh`
- `git diff --check`

## Rollback

Cada fase gera um commit isolado. Se a propagação causar regressão, reverter primeiro a fase de observabilidade/documentação e depois a fase do contrato. Nenhuma migration, dado persistente de aplicação ou integração externa participa do rollback.

## Handoff operacional posterior

Depois que esta feature do harness estiver verde e commitada:

1. Confirmar que `plataforma-simuladores` permanece limpo e que a Fase 1 do acceptance hardening continua registrada no commit `0bc8056`.
2. Executar primeiro a feature de fidelidade textual, registrada no commit de planejamento `7086420`:

```bash
scripts/ralph.sh \
  --engine codex --quiet \
  --model gpt-5.6-luna --reasoning xhigh \
  --verify-model gpt-5.6-luna --verify-reasoning xhigh \
  .spec/features/processos-trabalhistas-source-copy-fidelity/PHASES.md
```

3. Com todas as fases de fidelidade textual verdes e commitadas, retomar o acceptance hardening a partir da Fase 2:

```bash
scripts/ralph.sh \
  --engine codex --from 2 --quiet \
  --model gpt-5.6-luna --reasoning xhigh \
  --verify-model gpt-5.6-luna --verify-reasoning xhigh \
  .spec/features/processos-trabalhistas-v3-acceptance-hardening/PHASES.md
```

Esse handoff não integra as fases executáveis do harness e só pode ocorrer depois da conclusão desta feature, com as árvores dos dois repositórios limpas. O bootstrap desta própria feature deve usar uma execução direta do Codex explicitamente fixada em `gpt-5.6-luna`/`xhigh`, sem depender da herança do Ralph atual.
