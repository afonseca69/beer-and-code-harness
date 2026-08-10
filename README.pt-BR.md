# Beer and Code Harness (`bc-harness`)

Plugin de [Claude Code](https://claude.com/claude-code) com comandos, agentes e scripts para levar um projeto da ideia à implementação de forma estruturada: especificação formal, planejamento em fases e execução autônoma com validação mecânica — sem abrir mão do controle humano nos pontos de decisão.

O harness é **agnóstico de stack**: quem define linguagem, framework, comandos e convenções são os documentos do próprio projeto (`AGENTS.md`, `CLAUDE.md`, cadeia `.spec/`), nunca o harness.

## Visão geral do fluxo

```
 IDEIA                                             CÓDIGO
   │                                                 ▲
   ▼                                                 │
 /init:project-description  ──┐                      │
 /init:user-stories           │  cadeia init         │
 /init:database-schema        │  (.spec/init/)       │
 /init:project-phases       ──┘                      │
   │                                                 │
   │            /plan "<descrição da feature>"       │
   │            (.spec/features/<slug>/)             │
   ▼                                                 │
 project-phases.md  ou  PHASES.md ────────► scripts/ralph.sh
                                            (execução autônoma
                                             com 4 gates)

 /ai-context ─► AGENTS.md + docs/agents/*  (documenta o código JÁ implementado;
                                            alimenta /plan e o ralph)
```

Três pipelines independentes que se encaixam:

1. **`/init`** — do zero ao plano de construção do projeto (descrição → user stories → schema → fases).
2. **`/plan`** — de uma descrição de feature a SPEC formal + plano faseado, pronto para execução.
3. **`ralph.sh`** — executa qualquer documento de fases de forma autônoma, uma sessão nova de agente por fase, com gates mecânicos e um commit por fase concluída.

Transversal a tudo: **`/ai-context`** mantém a árvore de contexto (`AGENTS.md`, `CLAUDE.md`, `docs/agents/*.md`) sincronizada com o código real.

## Instalação

O repositório é um plugin de Claude Code (`.claude-plugin/plugin.json`). Instale via marketplace/caminho local conforme sua configuração de plugins:

```
/plugin install bc-harness
```

Os comandos ficam disponíveis com namespace: `/bc-harness:init`, `/bc-harness:plan`, etc. (nesta documentação, abreviados sem o namespace).

O `ralph.sh` é um script bash independente — copie ou referencie `scripts/ralph.sh` e rode direto no repositório do projeto-alvo.

**Pré-requisitos do ralph.sh:**

- Engine Codex: `rtk` + `npm install -g @openai/codex` + `OPENAI_API_KEY` (o ralph executa `rtk codex exec`)
- Engine Claude: `npm install -g @anthropic-ai/claude-code` + `ANTHROPIC_API_KEY`
- Raiz de um repositório git com árvore de trabalho **limpa**

### Configuracao das sessoes mutaveis

As sessoes de implementacao/correcao aceitam `--model` / `RALPH_MODEL` e
`--reasoning` / `RALPH_REASONING`. A precedencia e flag > ambiente > heranca
do engine. O Codex aceita `minimal`, `low`, `medium`, `high` ou `xhigh` como
reasoning. O Claude aceita modelo explicito, mas reasoning nao e aplicavel.

O Gate 3 continua com `--verify-model` / `--verify-reasoning` proprios e
permanece separado das sessoes de implementacao. Antes de cada sessao mutavel,
o ralph imprime a configuracao solicitada, o sandbox e o caminho do log. No
Codex `--quiet`, as linhas efetivas `model:` e `reasoning effort:` tambem sao
espelhadas tanto na implementacao quanto na verificacao, enquanto o cabecalho
completo fica preservado no log.

Exemplo aprovado usando Luna/xhigh nas duas sessoes mutaveis:

```bash
scripts/ralph.sh --engine codex --quiet \
  --model gpt-5.6-luna --reasoning xhigh \
  --verify-model gpt-5.6-luna --verify-reasoning xhigh \
  .spec/features/<slug>/PHASES.md
```

## Comandos

### `/init` — roteador da cadeia init

Mostra o estado dos artefatos de `.spec/init/` (presente / ausente / desatualizado) e **invoca o próximo comando da cadeia** (um passo por execução — re-rode `/init` para avançar). Não escreve nada por conta própria; toda autoria vive no comando `init:*` invocado.

A cadeia, em ordem:

| # | Artefato | Comando | Insumos |
|---|---|---|---|
| 1 | `.spec/init/project-description.md` | `/init:project-description` | — (cabeça da cadeia) |
| 2 | `.spec/init/user-stories.md` | `/init:user-stories` | project-description |
| 3 | `.spec/init/database-schema.md` | `/init:database-schema` | description + stories |
| 4 | `.spec/init/project-phases.md` | `/init:project-phases` | description + stories + schema |
| — | `.spec/init/design/` | manual (opcional) | — |

Cada artefato gerado carrega na linha 3 um **stamp** dos insumos (`arquivo@sha256:<12 chars>`). Se um insumo mudar depois, o `/init` detecta e reporta o downstream como *stale* — re-rodar o comando correspondente é upsert-safe: ele entrevista só sobre os deltas e atualiza o stamp.

- **`/init:project-description`** — entrevista o desenvolvedor, descobre a stack e produz a descrição estruturada do projeto.
- **`/init:user-stories`** — deriva user stories estruturadas e testáveis da descrição.
- **`/init:database-schema`** — deriva um schema de banco sugerido em DBML.
- **`/init:project-phases`** — planeja a construção em fases numeradas, agent-ready, com tasks, acceptance criteria e feature tests. **É o input padrão do `ralph.sh`.** Lê `.spec/init/design/` quando existir (refs de telas/componentes).

### `/plan` — pipeline de planejamento de feature

```
/plan "<descrição da feature ou caminho para arquivo de descrição>"
```

Produz, sob `.spec/features/<slug>/`:

| Artefato | Conteúdo |
|---|---|
| `SPEC.md` | Especificação formal em GEARS, com seções RIGID/FLEXIBLE, diagramas AS IS / TO BE e acceptance criteria binários |
| `PLAN.md` | Decomposição de tasks consciente da arquitetura, com fases de dependência, riscos e critérios de validação |
| `PHASES.md` | Visão do PLAN no formato executável pelo `ralph.sh` |
| `openapi.yaml` / `service.proto` / `asyncapi.yaml` | Contratos formais, quando a SPEC declara superfície de API (condicional) |

Características:

- **Sem issue tracker** — a descrição confirmada + ACs são a fonte de verdade. Nada de Jira.
- **Tier de complexidade** (`light` / `standard` / `complete`) classificado por sinais objetivos (nº de requisitos, multi-repo, contratos, mensageria); ajusta a profundidade da SPEC, a obrigatoriedade do clarifier e a emissão de contratos.
- **Checkpoints humanos** em cada etapa: confirmação do input normalizado, aprovação da SPEC, resolução de ambiguidades, confirmação da decomposição.
- **Clarifier em duas fases** — o agente analisa a SPEC e devolve perguntas priorizadas; o roteador as apresenta ao desenvolvedor e re-invoca o agente com as respostas, que atualiza a SPEC in-place.
- **Gate de arquitetura** — exige `AGENTS.md` / `docs/agents/` (ou avisa e marca `architecture_reference_status: missing`). Sem contexto de arquitetura o pipeline nunca planeja em silêncio.
- **Nunca escreve código de aplicação.** O fechamento aponta o handoff de execução:

```bash
./ralph.sh .spec/features/<slug>/PHASES.md
```

### `/ai-context` — árvore de contexto canônica

```
/ai-context [path] [+id] [-id] [--adopt]
```

Gera ou atualiza 10 artefatos a partir do **código implementado** (nunca lê `.spec/`):

| Artefato | Conteúdo |
|---|---|
| `AGENTS.md` | 6 seções: comandos, convenções, regras comportamentais, setup, referências, índice de docs |
| `CLAUDE.md` | Redirect ≤ 400 bytes para AGENTS.md |
| `docs/agents/project_overview.md` | Propósito, consumidores, fluxo macro |
| `docs/agents/architecture.md` | Estilo, layout, responsabilidades por camada |
| `docs/agents/tech_stack.md` | Linguagem, framework, runtime, tooling de teste |
| `docs/agents/coding_guidelines.md` | ≥ 3 padrões observados + enforcement |
| `docs/agents/domain_rules.md` | Regras de negócio como implementadas |
| `docs/agents/api_contracts.md` | Endpoints, payloads, formatos de mensagem |
| `docs/agents/data_model.md` | Entidades, storage, migrations |
| `docs/agents/dependencies.md` | Serviços externos, libs internas, infra compartilhada |

Regras centrais:

- **Idempotente** — upsert seguro; re-rodar atualiza só o que sofreu drift.
- **Documenta a realidade (AS IS)** — código, manifests, CI e configs são as únicas fontes; nunca inventa, nunca prescreve.
- **Contrato de ownership** — todo arquivo gerado carrega banner na linha 3. Arquivo sem banner (escrito à mão) nunca é sobrescrito; `--adopt` incorpora as regras concretas dele à árvore gerada e assume a posse.
- **Preserva blocos de terceiros** — regiões `<tag>...</tag>` (ex.: Laravel Boost) são re-anexadas verbatim na regeneração.
- Filtros `+id` / `-id` geram só um subconjunto (ex.: `/ai-context +AGENTS +architecture`).

## `scripts/ralph.sh` — orquestrador de execução

Lê um documento de fases, quebra pelo heading `## Phase N: <título>` e alimenta cada fase a uma sessão **nova** do Codex CLI ou Claude Code, sem interação humana, do início ao fim.

```bash
./scripts/ralph.sh [opções] [caminho-do-arquivo]
```

Sem argumento, resolve o input nesta ordem: `.spec/init/project-phases.md` → `.spec/project-phases.md` (layout pré-init, com aviso). Um `PHASES.md` de feature também é input válido.

> **Nota sobre autonomia e permissões**: o ralph é um orquestrador não assistido por design. Com o engine Claude, as sessões de implementação usam `--dangerously-skip-permissions`, portanto o agente pode editar arquivos e executar comandos no repositório sem pedir confirmação. Rode apenas em repositórios confiáveis, de preferência em branch descartável ou ambiente isolado (container/VM). Cada fase verde gera um commit separado, permitindo reverter somente o trabalho correspondente. A sessão verificadora do Gate 3 permanece restrita a ferramentas somente-leitura (`Read,Glob,Grep`).

### Perfil `system4u-autonomous`

Este perfil opt-in do Codex é destinado a execuções autônomas protegidas do System4u Portal. Ele não pede confirmações, mas **não** é YOLO irrestrito: a implementação usa `rtk codex exec -c 'approval_policy="never"' --sandbox workspace-write`, e a verificação continua somente-leitura.

Ele exige branch limpa e diferente de `main`, documento de fases explícito, `RALPH_VERIFY=always`, diretório novo de artefatos locais e uma allowlist relativa ao repositório. Rejeita exclusões, renomeações, `.env`, `.git`, `storage/`, `vendor/` e `node_modules/`; nunca faz push, merge, deploy, instala dependências ou roda migrations. As fases completas só recebem commit depois que os paths alterados passam pela allowlist.

```bash
scripts/ralph.sh --engine codex --profile system4u-autonomous --quiet \
  --allowed-paths-file controls/approved-paths.txt \
  --run-dir .ralph-system4u-20260728 \
  docs/approved-phases.md
```

A allowlist é baseada em linhas: arquivos exatos ou prefixos de diretório terminados em `/`; linhas vazias e comentários `#` são ignorados. Ela deve estar commitada antes da execução e não pode incluir glob, traversal, segredos, metadados Git ou diretórios gerados/de runtime.

### Invariantes

1. Cada fase **e** cada ciclo de correção roda em sessão nova, com prompt auto-contido. Nunca reutiliza sessão.
2. Zero perguntas — execução totalmente autônoma.
3. Fase só é "completa" quando passa pelos **4 gates mecânicos**, nunca pelo exit code do engine.
4. Limite de uso da API → espera o reset e re-executa a **mesma** fase, sem consumir ciclo de correção.
5. **Um commit por fase concluída** (`feat(phase-N): <título>`).

### Os 4 gates

| Gate | Pergunta | Como decide |
|---|---|---|
| 0 | O engine terminou de verdade? | claude: `is_error` no JSON de resultado; codex: exit code |
| 1 | A sessão escreveu código? | Assinatura da árvore antes/depois. **Sinal, não veredito** — fase já implementada faz o engine (corretamente) não escrever nada; o sinal alimenta a causa do ciclo de correção |
| 2 | A suite de testes passa? | Rodada **pelo ralph**, fora da sessão do agente — o agente não pode "mentir verde" |
| 3 | Cada task está de fato no código? | Sessão verificadora independente, read-only, que emite `TASK <n>: DONE/INCOMPLETE` por task. Roda em toda fase por default (`RALPH_VERIFY=always`); no engine claude usa modelo barato (haiku) |

Qualquer gate vermelho → **ciclo de correção**: uma sessão nova recebe a fase inteira + a causa real da falha (nunca "os testes falharam" genérico). O hard cap padrão é de **12 ciclos totais por fase**, contando a implementação inicial; `--max-cycles` ou `RALPH_MAX_CYCLES` definem outro limite explícito.

A primeira falha é a referência de progresso. A repetição consecutiva do mesmo gate + causa normalizada + assinatura da árvore incrementa a estagnação; gate, finding ou árvore diferentes zeram o contador. O padrão `--max-stalled-cycles 2` encerra após duas repetições corretivas consecutivas sem progresso. Assim, a fase termina verde, por hard cap, por estagnação ou por falha operacional/guardrail/commit que não pôde ser corrigida dentro desses limites; falhas de preflight abortam antes da primeira sessão.

Limite de uso é tratado separadamente: o ralph espera o reset e reexecuta a mesma sessão numerada sem consumir ciclo corretivo. Para evitar espera infinita, `RALPH_MAX_LIMIT_WAITS` limita as esperas consecutivas por fase (padrão: 20).

Gates verdes com árvore limpa → fase já estava implementada em HEAD: marcada como feita, sem commit.

### Configuração, runtime e logs do Gate 3

Modelo e reasoning do verificador seguem a precedência **flag > variável de ambiente > configuração herdada do engine**. No Codex, reasoning aceita `minimal`, `low`, `medium`, `high` ou `xhigh` e é enviado como `model_reasoning_effort`; sem override, modelo e reasoning são herdados. No Claude, o modelo padrão continua `haiku` e qualquer override de reasoning falha no preflight por não ser aplicável.

Antes de cada verificação, o terminal registra o estado `gravando`, engine, modelo/reasoning solicitados (ou `herdado`/`não aplicável`), sandbox `read-only` e caminho do log. Essa é a **configuração solicitada**. No Codex, o cabeçalho emitido pelo CLI revela o **runtime efetivo**; suas linhas de modelo e reasoning são espelhadas no terminal mesmo com `--quiet`, enquanto o cabeçalho completo permanece no log.

Os artefatos são separados por fase e ciclo em `.phases/logs/` por padrão, ou em `<run-dir>/logs/` com `system4u-autonomous`: `phase-NN.cycle-C.log` para implementação/correção, `phase-NN.test-C.log` para o Gate 2 e `phase-NN.verify-C.log` para o Gate 3. Todo Gate 3 executado exige um log de verificação existente e não vazio; ausência ou arquivo vazio deixa o gate vermelho com causa operacional explícita e o caminho correspondente no resumo.

### Autorização funcional versus operacional

Um finding de autenticação, autorização, isolamento, policy, gate ou permissão **da aplicação** é corrigível sem pausa quando aparece no texto aprovado da fase ou na causa do gate; o ciclo corretivo deve implementar e testar esse requisito funcional.

Isso não amplia a autorização operacional do agente. Continuam valendo as regras do projeto, sandbox, allowlist, limites de arquivos e proibições de ler segredos, fazer chamadas externas não autorizadas, migrations destrutivas, deploy, push, merge, tag ou release.

### Detecção do comando de teste (gate 2)

Primeira regra que resolver: `--test-cmd` → `RALPH_TEST_CMD` → detecção por manifest (Laravel Sail → `composer test` → `php artisan test` → `npm test` → `pytest` → `go test ./...` → `cargo test`) → nada resolvido = gate 2 pulado com aviso alto (gate 3 segura sozinho).

Projeto Laravel Sail: a suite roda **dentro do container** (`vendor/bin/sail test`); containers parados abortam no preflight — todo gate 2 falharia e queimaria ciclos à toa.

### Opções e variáveis

| Opção | Efeito |
|---|---|
| `--engine codex\|claude` | Engine de implementação (default: `codex`) |
| `--from N` | Começa na fase N (limpa o progresso das fases ≥ N) |
| `--keep-going` | Continua após fase falhar (cria commit `wip(phase-N)`; default: para) |
| `--max-cycles N` | Hard cap total por fase, incluindo a implementação inicial (default: 12) |
| `--max-stalled-cycles N` | Repetições corretivas consecutivas sem progresso após a primeira falha de referência (default: 2) |
| `--verify-model MODEL` | Modelo do Gate 3; prevalece sobre `RALPH_VERIFY_MODEL` |
| `--verify-reasoning EFFORT` | Reasoning do Gate 3 Codex (`minimal\|low\|medium\|high\|xhigh`); prevalece sobre `RALPH_VERIFY_REASONING` |
| `--test-cmd "<cmd>"` | Comando de teste do projeto (gate 2) |
| `--no-verify` | Desliga o gate 3 |
| `-q`, `--quiet` | Oculta o output bruto do Codex/Claude no terminal e imprime um resumo ao concluir cada fase; os logs completos continuam no diretório de logs dos artefatos ativo |
| `--profile system4u-autonomous` | Perfil Codex autônomo protegido: workspace-write, allowlist explícita, sem commits WIP nem limpeza destrutiva |
| `--allowed-paths-file <path>` | Allowlist relativa ao repositório obrigatória no `system4u-autonomous` |
| `--run-dir <path>` | Diretório local novo de artefatos do `system4u-autonomous` (padrão: `.ralph-system4u`) |
| `-h`, `--help` | Exibe o contrato operacional completo e sai |

| Variável | Efeito |
|---|---|
| `RALPH_TEST_CMD` | Comando de teste (gate 2) |
| `RALPH_VERIFY` | Gate 3: `always` (default) \| `auto` (economiza: só quando o gate 2 não basta) \| `off` |
| `RALPH_VERIFY_MODEL` | Modelo do verificador (default no Claude: `haiku`; no Codex, herdado) |
| `RALPH_VERIFY_REASONING` | Reasoning do verificador Codex; não aplicável ao Claude |
| `RALPH_MAX_CYCLES` | Hard cap total por fase (default: 12) |
| `RALPH_MAX_STALLED_CYCLES` | Repetições corretivas consecutivas sem progresso (default: 2) |
| `RALPH_QUIET` | `true` ou `false` (default: `false`) |
| `RALPH_MAX_LIMIT_WAITS` | Esperas consecutivas por limite de uso, por fase (default: 20) |
| `RALPH_LIMIT_WAIT_DEFAULT` | Fallback de espera em segundos (default: 1800) |
| `RALPH_LIMIT_BUFFER` | Segundos extras após o reset (default: 60) |

Durante cada sessão, o ralph exporta `RALPH_ENGINE`, `RALPH_PHASE_TITLE`, `RALPH_PHASE_NUM`, `RALPH_PHASE_TOTAL`, `RALPH_PHASE_ATTEMPT` e `RALPH_PHASE_MAX_ATTEMPTS` — úteis para hooks de notificação (ex.: n8n). `RALPH_PHASE_ATTEMPT=1` identifica a implementação inicial; retries por limite de uso preservam o mesmo valor. `RALPH_PHASE_MAX_ATTEMPTS` contém o hard cap efetivo resolvido por flag/env/default.

### Estado e progresso

Trabalho interno em `.phases/` (registrado em `.git/info/exclude`, sem tocar o `.gitignore` do projeto): fases quebradas, prompts, logs, manifest e `.progress`. O progresso sobrevive entre execuções, mas só vale para o **mesmo input** (stamp sha256) — documento de fases alterado zera o progresso.

Exit code: `0` = todas as fases verdes; `1` = alguma falhou ou abortou.

### Contrato de formato do input

Validado no preflight:

- ≥ 1 heading `## Phase N: <título>`
- Nenhum heading `## Phase ...` fora desse formato (heading torto some silenciosamente do run — o preflight aborta antes de gastar tokens)
- Sub-fases em `### Phase N.M:` (não viram sessão própria)
- Qualquer outro `## ` encerra a captura da fase anterior

## Agentes

Os comandos são **roteadores finos** — todo conhecimento de template vive nos agentes:

| Agente | Pipeline | Papel |
|---|---|---|
| `specifier` | `/plan` §5 | Descrição confirmada + ACs → SPEC.md formal (GEARS, RIGID/FLEXIBLE) |
| `clarifier` | `/plan` §6 | QA adversarial de requisitos: analisa ambiguidades, resolve com as respostas do dev |
| `planner` | `/plan` §7 | SPEC → PLAN.md + PHASES.md + contratos; read-only sobre o código |
| `ai-context-inspector` | `/ai-context` §3 | Varredura read-only do repo → digest estruturado |
| `ai-context-core` | `/ai-context` §4 | Digest → `AGENTS.md` + `CLAUDE.md` |
| `ai-context-docs` | `/ai-context` §4 | Digest → 8 arquivos `docs/agents/*.md` |

Os dois writers de `/ai-context` rodam em paralelo (arquivos disjuntos, digest read-only).

## Estrutura do repositório

```
.claude-plugin/plugin.json     manifest do plugin
commands/
  init.md                      /init (roteador diagnóstico)
  init/                        /init:project-description, user-stories,
                               database-schema, project-phases
  plan.md                      /plan (roteador do pipeline de planejamento)
  ai-context.md                /ai-context (roteador da árvore de contexto)
agents/                        specifier, clarifier, planner,
                               ai-context-{inspector,core,docs}
scripts/
  ralph.sh                     orquestrador de execução por fases
  test-ralph.sh                suite red/green do ralph com engine mock
  check-init-drift.sh          guarda contra drift textual das regras
                               duplicadas nos comandos init
  check-shell.sh               bash -n + shellcheck em scripts/*.sh
docs/plans/                    planos de hardening internos do harness
```

## Desenvolvimento

```bash
scripts/test-ralph.sh        # suite do ralph.sh — binários fake `claude`/`codex`
                             # no PATH, zero rede, zero token; exit 0 = verde
scripts/test-ralph.sh <caso> # roda um caso específico
scripts/check-shell.sh       # bash -n em todos os scripts + shellcheck se disponível
scripts/check-init-drift.sh  # âncoras verbatim das regras compartilhadas dos init:*
```

Sobre o `check-init-drift.sh`: os quatro `commands/init/*.md` **inlinam de propósito** as mesmas regras de entrevista, idioma, re-run e staleness — comandos de plugin precisam ser auto-contidos em runtime (executam dentro do projeto do desenvolvedor, onde a raiz do plugin não é alcançável via `@`-includes). O custo dessa duplicação é drift silencioso; o script torna o drift barulhento.

## Princípios de design

- **Roteadores finos, agentes donos do conteúdo** — comandos orquestram, verificam artefatos em disco e reportam; nunca autoram SPEC/PLAN/docs.
- **Confie, mas verifique** — todo artefato entregue por agente é validado mecanicamente (existência, headings, contagens) pelo roteador.
- **Realidade ≠ intenção** — `/ai-context` documenta só o implementado; `.spec/` é invisível para ele. A cadeia `.spec/` documenta a intenção.
- **Sem escrita em git pelos comandos** — o desenvolvedor revisa com `git diff` e commita manualmente. O único que commita é o `ralph.sh`, por design (um commit por fase validada).
- **Sem segredos** — `.env` nunca é lido; nomes de variáveis vêm de `.env.example`.
- **Staleness explícita, nunca bloqueante** — stamps sha256 detectam insumos desatualizados; a decisão é sempre do desenvolvedor.
