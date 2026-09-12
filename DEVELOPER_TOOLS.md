# Jairus — Phase 17: Developer Tools

**Migration step:** Phase 17 of `JAIRUS_ARCHITECTURE.md` Part 14.19, Part
15.11 ("V1 Developer Tools" — "Limited... enough to make Jairus useful
during development without handing the LLM unrestricted terminal
access"), Part 23's catalog, and Part 24/91's explicit V1 exclusions
("unrestricted shell", "unrestricted PowerShell").

**One-sentence summary:** five new `developer.*` tools — `git_status`,
`git_diff`, `run_tests`, `search_code`, `open_project` — let the
assistant inspect a repo's state, diff it, run its tests, grep its code,
and open it in VS Code, with **no general shell/terminal capability
anywhere** in the implementation; **nothing reaches this from voice
yet**, same as every phase since 7.

---

## The security boundary this phase is built inside of

Part 91 explicitly excludes "unrestricted shell execution" and
"unrestricted PowerShell" from V1 — Part 14.19 spells out exactly why:
"Give the LLM unrestricted PowerShell... that's a security disaster
waiting to happen." Every function in `dev_tools.py` is built to make
that structurally impossible, not just discouraged by convention:

| Tool | How it avoids being a shell |
|---|---|
| `git_status` / `git_diff` | `subprocess` with a **fixed argv list** per call (e.g. `["git", "-C", repo_path, "status", "--porcelain"]`) — never `shell=True`, never a command string built by concatenating caller input. `git_diff`'s optional `file_path` is passed after a `--` separator so a value starting with `-` is defused as a literal path, never interpreted as a flag. |
| `search_code` | Does **not** shell out to `grep`/`findstr`/`ripgrep` at all. Pattern matching is implemented directly in Python: `os.walk` (via `pathlib.Path` wrapping) for file discovery, `re` for line matching. A caller supplies a search term and gets matches back; it never controls what program runs. |
| `run_tests` | Invokes exactly one hardcoded command shape: `[sys.executable, "-m", "pytest", repo_path, "-q", "--no-header"]`. A caller supplies only `repo_path` — there is no way to pass an arbitrary command, arbitrary flags, or a different program. |
| `open_project` | A single-purpose wrapper around `[code_cli, path]` (`code_cli` resolved via `shutil.which`) — nothing else, no shell, no other arguments accepted. |

Every function also validates its input and returns a clean failure value
rather than raising — same discipline as every prior infrastructure
module (`apps.py`, `fs_tools.py`).

---

## What was built

### New: `src/jairus/infrastructure/developer/dev_tools.py`

```python
def git_status(repo_path: str) -> dict
def git_diff(repo_path: str, file_path: str | None = None) -> str
def run_tests(repo_path: str) -> dict
def search_code(repo_path: str, query: str, file_pattern: str = "*.py") -> list[dict]
def open_project(path: str) -> bool
```

| Function | Notes |
|---|---|
| `git_status` | Parses `git status --porcelain` into `{is_git_repo, clean, staged, modified, untracked}`. A path that isn't a directory or isn't a git repo returns the same shape with `is_git_repo=False` and everything empty — never raises. |
| `git_diff` | Full working-tree diff, or one file's diff if `file_path` is given. Capped at `MAX_DIFF_CHARS` (50,000) — same bounding spirit as Phase 16's `max_bytes` on `read_file` — with a truncation note appended if the real diff was longer. Returns `""` both for "no diff" and "not a git repo," the same ambiguity `APPS_TOOLS.md` already accepted for `apps.close` returning `False` for "nothing to close." |
| `run_tests` | Runs `pytest` with a fixed argument set. Returns `{"ran": bool, "output": str, "passed": bool \| None}` — `passed=None` covers both "pytest ran but collected zero tests" (pytest's own exit code 5) and "pytest itself isn't installed in this interpreter," both honest non-verdicts rather than a fabricated pass/fail. `ran=False` is reserved for "the subprocess itself couldn't produce a verdict at all" (bad path, pytest not importable, timeout). |
| `search_code` | Walks `repo_path` with `os.walk`, **pruning** (not just filtering) `venv/`, `__pycache__/`, `.git/`, `node_modules/` wherever they appear, so it never descends into them at all. Matches `query` as a literal substring via a `re.escape()`-d compiled pattern — genuinely uses `re` for the match without ever exposing caller-controlled regex syntax (and the ReDoS risk that would come with it). Capped at `MAX_SEARCH_MATCHES` (500). A file that isn't valid UTF-8 is skipped, not garbled into false matches. |
| `open_project` | Resolves the `code` CLI via `shutil.which()` first — `subprocess` with `shell=False` doesn't consult `PATHEXT` the way a real shell does, and VS Code's CLI on Windows is a `.cmd` shim, not a bare `.exe`; without this resolution step the call fails with `WinError 2` even though `code` genuinely is on `PATH` (found and fixed during this phase's own testing, see below). Still a fixed two-element argv list, still no shell. |

### New: `src/jairus/tools/developer_tools.py`

Defines `DEVELOPER_TOOLS: list[ToolDefinition]`:

| Tool name | permission_level | requires_confirmation |
|---|---|---|
| `developer.git_status` | `HARMLESS` | `False` |
| `developer.git_diff` | **`DANGEROUS`** | **`True`** |
| `developer.run_tests` | **`DANGEROUS`** | **`True`** |
| `developer.search_code` | **`DANGEROUS`** | **`True`** |
| `developer.open_project` | `HARMLESS` | `False` |

Registration is explicit: `register_developer_tools()`, same pattern as
every prior `register_*_tools()`.

### Changed: `src/jairus/tools/executor.py`

Extended `_handlers()` with five new entries mapping the five
`developer.*` tools to the matching `dev_tools` function, same
try/except/`ToolResult` shape as every prior phase. All other mappings
are untouched.

### Changed: `src/jairus/tools/__init__.py`

Now also re-exports `DEVELOPER_TOOLS` and `register_developer_tools`.

---

## Permission-level reasoning (called out explicitly, same prominence as Phase 16's `filesystem.read`)

Two of these five were easy: `git_status` returns filenames and
one-letter status codes, never content — same category as
`filesystem.list`. `open_project` just launches an editor window on a
path — same reasoning as `apps.launch`/`game.launch` (Part 25's own Level
0 example, "launch application"). Both **`HARMLESS`**.

The other three needed real thought, not a reflex classification:

**`git_diff` and `search_code` — both expose file content, the same
category of concern that made `filesystem.read` `DANGEROUS` last phase.**
The task this phase was built against explicitly asked: does being
scoped to "this repo" change that calculus? Considered seriously, and
the answer landed on **no**, for two concrete reasons:

1. `repo_path` is fully caller-supplied, with no enforced path-scoping —
   the same gap flagged in Phase 16 (the Policy Engine remains
   shadow-only; nothing restricts `repo_path` to "the actual Jairus
   project" specifically, or to any allow-listed root at all). "Scoped to
   a repo" is not the same guarantee as "scoped to a known-safe repo."
2. The narrowing that genuinely exists is real but partial — a
   difference of degree, not of kind. `git_diff` only shows *changed*
   lines of *tracked* files, smaller than a full file dump, but a secret
   accidentally pasted into a tracked config mid-edit shows up in a diff
   exactly as readily as it would in a raw `filesystem.read`.
   `search_code` is, if anything, *less* scoped than `git_diff`: it
   matches full line content of any file under `repo_path` matching
   `file_pattern` — tracked, untracked, or gitignored — subject only to
   skipping `venv/`/`__pycache__/`/`.git/`/`node_modules/`, not to
   whether the file is even meant to be part of the project.

Both are therefore kept at the same tier as `filesystem.read`:
**`PermissionLevel.DANGEROUS`, `requires_confirmation=True`.** Part 25
doesn't define an intermediate tier for "somewhat narrower content
exposure," and inventing one ungrounded in the architecture's own
four-level taxonomy would be a worse outcome than reusing the tier that
already, honestly, fits.

**`run_tests` — also `DANGEROUS`, but for a categorically different
reason than the two tools above.** This isn't content *disclosure*, it's
code *execution*. `pytest` imports and runs whatever test
modules/`conftest.py` files actually exist at `repo_path` — the fixed,
hardcoded invocation constrains *how* the tool is invoked, not *what code
runs* once `pytest` starts collecting. That's a strictly more powerful
capability than any read-oriented tool in this project so far, which is
exactly why it's held at the ceiling of this project's permission
taxonomy rather than defaulted down just because this particular repo
doesn't have a real test suite to run yet. The classification is about
the capability the tool grants, not today's contents of this one repo —
a repo with a compromised or malicious test file would make that
concrete immediately.

No tool here defaults to `HARMLESS` for convenience, and none is pushed
to `DANGEROUS` reflexively either — the two genuinely metadata-only tools
stay `HARMLESS`, and the three content/execution tools are held at the
same ceiling `filesystem.read` established last phase, for two distinct,
individually-argued reasons rather than one blanket rule.

---

## What was explicitly NOT touched

Confirmed via empty `git diff` on all of: `intent_parser.py`,
`assistant_loop.py`, `command_gateway.py`, `task_manager.py`,
`player_action.py`, `apps.py`, `windows_ui.py`, `browser.py`, `games.py`,
`game_registry.py`, `fs_tools.py`, `filesystem_tools.py`,
`agent_core.py`, `policy_engine.py`, `voice_adapter.py`, `main.py`, and
everything under `interfaces/android/`.

- **`intent_parser.py`.** No `developer.*` action exists in its
  `SYSTEM_PROMPT` or JSON shape. The live assistant has zero concept of
  "developer tools" as a domain after this phase.
- **The executor's existing mappings.** Only new entries were added to
  `_handlers()`'s returned dict.
- **The user-facing behaviour.** Run `python main.py` — it behaves
  exactly as before. Nothing calls `execute_tool("developer....", ...)`
  outside tests.

## What Phase 17 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Voice reachability for `developer.*` (intent parsing, dispatch) | Part 14.10–14.13 (Agent Core, then legacy-routing removal) |
| `developer.terminal` (any general command execution) | Part 14.19's own words: "Only later... and even then, it should be heavily controlled." Not a planned near-term phase. |
| Policy Engine actually enforcing `permission_level`/confirmation (including the three `DANGEROUS` gates here) | Later hardening |

---

## Verification performed

`python -m compileall` is clean on the new and changed files. `git diff`
on every protected file/path listed above is empty.

Tested against **this repo itself** (`voice_command_experiment`) — the
one real git repository available, and appropriate here unlike Phase 16
(which deliberately used a throwaway fixture to avoid touching real
files, since `filesystem.read`/etc. had no reason to need a real repo).
One harmless, fully-reverted edit was made to `README.md`, plus one
throwaway untracked file, both cleaned up by the end of the test run.

All via `execute_tool()`:

1. **Baseline `git_status`** — accurately reported this session's actual
   in-progress changes (`modified`: `src/jairus/tools/__init__.py`,
   `executor.py`; `untracked`: the new Phase 17 files, plus a
   pre-existing untracked `CLAUDE.md` from earlier in the session).
2. Created a throwaway untracked file
   (`phase17_test_scratch.txt`) — `git_status` correctly added it to
   `untracked`.
3. Appended a blank line to `README.md` — `git_status` correctly moved it
   into `modified`.
4. `git_diff(repo_path, "README.md")` — returned the real, correct diff
   (`+` a single blank line at the end of the file).
5. Reverted `README.md` to its original bytes and deleted the scratch
   file — `git_status` afterward matched the original baseline exactly;
   `git diff --stat -- README.md` outside the tool confirmed zero
   remaining diff.
6. `git_diff(repo_path)` with no `file_path` — returned the real,
   accurate diff of this phase's own in-progress `executor.py`/`__init__.py`
   changes.
7. `run_tests(repo_path)` — returned
   `{"ran": False, "output": "...No module named pytest", "passed": None}`.
   Honest and correct: this project's venv has no `pytest` installed and
   no test suite exists yet — exactly the "no fake tests invented" outcome
   the phase called for, one level more honest than "ran, found nothing"
   since the runner itself couldn't start.
8. `search_code(repo_path, "def run_assistant", "*.py")` — found exactly
   one real match: `assistant_loop.py:165`, the actual
   `def run_assistant(state):` definition.
9. `search_code` with an empty query — `[]`, no attempt made.
10. `open_project(repo_path)` — **initially failed** with `WinError 2`
    (`code` not found) despite `code` genuinely being on `PATH` — this
    surfaced the real Windows `subprocess`/`PATHEXT`/`.cmd`-shim gap
    described above. Fixed by resolving the CLI via `shutil.which()`
    first, then re-verified: returned `{"opened": True}`, and a real VS
    Code process (`Code.exe`) was confirmed running afterward via
    `tasklist`.
11. `open_project` on a nonexistent path — `{"opened": False}`, no
    exception.

`python main.py` was run afterward and blocked normally on the orb UI
with only the same benign
`Tried to import the tflite runtime...switching to onnxruntime` warning
seen in every prior phase's regression check — no crash, no traceback.

## Known limitations

- `run_tests` has never actually observed a passing or failing test in
  this project, since none exist yet — its `passed=True`/`False` paths
  are implemented and reasoned about, but only exercised against a real
  suite once one exists (a natural byproduct of Phase 17 landing before
  this project has tests of its own).
- `open_project`'s Windows `.cmd`-shim resolution (`shutil.which`) is
  Windows-specific; a cross-platform `code` binary (a real executable, no
  shim) on macOS/Linux would have worked without it, so this fix is
  necessary specifically because this project targets Windows.
- No path-scoping/sandboxing exists for any of these tools yet, same gap
  flagged for `filesystem.read` last phase — `requires_confirmation` is
  currently the only gate in front of the three `DANGEROUS` tools here.
