#!/usr/bin/env bash
# memory.sh — add|index|search|show|redact|check|rm|capture|backfill|prune
# Emitted single-copy to `_kit/memory.sh` (Windows outside Git Bash: `_kit\memory.cmd`).
#
#   memory.sh add --kind <k> --title <t> --body <path>
#             [--source <s>] [--tags <list>] [--supersedes <list>] [--harness <h>] [--root <dir>]
#   memory.sh index [--root <dir>]
#   memory.sh search <term>... [--kind <list>] [--limit <n>] [--include-superseded]
#             [--engine grep|fts] [--root <dir>]
#   memory.sh show <id> [--root <dir>]
#   memory.sh redact [--root <dir>]
#   memory.sh check [--staged] [--root <dir>] [<path>…]
#   memory.sh rm <id> [--root <dir>]
#   memory.sh capture [--harness cursor|claude|codex|all] [--from <dir>] … [--root <dir>]
#   memory.sh backfill [--plan|--apply] [--goals] [--research] [--escalations] [--only <name>] [--root <dir>]
#   memory.sh prune [--plan|--apply] [--goals] [--research] [--only <name>] [--root <dir>]
#
# Exit codes: 0 ok · 2 usage/format · 3 gate failed · 4 missing root, file, id, or optional dependency · 5 quarantined.
# Errors: one line on stderr prefixed `memory: `. Store path: `<root>/_memory/`.
#
# Portability: bash 3.2+, LC_ALL=C, coreutils/grep/sed/awk/find; optional sqlite3 (FTS5 auto-detect).
set -euo pipefail
set -f
export LC_ALL=C

TAB="$(printf '\t')"
NL="$(printf '\nx')"
NL="${NL%x}"
# ASCII unit separator: internal delimiter for record-read lists (items may contain spaces).
US="$(printf '\037')"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/memory.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

mk_tmp() {
  mktemp "$TMPD/t.XXXXXX"
}

# Search terms (cmd_search sets; batch search awk reads).
TERMS=()

re_match() { # <string> <ere>
  case "$1" in
    *"$NL"*) return 1 ;;
  esac
  printf '%s\n' "$1" | LC_ALL=C grep -Eq -- "$2"
}

# LC_ALL=C; equivalent to re_id ERE without forking grep.
valid_record_id() { # <id>
  case "$1" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
usage: memory.sh <add|index|search|show|redact|check|rm|capture|backfill|prune> [--root <dir>] ...
  add    --kind <k> --title <t> --body <path> [--source <s>] [--tags <list>] [--supersedes <list>] [--harness <h>]
  index  [--root <dir>]
  search <term>... [--kind <list>] [--limit <n>] [--include-superseded] [--engine grep|fts]
  show   <id> [--root <dir>]
  redact [--root <dir>]
  check  [--staged] [--root <dir>] [<path>…]
  rm     <id> [--root <dir>]
  capture [--harness cursor|claude|codex|all] [--from <dir>] [--idle-hours <n>] [--since <YYYY-MM-DD>] [--root <dir>]
  backfill [--plan|--apply] [--goals] [--research] [--escalations] [--only <name>] [--root <dir>]
  prune  [--plan|--apply] [--goals] [--research] [--only <name>] [--root <dir>]
exit: 0 ok · 2 usage/format · 3 gate failed · 4 missing root/file/id/dependency · 5 quarantined
EOF
}

die() { # <code> <message>
  printf 'memory: %s\n' "$2" >&2
  exit "$1"
}

need_val() { # <flag>
  [ $# -ge 2 ] || die 2 "flag '$1' needs a value"
  [ "${2#--}" = "$2" ] || die 2 "flag '$1' needs a value"
}

# --- formats (ERE, LC_ALL=C) ---
re_id='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
re_tag='^[a-z0-9][a-z0-9-]*$'
re_limit='^[1-9][0-9]*$'
re_memory_now='^[0-9]{8}T[0-9]{6}Z$'

valid_kind() {
  case "$1" in
    goal-summary|spawn-digest|session-summary|research-ingest|decision|learning|fact|pitfall) return 0 ;;
    *) return 1 ;;
  esac
}

valid_harness() {
  case "$1" in
    claude|cursor|copilot|codex) return 0 ;;
    *) return 1 ;;
  esac
}

byte_len() { # <string>
  printf '%s' "$1" | wc -c | tr -d '[:space:]'
}

escape_source() { # <string> → stdout
  printf '%s' "$1" | sed 's/"/'"'"'/g;s/\\/\//g'
}

# Trim ASCII space (0x20) only.
trim_ascii_sp() {
  local s="$1"
  while [ "${s# }" != "$s" ]; do s="${s# }"; done
  while [ "${s% }" != "$s" ]; do s="${s% }"; done
  printf '%s' "$s"
}

# parse comma list: sets global PARSED_LIST_ITEMS (space-separated, safe ids/tags/kinds)
parse_list() { # <list-string> <mode: tag|id|kind>
  local raw="$1" mode="$2" part items="" seen="" item
  PARSED_LIST_ITEMS=""
  [ -n "$raw" ] || return 0
  local rest="$raw"
  while [ -n "$rest" ]; do
    part="${rest%%,*}"
    if [ "$part" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*,}"
    fi
    item="$(trim_ascii_sp "$part")"
    [ -n "$item" ] || continue
    case "$mode" in
      tag)
        re_match "$item" "$re_tag" || return 1
        ;;
      id)
        re_match "$item" "$re_id" || return 1
        ;;
      kind)
        valid_kind "$item" || return 1
        ;;
    esac
    case " $seen " in
      *" $item "*) ;;
      *)
        seen="$seen $item"
        items="${items:+$items }$item"
        ;;
    esac
  done
  PARSED_LIST_ITEMS="$items"
  return 0
}

list_to_yaml_inline() { # space-separated items → [a, b] or []
  local items="$1" out="" x
  [ -n "$items" ] || { printf '[]'; return; }
  for x in $items; do
    out="${out:+$out, }$x"
  done
  printf '[%s]' "$out"
}

list_to_comma_nospace() { # US-separated record-list items (REC_LIST_ITEMS) → a,b for manifest
  local rest="$1" out="" x
  while [ -n "$rest" ]; do
    x="${rest%%"$US"*}"
    if [ "$x" = "$rest" ]; then rest=""; else rest="${rest#*"$US"}"; fi
    [ -n "$x" ] || continue
    out="${out:+$out,}$x"
  done
  printf '%s' "$out"
}

default_root() {
  local r
  r="$(git rev-parse --show-toplevel 2>/dev/null)" || r="$PWD"
  printf '%s' "$r"
}

resolve_root() { # <root-arg>
  local r="$1"
  [ -d "$r" ] || die 4 "root directory not found: $r"
  printf '%s' "$r"
}

canonical_dir() { # <dir> → physical absolute path
  local d="$1"
  ( CDPATH= cd -- "$d" && pwd -P ) || return 1
}

canonical_file_path() { # <path> → physical absolute path to regular file
  local f="$1" dir base
  [ -f "$f" ] || return 1
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  dir="$(CDPATH= cd -- "$dir" && pwd -P)" || return 1
  printf '%s/%s' "$dir" "$base"
}

store_dir() { # <root>
  printf '%s/_memory' "$1"
}

relpath_under_root() { # <root> <abs-path>
  local root="$1" path="$2"
  case "$path" in
    "$root"/*) path="${path#"$root"/}" ;;
  esac
  printf '%s' "${path//\\//}"
}

id_to_record_path() { # <store> <id> → abs path under records/
  local store="$1" id="$2" yyyy mm
  yyyy="${id:0:4}"
  mm="${id:4:2}"
  printf '%s/records/%s/%s/%s.md' "$store" "$yyyy" "$mm" "$id"
}

id_to_quarantine_path() { # <store> <id>
  printf '%s/quarantine/%s.md' "$1" "$2"
}

sha256_hex() { # <file-or-stdin-marker> — reads stdin
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die 4 "no sha256 tool"
  fi
}

have_sha256() {
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1
}

commit_short() { # <root>
  local c
  c="$(git -C "$1" rev-parse --short=12 HEAD 2>/dev/null)" || c="none"
  printf '%s' "$c"
}

utc_now_id_prefix() {
  date -u +%Y%m%dT%H%M%SZ
}

# NUL check before reading body into variables (evaluator note a).
body_has_nul() { # <path>
  tr -d '\000' < "$1" | cmp -s - "$1"
  local st=$?
  [ "$st" -ne 0 ]
}

normalize_body_file() { # <in-path> <out-path>
  local in="$1" out="$2" endlf=0
  [ -s "$in" ] && [ "$(tail -c 1 "$in" | od -An -tx1 | tr -d ' \n')" = "0a" ] && endlf=1
  awk -v endlf="$endlf" '
    {
      if (NR==1 && length($0)>=3 && substr($0,1,3)==sprintf("%c%c%c",239,187,191)) {
        $0=substr($0,4)
      }
      lines[++n]=$0
    }
    END {
      for (i=1;i<=n;i++) if (i<n || endlf) sub(/\r$/, "", lines[i])
      while (n>0 && lines[n] ~ /^[ \t]*$/) n--
      if (n<1) exit 1
      for (i=1;i<=n;i++) print lines[i]
    }
  ' "$in" > "$out" || return 1
  # Ensure exactly one trailing LF (awk print adds newline per line; no extra blank line at end)
  local bytes
  bytes="$(wc -c < "$out" | tr -d '[:space:]')"
  if [ "$bytes" -eq 0 ]; then
    return 1
  fi
  return 0
}

prepare_body_file() { # <in-path> → writes normalized body to stdout path; die on error
  local in="$1" tmp len
  [ -f "$in" ] && [ -r "$in" ] || die 4 "body file not found: $in"
  body_has_nul "$in" && die 2 "body contains NUL byte"
  tmp="$(mk_tmp)"
  normalize_body_file "$in" "$tmp" || die 2 "invalid body"
  len="$(wc -c < "$tmp" | tr -d '[:space:]')"
  [ "$len" -ge 1 ] || die 2 "invalid body"
  [ "$len" -le 4096 ] || die 2 "invalid body"
  printf '%s' "$tmp"
}

ascii_fold_line() { # <line> → stdout (A-Z → a-z)
  printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# Frozen ERE alternation; the README literal `<\|?im_start\|?>` is equivalent to the code's `<[|]?im_start[|]?>`.
ADMISSION_ERE='ignore (all )?(previous|prior|above) instructions|disregard (all )?(previous|prior|above)|you must now|new instructions:|<[|]?im_start[|]?>|</?system>'

admission_violation() { # <title> <body-file>
  local title="$1" body_file="$2" folded_body
  ascii_fold_line "$title" | LC_ALL=C grep -Eq "$ADMISSION_ERE" && return 0
  folded_body="$(mk_tmp)"
  tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' < "$body_file" > "$folded_body"
  LC_ALL=C grep -Eq "$ADMISSION_ERE" "$folded_body" && return 0
  return 1
}

# Frozen redaction classes (ERE order and patterns match skills/agent-kit/templates/memory/README.md § Redaction).
REDACT_CLASS_ORDER="private-key secret aws-key github-token api-key slack-token jwt azure-key"

# Globals set by memory_redact_file: total replacements and comma-separated class list.
REDACT_N=0
REDACT_CLASSES=""

count_redact_markers() { # <path> <class>
  local n
  n="$(grep -o "\\[REDACTED:$2\\]" "$1" 2>/dev/null | wc -l | tr -d '[:space:]')"
  printf '%s' "${n:-0}"
}

file_has_trailing_lf() { # <path>
  [ -s "$1" ] || return 1
  [ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" = "0a" ]
}

strip_trailing_lf_file() { # <path>
  local f="$1" len last
  len="$(wc -c < "$f" | tr -d '[:space:]')"
  [ "$len" -gt 0 ] || return 0
  last="$(tail -c 1 "$f" | od -An -tx1 | tr -d ' \n')"
  [ "$last" = "0a" ] || return 0
  head -c $((len - 1)) "$f" > "${f}.notail" && mv "${f}.notail" "$f"
}

redact_private_key_body() { # <in-path> <out-path>
  awk '
    BEGIN { in_block = 0 }
    # Inside an open block any line with the END marker closes it (even if it also holds a
    # BEGIN marker): no extra marker, no extra count. The same-line BEGIN+END rule below
    # applies only when not in a block.
    in_block {
      if (/-----END [A-Z0-9 ]*PRIVATE KEY-----/) { in_block = 0 }
      next
    }
    /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/ && /-----END [A-Z0-9 ]*PRIVATE KEY-----/ {
      print "[REDACTED:private-key]"
      next
    }
    /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/ {
      print "[REDACTED:private-key]"
      in_block = 1
      next
    }
    { print }
  ' "$1" > "$2"
}

# sed -E scripts (LC_ALL=C): boundary groups use \1 preservation where noted in the README.
REDACT_SED_AWS='s/((AKIA|ASIA)[0-9A-Z]{16})/[REDACTED:aws-key]/g'
REDACT_SED_GITHUB_A='s/(^|[^A-Za-z0-9_])((gh[pousr]_[A-Za-z0-9]{36,}))/\1[REDACTED:github-token]/g'
REDACT_SED_GITHUB_B='s/(^|[^A-Za-z0-9_])((github_pat_[A-Za-z0-9_]{22,}))/\1[REDACTED:github-token]/g'
REDACT_SED_API='s/(^|[^A-Za-z0-9_-])((sk-(ant-)?[A-Za-z0-9_-]{20,}))/\1[REDACTED:api-key]/g'
REDACT_SED_SLACK='s/(xox[abprs]-[A-Za-z0-9-]{10,})/[REDACTED:slack-token]/g'
REDACT_SED_JWT='s/(eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})/[REDACTED:jwt]/g'
REDACT_SED_AZURE='s/((AccountKey|SharedAccessKey)=)([^][;"'"'"'[:space:]][^;"'"'"'[:space:]]*)/\1[REDACTED:azure-key]/g'

redact_sed_pass() { # <in> <out> <script>
  LC_ALL=C sed -E "$3" "$1" > "$2"
}

redact_secret_assignments() { # <in-path> <out-path> — README secret class (POSIX awk)
  awk '
    function is_space(c) { return c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\v" || c == "\f" }
    function fold(c) {
      if (c >= "A" && c <= "Z") return sprintf("%c", index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c) + 96)
      return c
    }
    function secret_value_bad_first(c) {
      if (is_space(c)) return 1
      if (c == "[" || c == "]" || c == "\"" || c == "\047" || c == "<" || c == "$" || c == "{" || c == "`") return 1
      return 0
    }
    function secret_value_bad_rest(c) {
      if (is_space(c) || c == "\"" || c == "\047" || c == "`" || c == "," || c == ";") return 1
      return 0
    }
    function ci_eq_at(line, pos, key,    j, c1, c2) {
      for (j = 1; j <= length(key); j++) {
        c1 = fold(substr(line, pos + j - 1, 1))
        c2 = fold(substr(key, j, 1))
        if (c1 != c2) return 0
      }
      return 1
    }
    function match_key(line, pos,    keys, i, k, n) {
      n = length(line)
      split("password passwd pwd secret client_secret token access_token api_key api-key apikey", keys, " ")
      for (i = 1; i <= 10; i++) {
        k = keys[i]
        if (pos + length(k) - 1 <= n && ci_eq_at(line, pos, k)) return k
      }
      return ""
    }
    function value_start(line, p, n,    ch) {
      if (p <= n && (substr(line, p, 1) == "\"" || substr(line, p, 1) == "\047")) p++
      while (p <= n && is_space(substr(line, p, 1))) p++
      if (p > n || (substr(line, p, 1) != "=" && substr(line, p, 1) != ":")) return 0
      p++
      while (p <= n && is_space(substr(line, p, 1))) p++
      if (p <= n && (substr(line, p, 1) == "\"" || substr(line, p, 1) == "\047")) p++
      if (p > n) return 0
      return p
    }
    function redact_line(line,    out, i, n, c, b, key, k, sep_from, val_start, val_end, ch) {
      out = ""
      i = 1
      n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        b = (i == 1)
        if (!b) b = (substr(line, i - 1, 1) !~ /[A-Za-z0-9_]/)
        if (b) {
          key = match_key(line, i)
          if (key != "") {
            k = length(key)
            sep_from = i + k
            val_start = value_start(line, sep_from, n)
            if (val_start > 0) {
              ch = substr(line, val_start, 1)
              if (!secret_value_bad_first(ch)) {
                val_end = val_start
                while (val_end < n) {
                  ch = substr(line, val_end + 1, 1)
                  if (secret_value_bad_rest(ch)) break
                  val_end++
                }
                if (val_end - val_start + 1 >= 8) {
                  out = out substr(line, i, k) substr(line, sep_from, val_start - sep_from) "[REDACTED:secret]"
                  i = val_end + 1
                  continue
                }
              }
            }
          }
        }
        out = out c
        i++
      }
      return out
    }
    { print redact_line($0) }
  ' "$1" > "$2"
}

memory_redact_file() { # <in-path> <out-path> <include-private-key: 0|1> [skip-count: 0|1]
  local in="$1" out="$2" priv="$3" skip_count="${4:-0}" tmp step cls before after delta
  local counts_in counts_out total=0 classes=""
  tmp="$(mk_tmp)"
  step="$(mk_tmp)"
  if [ "$priv" = "1" ]; then
    redact_private_key_body "$in" "$step"
  else
    cp "$in" "$step"
  fi
  redact_secret_assignments "$step" "$tmp"
  if [ "$skip_count" = "1" ]; then
    LC_ALL=C sed -E \
      -e "$REDACT_SED_AWS" \
      -e "$REDACT_SED_GITHUB_A" \
      -e "$REDACT_SED_GITHUB_B" \
      -e "$REDACT_SED_API" \
      -e "$REDACT_SED_SLACK" \
      -e "$REDACT_SED_JWT" \
      -e "$REDACT_SED_AZURE" \
      "$tmp" > "$out"
    if ! file_has_trailing_lf "$in"; then
      strip_trailing_lf_file "$out"
    fi
    REDACT_N=0
    REDACT_CLASSES=""
    return 0
  fi
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_AWS"
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_GITHUB_A"
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_GITHUB_B"
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_API"
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_SLACK"
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_JWT"
  cp "$tmp" "$step"
  redact_sed_pass "$step" "$tmp" "$REDACT_SED_AZURE"
  cp "$tmp" "$out"
  if ! file_has_trailing_lf "$in"; then
    strip_trailing_lf_file "$out"
  fi
  for cls in private-key secret aws-key github-token api-key slack-token jwt azure-key; do
    if [ "$priv" != "1" ] && [ "$cls" = "private-key" ]; then
      continue
    fi
    before="$(count_redact_markers "$in" "$cls")"
    after="$(count_redact_markers "$out" "$cls")"
    delta=$((after - before))
    if [ "$delta" -gt 0 ]; then
      total=$((total + delta))
      classes="${classes:+$classes,}$cls"
    fi
  done
  REDACT_N="$total"
  REDACT_CLASSES="$classes"
}

merge_redact_classes() { # <csv-a> <csv-b>
  local a="$1" b="$2" cls out=""
  for cls in private-key secret aws-key github-token api-key slack-token jwt azure-key; do
    case ",$a,$b," in
      *",$cls,"*) out="${out:+$out,}$cls" ;;
    esac
  done
  REDACT_CLASSES="$out"
}

print_redact_notice() {
  [ "${REDACT_N:-0}" -gt 0 ] || return 0
  printf 'memory: redacted %s secret(s): %s\n' "$REDACT_N" "$REDACT_CLASSES" >&2
}

print_add_notices() {
  print_redact_notice
  if [ "${TAGS_TRUNCATED:-0}" -eq 1 ]; then
    printf 'memory: tags truncated to 6\n' >&2
  fi
}

TAGS_TRUNCATED=0

normalize_tags_list() { # <raw> — sets PARSED_LIST_ITEMS, TAGS_TRUNCATED; return 1 on invalid tag
  local raw="$1" flat w seen="" items="" n=0 kept=""
  PARSED_LIST_ITEMS=""
  TAGS_TRUNCATED=0
  [ -n "$raw" ] || return 0
  while IFS= read -r w || [ -n "$w" ]; do
    w="$(printf '%s' "$w" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
    [ -n "$w" ] || continue
    case " $seen " in
      *" $w "*) continue ;;
    esac
    re_match "$w" "$re_tag" || return 1
    seen="$seen $w"
    items="${items:+$items }$w"
  done <<EOF
$(printf '%s' "$raw" | tr ', \t\n\r\v\f' '\n\n\n\n\n\n\n')
EOF
  for w in $items; do
    n=$((n + 1))
    if [ "$n" -le 6 ]; then
      kept="${kept:+$kept }$w"
    else
      TAGS_TRUNCATED=1
    fi
  done
  PARSED_LIST_ITEMS="$kept"
  return 0
}

enforce_body_size() { # <path>
  local len
  len="$(wc -c < "$1" | tr -d '[:space:]')"
  [ "$len" -ge 1 ] || die 2 "invalid body"
  [ "$len" -le 4096 ] || die 2 "invalid body"
}

# Read frontmatter keys from record file; sets FM_* globals. Returns 0 ok, 1 malformed.
read_frontmatter() { # <path>
  local path="$1" line key val in_fm=0 closed=0
  local h_id=0 h_kind=0 h_title=0 h_date=0 h_source=0 h_commit=0 h_harness=0 h_tags=0 h_sup=0 h_sha=0
  FM_ID="" FM_KIND="" FM_TITLE="" FM_DATE="" FM_SOURCE="" FM_COMMIT="" FM_HARNESS=""
  FM_TAGS="" FM_SUPERSEDES="" FM_SHA256=""
  if [ ! -f "$path" ]; then return 1; fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$in_fm" -eq 0 ]; then
      [ "$line" = "---" ] || return 1
      in_fm=1
      continue
    fi
    if [ "$line" = "---" ]; then
      closed=1
      break
    fi
    key="${line%%:*}"
    val="${line#*: }"
    case "$key" in
      id) FM_ID="$val"; h_id=1 ;;
      kind) FM_KIND="$val"; h_kind=1 ;;
      title)
        val="${val#\"}"; val="${val%\"}"
        FM_TITLE="$val"
        h_title=1
        ;;
      date) FM_DATE="$val"; h_date=1 ;;
      source)
        val="${val#\"}"; val="${val%\"}"
        FM_SOURCE="$val"
        h_source=1
        ;;
      commit) FM_COMMIT="$val"; h_commit=1 ;;
      harness)
        val="${val#\"}"; val="${val%\"}"
        FM_HARNESS="$val"
        h_harness=1
        ;;
      tags)
        FM_TAGS="$val"
        h_tags=1
        ;;
      supersedes) FM_SUPERSEDES="$val"; h_sup=1 ;;
      sha256) FM_SHA256="$val"; h_sha=1 ;;
      quarantined) ;;
    esac
  done < "$path"
  [ "$closed" -eq 1 ] || return 1
  [ "$h_id" -eq 1 ] && [ "$h_kind" -eq 1 ] && [ "$h_title" -eq 1 ] && [ "$h_date" -eq 1 ] &&
    [ "$h_source" -eq 1 ] && [ "$h_commit" -eq 1 ] && [ "$h_harness" -eq 1 ] &&
    [ "$h_tags" -eq 1 ] && [ "$h_sup" -eq 1 ] && [ "$h_sha" -eq 1 ] || return 1
  return 0
}

glob_record_files() { # <store> <out-list-file>
  local store="$1" out="$2" f id
  : > "$out"
  [ -d "$store/records" ] || return 0
  find -L "$store/records" -mindepth 3 -maxdepth 3 -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
    case "$f" in
      */records/[0-9][0-9][0-9][0-9]/[0-9][0-9]/*.md) ;;
      *) continue ;;
    esac
    id="${f##*/}"; id="${id%.md}"
    valid_record_id "$id" || continue
    printf '%s\n' "$f"
  done >> "$out" || true
}

glob_dedupe_files() { # <store> <out-list-file> — records + quarantine
  local store="$1" out="$2" f id
  : > "$out"
  glob_record_files "$store" "$out"
  if [ -d "$store/quarantine" ]; then
    find -L "$store/quarantine" -maxdepth 1 -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
      id="${f##*/}"; id="${id%.md}"
      valid_record_id "$id" || continue
      printf '%s\n' "$f"
    done >> "$out" || true
  fi
}

write_record_file() { # <path> ... <sha> <body-file> [quarantine: 0|1]
  local path="$1" id="$2" kind="$3" title="$4" date="$5" source="$6" commit="$7" harness="$8"
  local tags_items="$9" sup_items="${10}" sha="${11}" body_file="${12}" quarantine="${13:-0}"
  local tags_yaml sup_yaml src_esc dir
  tags_yaml="$(list_to_yaml_inline "$tags_items")"
  sup_yaml="$(list_to_yaml_inline "$sup_items")"
  src_esc="$(escape_source "$source")"
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  {
    printf '%s\n' '---'
    printf 'id: %s\n' "$id"
    printf 'kind: %s\n' "$kind"
    printf 'title: "%s"\n' "$title"
    printf 'date: %s\n' "$date"
    printf 'source: "%s"\n' "$src_esc"
    printf 'commit: %s\n' "$commit"
    printf 'harness: "%s"\n' "$harness"
    printf 'tags: %s\n' "$tags_yaml"
    printf 'supersedes: %s\n' "$sup_yaml"
    printf 'sha256: %s\n' "$sha"
    [ "$quarantine" = "1" ] && printf '%s\n' 'quarantined: true'
    printf '%s\n' '---'
    cat "$body_file"
  } > "$path"
}

fts5_available() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(x);" >/dev/null 2>&1
}

sql_escape_sq() { # <string>
  printf '%s' "$1" | sed "s/'/''/g"
}

build_fts_db() { # <store> — MEM_AWK_LISTFILE must be set
  local store="$1" db="$store/.index/fts.db" sql listfile
  listfile="${MEM_AWK_LISTFILE:-}"
  [ -n "$listfile" ] || return 1
  mkdir -p "$store/.index"
  rm -f "$db"
  sql="$(mk_tmp)"
  {
    printf "CREATE VIRTUAL TABLE records USING fts5(id UNINDEXED, title, tags, body);\n"
    awk '
      function esc(s) { gsub(/\047/, "\047\047", s); return s }
      function fm_value(line,    p) {
        p = index(line, ": ")
        if (p > 0) return substr(line, p + 2)
        return line
      }
      function fm_strip_quotes(val) {
        if (substr(val, 1, 1) == "\042") val = substr(val, 2)
        if (length(val) > 0 && substr(val, length(val), 1) == "\042") val = substr(val, 1, length(val) - 1)
        return val
      }
      function tags_sql(raw,    s) {
        s = raw
        sub(/^\[/, "", s)
        sub(/\]$/, "", s)
        gsub(/, /, ",", s)
        return esc(s)
      }
      function fm_ok(got) {
        return got["id"] && got["kind"] && got["title"] && got["date"] && got["source"] &&
          got["commit"] && got["harness"] && got["tags"] && got["supersedes"] && got["sha256"]
      }
      function emit_insert(path,    line, key, val, c, closed, got, body, fm_id, fm_title, fm_tags, listfile) {
        split("", got)
        c = 0
        closed = 0
        body = ""
        fm_id = ""
        fm_title = ""
        fm_tags = ""
        while ((getline line < path) > 0) {
          sub(/\r$/, "", line)
          if (c == 0) {
            if (line != "---") { close(path); return }
            c = 1
            continue
          }
          if (c == 1) {
            if (line == "---") { closed = 1; c = 2; continue }
            key = line
            sub(/:.*/, "", key)
            val = fm_value(line)
            if (key == "title" || key == "source" || key == "harness") val = fm_strip_quotes(val)
            if (key == "id") { fm_id = val; got["id"] = 1 }
            else if (key == "kind") got["kind"] = 1
            else if (key == "title") { fm_title = val; got["title"] = 1 }
            else if (key == "date") got["date"] = 1
            else if (key == "source") got["source"] = 1
            else if (key == "commit") got["commit"] = 1
            else if (key == "harness") got["harness"] = 1
            else if (key == "tags") { fm_tags = val; got["tags"] = 1 }
            else if (key == "supersedes") got["supersedes"] = 1
            else if (key == "sha256") got["sha256"] = 1
            continue
          }
          if (body == "") body = line
          else body = body sprintf("%c", 10) line
        }
        close(path)
        if (!closed || !fm_ok(got)) return
        printf "INSERT INTO records(id, title, tags, body) VALUES('\''%s'\'','\''%s'\'','\''%s'\'','\''%s'\'');\n",
          esc(fm_id), esc(fm_title), tags_sql(fm_tags), esc(body)
      }
      BEGIN {
        listfile = ENVIRON["MEM_AWK_LISTFILE"]
        while ((getline path < listfile) > 0) {
          if (path == "") continue
          emit_insert(path)
        }
        close(listfile)
      }
    '
  } > "$sql"
  sqlite3 -batch -init /dev/null -noheader "$db" < "$sql" || return 1
  return 0
}

parse_tags_brackets() { # [a, b] → US-separated items in REC_LIST_ITEMS (an item may contain spaces)
  local raw="$1" inner x out=""
  inner="$(printf '%s' "$raw" | sed 's/^\[//;s/\]$//')"
  REC_LIST_ITEMS=""
  [ -n "$inner" ] || return 0
  local rest="$inner"
  while [ -n "$rest" ]; do
    x="${rest%%,*}"
    if [ "$x" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
    x="$(trim_ascii_sp "$x")"
    [ -n "$x" ] || continue
    out="${out:+$out$US}$x"
  done
  REC_LIST_ITEMS="$out"
}

parse_supersedes_brackets() {
  parse_tags_brackets "$1"
}

run_index() { # <root> <quiet: 0|1>
  local root="$1" quiet="${2:-0}" store rec_list man stamp n fts_yes=0
  store="$(store_dir "$root")"
  rec_list="$(mk_tmp)"
  man="$store/.index/manifest.tsv"
  stamp="$store/.index/stamp"
  glob_record_files "$store" "$rec_list"

  local sort_in ref_file badfile
  sort_in="$(mk_tmp)"
  ref_file="$(mk_tmp)"
  badfile="$(mk_tmp)"
  : > "$sort_in"
  : > "$ref_file"
  : > "$badfile"
  export MEM_AWK_ROOT="$root"
  export MEM_AWK_LISTFILE="$rec_list"
  export MEM_AWK_SORT_OUT="$sort_in"
  export MEM_AWK_REF_OUT="$ref_file"
  export MEM_AWK_BAD_OUT="$badfile"
  awk '
    function relpath(r, path,    p) {
      p = r "/"
      if (substr(path, 1, length(p)) == p) return substr(path, length(p) + 1)
      gsub(/\\/, "/", path)
      return path
    }
    function fm_value(line,    p) {
      p = index(line, ": ")
      if (p > 0) return substr(line, p + 2)
      return line
    }
    function fm_strip_quotes(val) {
      if (substr(val, 1, 1) == "\042") val = substr(val, 2)
      if (length(val) > 0 && substr(val, length(val), 1) == "\042") val = substr(val, 1, length(val) - 1)
      return val
    }
    function trim_sp(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    function brackets_csv(raw,    s, n, parts, i, item, out) {
      s = raw
      sub(/^\[/, "", s)
      sub(/\]$/, "", s)
      if (s == "") return ""
      n = split(s, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        item = trim_sp(parts[i])
        if (item == "") continue
        if (out != "") out = out "," item
        else out = item
      }
      return out
    }
    function fm_ok(got) {
      return got["id"] && got["kind"] && got["title"] && got["date"] && got["source"] &&
        got["commit"] && got["harness"] && got["tags"] && got["supersedes"] && got["sha256"]
    }
    function emit_refs(sup_m, newid,    n, parts, i, ref_out) {
      ref_out = ENVIRON["MEM_AWK_REF_OUT"]
      if (sup_m == "") return
      n = split(sup_m, parts, ",")
      for (i = 1; i <= n; i++) {
        if (parts[i] == "") continue
        printf "%s\t%s\n", parts[i], newid >> ref_out
      }
    }
    function skip_malformed(path,    root, bad_out) {
      root = ENVIRON["MEM_AWK_ROOT"]
      bad_out = ENVIRON["MEM_AWK_BAD_OUT"]
      print relpath(root, path) >> bad_out
    }
    function process_file(path,    line, key, val, c, closed, got, tags_m, sup_m, rel, root, sort_out) {
      split("", got)
      root = ENVIRON["MEM_AWK_ROOT"]
      sort_out = ENVIRON["MEM_AWK_SORT_OUT"]
      c = 0
      closed = 0
      fm_id = ""
      fm_kind = ""
      fm_date = ""
      fm_title = ""
      fm_tags = ""
      fm_sup = ""
      while ((getline line < path) > 0) {
        sub(/\r$/, "", line)
        if (c == 0) {
          if (line != "---") { close(path); skip_malformed(path); return 0 }
          c = 1
          continue
        }
        if (c == 1) {
          if (line == "---") { closed = 1; break }
          key = line
          sub(/:.*/, "", key)
          val = fm_value(line)
          if (key == "title" || key == "source" || key == "harness") val = fm_strip_quotes(val)
          if (key == "id") { fm_id = val; got["id"] = 1 }
          else if (key == "kind") { fm_kind = val; got["kind"] = 1 }
          else if (key == "title") { fm_title = val; got["title"] = 1 }
          else if (key == "date") { fm_date = val; got["date"] = 1 }
          else if (key == "source") got["source"] = 1
          else if (key == "commit") got["commit"] = 1
          else if (key == "harness") got["harness"] = 1
          else if (key == "tags") { fm_tags = val; got["tags"] = 1 }
          else if (key == "supersedes") { fm_sup = val; got["supersedes"] = 1 }
          else if (key == "sha256") got["sha256"] = 1
          continue
        }
      }
      close(path)
      if (!closed || !fm_ok(got)) { skip_malformed(path); return 0 }
      tags_m = brackets_csv(fm_tags)
      sup_m = brackets_csv(fm_sup)
      rel = relpath(root, path)
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", fm_id, fm_kind, fm_date, fm_title, tags_m, rel, sup_m >> sort_out
      emit_refs(sup_m, fm_id)
      return 1
    }
    BEGIN {
      listfile = ENVIRON["MEM_AWK_LISTFILE"]
      while ((getline path < listfile) > 0) {
        if (path == "") continue
        process_file(path)
      }
      close(listfile)
    }
  '
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf 'memory: skipped malformed %s\n' "$rel" >&2
  done < "$badfile"
  n="$(wc -l < "$sort_in" | tr -d '[:space:]')"
  n="${n:-0}"

  mkdir -p "$store/.index"
  {
    printf '%s\n' 'id	kind	date	title	tags	path	supersedes	superseded_by'
    export MEM_AWK_REFFILE="$ref_file"
    sort -t '	' -k1,1 "$sort_in" | awk -F'\t' '
      function join_sorted_arr(a, n,    i, j, tmp, out) {
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            if (a[i] > a[j]) { tmp = a[i]; a[i] = a[j]; a[j] = tmp }
        out = ""
        for (i = 1; i <= n; i++) {
          if (out != "") out = out "," a[i]
          else out = a[i]
        }
        return out
      }
      BEGIN {
        reffile = ENVIRON["MEM_AWK_REFFILE"]
        while ((getline < reffile) > 0) {
          key = $1 ""
          idx = ++ref_n[key]
          ref_by[key, idx] = $2 ""
        }
        close(reffile)
      }
      {
        rid = $1 ""
        if (!(rid in ref_n)) {
          print $0 "\t"
          next
        }
        nn = ref_n[rid]
        for (i = 1; i <= nn; i++) arr[i] = ref_by[rid, i]
        print $0 "\t" join_sorted_arr(arr, nn)
      }
    '
  } > "$man"

  printf '%s\n' "$n" > "$stamp"

  fts_yes=0
  if fts5_available; then
    fts_yes=1
    export MEM_AWK_LISTFILE="$rec_list"
    if build_fts_db "$store"; then
      :
    else
      rm -f "$store/.index/fts.db"
      fts_yes=0
    fi
  else
    rm -f "$store/.index/fts.db"
  fi

  if [ "$quiet" -eq 0 ]; then
    if [ "$fts_yes" -eq 1 ]; then
      printf 'memory: indexed %s records · fts: yes\n' "$n"
    else
      printf 'memory: indexed %s records · fts: no\n' "$n"
    fi
  fi
}

count_valid_records() { # <store>
  local store="$1" list="$(mk_tmp)" n
  glob_record_files "$store" "$list"
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
  done < "$list"
  printf '%s' "$n"
}

index_is_stale() { # <root>
  local root="$1" store man stamp cnt stamp_n f
  store="$(store_dir "$root")"
  man="$store/.index/manifest.tsv"
  stamp="$store/.index/stamp"
  [ -f "$man" ] && [ -f "$stamp" ] || return 0
  cnt="$(count_valid_records "$store")"
  stamp_n="$(tr -d '[:space:]' < "$stamp")"
  [ "$cnt" = "$stamp_n" ] || return 0
  if [ -d "$store/records" ]; then
    local newer_list id
    newer_list="$(mk_tmp)"
    find -L "$store/records" -mindepth 3 -maxdepth 3 -type f -name '*.md' -newer "$man" 2>/dev/null > "$newer_list" || true
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in
        */records/[0-9][0-9][0-9][0-9]/[0-9][0-9]/*.md) ;;
        *) continue ;;
      esac
      id="${f##*/}"; id="${id%.md}"
      valid_record_id "$id" && return 0
    done < "$newer_list"
  fi
  return 1
}

cmd_add() {
  local root="" kind="" title="" body_path="" source="" tags_raw="" sup_raw="" harness=""
  local seen_root=0 seen_kind=0 seen_title=0 seen_body=0 seen_source=0 seen_tags=0 seen_sup=0 seen_harness=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --kind) need_val "$@"; [ "$seen_kind" -eq 0 ] || die 2 "repeated flag '--kind'"; seen_kind=1; kind="$2"; shift 2 ;;
      --title) need_val "$@"; [ "$seen_title" -eq 0 ] || die 2 "repeated flag '--title'"; seen_title=1; title="$2"; shift 2 ;;
      --body) need_val "$@"; [ "$seen_body" -eq 0 ] || die 2 "repeated flag '--body'"; seen_body=1; body_path="$2"; shift 2 ;;
      --source) need_val "$@"; [ "$seen_source" -eq 0 ] || die 2 "repeated flag '--source'"; seen_source=1; source="$2"; shift 2 ;;
      --tags) need_val "$@"; [ "$seen_tags" -eq 0 ] || die 2 "repeated flag '--tags'"; seen_tags=1; tags_raw="$2"; shift 2 ;;
      --supersedes) need_val "$@"; [ "$seen_sup" -eq 0 ] || die 2 "repeated flag '--supersedes'"; seen_sup=1; sup_raw="$2"; shift 2 ;;
      --harness) need_val "$@"; [ "$seen_harness" -eq 0 ] || die 2 "repeated flag '--harness'"; seen_harness=1; harness="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done

  [ "$seen_kind" -eq 1 ] || die 2 "'add' requires --kind"
  [ "$seen_title" -eq 1 ] || die 2 "'add' requires --title"
  [ "$seen_body" -eq 1 ] || die 2 "'add' requires --body"

  valid_kind "$kind" || die 2 "invalid --kind"
  if [ "$seen_harness" -eq 1 ]; then
    valid_harness "$harness" || die 2 "invalid --harness"
  fi

  case "$source" in
    *[[:cntrl:]]*) die 2 "invalid --source" ;;
  esac

  normalize_tags_list "$tags_raw" || die 2 "invalid --tags"
  local tags_items="$PARSED_LIST_ITEMS"
  parse_list "$sup_raw" id || die 2 "invalid --supersedes"
  local sup_items="$PARSED_LIST_ITEMS"

  if [ -n "${MEMORY_NOW:-}" ]; then
    re_match "$MEMORY_NOW" "$re_memory_now" || die 2 "invalid MEMORY_NOW"
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  have_sha256 || die 4 "no sha256 tool"
  [ -f "$body_path" ] || die 4 "body file not found: $body_path"

  local norm_body red_body title_red body_file sha now id date commit store dup_id rel path
  body_has_nul "$body_path" && die 2 "body contains NUL byte"
  norm_body="$(mk_tmp)"
  normalize_body_file "$body_path" "$norm_body" || die 2 "invalid body"
  red_body="$(mk_tmp)"
  memory_redact_file "$norm_body" "$red_body" 1
  local red_body_n="$REDACT_N" red_body_c="$REDACT_CLASSES" title_in title_out
  title_in="$(mk_tmp)"
  title_out="$(mk_tmp)"
  printf '%s' "$title" > "$title_in"
  memory_redact_file "$title_in" "$title_out" 0
  title="$(cat "$title_out")"
  REDACT_N=$((red_body_n + REDACT_N))
  merge_redact_classes "$red_body_c" "$REDACT_CLASSES"
  local tlen
  tlen="$(byte_len "$title")"
  [ "$tlen" -ge 1 ] && [ "$tlen" -le 120 ] || die 2 "invalid --title"
  case "$title" in
    *[\"\\]*|*[[:cntrl:]]*) die 2 "invalid --title" ;;
  esac
  enforce_body_size "$red_body"
  body_file="$red_body"
  sha="$(sha256_hex < "$body_file")"
  if [ -n "${MEMORY_NOW:-}" ]; then
    now="$MEMORY_NOW"
  else
    now="$(utc_now_id_prefix)"
  fi
  id="${now}-${sha:0:8}"
  date="${id:0:4}-${id:4:2}-${id:6:2}"
  commit="$(commit_short "$root")"
  store="$(store_dir "$root")"

  for sid in $sup_items; do
    [ -f "$(id_to_record_path "$store" "$sid")" ] || die 4 "supersedes id not found: $sid"
  done

  local dedupe_list="$(mk_tmp)" f dup_id=""
  glob_dedupe_files "$store" "$dedupe_list"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_frontmatter "$f" || {
      printf 'memory: skipped malformed %s\n' "$(relpath_under_root "$root" "$f")" >&2
      continue
    }
    if [ "$FM_SHA256" = "$sha" ]; then
      if [ -z "$dup_id" ] || [ "$FM_ID" \< "$dup_id" ]; then
        dup_id="$FM_ID"
      fi
    fi
  done < "$dedupe_list"
  if [ -n "$dup_id" ]; then
    local dup_path
    if [ -f "$(id_to_record_path "$store" "$dup_id")" ]; then
      dup_path="$(relpath_under_root "$root" "$(id_to_record_path "$store" "$dup_id")")"
    else
      dup_path="$(relpath_under_root "$root" "$(id_to_quarantine_path "$store" "$dup_id")")"
    fi
    print_add_notices
    printf 'memory: duplicate %s %s\n' "$dup_id" "$dup_path"
    exit 0
  fi

  if admission_violation "$title" "$body_file"; then
    path="$(id_to_quarantine_path "$store" "$id")"
    rel="$(relpath_under_root "$root" "$path")"
    [ -e "$path" ] && die 4 "record exists $rel"
    write_record_file "$path" "$id" "$kind" "$title" "$date" "$source" "$commit" "$harness" \
      "$tags_items" "$sup_items" "$sha" "$body_file" 1
    print_add_notices
    printf 'memory: quarantined %s %s\n' "$id" "$rel"
    exit 5
  fi

  path="$(id_to_record_path "$store" "$id")"
  rel="$(relpath_under_root "$root" "$path")"
  [ -e "$path" ] && die 4 "record exists $rel"
  write_record_file "$path" "$id" "$kind" "$title" "$date" "$source" "$commit" "$harness" \
    "$tags_items" "$sup_items" "$sha" "$body_file" 0
  print_add_notices
  printf 'memory: added %s %s\n' "$id" "$rel"
  exit 0
}

cmd_index() {
  local root="" seen_root=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  run_index "$root" 0
  exit 0
}

cmd_redact() {
  local root="" seen_root=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  local in out
  in="$(mk_tmp)"
  out="$(mk_tmp)"
  cat > "$in"
  memory_redact_file "$in" "$out" 1
  cat "$out"
  print_redact_notice
  exit 0
}

glob_check_scope() { # <store> <out-list-file>
  local store="$1" out="$2"
  : > "$out"
  if [ -d "$store/records" ]; then
    find -L "$store/records" -type f -name '*.md' 2>/dev/null >> "$out" || true
  fi
  if [ -d "$store/quarantine" ]; then
    find -L "$store/quarantine" -type f -name '*.md' 2>/dev/null >> "$out" || true
  fi
}

extract_record_body_file() { # <record-path> <out-body-file>
  awk '
    BEGIN { c = 0 }
    /^---$/ && c == 0 { c = 1; next }
    c == 1 && /^---$/ { c = 2; next }
    c == 2 { print }
  ' "$1" > "$2"
}

check_path_under_store() { # <root> <store> <user-path> → sets CHECK_ABS CHECK_REL; return 1 if outside
  local root="$1" store="$2" user_path="$3" abs
  abs="$user_path"
  case "$abs" in
    /*) ;;
    *) abs="$root/$user_path" ;;
  esac
  abs="$(canonical_file_path "$abs")" || return 1
  case "$abs" in
    "$store/records"/*|"$store/quarantine"/*) ;;
    *) return 1 ;;
  esac
  CHECK_ABS="$abs"
  CHECK_REL="$(relpath_under_root "$root" "$abs")"
  return 0
}

check_emit_fail() { # <reason> <rel-path>
  printf 'memory: check failed %s %s\n' "$1" "$2"
}

# Validate one record file; prints failure lines to stdout. Returns 0 pass, 1 any failure.
check_record_content() { # <root> <store> <content-file> <abs-path> <rel-path>
  local root="$1" store="$2" content_file="$3" abs="$4" rel="$5"
  local stem expected body_file body_sha title_in title_out red_body id_bad
  local in_records=0 in_quarantine=0 any_fail=0

  case "$rel" in
    *.md) ;;
    *)
      check_emit_fail malformed "$rel"
      return 1
      ;;
  esac

  if ! read_frontmatter "$content_file"; then
    check_emit_fail malformed "$rel"
    return 1
  fi

  case "$abs" in
    "$store/records"/*) in_records=1 ;;
    "$store/quarantine"/*) in_quarantine=1 ;;
  esac
  stem="${abs##*/}"
  stem="${stem%.md}"

  id_bad=0
  if [ "$stem" != "$FM_ID" ]; then
    id_bad=1
  fi
  if [ "$in_records" -eq 1 ]; then
    expected="$(id_to_record_path "$store" "$FM_ID")"
    [ "$abs" = "$expected" ] || id_bad=1
  elif [ "$in_quarantine" -eq 1 ]; then
    expected="$(id_to_quarantine_path "$store" "$FM_ID")"
    [ "$abs" = "$expected" ] || id_bad=1
  fi
  if [ "$id_bad" -eq 1 ]; then
    check_emit_fail id-mismatch "$rel"
    any_fail=1
  fi

  body_file="$(mk_tmp)"
  extract_record_body_file "$content_file" "$body_file"
  body_sha="$(sha256_hex < "$body_file")"
  if [ "$body_sha" != "$FM_SHA256" ]; then
    check_emit_fail sha256-mismatch "$rel"
    any_fail=1
  fi

  title_in="$(mk_tmp)"
  title_out="$(mk_tmp)"
  red_body="$(mk_tmp)"
  local secret_hit=0
  printf '%s' "$FM_TITLE" > "$title_in"
  memory_redact_file "$title_in" "$title_out" 0 1
  if ! cmp -s "$title_in" "$title_out"; then
    secret_hit=1
  fi
  memory_redact_file "$body_file" "$red_body" 1 1
  if ! cmp -s "$body_file" "$red_body"; then
    secret_hit=1
  fi
  if [ "$secret_hit" -eq 1 ]; then
    check_emit_fail secret "$rel"
    any_fail=1
  fi

  if [ "$in_records" -eq 1 ] && admission_violation "$FM_TITLE" "$body_file"; then
    check_emit_fail admission "$rel"
    any_fail=1
  fi

  [ "$any_fail" -eq 0 ]
}

cmd_check() {
  local root="" staged=0 seen_root=0
  local paths_file="" path_arg
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --staged) staged=1; shift ;;
      --*) die 2 "unknown flag '$1'" ;;
      *)
        if [ -z "$paths_file" ]; then
          paths_file="$(mk_tmp)"
          : > "$paths_file"
        fi
        printf '%s\037' "$1" >> "$paths_file"
        shift
        ;;
    esac
  done
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  root="$(canonical_dir "$root")" || die 4 "root directory not found: $root"
  local store fail=0 ok=0
  store="$(store_dir "$root")"
  if [ -d "$store" ]; then
    store="$(canonical_dir "$store")" || die 4 "root directory not found: $root"
  fi

  if [ "$staged" -eq 1 ] && [ -n "$paths_file" ]; then
    die 2 "check --staged takes no paths"
  fi
  if [ "$staged" -eq 1 ]; then
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
      die 4 "check --staged needs a git work tree"
    have_sha256 || die 4 "no sha256 tool"
    local status git_path rel abs content_tmp ns_file status_letter
    ns_file="$(mk_tmp)"
    if ! git -C "$root" diff --cached --name-status --no-renames --no-ext-diff --relative -z -- \
      "_memory/records/" "_memory/quarantine/" > "$ns_file"; then
      die 4 "check --staged: git diff failed"
    fi
    exec 3< "$ns_file"
    while IFS= read -r -d '' status <&3; do
      IFS= read -r -d '' git_path <&3 || break
      [ -n "$status" ] && [ -n "$git_path" ] || continue
      case "$git_path" in
        _memory/records/*|_memory/quarantine/*) ;;
        *) continue ;;
      esac
      rel="$git_path"
      status_letter="${status%%[0-9]*}"
      [ -n "$status_letter" ] || status_letter="$status"
      case "$status_letter" in
        D)
          case "$git_path" in
            _memory/quarantine/*) continue ;;
          esac
          check_emit_fail immutable "$rel"
          fail=1
          continue
          ;;
        A|M) ;;
        *)
          check_emit_fail immutable "$rel"
          fail=1
          continue
          ;;
      esac
      case "$status_letter" in
        M)
          check_emit_fail immutable "$rel"
          fail=1
          ;;
      esac
      content_tmp="$(mk_tmp)"
      if ! git -C "$root" show ":./$git_path" > "$content_tmp" 2>/dev/null; then
        check_emit_fail malformed "$rel"
        fail=1
        continue
      fi
      abs="$root/$git_path"
      case "$status_letter" in
        A)
          if check_record_content "$root" "$store" "$content_tmp" "$abs" "$rel"; then
            ok=$((ok + 1))
          else
            fail=1
          fi
          ;;
        M)
          if check_record_content "$root" "$store" "$content_tmp" "$abs" "$rel"; then
            :
          else
            fail=1
          fi
          ;;
      esac
    done
    exec 3<&-
    if [ "$fail" -ne 0 ]; then
      exit 3
    fi
    printf 'memory: check ok %s file(s)\n' "$ok"
    exit 0
  fi

  have_sha256 || die 4 "no sha256 tool"
  local list_file abs rel CHECK_ABS CHECK_REL
  list_file="$(mk_tmp)"
  if [ -n "$paths_file" ]; then
    : > "$list_file"
    local rest part
    rest="$(cat "$paths_file")"
    while [ -n "$rest" ]; do
      part="${rest%%"$US"*}"
      if [ "$part" = "$rest" ]; then
        rest=""
      else
        rest="${rest#*"$US"}"
      fi
      [ -n "$part" ] || continue
      if ! check_path_under_store "$root" "$store" "$part"; then
        die 2 "check path outside store: $part"
      fi
      printf '%s\n' "$CHECK_ABS" >> "$list_file"
    done
  else
    glob_check_scope "$store" "$list_file"
  fi
  local nfiles idx outdir st running cur_idx
  nfiles="$(wc -l < "$list_file" | tr -d '[:space:]')"
  if [ "${nfiles:-0}" -le 1 ]; then
    while IFS= read -r abs || [ -n "$abs" ]; do
      [ -n "$abs" ] || continue
      rel="$(relpath_under_root "$root" "$abs")"
      if check_record_content "$root" "$store" "$abs" "$abs" "$rel"; then
        ok=$((ok + 1))
      else
        fail=1
      fi
    done < "$list_file"
  else
    outdir="$TMPD/check_out"
    mkdir -p "$outdir"
    idx=0
    running=0
    while IFS= read -r abs || [ -n "$abs" ]; do
      [ -n "$abs" ] || continue
      idx=$((idx + 1))
      cur_idx="$idx"
      (
        rel="$(relpath_under_root "$root" "$abs")"
        if check_record_content "$root" "$store" "$abs" "$abs" "$rel" > "$outdir/$cur_idx.msg"; then
          printf ok > "$outdir/$cur_idx.st"
        else
          printf fail > "$outdir/$cur_idx.st"
        fi
      ) &
      running=$((running + 1))
      if [ "$running" -ge 8 ]; then
        wait
        running=0
      fi
    done < "$list_file"
    wait
    idx=0
    while [ "$idx" -lt "$nfiles" ]; do
      idx=$((idx + 1))
      [ -f "$outdir/$idx.msg" ] && [ -s "$outdir/$idx.msg" ] && cat "$outdir/$idx.msg"
      st="$(cat "$outdir/$idx.st" 2>/dev/null || true)"
      case "$st" in
        ok) ok=$((ok + 1)) ;;
        fail) fail=1 ;;
      esac
    done
  fi
  if [ "$fail" -ne 0 ]; then
    exit 3
  fi
  printf 'memory: check ok %s file(s)\n' "$ok"
  exit 0
}

capture_root_slug_s1() { # <abs-root>
  local slug
  slug="$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')"
  case "$slug" in
    -*) slug="${slug#-}" ;;
  esac
  printf '%s' "$slug"
}

capture_root_slug_s2() { # <abs-root>
  printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'
}

capture_valid_harness_name() {
  case "$1" in
    cursor|claude|codex|all) return 0 ;;
    *) return 1 ;;
  esac
}

capture_validate_idle_hours() { # <value> → stdout normalized hours; exit 2 on invalid
  local v="$1"
  [ -n "$v" ] || die 2 "invalid --idle-hours"
  re_match "$v" '^[0-9]+$' || die 2 "invalid --idle-hours"
  [ "${#v}" -le 6 ] || die 2 "invalid --idle-hours"
  printf '%s' $((10#$v))
}

gregorian_date_valid_p() { # <YYYY-MM-DD> → exit 0 if real Gregorian calendar date
  local since="$1" yy mm dd dim
  re_match "$since" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || return 1
  yy=$((10#${since:0:4}))
  mm=$((10#${since:5:2}))
  dd=$((10#${since:8:2}))
  [ "$mm" -ge 1 ] && [ "$mm" -le 12 ] || return 1
  case "$mm" in
    1|3|5|7|8|10|12) dim=31 ;;
    4|6|9|11) dim=30 ;;
    *)
      if [ $((yy % 4)) -eq 0 ] && { [ $((yy % 100)) -ne 0 ] || [ $((yy % 400)) -eq 0 ]; }; then
        dim=29
      else
        dim=28
      fi
      ;;
  esac
  [ "$dd" -ge 1 ] && [ "$dd" -le "$dim" ]
}

capture_validate_since_date() { # <YYYY-MM-DD> → exit 2 unless a real Gregorian calendar date
  local since="$1"
  [ -n "$since" ] || die 2 "invalid --since"
  re_match "$since" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die 2 "invalid --since"
  gregorian_date_valid_p "$since" || die 2 "invalid --since"
}

capture_scope_from_file() { # <transcript-file> <root-abs> → repo|unknown
  local file="$1" root="$2"
  awk -v root="$root" '
    BEGIN { found = 0; rlen = length(root) }
    {
      text = $0
      pos = 1
      while (1) {
        idx = index(substr(text, pos), root)
        if (idx == 0) break
        idx = pos + idx - 1
        rest = substr(text, idx + rlen, 1)
        if (rest == "" || rest !~ /[A-Za-z0-9._-]/) { found = 1; exit }
        pos = idx + 1
      }
    }
    END { if (found) print "repo"; else print "unknown" }
  ' "$file"
}

capture_write_jq_filter_meta() { # <path>
  local out="$1"
  cat > "$out" <<'JQEOF'
def line_obj: try (fromjson) catch empty;

def cursor_parts($o):
  if ($o | type) != "object" then empty
  elif ($o.role // "") == "user" or ($o.role // "") == "assistant" then
    ($o.role) as $r |
    ($o.message.content // [] | if type == "array" then . else [] end)[] |
    if .type == "text" then {role: $r, kind: "text", text: (.text // "")}
    elif .type == "tool_use" then {role: $r, kind: "tool", name: (.name // "")}
    else empty end
  else empty end;

def claude_parts($o):
  if ($o | type) != "object" then empty
  elif ($o.type // "") == "user" or ($o.type // "") == "assistant" then
    ($o.type) as $r |
    ($o.message.content // null) as $c |
    if ($c | type) == "string" then {role: $r, kind: "text", text: $c}
    elif ($c | type) == "array" then
      $c[] |
      if .type == "text" then {role: $r, kind: "text", text: (.text // "")}
      elif .type == "tool_use" then {role: $r, kind: "tool", name: (.name // "")}
      else empty end
    else empty end
  else empty end;

def codex_parts($o):
  if ($o | type) != "object" then empty
  elif (.type // "") == "response_item" then
    (.payload // {}) as $p |
    if ($p.type // "") == "message" then
      ($p.role // "") as $r |
      if $r != "user" and $r != "assistant" then empty
      else
        ($p.content // [] | if type == "array" then . else [] end)[] |
        if .type == "input_text" or .type == "output_text" then
          {role: $r, kind: "text", text: (.text // "")}
        else empty end
      end
    elif ($p.type // "") == "function_call" then
      {role: "assistant", kind: "tool", name: ($p.name // "")}
    else empty end
  else empty end;

def parts($h; $o):
  if $h == "cursor" then cursor_parts($o)
  elif $h == "claude" then claude_parts($o)
  elif $h == "codex" then codex_parts($o)
  else empty end;

def format_parts($parts):
  (reduce $parts[] as $p (
    {out: "", cur: ""};
    if $p.kind == "text" then
      if .cur != $p.role then
        .out = (.out + (if .out == "" then "" else "\n\n" end) + "## " + $p.role + "\n" + $p.text) | .cur = $p.role
      else
        .out = (.out + "\n" + $p.text)
      end
    elif $p.kind == "tool" then
      if .cur != $p.role then
        .out = (.out + (if .out == "" then "" else "\n\n" end) + "## " + $p.role + "\n[tool: " + $p.name + "]") | .cur = $p.role
      else
        .out = (.out + "\n[tool: " + $p.name + "]")
      end
    else .
    end
  )) | .out;

split("\n")
| map(select(length > 0))
| map(line_obj)
| map(select(. != null)) as $objs
| [ $objs[] | parts($harness; .) ] as $parts
| {
    parsed: ($objs | length),
    first_user: (($parts | map(select(.kind == "text" and .role == "user")) | .[0].text // ""))
  }
JQEOF
}

capture_write_jq_filter_body() { # <path>
  local out="$1"
  cat > "$out" <<'JQEOF'
def line_obj: try (fromjson) catch empty;

def cursor_parts($o):
  if ($o | type) != "object" then empty
  elif ($o.role // "") == "user" or ($o.role // "") == "assistant" then
    ($o.role) as $r |
    ($o.message.content // [] | if type == "array" then . else [] end)[] |
    if .type == "text" then {role: $r, kind: "text", text: (.text // "")}
    elif .type == "tool_use" then {role: $r, kind: "tool", name: (.name // "")}
    else empty end
  else empty end;

def claude_parts($o):
  if ($o | type) != "object" then empty
  elif ($o.type // "") == "user" or ($o.type // "") == "assistant" then
    ($o.type) as $r |
    ($o.message.content // null) as $c |
    if ($c | type) == "string" then {role: $r, kind: "text", text: $c}
    elif ($c | type) == "array" then
      $c[] |
      if .type == "text" then {role: $r, kind: "text", text: (.text // "")}
      elif .type == "tool_use" then {role: $r, kind: "tool", name: (.name // "")}
      else empty end
    else empty end
  else empty end;

def codex_parts($o):
  if ($o | type) != "object" then empty
  elif (.type // "") == "response_item" then
    (.payload // {}) as $p |
    if ($p.type // "") == "message" then
      ($p.role // "") as $r |
      if $r != "user" and $r != "assistant" then empty
      else
        ($p.content // [] | if type == "array" then . else [] end)[] |
        if .type == "input_text" or .type == "output_text" then
          {role: $r, kind: "text", text: (.text // "")}
        else empty end
      end
    elif ($p.type // "") == "function_call" then
      {role: "assistant", kind: "tool", name: ($p.name // "")}
    else empty end
  else empty end;

def parts($h; $o):
  if $h == "cursor" then cursor_parts($o)
  elif $h == "claude" then claude_parts($o)
  elif $h == "codex" then codex_parts($o)
  else empty end;

def format_parts($parts):
  (reduce $parts[] as $p (
    {out: "", cur: ""};
    if $p.kind == "text" then
      if .cur != $p.role then
        .out = (.out + (if .out == "" then "" else "\n\n" end) + "## " + $p.role + "\n" + $p.text) | .cur = $p.role
      else
        .out = (.out + "\n" + $p.text)
      end
    elif $p.kind == "tool" then
      if .cur != $p.role then
        .out = (.out + (if .out == "" then "" else "\n\n" end) + "## " + $p.role + "\n[tool: " + $p.name + "]") | .cur = $p.role
      else
        .out = (.out + "\n[tool: " + $p.name + "]")
      end
    else .
    end
  )) | .out;

split("\n")
| map(select(length > 0))
| map(line_obj)
| map(select(. != null)) as $objs
| [ $objs[] | parts($harness; .) ] as $parts
| format_parts($parts)
JQEOF
}

capture_parse_transcript() { # <harness> <transcript> <jq-meta> <jq-body> <meta-out> <body-out> <first-user-out>
  local harness="$1" transcript="$2" jq_meta="$3" jq_body="$4" meta_out="$5" body_out="$6" fu_out="$7"
  local json_line parsed fu
  : > "$meta_out"
  : > "$body_out"
  : > "$fu_out"
  json_line="$(mk_tmp)"
  if ! jq -R -s -c --arg harness "$harness" -f "$jq_meta" "$transcript" > "$json_line" 2>/dev/null; then
    return 1
  fi
  if [ ! -s "$json_line" ]; then
    return 1
  fi
  parsed="$(jq -r '.parsed // 0' "$json_line" 2>/dev/null)" || return 1
  fu="$(jq -r '.first_user // ""' "$json_line" 2>/dev/null)" || return 1
  printf 'parsed=%s\n' "${parsed:-0}" >> "$meta_out"
  printf '%s' "$fu" > "$fu_out"
  if ! jq -R -s -r --arg harness "$harness" -f "$jq_body" "$transcript" > "$body_out" 2>/dev/null; then
    return 1
  fi
  return 0
}

capture_meta_get() { # <meta-file> <key>
  local meta="$1" key="$2"
  awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$meta"
}

capture_is_subagent() { # <first-user-text-file>
  local fu="$1" text line
  text="$(cat "$fu" 2>/dev/null || true)"
  case "$text" in
    *"Read and follow the context package"*) return 0 ;;
    *"Your full context package"*) return 0 ;;
    *"Re-check request"*) return 0 ;;
    *"-context.md"*) return 0 ;;
  esac
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "You are the "*subagent*) return 0 ;;
    esac
  done <<EOF
$text
EOF
  return 1
}

capture_since_out_of_range() { # <file> <since-ref-file>
  local f="$1" ref="$2"
  [ -n "$ref" ] && [ -f "$ref" ] || return 1
  if find "$f" -newer "$ref" 2>/dev/null | grep -q .; then
    return 1
  fi
  return 0
}

capture_is_idle() { # <file> <idle-hours>
  local f="$1" idle="$2"
  [ "$idle" -eq 0 ] && return 0
  find "$f" -mmin +$((idle * 60)) 2>/dev/null | grep -q .
}

capture_ledger_latest_sha() { # <ledger> <harness> <session>
  local ledger="$1" harness="$2" session="$3"
  [ -f "$ledger" ] || return 0
  awk -F'\t' -v h="$harness" -v s="$session" '
    $1 == h && $2 == s && NF >= 3 { sha = $3 }
    END { if (sha != "") print sha }
  ' "$ledger"
}

capture_ledger_append() { # <ledger> <harness> <session> <sha> <status> <ts>
  local ledger="$1"
  mkdir -p "$(dirname "$ledger")"
  printf '%s\n' "$2$TAB$3$TAB$4$TAB$5$TAB$6" >> "$ledger"
}

capture_session_id() { # <harness> <path>
  local harness="$1" path="$2" base
  base="$(basename "$path" .jsonl)"
  case "$harness" in
    codex)
      case "$base" in
        rollout-*) base="${base#rollout-}" ;;
      esac
      ;;
  esac
  printf '%s' "$base"
}

capture_codex_cwd() { # <transcript>
  local line
  line="$(grep -m1 '"type":"session_meta"' "$1" 2>/dev/null || true)"
  [ -n "$line" ] || return 1
  jq -r '.payload.cwd // empty' 2>/dev/null <<EOF
$line
EOF
}

capture_list_cursor() { # <dir> <out-list>
  local dir="$1" out="$2" f base parent_base finds
  : > "$out"
  [ -d "$dir" ] || return 0
  finds="$(mk_tmp)"
  find "$dir" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' > "$finds" 2>/dev/null || true
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    base="$(basename "$f" .jsonl)"
    parent_base="$(basename "$(dirname "$f")")"
    [ "$base" = "$parent_base" ] || continue
    printf '%s\n' "$f" >> "$out"
  done < "$finds"
}

capture_list_claude() { # <dir> <out-list>
  local dir="$1" out="$2"
  : > "$out"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null >> "$out" || true
}

capture_list_codex() { # <sessions-root> <root-abs> <out-list>
  local root_sessions="$1" root_abs="$2" out="$3" f cwd finds
  : > "$out"
  [ -d "$root_sessions" ] || return 0
  finds="$(mk_tmp)"
  find "$root_sessions" -type f -name 'rollout-*.jsonl' > "$finds" 2>/dev/null || true
  while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    cwd="$(capture_codex_cwd "$f")" || continue
    [ "$cwd" = "$root_abs" ] || continue
    printf '%s\n' "$f" >> "$out"
  done < "$finds"
}

capture_emit_skip() { # <harness> <session> <reason>
  printf 'memory: skipped %s %s %s\n' "$1" "$2" "$3"
}

capture_emit_captured() { # <harness> <session> <rel-path>
  printf 'memory: captured %s %s %s\n' "$1" "$2" "$3"
}

capture_home_dot_dir() { # <name: cursor|claude|codex>
  local n="$1" base="${HOME}/."
  base="${base}${n}"
  printf '%s' "$base"
}

capture_collect_sessions() { # <harness> <root-abs> <from-override> <out-list>
  local hh="$1" root_abs="$2" from_override="$3" dest="$4"
  local slug base_dir
  case "$hh" in
    cursor)
      if [ -n "$from_override" ]; then
        capture_list_cursor "$from_override" "$dest"
      else
        slug="$(capture_root_slug_s1 "$root_abs")"
        base_dir="$(capture_home_dot_dir cursor)/projects/${slug}/agent-transcripts"
        capture_list_cursor "$base_dir" "$dest"
      fi
      ;;
    claude)
      if [ -n "$from_override" ]; then
        capture_list_claude "$from_override" "$dest"
      else
        slug="$(capture_root_slug_s2 "$root_abs")"
        base_dir="$(capture_home_dot_dir claude)/projects/${slug}"
        capture_list_claude "$base_dir" "$dest"
      fi
      ;;
    codex)
      if [ -n "$from_override" ]; then
        capture_list_codex "$from_override" "$root_abs" "$dest"
      else
        base_dir="$(capture_home_dot_dir codex)/sessions"
        capture_list_codex "$base_dir" "$root_abs" "$dest"
      fi
      ;;
  esac
}

capture_process_one() { # <harness> <transcript> <root> <store> <idle> <since-ref> <ledger> <jq-meta> <jq-body>
  local harness="$1" transcript="$2" root="$3" store="$4" idle="$5" since_ref="$6" ledger="$7" jq_meta="$8" jq_body="$9"
  local session sha rel_out out_path meta fu body parsed scope ts latest
  local transcript_abs front raw_dir tmp_out
  session="$(capture_session_id "$harness" "$transcript")"
  transcript_abs="$(canonical_file_path "$transcript")" || transcript_abs="$transcript"
  sha="$(sha256_hex < "$transcript")"

  if [ -n "$since_ref" ] && capture_since_out_of_range "$transcript" "$since_ref"; then
    capture_emit_skip "$harness" "$session" out-of-range
    return 0
  fi
  if ! capture_is_idle "$transcript" "$idle"; then
    capture_emit_skip "$harness" "$session" live
    return 0
  fi

  latest="$(capture_ledger_latest_sha "$ledger" "$harness" "$session")"
  if [ -n "$latest" ] && [ "$latest" = "$sha" ]; then
    capture_emit_skip "$harness" "$session" unchanged
    return 0
  fi

  meta="$(mk_tmp)"
  fu="$(mk_tmp)"
  body="$(mk_tmp)"
  if ! capture_parse_transcript "$harness" "$transcript" "$jq_meta" "$jq_body" "$meta" "$body" "$fu"; then
    capture_emit_skip "$harness" "$session" unreadable
    ts="$(utc_now_id_prefix)"
    capture_ledger_append "$ledger" "$harness" "$session" "$sha" unreadable "$ts"
    return 0
  fi
  parsed="$(capture_meta_get "$meta" parsed)"
  parsed="${parsed:-0}"
  if [ "$parsed" -eq 0 ] 2>/dev/null; then
    capture_emit_skip "$harness" "$session" unreadable
    ts="$(utc_now_id_prefix)"
    capture_ledger_append "$ledger" "$harness" "$session" "$sha" unreadable "$ts"
    return 0
  fi
  if capture_is_subagent "$fu"; then
    capture_emit_skip "$harness" "$session" subagent
    ts="$(utc_now_id_prefix)"
    capture_ledger_append "$ledger" "$harness" "$session" "$sha" subagent "$ts"
    return 0
  fi

  scope="$(capture_scope_from_file "$transcript" "$root")"
  ts="$(utc_now_id_prefix)"
  rel_out="_memory/raw/${harness}/${session}.md"
  out_path="$store/raw/$harness/$session.md"
  raw_dir="$store/raw/$harness"
  mkdir -p "$raw_dir"
  front="$(mk_tmp)"
  {
    printf '%s\n' '---'
    printf 'session: %s\n' "$session"
    printf 'harness: %s\n' "$harness"
    printf 'transcript: %s\n' "$transcript_abs"
    printf 'sha256: %s\n' "$sha"
    printf 'captured: %s\n' "$ts"
    printf 'scope: %s\n' "$scope"
    printf '%s\n' '---'
    cat "$body"
  } > "$front"
  tmp_out="$raw_dir/.${session}.md.tmp.$$"
  memory_redact_file "$front" "$tmp_out" 1 1
  mv "$tmp_out" "$out_path"
  capture_emit_captured "$harness" "$session" "$rel_out"
  capture_ledger_append "$ledger" "$harness" "$session" "$sha" captured "$ts"
  return 0
}

cmd_capture() {
  local root="" harness="all" from="" idle_hours=6 since="" seen_root=0 seen_harness=0 seen_from=0 seen_idle=0 seen_since=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --harness) need_val "$@"; [ "$seen_harness" -eq 0 ] || die 2 "repeated flag '--harness'"; seen_harness=1; harness="$2"; shift 2 ;;
      --from) need_val "$@"; [ "$seen_from" -eq 0 ] || die 2 "repeated flag '--from'"; seen_from=1; from="$2"; shift 2 ;;
      --idle-hours) need_val "$@"; [ "$seen_idle" -eq 0 ] || die 2 "repeated flag '--idle-hours'"; seen_idle=1; idle_hours="$2"; shift 2 ;;
      --since) need_val "$@"; [ "$seen_since" -eq 0 ] || die 2 "repeated flag '--since'"; seen_since=1; since="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done

  capture_valid_harness_name "$harness" || die 2 "invalid --harness"
  if [ -n "$from" ] && [ "$harness" = "all" ]; then
    die 2 "capture --from needs a single --harness"
  fi
  if [ "$seen_idle" -eq 1 ]; then
    idle_hours="$(capture_validate_idle_hours "$idle_hours")"
  fi
  if [ "$seen_since" -eq 1 ]; then
    capture_validate_since_date "$since"
  fi
  command -v jq >/dev/null 2>&1 || die 4 "capture needs jq"
  if [ -z "$from" ]; then
    [ -n "${HOME:-}" ] || die 4 "HOME is not set"
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  root="$(canonical_dir "$root")" || die 4 "root directory not found: $root"
  have_sha256 || die 4 "no sha256 tool"

  local store ledger jq_meta jq_body list_file work sorted h sid f since_ref ymd
  store="$(store_dir "$root")"
  if [ -d "$store" ]; then
    store="$(canonical_dir "$store")" || store="$(store_dir "$root")"
  fi
  ledger="$store/raw/.captured"
  since_ref=""
  if [ -n "$since" ]; then
    since_ref="$(mk_tmp)"
    ymd="${since//-/}"
    touch -t "${ymd}0000" "$since_ref" 2>/dev/null || die 2 "invalid --since"
  fi
  jq_meta="$(mk_tmp)"
  jq_body="$(mk_tmp)"
  capture_write_jq_filter_meta "$jq_meta"
  capture_write_jq_filter_body "$jq_body"
  list_file="$(mk_tmp)"
  work="$(mk_tmp)"
  : > "$work"

  # Work rows: <harness-ordinal> TAB <harness> TAB <session> TAB <path>. The ordinal
  # (cursor=1, claude=2, codex=3) fixes harness order; the sort then orders by session id.
  local ord
  if [ "$harness" = "all" ]; then
    for h in cursor claude codex; do
      case "$h" in cursor) ord=1 ;; claude) ord=2 ;; *) ord=3 ;; esac
      capture_collect_sessions "$h" "$root" "$from" "$list_file"
      while IFS= read -r f || [ -n "$f" ]; do
        [ -n "$f" ] || continue
        sid="$(capture_session_id "$h" "$f")"
        printf '%s\t%s\t%s\t%s\n' "$ord" "$h" "$sid" "$f" >> "$work"
      done < "$list_file"
    done
  else
    case "$harness" in cursor) ord=1 ;; claude) ord=2 ;; *) ord=3 ;; esac
    capture_collect_sessions "$harness" "$root" "$from" "$list_file"
    while IFS= read -r f || [ -n "$f" ]; do
      [ -n "$f" ] || continue
      sid="$(capture_session_id "$harness" "$f")"
      printf '%s\t%s\t%s\t%s\n' "$ord" "$harness" "$sid" "$f" >> "$work"
    done < "$list_file"
  fi
  sorted="$(mk_tmp)"
  LC_ALL=C sort -t "$TAB" -k1,1 -k3,3 -k4,4 "$work" > "$sorted"
  while IFS="$TAB" read -r ord h sid f || [ -n "$h" ]; do
    [ -n "$f" ] || continue
    capture_process_one "$h" "$f" "$root" "$store" "$idle_hours" "$since_ref" "$ledger" "$jq_meta" "$jq_body"
  done < "$sorted"
  exit 0
}

cmd_rm() {
  local root="" id="" seen_root=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *)
        [ -z "$id" ] || die 2 "unexpected argument '$1'"
        id="$1"
        shift
        ;;
    esac
  done
  [ -n "$id" ] || die 2 "'rm' requires id"
  re_match "$id" "$re_id" || die 2 "invalid id"
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 4 "rm needs a git work tree"
  local store rec q path rel ls_rc
  store="$(store_dir "$root")"
  rec="$(id_to_record_path "$store" "$id")"
  q="$(id_to_quarantine_path "$store" "$id")"
  if [ -f "$rec" ]; then
    path="$rec"
  elif [ -f "$q" ]; then
    path="$q"
  else
    die 4 "record not found: $id"
  fi
  rel="$(relpath_under_root "$root" "$path")"
  ls_rc=0
  git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || ls_rc=$?
  if [ "$ls_rc" -eq 0 ]; then
    die 2 "record is tracked; add a superseding record instead"
  fi
  if [ "$ls_rc" -ne 1 ]; then
    die 4 "rm: git ls-files failed"
  fi
  rm -f "$path"
  printf 'memory: removed %s %s\n' "$id" "$rel"
  exit 0
}

cmd_show() {
  local root="" id="" seen_root=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *)
        [ -z "$id" ] || die 2 "unexpected argument '$1'"
        id="$1"
        shift
        ;;
    esac
  done
  [ -n "$id" ] || die 2 "'show' requires id"
  re_match "$id" "$re_id" || die 2 "invalid id"
  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  local store rec q
  store="$(store_dir "$root")"
  rec="$(id_to_record_path "$store" "$id")"
  q="$(id_to_quarantine_path "$store" "$id")"
  if [ -f "$rec" ]; then
    cat "$rec"
    exit 0
  fi
  if [ -f "$q" ]; then
    cat "$q"
    exit 0
  fi
  die 4 "record not found: $id"
}

cmd_search() {
  local root="" kind_raw="" limit="10" engine="grep" include_sup=0
  local seen_root=0 seen_kind=0 seen_limit=0 seen_engine=0 seen_include=0
  local parsing_flags=1

  TERMS=()
  while [ $# -gt 0 ]; do
    if [ "$parsing_flags" -eq 1 ]; then
      case "$1" in
        --) parsing_flags=0; shift; continue ;;
        --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
        --kind) need_val "$@"; [ "$seen_kind" -eq 0 ] || die 2 "repeated flag '--kind'"; seen_kind=1; kind_raw="$2"; shift 2 ;;
        --limit) need_val "$@"; [ "$seen_limit" -eq 0 ] || die 2 "repeated flag '--limit'"; seen_limit=1; limit="$2"; shift 2 ;;
        --engine) need_val "$@"; [ "$seen_engine" -eq 0 ] || die 2 "repeated flag '--engine'"; seen_engine=1; engine="$2"; shift 2 ;;
        --include-superseded) [ "$seen_include" -eq 0 ] || die 2 "repeated flag '--include-superseded'"; seen_include=1; include_sup=1; shift ;;
        --*) die 2 "unknown flag '$1'" ;;
        *) TERMS[${#TERMS[@]}]="$1"; shift ;;
      esac
    else
      TERMS[${#TERMS[@]}]="$1"
      shift
    fi
  done

  if [ ${#TERMS[@]} -eq 0 ]; then
    die 2 "search requires at least one term"
  fi
  for t in "${TERMS[@]}"; do
    [ -n "$t" ] || die 2 "empty search term"
  done

  re_match "$limit" "$re_limit" || die 2 "invalid --limit"
  [ "${#limit}" -le 3 ] || die 2 "invalid --limit"
  [ "$limit" -le 100 ] || die 2 "invalid --limit"

  case "$engine" in
    grep|fts) ;;
    *) die 2 "invalid --engine" ;;
  esac

  local kind_filter=""
  if [ "$seen_kind" -eq 1 ]; then
    parse_list "$kind_raw" kind || die 2 "invalid --kind"
    kind_filter="$PARSED_LIST_ITEMS"
    [ -n "$kind_filter" ] || die 2 "invalid --kind"
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"

  if index_is_stale "$root"; then
    run_index "$root" 1
  fi

  local store man
  store="$(store_dir "$root")"
  man="$store/.index/manifest.tsv"
  [ -f "$man" ] || run_index "$root" 1

  if [ "$engine" = "fts" ]; then
    fts5_available || die 4 "fts engine unavailable"
    [ -f "$store/.index/fts.db" ] || die 4 "fts engine unavailable"
  fi

  local cand="$(mk_tmp)" i=0 ti
  export MEM_NTERMS="${#TERMS[@]}"
  for ti in "${TERMS[@]}"; do
    i=$((i + 1))
    export "MEMTERM_$i=$ti"
  done
  export MEM_AWK_ROOT="$root"
  export MEM_INCLUDE_SUP="$include_sup"
  export MEM_AWK_KINDS="$kind_filter"
  tail -n +2 "$man" | awk -F'\t' '
    function foldline(s,    i, ch, out) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (ch >= "A" && ch <= "Z") ch = tolower(ch)
        out = out ch
      }
      return out
    }
    function fm_value(line,    p) {
      p = index(line, ": ")
      if (p > 0) return substr(line, p + 2)
      return line
    }
    function fm_strip_quotes(val) {
      if (substr(val, 1, 1) == "\042") val = substr(val, 2)
      if (length(val) > 0 && substr(val, length(val), 1) == "\042") val = substr(val, 1, length(val) - 1)
      return val
    }
    function trim_sp(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    function brackets_csv(raw,    s, n, parts, i, item, out) {
      s = raw
      sub(/^\[/, "", s)
      sub(/\]$/, "", s)
      if (s == "") return ""
      n = split(s, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        item = trim_sp(parts[i])
        if (item == "") continue
        if (out != "") out = out "," item
        else out = item
      }
      return out
    }
    function fm_ok(got) {
      return got["id"] && got["kind"] && got["title"] && got["date"] && got["source"] &&
        got["commit"] && got["harness"] && got["tags"] && got["supersedes"] && got["sha256"]
    }
    function kind_ok(k,    n, i, ka, kinds) {
      kinds = ENVIRON["MEM_AWK_KINDS"]
      if (kinds == "") return 1
      n = split(kinds, ka, " ")
      for (i = 1; i <= n; i++) if (ka[i] == k) return 1
      return 0
    }
    function meta_hit(title, tags_csv, term_f,    title_f, n, parts, i, tag_f) {
      title_f = foldline(title)
      if (index(title_f, term_f) > 0) return 1
      if (tags_csv == "") return 0
      n = split(tags_csv, parts, ",")
      for (i = 1; i <= n; i++) {
        tag_f = foldline(trim_sp(parts[i]))
        if (index(tag_f, term_f) > 0) return 1
      }
      return 0
    }
    function score_file(path,    line, key, val, c, closed, got, fm_title, fm_tags_raw, tags_csv, total, ti, term_f, bh, line_f, fi) {
      split("", got)
      c = 0
      closed = 0
      fm_title = ""
      fm_tags_raw = ""
      for (ti = 1; ti <= nt; ti++) bh[ti] = 0
      while ((getline line < path) > 0) {
        sub(/\r$/, "", line)
        if (c == 0) {
          if (line != "---") { close(path); return -1 }
          c = 1
          continue
        }
        if (c == 1) {
          if (line == "---") { closed = 1; c = 2; continue }
          key = line
          sub(/:.*/, "", key)
          val = fm_value(line)
          if (key == "title" || key == "source" || key == "harness") val = fm_strip_quotes(val)
          if (key == "id") got["id"] = 1
          else if (key == "kind") got["kind"] = 1
          else if (key == "title") { fm_title = val; got["title"] = 1 }
          else if (key == "date") got["date"] = 1
          else if (key == "source") got["source"] = 1
          else if (key == "commit") got["commit"] = 1
          else if (key == "harness") got["harness"] = 1
          else if (key == "tags") { fm_tags_raw = val; got["tags"] = 1 }
          else if (key == "supersedes") got["supersedes"] = 1
          else if (key == "sha256") got["sha256"] = 1
          continue
        }
        line_f = foldline(line)
        for (ti = 1; ti <= nt; ti++) {
          if (index(line_f, terms[ti]) > 0) bh[ti]++
        }
      }
      close(path)
      if (c == 0 || !closed || !fm_ok(got)) return -1
      tags_csv = brackets_csv(fm_tags_raw)
      total = 0
      for (ti = 1; ti <= nt; ti++) {
        term_f = terms[ti]
        if (meta_hit(fm_title, tags_csv, term_f)) total += 3
        total += bh[ti]
      }
      return total
    }
    BEGIN {
      nt = ENVIRON["MEM_NTERMS"] + 0
      for (i = 1; i <= nt; i++) {
        terms[i] = ENVIRON["MEMTERM_" i]
        terms[i] = foldline(terms[i])
      }
    }
    {
      rid = $1
      rkind = $2
      rdate = $3
      rtitle = $4
      rtags = $5
      rpath = $6
      rsup = $7
      rsby = $8
      for (fi = 9; fi <= NF; fi++) rsby = rsby "\t" $fi
      include_sup = ENVIRON["MEM_INCLUDE_SUP"] + 0
      if (include_sup == 0 && rsby != "") next
      if (!kind_ok(rkind)) next
      fpath = ENVIRON["MEM_AWK_ROOT"] "/" rpath
      score = score_file(fpath)
      if (score < 0) next
      if (score + 0 <= 0) next
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", rid, rkind, rdate, score, rtitle, rpath, score
    }
  ' > "$cand"

  if [ ! -s "$cand" ]; then
    die 0 "0 results"
  fi

  local out sorted ranked
  out="$(mk_tmp)"
  if [ "$engine" = "grep" ]; then
    sorted="$(mk_tmp)"
    sort -t '	' -k4,4nr -k1,1r "$cand" > "$sorted"
    head -n "$limit" "$sorted" | awk -F'\t' 'NF >= 6 {
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6
    }' > "$out"
  else
    local match_parts="" term esc sql qfile
    for term in "${TERMS[@]}"; do
      esc="$(printf '%s' "$term" | sed 's/"/""/g')"
      match_parts="${match_parts}${match_parts:+ OR }\"$esc\""
    done
    sql="$(mk_tmp)"
    qfile="$(mk_tmp)"
    {
      printf "SELECT id, bm25(records) FROM records WHERE records MATCH '%s';\n" "$(sql_escape_sq "$match_parts")"
    } > "$sql"
    if sqlite3 -batch -init /dev/null -noheader -separator "$TAB" "$store/.index/fts.db" < "$sql" > "$qfile" 2>/dev/null; then
      :
    else
      : > "$qfile"
    fi
    ranked="$(mk_tmp)"
    export MEM_AWK_QFILE="$qfile"
    awk -F'\t' '
      BEGIN {
        qf = ENVIRON["MEM_AWK_QFILE"]
        while ((getline line < qf) > 0) {
          split(line, f, "\t")
          k = f[1] ""
          if (!(k in bm)) bm[k] = f[2]
        }
        close(qf)
      }
      {
        cid = $1 ""
        if (cid in bm) printf "0\t%s\t%s\n", bm[cid], $0
        else printf "1\t0\t%s\n", $0
      }
    ' "$cand" > "$ranked"
    sorted="$(mk_tmp)"
    sort -t '	' -k1,1n -k2,2g -k3,3r "$ranked" > "$sorted"
    head -n "$limit" "$sorted" | awk -F'\t' 'NF >= 8 {
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $3, $4, $5, $6, $7, $8
    }' > "$out"
  fi

  if [ ! -s "$out" ]; then
    die 0 "0 results"
  fi
  cat "$out"
  exit 0
}


# --- backfill (Release D) ---

backfill_cut_utf8_bytes() { # <in-file> <out-file> <max-bytes>
  # Cut at <max-bytes>, then drop a trailing incomplete UTF-8 sequence (lead byte 0xC0-0xF7
  # followed by fewer continuation bytes than it needs). ASCII and complete sequences are kept.
  # Pure byte logic (od + awk under LC_ALL=C); no external UTF-8 tooling.
  local in="$1" out="$2" max="$3" tmp len drop
  len="$(wc -c < "$in" | tr -d '[:space:]')"
  if [ "$len" -le "$max" ]; then cp "$in" "$out"; return 0; fi
  tmp="$(mk_tmp)"
  head -c "$max" "$in" > "$tmp"
  drop="$(tail -c 4 "$tmp" | od -An -v -tu1 | awk '
    { for (i = 1; i <= NF; i++) b[++n] = $i + 0 }
    END {
      for (j = 1; j <= n && j <= 4; j++) {
        v = b[n - j + 1]
        if (v < 128) break
        if (v < 192) continue
        need = (v < 224) ? 2 : (v < 240) ? 3 : (v < 248) ? 4 : 0
        if (need > 0 && j < need) { print j; exit }
        break
      }
      print 0
    }
  ' | head -n 1)"
  case "$drop" in 1|2|3) ;; *) drop=0 ;; esac
  if [ "$drop" -gt 0 ]; then
    head -c $((max - drop)) "$tmp" > "$out"
  else
    cp "$tmp" "$out"
  fi
}

backfill_sanitize_title() { # <text> <fallback> → stdout
  local t="$1" fb="$2" tmp outf
  tmp="$(mk_tmp)"
  printf '%s' "$t" | sed 's/"/'"'"'/g;s/\\/\//g' | tr '\000-\037\177' ' ' > "$tmp"
  t="$(trim_ascii_sp "$(cat "$tmp")")"
  [ -n "$t" ] || t="$fb"
  outf="$(mk_tmp)"
  printf '%s' "$t" > "$tmp"
  backfill_cut_utf8_bytes "$tmp" "$outf" 120
  cat "$outf"
}

backfill_ts_to_id_prefix() { # <ts> → stdout YYYYMMDDTHHMM00Z
  local ts="$1"
  re_match "$ts" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$' || {
    printf '19700101T000000Z\n'
    return
  }
  export BF_Y="${ts:0:4}" BF_MO="${ts:5:2}" BF_D="${ts:8:2}" BF_H="${ts:11:2}" BF_MI="${ts:14:2}"
  export BF_SGN="${ts:16:1}" BF_OH="${ts:17:2}" BF_OM="${ts:20:2}"
  awk '
    function is_leap(y) { return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0) }
    function dim(y, m) {
      if (m == 2) return is_leap(y) ? 29 : 28
      if (m == 4 || m == 6 || m == 9 || m == 11) return 30
      return 31
    }
    function civil_to_days(y, m, d,    i, x) {
      x = 365 * (y - 1) + int((y - 1) / 4) - int((y - 1) / 100) + int((y - 1) / 400)
      for (i = 1; i < m; i++) x += dim(y, i)
      return x + d - 1
    }
    function days_to_ymd(z,    y, m, d) {
      for (y = 1; y <= 9999; y++) {
        if (z < civil_to_days(y + 1, 1, 1)) break
      }
      for (m = 12; m >= 1; m--) {
        if (z >= civil_to_days(y, m, 1)) break
      }
      d = z - civil_to_days(y, m, 1) + 1
      return y SUBSEP m SUBSEP d
    }
    function pad2(n) { return (n < 10 ? "0" : "") n }
    BEGIN {
      y = ENVIRON["BF_Y"] + 0; mo = ENVIRON["BF_MO"] + 0; d = ENVIRON["BF_D"] + 0
      h = ENVIRON["BF_H"] + 0; mi = ENVIRON["BF_MI"] + 0
      sgn = ENVIRON["BF_SGN"]; oh = ENVIRON["BF_OH"] + 0; om = ENVIRON["BF_OM"] + 0
      off = oh * 60 + om; if (sgn == "-") off = -off
      total_local = civil_to_days(y, mo, d) * 1440 + h * 60 + mi
      total_utc = total_local - off
      z = int(total_utc / 1440)
      utc_min = total_utc - z * 1440
      if (utc_min < 0) { utc_min += 1440; z-- }
      split(days_to_ymd(z), p, SUBSEP)
      printf "%s%s%sT%s%s00Z", p[1], pad2(p[2]), pad2(p[3]), pad2(int(utc_min / 60)), pad2(utc_min % 60)
    }
  '
}

backfill_utc_date_from_prefix() { # <YYYYMMDDTHHMM00Z>
  local p="$1"
  printf '%s-%s-%s' "${p:0:4}" "${p:4:2}" "${p:6:2}"
}

backfill_source_exists() { # <store> <source>
  local store="$1" want="$2" list f
  list="$(mk_tmp)"
  glob_dedupe_files "$store" "$list"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_frontmatter "$f" || continue
    [ "$FM_SOURCE" = "$want" ] && return 0
  done < "$list"
  return 1
}

backfill_heading_ts() { # <### heading line> → stdout ts or empty
  printf '%s\n' "$1" | LC_ALL=C sed -n 's/^### \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9][+-][0-9][0-9]:[0-9][0-9]\).*/\1/p' | head -n 1
}

backfill_id_in_store() { # <store> <id>
  local store="$1" id="$2"
  [ -f "$(id_to_record_path "$store" "$id")" ] && return 0
  [ -f "$(id_to_quarantine_path "$store" "$id")" ] && return 0
  return 1
}

backfill_goal_status() { # <root> <store> <goal> <only_hit:0|1> → prints 3 lines: status, ts, verdict
  local root="$1" store="$2" g="$3" only_hit="$4"
  local log="$root/_memory/work/goals/$g/orchestration-log.md" line last_spawn="" ts="" verdict="" last_note="" any_ts=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if printf '%s\n' "$line" | LC_ALL=C grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}' 2>/dev/null; then
      ts_part="$(backfill_heading_ts "$line")"
      [ -n "$ts_part" ] && any_ts="$ts_part"
      if printf '%s\n' "$line" | LC_ALL=C grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} — SPAWN evaluator \(Phase 5' 2>/dev/null; then
        last_spawn="$line"
      elif printf '%s\n' "$line" | LC_ALL=C grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} — Phase 5 APPROVED' 2>/dev/null; then
        last_note="$line"
      fi
    fi
  done < "$log"
  if [ -n "$last_spawn" ]; then
    local num vline
    ts_part="$(backfill_heading_ts "$last_spawn")"
    num="${last_spawn##*[#}"
    num="${num%]}"
    vline="$(awk -v n="$num" '
      index($0, "- OUTCOME [#" n "]: ") == 1 {
        v = $0
        sub(/^- OUTCOME \[#[0-9]+\]: /, "", v)
        sub(/ · model reported:.*/, "", v)
        print v
        exit
      }
    ' "$log")"
    case "$vline" in
      APPROVED*)
        ts="$ts_part"
        verdict="$vline"
        ;;
    esac
  fi
  if [ -z "$verdict" ] && [ -n "$last_note" ]; then
    ts="$(backfill_heading_ts "$last_note")"
    verdict="${last_note#* — }"
    [ -n "$verdict" ] || verdict="Phase 5 APPROVED"
  fi
  if [ -z "$verdict" ] && [ "$only_hit" = "1" ]; then
    ts="$any_ts"
    verdict="opted in with --only"
  fi
  if [ -n "$verdict" ]; then
    printf 'would-add\n%s\n%s\n' "$ts" "$verdict"
  else
    printf 'skip:open\n\n\n'
  fi
}

backfill_goal_archived_p() { # <root> <store> <goal>
  local root="$1" store="$2" g="$3" log="$root/_memory/work/goals/$g/orchestration-log.md" line rest id
  backfill_source_exists "$store" "goal $g (goal.md)" && return 0
  backfill_source_exists "$store" "_goals/$g/goal.md" && return 0
  backfill_source_exists "$store" "_memory/work/goals/$g/goal.md" && return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if printf '%s\n' "$line" | LC_ALL=C grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} — ARCHIVED:' 2>/dev/null; then
      rest="${line#*ARCHIVED:}"
      rest="$(trim_ascii_sp "$rest")"
      for id in $rest; do
        backfill_id_in_store "$store" "$id" && return 0
      done
    fi
  done < "$log"
  return 1
}

backfill_build_goal_body() { # <root> <goal> <verdict> <utc-date> <out-file>
  local root="$1" g="$2" verdict="$3" udate="$4" out="$5" goal="$root/_memory/work/goals/$g/goal.md"
  export BF_GOAL_MD="$goal" BF_G="$g" BF_VERDICT="$verdict" BF_UDATE="$udate" BF_FU="$root/_memory/work/goals/$g/follow-ups.md"
  awk '
    BEGIN {
      gm = ENVIRON["BF_GOAL_MD"]; g = ENVIRON["BF_G"]; fu = ENVIRON["BF_FU"]
      verdict = ENVIRON["BF_VERDICT"]; udate = ENVIRON["BF_UDATE"]
      prob = ""; in_prob = 0; in_sc = 0; sc = ""; last_sc = ""
      while ((getline line < gm) > 0) {
        sub(/\r$/, "", line)
        if (line ~ /^## Problem Statement/) { in_prob = 1; in_sc = 0; continue }
        if (line ~ /^## /) {
          if (in_sc && last_sc != "") { sc = sc "- " last_sc "\n"; last_sc = "" }
          in_prob = 0; in_sc = 0
        }
        if (line ~ /^## Success Criteria/) {
          if (last_sc != "") { sc = sc "- " last_sc "\n"; last_sc = "" }
          in_sc = 1; in_prob = 0; continue
        }
        if (in_prob) {
          if (line ~ /^[[:space:]]*$/) { if (prob != "") in_prob = 0; continue }
          if (prob == "") prob = line; else prob = prob " " line
        }
        if (in_sc && line ~ /^- \[[ xX]\] /) {
          if (last_sc != "") sc = sc "- " last_sc "\n"
          t = line; sub(/^- \[[ xX]\] /, "", t)
          last_sc = t
        } else if (in_sc && line ~ /^[[:space:]]+/ && last_sc != "") {
          sub(/^[[:space:]]+/, "", line)
          if (line != "") last_sc = last_sc " " line
        }
      }
      close(gm)
      if (last_sc != "") sc = sc "- " last_sc "\n"
      printf "Goal %s — back-filled from goal.md and orchestration-log.md.\n\n", g
      if (prob != "") printf "Problem: %s\n\n", prob
      if (sc != "") { printf "Success criteria:\n%s\n", sc }
      printf "Final verdict: %s (%s)\n\n", verdict, udate
      n = 0; fu_lines = ""
      while ((getline line < fu) > 0) {
        sub(/\r$/, "", line)
        if (line !~ /^[[:space:]]*$/) { fu_lines = fu_lines line "\n"; n++ }
        if (n >= 20) break
      }
      close(fu)
      if (n > 0) { printf "Follow-ups:\n%s", fu_lines }
    }
  ' > "$out"
}

backfill_prepare_body() { # <raw-body-file> <out-file>
  local raw="$1" out="$2" norm red trunc ell='…'
  norm="$(mk_tmp)"; red="$(mk_tmp)"; trunc="$(mk_tmp)"
  normalize_body_file "$raw" "$norm" || return 1
  memory_redact_file "$norm" "$red" 1 1
  local len max=4096 elen
  elen="$(printf '%s\n' "$ell" | wc -c | tr -d '[:space:]')"
  len="$(wc -c < "$red" | tr -d '[:space:]')"
  if [ "$len" -le "$max" ]; then cp "$red" "$out"; return 0; fi
  local budget=$((max - elen - 1)) partial line1f cutf
  partial="$(mk_tmp)"; line1f="$(mk_tmp)"; cutf="$(mk_tmp)"
  awk -v budget="$budget" '
    { lines[++n] = $0 }
    END {
      out = ""; used = 0
      for (i = 1; i <= n; i++) {
        need = length(lines[i]) + (out == "" ? 0 : 1)
        if (used + need > budget) break
        if (out == "") out = lines[i]; else out = out "\n" lines[i]
        used += need
      }
      if (out != "") print out
    }
  ' "$red" > "$partial"
  if [ ! -s "$partial" ]; then
    head -n 1 "$red" > "$line1f"
    backfill_cut_utf8_bytes "$line1f" "$cutf" "$budget"
    { cat "$cutf"; printf '\n%s\n' "$ell"; } > "$trunc"
  else
    { cat "$partial"; printf '%s\n' "$ell"; } > "$trunc"
  fi
  normalize_body_file "$trunc" "$out" || return 1
}

backfill_run_add() { # <root> <kind> <title> <body> <source> <tags> <id_prefix> → sets BF_ADD_LINE BF_ADD_RC; stderr passed
  local root="$1" kind="$2" title="$3" body="$4" source="$5" tags="$6" id_prefix="$7"
  local script out err rc first
  script="${BASH_SOURCE[0]:-$0}"
  script="$(cd "$(dirname "$script")" && pwd)/$(basename "$script")"
  out="$(mk_tmp)"; err="$(mk_tmp)"
  rc=0
  MEMORY_NOW="$id_prefix" bash "$script" add --kind "$kind" --title "$title" --body "$body" \
    --source "$source" --tags "$tags" --root "$root" >"$out" 2>"$err" || rc=$?
  BF_ADD_RC="$rc"
  BF_ADD_LINE="$(head -n 1 "$out" | tr -d '\r')"
  BF_ADD_ERR_FIRST="$(head -n 1 "$err" | tr -d '\r')"
  cat "$err" >&2
}

backfill_goal_tags() { # <goal> → stdout
  local g="$1"
  if re_match "$g" "$re_tag"; then printf 'backfill %s' "$g"; else printf 'backfill'; fi
}

backfill_research_status() { # <root> <store> <topic> <only_hit>
  local root="$1" store="$2" t="$3" only_hit="$4"
  [ -f "$root/_memory/work/research/$t/ingested" ] && { printf 'skip:archived'; return; }
  backfill_source_exists "$store" "research $t (report.md)" && { printf 'skip:archived'; return; }
  [ "$only_hit" = "1" ] && { printf 'would-add'; return; }
  printf 'skip:not-selected'
}

backfill_research_ts() { # <report.md>
  awk '
    /^\*\*Date\*\*: / {
      v = $0; sub(/^\*\*Date\*\*: /, "", v)
      sub(/ · .*/, "", v)
      sub(/\r$/, "", v)
      if (v ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
        gsub(/-/, "", v)
        print v "T120000Z"
        found = 1
        exit
      }
    }
    END { if (!found) print "19700101T000000Z" }
  ' "$1"
}

backfill_add_body_sha() { # <raw-body-file> → stdout sha256 hex of body as cmd_add would hash it
  local raw="$1" prep norm red len
  prep="$(mk_tmp)"
  backfill_prepare_body "$raw" "$prep" || return 1
  norm="$(mk_tmp)"
  red="$(mk_tmp)"
  normalize_body_file "$prep" "$norm" || return 1
  memory_redact_file "$norm" "$red" 1
  len="$(wc -c < "$red" | tr -d '[:space:]')"
  [ "$len" -ge 1 ] && [ "$len" -le 4096 ] || return 1
  sha256_hex < "$red"
}

backfill_body_sha_in_store_p() { # <store> <sha256-hex>
  local store="$1" want="$2" list f
  list="$(mk_tmp)"
  glob_dedupe_files "$store" "$list"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_frontmatter "$f" || continue
    [ "$FM_SHA256" = "$want" ] && return 0
  done < "$list"
  return 1
}

backfill_escalation_status() { # <store> <raw-body-file> <resolved-date-or-empty>
  local store="$1" raw="$2" resd="$3" sha raw_apply
  if [ -z "$resd" ]; then
    printf 'skip:open'
    return 0
  fi
  re_match "$resd" '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' && gregorian_date_valid_p "$resd" || {
    printf 'skip:bad-date'
    return 0
  }
  if have_sha256; then
    raw_apply="$(mk_tmp)"
    printf '%s' "$(cat "$raw")" > "$raw_apply"
    sha="$(backfill_add_body_sha "$raw_apply")" || sha=""
    if [ -n "$sha" ] && backfill_body_sha_in_store_p "$store" "$sha"; then
      printf 'skip:archived'
      return 0
    fi
  fi
  printf 'would-add'
}

backfill_build_research_body() { # <root> <topic> <out>
  local root="$1"
  local topic="$2"
  local out="$3"
  local rp="$root/_memory/work/research/$topic/report.md"
  local part
  part="$(mk_tmp)"
  awk '
    /^## Summary of Findings/ { inf = 1; next }
    inf && /^## / { exit }
    inf { lines[++n] = $0 }
    END {
      start = 1; end = n
      while (start <= end && lines[start] ~ /^[[:space:]]*$/) start++
      while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
      for (i = start; i <= end; i++) print lines[i]
    }
  ' "$rp" > "$part"
  {
    printf 'Research %s — back-filled from report.md.\n\n' "$topic"
    [ -s "$part" ] && cat "$part"
  } > "$out"
}

cmd_backfill() {
  local root="" mode="plan" do_goals=1 do_research=1 do_esc=1
  local seen_root=0 seen_plan=0 seen_apply=0 seen_goals=0 seen_research=0 seen_esc=0
  local only_raw="" only_items=""
  local w=0 s=0 a=0 d=0 q=0 f=0 exit_rc=0
  local only_goal="" only_topic="" only_name g t

  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --plan) [ "$seen_apply" -eq 0 ] || die 2 "backfill takes --plan or --apply, not both"; seen_plan=1; mode="plan"; shift ;;
      --apply) [ "$seen_plan" -eq 0 ] || die 2 "backfill takes --plan or --apply, not both"; seen_apply=1; mode="apply"; shift ;;
      --goals) [ "$seen_goals" -eq 0 ] || die 2 "repeated flag '--goals'"; seen_goals=1; do_goals=1; shift ;;
      --research) [ "$seen_research" -eq 0 ] || die 2 "repeated flag '--research'"; seen_research=1; do_research=1; shift ;;
      --escalations) [ "$seen_esc" -eq 0 ] || die 2 "repeated flag '--escalations'"; seen_esc=1; do_esc=1; shift ;;
      --only) need_val "$@"; only_raw="${only_raw}${only_raw:+$NL}$2"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done

  if [ "$seen_goals" -eq 1 ] || [ "$seen_research" -eq 1 ] || [ "$seen_esc" -eq 1 ]; then
    do_goals=0; do_research=0; do_esc=0
    [ "$seen_goals" -eq 1 ] && do_goals=1
    [ "$seen_research" -eq 1 ] && do_research=1
    [ "$seen_esc" -eq 1 ] && do_esc=1
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  local store goals_dir="$root/_memory/work/goals" research_dir="$root/_memory/work/research"
  store="$(store_dir "$root")"

  if [ -n "$only_raw" ]; then
    only_items="$(printf '%s' "$only_raw" | tr '\n' ' ')"
  fi

  backfill_emit_plan_or_apply() {
    local kind="$1" name="$2" status="$3" ts="$4" verdict="$5"
    local title source tags id_prefix udate raw_body prep_body title_s esc_file
    if [ "$status" = "would-add" ] && [ "$mode" = "plan" ]; then
      printf 'memory: backfill %s %s would-add\n' "$kind" "$name"
      w=$((w + 1))
      return 0
    fi
    if [ "${status#skip:}" != "$status" ]; then
      printf 'memory: backfill %s %s %s\n' "$kind" "$name" "$status"
      s=$((s + 1))
      return 0
    fi
    if [ "$mode" = "plan" ]; then return 0; fi
    case "$kind" in
      goal)
        title="${name}: back-filled goal summary"
        source="goal $name (goal.md)"
        tags="$(backfill_goal_tags "$name")"
        id_prefix="$(backfill_ts_to_id_prefix "$ts")"
        udate="$(backfill_utc_date_from_prefix "$id_prefix")"
        raw_body="$(mk_tmp)"
        backfill_build_goal_body "$root" "$name" "$verdict" "$udate" "$raw_body"
        prep_body="$(mk_tmp)"
        backfill_prepare_body "$raw_body" "$prep_body" || {
          printf 'memory: backfill %s %s failed 2 invalid body\n' "$kind" "$name"
          f=$((f + 1)); return 0
        }
        title_s="$(backfill_sanitize_title "$title" "$name")"
        backfill_run_add "$root" "goal-summary" "$title_s" "$prep_body" "$source" "$tags" "$id_prefix"
        ;;
      research)
        title="${name}: back-filled research summary"
        source="research $name (report.md)"
        tags="backfill research"
        id_prefix="$(backfill_research_ts "$root/_memory/work/research/$name/report.md")"
        raw_body="$(mk_tmp)"
        backfill_build_research_body "$root" "$name" "$raw_body"
        prep_body="$(mk_tmp)"
        backfill_prepare_body "$raw_body" "$prep_body" || {
          printf 'memory: backfill %s %s failed 2 invalid body\n' "$kind" "$name"
          f=$((f + 1)); return 0
        }
        title_s="$(backfill_sanitize_title "$title" "$name")"
        backfill_run_add "$root" "research-ingest" "$title_s" "$prep_body" "$source" "$tags" "$id_prefix"
        ;;
      escalation)
        esc_file="$(printf '%s' "$name" | sed 's/#.*//')"
        title_s="$(backfill_sanitize_title "$BF_ESC_TITLE" "$name")"
        source="goals ledger ($esc_file)"
        tags="backfill escalation"
        id_prefix="$(printf '%sT120000Z' "$(printf '%s' "$BF_ESC_RES" | tr -d '-')")"
        raw_body="$(mk_tmp)"
        printf '%s' "$BF_ESC_BODY" > "$raw_body"
        prep_body="$(mk_tmp)"
        backfill_prepare_body "$raw_body" "$prep_body" || {
          printf 'memory: backfill %s %s failed 2 invalid body\n' "$kind" "$name"
          f=$((f + 1)); return 0
        }
        backfill_run_add "$root" "decision" "$title_s" "$prep_body" "$source" "$tags" "$id_prefix"
        ;;
    esac
    case "$BF_ADD_RC" in
      0)
        case "$BF_ADD_LINE" in
          memory:\ added\ *)
            printf 'memory: backfill %s %s added %s\n' "$kind" "$name" "${BF_ADD_LINE#memory: added }"
            a=$((a + 1))
            ;;
          memory:\ duplicate\ *)
            printf 'memory: backfill %s %s duplicate %s\n' "$kind" "$name" "${BF_ADD_LINE#memory: duplicate }"
            d=$((d + 1))
            ;;
          *) printf 'memory: backfill %s %s failed %s %s\n' "$kind" "$name" "$BF_ADD_RC" "$BF_ADD_ERR_FIRST"; f=$((f + 1)) ;;
        esac
        ;;
      5)
        printf 'memory: backfill %s %s quarantined %s\n' "$kind" "$name" "${BF_ADD_LINE#memory: quarantined }"
        q=$((q + 1))
        ;;
      *)
        printf 'memory: backfill %s %s failed %s %s\n' "$kind" "$name" "$BF_ADD_RC" "$BF_ADD_ERR_FIRST"
        f=$((f + 1))
        ;;
    esac
  }

  if [ "$do_goals" -eq 1 ] && [ -d "$goals_dir" ]; then
    local goal_list="$(mk_tmp)"
    find "$goals_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort > "$goal_list"
    while IFS= read -r gd; do
      [ -n "$gd" ] || continue
      g="$(basename "$gd")"
      [ -f "$gd/goal.md" ] || continue
      if [ -n "$only_items" ]; then
        case " $only_items " in *" $g "*) ;; *) continue ;; esac
      fi
      only_hit=0
      case " $only_items " in *" $g "*) only_hit=1 ;; esac
      if [ ! -f "$gd/orchestration-log.md" ]; then
        backfill_emit_plan_or_apply goal "$g" "skip:no-log" "" ""
        continue
      fi
      if backfill_goal_archived_p "$root" "$store" "$g"; then
        backfill_emit_plan_or_apply goal "$g" "skip:archived" "" ""
        continue
      fi
      local meta st ts verdict
      meta="$(backfill_goal_status "$root" "$store" "$g" "$only_hit")"
      st="$(printf '%s\n' "$meta" | sed -n '1p')"
      ts="$(printf '%s\n' "$meta" | sed -n '2p')"
      verdict="$(printf '%s\n' "$meta" | sed -n '3p')"
      if [ "$st" = "would-add" ]; then
        backfill_emit_plan_or_apply goal "$g" "$st" "$ts" "$verdict"
      else
        backfill_emit_plan_or_apply goal "$g" "skip:open" "" ""
      fi
    done < "$goal_list"
  fi

  if [ "$do_research" -eq 1 ] && [ -d "$research_dir" ]; then
    local rlist="$(mk_tmp)"
    find "$research_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort > "$rlist"
    while IFS= read -r rd; do
      [ -n "$rd" ] || continue
      t="$(basename "$rd")"
      [ -f "$rd/report.md" ] || continue
      only_hit=0
      case " $only_items " in *" $t "*) only_hit=1 ;; esac
      if [ -n "$only_items" ] && [ "$only_hit" -eq 0 ]; then continue; fi
      st="$(backfill_research_status "$root" "$store" "$t" "$only_hit")"
      backfill_emit_plan_or_apply research "$t" "$st" "" ""
    done < "$rlist"
  fi

  if [ "$do_esc" -eq 1 ]; then
    if [ -n "$only_items" ] && [ "$seen_esc" -eq 0 ]; then
      :
    else
      local esc_files="$(mk_tmp)" ef entries
      {
        [ -f "$root/_memory/loop/ESCALATIONS.md" ] && printf '%s\n' "$root/_memory/loop/ESCALATIONS.md"
        if [ -d "$root/_memory/loop/archive" ]; then
          find "$root/_memory/loop/archive" -maxdepth 1 -type f -name 'ESCALATIONS-*.md' 2>/dev/null || true
        fi
      } | awk '{ b = $0; sub(/.*\//, "", b); print b "\t" $0 }' | LC_ALL=C sort -u -t "$TAB" -k1,1 -k2,2 | cut -f2- > "$esc_files"
      while IFS= read -r ef; do
        [ -n "$ef" ] || continue
        local idx=0 in_e=0 etitle="" resd="" bodyf="" ename eline
        while IFS= read -r eline || [ -n "$eline" ]; do
          eline="${eline%$'\r'}"
          case "$eline" in
            '## '*)
              if [ "$in_e" -eq 1 ]; then
                idx=$((idx + 1))
                ename="$(basename "$ef")#${idx}"
                st="$(backfill_escalation_status "$store" "$bodyf" "$resd")"
                if [ "$st" = "would-add" ]; then
                  BF_ESC_TITLE="$etitle"
                  BF_ESC_RES="$resd"
                  BF_ESC_BODY="$(cat "$bodyf")"
                fi
                backfill_emit_plan_or_apply escalation "$ename" "$st" "" ""
              fi
              in_e=1
              etitle="${eline##\#\# }"
              resd=""
              bodyf="$(mk_tmp)"
              printf '%s\n' "$eline" > "$bodyf"
              ;;
            *)
              [ "$in_e" -eq 1 ] || continue
              case "$eline" in
                '# '[!#]*) continue ;;
                '#') continue ;;
              esac
              printf '%s\n' "$eline" >> "$bodyf"
              if printf '%s\n' "$eline" | LC_ALL=C grep -Eq '^- resolved: [0-9]{4}-[0-9]{2}-[0-9]{2} .+$' 2>/dev/null; then
                resd="${eline#- resolved: }"
                resd="${resd%% *}"
              fi
              ;;
          esac
        done < "$ef"
        if [ "$in_e" -eq 1 ]; then
          idx=$((idx + 1))
          ename="$(basename "$ef")#${idx}"
          st="$(backfill_escalation_status "$store" "$bodyf" "$resd")"
          if [ "$st" = "would-add" ]; then
            BF_ESC_TITLE="$etitle"
            BF_ESC_RES="$resd"
            BF_ESC_BODY="$(cat "$bodyf")"
          fi
          backfill_emit_plan_or_apply escalation "$ename" "$st" "" ""
        fi
      done < "$esc_files"
    fi
  fi

  if [ -n "$only_items" ]; then
    for only_name in $only_items; do
      local is_goal=0 is_topic=0
      [ -d "$goals_dir/$only_name" ] && [ -f "$goals_dir/$only_name/goal.md" ] && is_goal=1
      [ -f "$research_dir/$only_name/report.md" ] && is_topic=1
      local matched_included=0
      [ "$is_goal" -eq 1 ] && [ "$do_goals" -eq 1 ] && matched_included=1
      [ "$is_topic" -eq 1 ] && [ "$do_research" -eq 1 ] && matched_included=1
      if [ "$matched_included" -eq 1 ]; then
        continue
      fi
      if [ "$is_goal" -eq 1 ] || [ "$is_topic" -eq 1 ]; then
        printf 'memory: backfill only %s skip:excluded-kind\n' "$only_name"
        s=$((s + 1))
        continue
      fi
      if [ "$is_goal" -eq 0 ] && [ "$is_topic" -eq 0 ]; then
        printf 'memory: backfill only %s skip:not-found\n' "$only_name"
        s=$((s + 1))
      fi
    done
  fi

  if [ "$mode" = "plan" ]; then
    printf 'memory: backfill plan %s would-add, %s skipped\n' "$w" "$s"
  else
    printf 'memory: backfill %s added, %s duplicate, %s quarantined, %s failed, %s skipped\n' "$a" "$d" "$q" "$f" "$s"
  fi
  if [ "$f" -gt 0 ]; then exit 4; fi
  if [ "$q" -gt 0 ]; then exit 5; fi
  exit 0
}

prune_only_name_invalid() { # <name>
  local n="$1"
  case "$n" in
    ''|.|..) return 0 ;;
    .*|*/*) return 0 ;;
    *) return 1 ;;
  esac
}

prune_have_git() {
  command -v git >/dev/null 2>&1
}

prune_git_worktree_ok() { # <root>
  [ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null || true)" = true ]
}

prune_git_head_ok() { # <root>
  git -C "$1" rev-parse --verify -q HEAD^{commit} >/dev/null 2>&1
}

prune_resolve_base_ref() { # <root> → stdout ref or empty
  local root="$1" ref
  for ref in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
    if git -C "$root" rev-parse --verify -q "${ref}^{commit}" >/dev/null 2>&1; then
      printf '%s' "$ref"
      return 0
    fi
  done
  return 1
}

prune_extract_ids() { # <text> → stdout one id per line
  printf '%s' "$1" | LC_ALL=C grep -oE '[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}' || true
}

prune_id_in_worktree() { # <root> <id>
  local root="$1" id="$2" store
  store="$(store_dir "$root")"
  [ -f "$(id_to_record_path "$store" "$id")" ] && return 0
  [ -f "$(id_to_quarantine_path "$store" "$id")" ] && return 0
  return 1
}

prune_id_in_git_ref() { # <root> <id> <ref>
  local root="$1" id="$2" ref="$3" store rel_rec rel_q
  store="$(store_dir "$root")"
  rel_rec="$(relpath_under_root "$root" "$(id_to_record_path "$store" "$id")")"
  rel_q="$(relpath_under_root "$root" "$(id_to_quarantine_path "$store" "$id")")"
  git -C "$root" cat-file -e "${ref}:./${rel_rec}" >/dev/null 2>&1 && return 0
  git -C "$root" cat-file -e "${ref}:./${rel_q}" >/dev/null 2>&1 && return 0
  return 1
}

prune_verdict_ids() { # <root> <base_ref> <id-list-file> → stdout keep:… or would-delete
  local root="$1" base_ref="$2" id_file="$3" id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    valid_record_id "$id" || continue
    if ! prune_id_in_worktree "$root" "$id" && ! prune_id_in_git_ref "$root" "$id" HEAD; then
      printf 'keep:missing:%s' "$id"
      return 0
    fi
    if prune_id_in_worktree "$root" "$id" && ! prune_id_in_git_ref "$root" "$id" HEAD; then
      printf 'keep:uncommitted:%s' "$id"
      return 0
    fi
    if [ -n "$base_ref" ] && prune_id_in_git_ref "$root" "$id" HEAD && ! prune_id_in_git_ref "$root" "$id" "$base_ref"; then
      printf 'keep:unmerged:%s' "$id"
      return 0
    fi
  done < "$id_file"
  printf 'would-delete'
}

prune_candidate_tracked() { # <root> <rel-under-root>
  local root="$1" rel="$2" listed
  listed="$(git -C "$root" --literal-pathspecs ls-files -- "./$rel" 2>/dev/null || true)"
  [ -n "$listed" ]
}

prune_goal_source_id_paths() { # <store> <goal> <out-file> — LC_ALL=C sorted abs paths
  local store="$1" g="$2" out="$3" want="goal $g (goal.md)" list f
  list="$(mk_tmp)"
  : > "$out"
  glob_dedupe_files "$store" "$list"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    read_frontmatter "$f" || continue
    [ "$FM_SOURCE" = "$want" ] || continue
    printf '%s\n' "$f" >> "$out"
  done < "$list"
  if [ -s "$out" ]; then
    LC_ALL=C sort -u "$out" -o "$out"
  fi
}

prune_goal_decide() { # <root> <store> <goal> <git_ok> <base_ref> → stdout keep:… or would-delete
  local root="$1" store="$2" g="$3" git_ok="$4" base_ref="$5"
  local work_dir="$root/_memory/work" goals_dir="$work_dir/goals" cand="$goals_dir/$g"
  local log="$cand/orchestration-log.md" line last_arch="" id_file ids id f src_list
  if [ "$git_ok" -eq 0 ]; then
    printf 'keep:no-git'
    return 0
  fi
  if [ -L "$cand" ] || [ -L "$goals_dir" ] || [ -L "$work_dir" ]; then
    printf 'keep:symlink'
    return 0
  fi
  if prune_candidate_tracked "$root" "_memory/work/goals/$g"; then
    printf 'keep:tracked'
    return 0
  fi
  if [ ! -f "$log" ]; then
    printf 'keep:no-log'
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if printf '%s\n' "$line" | LC_ALL=C grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} — ' 2>/dev/null &&
      printf '%s\n' "$line" | LC_ALL=C grep -Fq 'ARCHIVED:' 2>/dev/null; then
      last_arch="$line"
    fi
  done < "$log"
  id_file="$(mk_tmp)"
  : > "$id_file"
  if [ -n "$last_arch" ]; then
    ids="${last_arch##*ARCHIVED:}"
    prune_extract_ids "$ids" > "$id_file"
    if [ ! -s "$id_file" ]; then
      printf 'keep:no-ids'
      return 0
    fi
    prune_verdict_ids "$root" "$base_ref" "$id_file"
    return 0
  fi
  src_list="$(mk_tmp)"
  prune_goal_source_id_paths "$store" "$g" "$src_list"
  if [ ! -s "$src_list" ]; then
    printf 'keep:not-archived'
    return 0
  fi
  : > "$id_file"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    id="$(basename "$f" .md)"
    valid_record_id "$id" && printf '%s\n' "$id" >> "$id_file"
  done < "$src_list"
  if [ ! -s "$id_file" ]; then
    printf 'keep:no-ids'
    return 0
  fi
  prune_verdict_ids "$root" "$base_ref" "$id_file"
}

prune_research_decide() { # <root> <store> <topic> <git_ok> <base_ref>
  local root="$1" store="$2" t="$3" git_ok="$4" base_ref="$5"
  local work_dir="$root/_memory/work" research_dir="$work_dir/research" cand="$research_dir/$t"
  local ingested="$cand/ingested" line2 id_file
  if [ "$git_ok" -eq 0 ]; then
    printf 'keep:no-git'
    return 0
  fi
  if [ -L "$cand" ] || [ -L "$research_dir" ] || [ -L "$work_dir" ]; then
    printf 'keep:symlink'
    return 0
  fi
  if prune_candidate_tracked "$root" "_memory/work/research/$t"; then
    printf 'keep:tracked'
    return 0
  fi
  if [ ! -f "$ingested" ]; then
    printf 'keep:not-archived'
    return 0
  fi
  line2="$(sed -n '2p' "$ingested" 2>/dev/null || true)"
  line2="${line2%$'\r'}"
  id_file="$(mk_tmp)"
  prune_extract_ids "$line2" > "$id_file"
  if [ ! -s "$id_file" ]; then
    printf 'keep:no-ids'
    return 0
  fi
  prune_verdict_ids "$root" "$base_ref" "$id_file"
}

prune_try_delete() { # <root> <kind> <name> → stdout reason on failure, exit 0 ok 1 fail
  local root="$1" kind="$2" name="$3" parent cand abs
  case "$kind" in
    goal) parent="$root/_memory/work/goals" ;;
    research) parent="$root/_memory/work/research" ;;
  esac
  cand="$parent/$name"
  if [ ! -d "$cand" ] || [ -L "$cand" ]; then
    printf 'not a deletable directory'
    return 1
  fi
  case "$name" in
    ''|.|..|.*|*/*)
      printf 'path not under expected parent'
      return 1
      ;;
  esac
  abs="$( (CDPATH= cd -- "$parent" && pwd -P) )/$name" || {
    printf 'bad path'
    return 1
  }
  rm -rf -- "$abs" || {
    printf 'rm failed'
    return 1
  }
  if [ -e "$cand" ]; then
    printf 'still exists'
    return 1
  fi
  return 0
}

prune_list_candidates() { # <dir> <out-file>
  local dir="$1" out="$2" raw path
  : > "$out"
  if [ ! -d "$dir" ] && [ ! -L "$dir" ]; then
    return 0
  fi
  raw="$(mk_tmp)"
  find -H "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | LC_ALL=C sort > "$raw" || true
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -d "$path" ] || continue
    printf '%s\n' "$path" >> "$out"
  done < "$raw"
}

cmd_prune() {
  local root="" mode="plan" do_goals=1 do_research=1
  local seen_root=0 seen_plan=0 seen_apply=0 seen_goals=0 seen_research=0 seen_only=0
  local only_raw=""
  local w=0 k=0 d=0 f=0
  local git_ok=1 base_ref="" work_dir goals_dir research_dir

  while [ $# -gt 0 ]; do
    case "$1" in
      --root) need_val "$@"; [ "$seen_root" -eq 0 ] || die 2 "repeated flag '--root'"; seen_root=1; root="$2"; shift 2 ;;
      --plan) [ "$seen_apply" -eq 0 ] || die 2 "prune takes --plan or --apply, not both"; seen_plan=1; mode="plan"; shift ;;
      --apply) [ "$seen_plan" -eq 0 ] || die 2 "prune takes --plan or --apply, not both"; seen_apply=1; mode="apply"; shift ;;
      --goals) [ "$seen_goals" -eq 0 ] || die 2 "repeated flag '--goals'"; seen_goals=1; do_goals=1; shift ;;
      --research) [ "$seen_research" -eq 0 ] || die 2 "repeated flag '--research'"; seen_research=1; do_research=1; shift ;;
      --only) need_val "$@"; seen_only=1; only_raw="${only_raw}$2$NL"; shift 2 ;;
      --*) die 2 "unknown flag '$1'" ;;
      *) die 2 "unexpected argument '$1'" ;;
    esac
  done

  if [ "$seen_goals" -eq 1 ] || [ "$seen_research" -eq 1 ]; then
    do_goals=0
    do_research=0
    [ "$seen_goals" -eq 1 ] && do_goals=1
    [ "$seen_research" -eq 1 ] && do_research=1
  fi

  [ "$seen_root" -eq 1 ] || root="$(default_root)"
  root="$(resolve_root "$root")"
  local store
  store="$(store_dir "$root")"
  work_dir="$root/_memory/work"
  goals_dir="$work_dir/goals"
  research_dir="$work_dir/research"

  local only_file processed_only goal_names research_names
  only_file="$(mk_tmp)"
  processed_only="$(mk_tmp)"
  goal_names="$(mk_tmp)"
  research_names="$(mk_tmp)"
  : > "$only_file"
  : > "$processed_only"
  : > "$goal_names"
  : > "$research_names"
  if [ "$seen_only" -eq 1 ]; then
    printf '%s' "$only_raw" > "$only_file"
  fi

  if ! prune_have_git || ! prune_git_worktree_ok "$root" || ! prune_git_head_ok "$root"; then
    git_ok=0
  else
    base_ref="$(prune_resolve_base_ref "$root" 2>/dev/null || true)"
  fi

  local goal_list="$(mk_tmp)" research_list="$(mk_tmp)" path name verdict del_reason
  prune_list_candidates "$goals_dir" "$goal_list"
  prune_list_candidates "$research_dir" "$research_list"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    name="$(basename "$path")"
    case "$name" in
      .*) continue ;;
    esac
    printf '%s\n' "$name" >> "$goal_names"
  done < "$goal_list"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    name="$(basename "$path")"
    case "$name" in
      .*) continue ;;
    esac
    printf '%s\n' "$name" >> "$research_names"
  done < "$research_list"

  if [ "$do_goals" -eq 1 ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      name="$(basename "$path")"
      case "$name" in
        .*) continue ;;
      esac
      if [ "$seen_only" -eq 1 ]; then
        grep -Fxq -- "$name" "$only_file" || continue
      fi
      if [ ! -d "$path" ] && [ ! -L "$path" ]; then
        continue
      fi
      verdict="$(prune_goal_decide "$root" "$store" "$name" "$git_ok" "$base_ref")"
      printf '%s\n' "$name" >> "$processed_only"
      case "$verdict" in
        would-delete)
          if [ "$mode" = "plan" ]; then
            printf 'memory: prune goal %s would-delete\n' "$name"
            w=$((w + 1))
          else
            if del_reason="$(prune_try_delete "$root" goal "$name" 2>/dev/null)"; then
              printf 'memory: prune goal %s deleted\n' "$name"
              d=$((d + 1))
            else
              [ -n "$del_reason" ] || del_reason="remove failed"
              printf 'memory: prune goal %s failed %s\n' "$name" "$del_reason"
              f=$((f + 1))
            fi
          fi
          ;;
        *)
          printf 'memory: prune goal %s %s\n' "$name" "$verdict"
          k=$((k + 1))
          ;;
      esac
    done < "$goal_list"
  fi

  if [ "$do_research" -eq 1 ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      name="$(basename "$path")"
      case "$name" in
        .*) continue ;;
      esac
      if [ "$seen_only" -eq 1 ]; then
        grep -Fxq -- "$name" "$only_file" || continue
      fi
      if [ ! -d "$path" ] && [ ! -L "$path" ]; then
        continue
      fi
      verdict="$(prune_research_decide "$root" "$store" "$name" "$git_ok" "$base_ref")"
      printf '%s\n' "$name" >> "$processed_only"
      case "$verdict" in
        would-delete)
          if [ "$mode" = "plan" ]; then
            printf 'memory: prune research %s would-delete\n' "$name"
            w=$((w + 1))
          else
            if del_reason="$(prune_try_delete "$root" research "$name" 2>/dev/null)"; then
              printf 'memory: prune research %s deleted\n' "$name"
              d=$((d + 1))
            else
              [ -n "$del_reason" ] || del_reason="remove failed"
              printf 'memory: prune research %s failed %s\n' "$name" "$del_reason"
              f=$((f + 1))
            fi
          fi
          ;;
        *)
          printf 'memory: prune research %s %s\n' "$name" "$verdict"
          k=$((k + 1))
          ;;
      esac
    done < "$research_list"
  fi

  if [ "$seen_only" -eq 1 ]; then
    local only_name is_goal is_topic
    while IFS= read -r only_name || [ -n "$only_name" ]; do
      if grep -Fxq -- "$only_name" "$processed_only" 2>/dev/null; then
        continue
      fi
      if prune_only_name_invalid "$only_name"; then
        printf 'memory: prune only %s keep:not-found\n' "$only_name"
        k=$((k + 1))
        continue
      fi
      is_goal=0
      is_topic=0
      if grep -Fxq -- "$only_name" "$goal_names" 2>/dev/null; then
        is_goal=1
      fi
      if grep -Fxq -- "$only_name" "$research_names" 2>/dev/null; then
        is_topic=1
      fi
      if [ "$is_goal" -eq 1 ] && [ "$do_goals" -eq 1 ]; then
        continue
      fi
      if [ "$is_topic" -eq 1 ] && [ "$do_research" -eq 1 ]; then
        continue
      fi
      if [ "$is_goal" -eq 1 ] || [ "$is_topic" -eq 1 ]; then
        printf 'memory: prune only %s keep:excluded-kind\n' "$only_name"
        k=$((k + 1))
        continue
      fi
      printf 'memory: prune only %s keep:not-found\n' "$only_name"
      k=$((k + 1))
    done < "$only_file"
  fi

  if [ "$mode" = "plan" ]; then
    printf 'memory: prune plan %s would-delete, %s kept\n' "$w" "$k"
  else
    printf 'memory: prune %s deleted, %s kept, %s failed\n' "$d" "$k" "$f"
  fi
  if [ "$f" -gt 0 ]; then exit 4; fi
  exit 0
}

# --- main ---
[ $# -eq 0 ] && { usage >&2; exit 2; }

case "$1" in
  --help)
    usage
    exit 0
    ;;
esac

sub="$1"
shift

case "$sub" in
  --help)
    usage
    exit 0
    ;;
  add|index|search|show|redact|check|rm|capture|backfill|prune) ;;
  *)
    usage >&2
    die 2 "unknown subcommand '$sub'"
    ;;
esac

if [ $# -gt 0 ]; then
  case "$1" in
    --help)
      usage
      exit 0
      ;;
  esac
fi

case "$sub" in
  add) cmd_add "$@" ;;
  index) cmd_index "$@" ;;
  search) cmd_search "$@" ;;
  show) cmd_show "$@" ;;
  redact) cmd_redact "$@" ;;
  check) cmd_check "$@" ;;
  rm) cmd_rm "$@" ;;
  capture) cmd_capture "$@" ;;
  backfill) cmd_backfill "$@" ;;
  prune) cmd_prune "$@" ;;
esac
