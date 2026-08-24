# Beer and Code Harness (`bc-harness`)

> 🇧🇷 [Documentação em português](README.pt-BR.md)

A [Claude Code](https://claude.com/claude-code) & Codex CLI harness with commands, agents, and scripts that take a project from idea to implementation in a structured way: formal specification, phased planning, and autonomous execution with mechanical validation — while keeping a human in control at every decision point.

The harness is **stack-agnostic**: language, framework, commands, and conventions are defined by the project's own documents (`AGENTS.md`, `CLAUDE.md`, the `.spec/` chain), never by the harness.

## Workflow overview

```
 IDEA                                              CODE
   │                                                 ▲
   ▼                                                 │
 /init:project-description  ──┐                      │
 /init:user-stories           │  init chain          │
 /init:database-schema        │  (.spec/init/)       │
 /init:project-phases       ──┘                      │
   │                                                 │
   │            /plan "<feature description>"        │
   │            (.spec/features/<slug>/)             │
   ▼                                                 │
 project-phases.md  or  PHASES.md ────────► scripts/ralph.sh
                                            (autonomous execution
                                             with 4 gates)

 /ai-context ─► AGENTS.md + docs/agents/*  (documents the ALREADY implemented
                                            code; feeds /plan and ralph)
```

Three independent pipelines that fit together:

1. **`/init`** — from zero to a project build plan (description → user stories → schema → phases).
2. **`/plan`** — from a feature description to a formal SPEC + phased plan, ready for execution.
3. **`ralph.sh`** — executes any phase document autonomously, one fresh agent session per phase, with mechanical gates and one commit per completed phase.

Cross-cutting: **`/ai-context`** keeps the context tree (`AGENTS.md`, `CLAUDE.md`, `docs/agents/*.md`) in sync with the real code.

## Installation

The command interface is distributed as a [Claude Code](https://code.claude.com/docs/en/setup) plugin (`.claude-plugin/plugin.json`). The autonomous runner supports Claude Code and [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) through `scripts/ralph.sh`.

### Claude Code plugin

Install Claude Code with npm, then run `claude` from a project directory and complete a supported authentication method:

```bash
npm install -g @anthropic-ai/claude-code
claude
```

After Claude Code is authenticated, install the public marketplace hosted at [`afonseca69/beer-and-code-harness`](https://github.com/afonseca69/beer-and-code-harness), then install the `bc-harness` plugin from the `beer-and-code-local` marketplace:

```bash
claude plugin marketplace add afonseca69/beer-and-code-harness
claude plugin install bc-harness@beer-and-code-local
```

Inside an interactive Claude Code session, the equivalent commands are:

```text
/plugin marketplace add afonseca69/beer-and-code-harness
/plugin install bc-harness@beer-and-code-local
```

If Claude reports `Run /reload-plugins to activate.`, run `/reload-plugins`.

Commands are namespaced: `/bc-harness:init`, `/bc-harness:plan`, etc. (abbreviated without the namespace throughout this document). These slash commands are Claude Code plugin commands; Codex support in this repository is the `scripts/ralph.sh` executor.

### Codex CLI runner

Install Codex CLI with the official standalone installer for macOS/Linux, or with npm:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
# or
npm install -g @openai/codex
```

Then run `codex` from a project directory and sign in with ChatGPT or another supported method:

```bash
codex
```

Install RTK (Rust Token Killer) and verify that the `rtk` command is the expected token optimizer:

```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
rtk gain
```

Run `ralph.sh` with the target project repository root as the current working directory. You may copy `scripts/ralph.sh` into the target project, or invoke it from the harness clone by absolute or relative path.

```bash
# from the clean root of the target project, using the harness clone
/path/to/beer-and-code-harness/scripts/ralph.sh --engine codex .spec/features/<slug>/PHASES.md

# if scripts/ralph.sh was copied into the target project
scripts/ralph.sh --engine codex .spec/features/<slug>/PHASES.md
```

`OPENAI_API_KEY` is supported by Codex CLI authentication, but it is not a mandatory `ralph.sh` prerequisite when Codex is already authenticated by ChatGPT or another supported method. The Codex engine requires `rtk` and `codex` on `PATH`; ralph runs `rtk codex exec`.

### ralph.sh prerequisites

- Codex engine: [RTK](https://github.com/rtk-ai/rtk) + Codex CLI authenticated and available on `PATH`
- Claude engine: Claude Code CLI authenticated and available on `PATH`
- Root of a git repository with a **clean** working tree

### Mutable session configuration

Implementation/correction sessions accept `--model` / `RALPH_MODEL` and
`--reasoning` / `RALPH_REASONING`. Precedence is flag > environment > engine
inheritance. Codex accepts `minimal`, `low`, `medium`, `high`, or `xhigh` for
reasoning. Claude accepts an explicit model, but reasoning is not applicable.
Correction cycles may override only their effort with `--fix-reasoning` /
`RALPH_FIX_REASONING`; without it, they inherit the implementation reasoning.

Gate 3 keeps its own `--verify-model` / `--verify-reasoning` controls and stays
separate from implementation sessions. Before each mutable session, ralph
prints the requested configuration, sandbox, and log path. In Codex `--quiet`,
the effective `model:` and `reasoning effort:` lines are still mirrored for
both implementation and verification while the full header remains in the log.

Runtime-conscious example: Luna/high for implementation and corrections,
xhigh only for the independent verifier, three cycles at most, and one selected
phase:

```bash
scripts/ralph.sh --engine codex --quiet \
  --model gpt-5.6-luna --reasoning high --fix-reasoning high \
  --verify-model gpt-5.6-luna --verify-reasoning xhigh \
  --max-cycles 3 --only-phase 2 \
  .spec/features/<slug>/PHASES.md
```

## Commands

### `/init` — init chain router

Shows the state of the `.spec/init/` artifacts (present / absent / stale) and **invokes the next command in the chain** (one hop per run — re-run `/init` to advance). Writes nothing itself; all authoring lives in the invoked `init:*` command.

The chain, in order:

| # | Artifact | Command | Inputs |
|---|---|---|---|
| 1 | `.spec/init/project-description.md` | `/init:project-description` | — (head of chain) |
| 2 | `.spec/init/user-stories.md` | `/init:user-stories` | project-description |
| 3 | `.spec/init/database-schema.md` | `/init:database-schema` | description + stories |
| 4 | `.spec/init/project-phases.md` | `/init:project-phases` | description + stories + schema |
| — | `.spec/init/design/` | manual (optional) | — |

Every generated artifact carries a **stamp** of its inputs on line 3 (`file@sha256:<12 chars>`). If an input changes later, `/init` detects it and reports the downstream artifact as *stale* — re-running the corresponding command is upsert-safe: it interviews only about the deltas and refreshes the stamp.

- **`/init:project-description`** — interviews the developer, discovers the stack, and produces a structured project description.
- **`/init:user-stories`** — derives structured, testable user stories from the description.
- **`/init:database-schema`** — derives a suggested database schema in DBML.
- **`/init:project-phases`** — plans the build into numbered, agent-ready phases with tasks, acceptance criteria, and feature tests. **This is `ralph.sh`'s default input.** Reads `.spec/init/design/` when present (screen/component refs).

### `/plan` — feature planning pipeline

```
/plan "<feature description or path to a description file>"
```

Produces, under `.spec/features/<slug>/`:

| Artifact | Content |
|---|---|
| `SPEC.md` | Formal specification in GEARS syntax, with RIGID/FLEXIBLE sections, AS IS / TO BE diagrams, and binary acceptance criteria |
| `PLAN.md` | Architecture-aware task decomposition with dependency phases, risks, and validation criteria |
| `PHASES.md` | The PLAN rendered in the format executable by `ralph.sh` |
| `openapi.yaml` / `service.proto` / `asyncapi.yaml` | Formal contracts, when the SPEC declares an API surface (conditional) |

Key characteristics:

- **No issue tracker** — the confirmed description + ACs are the source of truth. No Jira.
- **Complexity tier** (`light` / `standard` / `complete`) classified from objective signals (requirement count, multi-repo, contracts, messaging); adjusts SPEC depth, whether the clarifier is mandatory, and contract emission.
- **Human checkpoints** at every step: confirmation of the normalized input, SPEC approval, ambiguity resolution, decomposition sign-off.
- **Two-phase clarifier** — the agent analyzes the SPEC and returns prioritized questions; the router presents them to the developer and re-invokes the agent with the answers, which updates the SPEC in-place.
- **Architecture gate** — requires `AGENTS.md` / `docs/agents/` (or warns and flags `architecture_reference_status: missing`). The pipeline never plans silently without architecture context.
- **Never writes application code.** The close-out points at the execution handoff:

```bash
./ralph.sh .spec/features/<slug>/PHASES.md
```

### `/ai-context` — canonical context tree

```
/ai-context [path] [+id] [-id] [--adopt]
```

Generates or refreshes 10 artifacts from the **implemented code** (never reads `.spec/`):

| Artifact | Content |
|---|---|
| `AGENTS.md` | 6 sections: commands, conventions, behavioral rules, setup, references, docs index |
| `CLAUDE.md` | ≤ 400-byte redirect to AGENTS.md |
| `docs/agents/project_overview.md` | Purpose, consumers, macro flow |
| `docs/agents/architecture.md` | Style, layout, layer responsibilities |
| `docs/agents/tech_stack.md` | Language, framework, runtime, test tooling |
| `docs/agents/coding_guidelines.md` | ≥ 3 observed patterns + enforcement |
| `docs/agents/domain_rules.md` | Business rules as implemented |
| `docs/agents/api_contracts.md` | Endpoints, payloads, message formats |
| `docs/agents/data_model.md` | Entities, storage, migrations |
| `docs/agents/dependencies.md` | External services, internal libs, shared infra |

Core rules:

- **Idempotent** — safe upsert; re-running updates only what drifted.
- **Documents reality (AS IS)** — code, manifests, CI, and configs are the only sources; never invents, never prescribes.
- **Ownership contract** — every generated file carries a banner on line 3. A file without the banner (hand-written) is never clobbered; `--adopt` folds its concrete rules into the generated tree and takes ownership.
- **Preserves third-party blocks** — `<tag>...</tag>` regions (e.g. Laravel Boost) are re-appended verbatim on regeneration.
- `+id` / `-id` filters generate only a subset (e.g. `/ai-context +AGENTS +architecture`).

## `scripts/ralph.sh` — execution orchestrator

Reads a phase document, splits it on the `## Phase N: <title>` heading, and feeds each phase to a **fresh** Codex CLI or Claude Code session, with no human interaction from start to finish.

```bash
./scripts/ralph.sh [options] [path-to-file]
```

With no argument, the input resolves in this order: `.spec/init/project-phases.md` → `.spec/project-phases.md` (pre-init layout, with a warning). A feature `PHASES.md` is also valid input.

> **Autonomy and permissions note**: ralph is an unattended orchestrator by design. With the Claude engine, implementation sessions run with `--dangerously-skip-permissions` — the agent can edit files and run commands in the repository without prompting. Run it only in repositories you trust, ideally in a disposable branch or isolated environment (container/VM). Every green phase lands as a separate commit, allowing only the corresponding work to be reverted. The Gate 3 verification session remains restricted to read-only tools (`Read,Glob,Grep`).

### `system4u-autonomous` profile

This opt-in Codex profile is for System4u Portal's guarded autonomous runs. It is non-interactive, but it is **not** unrestricted YOLO: implementation uses `rtk codex exec -c 'approval_policy="never"' --sandbox workspace-write`, while verification stays read-only.

It requires a clean non-`main` branch, an explicit phase document, `RALPH_VERIFY=always`, a new local artifact directory, and a repository-relative allowlist. It rejects deletions, renames, `.env`, `.git`, `storage/`, `vendor/`, and `node_modules/`; it never pushes, merges, deploys, installs dependencies, or runs migrations. Completed phases are committed only after the changed paths pass the allowlist.

```bash
scripts/ralph.sh --engine codex --profile system4u-autonomous --quiet \
  --allowed-paths-file controls/approved-paths.txt \
  --run-dir .ralph-system4u-20260728 \
  docs/approved-phases.md
```

The allowlist is line-based: exact files or directory prefixes ending in `/`; blank lines and `#` comments are ignored. It must be committed before the run and may not include globs, traversal, secrets, Git metadata, or generated/runtime directories.

### Invariants

1. Every phase **and** every fix cycle runs in a fresh session with a self-contained prompt. Sessions are never reused.
2. Zero questions — fully autonomous execution.
3. A phase is only "complete" when it passes the **4 mechanical gates**, never by the engine's exit code.
4. API usage limit → waits for the reset and re-runs the **same** phase, without consuming a fix cycle.
5. **One commit per completed phase** (`feat(phase-N): <title>`).

### The 4 gates

| Gate | Question | How it decides |
|---|---|---|
| 0 | Did the engine actually finish? | claude: `is_error` in the result JSON; codex: exit code |
| 1 | Did the session write code? | Tree signature before/after. **A signal, not a verdict** — an already-implemented phase makes the engine (correctly) write nothing; the signal feeds the fix-cycle cause |
| 2 | Do the configured tests pass? | Run **by ralph itself on the host**, outside the agent session. With staged commands, Gate 2a runs focused tests each cycle and Gate 2b runs the final suite only after 2a is green |
| 3 | Is each task actually in the code? | Independent read-only verifier session that emits `TASK <n>: DONE/INCOMPLETE` per task. It receives Gate 2's authoritative result and log paths, and runs on every phase by default (`RALPH_VERIFY=always`); on the Claude engine it uses a cheap model (haiku) |

Any red gate → **fix cycle**: a fresh session receives the full phase + a bounded excerpt of the real failure cause (never a generic "tests failed"). Correction prompts use the current phase, changed paths, and directly related evidence instead of replaying historical logs and the entire discovery chain. The default hard cap remains **12 total cycles per phase** for compatibility; use `--max-cycles 3` for a tighter runtime budget.

The first failure is the progress reference. A consecutive repetition of the same gate + normalized cause + tree signature increments stagnation; a different gate, finding, or tree resets the counter. The default `--max-stalled-cycles 2` stops after two consecutive corrective repetitions without progress. A phase therefore ends green, at the hard cap, on stagnation, or because an operational/guardrail/commit failure could not be corrected within those limits; preflight failures abort before the first session.

Usage limits are handled separately: ralph waits for the reset and re-runs the same numbered session without consuming a fix cycle. To avoid waiting forever, `RALPH_MAX_LIMIT_WAITS` caps consecutive waits per phase (default: 20).

Green gates with a clean tree → the phase was already implemented at HEAD: marked done, no commit.

### Gate 3 configuration, runtime, and logs

Verifier model and reasoning follow **flag > environment variable > inherited engine configuration** precedence. For Codex, reasoning accepts `minimal`, `low`, `medium`, `high`, or `xhigh` and is passed as `model_reasoning_effort`; without an override, model and reasoning are inherited. For Claude, the model default remains `haiku`, and any reasoning override fails at preflight because it is not applicable.

Before each verification, the terminal records `gravando` (recording), engine, requested model/reasoning (or `herdado`/inherited and `nao aplicavel`/not applicable), the `read-only` sandbox, and the log path. This is the **requested configuration**. For Codex, the header emitted by the CLI reveals the **effective runtime**; its model and reasoning lines are mirrored to the terminal even with `--quiet`, while the complete header remains in the log.

Artifacts are separated by phase and cycle under `.phases/logs/` by default, or `<run-dir>/logs/` with `system4u-autonomous`: `phase-NN.cycle-C.log` for implementation/fixes, `phase-NN.focused-C.log` for staged Gate 2a, `phase-NN.test-C.log` for the legacy Gate 2 or staged Gate 2b, and `phase-NN.verify-C.log` for Gate 3. Every Gate 3 run requires an existing, non-empty verification log; a missing or empty file leaves the gate red with an explicit operational cause and the corresponding path in the summary.

### Functional versus operational authorization

An **application-level** authentication, authorization, isolation, policy, gate, or permission finding is fixable without pausing when it appears in the approved phase text or gate cause; the fix cycle must implement and test that functional requirement.

This does not expand the agent's operational authorization. Project rules, sandbox, allowlist, file boundaries, and prohibitions on reading secrets, unauthorized external calls, destructive migrations, deploy, push, merge, tag, and release still apply.

### Test command detection (gate 2)

The legacy/final command resolves as `--test-cmd` → `RALPH_TEST_CMD` → manifest detection (Laravel Sail → `composer test` → `php artisan test` → `npm test` → `pytest` → `go test ./...` → `cargo test`). Without a focused command it remains the single Gate 2. When `--focused-test-cmd` / `RALPH_FOCUSED_TEST_CMD` is set, it becomes Gate 2a and `--final-test-cmd` / `RALPH_FINAL_TEST_CMD` becomes Gate 2b; if no explicit final command is set, the legacy command is used as Gate 2b. A focused command without any resolvable final suite fails at preflight.

Laravel Sail projects: Ralph invokes the Sail wrapper **from the host**, preferring an executable project wrapper (`./sail test`) before falling back to `vendor/bin/sail test`. This preserves project-defined service/user overrides while still running the suite inside the container. Stopped containers abort at preflight. The agent prompt is told not to retry Docker from a restricted sandbox or switch runners; the host-owned Gate 2 remains authoritative.

### Options and variables

| Option | Effect |
|---|---|
| `--engine codex\|claude` | Implementation engine (default: `codex`) |
| `--from N` | Starts at phase N (clears progress for phases ≥ N) |
| `--only-phase N` | Runs only phase N and stops; cannot be combined with `--from` or `--stop-after` |
| `--stop-after N` | Stops successfully after phase N is completed |
| `--keep-going` | Continues after a phase fails (creates a `wip(phase-N)` commit; default: stop) |
| `--max-cycles N` | Total hard cap per phase, including the initial implementation (default: 12) |
| `--max-stalled-cycles N` | Consecutive corrective repetitions without progress after the first reference failure (default: 2) |
| `--model MODEL` | Model for implementation and correction sessions; takes precedence over `RALPH_MODEL` |
| `--reasoning EFFORT` | Codex reasoning for implementation and, by default, correction sessions |
| `--fix-reasoning EFFORT` | Codex reasoning used only by correction cycles; takes precedence over `RALPH_FIX_REASONING` |
| `--verify-model MODEL` | Gate 3 model; takes precedence over `RALPH_VERIFY_MODEL` |
| `--verify-reasoning EFFORT` | Codex Gate 3 reasoning (`minimal\|low\|medium\|high\|xhigh`); takes precedence over `RALPH_VERIFY_REASONING` |
| `--test-cmd "<cmd>"` | Project test command (gate 2) |
| `--focused-test-cmd "<cmd>"` | Fast test command run as Gate 2a on every cycle |
| `--final-test-cmd "<cmd>"` | Final suite run as Gate 2b after Gate 2a is green |
| `--no-verify` | Disables gate 3 |
| `-q`, `--quiet` | Hides raw Codex/Claude output from the terminal and prints a summary when each phase ends; full logs remain in the active artifact log directory |
| `--profile system4u-autonomous` | Guarded non-interactive Codex profile: workspace-write, explicit allowlist, no WIP commits or destructive cleanup |
| `--allowed-paths-file <path>` | Required repository-relative allowlist for `system4u-autonomous` |
| `--run-dir <path>` | Fresh local artifact directory for `system4u-autonomous` (default: `.ralph-system4u`) |
| `-h`, `--help` | Prints the complete operational contract and exits |

| Variable | Effect |
|---|---|
| `RALPH_TEST_CMD` | Test command (gate 2) |
| `RALPH_FOCUSED_TEST_CMD` | Focused test command (staged Gate 2a) |
| `RALPH_FINAL_TEST_CMD` | Final test suite (staged Gate 2b) |
| `RALPH_MODEL` | Model for implementation/correction sessions |
| `RALPH_REASONING` | Codex reasoning for initial implementation and the correction fallback |
| `RALPH_FIX_REASONING` | Codex reasoning used only on correction cycles |
| `RALPH_VERIFY` | Gate 3: `always` (default) \| `auto` (saves tokens: only when gate 2's verdict isn't enough) \| `off` |
| `RALPH_VERIFY_MODEL` | Verifier model (Claude default: `haiku`; inherited in Codex) |
| `RALPH_VERIFY_REASONING` | Codex verifier reasoning; not applicable to Claude |
| `RALPH_MAX_CYCLES` | Total hard cap per phase (default: 12) |
| `RALPH_MAX_STALLED_CYCLES` | Consecutive corrective repetitions without progress (default: 2) |
| `RALPH_QUIET` | `true` or `false` (default: `false`) |
| `RALPH_MAX_LIMIT_WAITS` | Consecutive usage-limit waits, per phase (default: 20) |
| `RALPH_LIMIT_WAIT_DEFAULT` | Fallback wait in seconds (default: 1800) |
| `RALPH_LIMIT_BUFFER` | Extra seconds after the reset (default: 60) |

During each session, ralph exports `RALPH_ENGINE`, `RALPH_PHASE_TITLE`, `RALPH_PHASE_NUM`, `RALPH_PHASE_TOTAL`, `RALPH_PHASE_ATTEMPT`, and `RALPH_PHASE_MAX_ATTEMPTS` — useful for notification hooks (e.g. n8n). `RALPH_PHASE_ATTEMPT=1` identifies the initial implementation; usage-limit retries preserve the same value. `RALPH_PHASE_MAX_ATTEMPTS` contains the effective hard cap resolved from flag/env/default.

### State and progress

Internal work lives in `.phases/` (registered in `.git/info/exclude`, without touching the project's `.gitignore`): split phases, prompts, logs, manifest, and `.progress`. Progress survives across runs, but only for the **same input** (sha256 stamp) — a changed phase document resets progress.

`--only-phase N` leaves other phase progress untouched. `--stop-after N` records every successfully completed phase through N and exits before starting the next one.

Exit code: `0` = all phases green; `1` = some phase failed or aborted.

### Input format contract

Validated at preflight:

- ≥ 1 heading `## Phase N: <title>`
- No `## Phase ...` heading outside that format (a malformed heading silently disappears from the run — preflight aborts before burning tokens)
- Sub-phases as `### Phase N.M:` (do not become their own session)
- Any other `## ` heading ends the previous phase's capture

## Agents

Commands are **thin routers** — all template knowledge lives in the agents:

| Agent | Pipeline | Role |
|---|---|---|
| `specifier` | `/plan` §5 | Confirmed description + ACs → formal SPEC.md (GEARS, RIGID/FLEXIBLE) |
| `clarifier` | `/plan` §6 | Adversarial requirements QA: finds ambiguities, resolves them with the developer's answers |
| `planner` | `/plan` §7 | SPEC → PLAN.md + PHASES.md + contracts; read-only over the code |
| `ai-context-inspector` | `/ai-context` §3 | Read-only repo sweep → structured digest |
| `ai-context-core` | `/ai-context` §4 | Digest → `AGENTS.md` + `CLAUDE.md` |
| `ai-context-docs` | `/ai-context` §4 | Digest → the 8 `docs/agents/*.md` files |

The two `/ai-context` writers run in parallel (disjoint files, read-only digest).

## Repository structure

```
.claude-plugin/plugin.json     plugin manifest
commands/
  init.md                      /init (diagnostic router)
  init/                        /init:project-description, user-stories,
                               database-schema, project-phases
  plan.md                      /plan (planning pipeline router)
  ai-context.md                /ai-context (context tree router)
agents/                        specifier, clarifier, planner,
                               ai-context-{inspector,core,docs}
scripts/
  ralph.sh                     phase-by-phase execution orchestrator
  test-ralph.sh                red/green suite for ralph with a mock engine
  check-init-drift.sh          guards against textual drift of the rules
                               duplicated across the init commands
  check-shell.sh               bash -n + shellcheck over scripts/*.sh
docs/plans/                    internal hardening plans for the harness
```

## Development

```bash
scripts/test-ralph.sh        # ralph.sh suite — fake `claude`/`codex` binaries
                             # on PATH, zero network, zero tokens; exit 0 = green
scripts/test-ralph.sh <case> # run a single case
scripts/check-shell.sh       # bash -n over all scripts + shellcheck when available
scripts/check-init-drift.sh  # verbatim anchors for the shared init:* rules
```

About `check-init-drift.sh`: the four `commands/init/*.md` files **intentionally inline** the same interview, language, re-run, and staleness rules — plugin commands must be self-contained at runtime (they execute inside the developer's project, where the plugin root is not reachable via `@`-includes). The cost of that duplication is silent drift; the script makes drift loud.

## Design principles

- **Thin routers, agents own the content** — commands orchestrate, verify artifacts on disk, and report; they never author SPEC/PLAN/docs.
- **Trust, but verify** — every artifact delivered by an agent is mechanically validated (existence, headings, counts) by the router.
- **Reality ≠ intent** — `/ai-context` documents only what is implemented; `.spec/` is invisible to it. The `.spec/` chain documents intent.
- **No git writes from commands** — the developer reviews with `git diff` and commits manually. The only thing that commits is `ralph.sh`, by design (one commit per validated phase).
- **No secrets** — `.env` is never read; env var names come from `.env.example` only.
- **Explicit, never blocking staleness** — sha256 stamps detect outdated inputs; the decision always belongs to the developer.

## License

[MIT](LICENSE)
