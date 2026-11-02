#!/usr/bin/env bash
# hook-log — metadata-only telemetry for agent stop hooks, plus a read-only summary of the log.
# Emitted single-copy to `_kit/hook-log.sh` (Windows: `_kit/hook-log.cmd` via bash-launcher.cmd).
#
#   hook-log.sh hook <claude|cursor> [--root DIR]
#     Read one stop-hook payload from stdin (Claude Code Stop / SubagentStop / StopFailure, Cursor
#     stop / subagentStop) and append one JSON line of metadata to
#     <root>/_memory/work/hooks/events.jsonl.
#
#   hook-log.sh summary [--root DIR]
#     Read events.1.jsonl then events.jsonl (missing files are fine) and print the event count,
#     counts by event, by harness/agent_type, by status and by model (one `  <count> <value>` line
#     each, sorted by value, null shown as `-`), and an `errors and aborts` section listing
#     `ts harness event agent_type status error` for every line whose status is error or aborted
#     (or `  none`; `error` is `-` when it is null or the line predates the field). When no line has
#     harness claude, a last `hint:` line says to check the Claude Code Stop hooks. Never writes.
#
#   hook-log.sh --help
#     Print this usage and exit 0.
#
# Root: --root DIR when given; else the parent of this script's directory (_kit/..), via
# `CDPATH= cd` and pwd -P (an exported CDPATH never changes the answer).
# Log: <root>/_memory/work/hooks/events.jsonl (gitignored with the rest of _memory/work/). Past the
# size cap the file is moved once to events.1.jsonl under a mkdir lock (hooks/.rotate.lock); an
# older events.1.jsonl is replaced, and a lock older than 10 minutes is treated as stale.
#
# Never steers: hook mode only observes. `hook cursor` prints exactly `{}` plus a newline on every
# path (logged, skipped, failed or malformed input) and `hook claude` prints nothing; both exit 0.
# The tool never emits a follow-up message, a block decision, a continue flag, a permission verdict
# or added context, so it cannot start or extend an agent loop. Errors are swallowed (fail open).
#
# Skipped without writing: AGENT_KIT_HOOK_LOG=0; empty stdin, stdin without a right brace, or stdin
# whose first non-whitespace character is not a left brace (a top-level array is never read);
# `hook claude` with a Cursor caller (CURSOR_PROJECT_DIR set, or the payload contains
# "cursor_version"); a hook_event_name outside Stop / SubagentStop / StopFailure (claude) or
# stop / subagentStop (cursor); a payload whose key is already in events.jsonl or events.1.jsonl;
# any write failure.
#
# Line fields, in this order (a field the payload lacks, or of the wrong type, is null):
#   ts            UTC YYYY-MM-DDTHH:MM:SSZ
#   harness       claude | cursor
#   event         hook_event_name
#   session       claude session_id | cursor conversation_id
#   generation    claude prompt_id | cursor generation_id
#   agent_id      claude agent_id
#   agent_type    claude agent_type | cursor subagent_type
#   status        cursor status | the literal "error" for a claude StopFailure
#   error         claude StopFailure `error` (rate_limit, overloaded, ...): a string that matches
#                 ^[a-z_]+$, else null; null for every other event
#   duration_ms, message_count, tool_call_count, loop_count   cursor numbers (digits only)
#   model         cursor model
#   modified_files   element count of the cursor modified_files array
#   key           first 16 hex of the SHA-256 of the raw stdin bytes (sha256sum or shasum -a 256);
#                 `c` + the cksum CRC when neither exists
# Only top-level keys are read. A key inside a string value or inside a nested object or array is
# never read.
# Never logged: task, description, summary, last_assistant_message, error_details, transcript paths,
# cwd, workspace_roots, user_email, permission_mode, background_tasks and session_crons — metadata
# only, no text or paths.
#
# Environment: AGENT_KIT_HOOK_LOG (0 = off; anything else = on) · AGENT_KIT_HOOK_LOG_MAX_BYTES
# (rotation cap, default 5242880; non-numeric = default) · HOOK_LOG_NOW (fixed ts, for tests).
#
# Exit codes: 0 ok (hook always exits 0 once its arguments parse, even on an unreadable root) ·
# 2 usage error (any mode) or unreadable root (summary).
#
# Bash 3.2+, LC_ALL=C. No runtime JSON dependency; writes only under <root>/_memory/work/hooks/.
set -u
export LC_ALL=C

usage() {
  printf '%s\n' 'usage: hook-log.sh hook <claude|cursor> [--root DIR] | hook-log.sh summary [--root DIR] | hook-log.sh --help'
}

die() { # <code> <message>
  printf 'hook-log: %s\n' "$2" >&2
  exit "$1"
}

DEFAULT_MAX_BYTES=5242880
LOG_SUBDIR='_memory/work/hooks'

# --- field extraction (stdin: raw payload; prints the finished log line, or nothing to skip) -----
# A one-pass tokenizer over the top-level object only: strings are scanned with their escapes
# neutralized, nested objects and arrays are skipped (except the element count of modified_files),
# and each wanted key is taken once, from depth 1. A payload whose first non-whitespace character
# is not a left brace is skipped. -v harness / ts / key come from the shell.
EXTRACT_AWK='
function elem() {
  if (inarr && arr_expect) { arr_count++; arr_expect = 0 }
}
function take(k, tok, tk,    s) {
  if (!(k in slot)) return
  s = slot[k]
  if (s in seen) return
  seen[s] = 1
  if (kind[k] == "S") {
    if (tk == "S") val[s] = tok
  } else if (kind[k] == "N") {
    if (tk == "L" && tok ~ /^[0-9]+$/) val[s] = tok
  } else if (kind[k] == "E") {
    if (tk == "S" && tok ~ /^"[a-z_]+"$/) val[s] = tok
  }
}
function start_nested(c,    s) {
  if (!(curkey in slot)) return
  s = slot[curkey]
  if (s in seen) return
  seen[s] = 1
  if (kind[curkey] == "A" && c == "[") { inarr = 1; arr_slot = s; arr_count = 0; arr_expect = 1 }
}
function find_quote(m, j, n,    p) {
  while (j <= n) {
    p = index(substr(m, j, 4096), "\"")
    if (p > 0) return j + p - 1
    j += 4096
  }
  return 0
}
function emit(name) {
  printf ",\"%s\":%s", name, (name in val) ? val[name] : "null"
}
BEGIN {
  depth = 0; done = 0; inarr = 0; state = ""; curkey = ""
  slot["hook_event_name"] = "event"; kind["hook_event_name"] = "S"
  if (harness == "claude") {
    slot["session_id"] = "session"; kind["session_id"] = "S"
    slot["prompt_id"] = "generation"; kind["prompt_id"] = "S"
    slot["agent_id"] = "agent_id"; kind["agent_id"] = "S"
    slot["agent_type"] = "agent_type"; kind["agent_type"] = "S"
    slot["error"] = "error"; kind["error"] = "E"
  } else {
    slot["conversation_id"] = "session"; kind["conversation_id"] = "S"
    slot["generation_id"] = "generation"; kind["generation_id"] = "S"
    slot["subagent_type"] = "agent_type"; kind["subagent_type"] = "S"
    slot["status"] = "status"; kind["status"] = "S"
    slot["duration_ms"] = "duration_ms"; kind["duration_ms"] = "N"
    slot["message_count"] = "message_count"; kind["message_count"] = "N"
    slot["tool_call_count"] = "tool_call_count"; kind["tool_call_count"] = "N"
    slot["loop_count"] = "loop_count"; kind["loop_count"] = "N"
    slot["model"] = "model"; kind["model"] = "S"
    slot["modified_files"] = "modified_files"; kind["modified_files"] = "A"
  }
}
{
  if (done) next
  l = $0
  m = l
  gsub(/\\./, "@@", m)
  n = length(l)
  i = 1
  while (i <= n) {
    c = substr(m, i, 1)
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (depth == 0) {
      if (c != "{") { done = 1; break }
      depth = 1; state = "key"
      i++
      continue
    }
    if (c == "\"") {
      e = find_quote(m, i + 1, n)
      if (e == 0) { i = n + 1; continue }
      tok = substr(l, i, e - i + 1)
      i = e + 1
      if (depth == 1) {
        if (state == "key") { curkey = substr(tok, 2, length(tok) - 2); state = "colon" }
        else if (state == "value") { take(curkey, tok, "S"); state = "comma" }
      } else if (depth == 2) {
        elem()
      }
      continue
    }
    if (c == "{" || c == "[") {
      if (depth == 1 && state == "value") start_nested(c)
      else if (depth == 2) elem()
      depth++
      i++
      continue
    }
    if (c == "}" || c == "]") {
      depth--
      i++
      if (depth <= 0) { done = 1; break }
      if (depth == 1) {
        if (inarr) { val[arr_slot] = arr_count; inarr = 0 }
        state = "comma"
      }
      continue
    }
    if (c == ",") {
      if (depth == 1) state = "key"
      else if (depth == 2 && inarr) arr_expect = 1
      i++
      continue
    }
    if (c == ":") {
      if (depth == 1 && state == "colon") state = "value"
      i++
      continue
    }
    j = i
    while (j <= n && index(" \t\r,}]", substr(m, j, 1)) == 0) j++
    if (j == i) j = i + 1
    tok = substr(l, i, j - i)
    i = j
    if (depth == 1 && state == "value") { take(curkey, tok, "L"); state = "comma" }
    else if (depth == 2) elem()
  }
}
END {
  ev = ("event" in val) ? val["event"] : ""
  if (harness == "claude") ok = (ev == "\"Stop\"" || ev == "\"SubagentStop\"" || ev == "\"StopFailure\"")
  else ok = (ev == "\"stop\"" || ev == "\"subagentStop\"")
  if (!ok) exit 0
  if (ev == "\"StopFailure\"") val["status"] = "\"error\""
  else delete val["error"]
  printf "{\"ts\":\"%s\",\"harness\":\"%s\",\"event\":%s", ts, harness, ev
  emit("session"); emit("generation"); emit("agent_id"); emit("agent_type"); emit("status")
  emit("error"); emit("duration_ms"); emit("message_count"); emit("tool_call_count"); emit("loop_count")
  emit("model"); emit("modified_files")
  printf ",\"key\":\"%s\"}\n", key
}
'

# --- summary (stdin: events text; prints `<section>\t<value>\t<count|text>` records for sort) -----
# Values come from our own fixed-format lines: a quote that ends a string is never preceded by a
# backslash pair that hides it, and an escaped quote inside a value never forms `"name":`, so a
# first match is safe.
SUMMARY_AWK='
function field(l, name,    p, v, j, n, c) {
  p = index(l, "\"" name "\":")
  if (p == 0) return "-"
  p += length(name) + 3
  if (substr(l, p, 1) == "\"") {
    n = length(l)
    j = p + 1
    while (j <= n) {
      c = substr(l, j, 1)
      if (c == "\\") { j += 2; continue }
      if (c == "\"") break
      j++
    }
    if (j > n) return "-"
    return substr(l, p + 1, j - p - 1)
  }
  v = substr(l, p)
  sub(/[,}].*$/, "", v)
  if (v == "" || v == "null") return "-"
  return v
}
BEGIN { total = 0; nerr = 0; nclaude = 0 }
{
  line = $0
  sub(/\r$/, "", line)
  if (substr(line, 1, 1) != "{") next
  total++
  ev = field(line, "event")
  h = field(line, "harness")
  at = field(line, "agent_type")
  st = field(line, "status")
  er = field(line, "error")
  md = field(line, "model")
  c1[ev]++
  c2[h "/" at]++
  c3[st]++
  c4[md]++
  if (h == "claude") nclaude++
  if (st == "error" || st == "aborted") {
    nerr++
    errs[nerr] = field(line, "ts") " " h " " ev " " at " " st " " er
  }
}
END {
  printf "0\t\t%d\n", total
  for (k in c1) printf "1\t%s\t%d\n", k, c1[k]
  for (k in c2) printf "2\t%s\t%d\n", k, c2[k]
  for (k in c3) printf "3\t%s\t%d\n", k, c3[k]
  for (k in c4) printf "4\t%s\t%d\n", k, c4[k]
  for (k = 1; k <= nerr; k++) printf "5\t%06d\t%s\n", k, errs[k]
  printf "6\t\t%d\n", nclaude
}
'

# Formats the sorted records into the report. The events path arrives in the environment
# (HOOK_LOG_EVENTS_PATH): awk -v would turn a backslash in the path into an escape sequence.
SUMMARY_FORMAT_AWK='
BEGIN {
  FS = "\t"
  path = ENVIRON["HOOK_LOG_EVENTS_PATH"]
  title[1] = "by event"
  title[2] = "by harness/agent_type"
  title[3] = "by status"
  title[4] = "by model"
  title[5] = "errors and aborts"
  last = 0; total = 0; nclaude = 0
}
$1 == 0 {
  total = $3 + 0
  printf "hook-log: %d events (%s)\n", total, path
  next
}
$1 == 6 { nclaude = $3 + 0; next }
total == 0 { next }
{
  while (last < $1 - 1) { last++; print title[last]; if (last == 5) print "  none" }
  if ($1 != last) { last = $1; print title[last] }
  if ($1 == 5) printf "  %s\n", $3
  else printf "  %d %s\n", $3, $2
}
END {
  if (total > 0) {
    while (last < 5) { last++; print title[last]; if (last == 5) print "  none" }
  }
  if (nclaude == 0) {
    print "hint: no claude events — if Claude Code is in use, check that the Claude Code project settings file has the hook-log Stop hooks (merge the emit warning snippet)"
  }
}
'

# --- hook helpers ----------------------------------------------------------------------------

now_ts() {
  local v="${HOOK_LOG_NOW:-}"
  if [ -n "$v" ]; then
    case "$v" in
      *[!0-9A-Za-z:._+-]*) ;;
      *) printf '%s' "$v"; return 0 ;;
    esac
  fi
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

compute_key() { # <payload> → key on stdout; 1 when no checksum tool works
  local h="" c=""
  if command -v sha256sum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | sha256sum 2>/dev/null)"
  elif command -v shasum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | shasum -a 256 2>/dev/null)"
  fi
  h="${h%% *}"
  case "$h" in
    *[!0-9a-f]*) h="" ;;
  esac
  if [ "${#h}" -ge 16 ]; then
    printf '%s' "${h:0:16}"
    return 0
  fi
  c="$(printf '%s' "$1" | cksum 2>/dev/null)"
  c="${c%% *}"
  case "$c" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf 'c%s' "$c"
}

file_size() { # <file> → decimal byte count on stdout (empty when unreadable)
  local s
  s="$(wc -c < "$1" 2>/dev/null)" || s=""
  printf '%s' "${s//[!0-9]/}"
}

at_cap() { # <file> <cap> → 0 when the file holds at least <cap> bytes
  local s
  s="$(file_size "$1")"
  [ -n "$s" ] || return 1
  [ "$s" -gt 0 ] 2>/dev/null || return 1
  [ "$s" -ge "$2" ] 2>/dev/null
}

rotate_log() { # <hooks-dir> <log> <old-log> <cap>
  local dir="$1" f="$2" f1="$3" cap="$4" lock
  lock="${dir}/.rotate.lock"
  [ -f "$f" ] || return 0
  at_cap "$f" "$cap" || return 0
  if [ -d "$lock" ] && [ -n "$(find "$dir" -maxdepth 1 -name '.rotate.lock' -mmin +10 2>/dev/null)" ]; then
    rmdir "$lock" 2>/dev/null
  fi
  if mkdir "$lock" 2>/dev/null; then
    if at_cap "$f" "$cap"; then
      mv -f "$f" "$f1" 2>/dev/null
    fi
    rmdir "$lock" 2>/dev/null
  fi
  return 0
}

hook_main() { # <harness> <root>   (never prints; every failure returns 0)
  local harness="$1" root="$2" payload ts key line dir f f1 cap

  payload="$(cat; printf x)"
  payload="${payload%x}"

  [ "${AGENT_KIT_HOOK_LOG:-}" = '0' ] && return 0

  case "$payload" in
    *'{'*'}'*) ;;
    *) return 0 ;;
  esac

  if [ "$harness" = 'claude' ]; then
    [ -n "${CURSOR_PROJECT_DIR:-}" ] && return 0
    case "$payload" in
      *'"cursor_version"'*) return 0 ;;
    esac
  fi

  ts="$(now_ts)" || return 0
  [ -n "$ts" ] || return 0
  key="$(compute_key "$payload")" || return 0
  [ -n "$key" ] || return 0

  line="$(printf '%s' "$payload" | awk -v harness="$harness" -v ts="$ts" -v key="$key" "$EXTRACT_AWK" 2>/dev/null)" || return 0
  [ -n "$line" ] || return 0

  dir="${root}/${LOG_SUBDIR}"
  f="${dir}/events.jsonl"
  f1="${dir}/events.1.jsonl"

  if grep -sqF -- "\"key\":\"${key}\"" "$f" "$f1"; then
    return 0
  fi

  mkdir -p "$dir" 2>/dev/null || return 0

  cap="${AGENT_KIT_HOOK_LOG_MAX_BYTES:-}"
  case "$cap" in
    ''|*[!0-9]*) cap="$DEFAULT_MAX_BYTES" ;;
  esac
  rotate_log "$dir" "$f" "$f1" "$cap"

  printf '%s\n' "$line" >> "$f" 2>/dev/null
  return 0
}

hook_exit() { # EXIT trap in hook mode: the one place the output contract is written
  if [ "${HOOK_HARNESS:-}" = 'cursor' ]; then
    printf '{}\n'
  fi
  exit 0
}

run_summary() { # <root>
  local root="$1" dir f f1
  dir="${root}/${LOG_SUBDIR}"
  f="${dir}/events.jsonl"
  f1="${dir}/events.1.jsonl"
  cat "$f1" "$f" 2>/dev/null \
    | awk "$SUMMARY_AWK" \
    | sort -t "$(printf '\t')" -k1,1n -k2,2 \
    | HOOK_LOG_EVENTS_PATH="$f" awk "$SUMMARY_FORMAT_AWK"
}

default_root() { # parent of this script's directory
  local src="${BASH_SOURCE[0]:-$0}" d
  case "$src" in
    */*) d="${src%/*}" ;;
    *) d='.' ;;
  esac
  [ -n "$d" ] || d='/'
  (CDPATH= cd "$d/.." 2>/dev/null && pwd -P)
}

# --- main ------------------------------------------------------------------------------------

[ $# -ge 1 ] || { usage >&2; exit 2; }

mode="$1"
shift
harness=""

case "$mode" in
  --help)
    [ $# -eq 0 ] || { usage >&2; exit 2; }
    usage
    exit 0
    ;;
  hook)
    [ $# -ge 1 ] || { usage >&2; exit 2; }
    harness="$1"
    shift
    case "$harness" in
      claude|cursor) ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  summary) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

root_explicit=0
root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      root_explicit=1
      root="$2"
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done
if [ "$root_explicit" -eq 1 ] && [ -z "$root" ]; then
  usage >&2
  exit 2
fi

if [ "$mode" = 'hook' ]; then
  HOOK_HARNESS="$harness"
  trap hook_exit EXIT
  if [ "$root_explicit" -eq 1 ]; then
    rootdir="$(CDPATH= cd "$root" 2>/dev/null && pwd -P)"
  else
    rootdir="$(default_root)"
  fi
  if [ -n "$rootdir" ]; then
    # A subshell, so an unexpected exit or unset-variable abort inside hook_main cannot skip the trap's output.
    ( hook_main "$harness" "$rootdir" ) >/dev/null 2>&1
  fi
  exit 0
fi

if [ "$root_explicit" -eq 1 ]; then
  rootdir="$(CDPATH= cd "$root" 2>/dev/null && pwd -P)" || die 2 "cannot read root: $root"
else
  rootdir="$(default_root)"
fi
[ -n "$rootdir" ] || die 2 'cannot resolve root'
run_summary "$rootdir"
exit 0
