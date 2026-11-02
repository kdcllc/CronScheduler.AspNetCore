#!/usr/bin/env bash
# Model circuit breaker for the {{PROJECT_NAME}} autonomous loop — CLOSED/OPEN/
# HALF-OPEN state machine that degrades to cheaper models on rate limits and
# self-heals. Sourced by the loop driver (`loop.sh`); never executed directly.
#
# Cooldown threshold: 600s (OPEN -> HALF-OPEN eligible after 600s elapsed).
# Recovery threshold: HALF-OPEN closes at exactly 2 consecutive successes.
# Upward probe: after a rate-limit fallback (CLOSED), schedule a probe of
# chain[0] — first delay 1800 s, doubling on each failed probe with an 1800 s
# floor and 14400 s cap; a successful probe stays on chain[0]; a failed probe
# restores the pre-probe model (preProbeIndex).
#
# State schema (flat JSON, one key per line — never nested, never minified/reflowed;
# this script writes the following thirteen keys):
#   {
#   "state": "CLOSED"|"OPEN"|"HALF-OPEN",
#   "chain": "<comma-separated model chain, first = preferred>",
#   "fallbackIndex": <int, 0-based index of currentModel within chain — at chain
#     end the index stays put (pointing at the last entry) while currentModel
#     empties (omit-the-pin), so the two fields diverge by design>,
#   "currentModel": "<model id, or \"\" = omit the model flag/pin>",
#   "cooldownSeconds": 600,
#   "openedAt": <epoch seconds when OPEN was (re)entered, or 0>,
#   "halfOpenSuccesses": <int, consecutive successes while HALF-OPEN>,
#   "totalFallbacks": <int, lifetime>,
#   "totalRecoveries": <int, lifetime>,
#   "probeAfter": <epoch seconds when the next probe is due, 0 = none scheduled>,
#   "probeBackoff": <seconds, 0 = not degraded / reset>,
#   "probing": <0|1, 1 while a probe of the preferred model is in HALF-OPEN>,
#   "preProbeIndex": <non-negative int, fallbackIndex when the probe started;
#     meaningful only while probing == 1, else 0>
#   }
# NOTE: there is no `consecutiveFailures` key — it was a dead key in the original
# design note and is intentionally dropped from this schema.
#
# `chain` is normally seeded by the driver from the chain configured at install
# time (the LOOP_MODEL_CHAIN placeholder; see models.map.md's "Loop fallback
# chain" row) — this file never reads that token itself; the chain always
# arrives as a plain argument.
#
# Zero runtime deps: no jq/python/other JSON library. Parsing and persistence rely
# only on bash builtins plus grep (line presence), mv (atomic rename on write),
# sleep (torn-read retry backoff), and date — the latter only as breaker_load's
# default-parameter fallback when the caller does not inject a `now` — never
# `eval`, never `source`s the state file — because the flat, one-key-per-line
# layout above is simple enough that a real JSON parser buys nothing but a new
# dependency. This also means the state file is read as inert data: its bytes are
# never treated as code, so a corrupted or adversarially-edited file can only fail
# validation, not execute anything.
#
# Testability: transition logic (breaker_should_skip, breaker_record) takes
# timestamps as parameters — no wall-clock reads inside any transition logic.
# breaker_load's fail-safe seed is the one exception at the API boundary: its
# third parameter, `now`, is OPTIONAL and defaults to a wall-clock read
# (`date +%s`) only when the caller does not inject one, so every existing call
# site stays valid under `set -u` and the harness can still inject a timestamp for
# determinism. Wall-clock anomaly guard: the remaining-cooldown value is CLAMPED to
# [0, cooldownSeconds] so a system clock that jumps backward or forward can never
# produce a negative or absurdly long skip.
#
# Sourcing this file has zero side effects: it only defines functions.

# --- internal helpers (leading underscore; not part of the pinned API) -----------

# _breaker_get <file> <key> -> prints the raw value for a flat-JSON key, or ""
# if the key line is absent. Strips the surrounding quotes/comma for string values;
# numeric values pass through unquoted.
_breaker_get() {
  local file="$1" key="$2" line value
  line="$(grep -m1 "\"${key}\":" "$file" 2>/dev/null)" || true
  [[ -z "$line" ]] && { printf '%s' ""; return 0; }
  value="${line#*:}"
  # trim leading/trailing whitespace (guaranteed progress each iteration — handles
  # space/tab/CR/LF/VT/FF on either end; strips leading then trailing whitespace)
  while [[ -n "$value" && "$value" == [[:space:]]* ]]; do value="${value:1}"; done
  while [[ -n "$value" && "$value" == *[[:space:]] ]]; do value="${value%?}"; done
  value="${value%,}"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

# _breaker_valid_fields <file> -> return 0 iff every required key is present and
# every typed field parses (state is one of the three enum values; numeric fields
# are numeric). This is everything _breaker_valid checked before the terminator
# condition below was added; split out so breaker_load can tell a torn read
# (fields fine, terminator missing) apart from a genuinely invalid one (some
# field itself doesn't parse) — the two get different retry behavior.
_breaker_valid_fields() {
  local file="$1" key
  for key in state chain fallbackIndex currentModel cooldownSeconds openedAt \
             halfOpenSuccesses totalFallbacks totalRecoveries; do
    grep -q "\"${key}\":" "$file" 2>/dev/null || return 1
  done
  local state idx cooldown opened half fb rec
  state="$(_breaker_get "$file" state)"
  case "$state" in
    CLOSED|OPEN|HALF-OPEN) ;;
    *) return 1 ;;
  esac
  idx="$(_breaker_get "$file" fallbackIndex)"; [[ "$idx" =~ ^[0-9]+$ ]] || return 1
  cooldown="$(_breaker_get "$file" cooldownSeconds)"; [[ "$cooldown" =~ ^[0-9]+$ ]] || return 1
  opened="$(_breaker_get "$file" openedAt)"; [[ "$opened" =~ ^-?[0-9]+$ ]] || return 1
  half="$(_breaker_get "$file" halfOpenSuccesses)"; [[ "$half" =~ ^[0-9]+$ ]] || return 1
  fb="$(_breaker_get "$file" totalFallbacks)"; [[ "$fb" =~ ^[0-9]+$ ]] || return 1
  rec="$(_breaker_get "$file" totalRecoveries)"; [[ "$rec" =~ ^[0-9]+$ ]] || return 1
  local opt
  if grep -q '"probeAfter":' "$file" 2>/dev/null; then
    opt="$(_breaker_get "$file" probeAfter)"; [[ "$opt" =~ ^[0-9]+$ ]] || return 1
  fi
  if grep -q '"probeBackoff":' "$file" 2>/dev/null; then
    opt="$(_breaker_get "$file" probeBackoff)"; [[ "$opt" =~ ^[0-9]+$ ]] || return 1
  fi
  if grep -q '"probing":' "$file" 2>/dev/null; then
    opt="$(_breaker_get "$file" probing)"; [[ "$opt" == "0" || "$opt" == "1" ]] || return 1
  fi
  if grep -q '"preProbeIndex":' "$file" 2>/dev/null; then
    opt="$(_breaker_get "$file" preProbeIndex)"; [[ "$opt" =~ ^[0-9]+$ ]] || return 1
  fi
  return 0
}

# _breaker_terminator_ok <file> -> return 0 iff the file's final non-empty line is
# exactly `}` (the schema's terminator, breaker.sh:117), comparing AFTER stripping
# a trailing CR so a CRLF-normalized but otherwise valid file still passes
# (harness 11c is the regression this guards). tail-equivalent only, via a plain
# bash read loop — no new runtime dep. A reader that fails only this check knows
# it caught a write mid-flight (torn), not a corrupt file.
_breaker_terminator_ok() {
  local file="$1" line last=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -n "$line" ]] && last="$line"
  done < "$file"
  [[ "$last" == "}" ]]
}

# _breaker_valid <file> -> return 0 iff _breaker_valid_fields passes AND the
# terminator line is intact. This is the "parseable" gate breaker_load uses to
# decide return-untouched vs retry-or-fail-safe.
_breaker_valid() {
  local file="$1"
  _breaker_valid_fields "$file" || return 1
  _breaker_terminator_ok "$file" || return 1
  return 0
}

# _breaker_write <file> <state> <chain> <idx> <model> <cooldown> <openedAt> <half>
#                <totalFallbacks> <totalRecoveries> [probeAfter] [probeBackoff]
#                [probing] [preProbeIndex]
# The ONE place that serializes the schema — every transition below funnels through
# this so the on-disk layout never drifts. Atomicity rationale: writes go to a
# sibling temp file first, then `mv -f` onto the target — POSIX rename(2) on the
# same filesystem is atomic, so a concurrent reader can never observe a
# zero-length or partially-written file (the torn-read race this story closes).
# The temp name is colon-free (templates/loop/SKILL.template.md:27).
_breaker_write() {
  local file="$1" state="$2" chain="$3" idx="$4" model="$5" cooldown="$6" \
        opened="$7" half="$8" fb="$9" rec="${10}" \
        probe_after="${11:-0}" probe_backoff="${12:-0}" probing="${13:-0}" \
        pre_probe="${14:-0}"
  local tmp="$file.tmp.$$"
  {
    printf '{\n'
    printf '"state": "%s",\n' "$state"
    printf '"chain": "%s",\n' "$chain"
    printf '"fallbackIndex": %s,\n' "$idx"
    printf '"currentModel": "%s",\n' "$model"
    printf '"cooldownSeconds": %s,\n' "$cooldown"
    printf '"openedAt": %s,\n' "$opened"
    printf '"halfOpenSuccesses": %s,\n' "$half"
    printf '"totalFallbacks": %s,\n' "$fb"
    printf '"totalRecoveries": %s,\n' "$rec"
    printf '"probeAfter": %s,\n' "$probe_after"
    printf '"probeBackoff": %s,\n' "$probe_backoff"
    printf '"probing": %s,\n' "$probing"
    printf '"preProbeIndex": %s\n' "$pre_probe"
    printf '}\n'
  } > "$tmp"
  mv -f "$tmp" "$file"
}

# _breaker_seed <file> <chain> -> writes a fresh CLOSED state seeded from <chain>.
# currentModel = first chain entry, or "" when the chain is empty.
_breaker_seed() {
  local file="$1" chain="$2" first=""
  [[ -n "$chain" ]] && first="${chain%%,*}"
  _breaker_write "$file" CLOSED "$chain" 0 "$first" 600 0 0 0 0
}

# _breaker_read_all <file> -> populates the _BRK_* scratch variables used by
# breaker_should_skip/breaker_record. Not namerefs (bash 3.2 on stock macOS has no
# `local -n`), so these are deliberately module-scoped globals under the _BRK_
# prefix — internal to this file, never part of the pinned API.
_breaker_read_all() {
  local file="$1"
  _BRK_STATE="$(_breaker_get "$file" state)"
  _BRK_CHAIN="$(_breaker_get "$file" chain)"
  _BRK_INDEX="$(_breaker_get "$file" fallbackIndex)"
  _BRK_MODEL="$(_breaker_get "$file" currentModel)"
  _BRK_COOLDOWN="$(_breaker_get "$file" cooldownSeconds)"
  _BRK_OPENED="$(_breaker_get "$file" openedAt)"
  _BRK_HALF="$(_breaker_get "$file" halfOpenSuccesses)"
  _BRK_FALLBACKS="$(_breaker_get "$file" totalFallbacks)"
  _BRK_RECOVERIES="$(_breaker_get "$file" totalRecoveries)"
  if grep -q '"probeAfter":' "$file" 2>/dev/null; then
    _BRK_PROBE_AFTER="$(_breaker_get "$file" probeAfter)"
  else
    _BRK_PROBE_AFTER=0
  fi
  if grep -q '"probeBackoff":' "$file" 2>/dev/null; then
    _BRK_PROBE_BACKOFF="$(_breaker_get "$file" probeBackoff)"
  else
    _BRK_PROBE_BACKOFF=0
  fi
  if grep -q '"probing":' "$file" 2>/dev/null; then
    _BRK_PROBING="$(_breaker_get "$file" probing)"
  else
    _BRK_PROBING=0
  fi
  if grep -q '"preProbeIndex":' "$file" 2>/dev/null; then
    _BRK_PRE_PROBE="$(_breaker_get "$file" preProbeIndex)"
  else
    _BRK_PRE_PROBE=0
  fi
}

# _breaker_advance_chain -> mutates _BRK_INDEX/_BRK_MODEL per the pinned rule:
# index++ (and currentModel = that entry) if a next entry exists, ELSE
# currentModel="" (chain-end reconciles with models.map's omit-the-pin rule).
# A further advance while already at chain-end computes the same false condition
# again, so currentModel simply stays "" — no special "exhausted" sentinel needed.
_breaker_advance_chain() {
  local -a entries=()
  if [[ -n "$_BRK_CHAIN" ]]; then
    IFS=',' read -r -a entries <<< "$_BRK_CHAIN"
  fi
  local n=${#entries[@]}
  if (( _BRK_INDEX + 1 < n )); then
    _BRK_INDEX=$(( _BRK_INDEX + 1 ))
    _BRK_MODEL="${entries[$_BRK_INDEX]}"
  else
    _BRK_MODEL=""
  fi
}

# _breaker_failsafe_open <file> <chain-arg> <now> -> seeds OPEN with
# openedAt=<now> and the full cooldown, carrying the COMPLETE field disposition
# (goal.md, cycle-1 MAJOR-4 fix): chain/fallbackIndex preserved if they
# individually parse, else <chain-arg>/0; currentModel preserved if it parses,
# else DERIVED as chain[fallbackIndex] (empty past chain end, per the
# omit-the-pin rule at breaker.sh:146-150 — never blindly chain[0], which would
# re-pin the just-rate-limited model and undo half the harm the inversion
# prevents); halfOpenSuccesses always resets to 0; totalFallbacks/totalRecoveries
# preserved if they parse, else 0. Called only from breaker_load's still-invalid
# branch below.
_breaker_failsafe_open() {
  local file="$1" chain_arg="$2" now="$3"
  local chain idx model fb rec
  local -a entries=()

  if grep -q '"chain":' "$file" 2>/dev/null; then
    chain="$(_breaker_get "$file" chain)"
  else
    chain="$chain_arg"
  fi

  idx="$(_breaker_get "$file" fallbackIndex)"
  [[ "$idx" =~ ^[0-9]+$ ]] || idx=0

  if grep -q '"currentModel":' "$file" 2>/dev/null; then
    model="$(_breaker_get "$file" currentModel)"
  else
    [[ -n "$chain" ]] && IFS=',' read -r -a entries <<< "$chain"
    if (( idx < ${#entries[@]} )); then
      model="${entries[$idx]}"
    else
      model=""
    fi
  fi

  fb="$(_breaker_get "$file" totalFallbacks)"
  [[ "$fb" =~ ^[0-9]+$ ]] || fb=0

  rec="$(_breaker_get "$file" totalRecoveries)"
  [[ "$rec" =~ ^[0-9]+$ ]] || rec=0

  local probe_after probe_backoff probing pre_probe
  probe_after="$(_breaker_get "$file" probeAfter)"
  [[ "$probe_after" =~ ^[0-9]+$ ]] || probe_after=0
  probe_backoff="$(_breaker_get "$file" probeBackoff)"
  [[ "$probe_backoff" =~ ^[0-9]+$ ]] || probe_backoff=0
  probing="$(_breaker_get "$file" probing)"
  [[ "$probing" == "0" || "$probing" == "1" ]] || probing=0
  pre_probe="$(_breaker_get "$file" preProbeIndex)"
  [[ "$pre_probe" =~ ^[0-9]+$ ]] || pre_probe=0

  _breaker_write "$file" OPEN "$chain" "$idx" "$model" 600 "$now" 0 "$fb" "$rec" \
    "$probe_after" "$probe_backoff" "$probing" "$pre_probe"
}

# --- pinned API --------------------------------------------------------------

# breaker_load <state-file> <chain> [now-epoch]
# `now` is OPTIONAL and defaults to `$(date +%s)` at the API boundary when the
# caller does not inject one — every existing call site (loop.sh, run.sh) stays
# valid under `set -u`, and the harness can still inject a timestamp.
# Three branches (design §3.2 part 3):
#   - file absent -> seed fresh CLOSED from <chain>, silently (unchanged).
#   - present but failing ONLY the terminator check (torn — a write caught
#     mid-flight) -> re-read up to 3 times with a ~50ms backoff (`sleep 0.05`);
#     a retry that becomes fully valid returns silently, nothing rewritten, no
#     warning.
#   - present and still invalid after that (or invalid for reasons beyond the
#     terminator, e.g. a dropped key -> no retry) -> FAIL SAFE, not fail
#     CLOSED-erasing: one stderr warning, then seed OPEN via
#     _breaker_failsafe_open (openedAt=<now>, full cooldown, complete
#     per-field-preserved-if-parse disposition). This inverts the one branch
#     that could weaken protection: a lost/torn read now costs one cooldown
#     instead of silently erasing one.
breaker_load() {
  local state_file="$1" chain="$2" now="${3:-$(date +%s)}"
  if [[ ! -f "$state_file" ]]; then
    _breaker_seed "$state_file" "$chain"
    return 0
  fi
  if _breaker_valid "$state_file"; then
    return 0
  fi
  if _breaker_valid_fields "$state_file"; then
    local attempt=0
    while (( attempt < 3 )); do
      sleep 0.05
      attempt=$(( attempt + 1 ))
      _breaker_valid "$state_file" && return 0
    done
  fi
  echo "breaker: $state_file is unreadable — failing SAFE to OPEN" >&2
  _breaker_failsafe_open "$state_file" "$chain" "$now"
}

# breaker_current_model <state-file> -> echoes currentModel (may be empty).
breaker_current_model() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo ""; return 0; }
  _breaker_get "$state_file" currentModel
  echo
}

# breaker_should_skip <state-file> <now-epoch>
# OPEN & cooldown not elapsed -> echo remaining seconds (clamped to
#   [0, cooldownSeconds]).
# OPEN & cooldown elapsed -> transition to HALF-OPEN (halfOpenSuccesses=0),
#   persist, echo 0.
# Any other state -> echo 0, no state change.
breaker_should_skip() {
  local state_file="$1" now="$2"
  _breaker_read_all "$state_file"

  if [[ "$_BRK_STATE" != "OPEN" ]]; then
    echo 0
    return 0
  fi

  local elapsed remaining
  elapsed=$(( now - _BRK_OPENED ))
  remaining=$(( _BRK_COOLDOWN - elapsed ))
  # Wall-clock anomaly guard: clamp to [0, cooldownSeconds].
  (( remaining < 0 )) && remaining=0
  (( remaining > _BRK_COOLDOWN )) && remaining=$_BRK_COOLDOWN

  if (( remaining > 0 )); then
    echo "$remaining"
    return 0
  fi

  _BRK_STATE="HALF-OPEN"
  _BRK_HALF=0
  _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
    "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" "$_BRK_FALLBACKS" \
    "$_BRK_RECOVERIES" "$_BRK_PROBE_AFTER" "$_BRK_PROBE_BACKOFF" "$_BRK_PROBING" \
    "$_BRK_PRE_PROBE"
  echo 0
}

# breaker_record <state-file> <rate-limited:0|1> <now-epoch>
# Transitions exactly per goal.md's exhaustive table:
#   CLOSED   + 0 -> no-op.
#   CLOSED   + 1 -> OPEN; advance chain; openedAt=now; totalFallbacks++.
#   HALF-OPEN+ 0 -> halfOpenSuccesses++; at exactly 2 -> CLOSED (reset
#                   halfOpenSuccesses/openedAt; totalRecoveries++).
#   HALF-OPEN+ 1 -> OPEN; advance chain; openedAt=now (reset).
#   OPEN     +any -> defensive path (normally unreachable under mechanism B):
#                   log a warning, then treat exactly as the HALF-OPEN input above.
breaker_record() {
  local state_file="$1" rate_limited="$2" now="$3"
  _breaker_read_all "$state_file"

  if [[ "$_BRK_STATE" == "OPEN" ]]; then
    echo "breaker: breaker_record called while OPEN (defensive path — mechanism B should make this unreachable); treating as HALF-OPEN input" >&2
    _BRK_STATE="HALF-OPEN"
  fi

  case "$_BRK_STATE" in
    CLOSED)
      if [[ "$rate_limited" == "1" ]]; then
        _breaker_advance_chain
        _BRK_STATE="OPEN"
        _BRK_OPENED="$now"
        _BRK_FALLBACKS=$(( _BRK_FALLBACKS + 1 ))
        (( _BRK_PROBE_BACKOFF == 0 )) && _BRK_PROBE_BACKOFF=1800
        _BRK_PROBE_AFTER=$(( now + _BRK_PROBE_BACKOFF ))
        _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
          "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" \
          "$_BRK_FALLBACKS" "$_BRK_RECOVERIES" "$_BRK_PROBE_AFTER" \
          "$_BRK_PROBE_BACKOFF" "$_BRK_PROBING" "$_BRK_PRE_PROBE"
      fi
      # CLOSED + success -> no-op: nothing written.
      ;;
    HALF-OPEN)
      if [[ "$rate_limited" == "1" ]]; then
        if [[ "$_BRK_PROBING" == "1" ]]; then
          _BRK_INDEX="$_BRK_PRE_PROBE"
          local -a entries=()
          if [[ -n "$_BRK_CHAIN" ]]; then
            IFS=',' read -r -a entries <<< "$_BRK_CHAIN"
          fi
          if (( _BRK_INDEX < ${#entries[@]} )); then
            _BRK_MODEL="${entries[$_BRK_INDEX]}"
          else
            _BRK_MODEL=""
          fi
          _BRK_STATE="OPEN"
          _BRK_OPENED="$now"
          _BRK_HALF=0
          local backoff="$_BRK_PROBE_BACKOFF"
          (( backoff < 1800 )) && backoff=1800
          backoff=$(( backoff * 2 ))
          (( backoff > 14400 )) && backoff=14400
          _BRK_PROBE_BACKOFF=$backoff
          _BRK_PROBE_AFTER=$(( now + backoff ))
          _BRK_PROBING=0
          _BRK_PRE_PROBE=0
        else
          _breaker_advance_chain
          _BRK_STATE="OPEN"
          _BRK_OPENED="$now"
        fi
        _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
          "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" \
          "$_BRK_FALLBACKS" "$_BRK_RECOVERIES" "$_BRK_PROBE_AFTER" \
          "$_BRK_PROBE_BACKOFF" "$_BRK_PROBING" "$_BRK_PRE_PROBE"
      else
        _BRK_HALF=$(( _BRK_HALF + 1 ))
        if (( _BRK_HALF == 2 )); then
          _BRK_STATE="CLOSED"
          _BRK_HALF=0
          _BRK_OPENED=0
          _BRK_RECOVERIES=$(( _BRK_RECOVERIES + 1 ))
          if [[ "$_BRK_PROBING" == "1" ]]; then
            _BRK_PROBING=0
            _BRK_PROBE_AFTER=0
            _BRK_PROBE_BACKOFF=0
            _BRK_PRE_PROBE=0
          fi
        fi
        _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
          "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" \
          "$_BRK_FALLBACKS" "$_BRK_RECOVERIES" "$_BRK_PROBE_AFTER" \
          "$_BRK_PROBE_BACKOFF" "$_BRK_PROBING" "$_BRK_PRE_PROBE"
      fi
      ;;
  esac
}

# breaker_probe <state-file> <now-epoch>
# Schedules or starts an upward probe of chain[0] while CLOSED at a fallback
# index. Timestamps are parameters only — no wall-clock reads here.
breaker_probe() {
  local state_file="$1" now="$2"
  _breaker_read_all "$state_file"

  if [[ "$_BRK_STATE" != "CLOSED" ]]; then
    return 0
  fi
  if (( _BRK_INDEX <= 0 )); then
    return 0
  fi
  if [[ "$_BRK_PROBING" != "0" ]]; then
    return 0
  fi

  if (( _BRK_PROBE_AFTER == 0 )); then
    (( _BRK_PROBE_BACKOFF == 0 )) && _BRK_PROBE_BACKOFF=1800
    _BRK_PROBE_AFTER=$(( now + _BRK_PROBE_BACKOFF ))
    _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
      "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" "$_BRK_FALLBACKS" \
      "$_BRK_RECOVERIES" "$_BRK_PROBE_AFTER" "$_BRK_PROBE_BACKOFF" "$_BRK_PROBING" \
      "$_BRK_PRE_PROBE"
    return 0
  fi

  if (( now < _BRK_PROBE_AFTER )); then
    return 0
  fi

  local -a entries=()
  if [[ -n "$_BRK_CHAIN" ]]; then
    IFS=',' read -r -a entries <<< "$_BRK_CHAIN"
  fi
  _BRK_PRE_PROBE="$_BRK_INDEX"
  _BRK_INDEX=0
  if (( ${#entries[@]} > 0 )); then
    _BRK_MODEL="${entries[0]}"
  else
    _BRK_MODEL=""
  fi
  _BRK_STATE="HALF-OPEN"
  _BRK_HALF=0
  _BRK_PROBING=1
  _breaker_write "$state_file" "$_BRK_STATE" "$_BRK_CHAIN" "$_BRK_INDEX" \
    "$_BRK_MODEL" "$_BRK_COOLDOWN" "$_BRK_OPENED" "$_BRK_HALF" "$_BRK_FALLBACKS" \
    "$_BRK_RECOVERIES" "$_BRK_PROBE_AFTER" "$_BRK_PROBE_BACKOFF" "$_BRK_PROBING" \
    "$_BRK_PRE_PROBE"
  echo "breaker: probing preferred model $_BRK_MODEL" >&2
}
