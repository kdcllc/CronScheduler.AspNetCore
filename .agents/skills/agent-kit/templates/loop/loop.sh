#!/usr/bin/env bash
# Autonomous feature loop for {{PROJECT_NAME}} — drives one `auto-loop` iteration per
# fresh-context CLI run. State lives in _memory/loop/backlog.md + git, never in memory.
#
# Usage:   _loop/loop.sh [max-iterations]        (default 10)
#          _loop/loop.sh --lint [backlog-path]  (readiness check; exit 0/1/5)
# CLI:     override with LOOP_CLI, e.g. LOOP_CLI="codex exec --sandbox danger-full-access" or LOOP_CLI="claude -p"
# LINT:    `--lint [backlog-path]` checks backlog errors and warnings with no side
#          effects; default path is $PWD/_memory/loop/backlog.md; exit 0 when there
#          are no errors, 1 when there are errors, 5 when the backlog is missing or
#          unreadable.
# TAMPER:  LOOP_TAMPER_CHECK = warn (default) | fail | off — at reap, scan the slot's own
#          commits (head_before..HEAD) for test gaming: deleted:<path> (test file removed or
#          renamed to a non-test path), skip-marker:<path> (added skip/only/disabled markers),
#          assertions-removed:<path>:<n> (net removed assertion lines in a modified test file).
#          warn prints `!!! tamper (warn) slot …` and leaves integration unchanged; fail
#          quarantines (worktree only — requires LOOP_WORKTREE=1; use warn on the main tree)
#          and skips the backlog transition. off disables the scan. LOOP_TEST_PATTERNS —
#          optional comma-separated bash `case` patterns against the full repo-relative path;
#          when set, replaces all default rules below. Defaults: any segment is
#          test/tests/__tests__/spec or the basename matches test_*, *_test.*, *.test.*,
#          *.spec.*, *Test.*, or *Tests.* — excluding paths with a fixtures/ segment and
#          basenames *.golden / *.snap (not tests unless LOOP_TEST_PATTERNS matches them).
# TIMEOUT: LOOP_ITER_TIMEOUT — positive integer seconds; off when unset. Wraps each CLI
#          dispatch with timeout/gtimeout -s INT -k 60 (60 s SIGKILL grace after SIGINT).
#          Status 124/137 from GNU timeout always counts as a timeout; other nonzero
#          statuses count when elapsed ≥ N and rate-limit was not detected for that reap.
# BUDGETS: LOOP_RUN_BUDGET_TOKENS / LOOP_STORY_BUDGET_TOKENS — positive integer token
#          ceilings (claude/claude-stream/cursor sum input+output+cache_*; codex input+output). Off when
#          unset. LOOP_RUN_BUDGET_USD / LOOP_STORY_BUDGET_USD — positive decimal USD
#          ceilings from parsed CLI cost; off when unset. LOOP_ITER_BUDGET_USD — per-
#          iteration Claude Code --max-budget-usd (claude/claude-stream formats). All budget knobs
#          fail open when the CLI reports no usage/cost. Run budget stops claiming new
#          stories (exit 1 when eligible work remains); a drained backlog still exits 0.
# LEDGER:  LOOP_LEDGER default on -> $PWD/_memory/loop/ledger.jsonl (absolute, one JSON line
#          per reaped/killed slot); set LOOP_LEDGER=off to disable. After >=1 reap/kill, a run
#          summary prints to stderr on exit (not in --lint mode). Token totals: claude/claude-stream/cursor =
#          input+output+cache_read+cache_write; codex = input+output (cached input recorded, not summed).
# DOSSIER: LOOP_DOSSIER default on -> $PWD/_memory/loop/attempts/<story-id>.md (absolute, resolved
#          before any cd); set LOOP_DOSSIER=off to disable record/inject/clear. Slots may write
#          <outbox>/attempt.md with ## Verdict, ## Unmet criteria, ## Failing tests, ## Notes.
#          Keeps the 2 newest entries (~2048 bytes each); deleted when a reap sets passes: true.
# USAGE:   LOOP_USAGE_FORMAT = auto (default) | claude | claude-stream | codex | cursor | none —
#          auto resolves from the basename of the first word of LOOP_CLI once at
#          startup; splices machine-readable flags into LOOP_CLI before dispatch.
#          claude-stream is opt-in (stream-json, typed api_retry rate-limit detection;
#          never chosen by auto).
#          Silent-none: when LOOP_USAGE_FORMAT is unset and auto resolves to none,
#          the driver prints no usage banner/line and does not alter argv (path-
#          invoked test stubs stay byte-identical). Explicit LOOP_USAGE_FORMAT=none
#          prints the banner and `usage: unavailable (format none)` per slot.
#          LOOP_USAGE_LOG — when set, each usage line is appended prefixed with
#          `<ISO ts> slot=<s> story=<id> `.
# SLOTS:   override with LOOP_SLOTS (default 2, clamped [1,3]) — N>1 is honored only
#          when LOOP_WORKTREE=1 (worktree isolation makes concurrent slots sound);
#          otherwise effective concurrency is held at 1.
# WORKTREE: default from install `flags.loop_worktree` (this install: {{LOOP_WORKTREE_DEFAULT}}; 0 unless
#          worktree was chosen at install); override with LOOP_WORKTREE (including 0) — explicit wins.
#          1 runs each iteration in its own git worktree under .loop-worktrees/.
#
# SAFETY: run inside a sandbox (worktree/container) with minimal credentials.
# A worktree only separates the git tree — it gives no filesystem, network, or
# credential isolation — so any CLI flag that skips permission prompts or disables
# the CLI's own sandbox needs a container or VM.
# This script never pushes and never bypasses permission prompts by itself.
#
# Breaker: sources breaker.sh (functions: breaker_load, breaker_should_skip,
# breaker_record, breaker_probe, breaker_current_model); state file:
# _memory/loop/breaker-state.json.
#
# Exit codes (driver-aggregated across slots, precedence 4>3>2>1>0 -- the most
# severe cause is always the one reported):
# 0 = backlog complete -- the driver's own backlog re-scan found no eligible
# story and no branch was quarantined this run. Under driver-owned dispatch a
# slot-emitted sentinel is an ITERATION-mismatch (contract violation), never a
# completion signal; the sentinel decides completion only in MANUAL
# (non-dispatched) auto-loop runs.
# 1 = stopped without completing the backlog -- max iterations reached with
# eligible stories remaining, or no eligible story remains but quarantined
# branches were retained this run (inspect them before trusting the backlog).
# 2 = circuit breaker -- every slot retired on no-progress (a slot retires,
# and is no longer refilled, after 3 consecutive no-commit reaps).
# 3 = circuit breaker -- every slot retired and at least one retirement was
# for 5 consecutive identical failure signatures (per-slot lineage).
# 4 = protected-path modification detected (iteration reverted; the run stops
# immediately and every other running slot is killed).
# 126/127 (shell-propagated edge cases, not loop-owned codes): command-not-found
# propagates as exit 127 and found-but-not-executable as exit 126 (bash) --
# standard shell convention, distinct from the aggregated codes above.
# Exit 5 = setup or integration failure: the LOOP_WORKTREE=1 tracked-instance
# preflight failing after `git worktree add`, PROMPT.md missing a %%...%%
# substitution point, a missing/unreadable _memory/loop/backlog.md, or the
# rebase-then-ff integration step hitting a non-fast-forward -- all loud,
# driver-level stops that never silently fall back to the main tree (the
# preflight path removes its worktree; the non-ff path retains worktree and
# branch for inspection).
set -euo pipefail

# _loop_usd_to_micro <decimal> -> micro-USD integer on stdout; return 1 on bad input.
_loop_usd_to_micro() {
  local d="${1:-}"
  if [[ ! "$d" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    return 1
  fi
  local whole frac
  if [[ "$d" == *.* ]]; then
    whole="${d%%.*}"
    frac="${d#*.}"
  else
    whole="$d"
    frac=""
  fi
  [[ -z "$whole" ]] && whole=0
  while (( ${#frac} < 6 )); do
    frac="${frac}0"
  done
  if (( ${#frac} > 6 )); then
    frac="${frac:0:6}"
  fi
  printf '%d' $(( 10#${whole} * 1000000 + 10#${frac} ))
}

# _loop_setup_fail <message> — driver-level loud setup failure (exit 5).
_loop_setup_fail() {
  echo "!!! $1" >&2
  exit 5
}

_loop_lint_mode=0
_lint_backlog_path=""
if [[ "${1:-}" == "--lint" ]]; then
  _loop_lint_mode=1
  _lint_backlog_path="${2:-$PWD/_memory/loop/backlog.md}"
fi

MAX_ITER="${1:-10}"   # total dispatches ACROSS all active slots (fill/poll/reap/
                       # integrate/refill below) -- same 010/011 semantics: one
                       # dispatch consumes one unit of this budget no matter which
                       # slot row it lands in.
LOOP_CLI="${LOOP_CLI:-claude -p}"
LOOP_MODEL_FLAG="${LOOP_MODEL_FLAG:-}"

if (( _loop_lint_mode == 0 )); then
# --- LOOP_USAGE_FORMAT: resolve once at startup, optional flag splice ---------
usage_explicit=0
if [[ -n "${LOOP_USAGE_FORMAT+x}" ]]; then
  usage_explicit=1
  usage_format="${LOOP_USAGE_FORMAT}"
else
  usage_format="auto"
fi

_loop_resolve_usage_format() {
  local fmt="$1"
  if [[ "$fmt" == "auto" ]]; then
    local cli_base
    cli_base="$(basename "${LOOP_CLI%% *}")"
    case "$cli_base" in
      claude) fmt="claude" ;;
      codex) fmt="codex" ;;
      agent|cursor-agent) fmt="cursor" ;;
      *) fmt="none" ;;
    esac
  fi
  printf '%s' "$fmt"
}

usage_format_resolved="$(_loop_resolve_usage_format "$usage_format")"

if [[ "$usage_format_resolved" != "none" ]] && ! command -v jq >/dev/null 2>&1; then
  echo "usage: unavailable (jq not on PATH)"
  usage_format_resolved="none"
  usage_explicit=1
fi

if [[ "$usage_format_resolved" != "none" || "$usage_explicit" -eq 1 ]]; then
  echo "usage format: $usage_format_resolved"
fi

case "$usage_format_resolved" in
  claude|cursor) LOOP_CLI="$LOOP_CLI --output-format json" ;;
  claude-stream) LOOP_CLI="$LOOP_CLI --output-format stream-json --verbose" ;;
  codex) LOOP_CLI="$LOOP_CLI --json" ;;
esac

if [[ -n "${LOOP_ITER_BUDGET_USD:-}" ]]; then
  if [[ "$usage_format_resolved" == "claude" || "$usage_format_resolved" == "claude-stream" ]]; then
    LOOP_CLI="$LOOP_CLI --max-budget-usd ${LOOP_ITER_BUDGET_USD}"
  else
    echo "note: LOOP_ITER_BUDGET_USD ignored for usage format $usage_format_resolved (Claude Code only)" >&2
  fi
fi
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
_loop_ledger_enabled=1
_loop_ledger_path=""
if [[ "${LOOP_LEDGER:-}" == "off" ]]; then
  _loop_ledger_enabled=0
elif [[ -z "${LOOP_LEDGER:-}" ]]; then
  _loop_ledger_path="$PWD/_memory/loop/ledger.jsonl"
else
  _loop_ledger_path="${LOOP_LEDGER}"
  if [[ "$_loop_ledger_path" != /* ]]; then
    _loop_ledger_path="$PWD/$_loop_ledger_path"
  fi
fi

_loop_iter_timeout=0
_loop_run_budget_tokens=0
_loop_run_budget_usd_micro=0
_loop_run_budget_usd_set=0
_loop_story_budget_tokens=0
_loop_story_budget_usd_micro=0
_loop_story_budget_usd_set=0
_loop_timeout_bin=""
_loop_run_budget_stopped=0
_loop_any_budget_knob=0
_loop_note_no_usage_printed=0

if (( _loop_lint_mode == 0 )); then
  if [[ -n "${LOOP_ITER_TIMEOUT:-}" ]]; then
    if [[ ! "${LOOP_ITER_TIMEOUT}" =~ ^[1-9][0-9]*$ ]] || (( LOOP_ITER_TIMEOUT < 1 )); then
      _loop_setup_fail "invalid LOOP_ITER_TIMEOUT='${LOOP_ITER_TIMEOUT}' — expected a positive integer"
    fi
    _loop_iter_timeout=$LOOP_ITER_TIMEOUT
    if command -v timeout >/dev/null 2>&1; then
      _loop_timeout_bin="$(command -v timeout)"
    elif command -v gtimeout >/dev/null 2>&1; then
      _loop_timeout_bin="$(command -v gtimeout)"
    else
      _loop_setup_fail "LOOP_ITER_TIMEOUT requires timeout (coreutils) or gtimeout on PATH"
    fi
    if ! "$_loop_timeout_bin" -s INT -k 1 1 true >/dev/null 2>&1; then
      _loop_setup_fail "timeout binary $_loop_timeout_bin does not support -s/-k (need GNU coreutils timeout, gtimeout, or BusyBox >= 1.35)"
    fi
  fi
  if [[ -n "${LOOP_RUN_BUDGET_TOKENS:-}" ]]; then
    _loop_any_budget_knob=1
    if [[ ! "${LOOP_RUN_BUDGET_TOKENS}" =~ ^[1-9][0-9]*$ ]] || (( LOOP_RUN_BUDGET_TOKENS < 1 )); then
      _loop_setup_fail "invalid LOOP_RUN_BUDGET_TOKENS='${LOOP_RUN_BUDGET_TOKENS}' — expected a positive integer"
    fi
    _loop_run_budget_tokens=$LOOP_RUN_BUDGET_TOKENS
  fi
  if [[ -n "${LOOP_STORY_BUDGET_TOKENS:-}" ]]; then
    _loop_any_budget_knob=1
    if [[ ! "${LOOP_STORY_BUDGET_TOKENS}" =~ ^[1-9][0-9]*$ ]] || (( LOOP_STORY_BUDGET_TOKENS < 1 )); then
      _loop_setup_fail "invalid LOOP_STORY_BUDGET_TOKENS='${LOOP_STORY_BUDGET_TOKENS}' — expected a positive integer"
    fi
    _loop_story_budget_tokens=$LOOP_STORY_BUDGET_TOKENS
  fi
  if [[ -n "${LOOP_RUN_BUDGET_USD:-}" ]]; then
    _loop_any_budget_knob=1
    if ! _loop_run_budget_usd_micro="$(_loop_usd_to_micro "$LOOP_RUN_BUDGET_USD" 2>/dev/null)" \
       || (( _loop_run_budget_usd_micro == 0 )); then
      _loop_setup_fail "invalid LOOP_RUN_BUDGET_USD='${LOOP_RUN_BUDGET_USD}' — expected a positive decimal USD amount"
    fi
    _loop_run_budget_usd_set=1
    case "$usage_format_resolved" in
      cursor|codex|none)
        echo "note: LOOP_RUN_BUDGET_USD has no effect for usage format $usage_format_resolved (no cost reported)" >&2
        ;;
    esac
  fi
  if [[ -n "${LOOP_STORY_BUDGET_USD:-}" ]]; then
    _loop_any_budget_knob=1
    if ! _loop_story_budget_usd_micro="$(_loop_usd_to_micro "$LOOP_STORY_BUDGET_USD" 2>/dev/null)" \
       || (( _loop_story_budget_usd_micro == 0 )); then
      _loop_setup_fail "invalid LOOP_STORY_BUDGET_USD='${LOOP_STORY_BUDGET_USD}' — expected a positive decimal USD amount"
    fi
    _loop_story_budget_usd_set=1
    case "$usage_format_resolved" in
      cursor|codex|none)
        echo "note: LOOP_STORY_BUDGET_USD has no effect for usage format $usage_format_resolved (no cost reported)" >&2
        ;;
    esac
  fi
  if [[ -n "${LOOP_ITER_BUDGET_USD:-}" ]]; then
    _loop_any_budget_knob=1
    if ! micro_chk="$(_loop_usd_to_micro "$LOOP_ITER_BUDGET_USD" 2>/dev/null)" \
       || (( micro_chk == 0 )); then
      _loop_setup_fail "invalid LOOP_ITER_BUDGET_USD='${LOOP_ITER_BUDGET_USD}' — expected a positive decimal USD amount"
    fi
  fi
  _loop_tamper_check=warn
  if [[ -n "${LOOP_TAMPER_CHECK:-}" ]]; then
    case "$LOOP_TAMPER_CHECK" in
      warn|fail|off) _loop_tamper_check="$LOOP_TAMPER_CHECK" ;;
      *) _loop_setup_fail "invalid LOOP_TAMPER_CHECK='${LOOP_TAMPER_CHECK}' — expected warn|fail|off" ;;
    esac
  fi
  if [[ -n "${LOOP_DOSSIER:-}" ]] && [[ "${LOOP_DOSSIER}" != "on" ]] && [[ "${LOOP_DOSSIER}" != "off" ]]; then
    _loop_setup_fail "invalid LOOP_DOSSIER='${LOOP_DOSSIER}' — expected on|off"
  fi
fi

_loop_tamper_check="${_loop_tamper_check:-warn}"
_loop_dossier_enabled=1
if [[ "${LOOP_DOSSIER:-}" == "off" ]]; then
  _loop_dossier_enabled=0
fi

# Absolute paths, resolved BEFORE any `cd` happens anywhere below (the child
# subshell dispatched per-slot cd's into that slot's worktree at
# LOOP_WORKTREE=1) -- both were relative and depended on the invocation cwd.
PROMPT_FILE="$(cd "$(dirname "$0")" && pwd)/PROMPT.md"
SENTINEL='<promise>COMPLETE</promise>'
STATE_FILE="$PWD/_memory/loop/breaker-state.json"
BACKLOG_FILE="$PWD/_memory/loop/backlog.md"   # driver-owned selection reads/writes
                                        # this file directly (never via $tree
                                        # -- §6.3: "slots never write it").
_loop_dossier_store="$PWD/_memory/loop/attempts"

if (( _loop_lint_mode == 0 )); then
  # shellcheck source=./breaker.sh
  source "$(dirname "$0")/breaker.sh"
  breaker_load "$STATE_FILE" "{{LOOP_MODEL_CHAIN}}"
fi

# LOOP_WORKTREE: default from install `flags.loop_worktree` (0 unless worktree chosen
# at install); explicit LOOP_WORKTREE (including 0) wins. 0 runs every dispatched slot
# in the main tree — today's behavior, unchanged. 1 activates the worktree lifecycle
# below (loud tracked-instance preflight, per-slot HEAD/CB0-2, pinned ff-only
# integration, quarantine-lite on abnormal exit) AND is the precondition the guard
# below requires before honoring LOOP_SLOTS>1.
LOOP_WORKTREE_DEFAULT='{{LOOP_WORKTREE_DEFAULT}}'
WORKTREE="${LOOP_WORKTREE:-$LOOP_WORKTREE_DEFAULT}"

if (( _loop_lint_mode == 0 )) && [[ "$_loop_tamper_check" == "fail" ]] && (( WORKTREE != 1 )); then
  _loop_setup_fail "LOOP_TAMPER_CHECK=fail requires LOOP_WORKTREE=1 (quarantine is the only non-destructive response on a shared tree); use warn on the main tree"
fi

if (( _loop_lint_mode == 0 )); then
# --- LOOP_SLOTS: read, clamp, guard --------------------------------------
# LOOP_SLOTS_EXPLICIT captures the RAW value (pre-clamp) so the guard below
# can tell "explicitly requested >1" apart from the unset default -- the
# stderr warning fires only in the former case (no warning fatigue on every
# default run).
LOOP_SLOTS_EXPLICIT="${LOOP_SLOTS:-}"
SLOTS="${LOOP_SLOTS:-2}"
if (( SLOTS < 1 )); then
  SLOTS=1
fi
if (( SLOTS > 3 )); then
  SLOTS=3
fi

# Capacity-contention rationale (why the design default is 2, not 3+): (1) one
# iteration fans out many subagents (implementer/test-writer execute, evaluator
# verifies every task, fixes are always re-evaluated), and that per-iteration
# fan-out multiplies by N against a shared ~20-concurrent subagent-spawn
# ceiling; (2) all N slots would authenticate through the same LOOP_CLI as one
# provider account, so they would share ONE rate-limit budget -- more slots
# raise request rate against an unchanged quota rather than adding real
# throughput; (3) the circuit breaker is provider-global (one state file, one
# 600s cooldown) -- a single OPEN trip stalls ALL N slots at once, so more
# slots raise the odds of a full-run stall without shortening it. N=3 crowds
# fact (1) hardest, which is why 2 (not 3) is the design default.

# Guard replacement (STORY-011, replaces the STORY-010 dark-launch guard):
# LOOP_SLOTS>1 is honored IFF LOOP_WORKTREE=1 -- per-slot worktree isolation
# is the mechanism that makes concurrent slots sound (disjoint checkouts);
# without it, N slots would share one working tree and stomp each other's
# checkout state. At LOOP_WORKTREE=0, EFFECTIVE_SLOTS clamps to 1 regardless
# of the requested SLOTS value, with a one-line stderr note fired only when
# >1 was EXPLICITLY requested (LOOP_SLOTS_EXPLICIT) -- never on every default
# run. THIS repo stays gitignored (worktree preflight is inoperable here), so
# live runs here remain serial N=1; N=2 behavior is proven in the harness's
# tracked sandboxes.
if (( SLOTS > 1 )) && (( WORKTREE != 1 )); then
  EFFECTIVE_SLOTS=1
else
  EFFECTIVE_SLOTS=$SLOTS
fi

if [[ -n "$LOOP_SLOTS_EXPLICIT" ]] && (( LOOP_SLOTS_EXPLICIT > 1 )) \
   && (( WORKTREE != 1 )); then
  echo "LOOP_SLOTS>1 requires LOOP_WORKTREE=1 (worktree isolation); running with 1" >&2
fi

mode_str="main-tree"
if (( WORKTREE == 1 )); then
  mode_str="worktree"
fi
echo "slots: $EFFECTIVE_SLOTS (mode: $mode_str)"
else
  EFFECTIVE_SLOTS=0
fi

# detect_rate_limit <output> -> return 0 iff any SINGLE line of <output> matches the
# pinned rate-limit pattern (case-insensitive), 1 otherwise. Deliberately line-oriented
# (grep matches within one line at a time — it never merges text across newlines) —
# never `[[ output =~ pattern ]]` on the whole multi-line capture, whose `.` can cross
# line boundaries and falsely join unrelated lines (e.g. a bare token count on one line
# and the word "error" on another).
# Herestrings (`<<<`), not `printf | grep`, and a SINGLE grep per stage (no
# inter-grep pipe at all): under `set -o pipefail`, any pipeline whose
# downstream `grep -q` matches and exits early can SIGPIPE an upstream process
# still writing a large capture — pipefail then reports the pipeline's status
# as that upstream process's non-zero (SIGPIPE, 141, the rightmost NON-ZERO
# exit), not the downstream grep's own successful 0, silently flipping a real
# match into "no match". A herestring feeds data via a pre-materialized temp
# file with no live producer to SIGPIPE, closing that path for stage 1. Stage
# 2's "429 co-occurring with a keyword on the same line" no longer pipes one
# grep into another either: the co-occurrence is folded into ONE bidirectional
# alternation (`429.*(keyword)|(keyword).*429`) so a single process decides
# the whole stage — no process boundary for a downstream match to SIGPIPE
# across, at any capture size. Still strictly line-oriented (grep's `.` never
# crosses a newline), so a bare `429` on one line and a keyword on another
# never falsely co-occur.
detect_rate_limit() {
  local output="$1"
  grep -qiE 'rate.?limit|too many requests|quota (exceeded|reached|hit)' <<< "$output" && return 0
  grep -qiE '429.*(error|status|http|rate|too many)|(error|status|http|rate|too many).*429' <<< "$output" && return 0
  return 1
}

# _loop_detect_rate_limit_stream <raw> -> return 0 when any line is a typed api_retry
# rate-limit event (stream-json); malformed lines are ignored (grep no-match guarded).
_loop_detect_rate_limit_stream() {
  local raw="$1"
  local stage1 stage2
  stage1="$(grep -E '^\{.*"type"[[:space:]]*:[[:space:]]*"system"' <<< "$raw" 2>/dev/null)" || true
  [[ -z "$stage1" ]] && return 1
  stage2="$(grep -E '"subtype"[[:space:]]*:[[:space:]]*"api_retry"' <<< "$stage1" 2>/dev/null)" || true
  [[ -z "$stage2" ]] && return 1
  if grep -qE '"error"[[:space:]]*:[[:space:]]*"(rate_limit|overloaded)"' <<< "$stage2" 2>/dev/null; then
    return 0
  fi
  return 1
}

# _loop_claude_stream_text_fallback_raw <raw> -> stderr plus the final result envelope
# only (transcript JSON event lines stripped) for detect_rate_limit fallback.
_loop_claude_stream_text_fallback_raw() {
  local raw="$1"
  local result_line line out=""
  result_line="$(_loop_last_json_line "$raw" '"type":"result"')"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == \{* ]]; then
      if [[ -n "$result_line" && "$line" == "$result_line" ]]; then
        if [[ -n "$out" ]]; then
          out+=$'\n'
        fi
        out+="$line"
      fi
      continue
    fi
    if [[ -n "$out" ]]; then
      out+=$'\n'
    fi
    out+="$line"
  done <<< "$raw"
  printf '%s' "$out"
}

# _loop_last_json_line <raw> [needle] -> last line starting with `{`, optionally
# containing <needle> (empty needle = any `{` line).
_loop_last_json_line() {
  local raw="$1" needle="${2:-}" line last=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == \{* ]] || continue
    if [[ -z "$needle" || "$line" == *"$needle"* ]]; then
      last="$line"
    fi
  done <<< "$raw"
  printf '%s' "$last"
}

# _loop_json_field <json-line> <field> -> first grep -o match digits/text after field.
_loop_json_field() {
  local json="$1" field="$2" match
  match="$(grep -oE "\"${field}\":[0-9]+(\.[0-9]+)?" <<< "$json" | head -1)" || true
  [[ -z "$match" ]] && return 1
  sed "s/\"${field}\"://" <<< "$match"
}

# _loop_format_usage_line <input> <output> <cache_read> <cache_write> <cost> <fmt>
_loop_format_usage_line() {
  local inp="${1:-n/a}" out="${2:-n/a}" cr="${3:-n/a}" cw="${4:-n/a}" cost="${5:-n/a}" fmt="$6"
  [[ -z "$inp" ]] && inp="n/a"
  [[ -z "$out" ]] && out="n/a"
  [[ -z "$cr" ]] && cr="n/a"
  [[ -z "$cw" ]] && cw="n/a"
  [[ -z "$cost" ]] && cost="n/a"
  printf 'usage: input=%s output=%s cache_read=%s cache_write=%s cost_usd=%s format=%s\n' \
    "$inp" "$out" "$cr" "$cw" "$cost" "$fmt"
}

_loop_run_tokens=0
_loop_run_cost_micro=0
_loop_run_cost_seen=0
_loop_run_activity=0
_loop_ledger_warned=0
_loop_stories=()
_loop_st_tok=()
_loop_st_cost_micro=()
_loop_st_cost_seen=()
_loop_st_reaps=()
_loop_st_last_outcome=()
_loop_story_idx=0
_loop_outcome_names=(passed failed blocked mismatch abnormal subset tamper timeout protected nonff killed)
_loop_outcome_counts=(0 0 0 0 0 0 0 0 0 0 0)
_loop_reap_diff_files=0
_loop_reap_diff_lines=0

_loop_json_escape() {
  local s="$1" out="" i c
  local LC_ALL=C
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\' ;;
      \") out+='\"' ;;
      $'\n'|$'\r'|$'\t') out+=' ' ;;
      [[:cntrl:]]) out+=' ' ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

_loop_story_index() {
  local story="$1" i n
  n=${#_loop_stories[@]}
  for ((i = 0; i < n; i++)); do
    if [[ "${_loop_stories[i]}" == "$story" ]]; then
      _loop_story_idx=$i
      return 0
    fi
  done
  _loop_stories+=("$story")
  _loop_st_tok+=(0)
  _loop_st_cost_micro+=(0)
  _loop_st_cost_seen+=(0)
  _loop_st_reaps+=(0)
  _loop_st_last_outcome+=("")
  _loop_story_idx=$n
}

_loop_story_tokens() {
  local story="$1" i n=${#_loop_stories[@]}
  for ((i = 0; i < n; i++)); do
    if [[ "${_loop_stories[i]}" == "$story" ]]; then
      printf '%s' "${_loop_st_tok[i]}"
      return 0
    fi
  done
  printf '0'
}

_loop_story_cost_micro() {
  local story="$1" i n=${#_loop_stories[@]}
  for ((i = 0; i < n; i++)); do
    if [[ "${_loop_stories[i]}" == "$story" ]]; then
      printf '%s' "${_loop_st_cost_micro[i]}"
      return 0
    fi
  done
  printf '0'
}

_loop_story_reaps() {
  local story="$1" i n=${#_loop_stories[@]}
  for ((i = 0; i < n; i++)); do
    if [[ "${_loop_stories[i]}" == "$story" ]]; then
      printf '%s' "${_loop_st_reaps[i]}"
      return 0
    fi
  done
  printf '0'
}

_loop_usage_accumulate() {
  local story="$1" inp out cr cw tok=0 micro idx
  inp="${_loop_usage_in:-}"
  out="${_loop_usage_out:-}"
  cr="${_loop_usage_cr:-}"
  cw="${_loop_usage_cw:-}"
  [[ -z "$inp" ]] && inp=0
  [[ -z "$out" ]] && out=0
  [[ -z "$cr" ]] && cr=0
  [[ -z "$cw" ]] && cw=0
  case "$usage_format_resolved" in
    codex) tok=$(( inp + out )) ;;
    claude|claude-stream|cursor) tok=$(( inp + out + cr + cw )) ;;
    *) tok=0 ;;
  esac
  _loop_run_tokens=$(( _loop_run_tokens + tok ))
  if [[ -n "${_loop_usage_cost:-}" ]]; then
    if micro="$(_loop_usd_to_micro "$_loop_usage_cost" 2>/dev/null)"; then
      _loop_run_cost_micro=$(( _loop_run_cost_micro + micro ))
      _loop_run_cost_seen=1
    fi
  fi
  _loop_story_index "$story"
  idx=$_loop_story_idx
  _loop_st_tok[idx]=$(( _loop_st_tok[idx] + tok ))
  if [[ -n "${_loop_usage_cost:-}" ]]; then
    if micro="$(_loop_usd_to_micro "$_loop_usage_cost" 2>/dev/null)"; then
      _loop_st_cost_micro[idx]=$(( _loop_st_cost_micro[idx] + micro ))
      _loop_st_cost_seen[idx]=1
    fi
  fi
  _loop_st_reaps[idx]=$(( _loop_st_reaps[idx] + 1 ))
}

_loop_outcome_bump() {
  local o="$1" i
  for ((i = 0; i < ${#_loop_outcome_names[@]}; i++)); do
    if [[ "${_loop_outcome_names[i]}" == "$o" ]]; then
      _loop_outcome_counts[i]=$(( _loop_outcome_counts[i] + 1 ))
      return 0
    fi
  done
  _loop_outcome_counts[1]=$(( _loop_outcome_counts[1] + 1 ))
}

_loop_reap_diff_stats() {
  local tree="$1" hb="$2" add del
  _loop_reap_diff_files=0
  _loop_reap_diff_lines=0
  while IFS=$'\t' read -r add del _ || [[ -n "$add" ]]; do
    [[ -z "$add" && -z "$del" ]] && continue
    _loop_reap_diff_files=$(( _loop_reap_diff_files + 1 ))
    if [[ "$add" != "-" && "$add" =~ ^[0-9]+$ ]]; then
      _loop_reap_diff_lines=$(( _loop_reap_diff_lines + add ))
    fi
    if [[ "$del" != "-" && "$del" =~ ^[0-9]+$ ]]; then
      _loop_reap_diff_lines=$(( _loop_reap_diff_lines + del ))
    fi
  done < <(git -C "$tree" diff --numstat "$hb" HEAD 2>/dev/null || true)
}

_loop_micro_to_usd_str() {
  local micro="$1" whole frac
  whole=$(( micro / 1000000 ))
  frac=$(( micro % 1000000 ))
  printf '%d.%06d' "$whole" "$frac"
}

_loop_run_budget_reached() {
  if (( _loop_run_budget_tokens > 0 )) && (( _loop_run_tokens >= _loop_run_budget_tokens )); then
    return 0
  fi
  if (( _loop_run_budget_usd_set == 1 )) && (( _loop_run_cost_seen == 1 )) \
     && (( _loop_run_cost_micro >= _loop_run_budget_usd_micro )); then
    return 0
  fi
  return 1
}

_loop_run_budget_limit_str() {
  if (( _loop_run_budget_tokens > 0 )) && (( _loop_run_tokens >= _loop_run_budget_tokens )); then
    printf 'tokens %s/%s' "$_loop_run_tokens" "$_loop_run_budget_tokens"
    return 0
  fi
  if (( _loop_run_budget_usd_set == 1 )) && (( _loop_run_cost_seen == 1 )) \
     && (( _loop_run_cost_micro >= _loop_run_budget_usd_micro )); then
    printf 'usd %s/%s' \
      "$(_loop_micro_to_usd_str "$_loop_run_cost_micro")" \
      "$(_loop_micro_to_usd_str "$_loop_run_budget_usd_micro")"
    return 0
  fi
  printf '%s' "budget"
}

_loop_story_budget_reached() {
  local story="$1" tok micro seen
  tok="$(_loop_story_tokens "$story")"
  if (( _loop_story_budget_tokens > 0 )) && (( tok >= _loop_story_budget_tokens )); then
    return 0
  fi
  if (( _loop_story_budget_usd_set == 1 )); then
    _loop_story_index "$story"
    seen="${_loop_st_cost_seen[_loop_story_idx]:-0}"
    micro="$(_loop_story_cost_micro "$story")"
    if (( seen == 1 )) && (( micro >= _loop_story_budget_usd_micro )); then
      return 0
    fi
  fi
  return 1
}

_loop_story_budget_limit_str() {
  local story="$1" tok micro seen
  tok="$(_loop_story_tokens "$story")"
  if (( _loop_story_budget_tokens > 0 )) && (( tok >= _loop_story_budget_tokens )); then
    printf 'tokens %s/%s' "$tok" "$_loop_story_budget_tokens"
    return 0
  fi
  _loop_story_index "$story"
  seen="${_loop_st_cost_seen[_loop_story_idx]:-0}"
  micro="$(_loop_story_cost_micro "$story")"
  if (( _loop_story_budget_usd_set == 1 )) && (( seen == 1 )) \
     && (( micro >= _loop_story_budget_usd_micro )); then
    printf 'usd %s/%s' \
      "$(_loop_micro_to_usd_str "$micro")" \
      "$(_loop_micro_to_usd_str "$_loop_story_budget_usd_micro")"
    return 0
  fi
  printf '%s' "budget"
}

_loop_backlog_story_title() {
  local story_id="$1" line title=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "## ${story_id}:"* ]]; then
      title="${line#*: }"
      break
    fi
  done < "$BACKLOG_FILE"
  printf '%s' "$title"
}

# _loop_ledger_append <slot> <outcome> [killed|reap]
# killed=1: minimal killed line (no usage, exit_status null).
_loop_ledger_append() {
  local s="$1" outcome="$2" mode="${3:-reap}"
  _loop_story_index "${slot_story[s]:-}"
  _loop_st_last_outcome[_loop_story_idx]="$outcome"
  _loop_outcome_bump "$outcome"
  if (( _loop_ledger_enabled == 0 )); then
    return 0
  fi
  local dir ts_end story attempt fmt model esc_story esc_reason
  local exit_json rate_json inp_json out_json cr_json cw_json cost_json cost_src
  local tamper="${_loop_tamper_status:-none}" reasons="${_loop_tamper_reasons:-}"
  dir="$(dirname "$_loop_ledger_path")"
  ts_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  story="${slot_story[s]:-}"
  attempt="${slot_attempt[s]:-0}"
  fmt="$usage_format_resolved"
  model="${slot_model[s]:-}"
  esc_story="$(_loop_json_escape "$story")"
  esc_reason="$(_loop_json_escape "$reasons")"
  if [[ "$mode" == "killed" ]]; then
    exit_json="null"
    rate_json="false"
    inp_json="null"
    out_json="null"
    cr_json="null"
    cw_json="null"
    cost_json="null"
    cost_src="null"
    tamper="none"
    reasons=""
    esc_reason="$(_loop_json_escape "$reasons")"
    _loop_reap_diff_files=0
    _loop_reap_diff_lines=0
  else
    exit_json="${_loop_reap_exit_status:-0}"
    if (( _loop_reap_rate_limited == 1 )); then
      rate_json="true"
    else
      rate_json="false"
    fi
    if [[ -n "${_loop_usage_in:-}" ]]; then inp_json="${_loop_usage_in}"; else inp_json="null"; fi
    if [[ -n "${_loop_usage_out:-}" ]]; then out_json="${_loop_usage_out}"; else out_json="null"; fi
    if [[ -n "${_loop_usage_cr:-}" ]]; then cr_json="${_loop_usage_cr}"; else cr_json="null"; fi
    if [[ -n "${_loop_usage_cw:-}" ]]; then cw_json="${_loop_usage_cw}"; else cw_json="null"; fi
    if [[ -n "${_loop_usage_cost:-}" ]]; then
      cost_json="${_loop_usage_cost}"
      cost_src='"cli_estimate"'
    else
      cost_json="null"
      cost_src="null"
    fi
  fi
  local model_json
  if [[ -z "$model" ]]; then
    model_json="null"
  else
    model_json="\"$(_loop_json_escape "$model")\""
  fi
  local line
  line="{\"schema\":1,\"run_id\":\"$(_loop_json_escape "$run_id")\","
  line+="\"ts_start\":\"${slot_ts_start[s]:-}\",\"ts_end\":\"$ts_end\","
  line+="\"slot\":$((s + 1)),\"story\":\"$esc_story\",\"attempt\":$attempt,"
  line+="\"format\":\"$(_loop_json_escape "$fmt")\",\"model\":$model_json,"
  line+="\"exit_status\":$exit_json,\"outcome\":\"$outcome\",\"rate_limited\":$rate_json,"
  line+="\"gen_ai.usage.input_tokens\":$inp_json,\"gen_ai.usage.output_tokens\":$out_json,"
  line+="\"cache_read_tokens\":$cr_json,\"cache_write_tokens\":$cw_json,"
  line+="\"cost_usd\":$cost_json,\"cost_source\":$cost_src,"
  line+="\"diff_files\":${_loop_reap_diff_files},\"diff_lines\":${_loop_reap_diff_lines},"
  line+="\"tamper\":\"$tamper\",\"tamper_reasons\":\"$esc_reason\"}"
  set +e
  if [[ ! -d "$dir" ]]; then
    { mkdir -p "$dir"; } 2>/dev/null
  fi
  { printf '%s\n' "$line" >> "$_loop_ledger_path"; } 2>/dev/null
  local wrc=$?
  set -e
  if (( wrc != 0 )) && (( _loop_ledger_warned == 0 )); then
    echo "!!! ledger write failed: $_loop_ledger_path" >&2
    _loop_ledger_warned=1
  fi
}

_loop_dossier_fence_safe() {
  local content="$1" line trimmed ticks n out="" i c
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="$line"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    if [[ "$trimmed" == \`* ]]; then
      ticks=""
      n=${#trimmed}
      for ((i = 0; i < n; i++)); do
        c="${trimmed:i:1}"
        [[ "$c" == \` ]] || break
        ticks+='`'
      done
      if [[ ${#ticks} -ge 4 ]]; then
        line="    $line"
      fi
    fi
    line="${line//<!-- loop:dossier:begin -->/<!-- loop dossier marker removed -->}"
    line="${line//<!-- loop:dossier:end -->/<!-- loop dossier marker removed -->}"
    if [[ -n "$out" ]]; then
      out+=$'\n'
    fi
    out+="$line"
  done <<< "$content"
  printf '%s' "$out"
}

_loop_dossier_verdict_line() {
  local content="$1" line trimmed past=0
  if [[ "$content" == "(none)" ]]; then
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "${line%$'\r'}" == "## Verdict" ]]; then
      past=1
      continue
    fi
    if (( past == 1 )); then
      trimmed="$line"
      trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
      if [[ -n "$trimmed" ]]; then
        printf '%s' "$line"
        return 0
      fi
    fi
  done <<< "$content"
}

_loop_dossier_failure_cksum() {
  local outcome="$1" exit_st="$2" tamper="$3" verdict_line="$4" payload
  payload="${outcome}|${exit_st}|${tamper}|${verdict_line}"
  printf '%s' "$payload" | cksum | awk '{print $1}'
}

_loop_dossier_truncate_bytes() {
  local text="$1" max="$2" sz
  sz="$(printf '%s' "$text" | wc -c | tr -d '[:space:]')"
  if (( sz <= max )); then
    printf '%s' "$text"
    return 0
  fi
  printf '%s' "$(printf '%s' "$text" | head -c "$(( max - 12 ))")"$'\n'"[truncated]"
}

_loop_dossier_capture_attempt() {
  local s="$1" outbox="$2" sz raw
  slot_dossier_attempt[s]="(none)"
  [[ -f "$outbox/attempt.md" && ! -L "$outbox/attempt.md" ]] || return 0
  sz="$(wc -c < "$outbox/attempt.md" 2>/dev/null | tr -d '[:space:]')" || sz=0
  raw="$(head -c 1500 "$outbox/attempt.md" 2>/dev/null || true)"
  if (( sz > 1500 )); then
    raw="${raw}"$'\n'"[truncated]"
  fi
  slot_dossier_attempt[s]="$(_loop_dossier_fence_safe "$raw")"
}

_loop_dossier_capture_diffstat() {
  local s="$1" tree="$2" hb="$3" head_now stat_raw line n=0 indented=""
  slot_dossier_diffstat[s]="(diffstat unavailable)"
  head_now="$(git -C "$tree" rev-parse HEAD 2>/dev/null)" || return 0
  if [[ "$hb" == "$head_now" ]]; then
    slot_dossier_diffstat[s]="(no commits)"
    return 0
  fi
  stat_raw="$(git -C "$tree" diff --stat "$hb" HEAD 2>/dev/null)" || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( n >= 20 )); then
      break
    fi
    if [[ -n "$indented" ]]; then
      indented+=$'\n'
    fi
    indented+="  $line"
    n=$(( n + 1 ))
  done <<< "$stat_raw"
  if [[ -n "$indented" ]]; then
    slot_dossier_diffstat[s]="$indented"
  fi
}

_loop_dossier_clear_story() {
  local story="$1" path
  (( _loop_dossier_enabled == 1 )) || return 0
  if [[ ! "$story" =~ ^[A-Za-z0-9._-]+$ ]]; then
    return 0
  fi
  path="$_loop_dossier_store/${story}.md"
  if [[ -f "$path" ]]; then
    rm -f "$path" 2>/dev/null || echo "!!! dossier write failed: $path" >&2
  fi
}

_loop_dossier_record_if_needed() {
  local s="$1" outcome="$2" reap_passes="${3:-0}"
  local story attempt diffstat n exit_st tamper_disp tamper_r vline sig cksum entry
  local path dir existing first_old combined
  if (( _loop_dossier_enabled == 0 )); then
    return 0
  fi
  if [[ "$outcome" == "passed" ]]; then
    return 0
  fi
  if (( reap_passes == 1 )); then
    return 0
  fi
  story="${slot_story[s]:-}"
  if [[ ! "$story" =~ ^[A-Za-z0-9._-]+$ ]]; then
    return 0
  fi
  attempt="${slot_dossier_attempt[s]:-(none)}"
  diffstat="${slot_dossier_diffstat[s]:-(diffstat unavailable)}"
  n="${slot_attempt[s]:-0}"
  exit_st="${_loop_reap_exit_status:-0}"
  tamper_r="${_loop_tamper_reasons:-}"
  tamper_disp="none"
  [[ -n "$tamper_r" ]] && tamper_disp="$tamper_r"
  vline="$(_loop_dossier_verdict_line "$attempt")"
  cksum="$(_loop_dossier_failure_cksum "$outcome" "$exit_st" "$tamper_r" "$vline")"
  sig="${outcome}-${cksum}"
  entry="### Attempt ${n} — ${outcome}"$'\n'
  entry+="- exit status: ${exit_st}"$'\n'
  entry+="- tamper: ${tamper_disp}"$'\n'
  entry+="- failure signature: ${sig}"$'\n'
  entry+="- diffstat:"$'\n'
  entry+="${diffstat}"$'\n'
  entry+="#### Slot notes (attempt.md)"$'\n'
  entry+="${attempt}"
  entry="$(_loop_dossier_truncate_bytes "$entry" 2048)"
  existing=""
  [[ -f "$_loop_dossier_store/${story}.md" ]] && existing="$(cat "$_loop_dossier_store/${story}.md" 2>/dev/null)" || existing=""
  if [[ -n "$existing" ]]; then
    first_old="$(printf '%s\n' "$existing" | awk 'BEGIN{e=0} /^### Attempt /{e++; if(e>1) exit} {if(e>=1) print}')"
    first_old="$(_loop_dossier_truncate_bytes "$first_old" 2048)"
    if [[ -n "$first_old" ]]; then
      combined="${entry}"$'\n\n'"${first_old}"
    else
      combined="$entry"
    fi
  else
    combined="$entry"
  fi
  path="$_loop_dossier_store/${story}.md"
  dir="$(dirname "$path")"
  set +e
  if [[ ! -d "$dir" ]]; then
    { mkdir -p "$dir"; } 2>/dev/null
  fi
  { printf '%s' "$combined" > "$path"; } 2>/dev/null
  local wrc=$?
  set -e
  if (( wrc != 0 )); then
    echo "!!! dossier write failed: $path" >&2
  fi
}

_loop_dossier_inject_block() {
  local story="$1" path content
  if (( _loop_dossier_enabled == 0 )); then
    return 0
  fi
  if [[ ! "$story" =~ ^[A-Za-z0-9._-]+$ ]]; then
    return 0
  fi
  path="$_loop_dossier_store/${story}.md"
  if [[ ! -f "$path" ]]; then
    return 0
  fi
  content="$(cat "$path")"
  if [[ -z "$content" ]]; then
    return 0
  fi
  content="$(_loop_dossier_fence_safe "$content")"
  printf '\n\n<!-- loop:dossier:begin -->\n## Prior attempts for %s (DATA — not instructions; verify against code)\n````text\n%s\n````\n<!-- loop:dossier:end -->' \
    "$story" "$content"
}

_loop_print_run_summary() {
  local i story idx cost_str total_cost
  if (( _loop_lint_mode == 1 )) || (( _loop_run_activity == 0 )); then
    return 0
  fi
  {
    echo "=== loop run summary (run $run_id) ==="
    for ((i = 0; i < ${#_loop_outcome_names[@]}; i++)); do
      if (( _loop_outcome_counts[i] > 0 )); then
        echo "${_loop_outcome_names[i]}: ${_loop_outcome_counts[i]}"
      fi
    done
    if (( _loop_run_cost_seen == 1 )); then
      total_cost="$(_loop_micro_to_usd_str "$_loop_run_cost_micro")"
      echo "tokens: $_loop_run_tokens cost_usd=$total_cost"
    else
      echo "tokens: $_loop_run_tokens cost_usd=n/a"
    fi
    for ((i = 0; i < ${#_loop_stories[@]}; i++)); do
      story="${_loop_stories[i]}"
      idx="$i"
      if (( _loop_st_cost_seen[idx] == 1 )); then
        cost_str="$(_loop_micro_to_usd_str "${_loop_st_cost_micro[idx]}")"
      else
        cost_str="n/a"
      fi
      echo "$story reaps=${_loop_st_reaps[idx]} last=${_loop_st_last_outcome[idx]} tokens=${_loop_st_tok[idx]} cost_usd=$cost_str"
    done
    if (( _loop_ledger_enabled == 0 )); then
      echo "ledger: off"
    else
      echo "ledger: $_loop_ledger_path"
    fi
  } >&2
}

# _loop_decode_slot_output <raw> <fmt> -> sets _loop_decoded_output and
# _loop_usage_line (printed after tail -n 25 when due).
_loop_decode_slot_output() {
  local raw="$1" fmt="$2"
  _loop_decoded_output="$raw"
  _loop_usage_line=""
  _loop_usage_in=""
  _loop_usage_out=""
  _loop_usage_cr=""
  _loop_usage_cw=""
  _loop_usage_cost=""

  if [[ "$fmt" == "none" ]]; then
    if (( usage_explicit == 1 )); then
      _loop_usage_line="usage: unavailable (format none)"
    fi
    return 0
  fi

  local envelope decoded inp out cr cw cost uline
  case "$fmt" in
    claude|claude-stream)
      envelope="$(_loop_last_json_line "$raw" '"type":"result"')"
      if [[ -z "$envelope" ]]; then
        _loop_usage_line="usage: unavailable (no envelope)"
        return 0
      fi
      decoded="$(jq -r '.result // empty' <<< "$envelope" 2>/dev/null)" || decoded=""
      if [[ -z "$decoded" ]]; then
        _loop_usage_line="usage: unavailable (no envelope)"
        return 0
      fi
      _loop_decoded_output="$decoded"
      inp="$(_loop_json_field "$envelope" input_tokens 2>/dev/null)" || inp=""
      out="$(_loop_json_field "$envelope" output_tokens 2>/dev/null)" || out=""
      cr="$(_loop_json_field "$envelope" cache_read_input_tokens 2>/dev/null)" || cr=""
      cw="$(_loop_json_field "$envelope" cache_creation_input_tokens 2>/dev/null)" || cw=""
      cost="$(_loop_json_field "$envelope" total_cost_usd 2>/dev/null)" || cost=""
      local cost_raw_match cost_raw
      cost_raw_match="$(grep -oE '"total_cost_usd":[0-9.]+([eE][-+]?[0-9]+)?' <<< "$envelope" | head -1)" || true
      cost_raw=""
      if [[ -n "$cost_raw_match" ]]; then
        cost_raw="${cost_raw_match#\"total_cost_usd\":}"
      fi
      if [[ "$cost_raw" =~ ^[0-9.]+[eE][-+]?[0-9]+$ ]]; then
        _loop_usage_cost="$(awk -v v="$cost_raw" 'BEGIN{printf "%.6f", v}')"
      else
        _loop_usage_cost="$cost"
      fi
      _loop_usage_in="$inp"
      _loop_usage_out="$out"
      _loop_usage_cr="$cr"
      _loop_usage_cw="$cw"
      _loop_usage_line="$(_loop_format_usage_line "$inp" "$out" "$cr" "$cw" "$cost" "$fmt")"
      ;;
    cursor)
      envelope="$(_loop_last_json_line "$raw" "")"
      if [[ -z "$envelope" ]]; then
        _loop_usage_line="usage: unavailable (no envelope)"
        return 0
      fi
      decoded="$(jq -r '.result // empty' <<< "$envelope" 2>/dev/null)" || decoded=""
      if [[ -z "$decoded" ]]; then
        _loop_usage_line="usage: unavailable (no envelope)"
        return 0
      fi
      _loop_decoded_output="$decoded"
      inp="$(_loop_json_field "$envelope" inputTokens 2>/dev/null)" || inp=""
      out="$(_loop_json_field "$envelope" outputTokens 2>/dev/null)" || out=""
      cr="$(_loop_json_field "$envelope" cacheReadTokens 2>/dev/null)" || cr=""
      cw="$(_loop_json_field "$envelope" cacheWriteTokens 2>/dev/null)" || cw=""
      _loop_usage_in="$inp"
      _loop_usage_out="$out"
      _loop_usage_cr="$cr"
      _loop_usage_cw="$cw"
      _loop_usage_line="$(_loop_format_usage_line "$inp" "$out" "$cr" "$cw" "n/a" "$fmt")"
      ;;
    codex)
      local line agent_line=""
      local sum_in=0 sum_out=0 sum_cached=0 found_agent=0 found_turn=0
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *'"type":"agent_message"'* ]]; then
          agent_line="$line"
          found_agent=1
        fi
        if [[ "$line" == *'"type":"turn.completed"'* ]]; then
          found_turn=1
          local ti to tc
          ti="$(_loop_json_field "$line" input_tokens 2>/dev/null)" || ti="0"
          to="$(_loop_json_field "$line" output_tokens 2>/dev/null)" || to="0"
          tc="$(_loop_json_field "$line" cached_input_tokens 2>/dev/null)" || tc="0"
          sum_in=$(( sum_in + ti ))
          sum_out=$(( sum_out + to ))
          sum_cached=$(( sum_cached + tc ))
        fi
      done <<< "$raw"
      if (( found_agent == 0 )); then
        _loop_usage_line="usage: unavailable (no envelope)"
        return 0
      fi
      decoded="$(jq -r '.item.text // empty' <<< "$agent_line" 2>/dev/null)" || decoded=""
      if [[ -z "$decoded" ]]; then
        _loop_usage_line="usage: unavailable (no envelope)"
        return 0
      fi
      _loop_decoded_output="$decoded"
      if (( found_turn == 0 )); then
        _loop_usage_line="$(_loop_format_usage_line "n/a" "n/a" "n/a" "n/a" "n/a" "$fmt")"
      else
        _loop_usage_in="$sum_in"
        _loop_usage_out="$sum_out"
        _loop_usage_cr="$sum_cached"
        _loop_usage_line="$(_loop_format_usage_line "$sum_in" "$sum_out" "$sum_cached" "n/a" "n/a" "$fmt")"
      fi
      ;;
    *)
      _loop_usage_line="usage: unavailable (format none)"
      ;;
  esac
}

# --- Slot table --------------------------------------------------------------
# bash-3.2-safe parallel indexed arrays (no associative arrays -- same floor
# breaker.sh:172-174 documents for `local -n`: bash 3.2 on stock macOS has
# neither). One row per slot, indexed 0..EFFECTIVE_SLOTS-1; this task's
# fill/poll/reap/integrate/refill loop iterates every row without changing
# this shape.
slot_pid=()
slot_tree=()
slot_branch=()
slot_no_progress=()
slot_last_error_sig=()
slot_same_error=()
slot_state=()   # "idle" | "running"
# Retirement (D2/STORY-012): a slot that trips CB1 or CB2 is RETIRED, not
# run-fatal -- slot_retired flips to 1 and FILL skips it forever (no
# un-retire path); slot_retire_reason records which breaker retired it
# ("cb1"|"cb2"), consumed only by the D3 aggregation funnel's 3-vs-2
# precedence test below.
slot_retired=()
slot_retire_reason=()
# In-memory claim table (STORY-011 §4 step 3; design twin note :456-459):
# slot -> story-id, parallel to the row above -- slot_writes mirrors the
# claimed story's writes: glob for the admission test below. Consulted via
# slot_state (only a "running" row counts as in-flight), never cleared on
# reap -- stale content in an idle row is inert because the state gate
# excludes it.
slot_story=()
slot_writes=()
# Per-slot dispatch bookkeeping populated by _loop_fill_slot, consumed by
# _loop_reap_slot -- these replace the single scalar locals (outbox_dir,
# out_file, head_before) the dark-launched N=1 code used, since N>1 now
# needs one of each per concurrently-running slot.
slot_outbox=()
slot_outfile=()
slot_headbefore=()
slot_ts_start=()
slot_start_epoch=()
slot_attempt=()
slot_model=()
# Copy-aside for <outbox>/memory/*.md between outbox removal and integrator
# step 3b (driver-owned temp under $TMPDIR; cleared at 3b end or EXIT trap).
slot_memory_aside=()
slot_dossier_attempt=()
slot_dossier_diffstat=()

for ((SLOT = 0; SLOT < EFFECTIVE_SLOTS; SLOT++)); do
  slot_pid[SLOT]=0
  slot_tree[SLOT]=""
  slot_branch[SLOT]=""
  slot_no_progress[SLOT]=0
  slot_last_error_sig[SLOT]=""
  slot_same_error[SLOT]=0
  slot_state[SLOT]="idle"
  slot_retired[SLOT]=0
  slot_retire_reason[SLOT]=""
  slot_story[SLOT]=""
  slot_writes[SLOT]=""
  slot_outbox[SLOT]=""
  slot_outfile[SLOT]=""
  slot_headbefore[SLOT]=""
  slot_ts_start[SLOT]=""
  slot_start_epoch[SLOT]=""
  slot_attempt[SLOT]=""
  slot_model[SLOT]=""
  slot_memory_aside[SLOT]=""
  slot_dossier_attempt[SLOT]=""
  slot_dossier_diffstat[SLOT]=""
done

# _loop_integrate_slot <tree> <branch> -- interim integration (flag=1 only).
# ORDERING PINNED: merge --ff-only (from the MAIN tree, i.e. this process's
# own cwd, never the worktree) -> worktree remove -> branch -d. That order is
# load-bearing: `git branch -d` fails while the branch is still checked out
# in a worktree, so the worktree must be removed first. Non-ff -> loud
# stderr + exit 5, never merge -- a plain function call (not a subshell), so
# this `exit` terminates the whole script, i.e. stays driver-level.
# Called from _loop_reap_slot's disposal step, AFTER the pre-merge subset
# check passes (below) -- this helper still owns only the merge mechanics;
# the subset check, the ITERATION-mismatch quarantine, and the abnormal-exit
# quarantine all live in the caller.
_loop_integrate_slot() {
  local tree="$1" branch="$2" s="$3"
  # N>1 addendum (necessary for the pinned ff-only policy to actually work
  # under real concurrency, argued rather than silent): every slot filled in
  # the SAME round forks its worktree branch from the identical base HEAD
  # (nothing merges until reap), so once one sibling has merged, the NEXT
  # sibling reaped is no longer a descendant of the new HEAD -- a plain
  # `--ff-only` would spuriously fail even though admission already
  # guaranteed the two branches' writes: are disjoint. Rebasing the branch
  # onto the CURRENT main HEAD first (from inside the worktree, so the
  # worktree's own branch ref gains the replayed commit) is safe precisely
  # BECAUSE that same disjoint-writes guarantee means the rebase itself
  # cannot conflict in the normal case. A genuine rebase conflict (something
  # admission did not anticipate) aborts the rebase and falls through to the
  # SAME non-ff/exit-5 disposition below -- never silently resolved.
  if ! git -C "$tree" rebase "$(git rev-parse HEAD)" >/dev/null 2>&1; then
    git -C "$tree" rebase --abort >/dev/null 2>&1 || true
  fi
  if ! git merge --ff-only "$branch"; then
    echo "!!! integration failed: '$branch' is not a fast-forward of the current tree — stopping (worktree and branch retained for inspection: $tree)" >&2
    _loop_ledger_append "$s" "nonff"
    _loop_dossier_record_if_needed "$s" "nonff" "${reap_set_passes:-0}"
    exit 5
  fi
  git worktree remove "$tree"
  git branch -d "$branch"
}

# _loop_memory_aside_cleanup_all -- remove per-slot memory proposal copy-aside
# dirs (mktemp under $TMPDIR). Called from the EXIT trap so CB0 (exit 4) and
# failed ff-only integration (exit 5) never leak when step 3b is not reached.
_loop_memory_aside_cleanup_all() {
  local s
  for ((s = 0; s < EFFECTIVE_SLOTS; s++)); do
    if [[ -n "${slot_memory_aside[s]:-}" ]]; then
      rm -rf "${slot_memory_aside[s]}"
      slot_memory_aside[s]=""
    fi
  done
}

# _loop_memory_aside_cleanup_slot <slot> -- remove one slot's copy-aside dir.
_loop_memory_aside_cleanup_slot() {
  local s="$1"
  if [[ -n "${slot_memory_aside[s]:-}" ]]; then
    rm -rf "${slot_memory_aside[s]}"
    slot_memory_aside[s]=""
  fi
}

# _loop_integrate_memory_proposals <slot> <story-id> <aside-dir>
# Integrator step 3b body: parse proposals, call _kit/memory.sh add, path-limited
# commit. Must not trip set -e; never changes run exit code or backlog state.
_loop_integrate_memory_proposals() {
  local s="$1" story="$2" aside_dir="$3"
  local memory_sh="$PWD/_kit/memory.sh"
  local sorted_list f base name
  local -a commit_paths=()
  local proposal_count=0

  shopt -s nullglob
  for f in "$aside_dir"/*.md; do
    proposal_count=$((proposal_count + 1))
  done
  shopt -u nullglob
  if (( proposal_count == 0 )); then
    return 0
  fi

  if [[ ! -f "$memory_sh" ]]; then
    echo "!!! memory proposals skipped: _kit/memory.sh not found" >&2
    return 0
  fi

  sorted_list="$(mktemp)" || {
    echo "!!! memory proposals skipped: mktemp failed" >&2
    return 0
  }
  shopt -s nullglob
  for f in "$aside_dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    printf '%s\t%s\n' "$base" "$f"
  done | LC_ALL=C sort -t $'\t' -k1,1 > "$sorted_list"
  shopt -u nullglob

  while IFS=$'\t' read -r base fpath || [[ -n "$base" ]]; do
    [[ -n "$base" ]] || continue
    [[ -f "$fpath" ]] || continue
    name="${base%.md}"
    local body_tmp meta_err meta_file
    # mktemp failure mid-pass: stop further proposals (break), but still reach the
    # commit step below for records already added.
    body_tmp="$(mktemp)" || {
      echo "!!! memory proposals skipped: mktemp failed" >&2
      break
    }
    meta_err="$(mktemp)" || {
      echo "!!! memory proposals skipped: mktemp failed" >&2
      rm -f "$body_tmp"
      break
    }
    meta_file="$(mktemp)" || {
      echo "!!! memory proposals skipped: mktemp failed" >&2
      rm -f "$body_tmp" "$meta_err"
      break
    }
    local kind="" title="" tags="" source="" harness="" sep_line="" parse_ok=0
    set +e
    LC_ALL=C awk -v metafile="$meta_file" '
      BEGIN { sep=0; delete seen; k=""; t=""; tg=""; so=""; ha=""; sep_line=0 }
      function die(msg) { print msg > "/dev/stderr"; exit 1 }
      {
        line=$0
        sub(/\r$/, "", line)
        if (sep) { next }
        if (line == "---") { sep=1; sep_line=NR; next }
        if (line == "") { die("blank header line") }
        p=index(line, ": ")
        if (p == 0) { die("header line without colon-space") }
        key=substr(line, 1, p - 1)
        val=substr(line, p + 2)
        if (key in seen) { die("duplicate header key") }
        seen[key]=1
        if (key == "kind") k=val
        else if (key == "title") t=val
        else if (key == "tags") tg=val
        else if (key == "source") so=val
        else if (key == "harness") ha=val
        else { die("unknown key") }
      }
      END {
        if (!sep) { die("no separator line") }
        if (k == "" || t == "") { die("missing kind or title") }
        print sep_line > metafile
        print k >> metafile
        print t >> metafile
        print tg >> metafile
        print so >> metafile
        print ha >> metafile
      }
    ' "$fpath" 2>"$meta_err"
    parse_ok=$?
    set -e
    if (( parse_ok != 0 )); then
      local reason
      reason="$(head -1 "$meta_err" 2>/dev/null || true)"
      [[ -z "$reason" ]] && reason="malformed proposal"
      echo "!!! memory proposal $name skipped: $reason" >&2
      rm -f "$body_tmp" "$meta_err" "$meta_file"
      continue
    fi
    rm -f "$meta_err"
    {
      IFS= read -r sep_line || sep_line=""
      IFS= read -r kind || kind=""
      IFS= read -r title || title=""
      IFS= read -r tags || tags=""
      IFS= read -r source || source=""
      IFS= read -r harness || harness=""
    } < "$meta_file"
    rm -f "$meta_file"
    if [[ "$sep_line" =~ ^[0-9]+$ ]] && (( sep_line > 0 )); then
      tail -n +$((sep_line + 1)) "$fpath" > "$body_tmp" 2>/dev/null || : > "$body_tmp"
    else
      : > "$body_tmp"
    fi

    local -a add_args=(add --root "$PWD" --kind "$kind" --title "$title" --body "$body_tmp")
    [[ -n "$tags" ]] && add_args+=(--tags "$tags")
    [[ -n "$source" ]] && add_args+=(--source "$source")
    [[ -n "$harness" ]] && add_args+=(--harness "$harness")

    local add_out add_err add_status first_err rel
    add_err="$(mktemp)" || {
      echo "!!! memory proposals skipped: mktemp failed" >&2
      rm -f "$body_tmp"
      break
    }
    set +e
    add_out="$("$memory_sh" "${add_args[@]}" </dev/null 2>"$add_err")"
    add_status=$?
    set -e
    first_err="$(head -1 "$add_err" 2>/dev/null || true)"
    first_err="${first_err%$'\r'}"
    rm -f "$body_tmp" "$add_err"

    if (( add_status == 0 )); then
      printf '%s\n' "$add_out"
      set -- $add_out
      if [[ "${2:-}" == "added" || "${2:-}" == "quarantined" ]]; then
        rel="${4:-}"
        [[ -n "$rel" ]] && commit_paths+=("$rel")
      fi
    elif (( add_status == 5 )); then
      echo "!!! memory proposal $name quarantined: $add_out" >&2
      set -- $add_out
      if [[ "${2:-}" == "quarantined" ]]; then
        rel="${4:-}"
        [[ -n "$rel" ]] && commit_paths+=("$rel")
      fi
    else
      echo "!!! memory proposal $name rejected (exit $add_status): ${first_err:-unknown error}" >&2
    fi
  done < "$sorted_list"
  rm -f "$sorted_list"

  if (( ${#commit_paths[@]} == 0 )); then
    return 0
  fi

  set +e
  git add -- "${commit_paths[@]}"
  local add_rc=$?
  if (( add_rc != 0 )); then
    echo "!!! memory records left uncommitted: git add failed (exit $add_rc)" >&2
    set -e
    return 0
  fi
  git commit -q -m "chore(memory): $story records" -- "${commit_paths[@]}"
  local commit_rc=$?
  set -e
  if (( commit_rc != 0 )); then
    echo "!!! memory records left uncommitted: git commit failed (exit $commit_rc)" >&2
  fi
}

active_slots=0
dispatched=0            # total dispatches across ALL slots this run -- counts
                         # against MAX_ITER (010 semantics preserved).
_loop_dispatch_seq=0     # monotonic counter for the interim `loop/iter-N` branch
                         # name (the real story id is unknown at spawn time until
                         # the claim below runs; unique across slots and rounds).
retained_branches=()   # quarantine-lite: branches from abnormally-exited
                        # slots, retained (not integrated) for inspection --
                        # named again in the driver's closing output below.
refused_ids=()   # protected-path REFUSALS this run (cycle-1 fix 10) -- named
                 # in the no-eligible-stories completion output below, so
                 # "complete" never silently masks permanently
                 # undispatchable work.

# _loop_report_retained -- prints the retained-branches list (if any) exactly
# once, in the driver's closing output, on EVERY run-ending path (0/1/2/3/4/5),
# not just the max-iterations path. An EXIT trap (bash 3.2-safe; no `wait -n`
# or associative-array trick involved) is the right primitive here: it fires
# once as the shell is about to terminate, on any exit reason, and — because
# it never calls `exit` itself — cannot alter the pending exit status, so it
# does not touch (and cannot hide) any of the literal `exit N` statements
# above (check G's greps still see them; this trap runs strictly after them).
_loop_report_retained() {
  if (( ${#retained_branches[@]} > 0 )); then
    echo "=== retained branches from quarantined slots (NOT integrated): ${retained_branches[*]} ==="
  fi
}
_loop_driver_exit_hook() {
  _loop_report_retained
  _loop_memory_aside_cleanup_all
  _loop_print_run_summary
}
trap _loop_driver_exit_hook EXIT

# =============================================================================
# STORY-011: driver-owned story selection, writes:-glob admission, in-memory
# claim table (task 01) + the fill/poll/reap/integrate/refill restructure,
# guard replacement, and the single-writer integrator (task 02) below. The
# selection/admission/claim/backlog-transition functions in this section are
# UNCHANGED from task 01 -- task 02 calls them per slot from the main loop
# instead of once per single-slot iteration.
# =============================================================================

# --- Protected paths -- shared by CB0's revert check below AND admission's
# refusal test (the CB0-vs-writes seam, addendum 1a): a story declaring
# writes: on any of these paths is REFUSED at claim time, so the unattended
# CB0 hard-revert can never be the FIRST detection point for it. -----------
PROTECTED_PATHS=(
  "_loop/"
  "{{IDE_DIR}}/agents/"
  "{{IDE_DIR}}/skills/"
  "orchestration-kit.manifest.json"
  ".gitattributes"
  "_memory/records/"
  "_memory/quarantine/"
)

# --- Hotspot set (§6.3 :700-724 + addendum 1c): per-FILE serialization --
# at most one in-flight story may hold any one member. Kit-repo paths only
# (minor E) -- inert in consumer installs, where these files are simply
# absent, so the membership test below never matches there.
_LOOP_HOTSPOTS=(
  "ORCHESTRATION.md"
  # Split string literal (adjacent-quote concatenation -> one unchanged
  # value at runtime): check E's model-ID heuristic greps for a
  # (claude|gpt|gemini) name directly followed by a dash and an
  # alphanumeric, which the emitter filename below would otherwise
  # false-positive-match -- it is a filename, not a model ID.
  "skills/agent-kit/emitters/claude""-code.md"
  "skills/agent-kit/emitters/codex.md"
  "skills/agent-kit/emitters/copilot.md"
  "skills/agent-kit/emitters/cursor.md"
  "skills/agent-kit/templates/ORCHESTRATION.md"
  "skills/agent-kit/templates/skills/feature/SKILL.template.md"
)

# _loop_normalize_glob <glob> -> prints the normalized PREFIX on stdout;
# returns 1 (prints nothing) iff a '*' appears anywhere OTHER than a
# trailing run of '*' characters (SUFFIX-ONLY rule, goal-pinned: globs are
# literal paths or `*`/`**` SUFFIX globs only -- any other placement is
# rejected). A literal path (no '*' at all) normalizes to itself.
# Bash-3.2-safe, no external tools. Stated conservatism: a trailing single
# '*' is promoted to the SAME prefix as '**' (one-level vs multi-level
# globbing is not distinguished) -- an over-approximation whose only cost is
# an unnecessary DEFER, never a missed collision.
_loop_normalize_glob() {
  local trimmed="$1"
  while [[ "$trimmed" == *'*' ]]; do
    trimmed="${trimmed%\*}"
  done
  if [[ "$trimmed" == *'*'* ]]; then
    return 1   # '*' remains outside the trailing run -- mid-path, REJECTED
  fi
  printf '%s' "$trimmed"
  return 0
}

# _loop_globs_intersect <glob1> <glob2> -> exit 0 (intersect) / 1 (disjoint)
# / 2 (either glob failed the suffix-only parse). EXACT semantics
# (goal-pinned): each glob normalizes to a PREFIX (above); two normalized
# prefixes intersect iff one is a prefix of the other (this also covers the
# equal case) -- e.g. `a/**` (-> `a/`) and `a/b` intersect because `a/` is a
# prefix of `a/b`; `a/*` (-> `a/`) and `b/*` (-> `b/`) do not.
_loop_globs_intersect() {
  local p1 p2
  p1="$(_loop_normalize_glob "$1")" || return 2
  p2="$(_loop_normalize_glob "$2")" || return 2
  [[ "$p1" == "$p2"* || "$p2" == "$p1"* ]]
}

# _loop_split_csv <csv> -> populates global array _csv_tokens, trimmed of
# surrounding whitespace. An absent/empty input yields ONE empty-string
# token (never zero tokens), so downstream intersection tests see the
# "absent writes: intersects everything" rule fall out of
# _loop_normalize_glob("") -> "" (a prefix of every string). Bash-3.2-safe
# (`read -a`; no mapfile, no associative arrays).
_loop_split_csv() {
  local input="$1" i tok
  _csv_tokens=()
  IFS=',' read -ra _csv_tokens <<< "$input" || true
  if (( ${#_csv_tokens[@]} == 0 )); then
    _csv_tokens=("")
  fi
  for ((i = 0; i < ${#_csv_tokens[@]}; i++)); do
    tok="${_csv_tokens[i]}"
    tok="${tok#"${tok%%[![:space:]]*}"}"
    tok="${tok%"${tok##*[![:space:]]}"}"
    _csv_tokens[i]="$tok"
  done
}

# _loop_writes_conflict <writes_csv_A> <writes_csv_B> -> exit 0 iff ANY glob
# in A's comma-list intersects ANY glob in B's. By the time this is called,
# malformed globs have already been rejected-and-blanked at parse (see
# _loop_bl_flush below), so a 2 (parse-rejected) return from
# _loop_globs_intersect should not occur here in practice; treated as "no
# conflict" defensively either way -- never a crash.
_loop_writes_conflict() {
  local a b
  _loop_split_csv "$1"; local -a toks_a=("${_csv_tokens[@]}")
  _loop_split_csv "$2"; local -a toks_b=("${_csv_tokens[@]}")
  for a in "${toks_a[@]}"; do
    for b in "${toks_b[@]}"; do
      # `if`-guarded (never a bare call followed by `; rc=$?`): a bare
      # command's nonzero status (the ordinary "these two don't intersect"
      # outcome) would trip this script's `set -e` immediately, since only
      # an `if`/`while` CONDITION (or a `&&`/`||`/`!` list) is exempted.
      if _loop_globs_intersect "$a" "$b"; then
        return 0
      fi
    done
  done
  return 1
}

# _loop_hotspot_conflict <writes_csv_A> <writes_csv_B> -> exit 0 iff A and B
# BOTH intersect the SAME hotspot member (§6.3 per-file serialization). Kept
# as an EXPLICIT, independently-auditable rule -- in practice a shared
# hotspot member is usually already caught by _loop_writes_conflict too
# (both stories would have to name/cover that same path), but this makes
# "at most one in-flight holder of any hotspot member" checkable on its own.
_loop_hotspot_conflict() {
  local hs
  for hs in "${_LOOP_HOTSPOTS[@]}"; do
    if _loop_writes_conflict "$1" "$hs" && _loop_writes_conflict "$2" "$hs"; then
      return 0
    fi
  done
  return 1
}

# --- Backlog parsing (driver-owned selection, §4 step 1) -------------------
# Bash-3.2-safe (no associative arrays, no mapfile): story blocks begin at a
# `## STORY-<id>: <title>` header and run to the next such header or EOF.
# Recognized field lines anywhere inside a block: `- priority: N`,
# `- passes: true|false`, `- attempts: N`, `- blocked: true|false`, and the
# optional `- writes: <glob>[, <glob>...]`. Parser robustness (minor H): a
# block missing ANY of the four pinned fields is INELIGIBLE -- reported
# loudly to stderr, never a crash, never a silent skip. A malformed
# (mid-path '*') writes: glob is reported loudly and the WHOLE story is
# treated as writes-absent (intersects everything, runs alone) this run --
# the suffix-only rule, goal-pinned. With second argument `lint`, each story
# dispatches to _loop_lint_bl_flush instead of _loop_bl_flush.
_loop_bl_flush() {
  # `if`-form throughout (never a bare `COND && action`/`COND || action` at
  # top level): under this script's `set -e`, a bare short-circuit list
  # whose left side is false has the WHOLE list's status (1), which is NOT
  # exempted from errexit the way an `if`/`while` CONDITION is -- it would
  # abort the entire driver on the very first ordinary "condition didn't
  # hold" case, not just on a real error.
  if [[ -z "$_bl_cur_id" ]]; then
    return 0
  fi
  if (( ! (_bl_cur_has_prio && _bl_cur_has_passes && _bl_cur_has_attempts && _bl_cur_has_blocked) )); then
    echo "!!! backlog: $_bl_cur_id is missing a pinned field line (priority/passes/attempts/blocked) -- INELIGIBLE" >&2
    return 0
  fi
  if [[ -n "$_bl_cur_writes" ]]; then
    _loop_split_csv "$_bl_cur_writes"
    local tok
    for tok in "${_csv_tokens[@]}"; do
      if ! _loop_normalize_glob "$tok" >/dev/null; then
        echo "!!! backlog: $_bl_cur_id declares a malformed writes: glob '$tok' (literal paths or trailing '*'/'**' suffix globs only) -- treating $_bl_cur_id as writes-absent (runs alone) this run" >&2
        _bl_cur_writes=""
        break
      fi
    done
  fi
  if [[ "$_bl_cur_blocked" == "false" && "$_bl_cur_passes" == "false" ]] && (( _bl_cur_attempts < 3 )); then
    local n=${#_bl_id[@]} j
    local idx=$n
    for ((j = 0; j < n; j++)); do
      if (( _bl_cur_priority < _bl_priority[j] )); then
        idx=$j
        break
      fi
    done
    for ((j = n; j > idx; j--)); do
      _bl_id[j]="${_bl_id[j-1]}"
      _bl_priority[j]="${_bl_priority[j-1]}"
      _bl_writes[j]="${_bl_writes[j-1]}"
      _bl_attempts[j]="${_bl_attempts[j-1]}"
    done
    _bl_id[idx]="$_bl_cur_id"
    _bl_priority[idx]="$_bl_cur_priority"
    _bl_writes[idx]="$_bl_cur_writes"
    _bl_attempts[idx]="$_bl_cur_attempts"
  fi
  return 0
}

# _loop_lint_bl_flush -- lint-mode flush hook (no arithmetic on raw field text).
_loop_lint_bl_flush() {
  if [[ -z "$_bl_cur_id" ]]; then
    return 0
  fi
  local n=${#_lint_ids[@]}
  _lint_ids[n]="$_bl_cur_id"
  _lint_priority[n]="$_bl_cur_priority"
  _lint_passes[n]="$_bl_cur_passes"
  _lint_attempts[n]="$_bl_cur_attempts"
  _lint_blocked[n]="$_bl_cur_blocked"
  _lint_writes[n]="$_bl_cur_writes"
  _lint_has_prio[n]=$_bl_cur_has_prio
  _lint_has_passes[n]=$_bl_cur_has_passes
  _lint_has_attempts[n]=$_bl_cur_has_attempts
  _lint_has_blocked[n]=$_bl_cur_has_blocked
  _lint_has_ac_heading[n]=$_bl_cur_has_ac_heading
  _lint_ac_count[n]=$_bl_cur_ac_count
  _lint_body[n]="$_bl_cur_body"
  return 0
}

_loop_parse_backlog() {
  local file="$1" lint_mode=0 line val
  if [[ "${2:-}" == "lint" ]]; then
    lint_mode=1
    _lint_ids=() _lint_priority=() _lint_passes=() _lint_attempts=() _lint_blocked=()
    _lint_writes=() _lint_has_prio=() _lint_has_passes=() _lint_has_attempts=()
    _lint_has_blocked=() _lint_has_ac_heading=() _lint_ac_count=() _lint_body=()
  fi
  _bl_id=() _bl_priority=() _bl_writes=() _bl_attempts=()
  _bl_cur_id="" _bl_cur_priority="" _bl_cur_passes="" _bl_cur_attempts=""
  _bl_cur_blocked="" _bl_cur_writes=""
  _bl_cur_has_prio=0 _bl_cur_has_passes=0 _bl_cur_has_attempts=0 _bl_cur_has_blocked=0
  if (( lint_mode == 1 )); then
    _bl_cur_has_ac_heading=0 _bl_cur_ac_count=0 _bl_cur_body="" _bl_in_ac=0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "## STORY-"* ]]; then
      if (( lint_mode == 1 )); then
        _loop_lint_bl_flush
      else
        _loop_bl_flush
      fi
      _bl_cur_id="${line#\#\# }"
      _bl_cur_id="${_bl_cur_id%%:*}"
      _bl_cur_priority="" _bl_cur_passes="" _bl_cur_attempts="" _bl_cur_blocked="" _bl_cur_writes=""
      _bl_cur_has_prio=0 _bl_cur_has_passes=0 _bl_cur_has_attempts=0 _bl_cur_has_blocked=0
      if (( lint_mode == 1 )); then
        _bl_cur_has_ac_heading=0 _bl_cur_ac_count=0 _bl_cur_body="${line}"$'\n' _bl_in_ac=0
      fi
      continue
    fi
    if [[ -z "$_bl_cur_id" ]]; then
      continue
    fi
    if (( lint_mode == 1 )); then
      _bl_cur_body="${_bl_cur_body}${line}"$'\n'
      if [[ "$line" == "**Acceptance criteria"* ]]; then
        _bl_cur_has_ac_heading=1
        _bl_in_ac=1
        continue
      fi
      if (( _bl_in_ac == 1 )) && { [[ "$line" == "- [ ]"* ]] || [[ "$line" == "- [x]"* ]] || [[ "$line" == "- [X]"* ]]; }; then
        _bl_cur_ac_count=$(( _bl_cur_ac_count + 1 ))
        continue
      fi
    fi
    case "$line" in
      "- priority:"*) val="${line#*: }"; _bl_cur_priority="${val// /}"; _bl_cur_has_prio=1 ;;
      "- passes:"*) val="${line#*: }"; _bl_cur_passes="${val// /}"; _bl_cur_has_passes=1 ;;
      "- attempts:"*) val="${line#*: }"; _bl_cur_attempts="${val// /}"; _bl_cur_has_attempts=1 ;;
      "- blocked:"*) val="${line#*: }"; _bl_cur_blocked="${val// /}"; _bl_cur_has_blocked=1 ;;
      "- writes:"*) _bl_cur_writes="${line#*: }" ;;
    esac
  done < "$file"
  if (( lint_mode == 1 )); then
    _loop_lint_bl_flush
  else
    _loop_bl_flush
  fi
}

# _loop_lint_driver_writes <writes_csv> -- mirror the writes-admission checks in _loop_bl_flush (no stderr).
_loop_lint_driver_writes() {
  local writes="$1" tok
  if [[ -z "$writes" ]]; then
    printf '%s' "$writes"
    return 0
  fi
  _loop_split_csv "$writes"
  for tok in "${_csv_tokens[@]}"; do
    if ! _loop_normalize_glob "$tok" >/dev/null; then
      printf '%s' ""
      return 0
    fi
  done
  printf '%s' "$writes"
}

# _loop_lint_driver_eligible <story-index> <lint_int_ere> -- admission overlap predicate.
_loop_lint_driver_eligible() {
  local idx="$1" lint_int_ere="$2" att
  if (( _lint_has_prio[idx] == 0 || _lint_has_passes[idx] == 0 \
     || _lint_has_attempts[idx] == 0 || _lint_has_blocked[idx] == 0 )); then
    return 1
  fi
  if [[ "${_lint_passes[idx]}" != "false" || "${_lint_blocked[idx]}" != "false" ]]; then
    return 1
  fi
  att="${_lint_attempts[idx]}"
  if [[ ! "$att" =~ $lint_int_ere ]] || (( att >= 3 )); then
    return 1
  fi
  return 0
}

_loop_lint_error() {
  local id="$1" msg="$2"
  echo "lint: error $id : $msg"
}

_loop_lint_warn() {
  local id="$1" msg="$2"
  echo "lint: warn $id : $msg"
}

# _loop_run_lint <backlog-path> -- backlog readiness check; exit 0 or 1; exit 5 via _loop_setup_fail when the backlog is missing, unreadable, or non-regular.
_loop_run_lint() {
  local file="$1" protected_csv body
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    _loop_setup_fail "$file is missing or unreadable"
  fi

  local lint_errors=0 lint_warnings=0
  _loop_parse_backlog "$file" lint
  local n=${#_lint_ids[@]} i j id prio att passes blocked writes tok hs
  local lint_writes_a lint_writes_b lint_int_ere='^-?(0|[1-9][0-9]*)$'

  protected_csv="$(IFS=,; echo "${PROTECTED_PATHS[*]}")"

  for ((i = 0; i < n; i++)); do
    id="${_lint_ids[i]}"
    for ((j = 0; j < i; j++)); do
      if [[ "${_lint_ids[j]}" == "$id" ]]; then
        _loop_lint_error "$id" "duplicate story id"
        lint_errors=$(( lint_errors + 1 ))
        break
      fi
    done
    if (( _lint_has_prio[i] == 0 )); then
      _loop_lint_error "$id" "missing required field: priority"
      lint_errors=$(( lint_errors + 1 ))
    fi
    if (( _lint_has_passes[i] == 0 )); then
      _loop_lint_error "$id" "missing required field: passes"
      lint_errors=$(( lint_errors + 1 ))
    fi
    if (( _lint_has_attempts[i] == 0 )); then
      _loop_lint_error "$id" "missing required field: attempts"
      lint_errors=$(( lint_errors + 1 ))
    fi
    if (( _lint_has_blocked[i] == 0 )); then
      _loop_lint_error "$id" "missing required field: blocked"
      lint_errors=$(( lint_errors + 1 ))
    fi

    prio="${_lint_priority[i]}"
    if (( _lint_has_prio[i] == 1 )); then
      if [[ ! "$prio" =~ $lint_int_ere ]]; then
        _loop_lint_error "$id" "priority must be a decimal integer without leading zeros"
        lint_errors=$(( lint_errors + 1 ))
      fi
    fi

    att="${_lint_attempts[i]}"
    if (( _lint_has_attempts[i] == 1 )); then
      if [[ ! "$att" =~ $lint_int_ere ]]; then
        _loop_lint_error "$id" "attempts must be a decimal integer without leading zeros"
        lint_errors=$(( lint_errors + 1 ))
      fi
    fi

    passes="${_lint_passes[i]}"
    if (( _lint_has_passes[i] == 1 )) && [[ "$passes" != "true" && "$passes" != "false" ]]; then
      _loop_lint_error "$id" "passes must be true or false"
      lint_errors=$(( lint_errors + 1 ))
    fi

    blocked="${_lint_blocked[i]}"
    if (( _lint_has_blocked[i] == 1 )) && [[ "$blocked" != "true" && "$blocked" != "false" ]]; then
      _loop_lint_error "$id" "blocked must be true or false"
      lint_errors=$(( lint_errors + 1 ))
    fi

    writes="${_lint_writes[i]}"
    if [[ -n "$writes" ]]; then
      _loop_split_csv "$writes"
      for tok in "${_csv_tokens[@]}"; do
        [[ -z "$tok" ]] && continue
        if ! _loop_normalize_glob "$tok" >/dev/null; then
          _loop_lint_error "$id" "malformed writes: glob '$tok' (literal paths or trailing '*'/'**' suffix globs only)"
          lint_errors=$(( lint_errors + 1 ))
        fi
      done
      if _loop_writes_conflict "$writes" "$protected_csv"; then
        _loop_lint_error "$id" "writes: intersects a protected path"
        lint_errors=$(( lint_errors + 1 ))
      fi
    else
      _loop_lint_warn "$id" "absent or empty writes: (story always runs alone)"
      lint_warnings=$(( lint_warnings + 1 ))
    fi

    if (( _lint_has_ac_heading[i] == 0 )); then
      _loop_lint_error "$id" "missing **Acceptance criteria** heading"
      lint_errors=$(( lint_errors + 1 ))
    elif (( _lint_ac_count[i] == 0 )); then
      _loop_lint_error "$id" "no acceptance criteria checklist items"
      lint_errors=$(( lint_errors + 1 ))
    fi

    if (( _lint_ac_count[i] > 8 )); then
      _loop_lint_warn "$id" "more than 8 acceptance criteria items (size proxy)"
      lint_warnings=$(( lint_warnings + 1 ))
    fi

    if [[ -n "$writes" ]]; then
      _loop_split_csv "$writes"
      if (( ${#_csv_tokens[@]} > 12 )); then
        _loop_lint_warn "$id" "more than 12 writes: globs (size proxy)"
        lint_warnings=$(( lint_warnings + 1 ))
      fi
      for hs in "${_LOOP_HOTSPOTS[@]}"; do
        if _loop_writes_conflict "$writes" "$hs"; then
          _loop_lint_warn "$id" "writes: glob covers a hotspot path"
          lint_warnings=$(( lint_warnings + 1 ))
          break
        fi
      done
    fi

    body="${_lint_body[i]:-}"
    if [[ "$body" == *"<title>"* ]]; then
      _loop_lint_warn "$id" "template placeholder text remains: <title>"
      lint_warnings=$(( lint_warnings + 1 ))
    fi
    if [[ "$body" == *"<comma-separated path globs>"* ]]; then
      _loop_lint_warn "$id" "template placeholder text remains: <comma-separated path globs>"
      lint_warnings=$(( lint_warnings + 1 ))
    fi
    if [[ "$body" == *"<observable, verifiable outcome>"* ]]; then
      _loop_lint_warn "$id" "template placeholder text remains: <observable, verifiable outcome>"
      lint_warnings=$(( lint_warnings + 1 ))
    fi
  done

  for ((i = 0; i < n; i++)); do
    if ! _loop_lint_driver_eligible "$i" "$lint_int_ere"; then
      continue
    fi
    lint_writes_a="$(_loop_lint_driver_writes "${_lint_writes[i]}")"
    for ((j = i + 1; j < n; j++)); do
      if ! _loop_lint_driver_eligible "$j" "$lint_int_ere"; then
        continue
      fi
      lint_writes_b="$(_loop_lint_driver_writes "${_lint_writes[j]}")"
      if _loop_writes_conflict "$lint_writes_a" "$lint_writes_b" \
         || _loop_hotspot_conflict "$lint_writes_a" "$lint_writes_b"; then
        _loop_lint_warn "${_lint_ids[i]}" "writes: globs intersect with eligible story ${_lint_ids[j]}"
        lint_warnings=$(( lint_warnings + 1 ))
        _loop_lint_warn "${_lint_ids[j]}" "writes: globs intersect with eligible story ${_lint_ids[i]}"
        lint_warnings=$(( lint_warnings + 1 ))
      fi
    done
  done

  local story_word=stories
  if (( n == 1 )); then
    story_word=story
  fi
  echo "lint: ${lint_errors} error(s), ${lint_warnings} warning(s) in ${n} ${story_word}"
  if (( lint_errors > 0 )); then
    exit 1
  fi
  exit 0
}

# _loop_backlog_set_field <file> <story_id> <field> <value> -- a targeted,
# bash-3.2-safe sed-in-place EQUIVALENT: rewrites every `- <field>: ...`
# line inside <story_id>'s block ONLY (a well-formed block has exactly one,
# so in practice this is a single-line edit), preserving every other byte
# (line-by-line reconstruction via a temp file + mv, never a real in-place
# edit that could half-write on interruption). In TRACKED installs
# these writes (attempts at claim; passes/blocked at reap) are
# working-tree-only and NEVER committed by the driver (goal minor B) -- a
# human or a future story commits them.
_loop_backlog_set_field() {
  local file="$1" story_id="$2" field="$3" value="$4"
  local tmp line in_block=0
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # NOTE: story_id already carries the "STORY-" prefix (that is how
    # _loop_parse_backlog captures it from the "## STORY-<id>: <title>"
    # header), so the block-start match below is "## ${story_id}:" -- NOT
    # "## STORY-${story_id}:", which would double the prefix.
    if [[ "$line" == "## ${story_id}:"* ]]; then
      in_block=1
    elif [[ "$line" == "## STORY-"* ]]; then
      in_block=0
    fi
    if (( in_block == 1 )) && [[ "$line" == "- ${field}:"* ]]; then
      printf -- '- %s: %s\n' "$field" "$value" >> "$tmp"
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$file"
  mv "$tmp" "$file"
}

# _loop_select_story -- driver-owned selection + admission (§4 steps 1-2;
# step 3's claim happens at the call site once SELECTED_ID is non-empty, so
# a caller can log/skip before mutating the backlog). Sets SELECTED_ID,
# SELECTED_WRITES, SELECTED_ATTEMPTS (all empty if nothing survives).
# Protected-path writes: REFUSE the story outright (loud stderr, skipped,
# NO attempts increment -- addendum 1a). Otherwise pairwise-admit against
# the CURRENT in-flight claims (slot_story[]/slot_writes[], gated on
# slot_state[]=="running" so a stale/idle row is never mistaken for
# in-flight) plus the hotspot rule; failing admission DEFERS (the story
# stays eligible, tried again later -- never blocks). Called once per idle
# slot per fill round (_loop_fill_slot below) -- admission is therefore
# re-evaluated against the claim table as it stands AFTER each slot filled
# earlier in the SAME round: two disjoint-writes stories both admit within
# one round, while an intersecting pair correctly defers the second until
# the first's claim is released at reap.
_loop_select_story() {
  SELECTED_ID="" SELECTED_WRITES="" SELECTED_ATTEMPTS=""
  _loop_parse_backlog "$BACKLOG_FILE"

  local protected_csv
  protected_csv="$(IFS=,; echo "${PROTECTED_PATHS[*]}")"

  local i n=${#_bl_id[@]} id writes attempts conflict j s
  for ((i = 0; i < n; i++)); do
    id="${_bl_id[i]}"
    writes="${_bl_writes[i]}"
    attempts="${_bl_attempts[i]}"

    # Absent/empty writes: is NEVER refused here -- it declares nothing, so
    # there is no glob to intersect the protected-path list; it runs alone
    # via the ordinary admission rule below (absent writes: intersects
    # everything) instead. Refusal is reserved for a story whose DECLARED
    # writes: glob actually intersects a protected path (addendum 1a).
    if [[ -n "$writes" ]] && _loop_writes_conflict "$writes" "$protected_csv"; then
      echo "!!! story $id REFUSED: writes: '$writes' intersects a protected path -- skipped (no attempts increment, no transition)" >&2
      # Dedup: selection re-runs at EVERY fill round, so an undedup'd append
      # would name the same refused id once per round in the completion line --
      # and round count varies with slot timing under N>1. `[*]:-` guards the
      # pre-4.4 empty-array set -u trip (same note as model_arg above).
      if [[ " ${refused_ids[*]:-} " != *" $id "* ]]; then
        refused_ids+=("$id")
      fi
      continue
    fi

    conflict=0
    for ((j = 0; j < ${#slot_story[@]}; j++)); do
      if [[ "${slot_state[j]:-idle}" != "running" ]]; then
        continue
      fi
      s="${slot_story[j]:-}"
      if [[ -z "$s" ]]; then
        continue
      fi
      if _loop_writes_conflict "$writes" "${slot_writes[j]:-}" \
         || _loop_hotspot_conflict "$writes" "${slot_writes[j]:-}"; then
        conflict=1
        break
      fi
    done
    if (( conflict == 1 )); then
      continue   # DEFER -- stays eligible, not consumed, never blocks
    fi

    SELECTED_ID="$id" SELECTED_WRITES="$writes" SELECTED_ATTEMPTS="$attempts"
    return 0
  done
  return 1
}

# _loop_path_matches_glob <path> <glob> -- concrete-path membership test used
# ONLY by the pre-merge subset check below (§6.1); distinct from
# _loop_globs_intersect (which compares two GLOBS against each other for
# admission). Reuses the SAME normalization (_loop_normalize_glob) but adds
# the exact-vs-prefix distinction a two-glob intersect test never needed: a
# literal glob (no trailing '*') must match <path> EXACTLY, while a
# suffix-glob (had a trailing '*'/'**', stripped by normalization) matches
# any <path> with that prefix -- the same suffix-only, prefix-promoted
# conservatism the admission rule already documents.
_loop_path_matches_glob() {
  local path="$1" glob="$2" prefix
  prefix="$(_loop_normalize_glob "$glob")" || return 1
  if [[ "$glob" == *'*' ]]; then
    [[ "$path" == "$prefix"* ]]
  else
    [[ "$path" == "$prefix" ]]
  fi
}

_loop_is_test_path() {
  local path="$1" base
  base="${path##*/}"
  if [[ -n "${LOOP_TEST_PATTERNS:-}" ]]; then
    local tok
    _loop_split_csv "$LOOP_TEST_PATTERNS"
    for tok in "${_csv_tokens[@]}"; do
      [[ -z "$tok" ]] && continue
      case "$path" in
        $tok) return 0 ;;
      esac
    done
    return 1
  fi
  case "/$path/" in
    */fixtures/*) return 1 ;;
  esac
  case "$base" in
    *.golden|*.snap) return 1 ;;
  esac
  case "/$path/" in
    */test/*|*/tests/*|*/__tests__/*|*/spec/*) return 0 ;;
  esac
  case "$base" in
    test_*|*_test.*|*.test.*|*.spec.*|*Test.*|*Tests.*) return 0 ;;
  esac
  return 1
}

# _loop_tamper_reason_lines <tree> <head_before> -- prints one tamper signal
# per line to stdout; empty on no signals or `git diff` failure (never aborts).
_loop_tamper_reason_lines() {
  local tree="$1" head_before="$2"
  local skip_ere='(^|[^A-Za-z0-9_])(xit|xdescribe|xtest)\(|\.(only|skip)\(|@(Disabled|Ignore)([^A-Za-z0-9_]|$)|pytest\.mark\.(skip|xfail)|(^|[^A-Za-z0-9_])t\.Skip\(|\[Ignore\]|Skip *= *"|#\[ignore\]|(^|[^A-Za-z0-9_])skip\(\)'
  local assert_ere='assert|expect\(|Assert\.|should\.|\.Should\(|require\.'
  local ns_line status rest path old new diff_out awk_result a b c
  local -a scan_path=() scan_old=() scan_new=() scan_status=()
  while IFS= read -r ns_line || [[ -n "$ns_line" ]]; do
    [[ -z "$ns_line" ]] && continue
    status="${ns_line%%$'\t'*}"
    rest="${ns_line#*$'\t'}"
    case "$status" in
      D*)
        path="$rest"
        if _loop_is_test_path "$path"; then
          printf 'deleted:%s\n' "$path"
        fi
        ;;
      R*|C*)
        old="${rest%%$'\t'*}"
        new="${rest#*$'\t'}"
        if _loop_is_test_path "$old" && ! _loop_is_test_path "$new"; then
          printf 'deleted:%s\n' "$old"
        fi
        if _loop_is_test_path "$new"; then
          scan_path+=("$new")
          scan_old+=("$old")
          scan_new+=("$new")
          scan_status+=("$status")
        fi
        ;;
      M*|A*)
        path="$rest"
        scan_path+=("$path")
        scan_old+=("$path")
        scan_new+=("")
        scan_status+=("$status")
        ;;
    esac
  done < <(git -C "$tree" -c core.quotePath=false diff --no-ext-diff --no-color -M \
    --name-status "$head_before" HEAD 2>/dev/null || true)

  local i n=${#scan_path[@]} assertable saw_skip assert_add assert_rem net
  for ((i = 0; i < n; i++)); do
    path="${scan_path[i]}"
    status="${scan_status[i]}"
    old="${scan_old[i]}"
    new="${scan_new[i]}"
    if ! _loop_is_test_path "$path"; then
      continue
    fi
    assertable=0
    case "$status" in
      M*|R*|C*) assertable=1 ;;
    esac
    saw_skip=0
    assert_add=0
    assert_rem=0
    _loop_tamper_skip_ere="$skip_ere"
    _loop_tamper_assert_ere="$assert_ere"
    _loop_tamper_assertable="$assertable"
    export _loop_tamper_skip_ere _loop_tamper_assert_ere _loop_tamper_assertable
    if [[ -n "$new" ]]; then
      diff_out=$(git -C "$tree" -c core.quotePath=false diff --no-ext-diff --no-color -M \
        "$head_before" HEAD -- "$old" "$new" 2>/dev/null) || diff_out=""
    else
      diff_out=$(git -C "$tree" -c core.quotePath=false diff --no-ext-diff --no-color -M \
        "$head_before" HEAD -- "$old" 2>/dev/null) || diff_out=""
    fi
    awk_result=$(awk '
      BEGIN {
        saw_skip = 0
        assert_add = 0
        assert_rem = 0
        in_hunk = 0
        skip_ere = ENVIRON["_loop_tamper_skip_ere"]
        assert_ere = ENVIRON["_loop_tamper_assert_ere"]
        assertable = ENVIRON["_loop_tamper_assertable"] + 0
      }
      /^@@/ { in_hunk = 1; next }
      in_hunk == 0 { next }
      /^\+/ {
        body = substr($0, 2)
        if (!saw_skip && body ~ skip_ere) {
          saw_skip = 1
        }
        if (assertable && body ~ assert_ere) {
          assert_add++
        }
        next
      }
      /^-/ {
        body = substr($0, 2)
        if (assertable && body ~ assert_ere) {
          assert_rem++
        }
        next
      }
      END { print saw_skip, assert_add, assert_rem }
' <<< "$diff_out" 2>/dev/null) || awk_result=""
    a=0
    b=0
    c=0
    if [[ -n "$awk_result" ]]; then
      read -r a b c <<< "$awk_result" 2>/dev/null || true
    fi
    case "$a" in
      0|1) saw_skip=$a ;;
    esac
    case "$b" in
      ''|*[!0-9]*) ;;
      *) assert_add=$b ;;
    esac
    case "$c" in
      ''|*[!0-9]*) ;;
      *) assert_rem=$c ;;
    esac
    if (( saw_skip )); then
      printf 'skip-marker:%s\n' "$path"
    fi
    if (( assertable == 1 )); then
      net=$(( assert_rem - assert_add ))
      if (( net > 0 )); then
        printf 'assertions-removed:%s:%s\n' "$path" "$net"
      fi
    fi
  done
}

# _loop_subset_violation <tree> <head_before> <writes_csv> -- prints (stdout,
# one per line) every path from `git diff --name-only <head_before>..HEAD`
# NOT covered by any glob in <writes_csv>; empty output = no violation
# (STORY-011 §6.1's pre-merge subset check). Caller-side contract: an
# absent/empty <writes_csv> is NOT passed here at all -- there is no
# declared upper bound to audit a story against, and admission's
# runs-alone rule already prevented any conflict for it, so the caller
# skips this check entirely rather than manufacturing a spurious
# violation. A `git diff` failure here (tree/refs somehow invalid) yields
# no lines to iterate, hence no violation reported -- defensive, matching
# _loop_writes_conflict's "never a crash" stance -- never called as a bare
# statement (always inside `[[ -n ... ]]` on its captured output), so this
# is an intentional check function, not a command whose real failure
# `set -e` is expected to catch.
_loop_subset_violation() {
  local tree="$1" head_before="$2" writes_csv="$3" path covered tok
  local -a bad=()
  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -z "$path" ]] && continue
    covered=0
    _loop_split_csv "$writes_csv"
    for tok in "${_csv_tokens[@]}"; do
      [[ -z "$tok" ]] && continue
      if _loop_path_matches_glob "$path" "$tok"; then
        covered=1
        break
      fi
    done
    if (( covered == 0 )); then
      bad+=("$path")
    fi
  done < <(git -C "$tree" diff --name-only "$head_before".."HEAD" 2>/dev/null || true)
  if (( ${#bad[@]} > 0 )); then
    printf '%s\n' "${bad[@]}"
  fi
}

# _loop_write_quarantine_marker <story> <slot> <branch> <status> <reason>
# <dirty_paths> <prompt> -- D4-pinned marker file, one per quarantined/killed
# branch: `.loop-worktrees/QUARANTINE-<branch, slashes -> dashes>.md`.
# Content order pinned byte-for-byte: `QUARANTINE`, `story:`, `slot:`,
# `branch:`, `status:`, `reason:` (mismatch|abnormal|subset|tamper|killed),
# `dirty_paths:` (porcelain flattened to one line, or `none`/the killed-path
# literal), a blank line, `--- dispatched prompt ---`, then the dispatched
# prompt verbatim. Called from both _loop_reap_slot's quarantine-lite
# disposal (flag=1 only) and _loop_kill_other_slots' kill path -- the two
# ONLY producers of quarantined/lost branches.
_loop_write_quarantine_marker() {
  local story="$1" slot="$2" branch="$3" status="$4" reason="$5"
  local dirty_paths="$6" prompt="$7"
  mkdir -p "$PWD/.loop-worktrees"
  local safe_branch="${branch//\//-}"
  {
    echo "QUARANTINE"
    echo "story: $story"
    echo "slot: $slot"
    echo "branch: $branch"
    echo "status: $status"
    echo "reason: $reason"
    echo "dirty_paths: $dirty_paths"
    echo ""
    echo "--- dispatched prompt ---"
    printf '%s\n' "$prompt"
  } > "$PWD/.loop-worktrees/QUARANTINE-${safe_branch}.md"
}

# _loop_kill_other_slots <except-slot> -- best-effort SIGTERM + reap of every
# OTHER "running" slot before a driver-fatal exit. Post-STORY-012 this
# helper's ONLY remaining caller is CB0's exit-4 path: CB1/CB2 no longer
# call it (they retire the slot and let the SAME reap's own disposal run
# instead -- see the D2 retirement block in _loop_reap_slot), and the
# exit-5 sites never called it either. Without this, a background child
# would be orphaned when this script exits, since nothing else in the
# process tree would ever `wait` for it. `kill`/`wait` failures (the child
# already exited on its own) are swallowed. Each killed slot's branch is
# named in the retained-branches EXIT-trap summary too (extending that
# summary's CONTENT, not its printing mechanism) AND now writes a D4
# quarantine marker (reason `killed`, status the literal string `killed`,
# dirty_paths `unknown (killed before reap)` since the worktree is never
# inspected post-kill) -- this closes the "killed, unexamined" deferral
# this comment used to record: the marker ships on this path now, sourcing
# the dispatched prompt from the killed slot's own outbox before that
# outbox is removed (the "(killed, unexamined)" retained-branches suffix
# below is otherwise unchanged).
_loop_kill_other_slots() {
  local except="$1" s
  for ((s = 0; s < EFFECTIVE_SLOTS; s++)); do
    if (( s == except )); then
      continue
    fi
    if [[ "${slot_state[s]:-idle}" == "running" ]]; then
      kill "${slot_pid[s]}" 2>/dev/null || true
      wait "${slot_pid[s]}" 2>/dev/null || true
      slot_state[s]="idle"
      if [[ -n "${slot_branch[s]:-}" ]]; then
        local killed_prompt=""
        if [[ -n "${slot_outbox[s]:-}" && -f "${slot_outbox[s]}/dispatch-prompt.md" ]]; then
          killed_prompt="$(cat "${slot_outbox[s]}/dispatch-prompt.md")"
        fi
        _loop_write_quarantine_marker "${slot_story[s]:-}" "$s" "${slot_branch[s]}" \
          "killed" "killed" "unknown (killed before reap)" "$killed_prompt"
        _loop_ledger_append "$s" "killed" "killed"
        _loop_run_activity=$(( _loop_run_activity + 1 ))
        if [[ -n "${slot_outbox[s]:-}" ]]; then
          rm -rf "${slot_outbox[s]}"
        fi
        retained_branches+=("${slot_branch[s]} (killed, unexamined)")
      fi
    fi
  done
}

# _loop_fill_slot <slot> -- attempts to select+admit+claim+dispatch ONE
# eligible story into the given idle SLOT. Sets global FILL_OK=1 iff a
# story was claimed and dispatched, FILL_OK=0 iff nothing currently
# survives selection+admission (an ORDINARY "nothing eligible right now"
# outcome, never a script error). Bare statement at EVERY call site below,
# never an if/while CONDITION: several genuine failures inside (git
# worktree add, etc.) are deliberately left UNGUARDED so `set -e` still
# aborts the whole script on a real error -- bash's condition-exemption from
# errexit is transitive into called function bodies, so wrapping this call
# in a condition would silently exempt those too.
_loop_fill_slot() {
  local s="$1"
  FILL_OK=0

  if _loop_run_budget_reached; then
    if [[ ! -r "$BACKLOG_FILE" ]]; then
      _loop_setup_fail "$BACKLOG_FILE is missing or unreadable -- cannot select stories (setup failure)"
    fi
    _loop_select_story || true
    if [[ -n "$SELECTED_ID" ]]; then
      if (( _loop_run_budget_stopped == 0 )); then
        echo "!!! run budget reached ($(_loop_run_budget_limit_str)) — no new stories dispatched" >&2
        _loop_run_budget_stopped=1
      fi
    fi
    return 0
  else
    # Mechanism B: evaluated at FILL time, per dispatch attempt (goal-pinned
    # under N>1) -- ONE breaker, driver-level, shared by every slot. If OPEN
    # and cooldown has not elapsed, log + sleep, then ask again (the second
    # call performs OPEN->HALF-OPEN and returns 0), then proceed with THIS
    # fill attempt. This sleep is NOT per-slot: it serializes ALL fills while
    # the shared provider-global breaker cools down -- an accepted, stated
    # consequence of one breaker state file shared across every slot (never
    # invent per-slot breaker state).
    local skip
    skip="$(breaker_should_skip "$STATE_FILE" "$(date +%s)")"
    if (( skip > 0 )); then
      echo "breaker OPEN — sleeping ${skip}s before HALF-OPEN trial"
      sleep "$skip"
      skip="$(breaker_should_skip "$STATE_FILE" "$(date +%s)")"
    fi
  fi

  # Loud gate: a missing/unreadable backlog is a SETUP failure, never a
  # "nothing eligible" completion -- without this check, _loop_select_story
  # would just read zero story blocks and report no-eligible-stories +
  # exit 0, silently masking a broken/absent backlog file as "complete".
  if [[ ! -r "$BACKLOG_FILE" ]]; then
    echo "!!! $BACKLOG_FILE is missing or unreadable -- cannot select stories (setup failure)" >&2
    exit 5
  fi

  # `|| true`: a "nothing eligible survived" result (exit 1) is an ORDINARY
  # outcome of this call, not a driver error.
  _loop_select_story || true
  if [[ -z "$SELECTED_ID" ]]; then
    return 0
  fi
  FILL_OK=1

  # Claim (§4 step 3): the driver increments attempts ITSELF, before
  # dispatch, so a crashed slot still counts against the 3-attempt cap.
  _loop_backlog_set_field "$BACKLOG_FILE" "$SELECTED_ID" "attempts" "$((SELECTED_ATTEMPTS + 1))"
  slot_story[s]="$SELECTED_ID"
  slot_writes[s]="$SELECTED_WRITES"
  slot_ts_start[s]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  slot_attempt[s]=$((SELECTED_ATTEMPTS + 1))
  slot_dossier_attempt[s]=""
  slot_dossier_diffstat[s]=""

  # Outbox dir (ARGUED DEVIATION vs the design's in-worktree location,
  # goal-pinned): a driver-created mktemp DIRECTORY, outside the repo
  # entirely -- works identically at LOOP_WORKTREE=0 (no worktree exists
  # yet), matches the existing per-slot output-file mktemp pattern, and has
  # zero gitignore surface. Appended into shared memory on reap.
  local outbox_dir
  outbox_dir="$(mktemp -d)"
  slot_outbox[s]="$outbox_dir"

  # Interim `loop/iter-<n>` branch naming: the real story id is unknown at
  # spawn time until _loop_select_story above returns it, and the name must
  # stay unique across slots/rounds -- a monotonic driver-global sequence,
  # not the story id itself (a story can be re-dispatched after a defer).
  _loop_dispatch_seq=$((_loop_dispatch_seq + 1))
  local branch="loop/iter-$_loop_dispatch_seq"

  # --- worktree lifecycle (LOOP_WORKTREE=1 only) ----------------------------
  if (( WORKTREE == 1 )); then
    # 1-based path naming: preserves STORY-010's shipped slot-1 surface
    # (harness 43-46/49)
    local wt="$PWD/.loop-worktrees/slot-$((s+1))"
    git worktree add -b "$branch" "$wt" HEAD >/dev/null

    # Loud preflight (cycle-3 correction): BOTH probes are built from the SAME
    # resolved worktree-path variable ($wt) just passed to `git worktree add`
    # above — never a second hardcoded literal. The second probe is a
    # DIRECTORY test on {{IDE_DIR}}, deliberately NOT a skill-FILE path: each
    # harness tree may carry its own skills (the Cursor
    # emitter is self-contained), so a single skill-file path can't cover
    # every install shape. {{IDE_DIR}} in this single-copy loop driver
    # resolves to the PRIMARY harness's dir, and a directory probe stays
    # layout-agnostic across all four harnesses regardless of which one is
    # primary. A directory probe on {{IDE_DIR}} is true on all four harnesses
    # whenever the instance is tracked, and false in exactly the
    # gitignored-instance case -- the iteration needs that whole directory
    # (it is sent to ORCHESTRATION.md and _memory/loop/ESCALATIONS.md), not just
    # one file in it.
    if [[ ! -f "$wt/_memory/loop/backlog.md" || ! -d "$wt/{{IDE_DIR}}" ]]; then
      echo "!!! worktree preflight failed: '$wt' is missing a tracked _memory/loop/backlog.md and/or a tracked {{IDE_DIR}} directory — a worktree checks out TRACKED files only, so this repo's loop instance must be committed (not gitignored) for LOOP_WORKTREE=1 — stopping, no fallback to the main tree" >&2
      git worktree remove --force "$wt" 2>/dev/null || true
      git worktree prune
      # The `-b "$branch"` on `git worktree add` above already created this
      # branch even though the preflight then failed -- without deleting it
      # here, a rerun's `git worktree add -b "$branch"` dies at git's own
      # exit 128 ("branch already exists"), not a loop-owned code.
      git branch -D "$branch" 2>/dev/null || true
      exit 5
    fi
    slot_tree[s]="$wt"
  else
    slot_tree[s]="$PWD"
  fi
  slot_branch[s]="$branch"

  local tree="${slot_tree[s]}"

  # DRIVER-owned HEAD capture, before dispatch (after reap: see
  # slot_headbefore consumed in _loop_reap_slot). Unified for both flags via
  # `-C`: at LOOP_WORKTREE=0, tree is $PWD, so this is identical to a plain
  # `git rev-parse HEAD`.
  slot_headbefore[s]="$(git -C "$tree" rev-parse HEAD)"

  local model model_arg=""
  breaker_probe "$STATE_FILE" "$(date +%s)"
  model="$(breaker_current_model "$STATE_FILE")"
  slot_model[s]="$model"
  # Plain string (not an array): kept consistent with $LOOP_CLI's own unquoted,
  # naive whitespace-splitting expansion below — and avoids the pre-4.4 bash bug
  # where an empty array referenced via "${arr[@]}" trips `set -u` as unbound.
  if [[ -n "$LOOP_MODEL_FLAG" && -n "$model" ]]; then
    model_arg="$LOOP_MODEL_FLAG $model"
  fi

  local p
  p="$(cat "$PROMPT_FILE")"
  # CRLF handling: strip BOTH trailing CR and LF, not CR alone
  # — command substitution above already strips trailing newlines, so a \n before a \r
  # (e.g. a CRLF file ending "text\r\n\r\n") would otherwise re-expose a trailing \r
  # that a CR-only strip misses.
  while [[ "$p" == *$'\r' || "$p" == *$'\n' ]]; do p="${p%?}"; done

  # Pinned-prompt substitution (§4 step 4 / prompt-pinning-mechanism pin):
  # the read line and the strip loop above are IDENTIFIER-PRESERVED
  # byte-for-byte (STORY-010 rule) -- substitution is applied to $p strictly
  # AFTER them, never inside. FAIL LOUD (exit 5, setup-failure category) if
  # the template lacks EITHER substitution point: a consumer-edited
  # PROMPT.md must never silently dispatch an unpinned prompt that flips the
  # slot into manual mode.
  if [[ "$p" != *'%%STORY_ID%%'* || "$p" != *'%%OUTBOX_DIR%%'* ]]; then
    echo "!!! PROMPT.md is missing %%STORY_ID%% and/or %%OUTBOX_DIR%% -- refusing to dispatch an unpinned prompt" >&2
    exit 5
  fi
  p="${p//%%STORY_ID%%/$SELECTED_ID}"
  p="${p//%%OUTBOX_DIR%%/$outbox_dir}"
  p="${p}$(_loop_dossier_inject_block "$SELECTED_ID")"

  # Dispatch-prompt capture (D5/STORY-012, addendum 1 §7.2 durable
  # evidence): the EXACT dispatched prompt, written after both
  # substitutions and before the child spawns -- driver-owned; slots must
  # not modify it. Read back at reap (before the outbox is removed) and
  # embedded verbatim in quarantine markers (D4) on every non-clean
  # disposal/kill path; discarded with the outbox on a clean integration.
  printf '%s' "$p" > "$outbox_dir/dispatch-prompt.md"

  # --- driver/child boundary (the pin) --------------------------------------
  # The child is a background subshell that runs ONLY the CLI invocation, cwd
  # = the slot's tree (worktree at LOOP_WORKTREE=1, main tree otherwise),
  # stdout+stderr redirected to a driver-created per-slot output file (mktemp,
  # outside the repo — no gitignore concern; removed after evaluation in
  # reap). The ONLY things that cross child->driver are the CLI exit status
  # (via `wait "$pid"` in _loop_reap_slot, after the kill -0 poll) and that
  # output file. Every exit 2/3/4/5 statement in this script lives OUTSIDE
  # this subshell, at driver level: an `exit` inside a subshell only ends the
  # subshell, and check G's grep cannot see that distinction, so keeping
  # every exit statement out here is a discipline this comment is the only
  # guard for.
  local out_file
  out_file="$(mktemp)"
  slot_outfile[s]="$out_file"
  slot_start_epoch[s]="$(date +%s)"
  if [[ -n "$_loop_timeout_bin" ]]; then
    (
      cd "$tree"
      "$_loop_timeout_bin" -s INT -k 60 "$_loop_iter_timeout" $LOOP_CLI $model_arg "$p" > "$out_file" 2>&1
    ) &
  else
    (
      cd "$tree"
      $LOOP_CLI $model_arg "$p" > "$out_file" 2>&1
    ) &
  fi
  slot_pid[s]=$!
  slot_state[s]="running"
  active_slots=$((active_slots + 1))
  return 0
}

# _loop_reap_slot <slot> -- drains ONE finished slot (caller has already
# confirmed `kill -0` is negative): real exit status, breaker record,
# ITERATION-mismatch check (quarantine-lite; ORDERED BEFORE the sentinel
# scan's own outcome, per the goal's reap-order pin), backlog transition,
# outbox appends (integration order = reap order), memory size gates, CB0
# (global-fatal, kills every other active slot), CB1/CB2 (per-slot
# RETIREMENT, D2/STORY-012 -- thresholds/semantics UNCHANGED from STORY-010,
# but a trip no longer ends the run: the slot retires and stops being
# refilled instead), and disposal
# (subset-check + integrate, or quarantine-lite). Bare statement at EVERY
# call site below -- see _loop_fill_slot's comment: this function contains
# unguarded `git worktree prune` / `git -C ... reset --hard` call sites that
# rely on `set -e` for real coverage, which only holds if this function is
# never itself the condition of an if/while.
_loop_reap_slot() {
  local s="$1"
  local pid="${slot_pid[s]}" tree="${slot_tree[s]}" branch="${slot_branch[s]}"
  local out_file="${slot_outfile[s]}" head_before="${slot_headbefore[s]}"
  local story="${slot_story[s]}" writes="${slot_writes[s]}"
  local outbox_dir="${slot_outbox[s]}"

  _loop_reap_timeout=0
  _loop_tamper_status=none
  _loop_tamper_reasons=""

  # Supervision handoff: the caller's `kill -0` poll already established the
  # child has exited (or is a collectible zombie); `wait` collects the real
  # exit status -- the portable bash-3.2-floor primitive (`wait -n` needs
  # bash 4.3+, which the kit does not require anywhere else either).
  set +e
  wait "$pid"
  local status=$?
  set -e

  slot_state[s]="idle"
  active_slots=$((active_slots - 1))   # refill trigger: slot exit, not merge

  # Identifier preservation (cycle-3): `output` is populated from the per-slot
  # output file the child wrote to (decoded `result` text when a usage format
  # is active) -- never a reimplementation. `raw` keeps the undecoded capture
  # for rate-limit detection.
  local raw output
  raw="$(cat "$out_file")"
  rm -f "$out_file"

  _loop_decode_slot_output "$raw" "$usage_format_resolved"
  output="$_loop_decoded_output"
  _loop_reap_exit_status=$status

  local detected fallback_raw
  if [[ "$usage_format_resolved" == "claude-stream" ]]; then
    if _loop_detect_rate_limit_stream "$raw"; then
      detected=1
    else
      fallback_raw="$(_loop_claude_stream_text_fallback_raw "$raw")"
      if detect_rate_limit "$fallback_raw"; then
        detected=1
      else
        detected=0
      fi
    fi
  elif detect_rate_limit "$raw"; then
    detected=1
  else
    detected=0
  fi
  _loop_reap_rate_limited=$detected
  if (( _loop_iter_timeout > 0 )); then
    local elapsed=$(( $(date +%s) - slot_start_epoch[s] ))
    if (( status == 124 || status == 137 )); then
      _loop_reap_timeout=1
    elif (( status != 0 )) && (( detected == 0 )) && (( elapsed >= _loop_iter_timeout )); then
      _loop_reap_timeout=1
    fi
    if (( _loop_reap_timeout == 1 )); then
      echo "!!! slot $s: iteration exceeded LOOP_ITER_TIMEOUT=${_loop_iter_timeout}s — interrupted" >&2
    fi
  fi
  _loop_usage_accumulate "$story"
  _loop_run_activity=$(( _loop_run_activity + 1 ))
  if (( _loop_any_budget_knob == 1 )); then
    case "$usage_format_resolved" in
      *)
        if [[ -z "${_loop_usage_in:-}" && -z "${_loop_usage_out:-}" && -z "${_loop_usage_cr:-}" && -z "${_loop_usage_cw:-}" ]]; then
          if (( _loop_note_no_usage_printed == 0 )); then
            echo "!!! budget: usage format $usage_format_resolved reported no usage — token/cost budgets cannot advance" >&2
            _loop_note_no_usage_printed=1
          fi
        fi
        ;;
    esac
  fi
  if (( _loop_reap_timeout == 1 )); then
    breaker_record "$STATE_FILE" 0 "$(date +%s)"
  else
    breaker_record "$STATE_FILE" "$detected" "$(date +%s)"
  fi

  printf '%s\n' "$output" | tail -n 25

  if [[ "$usage_format_resolved" != "none" || "$usage_explicit" -eq 1 ]]; then
    printf '%s\n' "$_loop_usage_line"
    if [[ -n "${LOOP_USAGE_LOG:-}" ]]; then
      printf '%s slot=%s story=%s %s\n' "$(date -Is)" "$s" "$story" "$_loop_usage_line" \
        >> "$LOOP_USAGE_LOG"
    fi
  fi

  # --- Integrator step 1: ITERATION validation, BEFORE sentinel handling
  # (goal-pinned reap order). A dispatched slot must NEVER emit the
  # sentinel (skill contract: it runs the pinned story without
  # re-evaluating eligibility); the driver's own no-eligible banner is the
  # ONLY completion path in dispatched runs. The sentinel scan below
  # survives byte-identical (extraction-site pin) -- its outcome now feeds
  # THIS mismatch decision, never a completion branch.
  local iteration_line iter_id iter_verdict="" mismatch=0
  iteration_line="$(grep -m1 '^ITERATION:' <<< "$output" || true)"
  if [[ -z "$iteration_line" ]]; then
    mismatch=1
  else
    read -r _ iter_id iter_verdict _ <<< "$iteration_line" || true
    if [[ "$iter_id" != "$story" ]]; then
      mismatch=1
    fi
  fi
  # Herestring, not `printf | grep`: same pipefail+SIGPIPE false-negative class as
  # detect_rate_limit above — no live producer here for a downstream match to SIGPIPE.
  if grep -qF "$SENTINEL" <<< "$output"; then
    mismatch=1   # sentinel-from-dispatched-slot rule: itself an ITERATION-mismatch
  fi

  # Integrator step 5's subset check is computed HERE, EARLY (not deferred to
  # the pre-merge disposal step below), so its outcome can also gate step 2's
  # backlog transition below: a subset violation must leave NO transition,
  # exactly like an ITERATION-mismatch (verified: backlog stays untouched for
  # a quarantined story either way). head_before/tree/writes are all already
  # known at this point (captured at dispatch), so nothing here waits on the
  # disposal step -- it just reuses this cached result instead of
  # re-running the same `git diff`.
  local subset_bad=""
  if (( WORKTREE == 1 )) && (( mismatch == 0 )) && [[ -n "$writes" ]]; then
    subset_bad="$(_loop_subset_violation "$tree" "$head_before" "$writes")"
  fi

  if [[ "$_loop_tamper_check" != "off" ]] && (( mismatch == 0 )); then
    local head_now tamper_line tamper_first=1
    head_now="$(git -C "$tree" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$head_now" && "$head_now" != "$head_before" ]]; then
      _loop_tamper_reasons=""
      while IFS= read -r tamper_line || [[ -n "$tamper_line" ]]; do
        [[ -z "$tamper_line" ]] && continue
        if (( tamper_first == 1 )); then
          _loop_tamper_reasons="$tamper_line"
          tamper_first=0
        else
          _loop_tamper_reasons+="; $tamper_line"
        fi
      done < <(_loop_tamper_reason_lines "$tree" "$head_before")
      if [[ -n "$_loop_tamper_reasons" ]]; then
        if [[ "$_loop_tamper_check" == "fail" ]]; then
          _loop_tamper_status=fail
        else
          _loop_tamper_status=warn
          echo "!!! tamper (warn) slot $s story $story: $_loop_tamper_reasons" >&2
        fi
      fi
    fi
  fi

  # --- Integrator step 2: backlog transition -- skipped entirely on an
  # ITERATION-mismatch, a subset-check violation, or tamper fail (STORY-010
  # disposition: NO backlog transition any of those ways).
  local reap_set_passes=0
  if (( mismatch == 1 )); then
    echo "!!! slot $s: ITERATION-mismatch (claim was '$story') -- quarantine-lite pending: no backlog transition, claim released" >&2
  elif [[ -n "$subset_bad" ]]; then
    echo "!!! slot $s: branch '$branch' touched paths outside its declared writes: -- quarantine-lite pending: no backlog transition, claim released: $subset_bad" >&2
  elif [[ "$_loop_tamper_status" == "fail" ]]; then
    echo "!!! slot $s: test tamper detected -- quarantine-lite pending: no backlog transition, claim released: $_loop_tamper_reasons" >&2
  else
    case "$iter_verdict" in
      passed) _loop_backlog_set_field "$BACKLOG_FILE" "$story" "passes" "true"; reap_set_passes=1 ;;
      blocked) _loop_backlog_set_field "$BACKLOG_FILE" "$story" "blocked" "true" ;;
      failed) : ;;   # attempts already counted at claim -- no field change
      *) echo "!!! ITERATION line for $story has an unrecognized verdict '$iter_verdict' -- no transition" >&2 ;;
    esac
  fi
  if (( reap_set_passes == 1 )); then
    _loop_dossier_clear_story "$story"
  fi

  if (( mismatch == 0 )) && [[ -z "$subset_bad" ]] && [[ "$_loop_tamper_status" != "fail" ]] \
     && [[ "${iter_verdict:-}" != "passed" ]] \
     && { (( _loop_story_budget_tokens > 0 )) || (( _loop_story_budget_usd_set == 1 )); }; then
    if _loop_story_budget_reached "$story"; then
      local st_title budget_msg
      st_title="$(_loop_backlog_story_title "$story")"
      budget_msg="story budget reached ($(_loop_story_budget_limit_str "$story")) after attempt ${slot_attempt[s]:-0}"
      _loop_backlog_set_field "$BACKLOG_FILE" "$story" "blocked" "true"
      {
        printf '\n## %s: %s\n' "$story" "$st_title"
        printf -- '- reason: %s\n' "$budget_msg"
      } >> "$PWD/_memory/loop/ESCALATIONS.md"
      echo "!!! $budget_msg" >&2
    fi
  fi

  # --- Integrator step 3: outbox appends, ALWAYS (independent evidence from
  # the child's own work) -- integration order = reap order.
  if [[ -f "$outbox_dir/learnings.md" ]]; then
    cat "$outbox_dir/learnings.md" >> "$PWD/_memory/loop/LEARNINGS.md"
  fi
  if [[ -f "$outbox_dir/escalations.md" ]]; then
    cat "$outbox_dir/escalations.md" >> "$PWD/_memory/loop/ESCALATIONS.md"
  fi
  # Dispatch-prompt readback (D5/STORY-012): read before the outbox goes
  # away -- empty-safe (a manual/pre-STORY-012 outbox may lack the file).
  # Discarded with the outbox on a clean integration (that evidence is the
  # integrated commit itself); embedded verbatim in the quarantine marker
  # (D4) on every non-clean disposal path below.
  local dispatched_prompt=""
  if [[ -f "$outbox_dir/dispatch-prompt.md" ]]; then
    dispatched_prompt="$(cat "$outbox_dir/dispatch-prompt.md")"
  fi
  _loop_dossier_capture_attempt "$s" "$outbox_dir"
  # Copy-aside for integrator step 3b: direct children of <outbox>/memory/
  # only, into a per-slot mktemp dir (same pattern as the outbox itself).
  shopt -s nullglob
  local _mem_props=( "$outbox_dir"/memory/*.md )
  shopt -u nullglob
  if (( ${#_mem_props[@]} > 0 )); then
    local _aside _mp _aside_ok=1
    _aside="$(mktemp -d "${TMPDIR:-/tmp}/loop-memory-aside.XXXXXX")" || _aside=""
    if [[ -z "$_aside" ]]; then
      echo "!!! memory proposal copy-aside failed: mktemp failed" >&2
    else
      slot_memory_aside[s]="$_aside"
      for _mp in "${_mem_props[@]}"; do
        [[ -f "$_mp" ]] || continue
        if ! cp "$_mp" "${_aside}/$(basename "$_mp")"; then
          echo "!!! memory proposal copy-aside failed: cp failed" >&2
          _aside_ok=0
          break
        fi
      done
      if (( _aside_ok == 0 )); then
        rm -rf "$_aside"
        slot_memory_aside[s]=""
      fi
    fi
  fi
  rm -rf "$outbox_dir"

  # --- Integrator step 4: memory size gates, driver-side, AFTER appends
  # (§6.3 :685-689's single-writer compaction rule). Loud deferral notes
  # ONLY -- the driver never rewrites prose itself: "merge duplicates,
  # summarize older entries" / "move RESOLVED entries" need semantic
  # evaluation a shell function cannot honestly perform. The driver enforces
  # the single-writer HALF it can (slots never compact); the compaction/
  # archival rewrite itself is deferred to the next MANUAL (non-driver-
  # dispatched) iteration, whose skill text keeps the gates. 15/20 KB read
  # as the binary (KiB) convention, matching typical file-size tooling.
  local sz
  if [[ -f "$PWD/_memory/loop/LEARNINGS.md" ]]; then
    sz="$(wc -c < "$PWD/_memory/loop/LEARNINGS.md" | tr -d '[:space:]')"
    if (( sz >= 15360 )); then
      echo "!!! _memory/loop/LEARNINGS.md is >= 15KB ($sz bytes) -- compaction deferred to the next MANUAL iteration; automated prose compaction is out of the driver's competence (design §6.3 :685-689 single-writer rule -- the driver IS the single writer, but semantic rewriting is not)" >&2
    fi
  fi
  if [[ -f "$PWD/_memory/loop/ESCALATIONS.md" ]]; then
    sz="$(wc -c < "$PWD/_memory/loop/ESCALATIONS.md" | tr -d '[:space:]')"
    if (( sz >= 20480 )); then
      echo "!!! _memory/loop/ESCALATIONS.md is >= 20KB ($sz bytes) -- archival (move RESOLVED entries) deferred to the next MANUAL iteration; same single-writer-competence limit as LEARNINGS above" >&2
    fi
  fi

  # Circuit breaker 0: protected paths — the loop must never modify its own
  # machinery. Evaluated over the slot's own head_before..HEAD (its worktree
  # at LOOP_WORKTREE=1, the main tree at 0 — today's behavior); run-fatal,
  # meaning preserved. Global integrity failure (design §5): kills every
  # OTHER active slot's child before exiting so exit 4 never leaves an
  # orphaned background process behind.
  _loop_reap_diff_stats "$tree" "$head_before"
  _loop_dossier_capture_diffstat "$s" "$tree" "$head_before"
  if ! git -C "$tree" diff --quiet "$head_before" HEAD -- "${PROTECTED_PATHS[@]}" 2>/dev/null; then
    echo "!!! protected-path modification detected in slot $s — reverting iteration and stopping" >&2
    git -C "$tree" reset --hard "$head_before"
    if (( WORKTREE == 1 )); then
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
    fi
    _loop_ledger_append "$s" "protected"
    _loop_dossier_record_if_needed "$s" "protected" "$reap_set_passes"
    _loop_kill_other_slots "$s"
    exit 4
  fi

  # DRIVER-owned HEAD capture, after reap.
  local head_after
  head_after="$(git -C "$tree" rev-parse HEAD)"

  # retired_this_reap replaces the old cb_disposition/cb_exit deferred-exit
  # pair (D2/STORY-012, goal-judge fix 5): CB1/CB2 no longer exit AT ALL --
  # they RETIRE the slot (slot_retired[s]=1, no un-retire path) and let this
  # reap's own disposal (integrate-or-quarantine, below) run first, exactly
  # as today's deferred-exit ordering did (record -> sentinel -> CB0 -> CB1
  # -> CB2 -> disposal, unchanged). The flag's only remaining job is gating
  # CB2 and the abnormal test so a CB1-retiring reap is never
  # double-evaluated by CB2 and never double-counted as abnormal (INVARIANT:
  # a CB1-retiring reap never sets slot_retire_reason=cb2). Every literal
  # exit statement this used to gate now lives in _loop_aggregate_exit,
  # below the main loop.
  local retired_this_reap=0

  # Circuit breaker 1: no new commit for 3 consecutive iterations (per-slot
  # counter, unchanged threshold). RETIRES the slot (D2) instead of ending
  # the run -- other slots keep going; FILL skips a retired slot forever.
  # CB1 carve-out (amended scope): a rate-limited pass never counts against this
  # counter — the breaker owns recovery for it instead. Non-rate-limited no-commit
  # passes increment no_progress exactly as before.
  if [[ "$head_after" == "$head_before" ]]; then
    if (( detected == 1 )) && (( _loop_reap_timeout == 0 )); then
      echo "rate-limited pass — CB1 exempt (breaker owns it)"
    else
      slot_no_progress[s]=$(( slot_no_progress[s] + 1 ))
      echo "--- no progress (${slot_no_progress[s]}/3)"
      if (( slot_no_progress[s] >= 3 )); then
        echo "!!! circuit breaker: 3 iterations without a commit — slot $s retired (not refilled)" >&2
        slot_retired[s]=1
        slot_retire_reason[s]="cb1"
        retired_this_reap=1
      fi
    fi
  else
    slot_no_progress[s]=0
  fi

  # Circuit breaker 2: same failure signature 5 times in a row (per-slot
  # counter, thresholds unchanged; CB2's signature reads the same output
  # variable the driver already captured above). Skipped entirely once CB1
  # has already retired this slot this reap — matches the original
  # ordering, where CB1's disposition would have prevented this code from
  # ever running (INVARIANT: a CB1-retiring reap never sets
  # slot_retire_reason=cb2). RETIRES the slot (D2) instead of ending the run.
  if (( retired_this_reap == 0 )) && (( status != 0 )); then
    local error_sig
    error_sig="$(printf '%s' "$output" | tail -n 5 | sha256sum | cut -d' ' -f1)"
    if [[ "$error_sig" == "${slot_last_error_sig[s]}" ]]; then
      slot_same_error[s]=$(( slot_same_error[s] + 1 ))
      if (( slot_same_error[s] >= 5 )); then
        echo "!!! circuit breaker: same error 5 times — slot $s retired (not refilled)" >&2
        slot_retired[s]=1
        slot_retire_reason[s]="cb2"
        retired_this_reap=1
      fi
    else
      slot_same_error[s]=1
      slot_last_error_sig[s]="$error_sig"
    fi
  elif (( retired_this_reap == 0 )); then
    slot_same_error[s]=0
    slot_last_error_sig[s]=""
  fi

  # --- slot disposal: quarantine-lite (mismatch / tamper / abnormal / subset
  # violation) vs normal integration -- flag=1 only; flag=0 has no
  # worktree/branch to act on (main tree already carries whatever the slot
  # committed, today's unchanged behavior).
  local slot_did_integrate=0 ledger_abnormal=0 final_outcome
  if (( WORKTREE == 1 )); then
    # dirty_paths capture (D4/STORY-012): the porcelain text itself, not just
    # the boolean it also feeds -- flattened to one line for the quarantine
    # marker's `dirty_paths:` field (`none` when clean, the D4 accepted-loss
    # mitigation for the dirty-abnormal path's `--force` worktree removal).
    # Captured BEFORE any removal below (order pinned: capture, then act).
    local porcelain
    porcelain="$(git -C "$tree" status --porcelain 2>/dev/null)"
    local dirty=0
    if [[ -n "$porcelain" ]]; then
      dirty=1
    fi
    local dirty_paths_flat="none"
    if (( dirty == 1 )); then
      dirty_paths_flat="${porcelain//$'\n'/; }"
    fi
    local abnormal=0
    # Abnormal slot exit (quarantine-lite, pinned): a nonzero CLI status that
    # did NOT retire this slot this reap (CB1/CB2 retirement, D2), OR a
    # dirty worktree left behind either way. Quarantine markers (D4) now
    # ship on this path (and the mismatch/subset paths below) -- see
    # _loop_write_quarantine_marker.
    if (( status != 0 )) && (( retired_this_reap == 0 )); then
      abnormal=1
    fi
    if (( dirty == 1 )); then
      abnormal=1
    fi
    ledger_abnormal=$abnormal

    if (( mismatch == 1 )); then
      echo "!!! slot $s: ITERATION-mismatch — quarantine-lite: NOT integrating; retaining branch '$branch' for inspection ($tree)" >&2
      _loop_write_quarantine_marker "$story" "$s" "$branch" "$status" "mismatch" "$dirty_paths_flat" "$dispatched_prompt"
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
      retained_branches+=("$branch")
    elif [[ "$_loop_tamper_status" == "fail" ]]; then
      echo "!!! slot $s: test tamper detected — quarantine-lite, not integrated: $_loop_tamper_reasons" >&2
      _loop_write_quarantine_marker "$story" "$s" "$branch" "$status" "tamper" "$dirty_paths_flat" "$dispatched_prompt"
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
      retained_branches+=("$branch")
    elif (( abnormal == 1 )); then
      echo "!!! slot $s exited abnormally (status=$status dirty=$dirty) — quarantine-lite: NOT integrating; retaining branch '$branch' for inspection ($tree)" >&2
      _loop_write_quarantine_marker "$story" "$s" "$branch" "$status" "abnormal" "$dirty_paths_flat" "$dispatched_prompt"
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
      retained_branches+=("$branch")
    elif [[ -n "$subset_bad" ]]; then
      # Integrator step 5: PRE-MERGE subset check -- the branch's actual
      # changed paths must be a subset of the story's declared writes:
      # (same normalization as admission; computed early, above, so the
      # backlog-transition skip and this disposal agree on one result
      # without a second `git diff`). Absent/empty writes: has no declared
      # bound to audit against -- admission's runs-alone rule already
      # prevented any conflict for it, so the check is skipped there
      # rather than manufacturing a spurious violation.
      echo "!!! slot $s: branch '$branch' touched paths outside its declared writes: (quarantine-lite, not integrated): $subset_bad" >&2
      _loop_write_quarantine_marker "$story" "$s" "$branch" "$status" "subset" "$dirty_paths_flat" "$dispatched_prompt"
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
      retained_branches+=("$branch")
    else
      _loop_integrate_slot "$tree" "$branch" "$s"
      slot_did_integrate=1
    fi
  else
    if (( status != 0 )) && (( retired_this_reap == 0 )); then
      ledger_abnormal=1
    fi
  fi

  if (( _loop_reap_timeout == 1 )); then
    final_outcome="timeout"
  elif [[ "$_loop_tamper_status" == "fail" ]]; then
    final_outcome="tamper"
  elif (( mismatch == 1 )); then
    final_outcome="mismatch"
  elif (( ledger_abnormal == 1 )); then
    final_outcome="abnormal"
  elif [[ -n "$subset_bad" ]]; then
    final_outcome="subset"
  else
    case "$iter_verdict" in
      passed) final_outcome="passed" ;;
      blocked) final_outcome="blocked" ;;
      failed) final_outcome="failed" ;;
      *) final_outcome="failed" ;;
    esac
  fi
  _loop_ledger_append "$s" "$final_outcome"
  _loop_dossier_record_if_needed "$s" "$final_outcome" "$reap_set_passes"

  # --- Integrator step 3b: memory proposals from the copy-aside dir. Runs at
  # the END of reap, after CB0 (CB0 exits first — never reached there) and
  # disposal. Gate: no ITERATION-mismatch, no subset/tamper quarantine, and at
  # LOOP_WORKTREE=1 the branch was integrated (not quarantined). Any verdict
  # qualifies, including failed. Never changes exit code, backlog, or breaker.
  local run_memory_3b=0
  if (( mismatch == 0 )) && [[ -z "$subset_bad" ]] && [[ "$_loop_tamper_status" != "fail" ]]; then
    if (( WORKTREE == 0 )) || (( slot_did_integrate == 1 )); then
      run_memory_3b=1
    fi
  fi
  if (( run_memory_3b == 1 )) && [[ -n "${slot_memory_aside[s]:-}" ]]; then
    _loop_integrate_memory_proposals "$s" "$story" "${slot_memory_aside[s]}"
  fi
  _loop_memory_aside_cleanup_slot "$s"
}

# _loop_all_retired -- exit 0 (true) iff every slot 0..EFFECTIVE_SLOTS-1 is
# retired. Used only to WIDEN the in-loop terminal's trigger condition
# (goal-pinned): filled_this_round==0 already holds whenever every slot is
# retired (FILL skips a retired slot, so it can never set
# filled_this_round=1), but this makes the "every slot stopped progressing"
# trigger the funnel's rows 3/2 depend on an explicit, named check rather
# than an emergent property of the FILL skip.
_loop_all_retired() {
  local s
  for ((s = 0; s < EFFECTIVE_SLOTS; s++)); do
    if (( slot_retired[s] == 0 )); then
      return 1
    fi
  done
  return 0
}

# _loop_aggregate_exit <context> -- THE single driver-level exit-aggregation
# funnel (D3, goal-judge fix 1): every terminal literal `exit N` statement
# EXCEPT CB0's `exit 4` (above, short-circuits the table), the six loud
# `exit 5` stops (five inline sites plus setup-failure helper `_loop_setup_fail`),
# and lint mode's literal `exit 0` / `exit 1` (in `_loop_run_lint`, outside the
# run funnel) lives HERE. Evaluated strictly TOP-DOWN on every call: rows
# 3/2 (all-retired) BEFORE rows 0/1 (drained/quarantine) -- the two-gate
# form (checking drained-vs-survivor first, all-retired second) is
# forbidden, because it can report a lying exit 0/1 on the exact dispatch
# where MAX_ITER exhaustion coincides with the last slot's retirement
# (micro-test (h)). <context> is "in_loop" or "bottom" -- the ONLY thing it
# affects is which banner prints on the clean-drained outcome (in_loop keeps
# today's "no eligible stories" banner + refused-ids line; bottom prints
# P5); every other outcome (all-retired 3/2, drained-with-quarantine 1,
# survivor-remains 1) is call-site-independent. Both callers invoke this
# ONLY at active_slots==0, so there are no in-flight claims to bias the
# eligibility re-check below -- a survivor found here is genuine remaining
# work, not a transient admission conflict (in practice, unreachable from
# the in_loop call site: active==0 there already implies no admission
# conflicts, so a genuine survivor would have been filled instead of
# reaching this call at all -- see the in-loop call site's comment).
_loop_aggregate_exit() {
  local context="$1" s all_retired=1 any_cb2=0

  for ((s = 0; s < EFFECTIVE_SLOTS; s++)); do
    if (( slot_retired[s] == 0 )); then
      all_retired=0
    elif [[ "${slot_retire_reason[s]}" == "cb2" ]]; then
      any_cb2=1
    fi
  done

  # Rows 3/2: all-retired. 3-vs-2 precedence from retirement reasons alone
  # (D3): ANY cb2 retirement anywhere in the lineage wins over an all-cb1
  # run, so a lone slot that committed earlier and only later tripped CB2
  # still exits 3, exactly as N=1 always has.
  if (( all_retired == 1 )); then
    echo "!!! all slots retired — stopping" >&2
    if (( any_cb2 == 1 )); then
      exit 3
    fi
    exit 2
  fi

  # Rows 0/1: re-check eligibility (§7.1(b)(ii), the driver's own re-scan --
  # strictly stronger than trusting a slot's advisory sentinel).
  SELECTED_ID=""
  if [[ ! -r "$BACKLOG_FILE" ]]; then
    # A backlog readable at the last FILL gate and unreadable now was destroyed
    # mid-run: the SAME setup failure _loop_fill_slot's gate catches, and the
    # contract block above names it an exit-5 cause. Only the never-dispatched
    # degenerate case (MAX_ITER=0, where FILL's gate never ran) stays quiet --
    # nothing ran, so nothing can have broken.
    if (( dispatched > 0 )); then
      echo "!!! $BACKLOG_FILE is missing or unreadable -- cannot confirm completion (setup failure)" >&2
      exit 5
    fi
  else
    _loop_select_story || true
  fi
  if [[ -z "$SELECTED_ID" ]]; then
    # No survivor. §7.1(b)(iii)/D1: exit 0 is gated on zero quarantined
    # branches this run -- a quarantine-looped-to-exhaustion story must
    # never report a lying "backlog complete".
    if (( ${#retained_branches[@]} > 0 )); then
      echo "=== no eligible stories remain, but quarantined branches were retained this run — exiting 1 (inspect before trusting the backlog) ==="
      exit 1
    fi
    if [[ "$context" == "bottom" ]]; then
      echo "=== max iterations reached and no eligible stories remain — backlog complete ==="
    else
      echo "=== no eligible stories remain -- exiting ==="
      if (( ${#refused_ids[@]} > 0 )); then
        echo "=== protected-path-refused this run (never dispatched): ${refused_ids[*]} ==="
      fi
    fi
    exit 0
  fi

  # Survivor remains: MAX_ITER exhausted with eligible work still pending.
  if (( _loop_run_budget_stopped == 1 )); then
    echo "=== run budget reached -- exiting ==="
    exit 1
  fi
  echo "=== max iterations ($MAX_ITER) reached; backlog not complete ==="
  exit 1
}

if (( _loop_lint_mode == 1 )); then
  _loop_run_lint "$_lint_backlog_path"
fi

# =============================================================================
# Main loop: fill every available slot -> poll ALL active slots (kill -0
# sweep, bash-3.2, no `wait -n`) -> reap each finished slot (in slot order)
# -> integrate (inside reap, above) -> refill. MAX_ITER counts total
# dispatches across slots (010 semantics preserved); at EFFECTIVE_SLOTS=1
# (the default-flags / LOOP_WORKTREE=0 path) this degenerates to exactly
# today's serial one-dispatch-at-a-time behavior.
# =============================================================================
while (( dispatched < MAX_ITER )) || (( active_slots > 0 )); do
  echo "=== fill round: dispatched=$dispatched/$MAX_ITER active=$active_slots $(date -Is) ==="

  # --- FILL ------------------------------------------------------------------
  filled_this_round=0
  for ((SLOT = 0; SLOT < EFFECTIVE_SLOTS; SLOT++)); do
    if [[ "${slot_state[SLOT]}" == "running" ]] || (( slot_retired[SLOT] == 1 )); then
      continue
    fi
    if (( dispatched >= MAX_ITER )); then
      break   # no capacity left this run -- true for every remaining idle slot too
    fi
    _loop_fill_slot "$SLOT"
    if (( FILL_OK == 1 )); then
      dispatched=$((dispatched + 1))
      filled_this_round=1
    else
      # Nothing eligible right now: _loop_select_story is a pure function of
      # the backlog + the CURRENT claim table, and neither changed since the
      # last idle slot's (failed) attempt in this SAME round -- trying
      # another idle slot would recompute the identical empty result.
      break
    fi
  done

  # No eligible story survived selection this round AND nothing is still
  # running (OR every slot has retired -- _loop_all_retired below, an
  # explicit widening of the same trigger) -> hand off to the D3
  # aggregation funnel, which owns every literal exit statement from here
  # down (the skill's <promise>COMPLETE</promise> branch remains for MANUAL
  # invocation only). Rows 3/2 (all-retired) evaluate before rows 0/1
  # (drained/quarantine) inside the funnel -- the refused-story visibility
  # (cycle-1 fix 10) and the drained-with-quarantine gate (D1) both live
  # there now, not here.
  if (( active_slots == 0 )) && { (( filled_this_round == 0 )) || _loop_all_retired; }; then
    _loop_aggregate_exit "in_loop"
  fi

  # --- POLL --------------------------------------------------------------
  # Supervision: a `kill -0` poll loop over every RUNNING slot -- the
  # portable bash-3.2-floor primitive (`wait -n` needs bash 4.3+, which the
  # kit does not require anywhere else either). `kill -0` only tests whether
  # a signal COULD be delivered; a child that has already exited but not
  # yet been collected (a zombie) still answers it, so `wait` in the reap
  # step below is what actually collects the real status. Trivially
  # exercised at EFFECTIVE_SLOTS=1 (one pid to sweep) -- N>1 iterates more
  # pids here without restructuring this shape.
  while :; do
    any_done=0
    for ((SLOT = 0; SLOT < EFFECTIVE_SLOTS; SLOT++)); do
      if [[ "${slot_state[SLOT]}" != "running" ]]; then
        continue
      fi
      if ! kill -0 "${slot_pid[SLOT]}" 2>/dev/null; then
        any_done=1
      fi
    done
    if (( any_done == 1 )); then
      break
    fi
    sleep 0.2
  done

  # --- REAP (integrator runs inside _loop_reap_slot) ------------------------
  # Reap order = slot index order = integration order (outbox appends and
  # the closing summary both inherit this ordering).
  for ((SLOT = 0; SLOT < EFFECTIVE_SLOTS; SLOT++)); do
    if [[ "${slot_state[SLOT]}" != "running" ]]; then
      continue
    fi
    if kill -0 "${slot_pid[SLOT]}" 2>/dev/null; then
      continue   # still running -- not one of this round's finishers
    fi
    _loop_reap_slot "$SLOT"
  done

  # --- REFILL: loop back to FILL at the top ---------------------------------
done

# Bottom (MAX_ITER-exhausted) terminal: calls the SAME D3 aggregation funnel
# as the in-loop terminal above -- this is what closes the cycle-1 blocker
# (a slot retiring on the exact dispatch that also exhausts MAX_ITER must
# still land in rows 3/2, never fall through to a lying exit 0/1). Every
# literal exit statement, and the banner for each of its outcomes, lives
# inside the funnel. (Retained-branches summary, if any, is printed by the
# _loop_report_retained EXIT trap installed above -- it fires here too,
# after the funnel's exit statement.)
_loop_aggregate_exit "bottom"
