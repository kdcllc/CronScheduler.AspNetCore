# Harness Capability Matrix

Reference for the `agent-kit` skill's emitters. **Verified 2026-08-18** against official
docs for the interchange/capability table below (✅ = 3-vote adversarial verification
against the cited page; 🔎 = manually spot-verified against the live page; ⚠️ =
primary source, unverified). **Context/invocation/command-output addendum verified
2026-08-20** from live vendor docs (D = documented on the live page that day; I =
inferred; U = unknown) — see that section; it is not 3-vote adversarial. This space
moves fast — when an emitter hits behavior that contradicts this table, trust the
live docs, emit accordingly, and update this file with a new verified-on date.
**Headless-CLI usage row verified 2026-09-03** from live vendor docs.
**Model-currency addendum 2026-10-08** ingested from `_memory/research/model-currency-2026-10.md`
§2 (⚠️ = primary source cited by that report, not 3-vote adversarial; ⚠️ (secondary) =
community/secondary sources cited there).
**Native memory/transcripts/hooks addendum 2026-10-08** — see that section; uses the
research report's legend.
**Concurrent-spawn row 2026-10-16** — marks follow the top legend; 🔎 = live page spot-checked that day.
**Degraded-spawn row 2026-10-16** — marks follow the top legend; 🔎 = live page spot-checked that day.
**Path-scoped guidance row 2026-10-19** — Claude Code `.claude/rules/` `paths:` added; D = code.claude.com/docs/en/memory § Path-specific rules, spot-checked that day.
**Path-scoped subagent delivery observation 2026-10-20** — field report from a downstream install (Claude Code VS Code extension 2.1.241; probed 2026-08-25); IDE-extension-scoped, not CLI-probed and not 3-vote adversarial; re-probe after a Claude Code upgrade before relying on it.

## The interchange finding

The Claude Code format is the de-facto interchange format — which is why this kit's
canonical templates are Claude-format:

- Cursor natively reads `.claude/agents/`, `.codex/agents/`, `.claude/skills/`,
  `.codex/skills/` (`.cursor/` wins name conflicts). ✅ [cursor.com/docs/subagents, /skills]
- VS Code (Copilot) natively reads `.claude/agents` alongside `.github/agents`. ✅
  [code.visualstudio.com/docs/agent-customization/custom-agents]
- Caveat: directory *loading* is confirmed; per-field fidelity of Claude-specific keys
  (`tools:`, model aliases, `effort:`) is undocumented — emit translated per-harness
  copies for anything model- or tools-critical. (Claude Code raw-tree fidelity for
  name/description empirically verified 2026-08-18, CLI-observed; tools partial — see
  Empirical validation)
- **Kit policy:** the Cursor emitter emits a fully **self-contained**
  `.cursor/` tree and does not rely on this cross-read — per-field fidelity of
  Claude-specific keys is undocumented, and **dual-install** behavior (both `.claude/`
  and `.cursor/` present) must not depend on `.claude/`'s presence. The FACTS above
  remain true and verified; this is a kit emission policy built on top of them, not a
  correction to them.

## Capability table

| Capability | Claude Code | Cursor | Copilot (VS Code) | OpenAI Codex |
|---|---|---|---|---|
| Agent definition | `.claude/agents/*.md`, YAML frontmatter ✅ | `.cursor/agents/` + reads `.claude/agents/` ✅ | `.github/agents/*.agent.md` (ex-`.chatmode.md`) + reads `.claude/agents` ✅ | `[agents.<name>]` tables in `config.toml` (`config_file`, `description`) 🔎 |
| Skills | `.claude/skills/*/SKILL.md` ✅ | `.cursor/skills/` + reads `.claude/skills/`; `name`+`description` required; **no model key** ✅ | `.github/skills/*/SKILL.md` first-class (progressive disclosure, `/skill`, `disable-model-invocation`) ✅ 2026-08-20 | `skills.config` per-skill enablement 🔎 |
| Fresh-context subagents | Yes; nesting depth via `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default flipped twice July 2026 — **pin explicitly**) ✅ | Yes; main→L1→L2 since 2.5 🔎 — cursor.com/docs/subagents (spot-checked 2026-10-16): main agent and direct subagents can launch subagents; a subagent launched by another can't launch further; ⚠️ Cloud Agents-specific L1-only nesting cap not documented on spot-checked pages | Yes (`agent/runSubagent`, stateless); nesting off by default (`chat.subagents.allowInvocationsFromSubagents`, max 5) ✅ | Yes: `spawn_agent` et al., `features.multi_agent` stable, on by default 🔎 |
| Per-agent model pin | frontmatter `model:` (alias/ID/`inherit`); env > tool param > frontmatter > parent ✅; **Anthropic models only** — alias resolution is provider-dependent (full IDs pin reproducibly) ⚠️ [code.claude.com/docs/en/model-config, _memory/research/model-currency-2026-10.md §2] — addendum 2026-10-08 | frontmatter `model` incl. bracket params `[effort=…,context=…]` (e.g. `<model-id>[effort=high,context=300k]`); slug-suffix effort variants (e.g. `…-high`-shaped model IDs) also appear in Cursor's live model lists — both forms coexist; see the model map's guidance; up or down OK; **silent fallback** under restrictions — re-verified 2026-08-21 against cursor.com/docs/subagents ✅; bracket params are the documented frontmatter syntax ⚠️ [cursor.com/docs/subagents]; suffix slugs appear in listings ⚠️ (secondary) [_memory/research/model-currency-2026-10.md §2]; unresolved subagent models **fall back to the parent's model** ⚠️ [_memory/research/model-currency-2026-10.md §2 — Cursor staff, Aug 2026] (the docs page itself says only that Cursor "falls back to a compatible model" under admin blocks / plan limits); quoting the YAML value can trigger this ⚠️ (secondary) [_memory/research/model-currency-2026-10.md §2] — addendum 2026-10-08 | frontmatter `model` (string or fallback array); **cannot exceed parent tier** — stronger refuses to run; cheaper-than-parent is valid; CLI rejects array form ✅ | `agents.default_subagent_model`, per-role `config_file`; spawn-time wins 🔎; standalone `.codex/agents/*.toml` custom agents are documented but **not used by this kit** ⚠️ [developers.openai.com/codex/config-reference, _memory/research/model-currency-2026-10.md §2] — addendum 2026-10-08 |
| Effort pin | `effort:` low→max on agents/skills/commands ✅ | `[effort=…]` bracket param (e.g. `[effort=high]`) — re-verified 2026-08-21 against cursor.com/docs/subagents, same scheme as the model-pin row above ✅ | — | `default_subagent_reasoning_effort` 🔎; values `low \| medium \| high \| xhigh \| max \| ultra` (model-dependent) ⚠️ [developers.openai.com/codex/config-reference, _memory/research/model-currency-2026-10.md §2] — addendum 2026-10-08 |
| Rules/instructions | `CLAUDE.md`; reads `AGENTS.md` only when no `CLAUDE.md` / `.claude/CLAUDE.md` / `CLAUDE.local.md` exists in cwd or above (v2.1.277+) — a kit install's `CLAUDE.md` pointer suppresses it; import AGENTS.md from CLAUDE.md to load both ✅ (2026-10-08) | `.cursor/rules/*.mdc` only (plain `.md` ignored); keys `alwaysApply`/`description`/`globs`; native nested AGENTS.md ✅ | `.github/copilot-instructions.md`, `.github/instructions/` | AGENTS.md root-down concat, nearest-last-wins; **32 KiB cap** (`project_doc_max_bytes`); read once per session 🔎 |
| Role controls | `tools: Agent(implementer, test-writer)` allowlists; skill `disable-model-invocation: true` drops the description from session-start context ✅ 2026-08-20 | description-driven or `/name`; L1 agents may need explicit "you MUST spawn" prompting; skill `disable-model-invocation: true` (same spelling) ✅ 2026-08-20 | `agents:` allowlist, `user-invocable: false` (agents *and* skills, different meaning), skill/agent `disable-model-invocation: true` ✅ | role `description` guides spawn 🔎 |
| Unattended mode | headless `claude -p` ⚠️ | Cloud Agents 🔎 — same nesting rule as Fresh-context row (spot-checked 2026-10-16); ⚠️ Cloud Agents-specific L1-only unattended cap not documented on spot-checked pages | Copilot coding agent on issues ⚠️ | `approval_policy: never` + `sandbox_mode` 🔎 |
| Token usage exposure (headless CLI) | `claude -p --output-format json` → `usage` + `total_cost_usd` ✅ (verified 2026-09-03) | `agent -p --output-format json` → camelCase `usage` (`inputTokens` = uncached only) ✅ (verified 2026-09-03) | none documented ❌ | `codex exec --json` → `turn.completed.usage` incl. `reasoning_output_tokens` ✅ (verified 2026-09-03) |
| Kit transcript capture (`_memory/raw/`, gitignored) | `_kit/memory.sh capture` scans `~/.claude/projects/<slug>/*.jsonl` under `$HOME` | `_kit/memory.sh capture` scans `~/.cursor/projects/<slug>/agent-transcripts/` | orchestrator-written fallback only (no export API) | `_kit/memory.sh capture --harness codex` best-effort on `~/.codex/sessions/`; docs-only skills tree |
| Kit memory backfill (`backfill`, deterministic) | `_kit/memory.sh backfill --plan` / `--apply` (Windows outside Git Bash: `_kit\memory.cmd`) | same | same | same |
| Kit memory prune (`prune`, deterministic) | `_kit/memory.sh prune --plan` / `--apply` (Windows outside Git Bash: `_kit\memory.cmd`); feature Phase 2 runs `--apply` before recall | same | same | same |
| Kit workflow layout (emit) | In-flight goals/research under gitignored `_memory/work/`; loop backlog/ledgers under tracked `_memory/loop/` (`backlog.md` seed). Legacy top-level `_goals/` / `_research/` move whenever emit finds them (`git mv` when tracked). | same | same | same |
| Concurrent subagent spawns (ready groups) | 🔎 documented — code.claude.com/docs/en/sub-agents § Run parallel research (spot-checked 2026-10-16): "For independent investigations, spawn multiple subagents to work simultaneously"; § Concurrent subagent limit: default 20 running, spawning past it fails with `Concurrent subagent limit reached` (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, v2.1.217+); subagents share the checkout unless `isolation: worktree` — kit runs ready groups | 🔎 documented — cursor.com/docs/subagents § Parallel execution (spot-checked 2026-10-16): "Agent sends multiple Task tool calls in a single message, so subagents run simultaneously"; same page warns subagents share the parent checkout and concurrent edits can overwrite each other; supporting local observation (not ✅): concurrent worktree-less writers observed in this repo's own runs; nesting per Fresh-context row (spot-checked 2026-10-16); ⚠️ Cloud Agents-specific L1-only cap not documented — concurrency there unverified — kit runs ready groups | ⚠️ unverified (`runSubagent` stateless; concurrency not verified) — kit tries parallel ready groups, falls back to sequential on concurrency error | ⚠️ unverified — reserved `[agents]` names `max_concurrent_threads_per_session`, `max_threads` only (verified 2026-08-21); behavior inferred, not verified — kit tries parallel ready groups, falls back to sequential on concurrency error |
| Degraded spawn conditions (model pin rejected / no spawn tool) | ⚠️ not documented as a degraded condition; nesting is capped by `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (see Fresh-context subagents row) — kit falls back to degraded mode if it happens | 🔎 spot-checked 2026-10-16 — cursor.com/docs/subagents: "You can use subagents in the editor, CLI, and Cloud Agents"; model config honors frontmatter `model` with admin/plan/Max-Mode fallbacks ("In these cases, Cursor falls back to a compatible model"); "Cloud subagents … follow the same model and capability rules as other Cloud Agents"; spawn can fail 🔎 — "a subagent launched by another subagent can't launch further ones" and "Nested launches also need Task tool access in the current mode, and hooks or tool policies can block spawning"; cursor.com/docs/cloud-agent Models: "Cloud Agents use a curated selection of models"; ⚠️ not documented on those pages whether Cloud Agents always ignore custom `model` pins or run as the parent model; ⚠️ no Cloud-Agent-specific L1 nesting limit documented on spot-checked pages — kit: see degraded mode (model pin rejected → inherit; no spawn tool → self-performed roles, disclosed gates) | ⚠️ not documented as a degraded condition; a `model` stronger than the parent refuses to run (see Per-agent model pin row) and subagent nesting is off unless `chat.subagents.allowInvocationsFromSubagents` is set (see Fresh-context subagents row) — kit falls back to degraded mode if it happens | ⚠️ not documented — kit falls back to degraded mode if it happens |

### Opt-in (`flags.opt_in`) — verified 2026-10-27

Description-scoped delegation is guidance the model follows, not an enforced gate (🔎).

| Harness | Support | Notes |
|---|---|---|
| Claude Code | ✅ full | Skill `disable-model-invocation: true` on orchestrator skills; agent descriptions scoped via template prefix. `CLAUDE.md` orchestration pointer is a user file — unchanged. |
| Cursor | ✅ full | Same `disable-model-invocation` key (skill translation); kit-owned `.cursor/rules/orchestration.mdc` rewritten to opt-in wording on upgrade. |
| Copilot (VS Code) | ✅ full | `.github/skills/*/SKILL.md` and `.github/agents/feature.agent.md` carry the flag; `.agent.md` descriptions scoped. `.github/copilot-instructions.md` pointer unchanged. |
| OpenAI Codex | 🔎 partial | No kit skills tree; `[agents.*]` descriptions scoped only when emit writes agent tables (new install). Existing `.codex/config.toml` with the kit marker is never rewritten. `AGENTS.md` pointer unchanged; emit warns on stderr. |

### Kit-file guard (`flags.kit_guard`) — verified 2026-10-27

Agent edit hooks are enforced by the harness (✅ per vendor hook docs); path-field parsing for Cursor `Write`/`Delete` is 🔎 (guard checks `file_path`, `notebook_path`, `path`, `target_file`).

| Harness | Edit hook | Check + rule text |
|---|---|---|
| Claude Code | ✅ `PreToolUse` in `.claude/settings.json`; exit **2** blocks (code.claude.com/docs/en/hooks) | ✅ ORCHESTRATION.md item 4; feature progress in `_memory/work/goals/[goal]/progress.md` |
| Cursor | ✅ `preToolUse` in `.cursor/hooks.json`; exit **2** denies (guard prints JSON `permission: deny`); an exit-**0** reply that is not valid JSON blocks, so guard allow paths print `{"permission":"allow"}`; matcher `Write|Delete` ✅ (cursor.com/docs/agent/hooks). Cursor loads Claude Code hooks from `.claude/settings.json` too ✅ — dual-harness may run the guard twice; reply format for third-party hooks 🔎 (`hook claude` detects Cursor caller JSON) | same |
| Copilot (VS Code) | ⚠️ agent hooks Preview — not used by this kit | ✅ `emit.sh --check`; partial warning on emit |
| OpenAI Codex | — no edit hook | ✅ `emit.sh --check`; partial warning on emit |

All harnesses: hooks cover agent edit tools, not shell or human edits; `check` detects those. Manifest and hook config files are user-writable exclusions — CI `check` is the backstop.

### Hook telemetry (`flags.hook_telemetry`) — verified 2026-10-29

Telemetry only: the hooks observe stops and never steer. Hook events and config shapes are documented by the vendors (✅ per vendor hook docs, not the top legend's 3-vote verification); 🔎 marks an unverified point. The hook configs are written only when the config file is absent; an existing file is left untouched and emit prints a merge snippet.

- **Claude Code:** ✅ per vendor hook docs: `Stop` + `SubagentStop` + `StopFailure` in `.claude/settings.json`, each with a guarded command (`test -f … && bash … hook claude || true`), so it stays silent when `_kit/` is missing (fresh clone) (code.claude.com/docs/en/hooks). `StopFailure` fires when a turn ends on an API error and is logging-only: the docs give it no decision control and say it runs for notification and logging purposes only (spot-checked 2026-10-30).
- **Cursor:** ✅ per vendor hook docs: `stop` + `subagentStop` with `loop_limit: 1` in `.cursor/hooks.json` (cursor.com/docs/agent/hooks), each with the guarded command `test -f _kit/hook-log.sh && bash _kit/hook-log.sh hook cursor || echo '{}'`, so a fresh clone without `_kit/` answers `{}` instead of failing the hook. 🔎 Cursor's hook shell on Windows is unverified: the guard assumes a POSIX shell (`test`, `&&`, `||`). Cursor also loads Claude Code hooks from `.claude/settings.json` ✅ per vendor hook docs, so on a dual install the claude hook skips a Cursor caller and Cursor logs only through its native hook.
- **Copilot:** 🔎 partial, no hook. Copilot may run repository `.claude/settings.json` hooks when its agent hooks are enabled (**documented**: code.visualstudio.com/docs/copilot/customization/hooks; numbered fact 8 under "Addendum 2026-10-27 — Cursor hook behavior"), and those runs log under harness `claude` only when `$CLAUDE_PROJECT_DIR` is set under Copilot 🔎 (unconfirmed, numbered fact 9 under the same addendum); if it is unset, the guarded command's `test -f` fails and nothing is logged. 🔎 That assumes Copilot runs the hook command in a POSIX shell (`test`, `&&`, `||`); its hook shell, notably on Windows, is unverified. Emit warns.
- **Codex:** 🔎 partial, no hook. Emit warns.

Windows note: per-harness CLI availability on Windows is unverified — the loop
drivers assume the harness CLI runs natively where invoked. **Kit tools** (`bin/emit.*`,
`_kit/memory.*`, `_kit/log-spawn.*`, `_kit/trace-lint.*`, `_kit/kit-guard.*` on `flags.kit_guard` installs, `_kit/hook-log.*` on `flags.hook_telemetry` installs, and `_loop/loop.cmd` on loop installs) require **Git for Windows** when invoked from cmd
or PowerShell via the `.cmd` launchers; inside Git Bash, call the `.sh` scripts with
`bash` directly ([windows-launcher.md](windows-launcher.md)). Loop-specific Windows caveats are in [windows-launcher.md § Loop on Windows: known limitations](windows-launcher.md#loop-on-windows-known-limitations).

## Friction points every emitter must respect

1. Cursor rules must be **`.mdc`** — a plain `.md` in `.cursor/rules` is silently ignored. ✅
2. `.claude/agents` uses comma-separated-string `tools:`; `.agent.md` uses YAML arrays. ✅
3. Cursor skills have no model key — pin models at the **agent** level for Cursor. ✅
4. Codex AGENTS.md has no frontmatter/schema — roles and models live in `config.toml`. 🔎
5. The exact `.cursor/agents` frontmatter schema was **refuted** in verification (0-3) —
   re-check `cursor.com/docs/subagents` live before emitting Cursor agent files,
   including the current model-ID/bracket-param format and the live model list (an
   unknown or stale model ID is substituted silently, with no error surfaced).
6. Copilot: the session runs the frontier tier (ceiling rule); evaluators cannot pin
   up. Workers and other subagents **may pin down**. The ceiling is “cannot exceed the
   parent tier,” not “must equal the parent tier.”
7. Copilot skills live at `.github/skills/*/SKILL.md` (first-class as of 2026-08-20).
   Do **not** inline skill bodies into agents on current VS Code; reserve inlining
   for a detected legacy build with no skills support.
8. `disable-model-invocation: true` is the same skill frontmatter key on Claude Code,
   Cursor, and Copilot. On Claude Code it removes the skill **description** from
   session-start context (“full skill loads when you invoke”). Copilot `.prompt.md`
   is the zero-metadata-tax analogue for manual-only workflows.
9. Command-output size cap is Claude-only (`BASH_MAX_OUTPUT_LENGTH`, default 30,000
   characters, middle-truncation). Cursor and Copilot document no equivalent; Copilot
   documents terminal `outputLocation` and a timeout, not a size cap. Isolate noisy
   commands in a light-tier subagent and capture quiet command forms at setup —
   never invent runner flags.
10. Codex agent-name rule — **verified on 2026-08-21** against
    `developers.openai.com/codex/config-reference`: `[agents.<name>]` custom role
    names must not collide with the reserved scalar setting names under `[agents]`
    (`enabled`, `default_subagent_model`, `default_subagent_reasoning_effort`,
    `interrupt_message`, `max_concurrent_threads_per_session`, `max_threads`);
    `evaluator` and `qa-evaluator` collide with none of them, so both names are
    confirmed safe under the live rule. The external report's stronger "simple ASCII
    names… `name` is the source of truth" phrasing was NOT found verbatim on that
    page as of this check — only the reserved-name-collision constraint above is
    independently confirmed; treat any broader ASCII/charset claim as still
    unverified.

## Context, skills invocation, and command-output isolation (verified 2026-08-20)

Session start injects skill **name + description only** (not bodies, not parameter
schemas) on all three IDEs. Typical metadata ≈ 50–105 tokens/skill (description
words × ~1.3) or ~100 tokens/skill per the Agent Skills spec community figure.
Full sources and the kit skill-by-skill verdict:
`_memory/research/token-efficient-skills.md`.

| Capability | Claude Code | Cursor | Copilot (VS Code) |
|---|---|---|---|
| Block auto-invoke, keep `/name` | `disable-model-invocation: true` (D) | `disable-model-invocation: true` (D) | `disable-model-invocation: true` (D) |
| “Only model invokes” | `user-invocable: false` (D) | via `paths` / agent-decides; no skill `user-invocable` doc (I) | `user-invocable: false` on skills (D); on `.agent.md` hides from picker but still spawnable |
| Manual-only prompt file | `.claude/commands/*.md` (D) | `.cursor/commands` / migrate-to-skills (D) | `.prompt.md` (D) |
| Path-scoped guidance | `.claude/rules/**/*.md` `paths:` frontmatter; skill `paths:`; nested CLAUDE.md (D) | `.mdc` `globs:` (D) | `.github/instructions/*.instructions.md` `applyTo` (D) |
| Skill body model pin | `model:` on skill (D) | **no skill model key** — pin on agent (D) | pin on agent/prompt (D) |
| Command-output isolation | subagent + `model: haiku`; `context: fork` (D) | built-in Bash subagent; custom agent model ID (D) | `runSubagent` (summary only); **model ≤ parent tier** — pinning *down* is valid (D) |
| Output size cap | `BASH_MAX_OUTPUT_LENGTH` 30,000 default (D) | none (U) | none documented — only `outputLocation` / timeout (D) |
| Command-rewrite hook | PreToolUse `updatedInput` / PostToolUse `updatedToolOutput` (D) | `beforeShellExecution` / `afterShellExecution` in hooks.json (D) | agent hooks Preview; shell-rewrite not the documented pattern (I) |
| Cache-bust events | model, effort, fast-mode, compact, >1h, MCP change (D) | model/effort/context/tools change, inactivity (D) | model switch mid-session, instruction/agent change, inactivity (D) |
| `/context` equivalent | `/context` + `/doctor` (D) | Customize panel; dashboard usage (D; no token breakdown) | Cache Explorer + Diagnostics view (D) |
| Subagent nesting | subagents spawn subagents (D) | L1 + direct subagents spawn; grandchildren can't (D) | off by default; `chat.subagents.allowInvocationsFromSubagents` (D) |

In the Claude Code VS Code extension (field observation, 2.1.241; probed 2026-08-25) a
fresh subagent loaded root `CLAUDE.md` and unscoped rules at start, and scoped rules
injected only after it read a matching file with the Read tool (shell `cat`/`head`/`sed`
and the user opening the file in the editor did not trigger it). Cursor and Copilot
subagent delivery is unknown (U). The kit's policy stays routing through Critical
Reference Files and task context packages (`## Files to Read`).

## Empirical validation (2026-08-18, CLI-observed)

Live headless-CLI probes were run against per-harness scratch fixtures (outside this
repo, per story-001-harness-validation) to test per-field frontmatter fidelity
empirically rather than by documentation alone. Full detail, transcripts, and
per-claim evidence citations live in the session scratchpad's `hv-results.md`
(not committed to this repo — quoted here only where load-bearing).

**Method:** headless CLI probes (`claude -p`, `cursor-agent`, `copilot -p`) against
per-harness fixtures, instrumented with per-agent nonces embedded in `description:`
fields, file-read denial where the harness exposes a mechanism (Claude Code:
`--disallowedTools "Read,Grep,Glob,Bash"`), and a decoy negative-control agent/nonce
per fixture — a `honored` verdict requires nonce traversal under active denial AND
absence of the decoy nonce. Transcripts are retained in the session scratchpad
(`hv-*/probes/*.txt`) — not committed to this repo. **GUI/IDE behavior was not
exercised by any probe — every result below is CLI-scoped**, not evidence about any
IDE/GUI surface (VS Code Copilot chat panel, Cursor IDE panel, or a hypothetical
Claude Code IDE extension).

| Harness | `name` | `description` | `model` | `effort` | `tools` (injected-key test: `WebSearch, WebFetch`) |
|---|---|---|---|---|---|
| Claude Code (`claude`) | honored | honored | untestable (no model/effort metadata surfaced in captured output) | untestable (no model/effort metadata surfaced in captured output) | partial (ambiguity: injected pair returned verbatim — injected-key test credited — but the same reply also asserted file-visibility facts, e.g. directory contents and exact frontmatter key order/formatting, that the active `Read,Grep,Glob,Bash` denial should have made unobservable; downgraded from a clean `honored`) |
| Cursor (`cursor-agent`) | untestable (no model available for account) | untestable (no model available for account) | untestable (no model available for account) | untestable (no model available for account) | untestable (no model available for account) |
| Copilot (VS Code CLI, `copilot`) | partial (confound: file-read not deniable) | partial (confound: file-read not deniable) | untestable (no introspection surface; native file omits the keys) | untestable (no introspection surface; native file omits the keys) | partial (confound: file-read not deniable) |
| OpenAI Codex (`codex`) | untested — CLI absent | untested — CLI absent | untested — CLI absent | untested — CLI absent | untested — CLI absent |
| VS Code GUI (Copilot chat panel / Cursor IDE panel / any Claude Code IDE extension) | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment |

Cursor's arm was gated pre-budget: `cursor-agent models` reported "No models
available for this account" (`cursor-agent status` separately confirmed the account
is logged in, so this is a model-availability restriction, not an auth failure) —
zero probe budget was spent, including for the Q2 dual-emission (`.cursor/agents/*-cursor`)
schema-acceptance check. Copilot's initial two probes failed unauthenticated (auth
lost mid-session, on the first invocation after a clean auth smoke test; the
auto-update-caused-invalidation explanation is the most plausible read of the
observed sequence but is not itself transcript-proven) — a user-authorized re-auth
and re-probe superseded that unauthenticated state with the results in the table
above. Copilot exposes no file-read denial mechanism (`copilot help permissions`
documents only `shell()/write()/<mcp-server>()/url()` permission kinds, no
Read/Grep/Glob-equivalent), so no Copilot cell can clear `honored` regardless of
nonce fidelity — every re-probed cell caps at `partial`. `model`/`effort` remain
untestable for a different reason: the native `.agent.md` fixture deliberately
omits both keys (a sanctioned manifest deviation), leaving nothing to introspect
even with working auth.

Observed once (CLI-observed, n=1): with same-named `judge` (role renamed to
evaluator) agents in both `.github/agents` and `.claude/agents`, only the
native one surfaced in the recognition reply; mechanism unconfirmed — reply-level
dedup of same-named agents not excluded. Do not treat as a precedence rule.

**Evidence-floor status:** 9 non-untestable cells were obtained across all harnesses
vs the goal's floor of 5 non-untestable cells — floor cleared (9 ≥ 5): Claude Code
contributes 3 (`name` honored, `description` honored, `tools` partial); the Copilot
re-probe contributes 6 confound-capped `partial` cells (native `name`, native
`description`, native schema-acceptance, raw-tree `name`, raw-tree `description`,
and `tools` — native tree only).
Composition caveat: 6 of the 9 are confound-capped partials from Copilot, the one
harness with no file-read denial mechanism (so its cells are ceilinged at `partial`
independent of nonce fidelity); only the 3 Claude Code cells carry denial-controlled
evidence (an active `Read,Grep,Glob,Bash` deny list during the probe). Cursor still
contributes zero — its cells are gated on model availability, not auth, so the
Copilot re-authorization does not touch them.

## Sources

code.claude.com/docs/en/{sub-agents,model-config,settings,skills} ·
cursor.com/docs/{subagents,rules,skills} ·
code.visualstudio.com/docs/{agent-customization/custom-agents,agents/run/subagents,copilot/copilot-customization,copilot/customization/prompt-files} ·
developers.openai.com/codex/{config-reference,guides/agents-md} (redirects to
learn.chatgpt.com) · full citations in `_memory/research/multi-harness-upgrade.md` ·
2026-08-20 context/invocation addendum:
`_memory/research/token-efficient-skills.md`.

## Addendum 2026-10-08 — native memory, transcripts, hooks

Ingested from `_memory/research/agent-memory-store.md` § "Verified harness facts (2026-10-08)"
and § "Load-bearing conclusions" item 1 (Cursor persistent agent stores). Marks follow
**that report's** legend, which differs from this file's top legend: ✅ = verified against
live official docs by the kit maintainers (✅ observed = local inspection); 🔎 = primary
source cited by the report, not re-verified; 💬 = community/secondary; ⚠️ = report flagged
it as secondhand or unconfirmed.

| Fact | Status | Source |
|---|---|---|
| Claude Code reads `AGENTS.md` only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists in cwd or above (v2.1.277+); kit installs' `CLAUDE.md` pointer suppresses it — listed for discoverability | ✅ | code.claude.com/docs/en/memory § AGENTS.md |
| Claude Code auto memory: `~/.claude/projects/<project>/memory/MEMORY.md`; first 200 lines / 25KB load each session; machine-local; excluded from `cleanupPeriodDays` transcript sweep; `autoMemoryDirectory` relocates it | ✅ | code.claude.com/docs/en/memory |
| Claude Code subagent frontmatter `memory: user\|project\|local` → `~/.claude/agent-memory/<name>/`, `.claude/agent-memory/<name>/`, `.claude/agent-memory-local/<name>/`; kit agents must **not** set it | ✅ | code.claude.com/docs/en/sub-agents |
| Claude Code subagent `omitClaudeMd: true` (v2.1.271+) skips user/project/local CLAUDE.md; not adopted — target projects' CLAUDE.md carries rules workers need | ✅ | code.claude.com/docs/en/sub-agents |
| Claude Code subagent `mcpServers` frontmatter (named or inline) | ✅ | code.claude.com/docs/en/sub-agents |
| Cursor hooks receive `transcript_path` (null when transcripts are disabled) | ✅ | cursor.com/docs/agent/hooks |
| Cursor cloud agents run project `.cursor/hooks.json` hooks for `stop`, `afterAgentResponse`, `subagentStop`, `preCompact`; not `sessionStart`, `sessionEnd`, MCP-execution hooks, or user-level `~/.cursor/hooks.json` | ✅ | cursor.com/docs/agent/hooks § Cloud agent support — superseded by the 2026-10-27 addendum (Cursor hook behavior) |
| Cursor transcripts: `~/.cursor/projects/<slug>/agent-transcripts/` JSONL (format undocumented) | ✅ observed / 💬 format | local inspection; community parsers |
| Cursor persistent agent stores: undocumented; mount locally on tmpfs (`/run/user/<uid>/cursor_agent_stores/…`); never a kit target | ✅ observed | _memory/research/agent-memory-store.md § Load-bearing conclusions item 1 |
| Copilot Memory: preview since 2026-01-15, repo-scoped, 28-day unused expiry, no export API; VS Code memory tool local `/memories/` (preview) | 🔎 | docs.github.com, code.visualstudio.com (per report) |
| Codex memories: `[features] memories = true`, `~/.codex/memories/`, per-user; hooks include `SessionEnd`, `Stop`, `PreCompact` | ⚠️ | developers.openai.com (secondhand per report) |

## Addendum 2026-10-27 — Cursor hook behavior

Ingested from the gate-hardening research (public forum threads and docs pages are cited per fact), accessed 2026-10-27.
With `flags.kit_guard` (2.2.0) the kit installs edit-blocking hooks for Claude Code (`.claude/settings.json`) and Cursor (`.cursor/hooks.json`).
The facts below inform those hooks, optional user hooks and any future hook goal.
Marks follow **this addendum's** legend, which differs from the top legend:

- **staff-confirmed**: a Cursor staff forum reply.
- **documented**: cursor.com docs, or the vendor docs the fact names.
- **community-reported**: forum or issue reports.
- **unconfirmed**: a single field observation.

1. A `preToolUse` or `beforeShellExecution` deny delivers only `user_message` to the agent, not `agent_message`, although the docs still say `agent_message` is fed back to the agent.
   **staff-confirmed**: Cursor forum thread 174283 (staff reply 2026-10-12; desktop 3.23.23).
   Cloud is not verified.
2. Hooks do not run during a cloud agent's read-only early turns; they start once the agent has a writable environment.
   **documented**: cursor.com/docs/agent/hooks.
   Cloud agents only.
3. Cursor loads Claude Code hooks (third-party configs are on by default), with `loop_limit` `null` for them; Cursor's own default is 5.
   **documented**: cursor.com/docs/agent/hooks.
4. For permission hooks (`preToolUse` among them), invalid JSON blocks the action, and crashes, timeouts and non-zero exits other than 2 fail open unless `failClosed: true`.
   **documented**: cursor.com/docs/agent/hooks.
   Whether `failClosed` blocks a crashed `stop` or `subagentStop` hook is **unconfirmed**: the docs define `failClosed` as blocking the action, and Cursor staff in thread 161869 call the IDE stop invocation fire-and-forget.
5. A Task launch without a `model` runs on the parent's model, and an unrecognized frontmatter model silently falls back to the parent's.
   **community-reported**, staff-acknowledged: Cursor forum threads 160840 and 156736.
6. `subagentStop` `summary`, `modified_files` and `agent_transcript_path` are often empty or null.
   **community-reported**: Cursor forum thread 166681.
7. `loop_count` resetting on each user prompt, hooks firing in a named environment with several workspace roots, and a resumed Task skipping `subagentStart`.
   **unconfirmed**: no public thread or docs page confirms any of the three.
8. Copilot reads repository `.claude/settings.json` hooks and runs hooks from every source together, so a hook there can run in Claude Code, Cursor and Copilot.
   **documented**: code.visualstudio.com/docs/copilot/customization/hooks.
9. Interaction with `kit_guard` (2.2.0).
   The entry "Kit-file guard (`flags.kit_guard`) — verified 2026-10-27" above states the per-harness hook design; this fact adds what facts 3, 4 and 8 imply for it and does not restate that entry.
   - **Cursor, double run.** On an install with both Claude Code and Cursor, Cursor also loads the Claude-format hook from `.claude/settings.json` (fact 3), so the guard can run twice per edit.
     The double run is a **documented** consequence, not yet observed: Cursor runs all matching hooks from every source (cursor.com/docs/agent/hooks) and loads the Claude Code hooks (fact 3).
   - **Cursor, reply format.** The guard detects a Cursor caller and answers in Cursor's JSON format (`templates/tools/kit-guard.sh`; the Kit-file guard entry above), so fact 4's invalid-JSON rule does not apply to it.
     That is the documented design.
     How reliable the Cursor-caller detection is stays **unconfirmed**.
   - **Copilot.** On an install with both Claude Code and Copilot, Copilot may also run the guard's Claude hook from `.claude/settings.json` (fact 8) when its agent hooks are enabled, although the Kit-file guard entry says agent-kit doesn't use Copilot hooks.
     Two things are **unconfirmed**: whether `$CLAUDE_PROJECT_DIR` is set under Copilot, and how the guard's `claude` mode handles Copilot's input.
     For PascalCase events, Copilot sends snake_case fields and reports Claude tool names (docs.github.com/en/copilot/reference/hooks-configuration, "VS Code compatible format" and "Claude-format matchers").
   - **Copilot fails closed.** Copilot `preToolUse` command hooks deny the tool call on a crash or non-zero exit (**documented**: docs.github.com/en/copilot/reference/hooks-reference).
     So if `$CLAUDE_PROJECT_DIR` is unset under Copilot, the guard's Claude hook could deny every matched edit.
     This consequence is **unconfirmed**; it is stated as a risk to check.
     Command hook timeouts are fail-open: the action proceeds through the normal permission flow, not an outright allow (**documented**: docs.github.com/en/copilot/reference/hooks-reference).
   - Fact 8 holds for Copilot CLI and VS Code.
     Copilot cloud agent loads only `.github/hooks/*.json` (**documented**: docs.github.com/en/copilot/reference/hooks-reference).
10. Cursor cloud agents run `preToolUse`, `beforeShellExecution`, `subagentStop`, `stop` and other project hooks once the environment is writable; `sessionStart` is deferred.
    **documented**: cursor.com/docs/agent/hooks, § Cloud agent support.
    This restates the current list that the 2026-10-08 cloud-agent row now points to.

Facts 1, 3, 4 and 8–10 bear on the `kit_guard` hooks directly.
Fact 2 limits every Cursor cloud-agent hook until the environment is writable.
Facts 5–7 concern model, subagent and loop hooks the kit does not install.

Re-check these facts by 2027-01-27: Cursor's hook behavior changed several times in 2026, so re-test per Cursor version.
