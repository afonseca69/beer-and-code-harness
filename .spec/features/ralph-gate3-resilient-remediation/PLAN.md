# PLAN — Gate 3 resiliente, observável e capaz de concluir remediações progressivas

## Estratégia

Evoluir o Ralph em três entregas autocontidas: primeiro tornar o Gate 3 e o relatório observáveis e verdadeiros; depois alterar o controle de remediação e o contrato do prompt corretivo; por fim sincronizar documentação e executar a regressão completa.

O trabalho deve ser feito sobre as mudanças locais existentes no repositório `bc-harness-codex`. Nenhum arquivo preexistente pode ser restaurado ou reescrito a partir de `HEAD` como forma de simplificar o diff.

## Dependências

- Phase 1 fornece estado e helpers de observabilidade usados pelo relatório.
- Phase 2 depende da coleta de estado da Phase 1 para decidir progresso e estagnação.
- Phase 3 depende dos contratos finais das duas fases anteriores para documentar sem antecipar comportamento.

## Tarefa 1 — Configuração e runtime efetivo do verificador

### Arquivos prováveis

- `scripts/ralph.sh`
- `scripts/test-ralph.sh`

### Alterações

- Resolver `--verify-model` e `--verify-reasoning` antes do input posicional.
- Implementar precedência flag > env > herdado.
- Validar reasoning Codex e rejeitar override incompatível no Claude.
- Passar `model_reasoning_effort` ao `codex exec` somente quando configurado.
- Evoluir o mock para capturar modelo e reasoning recebidos.
- Fazer a captura quiet espelhar apenas os metadados efetivos relevantes, mantendo o stream completo no arquivo.
- Informar engine, modelo/reasoning solicitados, sandbox, caminho do log e `gravando` antes da sessão.
- Tratar log ausente ou vazio como Gate 3 vermelho.

### Verificação

- Casos focados para flag/env/herdado, reasoning inválido, Claude incompatível, quiet e log vazio.
- Nenhuma chamada real ao Codex ou Claude.

## Tarefa 2 — Estado de Gate 3 e relatório fiel

### Arquivos prováveis

- `scripts/ralph.sh`
- `scripts/test-ralph.sh`

### Alterações

- Atualizar `LAST_VERIFY_RESULT` em todos os retornos vermelhos.
- Registrar cobertura, quantidade de incompletas, ciclo e log.
- Criar helper read-only para paths alterados/untracked da fase.
- Atualizar `LAST_PHASE_FILES` antes de qualquer relatório de falha, inclusive hard cap, estagnação, guardrail ou commit.
- Manter `nenhum` apenas quando a árvore realmente não contém paths de trabalho.
- Garantir que a coleta não execute staging e respeite o perfil protegido.

### Verificação

- Gate 3 incomplete deve constar como vermelho no resumo.
- Fase com arquivo parcial deve listar o path e manter o número de commits inalterado.
- Fase sem mudança deve continuar exibindo `nenhum`.

## Tarefa 3 — Controle progressivo de remediação

### Arquivos prováveis

- `scripts/ralph.sh`
- `scripts/test-ralph.sh`

### Alterações

- Mudar o default de `MAX_CYCLES` para 12 sem alterar o hard cap explícito.
- Adicionar `MAX_STALLED_CYCLES`, flag, env e validação `>= 1`.
- Gerar fingerprint estável a partir do gate e causa normalizada.
- Comparar fingerprint e assinatura da árvore após cada falha.
- Zerar estagnação quando houver novo finding, novo gate ou mudança na árvore.
- Encerrar com causa `sem progresso` ao atingir o limite de estagnação.
- Preservar o comportamento especial de rate/usage limit, que não consome ciclo.
- Preservar `RALPH_PHASE_ATTEMPT` e atualizar `RALPH_PHASE_MAX_ATTEMPTS` para refletir o hard cap efetivo.

### Verificação

- Mock em camadas: três Gate 3 vermelhos com findings diferentes e quarto verde.
- Hard cap explícito 3 continua interrompendo o mesmo cenário.
- Mesmo finding + mesma árvore alcança estagnação.
- Mesmo finding + árvore alterada continua.
- Finding novo continua e zera o contador.

## Tarefa 4 — Contrato de autorização funcional no prompt

### Arquivos prováveis

- `scripts/ralph.sh`
- `scripts/test-ralph.sh`

### Alterações

- Acrescentar ao `build_fix_prompt` que autenticação, autorização, isolamento e permissões da aplicação são trabalho aprovado quando constam da fase ou da causa do gate.
- Exigir testes para esses findings.
- Reafirmar que o agente não pode ampliar permissões operacionais nem contornar regras do projeto, sandbox ou allowlist.

### Verificação

- Assert literal no prompt do ciclo corretivo.
- Cenário mock com `TASK 4: INCOMPLETE — falta validar workspace autorizado` chega ao ciclo seguinte sem pausa ou reclassificação.

## Tarefa 5 — Documentação operacional

### Arquivos prováveis

- `README.pt-BR.md`
- `README.md`
- comentários/help de `scripts/ralph.sh`

### Alterações

- Documentar default 12 e estagnação default 2.
- Documentar flags e variáveis de modelo/reasoning.
- Explicar requested versus effective runtime e os logs no quiet.
- Explicar autorização funcional versus autorização operacional.
- Explicar causas de parada: verde, hard cap, estagnação, guardrail e falha operacional.
- Manter os dois idiomas equivalentes.

## Dados, migrations e dependências

- Nenhuma alteração de dados.
- Nenhuma migration.
- Nenhuma dependência nova.
- Artefatos continuam locais em `.phases/` ou no `--run-dir` existente.

## Estratégia de testes

1. Implementar cada cenário novo primeiro no mock e provar que falha contra uma cópia do Ralph anterior quando o mecanismo `RALPH_BIN` permitir.
2. Corrigir `scripts/ralph.sh` até o caso focado ficar verde.
3. Rodar novamente os casos existentes relacionados: `verify-incomplete`, `verify-duplicate`, `verify-eleven-tasks`, `stall-after-red`, `dirty-after-fail`, `verify-model`, `quiet`, `codex-rtk` e `system4u-autonomous`.
4. Rodar `scripts/test-ralph.sh` completo.
5. Rodar `scripts/check-shell.sh`.
6. Se Shellcheck estiver disponível, exigir resultado verde; se não estiver, registrar o skip sem instalar dependência.
7. Executar `git diff --check` e revisar manualmente o diff dos quatro arquivos previstos.

## Rollback

Como não há dados nem dependências, rollback consiste em reverter somente os commits das fases deste slice. Não usar reset destrutivo. As mudanças locais anteriores devem permanecer preservadas.

## Handoff e self-hosting

- Os documentos deste diretório devem ser revisados e aprovados antes do Ralph.
- A árvore do `bc-harness-codex` precisa estar limpa antes do handoff.
- O Ralph pode alterar `scripts/ralph.sh` enquanto uma instância antiga está executando; por isso o comportamento novo deve ser provado por subprocessos de `scripts/test-ralph.sh`, não pela instância pai já carregada.
- Não executar o handoff a partir de `plataforma-simuladores`; o diretório de trabalho deve ser a raiz do checkout `bc-harness-codex`.

