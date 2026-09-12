# Jairus — Phase 16: Filesystem Tools (Read-Only)

**Migration step:** Phase 16 of `JAIRUS_ARCHITECTURE.md` Part 14.18, Part
15.9 ("V1 Filesystem" — "Start read-only... Then eventually
`filesystem.create/modify/move/delete` with increasingly strict policy" /
"No deletion yet"), and Part 23's catalog.

**One-sentence summary:** four new `filesystem.*` tools — `search`,
`list`, `read`, `exists` — let the assistant look at files and
directories, backed by a brand-new `fs_tools.py` module that contains
**zero** write/delete/move capability anywhere in it, not even as an
unregistered helper; **nothing reaches this from voice yet**, same as
every phase since 7.

---

## Scope: this is the read-only half, and only the read-only half

Part 14.18's own sequencing draws a hard line: read-only now,
write/delete/move "eventually... with increasingly strict policy." This
phase treats that as a stronger boundary than prior phases' usual "don't
wire it up yet" — there is no code path in `fs_tools.py` capable of
mutating the filesystem, period. No `write_file`, no `delete_file`, no
`move_file`, not even as dead code. That capability belongs entirely to a
later phase.

---

## What was built

### New: `src/jairus/infrastructure/filesystem/fs_tools.py`

```python
def search_files(directory: str, pattern: str) -> list[str]
def list_directory(path: str) -> list[dict]
def read_file(path: str, max_bytes: int = 100_000) -> str | None
def path_exists(path: str) -> bool
```

All four validate their input up front and return a clean failure value
(`[]`, `None`, or `False`) for a missing/invalid path — same discipline
`apps.py` uses (e.g. `close_app` returning `False` instead of raising).

| Function | Backend | Notes |
|---|---|---|
| `search_files` | `pathlib.Path.glob` | Glob-style pattern (`"*.py"`, `"**/*.py"`). Two bounds against pathological input: (1) a recursive (`"**"`) pattern rooted at a filesystem root (e.g. `"C:\\"`) is **rejected outright** — not truncated, not attempted — since that's exactly the "walk the entire C:\ drive" case called out in the task; (2) results are capped at `MAX_SEARCH_RESULTS` (1000) regardless, so even a broad-but-legitimate recursive search can't return an unbounded set. |
| `list_directory` | `pathlib.Path.iterdir` + `stat()` | Non-recursive — immediate children only. A directory entry's own `size` is reported as `0`; this never recurses to compute a directory's total size. An entry that can't be `stat()`'d (permission denied, removed mid-listing) is skipped, not fatal to the whole call. |
| `read_file` | plain `open(..., "rb")` | Reads **at most** `max_bytes` — the cap is enforced at the read call itself, so a large file is never loaded whole into memory just to be truncated afterward. Returns `None` for a missing path, a directory, a permission error, or a file that fails UTF-8 decoding (the binary-file signal), never an exception. |
| `path_exists` | `pathlib.Path.exists` | Returns `False`, not an exception, for an unusable path string. |

### New: `src/jairus/tools/filesystem_tools.py`

Defines `FILESYSTEM_TOOLS: list[ToolDefinition]`:

| Tool name | permission_level | requires_confirmation |
|---|---|---|
| `filesystem.search` | `HARMLESS` | `False` |
| `filesystem.list` | `HARMLESS` | `False` |
| `filesystem.read` | **`DANGEROUS`** | **`True`** |
| `filesystem.exists` | `HARMLESS` | `False` |

Registration is explicit: `register_filesystem_tools()`, same pattern as
every prior `register_*_tools()`.

### Changed: `src/jairus/tools/executor.py`

Extended `_handlers()` with four new entries mapping `filesystem.search` /
`filesystem.list` / `filesystem.read` / `filesystem.exists` to the
matching `fs_tools` function, same try/except/`ToolResult` shape as every
prior phase. All other mappings (`media.*`, `apps.*`, `game.*`,
`browser.*`, `windows.*`) are untouched.

### Changed: `src/jairus/tools/__init__.py`

Now also re-exports `FILESYSTEM_TOOLS` and `register_filesystem_tools`.

---

## Permission-level reasoning for `filesystem.read` (called out explicitly, per request)

The other three tools were easy calls: `search` returns matching
*paths*, `list` returns names/flags/sizes for one directory's immediate
children, and `exists` returns a single boolean. None of them reveal what
is actually *inside* any file. All three are pure metadata, comparable to
Part 25's own Level 0 examples ("search," "read system information"), so
all three are **`HARMLESS`**.

`filesystem.read` is not that. It returns actual file *contents*, and
this project has already run into exactly why that matters, for real,
once before: `RECONNAISSANCE.md` documents `browser_profile/` — a full
Brave user-data profile directory that was sitting checked into this
repo's own working tree. That is precisely the kind of directory
(cookies, saved-session tokens, potentially saved credentials) an
unscoped file-reader could be pointed at and return in full, exactly as
readily as it would return the text of a README. There is currently **no
path scoping or sandboxing anywhere** to prevent that — no allow-list, no
restricted root — because the Policy Engine that would eventually enforce
such a thing is still shadow-only (Phase 11). `requires_confirmation`
being `True` is the *only* gate standing between "read this README" and
"read this `.env` file / SSH private key / browser cookie database"
today.

Weighing the actual permission level, not just defaulting upward for
safety:

- **Not `DISRUPTIVE` (Level 1).** Part 25's Level 1 examples ("close
  application," "terminate process," "change certain system state") are
  all about causing a state change the user can observe going wrong and,
  in spirit, walk back. A file read changes nothing and has no visible
  side effect at all — which, perversely, makes it *harder* to notice
  going wrong, not easier.
- **Not `DESTRUCTIVE` (Level 2).** Its examples ("delete file," "overwrite
  data," "uninstall software") are about data loss. Reading doesn't
  delete or overwrite anything.
- **`DANGEROUS` (Level 3) fits directly.** Part 25's own Level 3 examples
  are "administrator operations," "security configuration," and
  **"credential-related actions."** An unscoped `filesystem.read` is
  exactly a credential-access vector once pointed at the right path — not
  hypothetically, but demonstrated by this exact repo's own
  `browser_profile/` precedent. The disclosure is also asymmetric with
  every other tool built so far: closing an app or invoking a UI control
  is a visible action the user could in principle notice and react to; a
  quiet file read that exfiltrates a secret has no equivalent visible
  side effect and no do-over once it's happened.

`filesystem.read` is therefore set to **`PermissionLevel.DANGEROUS`,
`requires_confirmation=True`** — the first tool in this project
classified at that level. This is a deliberate flag, not an oversight:
real path scoping (e.g. restricting reads to an explicit allow-listed
root, excluding things like `browser_profile/`, `.env`, `.ssh/`) is a
known, real future need that does not exist yet, called out here rather
than silently deferred to "later hardening" the way Policy Engine
enforcement itself has been for every phase so far.

---

## What was explicitly NOT touched

Confirmed via empty `git diff` on all of: `intent_parser.py`,
`assistant_loop.py`, `command_gateway.py`, `task_manager.py`,
`player_action.py`, `apps.py`, `windows_ui.py`, `browser.py`,
`agent_core.py`, `policy_engine.py`, `voice_adapter.py`, `main.py`,
`games.py`, `game_registry.py`, and everything in `interfaces/android/`.

- **`intent_parser.py`.** No `filesystem.*` action exists in its
  `SYSTEM_PROMPT` or JSON shape. The live assistant has zero concept of
  "filesystem" as a domain after this phase.
- **The executor's existing `media.*`/`apps.*`/`game.*`/`browser.*`/
  `windows.*` mappings.** Only new entries were added to `_handlers()`'s
  returned dict.
- **The user-facing behaviour.** Run `python main.py` — it behaves exactly
  as before. Nothing calls `execute_tool("filesystem....", ...)` outside
  tests.

## What Phase 16 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Voice reachability for `filesystem.*` (intent parsing, dispatch) | Part 14.10–14.13 (Agent Core, then legacy-routing removal) |
| `filesystem.create` / `modify` / `move` / `delete` | Later, "with increasingly strict policy" (Part 14.18/15.9's own words) |
| Path scoping / sandboxing (restricting reads to an allow-listed root) | Flagged above as a known future need; not built yet |
| Policy Engine actually enforcing `permission_level`/confirmation (including `filesystem.read`'s `DANGEROUS` gate) | Later hardening |

---

## Verification performed

`python -m compileall` is clean on the new and changed files. `git diff`
on every protected file/path listed above is empty.

Tested against a throwaway fixture directory created and destroyed by the
test itself — never against the person's real Documents/Desktop/existing
files (same caution Phase 9 applied to Notepad, applied proactively here):

```text
fs_test_fixture/
├── hello.txt      "Hello, Jairus!"
├── binary.bin     b'\xff\xfe\x00\x01\x80\x81'
└── sub/
    └── notes.md   "# Test notes\n"
```

All via `execute_tool()`:

1. `filesystem.search` for `"*.txt"` in the fixture root — found exactly
   `hello.txt`.
2. `filesystem.search` for `"**/*.md"` (recursive) — found
   `sub/notes.md`.
3. `filesystem.search` on `"C:\\"` with pattern `"**/*"` — rejected
   outright (`{"matches": []}`, logged as refused) rather than attempting
   to walk the drive, confirming the pathological-input guard.
4. `filesystem.list` on the fixture root — returned all three top-level
   entries (`hello.txt`, `binary.bin`, `sub`) with correct `is_dir`/`size`.
5. `filesystem.list` on a nonexistent path — `{"entries": []}`, no
   exception.
6. `filesystem.read` on `hello.txt` — `{"content": "Hello, Jairus!"}`.
7. `filesystem.read` on `binary.bin` — `{"content": None}`, confirming
   clean binary-file handling.
8. `filesystem.read` on a nonexistent file — `{"content": None}`.
9. `filesystem.exists` on `hello.txt` — `{"exists": True}`.
10. `filesystem.exists` on a nonexistent path — `{"exists": False}`.

Fixture directory was removed at the end of the test run (confirmed
`exists=False` afterward).

`python main.py` was run afterward and blocked normally on the orb UI
with only the same benign
`Tried to import the tflite runtime...switching to onnxruntime` warning
seen in every prior phase's regression check — no crash, no traceback.
