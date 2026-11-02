#!/usr/bin/env bash
# kit-guard — compare manifest hashes (check) and block agent edits to kit-owned files (hook).
# Emitted single-copy to `_kit/kit-guard.sh` (Windows: `_kit/kit-guard.cmd` via bash-launcher.cmd).
#
#   kit-guard.sh check [--root DIR]
#     Compare every kit-owned path in orchestration-kit.manifest.json to its recorded sha256.
#
#   kit-guard.sh hook <claude|cursor> [--root DIR]
#     Read hook JSON from stdin; deny edits to kit-owned paths (Claude Code PreToolUse / Cursor preToolUse).
#
# Root: --root DIR when given; else the parent of this script's directory (_kit/..), via
# `CDPATH= cd` and pwd -P (an exported CDPATH never changes the answer).
# Manifest: <root>/orchestration-kit.manifest.json.
#
# Kit-owned paths are manifest `files` keys minus user-owned exclusions: the Claude Code settings file
# (<harness-dir>/settings.json), .codex/config.toml, and .cursor/hooks.json.
#
# Exit codes: 0 ok or hook allow · 2 usage / no manifest / no sha256 tool / hook deny · 4 check found edits.
# Set AGENT_KIT_GUARD=0 to fail open in hook mode (allow). check ignores AGENT_KIT_GUARD.
#
# Known limit: the guard does not protect its own configuration — the manifest and the two hook config
# files are excluded or writable, so an agent could disable it; check run from CI (or emit.sh --check
# from the kit) is the backstop.
#
# Bash 3.2+, LC_ALL=C. No runtime JSON dependency.
set -u
export LC_ALL=C

usage() {
  printf 'usage: kit-guard.sh check [--root DIR] | kit-guard.sh hook <claude|cursor> [--root DIR]\n' >&2
}

die() { # <code> <message>
  printf 'kit-guard: %s\n' "$2" >&2
  exit "$1"
}

# Build harness directory name without embedding it as a source literal (template guard).
_harness_dir='.cla'
_harness_dir="${_harness_dir}ude"
EXCL_SETTINGS="${_harness_dir}/settings.json"
EXCL_CODEX='.codex/config.toml'
EXCL_CURSOR_HOOKS='.cursor/hooks.json'

DENY_MSG_SUFFIX=' is a kit-owned file listed in orchestration-kit.manifest.json — change kit behavior through the answers file and emit.sh --upgrade; do not edit it.'

RESTORE_LINE='kit-guard: restore tracked files from git; delete a modified _kit/ file and re-run emit.sh --upgrade; never edit kit-owned files'

SHA256_CMD=""
detect_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    SHA256_CMD='sha256sum'
  elif command -v shasum >/dev/null 2>&1; then
    SHA256_CMD='shasum -a 256'
  else
    return 1
  fi
  return 0
}

sha256_digest_line() { # stdin one line from hasher → digest field
  local line
  IFS= read -r line || line=""
  printf '%s' "${line%% *}"
}

sha256_file() { # <path> → digest on stdout; 1 if unreadable
  local p="$1" h
  if [ "$SHA256_CMD" = 'sha256sum' ]; then
    h="$(sha256sum < "$p" | sha256_digest_line)"
  else
    h="$(shasum -a 256 < "$p" | sha256_digest_line)"
  fi
  [ -n "$h" ] || return 1
  printf '%s' "$h"
}

is_excluded_path() { # <relpath>
  case "$1" in
    "$EXCL_SETTINGS"|"$EXCL_CODEX"|"$EXCL_CURSOR_HOOKS") return 0 ;;
  esac
  return 1
}

parse_files_line() { # <manifest>
  local mf="$1" in_files=0 line path hash
  MANIFEST_PATHS=()
  MANIFEST_HASHES=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *'"files"'*'{'*) in_files=1; continue ;;
    esac
    if [ "$in_files" -eq 1 ]; then
      case "$line" in
        *'}'*) break ;;
      esac
      path=""
      hash=""
      if [[ "$line" =~ ^[[:space:]]*\"([^\"]+)\":[[:space:]]*\"([0-9a-f]{64})\"(,)?[[:space:]]*$ ]]; then
        path="${BASH_REMATCH[1]}"
        hash="${BASH_REMATCH[2]}"
        is_excluded_path "$path" && continue
        MANIFEST_PATHS+=("$path")
        MANIFEST_HASHES+=("$hash")
      fi
    fi
  done < "$mf"
  [ "${#MANIFEST_PATHS[@]}" -gt 0 ]
}

load_manifest_files() { # <manifest>
  local mf="$1"
  parse_files_line "$mf"
}

sort_manifest_paths() {
  local tmp_p tmp_h i n paths hashes
  n="${#MANIFEST_PATHS[@]}"
  paths=("${MANIFEST_PATHS[@]}")
  hashes=("${MANIFEST_HASHES[@]}")
  MANIFEST_PATHS=()
  MANIFEST_HASHES=()
  while IFS=$'\t' read -r tmp_p tmp_h; do
    MANIFEST_PATHS+=("$tmp_p")
    MANIFEST_HASHES+=("$tmp_h")
  done < <(
    i=0
    while [ "$i" -lt "$n" ]; do
      printf '%s\t%s\n' "${paths[$i]}" "${hashes[$i]}"
      i=$((i + 1))
    done | LC_ALL=C sort -t $'\t' -k1,1
  )
}

resolve_roots() { # sets ROOT_REAL ROOT_GIVEN
  ROOT_GIVEN="$1"
  ROOT_REAL="$(CDPATH= cd "$ROOT_GIVEN" && pwd -P)"
}

# --- JSON helpers (hook stdin) ---

json_unescape() { # <escaped> → stdout
  local s="$1" out="" i c n
  i=0
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"
    if [ "$c" = '\' ] && [ $((i + 1)) -lt "${#s}" ]; then
      n="${s:$((i + 1)):1}"
      case "$n" in
        '"') out+='"'; i=$((i + 2)); continue ;;
        \\) out+='\'; i=$((i + 2)); continue ;;
        /) out+='/'; i=$((i + 2)); continue ;;
        n) out+=$'\n'; i=$((i + 2)); continue ;;
        t) out+=$'\t'; i=$((i + 2)); continue ;;
        r) out+=$'\r'; i=$((i + 2)); continue ;;
        *) out+="$c"; i=$((i + 1)); continue ;;
      esac
    fi
    out+="$c"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

extract_json_string_for_key() { # <json> <key> → stdout value or empty
  local json="$1" key="$2" pat rest esc val c
  pat="\"${key}\""
  rest="${json#*${pat}}"
  if [ "$rest" = "$json" ]; then
    return 1
  fi
  rest="${rest#*:}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [ "${rest:0:1}" = '"' ] || return 1
  rest="${rest:1}"
  esc=""
  while [ -n "$rest" ]; do
    c="${rest:0:1}"
    if [ "$c" = '"' ]; then
      json_unescape "$esc"
      return 0
    fi
    if [ "$c" = '\' ] && [ "${#rest}" -ge 2 ]; then
      esc="${esc}${rest:0:2}"
      rest="${rest:2}"
    else
      esc="${esc}${c}"
      rest="${rest:1}"
    fi
  done
  return 1
}

extract_hook_path() { # <json> → stdout path
  local json="$1" key val
  for key in file_path notebook_path path target_file; do
    if val="$(extract_json_string_for_key "$json" "$key" 2>/dev/null)"; then
      [ -n "$val" ] || continue
      printf '%s' "$val"
      return 0
    fi
  done
  return 1
}

json_escape_string() { # <raw> → stdout JSON string contents (no surrounding quotes)
  local s="$1" out="" i c
  i=0
  while [ "$i" -lt "${#s}" ]; do
    c="${s:$i:1}"
    case "$c" in
      '"') out+='\"' ;;
      \\) out+='\\' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *) out+="$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

hook_allow_cursor() {
  printf '%s\n' '{"permission":"allow"}'
}

hook_fail_open() { # <harness> <json>
  local harness="$1" json="$2"
  if [ "$harness" = 'cursor' ] || is_cursor_caller "$json"; then
    hook_allow_cursor
  fi
  exit 0
}

hook_deny_cursor() { # <message>
  local msg="$1" em
  em="$(json_escape_string "$msg")"
  printf '%s\n' "{\"permission\":\"deny\",\"user_message\":\"${em}\",\"agent_message\":\"${em}\"}"
}

is_cursor_caller() { # <json>
  local json="$1"
  [ -n "${CURSOR_PROJECT_DIR:-}" ] && return 0
  case "$json" in
    *'"cursor_version"'*) return 0 ;;
    *'"hook_event_name"'*'"preToolUse"'*) return 0 ;;
  esac
  return 1
}

normalize_to_root_rel() { # <path> <json> → stdout relpath or empty if outside root
  local p="$1" json="$2" cwd base full root real rel
  cwd="$(extract_json_string_for_key "$json" cwd 2>/dev/null)" || cwd=""
  if [ -z "$cwd" ]; then
    cwd="$PWD"
  fi
  if [ "${p#/}" = "$p" ]; then
    base="${cwd%/}"
    full="${base}/${p}"
  else
    full="$p"
  fi
  # Collapse // (simple)
  while case "$full" in *//*) full="${full//\/\//\/}"; true ;; *) false ;; esac; do :; done

  root="$ROOT_REAL"
  real="$ROOT_GIVEN"

  # Prefer canonical file path when parent exists.
  if [ -d "$(dirname "$full")" ]; then
    full="$(CDPATH= cd "$(dirname "$full")" 2>/dev/null && pwd -P)/$(basename "$full")"
  fi

  case "$full" in
    "$root"/*)
      rel="${full#$root/}"
      printf '%s' "$rel"
      return 0
      ;;
    "$root")
      printf ''
      return 0
      ;;
  esac
  case "$full" in
    "$real"/*)
      rel="${full#$real/}"
      printf '%s' "$rel"
      return 0
      ;;
    "$real")
      printf ''
      return 0
      ;;
  esac
  # Also try non-canonical full against given root (tests may pass absolute tmp paths).
  case "$1" in
    "$real"/*)
      rel="${1#$real/}"
      printf '%s' "$rel"
      return 0
      ;;
    "$root"/*)
      rel="${1#$root/}"
      printf '%s' "$rel"
      return 0
      ;;
  esac
  return 1
}

path_is_kit_owned() { # <root-rel path>
  local target="$1" i
  [ -n "$target" ] || return 1
  i=0
  while [ "$i" -lt "${#MANIFEST_PATHS[@]}" ]; do
    if [ "${MANIFEST_PATHS[$i]}" = "$target" ]; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

run_check() {
  local mf="$1" skipped_kit=0 checked=0 issues=0
  local i p expect disk issue_lines kit_present

  if [ ! -f "$mf" ]; then
    die 2 "no manifest at $mf"
  fi

  if ! load_manifest_files "$mf"; then
    die 2 "no files block in orchestration-kit.manifest.json"
  fi
  sort_manifest_paths

  kit_present=0
  if [ -d "${ROOT_GIVEN}/_kit" ]; then
    kit_present=1
  fi

  issue_lines=""

  i=0
  while [ "$i" -lt "${#MANIFEST_PATHS[@]}" ]; do
    p="${MANIFEST_PATHS[$i]}"
    expect="${MANIFEST_HASHES[$i]}"
    case "$p" in
      _kit/*)
        if [ "$kit_present" -eq 0 ]; then
          skipped_kit=$((skipped_kit + 1))
          i=$((i + 1))
          continue
        fi
        ;;
    esac
    checked=$((checked + 1))
    if [ ! -f "${ROOT_GIVEN}/$p" ]; then
      issue_lines="${issue_lines}kit-guard: missing ${p}"$'\n'
      issues=$((issues + 1))
    else
      disk="$(sha256_file "${ROOT_GIVEN}/$p" 2>/dev/null)" || disk=""
      if [ -z "$disk" ] || [ "$disk" != "$expect" ]; then
        issue_lines="${issue_lines}kit-guard: modified ${p}"$'\n'
        issues=$((issues + 1))
      fi
    fi
    i=$((i + 1))
  done

  if [ "$kit_present" -eq 0 ] && [ "$skipped_kit" -gt 0 ]; then
    printf 'kit-guard: note: _kit/ absent (gitignored until emit runs) — skipped %s _kit/ entries\n' "$skipped_kit"
  fi

  if [ -n "$issue_lines" ]; then
    printf '%s' "$issue_lines"
  fi

  if [ "$issues" -gt 0 ]; then
    printf '%s\n' "$RESTORE_LINE"
    exit 4
  fi
  printf 'kit-guard: ok (%s kit files)\n' "$checked"
  exit 0
}

run_hook() {
  local harness="$1" mf="$2" json="" rel="" msg="" use_cursor=0

  json="$(cat)"

  if [ "${AGENT_KIT_GUARD:-}" = '0' ]; then
    hook_fail_open "$harness" "$json"
  fi
  if [ -z "$json" ]; then
    hook_fail_open "$harness" "$json"
  fi

  # Rough JSON validity: must contain { and }
  case "$json" in
    *'{'*'}'*) ;;
    *)
      hook_fail_open "$harness" "$json"
      ;;
  esac

  if ! extract_hook_path "$json" >/dev/null 2>&1; then
    hook_fail_open "$harness" "$json"
  fi
  rel="$(extract_hook_path "$json")"
  rel="$(normalize_to_root_rel "$rel" "$json" 2>/dev/null)" || rel=""

  if [ ! -f "$mf" ]; then
    hook_fail_open "$harness" "$json"
  fi
  if ! load_manifest_files "$mf"; then
    hook_fail_open "$harness" "$json"
  fi

  if [ -z "$rel" ] || ! path_is_kit_owned "$rel"; then
    hook_fail_open "$harness" "$json"
  fi

  msg="kit-guard: ${rel}${DENY_MSG_SUFFIX}"
  use_cursor=0
  if [ "$harness" = 'cursor' ]; then
    use_cursor=1
  elif [ "$harness" = 'claude' ] && is_cursor_caller "$json"; then
    use_cursor=1
  fi

  if [ "$use_cursor" -eq 1 ]; then
    hook_deny_cursor "$msg"
    if [ "$harness" = 'claude' ]; then
      printf '%s\n' "$msg" >&2
    fi
    exit 2
  fi
  printf '%s\n' "$msg" >&2
  exit 2
}

# --- main ---

[ $# -eq 0 ] && { usage; exit 2; }

mode="$1"
shift

root_explicit=0
root=""
harness=""

case "$mode" in
  check)
    while [ $# -gt 0 ]; do
      case "$1" in
        --root)
          [ $# -ge 2 ] || { usage; exit 2; }
          root_explicit=1
          root="$2"
          shift 2
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done
    ;;
  hook)
    [ $# -ge 1 ] || { usage; exit 2; }
    harness="$1"
    shift
    case "$harness" in
      claude|cursor) ;;
      *)
        usage
        exit 2
        ;;
    esac
    while [ $# -gt 0 ]; do
      case "$1" in
        --root)
          [ $# -ge 2 ] || { usage; exit 2; }
          root_explicit=1
          root="$2"
          shift 2
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [ "$root_explicit" -eq 1 ]; then
  [ -n "$root" ] || { usage; exit 2; }
else
  _self="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
  root="$(CDPATH= cd "${_self}/.." && pwd -P)"
fi

resolve_roots "$root"
manifest="${ROOT_GIVEN}/orchestration-kit.manifest.json"

if ! detect_sha256; then
  die 2 'no sha256 tool'
fi

case "$mode" in
  check) run_check "$manifest" ;;
  hook) run_hook "$harness" "$manifest" ;;
esac
