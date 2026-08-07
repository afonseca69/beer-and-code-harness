# SPEC — Gate 3 resiliente, observável e capaz de concluir remediações progressivas

## Objetivo

Corrigir o orquestrador Ralph para que o Gate 3 informe claramente como está sendo executado, produza relatórios verdadeiros e continue entregando findings sucessivos ao agente corretor enquanto houver progresso, sem abandonar pendências funcionais de autorização já contidas no escopo aprovado da fase.

## Contexto aprovado

Em 07/08/2026, a execução da Phase 2 de `processos-trabalhistas-s2500-recibo-v2` passou três vezes pelo Gate 2 e três vezes pelo Gate 3. Cada verificação encontrou uma camada diferente de pendências. O terceiro ciclo corrigiu os findings anteriores, mas a verificação final encontrou novos casos de autorização por workspace e cobertura funcional. O Ralph encerrou porque o default de `--max-cycles` era 3.

Não houve bloqueio operacional de permissão nessa execução:

- implementação Codex: `approval: never` e `sandbox: danger-full-access`;
- verificação Codex: `approval: never` e `sandbox: read-only`;
- o finding final era autorização da aplicação, não autorização do shell ou do Codex.

Também foram confirmados dois defeitos de relatório:

- Gate 3 vermelho mantém `LAST_VERIFY_RESULT="Gate 3 nao executado"`;
- arquivos parciais só são coletados após commit verde, fazendo fases falhas mostrarem `arquivos: nenhum`.

## AS IS

- `scripts/ralph.sh` usa três ciclos totais por fase por default.
- Um Gate 3 vermelho sempre consome um ciclo, mesmo quando os findings mudaram e houve progresso.
- Não existe detecção de repetição sem progresso.
- `RALPH_VERIFY_MODEL` permite escolher o modelo do verificador, mas o modelo herdado não aparece na linha inicial.
- Não existe configuração própria para reasoning do verificador Codex.
- Em `--quiet`, o cabeçalho efetivo do Codex fica apenas no arquivo de log.
- A linha inicial do Gate 3 não informa sempre engine, modelo, reasoning, sandbox e caminho do log.
- Log vazio ou ausente não é tratado explicitamente como falha de infraestrutura do verificador.
- O prompt corretivo pode carregar regras genéricas que mandam pausar diante de implicações de autorização, mesmo quando o próprio PHASES ou o finding já aprovou esse trabalho.
- O relatório consolidado distingue Gate 3 verde e pulado, mas não registra corretamente o vermelho.
- A suíte mock atual está verde com 131 asserts, porém não simula findings novos depois do terceiro ciclo, estagnação, reasoning efetivo ou resumo vermelho fiel.

## TO BE

- O início de toda verificação mostra que o log está sendo gravado e informa engine, configuração solicitada, sandbox e caminho do arquivo.
- No Codex, o cabeçalho efetivo de modelo e reasoning é extraído do stream, preservado integralmente no log e espelhado no terminal mesmo em `--quiet`.
- Modelo e reasoning do verificador podem ser definidos por flag e variável de ambiente, com precedência explícita e validação no preflight.
- O reasoning configurado é passado ao Codex via `model_reasoning_effort`; no Claude ele é declarado como não aplicável e uma tentativa de override incompatível falha antes de consumir tokens.
- O ciclo corretivo possui orçamento total seguro maior e trava separada de estagnação.
- Findings novos ou mudança real na árvore zeram o contador de estagnação.
- O mesmo gate, a mesma causa normalizada e a mesma assinatura da árvore por ciclos corretivos consecutivos contam como ausência de progresso.
- Findings de autorização ou permissão da aplicação citados na fase ou na causa do gate são tratados como escopo funcional aprovado e devem ser implementados e testados.
- Essa autorização funcional nunca permite contornar sandbox, allowlist, segredos, deploy, chamadas externas ou comandos destrutivos.
- Gate 3 vermelho atualiza o relatório com cobertura, quantidade de incompletas e log correspondente.
- Fases falhas registram os paths parciais presentes na árvore sem staging ou mutação adicional.
- A documentação PT-BR e inglesa descreve exatamente os novos defaults, flags, variáveis, comportamento de progresso e limites.

## Requisitos rígidos

### R1 — Observabilidade antes e durante o Gate 3

Antes de iniciar o engine verificador, o Ralph deve imprimir uma linha contendo:

- `engine`;
- modelo configurado ou indicação inequívoca de que será herdado;
- reasoning configurado ou indicação inequívoca de que será herdado/não aplicável;
- sandbox efetivo;
- caminho do log;
- estado `gravando`.

Assim que o Codex emitir seu cabeçalho, modelo e reasoning efetivos devem ser espelhados no terminal sem remover essas linhas do log.

### R2 — Configuração determinística quando solicitada

Adicionar:

- `--verify-model MODEL` com fallback em `RALPH_VERIFY_MODEL`;
- `--verify-reasoning EFFORT` com fallback em `RALPH_VERIFY_REASONING`;
- validação Codex para `minimal`, `low`, `medium`, `high` e `xhigh`;
- passagem do reasoning por `-c model_reasoning_effort="<valor>"` ou forma equivalente aceita pelo CLI instalado.

Precedência: flag > variável de ambiente > configuração herdada do engine. O default Claude `haiku` permanece quando não houver override de modelo.

### R3 — Log obrigatório

Cada execução do Gate 3 deve gerar `phase-NN.verify-C.log`. Arquivo inexistente ou vazio reprova o gate com causa operacional explícita. O caminho deve constar tanto no output da fase quanto no relatório consolidado.

### R4 — Remediação progressiva e limitada

- Alterar o default total de ciclos de 3 para 12.
- Preservar `--max-cycles N` e `RALPH_MAX_CYCLES` como hard cap configurável.
- Adicionar `--max-stalled-cycles N` e `RALPH_MAX_STALLED_CYCLES`, default 2.
- Calcular fingerprint estável de `LAST_GATE + causa normalizada` e comparar junto da assinatura da árvore.
- Causa nova ou árvore diferente zera a estagnação.
- Repetição do mesmo fingerprint sem mudança na árvore incrementa a estagnação.
- Ao atingir o limite de estagnação, falhar com diagnóstico específico, sem fingir que o Gate 3 não rodou.
- Limites de uso continuam reexecutando a mesma sessão sem consumir ciclo corretivo.

### R5 — Autorização funcional aprovada

O prompt de correção deve declarar que requisitos de autenticação, autorização, isolamento, policies, gates ou permissões da aplicação são escopo aprovado quando aparecem no texto da fase ou na causa do gate. O agente deve implementar e testar esses requisitos sem pausar apenas por serem de autorização.

O mesmo prompt deve declarar que isso não amplia a autorização operacional: continuam proibidos bypass de sandbox/allowlist, leitura de segredos, chamadas externas não autorizadas, migrations destrutivas, deploy, push e alterações fora do escopo da fase.

### R6 — Relatório verdadeiro

Em todo retorno vermelho do Gate 3, `LAST_VERIFY_RESULT` deve registrar ao menos:

- estado vermelho;
- cobertura `parsed/expected`;
- quantidade de tasks incompletas quando disponível;
- ciclo;
- log.

Antes de registrar uma fase falha, `LAST_PHASE_FILES` deve ser atualizado a partir dos paths alterados e não rastreados, sem executar `git add`. Se não houver paths, deve continuar `nenhum`.

### R7 — Compatibilidade

- Manter Gate 3 read-only.
- Manter `approval_policy="never"` no perfil `system4u-autonomous`.
- Não enfraquecer allowlist, bloqueio da branch `main`, proteção de `.env`, bloqueio de migrations ou proibição de WIP no perfil protegido.
- Preservar engines Codex e Claude, `RALPH_VERIFY=always|auto|off`, `--quiet`, resume, Gate 2, limites de uso e um commit por fase verde.
- Não alterar dependências.

## Requisitos flexíveis

- Nomes internos das funções de fingerprint, coleta de runtime e paths podem seguir as convenções atuais do shell script.
- O formato visual pode usar uma ou duas linhas para configuração solicitada e runtime efetivo, desde que todos os campos obrigatórios estejam presentes.
- A causa normalizada pode usar `sha256sum` ou ferramenta já requerida pelo script.
- O relatório pode abreviar findings longos, desde que preserve a causa completa no log e no prompt corretivo seguinte.

## Critérios de aceite binários

- [ ] Um cenário mock com findings diferentes nos Gate 3 dos ciclos 1, 2 e 3 recebe um ciclo 4 e termina verde com um único commit de fase.
- [ ] O mesmo cenário falha com hard cap quando `--max-cycles 3` é passado explicitamente.
- [ ] Dois ciclos corretivos consecutivos com o mesmo gate, causa e árvore inalterada encerram por estagnação e informam essa causa.
- [ ] Um finding diferente zera a estagnação.
- [ ] Uma mudança na árvore zera a estagnação mesmo que a descrição do finding permaneça igual.
- [ ] O prompt corretivo contém a autorização funcional aprovada e a separação explícita dos limites operacionais.
- [ ] O início do Gate 3 informa engine, configuração solicitada, sandbox, log e `gravando`.
- [ ] Em Codex quiet, o terminal mostra modelo e reasoning efetivos e o arquivo preserva o cabeçalho completo.
- [ ] `--verify-model` prevalece sobre `RALPH_VERIFY_MODEL`.
- [ ] `--verify-reasoning` prevalece sobre `RALPH_VERIFY_REASONING` e chega ao mock Codex como `model_reasoning_effort`.
- [ ] Reasoning inválido falha no preflight antes da primeira sessão.
- [ ] Override de reasoning com engine Claude falha no preflight com mensagem clara.
- [ ] Log de verificação ausente ou vazio deixa Gate 3 vermelho com causa operacional.
- [ ] Gate 3 incompleto aparece no resumo como executado e vermelho, nunca como `nao executado`.
- [ ] Fase falha com trabalho parcial lista os arquivos atuais sem criar commit ou alterar o index.
- [ ] Os 131 asserts existentes continuam verdes, além dos novos casos.
- [ ] `scripts/check-shell.sh` permanece verde; Shellcheck é executado se estiver disponível e sua ausência é reportada honestamente.
- [ ] README PT-BR e inglês permanecem semanticamente equivalentes.

## Exclusões

- Alterar qualquer aplicação que use o Ralph, incluindo `plataforma-simuladores` e PortalXML.
- Reabrir ou modificar a implementação S-2500.
- Executar `ralph.sh` contra um projeto real durante a implementação deste slice.
- Remover o hard cap total ou criar loop infinito sem trava.
- Conceder acesso fora de sandbox/allowlist ou automatizar aprovação externa.
- Ler `.env`, tokens, certificados ou configurações secretas.
- Adicionar dependências, migrations, banco, rede, deploy, push, merge, tag ou release.
- Alterar `.claude-plugin/marketplace.json`.
- Descartar, reformatar ou sobrescrever mudanças locais anteriores sem relação com este slice.

## Riscos e mitigações

- **Mais consumo de tokens:** default 12 pode prolongar fases. Mitigar com estagnação default 2, hard cap explícito, logs e fingerprints.
- **Verifier muda a redação sem progresso real:** normalizar espaços e prefixos estáveis; combinar causa com assinatura da árvore.
- **Self-hosting:** o Ralph modifica seu próprio script, mas a instância já iniciada mantém funções carregadas. Provar comportamento novo por `scripts/test-ralph.sh`; uma execução real posterior usará o script novo.
- **CLI Codex evoluir:** validar o valor no preflight, manter o cabeçalho efetivo no log e cobrir os argumentos no mock.
- **Relatório expor conteúdo indevido:** listar somente paths e metadados operacionais; não imprimir conteúdo de arquivos nem variáveis secretas.
- **Worktree atual suja:** preservar os cinco arquivos já modificados; os artefatos de planejamento devem ser revisados e commitados antes do handoff.

## Gates da entrega

1. Testes red/green focados com engine mock, sem rede e sem tokens.
2. Suíte completa `scripts/test-ralph.sh` verde.
3. `scripts/check-shell.sh` verde.
4. Revisão do diff para segurança operacional, compatibilidade Codex/Claude e preservação das mudanças preexistentes.
5. README PT-BR e inglês sincronizados.

