Translation rules live in `bin/emit.sh` (Windows: `bin/emit.cmd`); this file is caveats only.

# Emitter: Claude Code

Target: `.claude/` — canonical format. The `CLAUDE.md` pointer and
`.claude/settings.json` merge content is embedded in `bin/emit.sh`.
Appends a separate `## Memory` block (marker `<!-- orchestration-kit:memory-pointer -->`) after the orchestration pointer when absent.

## Harness specifics

**Ready groups:** for write-disjoint Phase 4 tasks the orchestrator launches parallel
Agent spawns (documented; default limit 20 concurrent — `Concurrent subagent limit
reached` means fall back to sequential); kit runs ready groups. Set `parallel: false`
on a goal to force groups of one.

Orchestrator spawn allowlists use this literal tools line:

tools: Agent(implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician, evidence-collector)

`terminal` is on the allowlist so callers can spawn it; `diagnostician` joins
for rung 4; `evidence-collector` gathers QA evidence before `qa-evaluator` when
the QA gate runs. P0 skills keep `disable-model-invocation: true` (this emitter never
strips frontmatter keys).

Model values: Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) or full IDs
are both valid; `inherit` is the frontmatter default if a tier is deliberately
unpinned. `fable` is never valid in a loop chain — emit exits 3. Claude Code
runs **Anthropic models only** — a cross-family arbiter is unreachable
natively; use the same-family arbiter flag when the arbiter ID equals
frontier. Prefer full IDs; aliases resolve per provider (see the model-config
docs). Record the minimum Claude Code version for each pinned model (check
`claude --version` against the docs' per-model floor).

Pin nesting explicitly — the default flipped twice in July 2026. Merge
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=3` into `.claude/settings.json` (merge,
don't overwrite).

Loop-enabled installs emit `_loop/loop.sh`, `_loop/breaker.sh`, `_loop/PROMPT.md`, and the
`_loop/loop.cmd` Windows launcher. `_memory/loop/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/trace-lint.sh` and `_kit/trace-lint.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/memory.sh`, `_kit/memory.cmd`, and `_memory/README.md` (single-copy), appends `_memory/work/`, `_memory/.index/`, and `_memory/raw/` to `.gitignore`, and appends `_memory/** text eol=lf` and `*.cmd -text` to `.gitattributes`; loop emits also add `*.sh text eol=lf`, union-merge `_memory/loop/LEARNINGS.md` and `_memory/loop/ESCALATIONS.md` and gitignore `_memory/loop/breaker-state.json`, `_memory/loop/ledger.jsonl`, and `_memory/loop/attempts/`; `_memory/records/` and `_memory/quarantine/` stay tracked.
Post-hoc transcript capture scans `~/.claude/projects/<slug>/*.jsonl` under `$HOME` (see
`_memory/README.md`); distillation uses the emitted `memory-capture` skill.

**Opt-in (`flags.opt_in`):** the three orchestrator skills (`feature`, `research`,
`memory-capture`) also carry `disable-model-invocation: true`, and the seven kit
agents' descriptions carry the orchestration-kit scope prefix (full support on Claude
Code).

**Kit-file guard (`flags.kit_guard`):** when `.claude/settings.json` is absent, emit
writes a `PreToolUse` hook:
`matcher` `Edit|Write|MultiEdit|NotebookEdit`, command
`bash "$CLAUDE_PROJECT_DIR/_kit/kit-guard.sh" hook claude` (exit **2** blocks).
When the file already exists without that hook, emit leaves it untouched and prints
the merge snippet on stderr (see `bin/README.md`). ORCHESTRATION.md Repository safety
item 4 and agent read-only rules apply; the feature skill tracks Orchestration
Progress under `_memory/work/goals/[goal]/progress.md`.

**Hook telemetry (`flags.hook_telemetry`):** emits `_kit/hook-log.sh` and
`_kit/hook-log.cmd`. When `.claude/settings.json` is absent, emit writes `Stop`,
`SubagentStop` and `StopFailure` hooks (in that order), each with the command
`test -f "$CLAUDE_PROJECT_DIR/_kit/hook-log.sh" && bash "$CLAUDE_PROJECT_DIR/_kit/hook-log.sh" hook claude || true`
(guarded, so a fresh clone without `_kit/` shows no hook error). `StopFailure` fires when a
turn ends on an API error and is logging-only (no decision control); the hook logs it with
status `error` and the documented `error` type. With `flags.kit_guard`
also on, the one created file holds both, `PreToolUse` first. When the file already
exists without the hooks, emit leaves it untouched and warns with the merge snippet
(`warning: .claude/settings.json exists without the hook-telemetry hooks — left untouched; merge into it: …`,
see `bin/README.md`); a file that has the telemetry hooks but no `StopFailure` entry gets its own
warning with the entry to add
(`warning: .claude/settings.json has the hook-telemetry hooks but no StopFailure hook — left untouched; add to its "hooks" object: "StopFailure":[…]`).
Each stop appends one metadata line to
`_memory/work/hooks/events.jsonl` (gitignored); on a Cursor caller the hook skips.
