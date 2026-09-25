# Agent tooling — what works, what does NOT (measured 2026-09-25)

**Purpose.** The API hands every agent a set of file tools. Re-implementing one of
them with a shell command is a defect: it is slower, it pollutes the transcript,
and it hides the mistake (a `grep` that returns nothing looks like "the code is
not there"). This file says which tool to reach for, and which invocations are
broken in this build, so the next agent starts from measurement instead of
folklore.

It names no project paths on purpose: **copy it into any project as-is.** The
project's own `AGENTS.md` should carry the one-line rule and point here.

## The rule

| job | tool | never |
| --- | --- | --- |
| read a file | `read_files` **with** `{path, offset, limit}` | `cat`, `head`, `tail`, `sed -n` |
| find a string / symbol | `code_search` (no flags) | `grep`, `rg` |
| find a file by name | `glob` | `find`, `ls -R` |
| list a directory | `list_directory` | `ls`, `dir` |
| create / overwrite a file | `write_file` | `echo >`, heredoc, `tee` |
| edit a file | `str_replace` | `sed -i`, `awk`, a one-off script |
| plan multi-step work | `write_todos` | a prose checklist |
| run anything else | `run_terminal_command`, **bounded** by `timeout_seconds` | an unbounded command |

The terminal is legitimate for exactly four jobs: **compiling**, **git**,
**moving/deleting files** (no delete tool exists — `rm`/`mv` is the exception),
and **running the project's tests**. Everything else has a tool.

## Measured matrix (Windows, this app build, 2026-09-25)

| tool / invocation | verdict | evidence |
| --- | --- | --- |
| `read_files {path, offset, limit}` | ✅ | reports "showing lines a–b of N", so you also learn the size |
| `read_files` with a bare path | ⚠️ **context bomb** | read up to 2000 lines into the transcript; an 860-line file arrived whole |
| `read_files` on a missing file | ✅ clean | returns `[FILE_DOES_NOT_EXIST]`, no exception |
| `read_files` outside the project | ⛔ **blocked** | an absolute path outside the workspace also returns `[FILE_DOES_NOT_EXIST]` — file tools cannot reach outside the project |
| `read_files` on a **gitignored** path | ⛔ **`[BLOCKED]`** | re-measured 2026-09-25: `build-logs/_gate3.txt` (file inside an ignored dir) and `tests/*.ex4` (ignored by pattern) BOTH answer a bare `[BLOCKED]`; a **tracked** binary reads fine — `docs/media/ring.png` came back as a 291 KB image. So the ignore list is the gate, not the file type. Fetch an ignored file with the terminal instead (`grep -a`; MetaEditor logs are UTF-16) |
| `write_file` | ✅ | create and overwrite both verified |
| `str_replace` (several replacements in one call) | ✅ | 15 single-line `#define` rewrites landed in one call |
| `str_replace` with a multi-line `oldString` on a **CRLF** file | ✅ | verified 2026-09-25: a 55-line comment+function block in `BiotakPanels.mqh` (CRLF) matched with plain `\n` separators; the tool normalises the ending. A mismatch is still a clean no-op |
| `str_replace` with `allowMultiple: true` | ✅ | one call rewrote 51 repeated `#include` lines; never loop a script for this |
| `str_replace` on a missing file | ✅ clean | "The file does not exist, skipping…" |
| `str_replace` whose `oldString` does not match | ✅ safe | the call errors and nothing is written |
| `glob` | ✅ but **gitignore-aware** | `tests/*.ex4` → 0 files although 6 exist on disk (they are ignored). Use `list_directory` to see ignored files |
| `list_directory` | ✅ | files and dirs; a missing path returns a clean `errorMessage`. It also **sees gitignored entries** and follows a directory junction (it listed the six ignored `tests/*.ex4` and the linked `tests/Files/Icons`) |
| `code_search` (no flags) | ✅ | file + line numbers |
| `code_search -n` | ✅ | line numbers |
| `code_search -i` | ✅ | case-insensitive |
| `code_search -g '*.mqh'` | ✅ | file-type / glob filter; several globs in one call also work (`-g *.mqh -g *.mq4`) |
| `code_search -A n` / `-B` / `-C` | ✅ | context lines |
| `code_search -l` | ❌ **broken** | always `Found 0 matches`, even for strings that exist. Re-measured 2026-09-25: `-l` answered `Found 0 matches` for `BioSwatchBorder` while the same pattern found **11** hits without flags — the control that proves the tool, not the code |
| `code_search -c` | ❌ **broken** | always `Found 0 matches` (same re-measure as `-l`) |
| `code_search maxResults` | ✅ | caps hits *per file* and says so when it truncates |
| `code_search cwd` | ⚠️ **must be a DIRECTORY** | re-measured 2026-09-25: `cwd: "Biotak/BiotakMenu.mqh"` (a file) fails with a raw `Failed to execute ripgrep: ENOENT ... rg.exe` — while that very `rg.exe` sits on disk (5.4 MB, `ls`-verified) and the identical call with `cwd: "Biotak"` answers normally. A file as `cwd` is the bug, not the binary; use the *directory* or `-g <glob>` |
| `run_terminal_command` SYNC | ✅ | stderr and `exitCode` are surfaced; always pass `timeout_seconds` |
| `run_terminal_command` BACKGROUND | ❌ **not implemented** | replies "BACKGROUND process_type not implemented" — no dev server or watcher can be left running |
| `run_file_change_hooks` | ❌ **not implemented** | replies "File change hooks are not supported in SDK mode"; do not spend a step on it |
| `preview_status` | ✅ | tabs + profiles |
| `register_preview {htmlPath}` | ✅ | serves a workspace `.html` on `http://127.0.0.1:<port>/<file>`; no dev server needed |
| `preview_open` | ✅ | public/localhost URLs; returns a tab id |
| `preview_snapshot` | ✅ | accessibility tree with `uid=` handles |
| `preview_click` / `preview_type` / `preview_press` | ✅ | both `uid=` and Playwright locators (`#id`, `role=button[name="go"]`) work |
| `preview_scroll` / `preview_resize` / `preview_set_color_scheme` | ✅ | |
| `preview_evaluate` | ✅ | JSON-serialised result, promises awaited |
| `preview_logs` | ✅ | console + network since attach, `clear:` supported |
| `preview_screenshot` | ✅ | returns the image; the only way to see layout/rendering |
| `preview_wait` | ✅ | `selector` / `text` / `urlIncludes` |
| `preview_navigate` | ✅ | `reload` / `back` / `forward` / a URL |
| `preview_recording_start` / `_stop` | ✅ | writes a `.webm` under the app's `browser-recordings` dir |
| `preview_close` | ✅ | closes the tab, does not stop its dev server |
| `web_search` / `read_url` | ✅ | `read_url` returns status, title, truncated text |
| `write_todos` | ✅ | |
| `ask_questions` / `suggest_prompts` | ✅ | block/announce at the right moment |
| `read_thread_context` | ℹ️ | needs an explicit `@thread` mention in the prompt; unusable without one |
| `report_project_profile` | ℹ️ internal | only when a prompt asks for the project profile |

## Fast paths (why the measurement matters)

1. **Locate, then read a window.** `code_search "Symbol"` → `read_files {path,
   offset: <hit-40>, limit: 80}`. Never a bare path on a source file.
2. **One call per repeated edit.** `str_replace` with `allowMultiple: true`
   rewrites every occurrence of a pattern in a file; the same job as a rewrite
   script, without the script.
3. **Two calls per flag question.** When a search returns 0, re-ask without
   flags before believing it — `-l`/`-c` are broken, so a zero can be the tool.
4. **Bound every terminal command.** The runner blocks on the command it waits
   for: a long command does not fail, it HANGS the session. One bounded command
   per step; a hand-rolled loop over many gates is the classic way to wedge it.
5. **Verification order.** Cheap syntax check first (`bash -n`, `node --check`,
   a parser/API parse), then the real build, then the behavioural test. A build
   The build log is the one exception to the tool rule: MetaEditor writes it as
   **UTF-16**, and a log inside a gitignored dir reads as `[BLOCKED]` — so the
   result line is pulled with one bounded command,
   `grep -aoE "Result: *[0-9]+ *error[s]?" <log> | tail -1`, and the report names
   that command (AGENTS.md's "say which command did what").
6. **Delete with the terminal, deliberately.** There is no delete tool, so
   `rm`/`mv` is expected — but do it in its own step, name the paths in the
   report, and never delete a file that a live preview is serving (its reload
   then reports "no load event").
7. **Ignored files are invisible** to `glob`, `code_search` **and** `read_files`
   (`[BLOCKED]`). Only `list_directory` still sees them — that is how you audit a
   gitignored build directory (`tests/*.ex4`) — and the terminal is how you read
   one. The reverse is worth knowing: a tracked binary is readable, rendered as an
   image, so a screenshot in the repo is legitimate evidence.
