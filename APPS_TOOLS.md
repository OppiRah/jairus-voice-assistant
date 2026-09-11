# Jairus — Phase 7: Application Tools

**Migration step:** Phase 7 of `JAIRUS_ARCHITECTURE.md` (Part 14.9), adding
genuinely new application-control capabilities per Part 23's catalog, built
on Part 19's automation backend hierarchy (native OS APIs first) and using
the permission levels Part 25 gives as examples.

**One-sentence summary:** the assistant can now really launch, close,
focus, detect, and list Windows applications — five new `apps.*` tools,
backed by real (not stubbed) automation code — but **nothing reaches this
from voice yet**: `intent_parser.py` has no concept of "apps" as a domain.

---

## What's different from Phases 5-6

`media.*` wrapped **existing** code (`player_action.py`) that already
worked and was already reachable from voice. There was nothing to write,
only to describe and re-expose.

`apps.*` is **new** — there was no application-control code anywhere in
this repo before this phase. `jairus/infrastructure/automation/apps.py` is
real, working Windows automation, written from scratch this phase,
following Part 19's stated hierarchy: prefer plain native OS APIs over
anything fancier.

---

## What was built

### New: `src/jairus/infrastructure/automation/apps.py`

```python
def launch_app(path_or_name: str) -> bool
def close_app(process_name: str) -> bool
def focus_app(process_name: str) -> bool
def detect_app(process_name: str) -> bool
def list_running_apps() -> list[str]
```

Backend per function, per Part 19's hierarchy (native OS API first):

| Function | Backend | Notes |
|---|---|---|
| `launch_app` | `os.startfile` | Same mechanism as double-clicking in Explorer — resolves a bare name (`"notepad.exe"`) via PATH/App Paths, or takes a full path. |
| `close_app` | `psutil` `Process.terminate()` | A graceful close request per matching process, then `psutil.wait_procs(..., timeout=5)` to confirm exit — not a forced kill. Returns `False` if nothing matched, or if any match didn't actually exit. |
| `detect_app` | `psutil.process_iter` | Case-insensitive name match. |
| `list_running_apps` | `psutil.process_iter` | Distinct process names, sorted. |
| `focus_app` | `pywin32` (`win32gui`, `win32process`, `win32api`) | Finds the target process's PID(s) via `psutil`, enumerates top-level windows for the first visible, titled one owned by one of those PIDs, then `ShowWindow(SW_RESTORE)` + `SetForegroundWindow`. Windows refuses a bare `SetForegroundWindow` call from a background process (like a terminal-launched script) by default — worked around with the standard technique of synthesizing a harmless Alt key tap (`keybd_event`) immediately beforehand, which satisfies Windows' "did this process just receive input" check. Confirmed working in the live test below (initially failed without the key-tap workaround; fixed and re-verified). |

**Deliberately not built:** Windows UI Automation (finding controls inside
a window, typing into fields, clicking buttons). These functions only
launch/close/focus/detect whole applications as black boxes — Part 14.9's
sibling, Phase 9, is where UI Automation belongs.

### New: `src/jairus/tools/app_tools.py`

Defines `APP_TOOLS: list[ToolDefinition]`:

| Tool name | permission_level | requires_confirmation |
|---|---|---|
| `apps.launch` | `HARMLESS` | `False` |
| `apps.close` | `DISRUPTIVE` | `True` |
| `apps.focus` | `HARMLESS` | `False` |
| `apps.detect` | `HARMLESS` | `False` |
| `apps.list_running` | `HARMLESS` | `False` |

`apps.close` is `DISRUPTIVE`/`requires_confirmation=True` per Part 25's own
"close application" example — set correctly now as **data**, even though
no Policy Engine or confirmation flow exists yet to actually enforce
either. Same posture Phase 5 gave every `media.*` tool's `permission_level`.

Registration is explicit: `register_app_tools()`, same pattern as
`register_media_tools()`. Importing the module registers nothing by itself.

### Changed: `src/jairus/tools/executor.py`

Extended `_handlers()` with five new entries mapping `apps.launch` /
`apps.close` / `apps.focus` / `apps.detect` / `apps.list_running` to the
matching `apps.py` function, same try/except/`ToolResult` shape already
used for `media.*` (a raised exception becomes
`failure_category=EXECUTION_ERROR`, not a propagated exception). Each
handler's `data` reports the function's own return value (e.g.
`{"closed": True}`, `{"apps": [...]}`) — `ToolResult.success` still just
means "the call ran to completion" (Part 30: "tool executed != task
succeeded"), which is why e.g. `close_app` returning `False` (nothing to
close) still comes back as `success=True, data={"closed": False}`, not as
a failure.

`player_action.py`'s nine `media.*` mappings are untouched.

### Changed: `src/jairus/tools/__init__.py`

Now also re-exports `APP_TOOLS` and `register_app_tools`.

### Changed: `requirements.txt`

Added `psutil` (new dependency — process detection/listing/closing).
Installed into the project venv and used for the verification below.

---

## What was explicitly NOT touched

- **`intent_parser.py`.** No `apps.*` action exists in its `SYSTEM_PROMPT`
  or its JSON shape. The live assistant has zero concept of "apps" as a
  domain after this phase.
- **`handle_command()`, `command_gateway.py`, `task_manager.py`.**
  Byte-for-byte identical to the prior phase (including the recent
  success/failure-propagation fix).
- **The executor's existing `media.*` mappings.** Only new entries were
  added to `_handlers()`'s returned dict.
- **The user-facing behaviour.** Run `python main.py` — it behaves exactly
  as before. Nothing calls `execute_tool("apps....", ...)` outside tests.

## What Phase 7 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Voice reachability for `apps.*` (intent parsing, dispatch) | Part 14.10–14.13 (Agent Core, then legacy-routing removal) |
| Windows UI Automation (controls, typing, clicking inside a window) | Part 14.9's sibling, Phase 9 |
| Policy Engine actually enforcing `permission_level` / confirmation | later hardening |
| Non-media, non-app tools (browser, filesystem, etc.) | Part 14.8, 14.16–14.17 |

---

## Verification performed

`python -m compileall` is clean on the new and changed files.
`git diff` on `intent_parser.py`, `assistant_loop.py` (where
`handle_command()` lives), and `command_gateway.py` is empty.

Unlike Phases 5-6, this was **not** stubbed/mocked — it was run for real
against Notepad (safe, always present, no data-loss risk): launched it via
`execute_tool("apps.launch", ...)`, confirmed `apps.detect` found it and
`apps.list_running` listed it (Windows 11's modern Notepad actually
reports its process name as `Notepad.exe`, capital N — `list_running_apps`
preserves the OS's exact casing, so the check is case-insensitive; `detect`
/`close`/`focus` already match case-insensitively), focused it, then
closed it via `execute_tool("apps.close", ...)` and confirmed `apps.detect`
then returned `False`. Full terminal output is in the commit conversation.

The first real run surfaced a genuine bug: `focus_app` initially used a
bare `SetForegroundWindow`, which Windows silently refuses when called
from a background process (this script, launched from a terminal) —
`SetForegroundWindow` returned `False` and the window never came forward.
Fixed with the standard workaround (see `_set_foreground` in `apps.py`),
then re-verified: `apps.focus` brought the real Notepad window to the
foreground.
