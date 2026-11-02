#!/usr/bin/env bash
# trace-lint — consumer-trace linter for the AI Orchestration Kit.
# Emitted single-copy to `_kit/trace-lint.sh` (Windows outside Git Bash:
# `_kit\trace-lint.cmd` — Git for Windows required). Pre-flight check 2 runs it on a
# goal's `goal.md`; it reads that one file and writes nothing.
#
# CLI CONTRACT (frozen — the goal template and goal-criteria describe this):
#
#   trace-lint.sh <goal.md>     lint the goal's `## Searches` and `## Consumers`
#   trace-lint.sh --help        print usage, exit 0 (only as the sole argument)
#
#   Exit codes: 0 valid · 2 usage (wrong argument count, unknown flag, `--help` among
#   other arguments) · 3 findings ·
#   4 the file is missing or unreadable.
#   stdout, exit 0:  `trace-lint: ok (<S> searches, <C> consumers)`
#                    or `trace-lint: ok (none — <reason>)`
#   stdout, exit 3:  one `trace-lint: <file>:<line>: <message>` line per finding, then a
#                    last line `trace-lint: <N> finding(s)`
#   stderr, exit 2 / 4: one `trace-lint: <message>` line (exit 2 adds the usage text).
#
# FORMAT (the goal template's `## Searches` / `## Consumers` guidance is the source):
#   Parsing: a section runs from a `## <name>` heading to the next `## ` heading. A
#   heading starts at column 0. Lines inside fenced blocks (backtick or tilde fences,
#   closed only by the same character with at least as many marks) are never read as
#   headings.
#   1. Sections: `## Consumers` must exist. When its first non-blank body line starts
#      with `none — ` the trace is valid, that line is the only non-blank body line of
#      `## Consumers`, and `## Searches` must be absent. Otherwise `## Searches` must
#      exist with at least one item, and `## Consumers` must hold the exact header row
#      `| Surface | Consumer | Class | Evidence |` as its first table row.
#   2. Search items: every line in `## Searches` that starts with `- **S` matches the
#      pattern below; `1 hit` is required when N is 1 and `hits` otherwise; the next
#      non-blank line opens a text fence; the fence holds N non-empty lines. An item
#      starts at column 0; an indented `- **S` line is a finding.
#        PCRE notation, for readers:
#          ^- \*\*S([0-9]+)\*\* (`+)(.*)\2 — ([0-9]+) (hit|hits)$
#        This tool implements it in POSIX terms: the backtick-span back-reference in
#        BRE (sed) and the hit|hits alternation as a separate check.
#   3. Unique ids: no `S<n>` repeats. Ids compare as numbers: `S01` and `S1` are one id.
#   4. Hit lines (after trimming leading whitespace and a leading `./`) match
#      `^[^:]*[^0-9:][^:]*:[0-9]+:` — a path that is not all digits, then a line number.
#   5. Every hit path not under `_memory/` is a Consumer: the Consumer column, after
#      splitting the row on unescaped `|` (`\|` is a literal pipe) and stripping
#      backticks, spaces and a leading `./` (as hit paths are).
#   6. Class is exactly `changes`, `unaffected` or `owner-excluded`.
#   7. `unaffected` evidence starts with `test: `, `diff: ` or `search: S<n>`; a
#      `search:` reference names an existing search with 0 hits (ids compare as in 3).
#   8. `owner-excluded` evidence contains `Q&A row <n>`, and `## Discovery Summary`'s
#      table has a row whose first cell is `<n>`.
#   9. `changes` evidence contains `task <NN>` (two digits, optional letter) or is
#      exactly `Phase 6`; `Phase 6` is valid only when the goal has a line matching
#      `^[[:space:]]*align_docs:[[:space:]]*true[[:space:]]*(#.*)?$` (the template's
#      `align_docs: true|false` placeholder does not match).
#   Findings print in the order the checks run: the single pass over the file first,
#   then the Consumer rows in row order, then unlisted hits in file order.
#
# Zero runtime deps beyond bash + sed. Bash 3.2 compatible: no associative arrays, no
# case-folding expansions, no JSON tools, and no here-strings or here-docs (those use
# temp files on older Bash, so an unwritable $TMPDIR would abort the run). No setup
# placeholders — harness-agnostic.
set -u
LC_ALL=C
export LC_ALL

NL='
'
BT='`'

usage() {
  printf '%s\n' \
    'usage: trace-lint.sh <goal.md>' \
    '       trace-lint.sh --help' \
    "Checks the goal's '## Searches' and '## Consumers' sections (the consumer trace)." \
    'exit: 0 valid · 2 usage · 3 findings · 4 file missing or unreadable'
}

die() { # <code> <message>
  printf 'trace-lint: %s\n' "$2" >&2
  exit "$1"
}

if [ $# -eq 1 ] && [ "$1" = "--help" ]; then
  usage
  exit 0
fi
for a in "$@"; do
  case "$a" in
    --help) usage >&2; die 2 "--help must be the only argument" ;;
    -?*) usage >&2; die 2 "unknown flag '$a'" ;;
  esac
done
[ $# -eq 1 ] || { usage >&2; die 2 "expected exactly one argument: the goal.md path"; }
file="$1"
if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  die 4 "file not found or unreadable: $file"
fi

# --- patterns -----------------------------------------------------------------------
ALIGN_RE='^[[:space:]]*align_docs:[[:space:]]*true[[:space:]]*(#.*)?$'
HIT_RE='^[^:]*[^0-9:][^:]*:[0-9]+:'
SEP_RE='^[|][-:| ]*-[-:| ]*$'
TASK_RE='task [0-9][0-9]([^0-9]|$)'
HEADER_ROW='| Surface | Consumer | Class | Evidence |'
# Rule 2 in BRE: \1 = S number, \2 = the backtick run, \3 = the command, \4 = N, \5 = the
# count word (hit|hits is checked separately). Prints "<S number> <N> <word>" on a match.
# The item starts at column 0 (parse_item reports and strips any leading whitespace first).
ITEM_SED='s/^- \*\*S\([0-9][0-9]*\)\*\* \(`\{1,\}\)\(.*\)\2 — \([0-9][0-9]*\) \([A-Za-z]*\)$/\1 \4 \5/p'

MSG_ITEM='malformed search item (want: - **S<n>** `<command>` — <N> hit, or hits)'
MSG_INDENT='search item must start at column 0 (remove the leading whitespace)'
MSG_ONLY="none — <reason> must be the only body line of '## Consumers'"
MSG_UNAFF="unaffected evidence must start with 'test: ', 'diff: ' or 'search: S<n>'"

# --- helpers --------------------------------------------------------------------------
nf=0
finding() { # <line> <message>
  printf 'trace-lint: %s:%s: %s\n' "$file" "$1" "$2"
  nf=$((nf + 1))
}

trim() { # <text> → T (leading and trailing whitespace removed)
  T="${1#"${1%%[![:space:]]*}"}"
  T="${T%"${T##*[![:space:]]}"}"
}

norm_id() { # <digits> → NID (leading zeros removed, so S01 and S1 are one id; all zeros → 0)
  NID="${1#"${1%%[!0]*}"}"
  [ -n "$NID" ] || NID=0
}

next_line() { # pops the first line of $REST into $ROW (a loop over a variable, no temp file)
  case "$REST" in
    *"$NL"*)
      ROW="${REST%%"$NL"*}"
      REST="${REST#*"$NL"}" ;;
    *)
      ROW="$REST"
      REST="" ;;
  esac
}

split_row() { # <table row> → CELLS (trimmed; `\|` becomes `|`), NCELLS
  local s="$1" i=0 n ch cur=""
  CELLS=()
  NCELLS=0
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s#|}"
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    ch="${s:$i:1}"
    if [ "$ch" = '\' ] && [ "${s:$((i + 1)):1}" = '|' ]; then
      cur="$cur|"
      i=$((i + 2))
      continue
    fi
    if [ "$ch" = '|' ]; then
      trim "$cur"
      CELLS[$NCELLS]="$T"
      NCELLS=$((NCELLS + 1))
      cur=""
    else
      cur="$cur$ch"
    fi
    i=$((i + 1))
  done
  trim "$cur"
  if [ -n "$T" ]; then
    CELLS[$NCELLS]="$T"
    NCELLS=$((NCELLS + 1))
  fi
}

parse_item() { # reads $line / $lineno; registers the search and arms the fence check
  local m sid sn sw n body rest nid
  items=$((items + 1))
  body="$line"
  case "$line" in
    [[:space:]]*)
      finding "$lineno" "$MSG_INDENT"
      body="${line#"${line%%[![:space:]]*}"}" ;;
  esac
  m="$(printf '%s\n' "$body" | sed -n "$ITEM_SED")"
  if [ -z "$m" ]; then
    finding "$lineno" "$MSG_ITEM"
    return
  fi
  sid="${m%% *}"                 # m is "<S number> <N> <word>" (the word may be empty)
  rest="${m#* }"
  sn="${rest%% *}"
  sw="${rest#* }"
  n=$((10#$sn))
  case "$sw" in
    hit)  [ "$n" -eq 1 ] || finding "$lineno" "S$sid: the word 'hit' is only for a count of 1 (write '$n hits')" ;;
    hits) [ "$n" -ne 1 ] || finding "$lineno" "S$sid: '1 hits' is invalid (write '1 hit')" ;;
    *)    finding "$lineno" "$MSG_ITEM"; return ;;
  esac
  norm_id "$sid"
  nid="$NID"
  case "$NL$sids" in
    *"$NL$nid$NL"*) finding "$lineno" "duplicate search id S$sid" ;;
  esac
  sids="$sids$nid$NL"
  counts="$counts$nid:$n$NL"
  pending=1
  pend_id="$sid"
  pend_n="$n"
  pend_line="$lineno"
}

# --- single pass: sections, searches, hits, raw table rows ----------------------------
lineno=0
fence=0               # mark count of the open fence; 0 = not inside one
fence_ch=""           # mark character of the open fence: a backtick or a tilde
sec=""                # consumers | searches | discovery | other ("" before the first ##)
cons_line=0           # heading line of ## Consumers (0 = absent)
search_line=0         # heading line of ## Searches (0 = absent)
cons_first=""         # first non-blank body line of ## Consumers
cons_first_line=0
cons_extra_line=0     # second non-blank body line of ## Consumers (0 = none)
cons_rows=""          # "<lineno> <row>" per table row of ## Consumers
disc_rows=""          # first cells (digits) of ## Discovery Summary table rows
sids=""               # search ids, one per line
counts=""             # "<id>:<N>" per search, one per line
hits=""               # "<lineno> <path>" per well-formed hit line
items=0               # search items seen
align_docs=0
pending=0             # 1 while the last search item still awaits its text fence
pend_id="" pend_n=0 pend_line=0
in_hit=0              # 1 inside the text fence that belongs to a search item
cur_id="" cur_n=0 cur_line=0 hit_n=0 hit_open=0

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  lineno=$((lineno + 1))
  if [[ "$line" =~ $ALIGN_RE ]]; then align_docs=1; fi
  trim "$line"
  t="$T"

  # body lines of ## Consumers: the first decides `none — <reason>`, the second is a finding
  # under it. The next `## ` heading (outside a fence) is not a body line.
  if [ "$sec" = consumers ] && [ -n "$t" ] && { [ "$fence" -gt 0 ] || [ "${line:0:3}" != '## ' ]; }; then
    if [ "$cons_first_line" -eq 0 ]; then
      cons_first="$t"
      cons_first_line=$lineno
    elif [ "$cons_extra_line" -eq 0 ]; then
      cons_extra_line=$lineno
    fi
  fi

  # fenced blocks (backtick or tilde): openers, closers and content never reach the
  # heading/section logic. A fence closes only on its own character, with at least as
  # many marks as the opener and no text after them.
  mark=""
  case "${t:0:3}" in
    '```') mark="$BT" ;;
    '~~~') mark='~' ;;
  esac
  if [ -n "$mark" ]; then
    after="$t"
    ticks=0
    while [ "${after:0:1}" = "$mark" ]; do
      ticks=$((ticks + 1))
      after="${after:1}"
    done
    trim "$after"
    info="$T"
    if [ "$fence" -eq 0 ]; then
      opener=1
      if [ "$mark" = "$BT" ]; then
        case "$info" in
          *"$BT"*) opener=0 ;;                        # an inline span such as ```x```
        esac
      fi
      if [ "$opener" -eq 1 ]; then
        fence=$ticks
        fence_ch="$mark"
        if [ "$sec" = searches ] && [ "$pending" -eq 1 ]; then
          pending=0
          if [ "$info" = text ]; then
            in_hit=1
            hit_n=0
            hit_open=$lineno
            cur_id="$pend_id"
            cur_n="$pend_n"
            cur_line="$pend_line"
          else
            finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
          fi
        fi
        continue
      fi
    elif [ "$mark" = "$fence_ch" ] && [ "$ticks" -ge "$fence" ] && [ -z "$info" ]; then
      if [ "$in_hit" -eq 1 ] && [ "$hit_n" -ne "$cur_n" ]; then
        finding "$cur_line" "S$cur_id declares $cur_n hit(s) but its block has $hit_n non-empty line(s)"
      fi
      fence=0
      fence_ch=""
      in_hit=0
      continue
    fi
  fi
  if [ "$fence" -gt 0 ]; then
    if [ "$in_hit" -eq 1 ] && [ -n "$t" ]; then
      hit_n=$((hit_n + 1))
      h="${t#./}"
      if [[ "$h" =~ $HIT_RE ]]; then
        hits="$hits$lineno ${h%%:*}$NL"
      else
        finding "$lineno" "hit has no path (use -H): ${h:0:60}"
      fi
    fi
    continue
  fi

  # headings
  case "$line" in
    '## '*)
      if [ "$sec" = searches ] && [ "$pending" -eq 1 ]; then
        pending=0
        finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
      fi
      trim "${line:3}"
      case "$T" in
        Consumers)
          sec=consumers
          [ "$cons_line" -eq 0 ] && cons_line=$lineno ;;
        Searches)
          sec=searches
          [ "$search_line" -eq 0 ] && search_line=$lineno ;;
        'Discovery Summary'*) sec=discovery ;;
        *) sec=other ;;
      esac
      continue ;;
  esac

  [ -n "$t" ] || continue
  case "$sec" in
    searches)
      if [ "$pending" -eq 1 ]; then
        pending=0
        finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
      fi
      case "$t" in
        '- **S'*) parse_item ;;
      esac ;;
    consumers)
      case "$t" in
        '|'*) cons_rows="$cons_rows$lineno $t$NL" ;;
      esac ;;
    discovery)
      case "$t" in
        '|'*)
          cell="${t#|}"
          cell="${cell%%|*}"
          trim "$cell"
          case "$T" in
            ''|*[!0-9]*) ;;
            *) disc_rows="$disc_rows$T$NL" ;;
          esac ;;
      esac ;;
  esac
done < "$file"

if [ "$pending" -eq 1 ]; then
  finding "$pend_line" "S$pend_id: the next non-blank line must open a "'```text'" block"
fi
if [ "$in_hit" -eq 1 ]; then
  finding "$hit_open" "unterminated "'```text'" block for S$cur_id"
fi

# --- rule 1 and the consumer-dependent rules -------------------------------------------
none=0
none_reason=""
consumers=0
if [ "$cons_line" -eq 0 ]; then
  finding 1 "missing '## Consumers' section"
else
  case "$cons_first" in
    'none — '*)
      none=1
      none_reason="${cons_first#none — }" ;;
  esac
  if [ "$none" -eq 1 ]; then
    if [ "$search_line" -ne 0 ]; then
      finding "$search_line" "'## Searches' must be absent when '## Consumers' is 'none — <reason>'"
    fi
    if [ "$cons_extra_line" -ne 0 ]; then
      finding "$cons_extra_line" "$MSG_ONLY"
    fi
  else
    if [ "$search_line" -eq 0 ]; then
      finding "$cons_line" "missing '## Searches' section (a goal that changes no shared surface writes 'none — <reason>' under '## Consumers')"
    elif [ "$items" -eq 0 ]; then
      finding "$search_line" "'## Searches' has no items"
    fi

    first_row=1
    cons_paths=""
    REST="$cons_rows"
    while [ -n "$REST" ]; do
      next_line
      row="$ROW"
      [ -n "$row" ] || continue
      rl="${row%% *}"
      rt="${row#* }"
      if [ "$first_row" -eq 1 ]; then          # the first table row is the header row
        first_row=0
        if [ "$rt" != "$HEADER_ROW" ]; then
          finding "$rl" "'## Consumers' must hold the header row '$HEADER_ROW'"
        fi
        continue
      fi
      if [[ "$rt" =~ $SEP_RE ]]; then continue; fi
      consumers=$((consumers + 1))
      split_row "$rt"
      cpath="${CELLS[1]:-}"
      cpath="${cpath//"$BT"/}"
      trim "$cpath"
      cpath="${T#./}"                           # a leading ./ is ignored, as on hit paths
      cons_paths="$cons_paths$cpath$NL"
      class="${CELLS[2]:-}"
      ev="${CELLS[3]:-}"
      case "$class" in
        changes)
          if [ "$ev" = 'Phase 6' ]; then
            if [ "$align_docs" -ne 1 ]; then
              finding "$rl" "changes evidence 'Phase 6' is valid only when the goal sets 'align_docs: true' in its phases block"
            fi
          elif [[ "$ev" =~ $TASK_RE ]]; then
            :
          else
            finding "$rl" "changes evidence must contain 'task <NN>' or be exactly 'Phase 6' (got '$ev')"
          fi ;;
        unaffected)
          case "$ev" in
            'test: '*|'diff: '*) ;;
            'search: S'*)
              rest="${ev#search: S}"
              sid="${rest%%[!0-9]*}"
              if [ -z "$sid" ]; then
                finding "$rl" "$MSG_UNAFF"
              else
                norm_id "$sid"
                case "$NL$counts" in
                  *"$NL$NID:0$NL"*) ;;
                  *"$NL$NID:"*) finding "$rl" "unaffected evidence 'search: S$sid' names a search with hits (needs 0 hits)" ;;
                  *) finding "$rl" "unaffected evidence 'search: S$sid' names no search in '## Searches'" ;;
                esac
              fi ;;
            *) finding "$rl" "$MSG_UNAFF" ;;
          esac ;;
        owner-excluded)
          case "$ev" in
            *'Q&A row '*)
              rest="${ev#*Q&A row }"
              qn="${rest%%[!0-9]*}"
              if [ -z "$qn" ]; then
                finding "$rl" "owner-excluded evidence must contain 'Q&A row <n>' (n = a number)"
              else
                case "$NL$disc_rows" in
                  *"$NL$qn$NL"*) ;;
                  *) finding "$rl" "'Q&A row $qn' is not a row of '## Discovery Summary'" ;;
                esac
              fi ;;
            *) finding "$rl" "owner-excluded evidence must contain 'Q&A row <n>'" ;;
          esac ;;
        *)
          finding "$rl" "class '$class' must be exactly changes, unaffected or owner-excluded" ;;
      esac
    done
    if [ "$first_row" -eq 1 ]; then            # no table row at all
      finding "$cons_line" "'## Consumers' must hold the header row '$HEADER_ROW'"
    fi

    unlisted=""
    REST="$hits"
    while [ -n "$REST" ]; do
      next_line
      h="$ROW"
      [ -n "$h" ] || continue
      hl="${h%% *}"
      hp="${h#* }"
      case "$hp" in _memory/*) continue ;; esac
      case "$NL$cons_paths" in *"$NL$hp$NL"*) continue ;; esac
      case "$NL$unlisted" in *"$NL$hp$NL"*) continue ;; esac
      unlisted="$unlisted$hp$NL"
      finding "$hl" "hit path '$hp' is not listed as a Consumer"
    done
  fi
fi

if [ "$nf" -gt 0 ]; then
  printf 'trace-lint: %s finding(s)\n' "$nf"
  exit 3
fi
if [ "$none" -eq 1 ]; then
  printf 'trace-lint: ok (none — %s)\n' "$none_reason"
else
  printf 'trace-lint: ok (%s searches, %s consumers)\n' "$items" "$consumers"
fi
exit 0
