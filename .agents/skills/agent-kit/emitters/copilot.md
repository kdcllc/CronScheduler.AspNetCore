Translation rules live in `bin/emit.sh` (Windows: `bin/emit.cmd`); this file is caveats only.

# Emitter: GitHub Copilot (VS Code)

Target: `.github/`. Check the live VS Code custom-agents page
(https://code.visualstudio.com/docs/agent-customization/custom-agents)
before pinning tool names.

## Harness specifics

**Ready groups:** for write-disjoint Phase 4 tasks the orchestrator may try parallel
`runSubagent` spawns; concurrency is ⚠️ unverified — fall back to sequential on a
concurrency error. Set `parallel: false` on a goal to force groups of one.

**Cost ceiling**: a subagent cannot run a stronger model than the session; a
too-strong pin makes the subagent **not run at all**. Orchestrated sessions
run the frontier tier; evaluators never pin above it; workers pin down.
Copilot has no `effort` key.

Nesting stays off (kit default). `chat.subagents.allowInvocationsFromSubagents`
must not be enabled by `/agent-kit`. Do not write `.vscode/settings.json`.
`feature.agent.md` is the L1 orchestrator and spawns workers and evaluators
directly; that top-level spawn works with nesting off. Workers do not spawn
subagents of their own; when output needs isolating, spawn `terminal`.

Skills: copy `disable-model-invocation` as-is on
`.github/skills/*/SKILL.md`. Subagents are stateless — context packages must
be complete on first send.

The copilot-instructions pointer content is embedded in `bin/emit.sh`.
Appends a separate `## Memory` block (marker `<!-- orchestration-kit:memory-pointer -->`) after the orchestration pointer when absent.

Loop-enabled installs emit `_loop/loop.sh`, `_loop/breaker.sh`, `_loop/PROMPT.md`, and the
`_loop/loop.cmd` Windows launcher. `_memory/loop/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/trace-lint.sh` and `_kit/trace-lint.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/memory.sh`, `_kit/memory.cmd`, and `_memory/README.md` (single-copy), appends `_memory/work/`, `_memory/.index/`, and `_memory/raw/` to `.gitignore`, and appends `_memory/** text eol=lf` and `*.cmd -text` to `.gitattributes`; loop emits also add `*.sh text eol=lf`, union-merge `_memory/loop/LEARNINGS.md` and `_memory/loop/ESCALATIONS.md` and gitignore `_memory/loop/breaker-state.json`, `_memory/loop/ledger.jsonl`, and `_memory/loop/attempts/`; `_memory/records/` and `_memory/quarantine/` stay tracked.
No supported Copilot transcript export — session summaries use the `memory-capture`
skill's **orchestrator-written fallback** (see `feature/reference/memory-capture.md`).

**Opt-in (`flags.opt_in`):** the three orchestrator skills (`feature`, `research`,
`memory-capture`) under `.github/skills/` also carry `disable-model-invocation: true`, and
the seven kit agents' `.github/agents/*.agent.md` descriptions carry the orchestration-kit
scope prefix (full support). `.github/agents/feature.agent.md` is built from the same
template, so it also carries `disable-model-invocation: true` and the opt-in sentence.
The `.github/copilot-instructions.md` pointer is a user file and is not rewritten.

**Kit-file guard (`flags.kit_guard`):** no edit-blocking hook is emitted — emit warns
`warning: flags.kit_guard is partial on copilot: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)`.
`emit.sh --check` / `_kit/kit-guard.sh check` and ORCHESTRATION.md read-only rules
still apply.

**Hook telemetry (`flags.hook_telemetry`) — partial:** `_kit/hook-log.sh` and
`_kit/hook-log.cmd` are emitted, but no telemetry hook is — emit warns
`warning: flags.hook_telemetry is partial on copilot: no telemetry hook`.
On an install that also targets Claude Code, Copilot may run the repository
`.claude/settings.json` hooks when its agent hooks are enabled; those runs log under
harness `claude` only when `$CLAUDE_PROJECT_DIR` is set under Copilot 🔎 (unconfirmed:
`reference/harness-matrix.md`, 2026-10-27 addendum, fact 9). If it is unset, the guarded
command's `test -f` fails and nothing is logged. 🔎 That assumes Copilot runs the hook command in a POSIX
shell (`test`, `&&`, `||`); its hook shell, notably on Windows, is unverified.
