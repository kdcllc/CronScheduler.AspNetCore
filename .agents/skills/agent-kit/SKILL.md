---
name: agent-kit
description: "Install the orchestrator/worker/evaluator multi-agent system into the current project, compiled for its AI coding harness(es) — Claude Code, Cursor, GitHub Copilot (VS Code), and/or OpenAI Codex. Generates the seven subagents (evaluator, qa-evaluator, implementer, test-writer, evidence-collector, terminal, diagnostician) with tiered model pins — evidence-collector gathers optional-gate QA evidence — terminal is fast-tier (light when an install omits `fast`): it runs any Bash or PowerShell command and returns only the result the caller asked for — plus the orchestrator skills (feature, research, memory-capture), the criteria skills, an optional autonomous feature loop, and a project-specific ORCHESTRATION.md. On empty or near-empty (greenfield) directories it first asks whether to scaffold a project tree and creates nothing until the user confirms. After inspect, suggests skills.sh skills from inspection signals. Run once per project; re-run to upgrade or re-target."
license: MIT
metadata:
  version: "2.2.0"
---

# Setup (Orchestration Kit Compiler)

You are installing a multi-agent orchestration system (orchestrator coordinates,
worker subagents execute with fresh context, skeptical evaluators verify) into the
**current project**. The kit keeps ONE canonical template source in Claude Code format
(`templates/`). `bin/emit.sh` (Windows outside Git Bash: `bin/emit.cmd`) compiles it per harness; `emitters/`
are caveats only. Consult `reference/harness-matrix.md` for verified capabilities and friction points —
when live harness docs contradict it, trust the docs and update the matrix.

Skim `templates/ORCHESTRATION.md` first so you understand what you are instantiating.

## Step 1 — Detect target harness(es)

Evidence: existing `.claude/`, `.cursor/`, `.github/copilot-instructions.md` or
`.github/agents/`, `.codex/` or `AGENTS.md`; plus the session you are running in.
Present what you detected and ask which harnesses to target — **multiple is normal**
(the canonical `.claude/` tree already serves VS Code partially; see the matrix).
Cursor's emitter is self-contained: targeting Cursor emits its own full `.cursor/`
tree. If any destination file exists, list collisions and ask before overwriting —
unless a kit manifest exists (see Upgrading below).

## Step 2a — Greenfield gate

**Run order (hard):** run this step after Step 1 and **before** Step 2, despite the
`2a` label. Evaluate it **once per `/agent-kit` session** — evaluate the sparse heuristic
and ask at most once per invocation. After a confirmed generic tree (paths that sit on
the allowlist below), do not re-enter Step 2a; the only hand-back target is Step 2,
never Step 2a.

### Sparse heuristic

The workspace is sparse **only if every present file** is on this allowlist:

- `.git/` (any contents)
- `.gitignore`
- `LICENSE`
- `README*` (any suffix)
- `.editorconfig`
- `.gitattributes`
- `.DS_Store`
- `Thumbs.db`
- empty directories

**Any other file** means **not sparse** — including `skills/agent-kit/SKILL.md`, anything
under `tests/`, `docs/`, `scripts/`, or `src/`, a language manifest,
`orchestration-kit.manifest.json`, `notes.md`, or `main.py`.

Worked negative example: a repo containing `skills/agent-kit/SKILL.md`, or a non-empty
`tests/` directory, is **not** sparse and must skip Step 2a.

**Hard rule — not sparse:** skip **entirely** `## Step 2a — Greenfield gate` (no
scaffold offer) and continue with Step 2 inspect; Step 2b still runs.

**Hard rule — sparse:** **always ask** whether to scaffold a new project. Never
silently scaffold; never skip the question.

### Decline path

If the user declines the scaffold: create no scaffold files, set `flags.greenfield` in the answers file (Step 4) to `false`, and continue with the
normal inspect → interview → emit path.

### Accept path — guide, then confirm

1. Interview the stack with three choices only: **TypeScript/Node**, **Python**, or
   **Other**.
2. Present the matching frozen tree below as a list of paths — do not create anything
   yet. **Guide-then-confirm (hard):**
   create nothing until the user explicitly confirms that tree.
   No Write and no `mkdir` of scaffold paths before that confirmation. If they reject
   the presented tree, revise it and wait again — still create nothing.
3. After confirmation, create **exactly** the confirmed paths.
4. **Never overwrite:** if a confirmed path already exists, skip it and report the
   skip.

Frozen trees — create these after confirm and nothing else (no sample production
module, no failing test file, no CI):

| Stack | Paths to create after confirmation |
|-------|------------------------------------|
| **TypeScript/Node** | `package.json` (minimal: `name` from the project/folder name, `"private": true`), `tsconfig.json` (minimal `compilerOptions` sufficient for `src/`), `.gitignore` (at least `node_modules/` and `dist/`), `README.md` (title), `src/`, `tests/` |
| **Python** | `pyproject.toml` (minimal `[project]` name + version), `.gitignore` (at least `__pycache__/`, `.venv/`, `*.egg-info/`), `README.md` (title), `src/`, `tests/` |
| **Other / generic** | `.gitignore`, `README.md` (title), `src/`, `tests/` — no language manifest |

Skill suggestions run in Step 2b for every project (see below).

### Accept-path hand-back (hard)

After confirmed tree creation, the flow continues at Step 2 — Inspect the repo on the newly
created tree, then Step 2b skill suggestions, then Step 3 interview, then Steps 4–6 emit. This gate never ends the
skill.

### Greenfield token disposition (hard)

The frozen trees include **no** test runner and no failing test file, so nothing about
testing can be inferred from them. Step 3 **must ask** for the targeted and full test
commands, the setup commands, and the test framework name(s), and **must never invent**
`npm test` / `pytest`. Record the four inference-only values in answers `tokens`:

| Token | User supplied a value | User has none |
|-------|----------------------|---------------|
| `TARGETED_TEST_COMMAND` | the user's command | `(not configured)` |
| `FULL_TEST_COMMAND` | the user's command | `(not configured)` |
| `TEST_FRAMEWORKS` | the user's name(s) | `not configured` |
| `SETUP_COMMANDS` | the user's command | TypeScript/Node accept path: `npm install`; Python accept path: `pip install -e .`; Other or decline: `(not configured)` |

Omit `LINT_COMMAND` / `TYPECHECK_COMMAND` from `tokens` when the matching flag is false.

### Greenfield signal (hard)

Set `flags.greenfield` in the answers file (Step 4) to `true` only when the user
accepted and confirmed a tree, otherwise `false`. The emitter writes
`options.greenfield` from it. Do not rely on remembering which branch ran.

## Step 2 — Inspect the repo

Step 2a has already run (sparse workspace) or was skipped entirely (not sparse); either
way, inspect now and never re-enter the gate.

Establish from the code (do not ask what you can read):

- Language(s), runtime, package manager, workspace layout
- Exact commands for **targeted** tests (one file / pattern) and the **full** suite(s)
- Lint / type-check / build commands **that are actually configured** — never invent
- Code lanes/layers and their dependency order
- User-facing surfaces: CLIs, API endpoints, web UI, library entry points
- Existing skills/agents/rules — enumerate installed skill directories under
  `.claude/skills`, `.cursor/skills`, `.agents/skills`, and `.github/skills` (each
  subdirectory name is an installed skill); per-directory `AGENTS.md`/`CLAUDE.md`, canonical docs
- External services the code talks to (these must be mocked in tests)
- Enumerate `git remote -v` and classify each remote per the forge taxonomy in
  `templates/ORCHESTRATION.md` § Forge adapter (Phase 7 delivery)
- **Existing project agents** — enumerate agent definitions under
  `.claude/agents/*.md`, `.cursor/agents/*.md`, `.github/agents/*.agent.md`,
  `.codex/agents/*.toml` and `*.md`, and Codex `[agents.*]` tables in `.codex/config.toml`,
  excluding paths listed in an existing `orchestration-kit.manifest.json`
  `files` map. Report to the user (a) **name collisions** with the seven kit
  agents (`evaluator`, `qa-evaluator`, `evidence-collector`, `implementer`,
  `test-writer`, `terminal`, `diagnostician`) — Step 5 blocks colliding agent
  **files** (exit 4) until the user decides; a colliding Codex
  `[agents.<name>]` table in `.codex/config.toml` is not blocked (the kit
  appends its own tables), so call it out for manual resolution — and (b)
  **role overlaps** (e.g. a project `backend-engineer` vs kit `implementer`).
- **Path-scoped rules** — detect rule files that load only when a touched file
  matches a glob: Claude Code `.claude/rules/**/*.md` with `paths:` frontmatter,
  Cursor `.cursor/rules/**/*.mdc` with `globs:` (excluding the kit's own
  `orchestration.mdc`), Copilot `.github/instructions/*.instructions.md` with
  `applyTo:`. Fresh-context subagents may not receive these rules, so they are
  not guaranteed to reach `implementer` / `test-writer` / `evaluator` unless
  routed in Step 4.

## Step 2b — Skill suggestions

Runs for **every project** — greenfield accept path, greenfield decline path, and
non-sparse (existing) repos — **once per** interactive `/agent-kit` session, after Step 2
inspect so the signals below are known. Workflow reference:
https://www.skills.sh/vercel-labs/skills/find-skills — the find-skills skill itself is
**not** installed and **not** vendored; its workflow is embedded here.

1. **Derive queries** from Step 2 inspection using the signal table below.
2. **Leaderboard first**: check https://skills.sh/ for a well-known skill covering each
   signal before running the CLI.
3. **Search**: `npx skills find <query>` per derived query (optionally `--owner <owner>`
   to scope).
4. **Verify quality** before recommending: install count and publisher. Offer a skill only if its install count is 1000 or more. Prefer listings whose GitHub owner is
   `vercel-labs` or `anthropics`; also prefer `microsoft` when it meets the floor. Still
   show other publishers that meet the floor. Never list a skill under 1000.
5. **Present**: each candidate with skill name, what it does, install count, source
   (`owner/repo`), install command, and a skills.sh link. Present at most 8 candidates in total and at most 3 per signal, ranked by install count. Ties break toward the
   preferred publishers.
6. **User picks** zero or more. Never auto-install.
7. **Install** project-local with exactly:

`npx skills add <owner>/<repo> --skill <picked-skill> -y`
Never pass -g (project-local only).

**Why `--skill` is required:** `-y` skips confirmation and accepts defaults — without
`--skill` the CLI installs **every** skill in that source, which is auto-install and
out of scope. Optional `-a <agent>` only when the CLI agent id for a Step 1 harness is
known; otherwise omit `-a` (do not guess). Do not vendor installed copies into the
kit's `templates/` tree.

8. **Fail-open**: if `npx` is missing, the command exits non-zero, or the network is
   unavailable, do not abort `/agent-kit`; print the exact `npx skills add …` commands to
   run later, then continue to Step 3.

**No results** for a query: say so and move on; never fabricate a candidate.

| Signal | Evidence (from Step 2 inspect) | Queries for npx skills find |
|--------|-------------------------------|------------------------------|
| **Language / runtime** | e.g. `package.json` + `tsconfig.json`, `pyproject.toml` / `requirements.txt`, `*.csproj`, `go.mod`, `Cargo.toml` | `typescript`, `python`, `dotnet`, `go`, `rust` |
| **Web UI present** | e.g. `react` / `next` / `vue` / `svelte` / `@angular` dependencies, `*.razor`, HTML templates + CSS, `tailwind.config.*` | `web design`, `ui`, the framework name, `accessibility` |
| **Test framework** | e.g. `[tool.pytest]` / `pytest.ini` / `conftest.py`, `jest.config.*` / `vitest.config.*`, `playwright.config.*`, xunit / NUnit package refs | `pytest`, `jest`, `vitest`, `playwright`, `testing` |
| **Backend / web framework** | e.g. `fastapi` / `django` / `flask`, `express` / `fastify` / `next`, `Microsoft.AspNetCore`, Spring | the framework name |
| **Infra / DevOps** | e.g. `Dockerfile`, `docker-compose*`, Kubernetes manifests, `*.tf`, `*.bicep`, `.github/workflows/` | `docker`, `kubernetes`, `terraform`, `bicep`, `github actions` |
| **Docs surfaces** | e.g. `docs/`, `mkdocs.yml`, `docusaurus.config.*` | `documentation` |
| **Databases / ORMs** | e.g. `prisma/`, `sqlalchemy` / `alembic`, `Microsoft.EntityFrameworkCore`, `migrations/` | `prisma`, `sqlalchemy`, `database` |

A signal that is absent produces no query.

The agent may add **1–3 extra queries** beyond the table, each justified by a named
inspection file (worked example: `requirements.txt` lists `langchain` → `langchain`). No
extra query without named evidence.

Worked examples: a repo with a web UI → e.g. offer a web design / UI guidance skill; a
repo with `pytest` configured → e.g. offer a Python / pytest best-practices skill. Do
not promise a specific skill name or install count.

On a freshly scaffolded tree only the language signal is present, so the search reduces
to the stack query (`typescript` / `node` or `python`).

Before presenting, enumerate installed skill directories: `.claude/skills/*/`,
`.cursor/skills/*/`, `.agents/skills/*/`, `.github/skills/*/` (a skill is installed if
a directory with its name exists in any of them). Never re-offer a skill that is already installed. List installed matches to the user as already installed.

## Step 3 — Interview the user

Ask (multiple-choice where possible) only what you could not infer:

1. **Project name** as it should appear in docs (propose one).
2. **Execution layer order** — confirm your inferred chain.
3. **Model tiers** — for each target harness: pick CURRENT **frontier**, **light**,
   and optional **fast** model IDs, plus **alt-family** (fix-cycle rotation) and
   **frontier-alt-family** (post-exhaustion arbiter). Verify **every** ID against a
   live source; record the verification date and source in the
   `models-map-live-check` bootstrap text. Offer "inherit/unpinned" as an option
   (`flags.models_pinned` false). Live sources by harness:
   - **Cursor** — `agent models` (alias `cursor-agent models`); if it prints no
     models, use the IDE's **Settings → Models** / subagent model picker and say so
     in the live-check text.
   - **Claude Code** — the model-configuration docs' alias table plus
     `claude --version` checked against the minimum Claude Code version each pinned
     model needs.
   - **Copilot** — the model picker.
   - **Codex** — the model picker / config docs.
   When no different-family frontier model is reachable on a harness, set
   `frontier_alt_family` to the frontier ID and `arbiter_same_family: true`, write
   **same-family arbiter (reduced independence)** into the `frontier-alt-family`
   bootstrap answer, and tell the user the arbiter is same-family. Claude Code is
   always in this case (Anthropic models only). Never set `frontier_alt_family`
   equal to `alt_family` unless both are the frontier ID (same-family arbiter);
   otherwise the emitter warns. When no different-family model at
   light-comparable tier is reachable (Claude Code always), set `alt_family` to a
   different same-family model (for example the frontier ID, or the light model
   at higher effort where the harness pins effort) and label the fix-cycle-2 row
   `same-family rotation (reduced diversity)`; never set `alt_family` equal to
   `light` (emit warns: no rotation). Targeting a second harness such as Copilot
   or Codex is the way to obtain cross-family models for rotation and arbitration.
   Never put `best` or `fable` in a loop chain (emit exits 3).
4. **QA gate surfaces** — which user-facing surfaces qa-evaluator covers; any existing
   evidence-producing skills (API smoke, visual QA)?
5. **Research workflow** — wanted? Record `flags.research`.
6. **Autonomous loop** — wanted? If yes: confirm sandbox strategy (worktree/container),
   max iterations, and that commits stay local (no auto-push) unless they say otherwise.
   When confirming the sandbox strategy, tell the user that a worktree separates the git
   tree but is not isolation — unattended runs that skip permission prompts or disable the
   CLI's own sandbox need a container or VM. Record `flags.loop`. Persist the sandbox answer: worktree ⇒
   `flags.loop_worktree: true` (the emitted `_loop/loop.sh` driver then defaults to
   `LOOP_WORKTREE=1`; an explicit `LOOP_WORKTREE` env value, including `0`, still
   wins); container or none ⇒ `false`. Warn that worktree mode needs a **tracked**
   instance (`_memory/loop/backlog.md` and the harness directory committed) or the
   driver stops with exit 5 at preflight.
7. **Opt-in only, or let the agent invoke `/feature` itself?** Default: auto-invocable.
   Opt-in ⇒ `flags.opt_in: true`: `feature`, `research`, `memory-capture` get
   `disable-model-invocation: true` (run only via `/feature`, `/research`,
   `/memory-capture`); the seven kit agents' descriptions are scoped to kit workflows;
   the ORCHESTRATION.md skills note and the Cursor rule switch to opt-in wording. Partial
   on Codex (no skills tree; existing `.codex/config.toml` agent tables not rewritten). Record `flags.opt_in`.
8. **Guard kit-owned files?** (recommended yes for new installs.) `flags.kit_guard: true`
   emits `_kit/kit-guard.sh` (`check` for CI and the post-spawn orchestration gate),
   Claude Code / Cursor edit-blocking hooks when `.claude/settings.json` / `.cursor/hooks.json`
   are absent (else emit prints a merge snippet), and read-only rule text in ORCHESTRATION.md
   and the agents; Orchestration Progress moves to `_memory/work/goals/[goal]/progress.md`.
   Copilot and Codex get the check and rule text only. Record `flags.kit_guard`.
9. **Log subagent and session stops?** (default no.) `flags.hook_telemetry: true` emits
   `_kit/hook-log.sh`, Claude Code (`Stop`, `SubagentStop`, `StopFailure`) and Cursor
   (`stop`, `subagentStop`) hooks when `.claude/settings.json` / `.cursor/hooks.json` are
   absent (else emit prints a merge snippet), and metadata-only lines in
   `_memory/work/hooks/events.jsonl`. Copilot and Codex get none. Record `flags.hook_telemetry`.
10. **Delivery forge (Phase 7)** — present the detected forge and the chosen remote.
    Confirm or override with any of `github` / `azuredevops` / `gitlab` / `none`
    (plus `forgeHost` for self-hosted). The `ship-pr` skill is always emitted;
    `none` means the draft + hand-over branch.
11. **Ground-truth doc** — the committed reference file for domain decisions.

The live model check happens here — the script never fetches anything. See `emitters/`
for each harness's live-check URL and silent-fallback / cost-tier warnings.

## Step 4 — Write the answers file

Write `orchestration-kit.answers.json` at the repo root (`schema: 1`). Id table:
`reference/bootstrap-ids.md`.

```json
{
  "schema": 1,
  "projectName": "…",
  "harnesses": ["claude-code"],
  "primary": "claude-code",
  "flags": { "research": true, "loop": true, "loop_worktree": false,
             "greenfield": false, "lint": true, "typecheck": false,
             "models_pinned": true, "opt_in": false, "kit_guard": true,
             "hook_telemetry": false },
  "forge": { "kind": "github", "host": "" },
  "tokens": { "PROJECT_NAME": "…", "STACK_SUMMARY": "…", "EXECUTION_LAYERS": "…" },
  "models": { "claude-code": { "frontier": "opus", "light": "sonnet", "fast": "haiku",
                               "alt_family": "…", "frontier_alt_family": "…",
                               "loop_chain": "sonnet",
                               "arbiter_same_family": false } },
  "bootstrap": { "<id>": "verbatim replacement text", "other-id": "…" }
}
```

Skills installed in Step 2b are recorded through the existing bootstrap ids:
`bootstrap.domain-skill-rows` gains one table row per installed skill
(`| \`<skill>\` | Supporting | <one-line purpose> (\`owner/repo\`) |`) and
`bootstrap.layer-skill-map` maps the layer that produced the signal to the skill.
Only skills actually installed in this session or already present count as installed; printed fail-open commands do not.
When no project skills exist, those two ids are answered per the existing rules (`""`
deletes the comment).

Each detected path-scoped rule file (Step 2) gets one
`bootstrap.critical-reference-rows` row (file, purpose, "when a task's `writes` match
`<globs>`") and is listed in the `Rule files to cite` column of
`bootstrap.layer-skill-map` for its layer(s). Write the
existing-agents finding to `bootstrap.existing-agents` (which project agent covers
which role and which agent the orchestrator uses for kit work), or `""` when no project
agents exist. In `flags`, `loop_worktree` is optional (absent ⇒ false).
`opt_in` is optional (absent ⇒ false; non-boolean ⇒ exit 3). `kit_guard` is
optional (absent ⇒ false; non-boolean ⇒ exit 3). `hook_telemetry` is optional
(absent ⇒ false; non-boolean ⇒ exit 3).
In any table cell the kit writes, bootstrap rows included, escape a literal `|` as `\|`; never emit a bare `|` inside a cell.

Do **not** put derived keys in `tokens` (marked "derived — do not set" below).
`projectName` fills `PROJECT_NAME` when that token is absent. Omit `LINT_COMMAND` /
`TYPECHECK_COMMAND` when the matching flag is false. A bootstrap id may be
deliberately left unanswered when the project has nothing to say — the comment is
deleted (`""` counts as answered; a missing key is listed).

`$SETUP` is the directory containing this SKILL.md (e.g. `.claude/skills/agent-kit`). Then loop:

```
bash $SETUP/bin/emit.sh --answers orchestration-kit.answers.json --check-answers
```

Ask the user about each listed id, fill `bootstrap`, and repeat `--check-answers`
until exit 0.

Optional per harness: `"fast"` (fast-tier model ID; defaults to `"light"`) and
`"arbiter_same_family": true` when `frontier_alt_family` equals `frontier` (same-family
rung-5 arbiter — the emitter warns if the IDs match without this flag).

### Placeholder reference

| Token | Meaning |
|-------|---------|
| `{{PROJECT_NAME}}` | Display name of the project |
| `{{STACK_SUMMARY}}` | 2–5 sentence stack note |
| `{{IDE_DIR}}` | derived — do not set. Config dir of the harness **being emitted**, resolved per emitter (`.claude`, `.cursor`, `.github`, `.codex`); single-copy shared artifacts (`_loop/*`) resolve it to the **primary** harness's dir |
| `{{MODEL_FRONTIER}}` / `{{MODEL_LIGHT}}` | derived — do not set. Tier → model ID for the primary harness (from the model map) |
| `{{MODEL_FAST}}` | derived — do not set. Fast-tier model ID for the primary harness; defaults to the light ID |
| `{{CLAUDE_MODEL_*}}`, `{{CURSOR_MODEL_*}}`, `{{COPILOT_MODEL_*}}`, `{{CODEX_MODEL_*}}` | derived — do not set. Per-harness tier IDs (model map only); includes `*_MODEL_FAST` |
| `{{MODEL_ALT_FAMILY}}` | derived — do not set. Different-family model at light-comparable tier, used by fix-cycle rotation (model map) |
| `{{MODEL_FRONTIER_ALT_FAMILY}}` | derived — do not set. Different-family model at frontier tier, used by evaluator arbitration mode after fix-cycle exhaustion (model map) |
| `{{LOOP_MODEL_CHAIN}}` | derived — do not set. Comma-separated loop fallback chain, first = preferred (from the model map's "Loop fallback chain" row); empty ⇒ the breaker still tracks state but never passes a model flag |
| `{{LOOP_WORKTREE_DEFAULT}}` | derived — do not set. `1` when `flags.loop_worktree` is true, else `0`; default for `LOOP_WORKTREE` in `_loop/*` when the env var is unset |
| `{{OPT_IN_AGENT_PREFIX}}` | derived — do not set. When `flags.opt_in` is true, the orchestration-kit agent description prefix (`Orchestration-kit agent — spawn only from the /feature, /research or /align-docs workflow, never for ordinary work. `); empty when false |
| `{{OPT_IN_FEATURE_SENTENCE}}` | derived — do not set. When `flags.opt_in` is true, `Opt-in — runs only when the user types /feature.`; when false, `Invoke for any non-trivial feature.` |
| `{{OPT_IN_RESEARCH_SUFFIX}}` | derived — do not set. When `flags.opt_in` is true, ` Opt-in — runs only when the user types /research.` appended to the research skill description; empty when false |
| `{{OPT_IN_MEMORY_CAPTURE_SUFFIX}}` | derived — do not set. When `flags.opt_in` is true, ` Opt-in — runs only when the user types /memory-capture.` appended to the memory-capture skill description; empty when false |
| `{{EXECUTION_LAYERS}}` | Dependency-ordered layer chain |
| `{{GROUND_TRUTH_DOC}}` | Committed domain ground-truth doc path |
| `{{QA_SURFACES}}` | User-facing surfaces + evidence each produces |
| `{{SETUP_COMMANDS}}` | Dependency install commands |
| `{{TARGETED_TEST_COMMAND}}` / `{{FULL_TEST_COMMAND}}` | Staged test commands |
| `{{TEST_FRAMEWORKS}}` | Test framework(s) in use |
| `{{LINT_COMMAND}}` / `{{TYPECHECK_COMMAND}}` | Only if configured; else omit from `tokens` |
| `{{EVALUATOR_AUTO_FAIL_TRIGGERS}}` / `{{QA_AUTO_FAIL_TRIGGERS}}` | Project-specific instant-fail conditions |

## Step 5 — Emit

Run the emitter **inline** — the output is one line; the terminal-spawn rule does not
apply:

- `bash $SETUP/bin/emit.sh --answers orchestration-kit.answers.json`
- On Windows outside Git Bash: `$SETUP\bin\emit.cmd --answers orchestration-kit.answers.json`
  (path arguments use forward slashes; Git for Windows required — see
  [reference/windows-launcher.md](reference/windows-launcher.md))

Every install also emits the single-copy `_kit/memory.sh`, `_kit/log-spawn.sh` and `_kit/trace-lint.sh`, each with a `.cmd` launcher for Windows.

This kit repo's own dogfood uses `scripts/agent-kit/self-install.sh`. If `orchestration-kit.manifest.json` already exists, run with `--dry-run` first.

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | ok | continue to Step 6 |
| 2 | usage / answers unreadable | fix the path or answers file permissions |
| 3 | answers invalid **or** `--check-answers` found unanswered ids | fix answers |
| 4 | user-modified kit files **or** pre-existing files at kit paths that a previous emit did not write (first installs included; listed on stderr — pre-existing class: `emit: blocked <path> (exists; not written by a previous emit)`) | show the user the listed files, ask, `--force` |
| 5 | verify failed | report the listed verify hits as a kit bug |
| 6 | template syntax | kit bug |

## Step 6 — Report

Read the summary line (`emit: written N · unchanged M · pruned P · seeds-kept S · migrated U · warnings W · manifest orchestration-kit.manifest.json · kit <VERSION>`).
Delete `orchestration-kit.answers.json` (the manifest holds `answers`).
Report written / pruned / warnings and the next step (`/feature`).
The script writes the manifest; schema in `bin/README.md`.
Manifest `options` is flat — `"forge": "<detected>"` plus optional `forgeHost`.
`seedFiles` lists seeds (today `_memory/loop/backlog.md`); they are never overwritten
on upgrade.

## Upgrading / re-running

A script-only `--upgrade` never runs Step 2b. A full interactive `/agent-kit` re-run
does run it (skipping installed skills).

`bash $SETUP/bin/emit.sh --upgrade` (answers come from the manifest; add
`--answers` only when the interview changed). Exit 4 lists user-modified files,
pre-existing kit-path files, and upgrade target conflicts; show the user, then
`--force` if they confirm. A kit path newly added in an upgrade that already
exists on disk with other content is blocked the same way.
`--dry-run` prints planned actions and still exits 4 when any path is blocked.

Prune: kit-owned paths in the previous manifest that are not in the new emit set
are deleted when unchanged, else kept and warned; seeds are never pruned.

Emit warns for a reused or unacknowledged same-family arbiter (fix:
set `arbiter_same_family: true` or pick a different arbiter), when
`models.<h>.alt_family` equals `models.<h>.light` (fix: pick a different
`alt_family` so fix cycle 2 rotates models), and exits 3 for
`best`/`fable` in a loop chain (fix: replace the entry).

To adopt opt-in on an existing install, add `"opt_in": true` under `flags` in an
answers file (e.g. copied from the manifest's embedded `answers`) and run
`emit.sh --answers <file> --upgrade`; files hand-edited to exactly the emitted
opt-in text count as unchanged; any other difference is blocked (exit 4) — review,
then `--force` once. To add the guard, set `"kit_guard": true` the same way;
existing `.claude/settings.json` / `.cursor/hooks.json` are never edited — copy
the snippet from the emit warning; `bash $SETUP/bin/emit.sh --check` (or
`_kit/kit-guard.sh check`) reports edited kit files at any time. To add hook
telemetry, set `"hook_telemetry": true` the same way; existing configs get a merge
snippet from the emit warning.

On every re-run, re-detect the forge from the current remotes. If detection agrees
with the manifest, refresh silently. If it disagrees (remote migrated, e.g.
GitHub → Azure DevOps), surface both values and ask — never silently flip, never
keep a stale value unmentioned.

Paths listed in `seedFiles` are outside the overwrite flow: create a seed if it is
missing, otherwise leave it exactly as it is.

### Upgrading from the private setup kit

For projects that previously used the private `setup` skill: re-add with
`npx skills add kdcllc/skills --skill agent-kit`, delete old `setup` compiler copies
under each harness's `skills/` tree, then re-emit with `--upgrade` as above. Installs
from the private `setup` kit before 0.27.0 have no embedded `answers` — run Steps 1–4
once, then `--answers … --upgrade`.

**Legacy layout migration:** when `_goals/` or `_research/` still exist, emit moves
them into `_memory/loop/` (loop files) and `_memory/work/` (goal and research scratch)
before writing kit files — `git mv` when tracked, plain `mv` otherwise. `--dry-run`
prints planned actions including `migrate <src> -> <dst>` for these moves. Previously
tracked goal/research trees and `breaker-state.json` are untracked afterward
(`git rm --cached`; files stay on disk). Loop markdown stays tracked. Retired kit
`.gitattributes` / `.gitignore` lines (`_goals/*/orchestration-log.md merge=union`,
`_goals/LEARNINGS.md merge=union`, `_goals/ESCALATIONS.md merge=union`,
`_goals/breaker-state.json`) are removed by exact line match; user lines are kept.
If a target path already exists, emit exits 4 before moving anything unless
`--force` (conflicting sources stay put with a warning; nothing is overwritten).
A second upgrade with nothing left to move reports `migrated 0`. After a move, stderr
prints a hint to run `_kit/memory.sh backfill --plan`. See `_memory/README.md` §
Upgrade migration.

**Warnings after layout migration:**

- `LOOP_WORKTREE=1` users must commit the staged `_memory/loop/` move so worktrees
  see tracked loop files.
- Committing the untracking of goal/research folders removes those paths from
  teammates' working trees on pull — teammates should upgrade locally first, or the
  team should back-fill and coordinate before committing the layout change.

Manifests from older kits may still list `_goals/backlog.md` as a seed; that path is
treated as a seed, not foreign.
