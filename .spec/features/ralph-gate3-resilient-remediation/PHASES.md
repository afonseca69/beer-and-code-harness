# PHASES — Gate 3 resiliente, observável e capaz de concluir remediações progressivas

Este documento deve ser executado no repositório `bc-harness-codex`. Cada fase produz um commit autocontido. Nenhuma fase autoriza rede, tokens reais, deploy, push, merge, release, leitura de segredos, instalação de dependências ou descarte das mudanças locais preexistentes.

## Phase 1: Tornar o Gate 3 observável e o relatório verdadeiro

### Objetivo

Expor configuração e runtime efetivo do verificador, garantir a geração do log e corrigir o estado consolidado de verificações e arquivos parciais.

### Limites

- Configuração, captura de output e relatório do Gate 3.
- Testes somente com engines mockados.
- Sem alterar ainda a política de ciclos ou o prompt de autorização funcional.

### Tarefas

- [ ] Adicionar `--verify-model` e `--verify-reasoning` com precedência flag sobre `RALPH_VERIFY_MODEL` e `RALPH_VERIFY_REASONING`.
- [ ] Validar reasoning Codex em `minimal|low|medium|high|xhigh` e rejeitar override de reasoning no engine Claude antes de consumir tokens.
- [ ] Passar o reasoning configurado ao Codex por `model_reasoning_effort` sem alterar o sandbox read-only do verificador.
- [ ] Informar no início do Gate 3 engine, modelo/reasoning solicitados ou herdados, sandbox, caminho do log e estado `gravando`.
- [ ] Espelhar modelo e reasoning efetivos do cabeçalho Codex no terminal em modo quiet, preservando o cabeçalho integral no log.
- [ ] Reprovar explicitamente log de verificação ausente ou vazio.
- [ ] Atualizar `LAST_VERIFY_RESULT` em todos os retornos vermelhos com cobertura, incompletas, ciclo e log.
- [ ] Coletar paths modificados e não rastreados antes de registrar uma fase falha, sem executar staging.
- [ ] Estender o engine mock e criar regressões para configuração, runtime efetivo, log obrigatório, resumo vermelho e arquivos parciais.

### Critérios de aceite

- Gate 3 Codex quiet mostra engine, sandbox, log, modelo e reasoning efetivos.
- Flag prevalece sobre env para modelo e reasoning.
- Reasoning inválido ou incompatível aborta no preflight com zero sessões.
- Log ausente/vazio deixa o gate vermelho com causa clara.
- Resumo de Gate 3 incompleto nunca diz `Gate 3 nao executado`.
- Fase falha lista os paths parciais reais e não cria commit.

### Testes obrigatórios

- Casos focados novos de `scripts/test-ralph.sh` para runtime/config/log/report.
- Casos existentes `verify-model`, `quiet`, `dirty-after-fail`, `codex-rtk` e `system4u-autonomous`.
- `scripts/check-shell.sh`.
- `git diff --check`.

### Não pode alterar

- Default ou semântica de `--max-cycles`.
- Texto do prompt corretivo sobre autorização funcional.
- Sandbox, allowlist e guardrails System4u.
- `.claude-plugin/marketplace.json`.

## Phase 2: Continuar remediações enquanto houver progresso

### Objetivo

Permitir que findings sucessivos ultrapassem três ciclos por default, interrompendo cedo somente quando houver estagnação comprovada ou quando o hard cap configurado for atingido.

### Limites

- Loop corretivo, estado de progresso e prompt de correção.
- Testes somente com engines mockados.
- Sem executar Ralph contra projeto externo ou aplicação real.

### Tarefas

- [ ] Alterar o default total de ciclos de 3 para 12, preservando `--max-cycles` e `RALPH_MAX_CYCLES` como hard cap explícito.
- [ ] Adicionar `--max-stalled-cycles` e `RALPH_MAX_STALLED_CYCLES` com default 2 e validação inteira `>= 1`.
- [ ] Criar fingerprint estável de gate e causa normalizada e combiná-lo com a assinatura da árvore.
- [ ] Zerar a estagnação quando o finding, o gate ou a árvore mudar.
- [ ] Incrementar estagnação apenas quando gate, causa e árvore se repetirem sem progresso em ciclos corretivos consecutivos.
- [ ] Encerrar ao atingir a estagnação com diagnóstico próprio, último Gate 3, paths parciais e logs corretos.
- [ ] Preservar a regra de que limite de uso reexecuta a mesma sessão sem consumir ciclo.
- [ ] Declarar no prompt corretivo que autorização, autenticação, isolamento e permissões da aplicação são escopo aprovado quando constam da fase ou da causa do gate.
- [ ] Declarar no mesmo prompt que autorização funcional não permite contornar sandbox, allowlist, segredos, chamadas externas ou demais limites operacionais.
- [ ] Criar cenário mock em camadas com três findings sucessivos e quarto Gate 3 verde.
- [ ] Criar regressões para hard cap explícito, estagnação, finding novo, árvore alterada e finding de workspace autorizado.

### Critérios de aceite

- O cenário em camadas chega ao ciclo 4 e conclui com um único commit.
- O mesmo cenário falha quando recebe explicitamente `--max-cycles 3`.
- Repetição sem mudança atinge estagnação e não gira indefinidamente.
- Finding ou árvore diferente permite continuar e zera estagnação.
- Finding de autorização funcional chega verbatim ao corretor e é declarado aprovado dentro do escopo da fase.
- Nenhum guardrail operacional é removido ou enfraquecido.

### Testes obrigatórios

- Casos focados novos de `scripts/test-ralph.sh` para layered findings e estagnação.
- Casos existentes `verify-incomplete`, `stall-after-red`, `limit-epoch`, `limit-generic`, `verify-auto`, `dirty-after-fail` e `system4u-autonomous`.
- `scripts/check-shell.sh`.
- `git diff --check`.

### Não pode alterar

- Parser consolidado de tasks já corrigido, salvo ajuste estritamente necessário coberto por regressão.
- Políticas de sandbox, approval, allowlist, branch ou WIP.
- Engines reais, rede ou tokens.
- Aplicações consumidoras do harness.

## Phase 3: Sincronizar documentação e provar regressão completa

### Objetivo

Documentar o contrato final em PT-BR e inglês e provar que a evolução não quebrou os comportamentos existentes do Ralph.

### Limites

- README, help/comentários operacionais e verificação completa.
- Sem novas mudanças funcionais além de correções necessárias para manter docs e testes coerentes.

### Tarefas

- [ ] Atualizar `README.pt-BR.md` com default 12, estagnação default 2, flags/env de modelo e reasoning, runtime efetivo e logs.
- [ ] Atualizar `README.md` com conteúdo semanticamente equivalente.
- [ ] Atualizar help e comentários de `scripts/ralph.sh` para refletir exatamente flags, variáveis, causas de parada e exports.
- [ ] Documentar que findings de autorização funcional dentro da fase são corrigíveis sem ampliar permissões operacionais.
- [ ] Documentar hard cap, estagnação, usage limit e diferença entre configuração solicitada e runtime efetivo.
- [ ] Rodar a suíte completa `scripts/test-ralph.sh` e confirmar os 131 asserts anteriores mais os novos.
- [ ] Rodar `scripts/check-shell.sh` e Shellcheck se já estiver disponível.
- [ ] Rodar `git diff --check` e revisar o diff para preservar mudanças preexistentes e impedir inclusão de segredos ou dados reais.
- [ ] Confirmar que nenhum arquivo fora de `scripts/ralph.sh`, `scripts/test-ralph.sh`, `README.md` e `README.pt-BR.md` foi alterado pela implementação deste slice.

### Critérios de aceite

- READMEs PT-BR e inglês descrevem o mesmo contrato.
- Help do script coincide com a implementação e os defaults.
- Suíte completa do harness está verde com todos os casos antigos e novos.
- Bash syntax está verde; ausência de Shellcheck é reportada como skip, não como sucesso executado.
- Não há dependência nova, chamada real de engine, rede, secret handling ou alteração de aplicação consumidora.

### Testes obrigatórios

- `scripts/test-ralph.sh` completo.
- `scripts/check-shell.sh`.
- Shellcheck se disponível no ambiente.
- `git diff --check`.

### Não pode alterar

- `.claude-plugin/marketplace.json`.
- Aplicações externas e seus `.spec/`.
- Dependências, hooks, comandos de publicação ou configuração secreta.
- Histórico Git ou mudanças locais anteriores fora do slice.

