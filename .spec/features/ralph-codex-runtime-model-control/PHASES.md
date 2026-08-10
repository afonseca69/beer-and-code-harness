# Ralph Codex Runtime Model Control — Phases

**Status:** aprovado explicitamente em 2026-08-10 para bootstrap controlado com Codex `gpt-5.6-luna`/`xhigh`.

## Phase 1: Controlar modelo e reasoning das sessões mutáveis

### Objetivo

Adicionar um contrato determinístico de modelo e reasoning para toda sessão de implementação/correção iniciada pelo Ralph, mantendo o Gate 3 independente.

### Limites

- Alterar apenas o harness `bc-harness-codex`.
- Não definir Luna/xhigh como default universal; a configuração deve ser explícita por flag ou ambiente.
- Não modificar sandboxes, políticas de aprovação, allowlists, commits, gates, progresso, limite de uso ou detecção de testes.

### Tarefas

- [ ] Adicionar ao help e ao parser `--model MODEL`, `--model=MODEL`, `--reasoning EFFORT` e `--reasoning=EFFORT` para sessões de implementação/correção.
- [ ] Adicionar suporte a `RALPH_MODEL` e `RALPH_REASONING` com precedência `flag > ambiente > herdado`.
- [ ] Fazer o preflight rejeitar flags explicitamente vazias antes da primeira sessão de engine.
- [ ] Validar no Codex os esforços `minimal`, `low`, `medium`, `high` e `xhigh` para implementação/correção.
- [ ] Fazer o preflight rejeitar qualquer reasoning de implementação quando o engine for Claude, sem iniciar implementação nem verificação.
- [ ] Propagar modelo e reasoning resolvidos a toda chamada Codex em modo `impl`, incluindo sessão inicial, ciclos de correção e retry após limite de uso.
- [ ] Propagar modelo explícito às sessões Claude de implementação sem alterar o default `haiku` independente do verificador.
- [ ] Preservar `--verify-model`, `--verify-reasoning`, `RALPH_VERIFY_MODEL` e `RALPH_VERIFY_REASONING` como controles exclusivos do Gate 3.
- [ ] Estender o engine mock para registrar separadamente modelo/reasoning de cada sessão mutável e de verificação.
- [ ] Adicionar regressões para precedência por flag, fallback por ambiente, herança sem override e propagação em ciclo corretivo.
- [ ] Adicionar regressões que provem falha de preflight sem chamada de engine para valor vazio, reasoning Codex inválido e reasoning Claude incompatível.
- [ ] Executar `scripts/check-shell.sh` e `scripts/test-ralph.sh` integralmente.

### Critérios de aceite

- Flags prevalecem sobre ambiente e ambiente prevalece sobre herança.
- A mesma configuração chega à implementação inicial e à correção.
- Sem override, o comportamento herdado existente permanece.
- Reasoning inválido/incompatível falha antes de consumir sessão.
- Gate 3 continua recebendo somente seus próprios controles.
- As duas suites do harness ficam verdes.

### Testes obrigatórios

```bash
scripts/check-shell.sh
scripts/test-ralph.sh
```

### O que não pode ser alterado

- Defaults globais do Codex ou configurações pessoais.
- Contrato de commits por fase.
- Gate 2, Gate 3, estagnação, progresso e tratamento de limite de uso, salvo a passagem dos mesmos argumentos durante retry.
- Qualquer arquivo de `plataforma-simuladores`.

## Phase 2: Tornar o runtime efetivo observável e documentado

### Objetivo

Expor de forma auditável a configuração solicitada e o runtime efetivo das sessões de implementação/correção, fechar a documentação bilíngue e provar ausência de regressão.

### Limites

- Preservar o output completo nos logs existentes; não criar novo formato de artefatos.
- Em `--quiet`, espelhar somente as linhas necessárias do cabeçalho Codex.
- Não alterar decisões funcionais dos quatro gates.

### Tarefas

- [ ] Antes de cada sessão de implementação/correção, registrar modo, engine, modelo/reasoning solicitados ou herdados, sandbox e caminho do log.
- [ ] Fazer `--quiet` espelhar `model:` e `reasoning effort:` do cabeçalho Codex também no modo `impl`.
- [ ] Preservar no log de ciclo o cabeçalho Codex completo, incluindo metadados não espelhados no terminal quiet.
- [ ] Manter a observabilidade já existente do Gate 3 e seus logs obrigatórios sem regressão.
- [ ] Adicionar teste quiet para configuração solicitada, modelo/reasoning efetivos no terminal e cabeçalho completo no log de implementação.
- [ ] Adicionar regressão que confirme os sandboxes `danger-full-access`, `workspace-write` e `read-only` nos respectivos perfis/modos.
- [ ] Atualizar o help embutido com flags, variáveis, precedência, compatibilidade por engine e separação do Gate 3.
- [ ] Atualizar `README.md` com o contrato e um exemplo Codex Luna/xhigh para todas as sessões.
- [ ] Atualizar `README.pt-BR.md` com o mesmo contrato e exemplo.
- [ ] Confirmar que documentação e comportamento não afirmam que Luna/xhigh é default universal.
- [ ] Executar `scripts/check-shell.sh`, `scripts/test-ralph.sh` e `git diff --check`.
- [ ] Revisar o diff completo e confirmar que nenhum segredo, chamada externa, dado real ou arquivo fora do harness entrou na fase.

### Critérios de aceite

- O operador vê configuração solicitada, sandbox e log antes de cada sessão mutável.
- Em quiet, modelo e reasoning efetivos aparecem no terminal e o cabeçalho completo permanece no log.
- Help e READMEs descrevem o mesmo contrato.
- O exemplo aprovado usa `gpt-5.6-luna`/`xhigh` nos pares de implementação e verificação.
- A suite integral do harness e a checagem shell ficam verdes.
- O diff permanece restrito ao harness e aos artefatos desta feature.

### Testes obrigatórios

```bash
scripts/check-shell.sh
scripts/test-ralph.sh
git diff --check
```

### O que não pode ser alterado

- Código, documentação, dependências ou dados de `plataforma-simuladores`.
- Defaults globais do Codex.
- Política de segurança do perfil `system4u-autonomous`.
- Regras de commit, gates, estagnação, limite de uso ou progresso.
- Push, merge, deploy ou release.
