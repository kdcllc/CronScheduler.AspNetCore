Translation rules live in `bin/emit.sh` (Windows: `bin/emit.cmd`); this file is caveats only.

# Emitter: OpenAI Codex

Target: `AGENTS.md` + `.codex/`. No agent markdown format — roles live in
`config.toml` tables, instructions in AGENTS.md (plain markdown, no
frontmatter, **32 KiB combined cap**, read once per session). The `[agents.*]`
tables and the AGENTS.md pointer are embedded in `bin/emit.sh`.
Append the pointer to `AGENTS.md` (create if missing; keep ≤ 32 KiB).
Appends a separate `## Memory` block (marker `<!-- orchestration-kit:memory-pointer -->`) after the orchestration pointer when absent.

## Harness specifics

**Ready groups:** for write-disjoint Phase 4 tasks the orchestrator may try parallel
spawns; concurrency is ⚠️ unverified (`max_concurrent_threads_per_session` /
`max_threads` are reserved names only) — fall back to sequential on a concurrency
error. Set `parallel: false` on a goal to force groups of one.

Project-scoped `.codex/config.toml` loads only for **trusted** projects, and
`model_provider`, `model_providers`, `profile`, `profiles`, `notify`, `otel`
are ignored at project level — pin models, not providers.

Multi-agent tools (`spawn_agent`, `wait_agent`, …) are stable and on by
default; do not gate on `features.multi_agent` unless the project has
disabled it.

AGENTS.md is read once at session start — edits require a new session.
Re-check https://developers.openai.com/codex/config-reference if any key is
rejected.

Loop-enabled installs emit `_loop/loop.sh`, `_loop/breaker.sh`, `_loop/PROMPT.md`, and the
`_loop/loop.cmd` Windows launcher. `_memory/loop/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/trace-lint.sh` and `_kit/trace-lint.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/memory.sh`, `_kit/memory.cmd`, and `_memory/README.md` (single-copy), appends `_memory/work/`, `_memory/.index/`, and `_memory/raw/` to `.gitignore`, and appends `_memory/** text eol=lf` and `*.cmd -text` to `.gitattributes`; loop emits also add `*.sh text eol=lf`, union-merge `_memory/loop/LEARNINGS.md` and `_memory/loop/ESCALATIONS.md` and gitignore `_memory/loop/breaker-state.json`, `_memory/loop/ledger.jsonl`, and `_memory/loop/attempts/`; `_memory/records/` and `_memory/quarantine/` stay tracked.
Codex-only installs emit **no kit skills tree** — document `capture` and distillation in
project docs only. `_kit/memory.sh capture --harness codex` is best-effort against
`~/.codex/sessions/` rollout JSONL (see `_memory/README.md`).

**Opt-in (`flags.opt_in`) — partial:** no kit skills tree to gate. `[agents.*]`
descriptions are prefixed only when emit writes the agent tables (new installs); an
existing `.codex/config.toml` with the kit marker is never rewritten. The `AGENTS.md`
pointer is unchanged. Emit warns:
`warning: flags.opt_in is partial on codex: no kit skills tree to gate, and an existing .codex/config.toml agent table is never rewritten`.

**Kit-file guard (`flags.kit_guard`):** no edit-blocking hook — emit warns
`warning: flags.kit_guard is partial on codex: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)`.
`emit.sh --check` / `_kit/kit-guard.sh check` and ORCHESTRATION.md read-only rules
still apply.

**Hook telemetry (`flags.hook_telemetry`) — partial:** `_kit/hook-log.sh` and
`_kit/hook-log.cmd` are emitted, but no telemetry hook is — emit warns
`warning: flags.hook_telemetry is partial on codex: no telemetry hook`.
