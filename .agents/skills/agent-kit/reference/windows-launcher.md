# Windows launcher (`.cmd`)

Canonical source: `skills/agent-kit/templates/tools/bash-launcher.cmd`. Emitters copy that
file as **raw bytes** (never through template reads that strip `\r`) to:

- `skills/agent-kit/bin/emit.cmd`
- `_kit/memory.cmd`
- `_kit/log-spawn.cmd`
- `_kit/trace-lint.cmd`
- `_kit/kit-guard.cmd` (`flags.kit_guard` installs only)
- `_kit/hook-log.cmd` (`flags.hook_telemetry` installs only)
- `_loop/loop.cmd` (loop-enabled installs only)

Each copy sits beside a same-named `.sh` and runs it through Git for Windows Bash.

## Purpose

On Windows, cmd, Windows PowerShell 5.1, and PowerShell 7 (`pwsh`) can invoke kit Bash
scripts; PowerShell 7 is not required. The launcher discovers `bash.exe`, runs the sibling `.sh` with all arguments,
and returns its exit code. Inside a harness that already runs Git Bash, agents should call
`bash path/to/script.sh` directly instead of the `.cmd` wrapper.

## Invocation examples

```bat
_kit\memory.cmd search foo
skills\agent-kit\bin\emit.cmd --answers tests/agent-kit/fixtures/self-answers.json --root .
_loop\loop.cmd 10
```

Arguments with spaces are passed through unchanged. Path **arguments** to the script should
use forward slashes (for example `--answers C:/repo/tests/fixtures/a.json`). Backslash
path arguments are not supported in this release.

## Git Bash discovery

The first **valid** candidate wins. A candidate is valid only when it is non-empty,
normalized to a full path (forward slashes and `..` are folded before checks),
`if exist` finds a file that is not a directory, and it is not a WSL stub. Invalid
candidates are skipped silently and discovery continues, and no override value can abort
the launcher:

1. `%AGENT_KIT_BASH%`
2. `%CLAUDE_CODE_GIT_BASH_PATH%`
3. From `git --exec-path` when `git` is on PATH: output uses forward slashes; convert to
   backslashes, take `<root>\bin\bash.exe` where `<root>` is three levels up from the
   reported directory (covers `mingw64`, `mingw32`, `clangarm64` installs)
4. `%ProgramFiles%\Git\bin\bash.exe`
5. `%LOCALAPPDATA%\Programs\Git\bin\bash.exe`

Set `AGENT_KIT_BASH` to override discovery (for example a non-standard Git install).
Double quotes inside `AGENT_KIT_BASH` or `CLAUDE_CODE_GIT_BASH_PATH` are removed before
the value is checked, so a quoted path with or without spaces (for example
`set AGENT_KIT_BASH="C:\Program Files\Git\bin\bash.exe"`) is used when it is valid. An
override that is empty, names a missing file or a directory, or points at a WSL stub is
skipped like any other invalid candidate.

## WSL stubs (never selected)

These paths are rejected even when named by an override (case-insensitive):

- Any path ending in `\Microsoft\WindowsApps\bash.exe`
- `%SystemRoot%\System32\bash.exe`

## Script path and exit codes

The launcher runs `%~dpn0.sh` (same base name as the `.cmd`, same directory) with `%*`.
The script path passed to Bash uses forward slashes (`set "S=%S:\=/%"`) so MSYS
`dirname "$0"` resolves correctly when `--kit` is omitted.

On success, the process exit code is the script's exit code (the launcher invokes Bash,
then uses a bare `exit /b` so the child exit code is preserved). The launcher uses
`setlocal`, clears any inherited `AK_BASH` after `setlocal`, and does not enable delayed
expansion (so `!` in arguments is preserved).

When no valid Git Bash is found, stderr receives exactly one line (then exit 127):

```text
agent-kit: Git Bash not found - install Git for Windows from https://git-scm.com/download/win or set AGENT_KIT_BASH to the full path of bash.exe.
```

## Emitter contract

- Store committed `.cmd` files with CRLF bytes; root `.gitattributes` includes `*.cmd -text`
  so git does not normalize line endings on checkout.
- Copy `.cmd` launchers with a byte-preserving copy (`cp`, `Copy-Item -AsByteStream`, or
  equivalent). Do not read them through `read_file_raw_into` or other CR-stripping paths.
- Loop-enabled emits also copy `templates/tools/bash-launcher.cmd` to `_loop/loop.cmd` beside
  `_loop/loop.sh` (same byte-preserving rules as the other launchers).

## Loop on Windows: known limitations

The Windows CI leg (`windows-latest`, Git Bash) confirms both behaviors; the maintainer check
`tests/agent-kit/templates/loop-windows.sh` reports them as `INFO` lines.

1. **Orphaned native processes after kill or timeout** — stopping a slot (iteration timeout,
   manual kill, or breaker-driven termination) under Git Bash leaves native Windows child
   processes running (`claude.exe`, `codex.exe`, and similar). After a killed or timed-out run,
   check Task Manager or your process list and end stray harness CLI processes.
2. **`LOOP_CLI` and `.cmd` shims** — Git Bash does not resolve a bare `LOOP_CLI` command to a
   `.cmd` shim such as `cursor-agent.cmd`. Workaround: name the shim with its suffix, for example
   `LOOP_CLI="cursor-agent.cmd -p …"`. Caveat: a `.cmd` shim runs through `cmd.exe`, which cuts
   an argument at its first newline and re-reads `"`, `&`, and `%` — the loop passes the whole
   prompt as one argument (`"$p"` to the CLI), so prefer the CLI's native `.exe` (or its `node`
   entry point) when one exists.
