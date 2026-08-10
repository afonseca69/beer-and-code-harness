#!/usr/bin/env bash
#
# test-ralph.sh — suite red/green do scripts/ralph.sh com engine mock.
#
# Nenhuma chamada de rede, nenhum token gasto: binarios fake `claude` e `codex`
# entram no PATH e o comportamento e escolhido por MOCK_SCENARIO.
#
# Uso: scripts/test-ralph.sh [nome-do-caso]   (exit 0 = tudo verde)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# RALPH_BIN permite apontar para uma copia patchada (prova red dos testes).
RALPH="${RALPH_BIN:-$ROOT/scripts/ralph.sh}"
ONLY="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
CURRENT=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

ok()   { PASS=$((PASS + 1)); echo -e "  ${GREEN}ok${NC}   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo -e "  ${RED}FAIL${NC} $1"; }

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then ok "$msg"; else bad "$msg (esperado '$expected', veio '$actual')"; fi
}

assert_contains() {
  local haystack_file="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" "$haystack_file"; then ok "$msg"; else bad "$msg (nao achou '$needle')"; fi
}

assert_not_contains() {
  local haystack_file="$1" needle="$2" msg="$3"
  if grep -qF -- "$needle" "$haystack_file"; then bad "$msg (achou '$needle')"; else ok "$msg"; fi
}

# ---------------------------------------------------------------------------
# Mock engine — vale para claude e codex (dispatch por basename)
# ---------------------------------------------------------------------------

make_mocks() {
  local bin="$1"
  mkdir -p "$bin"

  cat > "$bin/mock-engine" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail

name=$(basename "$0")
state="${MOCK_STATE:?}"
scenario="${MOCK_SCENARIO:-ok}"
prompt=""
verify=0
sandbox=""

bump() {
  local f="$state/$1" n=0
  [ -f "$f" ] && n=$(cat "$f")
  n=$((n + 1))
  echo "$n" > "$f"
  echo "$n"
}

model=""
reasoning=""

if [ "$name" = "claude" ]; then
  # claude -p real le stdin quando nao e TTY: se o ralph nao redirecionar
  # < /dev/null, o mock engole o stream de quem chamou (ex: manifest do loop).
  [ -t 0 ] || cat > /dev/null
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p) prompt="$2"; shift 2 ;;
      --allowedTools) verify=1; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --output-format) shift 2 ;;
      *) shift ;;
    esac
  done
else
  printf '%s\n' "$@" >> "$state/codex_args"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sandbox)
        sandbox="$2"
        [ "$2" = "read-only" ] && verify=1
        shift 2
        ;;
      --model) model="$2"; shift 2 ;;
      -c)
        if [[ "$2" == model_reasoning_effort=* ]]; then
          reasoning="${2#*=}"
          reasoning="${reasoning#\"}"
          reasoning="${reasoning%\"}"
        fi
        shift 2
        ;;
      *) shift ;;
    esac
  done
  prompt=$(cat)
fi

grep -q '^RALPH_VERIFY' <<< "$prompt" && verify=1

# Grava o modelo pedido para a sessao verificadora (assert do teste de modelo).
if [ "$verify" -eq 1 ] && [ -n "$model" ]; then
  echo "$model" > "$state/verify_model"
fi
if [ "$verify" -eq 1 ] && [ -n "$reasoning" ]; then
  echo "$reasoning" > "$state/verify_reasoning"
fi
if [ "$verify" -eq 1 ]; then
  printf '%s|%s\n' "${model:-<inherited>}" "${reasoning:-<inherited>}" >> "$state/verify_configs"
else
  printf '%s|%s\n' "${model:-<inherited>}" "${reasoning:-<inherited>}" >> "$state/impl_configs"
fi

# --- verificador independente ------------------------------------------------
# Verifica o CODIGO REAL, como o verificador de verdade: sem arquivo de
# implementacao no repo, a fase esta incompleta.
if [ "$verify" -eq 1 ]; then
  n=$(bump verify_calls)
  tasks=$(grep -cE '^[[:space:]]*- \[[ x]\]' <<< "$prompt")

  if [ "$scenario" = "verify-log-empty" ] || [ "$scenario" = "verify-log-missing" ]; then
    exit 0
  fi

  if [ "$name" = "codex" ]; then
    echo "OpenAI Codex mock"
    echo "--------"
    echo "model: ${model:-gpt-mock-inherited}"
    echo "provider: mock"
    echo "approval: never"
    echo "sandbox: read-only"
    echo "reasoning effort: ${reasoning:-medium}"
    echo "reasoning summaries: none"
    echo "--------"
  fi

  implemented=0
  compgen -G "src/impl-*.txt" > /dev/null 2>&1 && implemented=1

  if [ "$implemented" -eq 0 ]; then
    for i in $(seq 1 "$tasks"); do echo "TASK $i: INCOMPLETE — nenhum codigo encontrado"; done
    exit 0
  fi

  if [ "$scenario" = "layered-findings" ]; then
    case "$n" in
      1)
        echo "TASK 1: INCOMPLETE — falta a camada de persistencia"
        echo "TASK 2: DONE"
        ;;
      2)
        echo "TASK 1: DONE"
        echo "TASK 2: INCOMPLETE — falta a camada de servico"
        ;;
      3)
        echo "TASK 1: INCOMPLETE — falta validar workspace autorizado"
        echo "TASK 2: DONE"
        ;;
      *)
        for i in $(seq 1 "$tasks"); do echo "TASK $i: DONE"; done
        ;;
    esac
  elif [ "$scenario" = "stagnant-finding" ]; then
    echo "TASK 1: INCOMPLETE — mesmo finding sem progresso"
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [ "$scenario" = "normalized-finding" ]; then
    if [ "$n" -eq 1 ]; then
      echo "TASK 1: INCOMPLETE — mesmo finding normalizado"
    else
      echo "TASK 1: INCOMPLETE — mesmo   finding   normalizado"
    fi
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [ "$scenario" = "finding-progress" ]; then
    case "$n" in
      1|2) echo "TASK 1: INCOMPLETE — finding camada A" ;;
      3|4) echo "TASK 1: INCOMPLETE — finding camada B" ;;
      *) echo "TASK 1: DONE" ;;
    esac
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [ "$scenario" = "tree-progress" ]; then
    if [ "$n" -le 2 ]; then
      echo "TASK 1: INCOMPLETE — finding constante com arvore evoluindo"
    else
      echo "TASK 1: DONE"
    fi
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [ "$scenario" = "gate-progress" ]; then
    if [ "$n" -eq 1 ]; then
      echo "TASK 1: INCOMPLETE — finding depois do gate 2"
    else
      echo "TASK 1: DONE"
    fi
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [ "$scenario" = "workspace-authorized" ]; then
    if [ "$n" -eq 1 ]; then
      echo "TASK 1: INCOMPLETE — falta validar workspace autorizado"
    else
      echo "TASK 1: DONE"
    fi
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [[ "$scenario" == "verify-incomplete-once" || "$scenario" == "verify-incomplete-tracked" ]] && [ "$n" -eq 1 ]; then
    echo "TASK 1: INCOMPLETE — o arquivo nao foi criado"
    for i in $(seq 2 "$tasks"); do echo "TASK $i: DONE"; done
  elif [ "$scenario" = "verify-duplicate" ]; then
    for i in $(seq 1 "$tasks"); do echo "TASK $i: DONE"; done
    for i in $(seq 1 "$tasks"); do echo "TASK $i: DONE"; done
  else
    for i in $(seq 1 "$tasks"); do echo "TASK $i: DONE"; done
  fi
  exit 0
fi

# --- sessao de implementacao -------------------------------------------------
n=$(bump impl_calls)

emit_claude_ok()    { echo '{"type":"result","subtype":"success","is_error":false,"result":"implementado"}'; }
emit_claude_limit() { echo "{\"type\":\"result\",\"subtype\":\"error\",\"is_error\":true,\"result\":\"Claude AI usage limit reached|$1\"}"; }

case "$scenario" in
  limit-epoch)
    if [ "$n" -eq 1 ]; then
      emit_claude_limit "$(date +%s)"
      exit 1
    fi
    ;;
  limit-generic)
    if [ "$n" -eq 1 ]; then
      echo "Rate limit reached. Try again later."
      exit 1
    fi
    ;;
esac

if [ "$name" = "codex" ]; then
  echo "OpenAI Codex mock"
  echo "--------"
  echo "model: ${model:-gpt-mock-inherited}"
  echo "provider: mock"
  echo "approval: never"
  echo "sandbox: ${sandbox:-danger-full-access}"
  echo "reasoning effort: ${reasoning:-medium}"
  echo "reasoning summaries: none"
  echo "--------"
fi

# stall-after-red: escreve no 1o ciclo (teste vermelho), depois trava sem
# escrever nada. already-done: o codigo ja existe em HEAD, o engine nao escreve.
write=1
[ "$scenario" = "empty-diff" ] && write=0
[ "$scenario" = "already-done" ] && write=0
[ "$scenario" = "stall-after-red" ] && [ "$n" -gt 1 ] && write=0
[ "$scenario" = "stagnant-finding" ] && [ "$n" -gt 1 ] && write=0
[ "$scenario" = "normalized-finding" ] && [ "$n" -gt 1 ] && write=0
[ "$scenario" = "finding-progress" ] && [ "$n" -gt 1 ] && write=0
[ "$scenario" = "gate-progress" ] && [ "$n" -gt 1 ] && write=0
[ "$scenario" = "workspace-authorized" ] && [ "$n" -gt 1 ] && write=0

if [ "$write" -eq 1 ]; then
  mkdir -p src
  echo "impl $n" > "src/impl-$n.txt"
fi
if [ "$scenario" = "verify-incomplete-tracked" ]; then
  echo "modificado $n" > tracked.txt
fi

if [ "$scenario" = "false-429" ]; then
  # 429 no MEIO do log: e output de teste do projeto, nao limite de uso.
  echo "FAIL tests/HttpClientTest: expected 429 Too Many Requests, got 200"
  for i in $(seq 1 25); do echo "linha de ruido $i"; done
  echo "Suite corrigida. Done."
  exit 0
fi

if [ "$name" = "claude" ]; then emit_claude_ok; else echo "Done."; fi
exit 0
MOCK

  chmod +x "$bin/mock-engine"
  cp "$bin/mock-engine" "$bin/claude"
  cp "$bin/mock-engine" "$bin/codex"

  cat > "$bin/tee" <<'TEEMOCK'
#!/usr/bin/env bash
set -euo pipefail

if [ "${MOCK_SCENARIO:-}" = "verify-log-missing" ]; then
  for path in "$@"; do
    if [[ "$path" == *verify-*.log ]]; then
      cat > /dev/null
      rm -f -- "$path"
      exit 0
    fi
  done
fi

exec /usr/bin/tee "$@"
TEEMOCK
  chmod +x "$bin/tee"

  cat > "$bin/rtk" <<'RTK'
#!/usr/bin/env bash
set -euo pipefail

state="${MOCK_STATE:?}"
[ "${1:-}" = "codex" ] || exit 64
shift

count=0
[ -f "$state/rtk_calls" ] && count=$(cat "$state/rtk_calls")
echo $((count + 1)) > "$state/rtk_calls"

exec "$(dirname "$0")/codex" "$@"
RTK
  chmod +x "$bin/rtk"
}

make_testcmd() {
  cat > "$1" <<'TESTCMD'
#!/usr/bin/env bash
set -uo pipefail
state="${MOCK_STATE:?}"
scenario="${MOCK_SCENARIO:-ok}"
# sail test real (docker compose exec) anexa stdin: mesmo risco do claude -p.
[ -t 0 ] || cat > /dev/null
f="$state/test_calls"; n=0
[ -f "$f" ] && n=$(cat "$f")
n=$((n + 1)); echo "$n" > "$f"

if [ "$scenario" = "test-red-once" ] || [ "$scenario" = "stall-after-red" ] || [ "$scenario" = "gate-progress" ]; then
  if [ "$n" -eq 1 ]; then
    echo "1 failing test: ExpectedFooTest"
    exit 1
  fi
fi
echo "all green"
exit 0
TESTCMD
  chmod +x "$1"
}

PHASES_FIXTURE='# Test Project — Project Phases

<!-- inputs: project-description.md@sha256:000000000000 -->

## Overview

Projeto de teste.

## Phase 1: Foundation

- [ ] **Task:** cria o arquivo A
  - **Acceptance criteria:**
    - o arquivo existe
- [ ] **Task:** cria o arquivo B
  - **Acceptance criteria:**
    - o arquivo existe

## Phase 2: Feature

- [ ] **Task:** cria o arquivo C
  - **Acceptance criteria:**
    - o arquivo existe

## Open Questions

- nenhuma
'

SINGLE_PHASES_FIXTURE='# Test Project — Project Phases

<!-- inputs: project-description.md@sha256:000000000000 -->

## Overview

Projeto de teste.

## Phase 1: Progressive Remediation

- [ ] **Task:** cria o arquivo A
  - **Acceptance criteria:**
    - o arquivo existe
- [ ] **Task:** cria o arquivo B
  - **Acceptance criteria:**
    - o arquivo existe

## Open Questions

- nenhuma
'

# Fixture de projeto Laravel + Sail. `sail ps` responde conforme SAIL_UP.
make_sail_fixture() {
  local repo="$1" up="$2"

  touch "$repo/artisan"
  cat > "$repo/composer.json" <<'JSON'
{
  "require-dev": { "laravel/sail": "^1.0" },
  "scripts": { "test": "phpunit" }
}
JSON

  mkdir -p "$repo/vendor/bin"
  cat > "$repo/vendor/bin/sail" <<SAILMOCK
#!/usr/bin/env bash
set -uo pipefail
if [ "\${1:-}" = "ps" ]; then
  if [ "$up" = "up" ]; then
    echo "NAME                IMAGE            STATUS"
    echo "proj-laravel.test-1 sail-8.3/app     Up 2 hours"
    exit 0
  fi
  echo "Sail is not running."
  exit 1
fi
if [ "\${1:-}" = "test" ]; then
  exec "\$MOCK_TEST_CMD"
fi
exit 0
SAILMOCK
  chmod +x "$repo/vendor/bin/sail"
}

# new_case <nome> -> ecoa o diretorio do repo fixture
new_case() {
  local name="$1"
  local dir="$TMP/$name"
  mkdir -p "$dir/repo" "$dir/state" "$dir/bin"
  make_mocks "$dir/bin"
  make_testcmd "$dir/test.sh"

  (
    cd "$dir/repo" || exit 1
    git init -q
    git config user.email "test@ralph"
    git config user.name "Ralph Test"
    mkdir -p .spec/init
    printf '%s' "$PHASES_FIXTURE" > .spec/init/project-phases.md
    git add -A
    git commit -q -m "chore: fixture"
  )
  echo "$dir"
}

use_single_phase_fixture() {
  local dir="$1"
  (
    cd "$dir/repo" || exit 1
    printf '%s' "$SINGLE_PHASES_FIXTURE" > .spec/init/project-phases.md
    git add -A
    git commit -q -m "chore: single phase fixture"
  )
}

# run_ralph <dir> <scenario> [args...] -> ecoa o exit code; log em <dir>/out.log
run_ralph() {
  local dir="$1" scenario="$2"; shift 2
  local rc=0
  (
    cd "$dir/repo" || exit 1
    PATH="$dir/bin:$PATH" \
    MOCK_STATE="$dir/state" \
    MOCK_SCENARIO="$scenario" \
    MOCK_TEST_CMD="$dir/test.sh" \
    RALPH_LIMIT_WAIT_DEFAULT=1 \
    RALPH_LIMIT_BUFFER=1 \
    RALPH_MODEL="${CASE_MODEL:-}" \
    RALPH_REASONING="${CASE_REASONING:-}" \
    RALPH_VERIFY="${CASE_VERIFY:-}" \
    RALPH_VERIFY_MODEL="${CASE_VERIFY_MODEL:-}" \
    RALPH_VERIFY_REASONING="${CASE_VERIFY_REASONING:-}" \
    RALPH_MAX_CYCLES="${CASE_MAX_CYCLES:-}" \
    RALPH_MAX_STALLED_CYCLES="${CASE_MAX_STALLED_CYCLES:-}" \
      bash "$RALPH" "$@" > "$dir/out.log" 2>&1
  ) || rc=$?
  echo "$rc"
}

commits() { git -C "$1/repo" rev-list --count HEAD; }

case_enabled() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

header() { CURRENT="$1"; echo -e "\n${YELLOW}== $1${NC}"; }

# ---------------------------------------------------------------------------
# 1. Fase ok de primeira -> 1 commit por fase, progresso gravado
# ---------------------------------------------------------------------------
if case_enabled ok-first; then
  header "1. fase ok de primeira"
  d=$(new_case ok-first)
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "exit 0"
  assert_eq 3 "$(commits "$d")" "2 commits de fase (1 fixture + 2)"
  assert_contains "$d/repo/.phases/.progress" "phase-01.md" "progresso registra phase-01"
  assert_contains "$d/repo/.phases/.progress" "phase-02.md" "progresso registra phase-02"
  assert_eq "feat(phase-2): Feature" "$(git -C "$d/repo" log -1 --pretty=%s)" "mensagem de commit da ultima fase"
  assert_eq 2 "$(cat "$d/state/impl_calls")" "1 sessao de implementacao por fase (2 fases)"
  assert_eq 2 "$(cat "$d/state/verify_calls")" "gate 3 (default always) rodou em toda fase"
  assert_contains "$d/out.log" "RESUMO DE ENTREGA" "relatorio final inclui resumo consolidado"
  assert_contains "$d/out.log" "testes: Gate 2 verde" "resumo registra a validacao da suite"
  assert_contains "$d/out.log" "verificacao: Gate 3 verde (2/2 tasks)" "resumo registra a verificacao independente"
  assert_contains "$d/out.log" "verificacao: Gate 3 verde (2/2 tasks) | ciclo: 1 | log: .phases/logs/phase-01.verify-1.log" "resumo verde registra ciclo e log"
  assert_contains "$d/out.log" "commit: " "resumo registra o commit da fase"
  assert_contains "$d/out.log" "arquivos: src/impl-1.txt" "resumo registra os arquivos do commit"
  assert_contains "$d/out.log" "Pendencias do run: nenhuma." "resumo declara ausencia de pendencias"
fi

# ---------------------------------------------------------------------------
# 2. Gate 2 vermelho 1x -> ciclo de correcao -> verde -> 1 commit so
# ---------------------------------------------------------------------------
if case_enabled test-red-once; then
  header "2. gate 2 vermelho uma vez -> ciclo de correcao"
  d=$(new_case test-red-once)
  rc=$(run_ralph "$d" test-red-once --engine claude --test-cmd "$d/test.sh" --max-cycles 2)
  assert_eq 0 "$rc" "exit 0"
  assert_eq 3 "$(commits "$d")" "1 commit por fase (ciclo intermediario nao commita)"
  assert_contains "$d/out.log" "Gate 2 vermelho" "gate 2 reportado vermelho"
  assert_contains "$d/out.log" "Ciclo de correcao 2/2" "entrou em ciclo de correcao"
  # o prompt de correcao carrega a causa REAL, nao "os testes falharam" generico
  assert_contains "$d/repo/.phases/prompts/phase-01.cycle-2.txt" "ExpectedFooTest" "prompt de correcao carrega a saida do teste"
  assert_contains "$d/repo/.phases/prompts/phase-01.cycle-2.txt" "## Fase a completar" "prompt de correcao e auto-contido (fase inteira)"
  # logs por ciclo, nunca sobrescritos
  test -f "$d/repo/.phases/logs/phase-01.cycle-1.log" && test -f "$d/repo/.phases/logs/phase-01.cycle-2.log" \
    && ok "logs por ciclo preservados" || bad "logs por ciclo preservados"
fi

# ---------------------------------------------------------------------------
# 3. Engine nao escreve nada e a fase esta incompleta -> falha sem commit
#    (gate 1 sinaliza; quem reprova e o verificador, contra o codigo real)
# ---------------------------------------------------------------------------
if case_enabled empty-diff; then
  header "3. engine nao escreve nada + fase incompleta -> falha sem commit"
  d=$(new_case empty-diff)
  rc=$(run_ralph "$d" empty-diff --engine claude --test-cmd "$d/test.sh" --max-cycles 2)
  assert_eq 1 "$rc" "exit 1"
  assert_eq 1 "$(commits "$d")" "nenhum commit criado (sem --allow-empty)"
  assert_contains "$d/out.log" "a sessao nao escreveu nada" "gate 1 sinalizou a sessao vazia"
  assert_contains "$d/out.log" "Gate 3 vermelho" "verificador reprovou contra o codigo real"
  assert_contains "$d/out.log" "Parando na primeira fase que falhou" "politica default = parar"
  assert_contains "$d/repo/.phases/prompts/phase-01.cycle-2.txt" "sem alterar nenhum arquivo" "causa do ciclo cita a sessao vazia"
  assert_contains "$d/out.log" "arquivos: nenhum" "fase sem mudancas continua reportando nenhum path"
fi

# ---------------------------------------------------------------------------
# 4. Verificador INCOMPLETE 1x -> ciclo -> DONE -> commit
# ---------------------------------------------------------------------------
if case_enabled verify-incomplete; then
  header "4. verificador INCOMPLETE uma vez -> ciclo -> DONE"
  d=$(new_case verify-incomplete)
  rc=$(run_ralph "$d" verify-incomplete-once --engine claude --test-cmd "$d/test.sh" --max-cycles 2)
  assert_eq 0 "$rc" "exit 0"
  assert_eq 3 "$(commits "$d")" "1 commit por fase"
  assert_contains "$d/out.log" "Gate 3 vermelho" "gate 3 reportado vermelho"
  assert_contains "$d/repo/.phases/prompts/phase-01.cycle-2.txt" "TASK 1: INCOMPLETE" "prompt de correcao carrega as tasks incompletas verbatim"
  test -f "$d/repo/.phases/logs/phase-01.verify-1.log" && ok "log do verificador por ciclo" || bad "log do verificador por ciclo"
fi

# ---------------------------------------------------------------------------
# 4b. Codex pode repetir a resposta final no stream combinado. O Gate 3
#     consolida pelo numero da task antes de validar a cobertura.
# ---------------------------------------------------------------------------
if case_enabled verify-duplicate; then
  header "4b. verificador duplicado e consolidado por task"
  d=$(new_case verify-duplicate)
  rc=$(run_ralph "$d" verify-duplicate --engine codex --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0"
  assert_eq 3 "$(commits "$d")" "fases commitadas com uma linha efetiva por task"
  assert_contains "$d/out.log" "Gate 3 — 2/2 tasks confirmadas no codigo" "cobertura usa tasks unicas"
  assert_not_contains "$d/out.log" "cobertura incompleta" "duplicacao nao gera falso negativo"
fi

# ---------------------------------------------------------------------------
# 4c. Gate 3 com 11+ tasks nao pode filtrar lexicograficamente apenas
#     TASK 1, 10 e 11.
# ---------------------------------------------------------------------------
if case_enabled verify-eleven-tasks; then
  header "4c. gate 3 confirma 11/11 tasks"
  d=$(new_case verify-eleven-tasks)
  (
    cd "$d/repo" || exit 1
    {
      printf '# Test Project — Project Phases\n\n'
      printf '<!-- inputs: project-description.md@sha256:000000000000 -->\n\n'
      printf '## Phase 1: Eleven Tasks\n\n'
      for i in $(seq 1 11); do
        printf -- '- [ ] **Task:** item %s\n' "$i"
        printf '  - **Acceptance criteria:**\n'
        printf '    - item %s existe\n' "$i"
      done
    } > .spec/init/project-phases.md
    git add -A && git commit -q -m "chore: fixture com 11 tasks"
  )
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0"
  assert_contains "$d/out.log" "Gate 3 — 11/11 tasks confirmadas no codigo" "gate 3 confirmou todas as 11 tasks"
  assert_not_contains "$d/out.log" "cobertura incompleta" "nao reportou cobertura incompleta"
fi

# ---------------------------------------------------------------------------
# 5. Limite com epoch -> espera -> re-executa a MESMA fase sem consumir ciclo
# ---------------------------------------------------------------------------
if case_enabled limit-epoch; then
  header "5. limite com epoch -> espera -> mesma fase"
  d=$(new_case limit-epoch)
  # --max-cycles 1: se a espera consumisse um ciclo, a fase falharia
  rc=$(run_ralph "$d" limit-epoch --engine claude --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0 (limite nao consome ciclo)"
  assert_eq 3 "$(commits "$d")" "fases commitadas apos a espera"
  assert_contains "$d/out.log" "Limite de uso atingido" "limite detectado"
  assert_contains "$d/out.log" "Reset previsto para" "epoch de reset extraido do log"
fi

# ---------------------------------------------------------------------------
# 6. Limite generico sem epoch -> fallback wait
# ---------------------------------------------------------------------------
if case_enabled limit-generic; then
  header "6. limite generico sem epoch -> fallback"
  d=$(new_case limit-generic)
  rc=$(CASE_MODEL=retry-model CASE_REASONING=low run_ralph "$d" limit-generic --engine codex --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0"
  assert_contains "$d/out.log" "Sem horario de reset no output" "usou o fallback de espera"
  assert_eq 3 "$(commits "$d")" "fases commitadas apos a espera"
  assert_eq $'retry-model|low\nretry-model|low\nretry-model|low' "$(cat "$d/state/impl_configs")" "retry de limite preserva modelo e reasoning nas sessoes mutaveis"
fi

# ---------------------------------------------------------------------------
# 7. "429 Too Many Requests" no MEIO do log -> NAO dispara espera (regressao)
# ---------------------------------------------------------------------------
if case_enabled false-429; then
  header "7. 429 no meio do log nao dispara espera"
  d=$(new_case false-429)
  start=$(date +%s)
  rc=$(run_ralph "$d" false-429 --engine codex --test-cmd "$d/test.sh" --max-cycles 1)
  elapsed=$(($(date +%s) - start))
  assert_eq 0 "$rc" "exit 0"
  assert_not_contains "$d/out.log" "Limite de uso atingido" "nao interpretou 429 de teste como limite"
  assert_contains "$d/repo/.phases/logs/phase-01.cycle-1.log" "429 Too Many Requests" "o 429 realmente estava no log"
  [ "$elapsed" -lt 5 ] && ok "sem espera (${elapsed}s)" || bad "sem espera (${elapsed}s)"
fi

# ---------------------------------------------------------------------------
# 8. Segunda execucao com mesmo input -> fases feitas puladas (resume vivo)
# ---------------------------------------------------------------------------
if case_enabled resume; then
  header "8. resume: segunda execucao pula fases feitas"
  d=$(new_case resume)
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "primeira execucao verde"
  before=$(commits "$d")
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "segunda execucao verde"
  assert_eq "$before" "$(commits "$d")" "nenhum commit novo"
  assert_contains "$d/out.log" "Progresso anterior preservado" "progresso preservado (input inalterado)"
  assert_contains "$d/out.log" "(ja completada)" "fases puladas"
fi

# ---------------------------------------------------------------------------
# 9. Input mutado entre execucoes -> progresso invalidado com aviso
# ---------------------------------------------------------------------------
if case_enabled resume-invalidated; then
  header "9. input mutado -> progresso invalidado"
  d=$(new_case resume-invalidated)
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "primeira execucao verde"
  before=$(commits "$d")
  (
    cd "$d/repo" || exit 1
    printf '\n## Phase 3: Extra\n\n- [ ] **Task:** cria o arquivo D\n  - **Acceptance criteria:**\n    - o arquivo existe\n' >> .spec/init/project-phases.md
    git add -A && git commit -q -m "chore: nova fase"
  )
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "segunda execucao verde"
  assert_contains "$d/out.log" "progresso zerado" "progresso invalidado com aviso"
  assert_eq $((before + 4)) "$(commits "$d")" "3 fases re-executadas + commit da mutacao"
fi

# ---------------------------------------------------------------------------
# 10. Arvore suja no preflight -> abort antes de qualquer sessao
# ---------------------------------------------------------------------------
if case_enabled dirty-tree; then
  header "10. arvore suja -> abort no preflight"
  d=$(new_case dirty-tree)
  echo "trabalho nao commitado" > "$d/repo/rascunho.txt"
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 1 "$rc" "exit 1"
  assert_contains "$d/out.log" "Arvore de trabalho suja" "abortou com instrucao"
  test -f "$d/state/impl_calls" && bad "nenhuma sessao de engine iniciada" || ok "nenhuma sessao de engine iniciada"
fi

# ---------------------------------------------------------------------------
# 11. Contrato de formato do input -> abort antes de gastar token
# ---------------------------------------------------------------------------
if case_enabled bad-format; then
  header "11. heading de fase torto -> abort no preflight"
  d=$(new_case bad-format)
  (
    cd "$d/repo" || exit 1
    sed -i 's/^## Phase 2: Feature$/## Phase Two — Feature/' .spec/init/project-phases.md
    git add -A && git commit -q -m "chore: heading torto"
  )
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  # "## Phase Two" nao casa com '^## Phase [0-9]+: ' -> heading malformado
  assert_eq 1 "$rc" "exit 1"
  assert_contains "$d/out.log" "Contrato de formato violado" "abortou por formato invalido"
  test -f "$d/state/impl_calls" && bad "nenhuma sessao de engine iniciada" || ok "nenhuma sessao de engine iniciada"
fi

# ---------------------------------------------------------------------------
# 12. Ciclo de correcao que nao escreve nada, mas o codigo do ciclo anterior
#     esta completo e verde -> a fase passa (o verificador manda, nao o diff)
# ---------------------------------------------------------------------------
if case_enabled stall-after-red; then
  header "12. ciclo sem escrita + codigo completo -> gate 3 decide, fase passa"
  d=$(new_case stall-after-red)
  rc=$(run_ralph "$d" stall-after-red --engine claude --test-cmd "$d/test.sh" --max-cycles 2)
  assert_eq 0 "$rc" "exit 0"
  # o mock so escreve na 1a sessao: fase 1 commita apos o ciclo 2; fase 2 cai
  # no caminho "ja implementada" (o verificador ve o codigo e aprova)
  assert_eq 2 "$(commits "$d")" "1 commit (fase 1); fase 2 nao tinha o que commitar"
  assert_contains "$d/out.log" "Gate 2 vermelho" "o ciclo comecou por um gate 2 vermelho"
  assert_contains "$d/out.log" "a sessao nao escreveu nada" "gate 1 sinalizou a sessao vazia do ciclo 2"
  assert_contains "$d/out.log" "feat(phase-1)" "fase 1 commitada apos o ciclo de correcao"
fi

# ---------------------------------------------------------------------------
# 17. Fase JA implementada em HEAD (run anterior commitada) -> reconhecida
#     sem commit, sem falhar. Regressao do bug real: o engine nao escreve
#     porque nao ha o que escrever, e o gate 1 reprovava isso.
# ---------------------------------------------------------------------------
if case_enabled already-done; then
  header "17. fase ja implementada em HEAD -> reconhecida sem commit"
  d=$(new_case already-done)
  # simula a run anterior: codigo implementado e commitado a mao, progress vazio
  mkdir -p "$d/repo/src"
  echo "impl previo" > "$d/repo/src/impl-1.txt"
  git -C "$d/repo" add -A && git -C "$d/repo" commit -q -m "feat: trabalho da run anterior"
  before=$(commits "$d")

  rc=$(run_ralph "$d" already-done --engine claude --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0 (nao reprova fase ja implementada)"
  assert_contains "$d/out.log" "JA IMPLEMENTADA" "reconheceu a fase como feita"
  assert_eq "$before" "$(commits "$d")" "nenhum commit criado (nada a commitar)"
  assert_contains "$d/repo/.phases/.progress" "phase-01.md" "progresso registra a fase"
  assert_contains "$d/repo/.phases/.progress" "phase-02.md" "progresso registra a fase seguinte"
fi

# ---------------------------------------------------------------------------
# 22. --quiet oculta o output dos engines, preserva os logs e mostra resumo
#     para cada fase concluida.
# ---------------------------------------------------------------------------
if case_enabled quiet; then
  header "22. --quiet preserva logs e resume cada fase"
  d=$(new_case quiet)
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh" --quiet)
  assert_eq 0 "$rc" "exit 0"
  assert_contains "$d/out.log" "[resumo] Fase 1/2: Foundation" "resumo da primeira fase"
  assert_contains "$d/out.log" "[resumo] Fase 2/2: Feature" "resumo da segunda fase"
  assert_not_contains "$d/out.log" '"result":"implementado"' "output bruto do engine nao aparece no terminal"
  assert_contains "$d/repo/.phases/logs/phase-01.cycle-1.log" '"result":"implementado"' "output bruto do engine fica no log"
fi

# ---------------------------------------------------------------------------
# 23. Engine Codex sempre passa pelo RTK, tanto na implementacao quanto na
#     verificacao independente.
# ---------------------------------------------------------------------------
if case_enabled rtk-codex; then
  header "23. engine codex passa por rtk codex"
  d=$(new_case rtk-codex)
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "exit 0"
  assert_eq 4 "$(cat "$d/state/rtk_calls")" "rtk envolveu implementacao e verificacao das duas fases"
fi

# ---------------------------------------------------------------------------
# 24. Perfil System4u: Codex e autonomo em workspace-write, com allowlist e
#     sem danger-full-access. O commit continua limitado aos paths declarados.
# ---------------------------------------------------------------------------
if case_enabled system4u-autonomous; then
  header "24. perfil system4u-autonomous"
  d=$(new_case system4u-autonomous)
  (
    cd "$d/repo" || exit 1
    git branch -M feature/ralph-autonomous
    mkdir -p controls
    printf 'src/\n' > controls/allowed-paths.txt
    git add -A
    git commit -q -m "chore: allowlist"
  )
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh" --profile system4u-autonomous --allowed-paths-file controls/allowed-paths.txt .spec/init/project-phases.md)
  assert_eq 0 "$rc" "exit 0"
  assert_eq 4 "$(cat "$d/state/rtk_calls")" "rtk envolve implementacao e verificacao"
  assert_contains "$d/state/codex_args" 'approval_policy="never"' "Codex executa sem perguntas dentro da fase"
  assert_contains "$d/state/codex_args" "workspace-write" "implementacao usa workspace-write"
  assert_not_contains "$d/state/codex_args" "danger-full-access" "perfil nao usa danger-full-access"
  assert_eq 4 "$(commits "$d")" "duas fases commitadas apenas com paths permitidos"

  d2=$(new_case system4u-blocked-path)
  (
    cd "$d2/repo" || exit 1
    git branch -M feature/ralph-autonomous
    mkdir -p controls
    printf 'docs/\n' > controls/allowed-paths.txt
    git add -A
    git commit -q -m "chore: restrictive allowlist"
  )
  rc=$(run_ralph "$d2" ok --engine codex --test-cmd "$d2/test.sh" --profile system4u-autonomous --allowed-paths-file controls/allowed-paths.txt --max-cycles 1 .spec/init/project-phases.md)
  assert_eq 1 "$rc" "path fora da allowlist reprova a fase"
  assert_contains "$d2/out.log" "Guardrail System4u vermelho" "bloqueio da allowlist reportado"
  assert_eq 2 "$(commits "$d2")" "nenhum commit de fase para path bloqueado"

  d3=$(new_case system4u-main-branch)
  (
    cd "$d3/repo" || exit 1
    git branch -M main
    mkdir -p controls
    printf 'src/\n' > controls/allowed-paths.txt
    git add -A
    git commit -q -m "chore: allowlist"
  )
  rc=$(run_ralph "$d3" ok --engine codex --test-cmd "$d3/test.sh" --profile system4u-autonomous --allowed-paths-file controls/allowed-paths.txt .spec/init/project-phases.md)
  assert_eq 1 "$rc" "main e bloqueada antes do engine"
  assert_contains "$d3/out.log" "na branch main" "bloqueio da branch main reportado"
  test -f "$d3/state/impl_calls" && bad "main nao inicia sessao de engine" || ok "main nao inicia sessao de engine"

  d4=$(new_case system4u-missing-allowlist)
  (
    cd "$d4/repo" || exit 1
    git branch -M feature/ralph-autonomous
  )
  rc=$(run_ralph "$d4" ok --engine codex --test-cmd "$d4/test.sh" --profile system4u-autonomous .spec/init/project-phases.md)
  assert_eq 1 "$rc" "allowlist e obrigatoria"
  assert_contains "$d4/out.log" "exige --allowed-paths-file" "erro da allowlist ausente reportado"
  test -f "$d4/state/impl_calls" && bad "allowlist ausente nao inicia sessao de engine" || ok "allowlist ausente nao inicia sessao de engine"
fi

# ---------------------------------------------------------------------------
# 18. Fase falhou -> avisa que o trabalho parcial ficou na arvore
# ---------------------------------------------------------------------------
if case_enabled dirty-after-fail; then
  header "18. fase falhou com trabalho na arvore -> instrui o dev"
  d=$(new_case dirty-after-fail)
  echo "original" > "$d/repo/tracked.txt"
  git -C "$d/repo" add tracked.txt
  git -C "$d/repo" commit -q -m "chore: arquivo rastreado"
  before=$(commits "$d")
  # Escreve um path novo e modifica um rastreado; o verificador reprova.
  rc=$(run_ralph "$d" verify-incomplete-tracked --engine claude --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 1 "$rc" "exit 1"
  assert_eq "$before" "$(commits "$d")" "nenhum commit de fase"
  assert_contains "$d/out.log" "trabalho parcial desta fase ficou na arvore" "avisou sobre a arvore suja"
  assert_contains "$d/out.log" "git clean -fd" "deu a saida de descarte"
  assert_contains "$d/out.log" "verificacao: Gate 3 vermelho (cobertura: 2/2; incompletas: 1) | ciclo: 1 | log: .phases/logs/phase-01.verify-1.log" "resumo registra Gate 3 vermelho executado"
  assert_not_contains "$d/out.log" "verificacao: Gate 3 nao executado" "resumo nao mente que o Gate 3 foi pulado"
  assert_contains "$d/out.log" "arquivos: src/impl-1.txt, tracked.txt" "resumo lista paths novo e modificado"
  git -C "$d/repo" diff --cached --quiet && ok "coleta de paths nao altera o index" || bad "coleta de paths nao altera o index"
fi

# ---------------------------------------------------------------------------
# 19. --no-verify desliga o gate 3 mesmo no caminho suspeito (sessao sem
#     escrita). Escolha explicita do dev: o ralph confia no gate 2 sozinho.
# ---------------------------------------------------------------------------
if case_enabled no-verify; then
  header "19. --no-verify desliga o gate 3 ate no caminho suspeito"
  d=$(new_case no-verify)
  rc=$(run_ralph "$d" empty-diff --engine claude --test-cmd "$d/test.sh" --max-cycles 1 --no-verify)
  assert_eq 0 "$rc" "exit 0 (gate 2 verde decide sozinho)"
  assert_contains "$d/out.log" "Gate 3 pulado (--no-verify)" "skip explicito logado"
  assert_contains "$d/out.log" "Gate 2 verde contra o codigo em HEAD" "mensagem nao menciona gate 3 (nao rodou)"
  test -f "$d/state/verify_calls" && bad "nenhuma sessao verificadora gasta" || ok "nenhuma sessao verificadora gasta"
fi

# ---------------------------------------------------------------------------
# 20. RALPH_VERIFY=auto (opt-in): caminho feliz (sessao escreveu + suite verde)
#     pula o gate 3; a fase ainda commita.
# ---------------------------------------------------------------------------
if case_enabled verify-auto; then
  header "20. RALPH_VERIFY=auto pula o gate 3 no caminho feliz"
  d=$(new_case verify-auto)
  rc=$(CASE_VERIFY=auto run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "exit 0"
  assert_eq 3 "$(commits "$d")" "fases commitadas"
  assert_contains "$d/out.log" "Gate 3 pulado: a sessao escreveu codigo" "skip logado com a causa"
  test -f "$d/state/verify_calls" && bad "nenhuma sessao verificadora gasta" || ok "nenhuma sessao verificadora gasta"
fi

# ---------------------------------------------------------------------------
# 21. Verificador roda com modelo barato: haiku por default no claude,
#     RALPH_VERIFY_MODEL sobrepoe.
# ---------------------------------------------------------------------------
if case_enabled verify-model; then
  header "21. verificador usa modelo barato (haiku default, env sobrepoe)"
  d=$(new_case verify-model)
  # fase ja implementada em HEAD: sessao nao escreve -> gate 3 roda em auto
  mkdir -p "$d/repo/src"
  echo "impl previo" > "$d/repo/src/impl-1.txt"
  git -C "$d/repo" add -A && git -C "$d/repo" commit -q -m "feat: trabalho previo"
  rc=$(run_ralph "$d" already-done --engine claude --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0"
  assert_eq "haiku" "$(cat "$d/state/verify_model" 2>/dev/null)" "verify chamado com --model haiku"
  assert_contains "$d/out.log" "modelo: haiku" "log do gate 3 informa o modelo"

  d2=$(new_case verify-model-override)
  mkdir -p "$d2/repo/src"
  echo "impl previo" > "$d2/repo/src/impl-1.txt"
  git -C "$d2/repo" add -A && git -C "$d2/repo" commit -q -m "feat: trabalho previo"
  rc=$(CASE_VERIFY_MODEL=sonnet run_ralph "$d2" already-done --engine claude --test-cmd "$d2/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0 (override)"
  assert_eq "sonnet" "$(cat "$d2/state/verify_model" 2>/dev/null)" "RALPH_VERIFY_MODEL sobrepoe o default"
fi

# ---------------------------------------------------------------------------
# 25. Flags de modelo/reasoning prevalecem sobre env e reasoning chega ao
#     Codex como model_reasoning_effort. Sem override, a config e herdada.
# ---------------------------------------------------------------------------
if case_enabled verify-config; then
  header "25. configuracao deterministica do verificador Codex"
  d=$(new_case verify-config)
  rc=$(CASE_VERIFY_MODEL=env-model CASE_VERIFY_REASONING=low run_ralph "$d" ok \
    --engine codex --test-cmd "$d/test.sh" --max-cycles 1 --quiet \
    --verify-model flag-model --verify-reasoning high)
  assert_eq 0 "$rc" "exit 0"
  assert_eq "flag-model" "$(cat "$d/state/verify_model" 2>/dev/null)" "flag de modelo prevalece sobre env"
  assert_eq "high" "$(cat "$d/state/verify_reasoning" 2>/dev/null)" "flag de reasoning prevalece sobre env"
  assert_contains "$d/state/codex_args" 'model_reasoning_effort="high"' "reasoning passado via model_reasoning_effort"
  assert_contains "$d/state/codex_args" "read-only" "verificacao Codex continua em sandbox read-only"
  assert_contains "$d/out.log" "modelo: flag-model | reasoning: high" "inicio do gate mostra config solicitada"

  d2=$(new_case verify-config-env)
  rc=$(CASE_VERIFY_MODEL=env-model CASE_VERIFY_REASONING=xhigh run_ralph "$d2" ok \
    --engine codex --test-cmd "$d2/test.sh" --max-cycles 1)
  assert_eq 0 "$rc" "exit 0 com fallback em env"
  assert_eq "env-model" "$(cat "$d2/state/verify_model" 2>/dev/null)" "modelo herdado do env"
  assert_eq "xhigh" "$(cat "$d2/state/verify_reasoning" 2>/dev/null)" "reasoning herdado do env"
fi

# ---------------------------------------------------------------------------
# 26. Reasoning invalido no Codex e qualquer override no Claude falham no
#     preflight, antes da primeira sessao de engine.
# ---------------------------------------------------------------------------
if case_enabled verify-preflight; then
  header "26. preflight valida reasoning sem consumir sessoes"
  d=$(new_case verify-reasoning-invalid)
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh" --verify-reasoning turbo)
  assert_eq 1 "$rc" "reasoning Codex invalido falha"
  assert_contains "$d/out.log" "Reasoning invalido para o verificador Codex" "erro lista a incompatibilidade"
  test -f "$d/state/impl_calls" && bad "reasoning invalido nao inicia implementacao" || ok "reasoning invalido nao inicia implementacao"
  test -f "$d/state/verify_calls" && bad "reasoning invalido nao inicia verificacao" || ok "reasoning invalido nao inicia verificacao"

  d2=$(new_case verify-reasoning-claude)
  rc=$(CASE_VERIFY_REASONING=medium run_ralph "$d2" ok --engine claude --test-cmd "$d2/test.sh")
  assert_eq 1 "$rc" "override de reasoning no Claude falha"
  assert_contains "$d2/out.log" "Reasoning do verificador nao e compativel com o engine Claude" "erro Claude e claro"
  test -f "$d2/state/impl_calls" && bad "Claude incompatível nao inicia implementacao" || ok "Claude incompatível nao inicia implementacao"
  test -f "$d2/state/verify_calls" && bad "Claude incompatível nao inicia verificacao" || ok "Claude incompatível nao inicia verificacao"
fi

# ---------------------------------------------------------------------------
# 27. Codex quiet espelha apenas modelo/reasoning efetivos, mas preserva o
#     cabecalho completo no log do Gate 3.
# ---------------------------------------------------------------------------
if case_enabled verify-runtime-quiet; then
  header "27. runtime efetivo do Codex aparece em quiet"
  d=$(new_case verify-runtime-quiet)
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh" --max-cycles 1 --quiet)
  assert_eq 0 "$rc" "exit 0"
  assert_contains "$d/out.log" "Gate 3 — gravando | engine: codex | modelo: herdado | reasoning: herdado | sandbox: read-only | log: .phases/logs/phase-01.verify-1.log" "inicio informa config, sandbox, log e gravacao"
  assert_contains "$d/out.log" "model: gpt-mock-inherited" "terminal mostra modelo efetivo"
  assert_contains "$d/out.log" "reasoning effort: medium" "terminal mostra reasoning efetivo"
  assert_not_contains "$d/out.log" "provider: mock" "quiet nao espelha o cabecalho inteiro"
  assert_contains "$d/repo/.phases/logs/phase-01.verify-1.log" "OpenAI Codex mock" "log preserva inicio do cabecalho"
  assert_contains "$d/repo/.phases/logs/phase-01.verify-1.log" "provider: mock" "log preserva metadados integrais"
  assert_contains "$d/repo/.phases/logs/phase-01.verify-1.log" "reasoning summaries: none" "log preserva fim do cabecalho"
fi

# ---------------------------------------------------------------------------
# 27b. Codex quiet na implementacao mostra config solicitada, runtime efetivo
#      e mantem o cabecalho completo no log da fase.
# ---------------------------------------------------------------------------
if case_enabled impl-runtime-quiet; then
  header "27b. runtime efetivo da implementacao aparece em quiet"
  d=$(new_case impl-runtime-quiet)
  use_single_phase_fixture "$d"
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh" --max-cycles 1 --quiet --model gpt-5.6-luna --reasoning xhigh --no-verify)
  assert_eq 0 "$rc" "exit 0"
  assert_contains "$d/out.log" "Implementacao/correcao — gravando | engine: codex | modelo: gpt-5.6-luna | reasoning: xhigh | sandbox: danger-full-access | log: .phases/logs/phase-01.cycle-1.log" "inicio informa config solicitada, sandbox e log"
  assert_contains "$d/out.log" "model: gpt-5.6-luna" "terminal mostra modelo efetivo na implementacao"
  assert_contains "$d/out.log" "reasoning effort: xhigh" "terminal mostra reasoning efetivo na implementacao"
  assert_not_contains "$d/out.log" "provider: mock" "quiet nao espelha o cabecalho inteiro na implementacao"
  assert_contains "$d/repo/.phases/logs/phase-01.cycle-1.log" "OpenAI Codex mock" "log preserva inicio do cabecalho da implementacao"
  assert_contains "$d/repo/.phases/logs/phase-01.cycle-1.log" "provider: mock" "log preserva metadados integrais da implementacao"
  assert_contains "$d/repo/.phases/logs/phase-01.cycle-1.log" "reasoning summaries: none" "log preserva fim do cabecalho da implementacao"
  assert_contains "$d/state/codex_args" "danger-full-access" "implementacao default usa danger-full-access"
fi

# ---------------------------------------------------------------------------
# 28. Gate 3 reprova explicitamente log ausente ou vazio e registra a causa
#     operacional no resumo consolidado.
# ---------------------------------------------------------------------------
if case_enabled verify-log-required; then
  header "28. log do Gate 3 e obrigatorio"
  d=$(new_case verify-log-empty)
  rc=$(run_ralph "$d" verify-log-empty --engine codex --test-cmd "$d/test.sh" --max-cycles 1)
  assert_eq 1 "$rc" "log vazio reprova"
  assert_contains "$d/out.log" "Log de verificacao vazio" "causa de log vazio e explicita"
  assert_contains "$d/out.log" "verificacao: Gate 3 vermelho (cobertura: 0/2; incompletas: indisponivel) | ciclo: 1 | log: .phases/logs/phase-01.verify-1.log" "resumo vermelho inclui cobertura, ciclo e log"
  assert_eq 1 "$(commits "$d")" "log vazio nao cria commit"

  d2=$(new_case verify-log-missing)
  rc=$(run_ralph "$d2" verify-log-missing --engine codex --test-cmd "$d2/test.sh" --max-cycles 1)
  assert_eq 1 "$rc" "log ausente reprova"
  assert_contains "$d2/out.log" "Log de verificacao ausente" "causa de log ausente e explicita"
  assert_contains "$d2/out.log" "log: .phases/logs/phase-01.verify-1.log" "caminho ausente permanece no resumo"
  assert_eq 1 "$(commits "$d2")" "log ausente nao cria commit"
fi

# ---------------------------------------------------------------------------
# 29. Findings sucessivos ultrapassam tres ciclos pelo default novo e chegam
#     ao quarto Gate 3 verde, ainda com um unico commit de fase.
# ---------------------------------------------------------------------------
if case_enabled layered-findings; then
  header "29. findings em camadas chegam ao quarto ciclo"
  d=$(new_case layered-findings)
  use_single_phase_fixture "$d"
  before=$(commits "$d")
  rc=$(run_ralph "$d" layered-findings --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "default permite concluir no ciclo 4"
  assert_eq $((before + 1)) "$(commits "$d")" "um unico commit de fase"
  assert_eq 4 "$(cat "$d/state/impl_calls")" "quatro sessoes de implementacao"
  assert_eq 4 "$(cat "$d/state/verify_calls")" "quarto Gate 3 ficou verde"
  assert_contains "$d/out.log" "Ciclo de correcao 4/12" "default total e 12 ciclos"
  assert_contains "$d/out.log" "Gate 3 verde (2/2 tasks) | ciclo: 4" "resumo registra o Gate 3 verde final"
fi

# ---------------------------------------------------------------------------
# 30. --max-cycles continua sendo hard cap explicito: o mesmo fluxo em
#     camadas para no terceiro finding, sem commit.
# ---------------------------------------------------------------------------
if case_enabled layered-hard-cap; then
  header "30. hard cap explicito interrompe findings em camadas"
  d=$(new_case layered-hard-cap)
  use_single_phase_fixture "$d"
  before=$(commits "$d")
  rc=$(run_ralph "$d" layered-findings --engine claude --test-cmd "$d/test.sh" --max-cycles 3)
  assert_eq 1 "$rc" "hard cap 3 falha antes do Gate 3 verde"
  assert_eq "$before" "$(commits "$d")" "hard cap nao cria commit de fase"
  assert_eq 3 "$(cat "$d/state/impl_calls")" "hard cap executa exatamente tres ciclos"
  assert_contains "$d/out.log" "FALHOU apos 3 ciclos" "diagnostico preserva o hard cap"
  assert_not_contains "$d/out.log" "FALHOU por estagnacao" "findings novos nao viram estagnacao"

  d2=$(new_case layered-hard-cap-env)
  use_single_phase_fixture "$d2"
  rc=$(CASE_MAX_CYCLES=3 run_ralph "$d2" layered-findings --engine claude --test-cmd "$d2/test.sh")
  assert_eq 1 "$rc" "RALPH_MAX_CYCLES preserva o hard cap explicito"
  assert_eq 3 "$(cat "$d2/state/impl_calls")" "hard cap por env tambem executa tres ciclos"
fi

# ---------------------------------------------------------------------------
# 31. Gate, causa e arvore repetidos param por estagnacao. Default 2 significa
#     duas tentativas corretivas consecutivas sem progresso apos a referencia.
# ---------------------------------------------------------------------------
if case_enabled remediation-stagnation; then
  header "31. repeticao sem progresso para por estagnacao"
  d=$(new_case remediation-stagnation)
  use_single_phase_fixture "$d"
  before=$(commits "$d")
  rc=$(run_ralph "$d" stagnant-finding --engine claude --test-cmd "$d/test.sh")
  assert_eq 1 "$rc" "estagnacao reprova a fase"
  assert_eq "$before" "$(commits "$d")" "estagnacao nao cria commit"
  assert_eq 3 "$(cat "$d/state/impl_calls")" "default para apos dois ciclos corretivos estagnados"
  assert_contains "$d/out.log" "Estagnacao detectada: 2/2 ciclos corretivos consecutivos sem progresso" "diagnostico proprio informa o contador"
  assert_contains "$d/out.log" "ultimo gate: gate 3 — verificacao independente" "diagnostico preserva o ultimo gate"
  assert_contains "$d/out.log" "verificacao: Gate 3 vermelho (cobertura: 2/2; incompletas: 1) | ciclo: 3 | log: .phases/logs/phase-01.verify-3.log" "resumo preserva ultimo Gate 3 e log"
  assert_contains "$d/out.log" "arquivos: src/impl-1.txt" "estagnacao lista paths parciais"

  d2=$(new_case remediation-stagnation-env)
  use_single_phase_fixture "$d2"
  rc=$(CASE_MAX_STALLED_CYCLES=1 run_ralph "$d2" stagnant-finding --engine claude --test-cmd "$d2/test.sh")
  assert_eq 1 "$rc" "RALPH_MAX_STALLED_CYCLES configura a trava"
  assert_eq 2 "$(cat "$d2/state/impl_calls")" "env 1 para na primeira repeticao corretiva"

  d3=$(new_case remediation-stagnation-flag)
  use_single_phase_fixture "$d3"
  rc=$(CASE_MAX_STALLED_CYCLES=1 run_ralph "$d3" stagnant-finding --engine claude --test-cmd "$d3/test.sh" --max-stalled-cycles 2)
  assert_eq 1 "$rc" "flag de estagnacao prevalece sobre env"
  assert_eq 3 "$(cat "$d3/state/impl_calls")" "flag 2 exige duas repeticoes corretivas"

  d4=$(new_case remediation-stagnation-invalid)
  rc=$(run_ralph "$d4" ok --engine claude --test-cmd "$d4/test.sh" --max-stalled-cycles 0)
  assert_eq 1 "$rc" "estagnacao zero falha no preflight"
  assert_contains "$d4/out.log" "Valor invalido para --max-stalled-cycles" "validacao exige inteiro >= 1"
  test -f "$d4/state/impl_calls" && bad "valor invalido nao inicia engine" || ok "valor invalido nao inicia engine"

  d5=$(new_case remediation-stagnation-env-invalid)
  rc=$(CASE_MAX_STALLED_CYCLES=invalido run_ralph "$d5" ok --engine claude --test-cmd "$d5/test.sh")
  assert_eq 1 "$rc" "env de estagnacao invalida falha no preflight"
  assert_contains "$d5/out.log" "Valor invalido para --max-stalled-cycles" "validacao tambem cobre RALPH_MAX_STALLED_CYCLES"

  d6=$(new_case remediation-stagnation-normalized)
  use_single_phase_fixture "$d6"
  rc=$(run_ralph "$d6" normalized-finding --engine claude --test-cmd "$d6/test.sh" --max-stalled-cycles 1)
  assert_eq 1 "$rc" "diferenca apenas de whitespace continua sendo estagnacao"
  assert_eq 2 "$(cat "$d6/state/impl_calls")" "causa normalizada produz fingerprint estavel"
fi

# ---------------------------------------------------------------------------
# 32. Finding, gate ou arvore diferentes sao progresso e zeram a estagnacao.
# ---------------------------------------------------------------------------
if case_enabled remediation-progress; then
  header "32. finding, gate e arvore diferentes permitem continuar"
  d=$(new_case remediation-finding-progress)
  use_single_phase_fixture "$d"
  rc=$(run_ralph "$d" finding-progress --engine claude --test-cmd "$d/test.sh" --max-cycles 6)
  assert_eq 0 "$rc" "finding novo permite chegar ao verde"
  assert_eq 5 "$(cat "$d/state/impl_calls")" "finding novo zerou estagnacao no ciclo 3"
  assert_contains "$d/out.log" "Progresso detectado: gate, causa ou arvore mudou; estagnacao zerada (era 1)" "reset por finding e observavel"

  d2=$(new_case remediation-tree-progress)
  use_single_phase_fixture "$d2"
  rc=$(run_ralph "$d2" tree-progress --engine claude --test-cmd "$d2/test.sh" --max-cycles 3 --max-stalled-cycles 1)
  assert_eq 0 "$rc" "arvore alterada evita falso positivo de estagnacao"
  assert_eq 3 "$(cat "$d2/state/impl_calls")" "mesmo finding continuou enquanto a arvore mudou"

  d3=$(new_case remediation-gate-progress)
  use_single_phase_fixture "$d3"
  rc=$(run_ralph "$d3" gate-progress --engine claude --test-cmd "$d3/test.sh" --max-cycles 3 --max-stalled-cycles 1)
  assert_eq 0 "$rc" "gate diferente evita falso positivo de estagnacao"
  assert_contains "$d3/out.log" "Gate 2 vermelho" "primeira falha veio do Gate 2"
  assert_contains "$d3/out.log" "Gate 3 vermelho" "falha seguinte veio do Gate 3"
fi

# ---------------------------------------------------------------------------
# 33. Finding funcional de workspace chega verbatim ao corretor, que recebe
#     autorizacao funcional explicita sem enfraquecer limites operacionais.
# ---------------------------------------------------------------------------
if case_enabled workspace-authorization; then
  header "33. autorizacao funcional aprovada no prompt corretivo"
  d=$(new_case workspace-authorization)
  use_single_phase_fixture "$d"
  rc=$(run_ralph "$d" workspace-authorized --engine claude --test-cmd "$d/test.sh" --max-cycles 2)
  assert_eq 0 "$rc" "finding de workspace chega ao ciclo corretivo e conclui"
  prompt="$d/repo/.phases/prompts/phase-01.cycle-2.txt"
  assert_contains "$prompt" "TASK 1: INCOMPLETE — falta validar workspace autorizado" "finding chega verbatim ao corretor"
  assert_contains "$prompt" "autenticacao, autorizacao, isolamento, policies, gates ou permissoes da aplicacao sao escopo funcional aprovado" "prompt aprova autorizacao funcional dentro da fase ou causa"
  assert_contains "$prompt" "nao contorne sandbox, allowlist, regras do projeto, segredos, chamadas externas nao autorizadas" "prompt preserva guardrails operacionais"
  assert_contains "$prompt" "migrations destrutivas, deploy, push" "prompt mantem operacoes destrutivas proibidas"
fi

# ---------------------------------------------------------------------------
# 13. Laravel Sail com containers de pe -> gate 2 usa `vendor/bin/sail test`
#     (e NAO `composer test`, que rodaria no host sem PHP nem banco)
# ---------------------------------------------------------------------------
if case_enabled sail-up; then
  header "13. Laravel Sail up -> gate 2 roda sail test"
  d=$(new_case sail-up)
  make_sail_fixture "$d/repo" up
  git -C "$d/repo" add -A && git -C "$d/repo" commit -q -m "chore: sail"
  rc=$(run_ralph "$d" ok --engine claude)   # sem --test-cmd: exercita a deteccao
  assert_eq 0 "$rc" "exit 0"
  assert_contains "$d/out.log" "comando de teste (detectado): vendor/bin/sail test" "detectou sail test"
  assert_not_contains "$d/out.log" "composer test" "composer test nao foi escolhido"
  assert_contains "$d/out.log" "Sail: containers de pe" "checou containers no preflight"
  # base = 2 commits (fixture + chore: sail) + 2 fases
  assert_eq 4 "$(commits "$d")" "fases commitadas (gate 2 rodou de verdade)"
  assert_eq 2 "$(cat "$d/state/test_calls")" "a suite rodou 1x por fase, via sail"
  # o agente precisa saber qual runner usar, senao roda php artisan test no host
  assert_contains "$d/repo/.phases/prompts/phase-01.cycle-1.txt" "vendor/bin/sail test" "prompt informa o comando de teste"
  assert_contains "$d/repo/.phases/prompts/phase-01.cycle-1.txt" "Nunca rode essas ferramentas no host" "prompt avisa sobre o container"
fi

# ---------------------------------------------------------------------------
# 14. Sail com containers parados -> abort no preflight, zero tokens
# ---------------------------------------------------------------------------
if case_enabled sail-down; then
  header "14. Laravel Sail down -> abort no preflight"
  d=$(new_case sail-down)
  make_sail_fixture "$d/repo" down
  git -C "$d/repo" add -A && git -C "$d/repo" commit -q -m "chore: sail"
  rc=$(run_ralph "$d" ok --engine claude)
  assert_eq 1 "$rc" "exit 1"
  assert_contains "$d/out.log" "containers nao estao de pe" "abortou com a causa"
  assert_contains "$d/out.log" "vendor/bin/sail up -d" "instruiu como subir o ambiente"
  assert_eq 2 "$(commits "$d")" "nenhum commit de fase"
  test -f "$d/state/impl_calls" && bad "nenhuma sessao de engine iniciada" || ok "nenhuma sessao de engine iniciada"
fi

# ---------------------------------------------------------------------------
# 15. --test-cmd sobrepoe a deteccao de Sail
# ---------------------------------------------------------------------------
if case_enabled sail-override; then
  header "15. --test-cmd sobrepoe a deteccao de Sail"
  d=$(new_case sail-override)
  make_sail_fixture "$d/repo" down   # containers parados, mas o cmd nao usa sail
  git -C "$d/repo" add -A && git -C "$d/repo" commit -q -m "chore: sail"
  rc=$(run_ralph "$d" ok --engine claude --test-cmd "$d/test.sh")
  assert_eq 0 "$rc" "exit 0 (nao checa containers para cmd sem sail)"
  assert_contains "$d/out.log" "comando de teste (--test-cmd)" "override respeitado"
  assert_eq 4 "$(commits "$d")" "fases commitadas"
fi

# ---------------------------------------------------------------------------
# 16. Laravel sem Sail -> composer test (regressao: nao vira sail test)
# ---------------------------------------------------------------------------
if case_enabled laravel-no-sail; then
  header "16. Laravel sem Sail -> composer test"
  d=$(new_case laravel-no-sail)
  touch "$d/repo/artisan"
  printf '{ "scripts": { "test": "phpunit" } }\n' > "$d/repo/composer.json"
  git -C "$d/repo" add -A && git -C "$d/repo" commit -q -m "chore: laravel"
  # nao roda ate o fim: so precisamos do preflight resolvendo o comando
  run_ralph "$d" empty-diff --engine claude --max-cycles 1 > /dev/null
  assert_contains "$d/out.log" "comando de teste (detectado): composer test" "sem sail -> composer test"
  assert_not_contains "$d/out.log" "Sail" "nao mencionou Sail"
fi

# ---------------------------------------------------------------------------
# 34. --help publica o contrato operacional completo. O marcador no cabecalho
#     impede que novas linhas cortem silenciosamente variaveis ou exports.
# ---------------------------------------------------------------------------
if case_enabled help-contract; then
  header "34. help publica defaults, runtime, paradas e exports"
  help_log="$TMP/help-contract.log"
  bash "$RALPH" --help > "$help_log"
  assert_contains "$help_log" "--max-cycles N           hard cap total de ciclos por fase (default: 12)" "help informa hard cap default 12"
  assert_contains "$help_log" "--max-stalled-cycles N   ciclos corretivos sem progresso (default: 2)" "help informa estagnacao default 2"
  assert_contains "$help_log" "--verify-model/--verify-reasoning prevalecem" "help documenta precedencia da configuracao"
  assert_contains "$help_log" "runtime efetivo: modelo/reasoning ficam no log" "help distingue runtime efetivo"
  assert_contains "$help_log" "phase-NN.verify-C.log nao vazio" "help documenta log obrigatorio do Gate 3"
  assert_contains "$help_log" "Limite de uso nao consome ciclo" "help preserva semantica de usage limit"
  assert_contains "$help_log" "RALPH_VERIFY_REASONING" "help lista env de reasoning"
  assert_contains "$help_log" "--model MODEL            modelo das sessoes de implementacao/correcao" "help lista modelo de implementacao"
  assert_contains "$help_log" "--reasoning EFFORT       reasoning Codex das sessoes de implementacao/correcao" "help lista reasoning de implementacao"
  assert_contains "$help_log" "RALPH_MODEL              modelo das sessoes de implementacao/correcao" "help lista RALPH_MODEL"
  assert_contains "$help_log" "RALPH_REASONING          reasoning Codex das sessoes de implementacao/correcao" "help lista RALPH_REASONING"
  assert_contains "$help_log" "--model/--reasoning prevalecem sobre RALPH_MODEL/RALPH_REASONING" "help documenta precedencia das sessoes mutaveis"
  assert_contains "$help_log" "Claude aceita modelo explicito, mas reasoning nao e aplicavel" "help separa compatibilidade Claude"
  assert_contains "$help_log" "RALPH_MAX_STALLED_CYCLES" "help lista env de estagnacao"
  assert_contains "$help_log" "RALPH_PHASE_MAX_ATTEMPTS igual a RALPH_MAX_CYCLES" "help lista export do hard cap efetivo"
  assert_contains "$help_log" "Isso nao amplia permissoes operacionais" "help separa autorizacao funcional e operacional"
fi

# ---------------------------------------------------------------------------
# 35. Modelo/reasoning das sessoes mutaveis usam flag > ambiente > heranca,
#     sem misturar os controles independentes do Gate 3.
# ---------------------------------------------------------------------------
if case_enabled impl-config; then
  header "35. configuracao deterministica das sessoes mutaveis"
  d=$(new_case impl-config)
  use_single_phase_fixture "$d"
  rc=$(CASE_MODEL=env-model CASE_REASONING=low \
    CASE_VERIFY_MODEL=verify-env CASE_VERIFY_REASONING=low \
    run_ralph "$d" test-red-once --engine codex --test-cmd "$d/test.sh" --max-cycles 2 \
      --model flag-model --reasoning high --verify-model verify-flag --verify-reasoning xhigh)
  assert_eq 0 "$rc" "exit 0 com ciclo corretivo"
  assert_eq $'flag-model|high\nflag-model|high' "$(cat "$d/state/impl_configs")" "flags de implementacao prevalecem no inicio e na correcao"
  assert_eq "verify-flag|xhigh" "$(cat "$d/state/verify_configs")" "Gate 3 permanece separado e usa seus proprios controles"
  assert_contains "$d/state/codex_args" 'model_reasoning_effort="high"' "reasoning de implementacao chega ao Codex"
  assert_contains "$d/state/codex_args" 'model_reasoning_effort="xhigh"' "reasoning do Gate 3 continua independente"

  d2=$(new_case impl-config-env)
  use_single_phase_fixture "$d2"
  rc=$(CASE_MODEL=env-model CASE_REASONING=medium \
    run_ralph "$d2" ok --engine codex --test-cmd "$d2/test.sh" --max-cycles 1 \
      --verify-model verifier --verify-reasoning low)
  assert_eq 0 "$rc" "exit 0 com fallback por ambiente"
  assert_eq "env-model|medium" "$(cat "$d2/state/impl_configs")" "ambiente configura as sessoes mutaveis sem flags"
  assert_eq "verifier|low" "$(cat "$d2/state/verify_configs")" "ambiente/flags do Gate 3 nao sao substituidos pela implementacao"

  d3=$(new_case impl-config-inherited)
  rc=$(run_ralph "$d3" ok --engine codex --test-cmd "$d3/test.sh" --max-cycles 1 --no-verify)
  assert_eq 0 "$rc" "exit 0 sem override"
  assert_eq $'<inherited>|<inherited>\n<inherited>|<inherited>' "$(cat "$d3/state/impl_configs")" "sem override o Codex herda modelo e reasoning"
  assert_not_contains "$d3/state/codex_args" "--model" "sem override nao passa modelo ao Codex"
  assert_not_contains "$d3/state/codex_args" "model_reasoning_effort" "sem override nao passa reasoning ao Codex"

  d4=$(new_case impl-config-claude)
  rc=$(run_ralph "$d4" ok --engine claude --test-cmd "$d4/test.sh" --max-cycles 1 --model claude-model)
  assert_eq 0 "$rc" "exit 0 com modelo explicito no Claude"
  assert_eq $'claude-model|<inherited>\nclaude-model|<inherited>' "$(cat "$d4/state/impl_configs")" "modelo chega as sessoes Claude de implementacao"
  assert_eq $'haiku|<inherited>\nhaiku|<inherited>' "$(cat "$d4/state/verify_configs")" "modelo default haiku do verificador permanece independente"
fi

# ---------------------------------------------------------------------------
# 36. Flags vazias e reasoning invalido/incompativel falham no preflight,
#     antes de implementar ou verificar.
# ---------------------------------------------------------------------------
if case_enabled impl-preflight; then
  header "36. preflight valida configuracao das sessoes mutaveis"
  d=$(new_case impl-model-empty)
  rc=$(run_ralph "$d" ok --engine codex --test-cmd "$d/test.sh" --model=)
  assert_eq 1 "$rc" "modelo vazio falha no preflight"
  assert_contains "$d/out.log" "--model exige um valor nao vazio" "erro de modelo vazio e claro"
  test -f "$d/state/impl_calls" && bad "modelo vazio nao inicia implementacao" || ok "modelo vazio nao inicia implementacao"
  test -f "$d/state/verify_calls" && bad "modelo vazio nao inicia verificacao" || ok "modelo vazio nao inicia verificacao"

  d2=$(new_case impl-reasoning-empty)
  rc=$(run_ralph "$d2" ok --engine codex --test-cmd "$d2/test.sh" --reasoning=)
  assert_eq 1 "$rc" "reasoning vazio falha no preflight"
  assert_contains "$d2/out.log" "--reasoning exige um valor nao vazio" "erro de reasoning vazio e claro"
  test -f "$d2/state/impl_calls" && bad "reasoning vazio nao inicia implementacao" || ok "reasoning vazio nao inicia implementacao"

  d3=$(new_case impl-reasoning-invalid)
  rc=$(run_ralph "$d3" ok --engine codex --test-cmd "$d3/test.sh" --reasoning=turbo)
  assert_eq 1 "$rc" "reasoning Codex invalido falha"
  assert_contains "$d3/out.log" "Reasoning invalido para sessoes de implementacao/correcao Codex" "erro lista os esforcos aceitos"
  test -f "$d3/state/impl_calls" && bad "reasoning Codex invalido nao inicia implementacao" || ok "reasoning Codex invalido nao inicia implementacao"

  d4=$(new_case impl-reasoning-claude)
  rc=$(run_ralph "$d4" ok --engine claude --test-cmd "$d4/test.sh" --reasoning=low)
  assert_eq 1 "$rc" "reasoning Claude explicito falha"
  assert_contains "$d4/out.log" "Reasoning de implementacao/correcao nao e compativel com o engine Claude" "incompatibilidade Claude e clara"
  test -f "$d4/state/impl_calls" && bad "reasoning Claude nao inicia implementacao" || ok "reasoning Claude nao inicia implementacao"

  d5=$(new_case impl-reasoning-claude-env)
  rc=$(CASE_REASONING=medium run_ralph "$d5" ok --engine claude --test-cmd "$d5/test.sh")
  assert_eq 1 "$rc" "reasoning Claude por ambiente falha"
  assert_contains "$d5/out.log" "Remova --reasoning/RALPH_REASONING" "erro de ambiente Claude orienta a remocao"
  test -f "$d5/state/impl_calls" && bad "reasoning Claude por ambiente nao inicia implementacao" || ok "reasoning Claude por ambiente nao inicia implementacao"
fi

# ---------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}TODOS VERDES: $PASS asserts${NC}"
else
  echo -e "${RED}FALHAS: $FAIL${NC} / verdes: $PASS"
fi
exit $((FAIL > 0 ? 1 : 0))
