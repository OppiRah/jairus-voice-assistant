# Jairus — Phase 9: Windows UI Automation

**Migration step:** Phase 9 of `JAIRUS_ARCHITECTURE.md` (Part 14.11),
implementing semantic Windows UI Automation from Part 20 ("Windows UI
Automation should provide semantic interaction... Coordinate-based raw
input should not be a general-purpose LLM tool in V1"), Part 19's backend
hierarchy, and Part 23's capability catalog.

**One-sentence summary:** the assistant can now really find and interact
with named controls (buttons, text fields, menu items) inside Windows
applications by *name*, never by screen coordinate — six new `windows.*`
tools — but **nothing reaches this from voice yet**.

---

## 1. What Phase 9 implemented

```
windows.get_active_window   windows.find_control   windows.type
windows.list_windows        windows.invoke          windows.hotkey
```

## 2. Files created / modified

| File | Status | Purpose |
|---|---|---|
| `src/jairus/infrastructure/automation/windows_ui.py` | **new** | Real implementation: `get_active_window`, `list_windows`, `find_control`, `invoke_control`, `type_into_control`, `send_hotkey`. |
| `src/jairus/tools/windows_tools.py` | **new** | `WINDOWS_TOOLS` (6 `ToolDefinition`s, reasoned permission levels — see §5) + `register_windows_tools()`. |
| `src/jairus/tools/executor.py` | modified | Added 6 handler mappings, same try/except/`ToolResult` shape as every prior phase. |
| `src/jairus/tools/__init__.py` | modified | Re-exports `WINDOWS_TOOLS`, `register_windows_tools`. |
| `requirements.txt` | modified | Added `pywinauto` (justified in §16). |

No other file was touched — see §12 for the protected-files diff.

## 3. Architecture integration

```
ToolDefinition (windows_tools.py)
        ↓
Tool Registry (registry.py, Phase 5 — unmodified)
        ↓
Tool Executor (executor.py, Phase 6 — extended)
        ↓
jairus.infrastructure.automation.windows_ui  (new this phase)
        ↓
win32gui/win32process/psutil (window enum)  |  pywinauto UIA backend (controls)
        ↓
Windows
```

Matches Part 14.11's own example flow:
`apps.launch → apps.focus → windows.find_control → windows.type`
(the chaining shown there is illustrative of a *future* Agent Core
composing these tools — nothing in this phase composes them; each call
here is independent, per this phase's own scope rule).

---

## 4. Backend hierarchy — why two backends inside one module

Per Part 19 ("prefer the plainest native API that does the job"):

- **`get_active_window` / `list_windows`**: plain `win32gui` +
  `win32process` + `psutil` — the exact combination Phase 7's `apps.py`
  already uses for window/process introspection. These are pure
  enumeration; no semantic control tree is needed.
- **`find_control` / `invoke_control` / `type_into_control` /
  `send_hotkey`**: `pywinauto`'s UI Automation (`"uia"`) backend — real
  semantic interaction with named controls. This is what `pywin32` alone
  cannot provide (raw window-handle/message access, not an accessibility
  tree), and exactly what Part 20 asks for.

---

## 5. Tool Registry — permission levels, reasoned per tool

| Tool name | permission_level | requires_confirmation |
|---|---|---|
| `windows.get_active_window` | `HARMLESS` | `False` |
| `windows.list_windows` | `HARMLESS` | `False` |
| `windows.find_control` | `HARMLESS` | `False` |
| `windows.invoke` | **`DISRUPTIVE`** | **`True`** |
| `windows.type` | **`DISRUPTIVE`** | **`True`** |
| `windows.hotkey` | **`DISRUPTIVE`** | **`True`** |

**Reasoning** (full text also lives as a docstring in `windows_tools.py`,
next to the definitions themselves — Part 25's own examples: Level 0 =
"read system information"/"focus window"; Level 1 = "change certain
system state"; Level 2 = specific *known*-destructive operations like
"delete file"):

- The three read/query tools are **HARMLESS** — they match Part 25's own
  Level 0 example ("read system information") directly; none of them
  touch anything.
- `windows.invoke`, `windows.type`, and `windows.hotkey` are all
  **DISRUPTIVE with `requires_confirmation=True`** — deliberately, not by
  default. Unlike a narrowly-scoped Phase 7 tool like `apps.close` (which
  only ever does one well-understood thing — gracefully end one named
  process), these three are *genuinely unbounded*: a "control name" could
  be "Save," "Delete All," or an "OK" on a confirmation dialog; typed text
  could go into a harmless search box or something consequential; a
  hotkey's effect depends entirely on whatever the focused app happens to
  bind it to. None of these tools has any semantic understanding of what
  the target actually does before acting on it — that is squarely Part
  25's Level 1 language ("change certain system state"), not Level 2's
  *specific known*-destructive examples. They are intentionally **not**
  all defaulted to `HARMLESS` "for convenience."

Registration is explicit — `register_windows_tools()` — matching every
prior phase's pattern. Importing the module registers nothing by itself.

## 6. Tool Executor

All six route through the same `execute_tool()` used since Phase 6: look
up the `ToolDefinition` (→ `NOT_FOUND` if unregistered), call the mapped
handler inside `try/except` (→ `EXECUTION_ERROR` on an unexpected
exception), otherwise `ToolResult(success=True, data=...)`. `find_control`
returning `{"found": False}` and `invoke_control`/`type_into_control`/
`send_hotkey` returning `False` are **not** failures at the `ToolResult`
level — "the control wasn't there" is itself the accurate, reportable
outcome of a call that ran to completion (Part 30: "tool executed != task
succeeded"), the same posture already established for `apps.*` in Phase 7.

---

## 7. Scope limits — deliberate, not oversights

- **No coordinate/pixel clicking, anywhere, not even as an internal
  fallback.** If a control can't be located semantically, every function
  reports that plainly (`found: False` / returns `False`) — nothing here
  ever computes or guesses a screen position. (`invoke_control` can fall
  back from UI Automation's `Invoke` pattern to pywinauto's own
  `click_input()` for a control that doesn't support `Invoke` — that still
  targets *that already-located control's own* on-screen rectangle as
  reported by UI Automation, not an arbitrary coordinate; it only ever
  runs against a control this module already found by name.)
- **No vision-based automation** (screenshots, image matching) — Part 19's
  own hierarchy puts that later ("Vision remains later").
- **No multi-step workflows.** Each function is one discrete action. There
  is no "open this menu, then click that item" composite behavior
  anywhere in this module — the Part 14.11 example chain
  (`apps.launch → apps.focus → windows.find_control → windows.type`) is
  something a *future* Agent Core would compose from these independent
  calls, not something built here.

---

## 8. What is intentionally NOT wired in yet

**The Windows UI tools are currently standalone infrastructure.**

**They are NOT yet selected by the Agent Core, NOT yet selected by the
LLM, and NOT yet part of the live voice command dispatch path.**

`intent_parser.py` has no `windows.*` concept. `handle_command()`'s
if/elif is unchanged. That integration is Part 14.12 (Agent Core) and Part
14.13 (removing legacy intent routing) — both later phases.

---

## 9. Testing

**Real, not mocked.** Deliberately **not** Notepad this time: a live
inspection before writing the test found an existing Notepad window
(`*JAIRUS_HANDOFF.md - Notepad`, the asterisk meaning unsaved changes,
alongside a second `ChangeHistory.txt` tab in the same window) — real,
unsaved user content that automated typing/hotkey testing could have
corrupted if mistargeted. Calculator (no user data — safe to click/hotkey)
and the Windows Run dialog (opened and closed cleanly, nothing executed)
were used instead. Confirmed both before and after: the Notepad window's
title (and its unsaved-changes asterisk) was unchanged — it was never
touched.

| Tool | Result | What was verified |
|---|---|---|
| `windows.get_active_window` | **PASS** | Reported `{"title": "Calculator", "process_name": "ApplicationFrameHost.exe"}` while Calculator was foreground. |
| `windows.list_windows` | **PASS** | `"Calculator"` present among the returned titles. |
| `windows.find_control` (found) | **PASS** | Located Calculator's real `"Seven"` button; `automation_id == "num7Button"`. |
| `windows.find_control` (failure case) | **PASS** | A made-up control name returned `{"found": False}` cleanly — no crash, no exception. |
| `windows.invoke` | **PASS** | Clicked `Clear → Seven → Plus → Three → Equals` (five separate, discrete `execute_tool` calls); verified the actually-computed result by then finding a control literally named `"Display is 10"` — the real 7+3 outcome, not just "no exception was raised." |
| `windows.type` | **PASS** | Typed `"PhaseNineTestString"` into the Run dialog's `"Open:"` Edit box; verified via `find_control`'s `value` field (see §11) reading back the exact typed string. |
| `windows.hotkey` | **PASS** | Sent `^a` (Ctrl+A, harmless select-all) then `{ESC}` to the Run dialog; confirmed the window was gone from `list_windows` afterward — closed, nothing executed. |
| (bonus) `windows.does_not_exist` | **PASS** | `NOT_FOUND`, no attempt to touch anything. |

### Two real issues found and fixed during this testing

1. **A real UI Automation flakiness, root-caused and fixed.** A bare
   `Desktop().window(title=...)` lookup intermittently failed to resolve
   even a window that definitely existed. Root cause: repeated test
   launches had left **two** windows both titled `"Calculator"` (one
   minimized) — an ambiguous match that pywinauto's default resolution
   handled inconsistently. Fixed by resolving windows through
   `Desktop().windows(title_re=..., visible_only=True)` (a concrete,
   pre-filtered list — `visible_only=True` excludes the minimized one)
   instead of a single ambiguous lookup; re-verified reliable across
   repeated fresh single-instance launches. `_locate_window`'s docstring
   documents this.
2. **A genuine gap in `find_control`'s returned info, found and fixed.**
   The first `windows.type` test failed — not because typing didn't work,
   but because the test tried to verify it via `find_control`'s `name`
   field, which for many native Edit controls is a *static label*
   (`"Open:"`) that doesn't change no matter what's typed; the actual
   typed content lives in a separate UI Automation Value-pattern property.
   Fixed by adding a `value` field to `find_control`'s output (via
   `get_value()` where the control exposes one) — this is what actually
   let the test verify the typed text landed, and makes `find_control`
   itself more useful for the same reason.

A timing issue in the **test harness** (not the tool code) was also fixed:
the first run's `apps.focus` setup call raced Calculator's own window
creation and needed a short retry loop.

### A cross-phase discovery (not a Phase 9 bug)

`get_active_window` correctly reported Calculator's owning process as
`ApplicationFrameHost.exe`, not `CalculatorApp.exe` — Calculator, like
many UWP-packaged apps, has its actual top-level window owned by a shared
hosting process, not the app's own executable. This incidentally explains
why Phase 7's `apps.focus_app("CalculatorApp.exe")` never finds a match
for Calculator specifically (it searches for a window owned by a process
matching the given name) — a pre-existing Phase 7 characteristic for
UWP-hosted apps, surfaced by this phase's testing but out of this phase's
scope to change (`apps.py` is a protected file this phase — see §12).
Noted here as a known limitation, not fixed.

---

## 10. Failure handling

| Scenario | How it's handled |
|---|---|
| Window doesn't exist | `_locate_window` raises `ElementNotFoundError` after a bounded retry window (8s); every public function catches it and returns a clean negative result (`found: False` / `False`) — never a crash. |
| Control doesn't exist | Same — `_locate_control` raises `ElementNotFoundError` after the same retry window; caught the same way. |
| Control found but disabled | `invoke_control`/`type_into_control` check `is_enabled()` and return `False` rather than attempting the action. |
| Control doesn't support `Invoke` | `invoke_control` falls back to `click_input()` on that same, already-located control — not a coordinate guess (see §7). |
| Unexpected pywinauto/UI Automation error | Not caught inside `windows_ui.py` — propagates to the Tool Executor's generic `try/except`, reported as `EXECUTION_ERROR` with the underlying message, same uniform mapping already used for `media.*`/`apps.*`/`browser.*`. |

---

## 11. Additional field beyond the original spec

`find_control`'s returned dict includes a `value` field (the control's UI
Automation Value-pattern content, when it exposes one — `None` otherwise),
in addition to `found`/`name`/`control_type`/`automation_id`/
`is_enabled`/`is_visible`. Added because testing `windows.type` surfaced a
real need for it (§9) — without it, there is no way to verify through
`find_control` alone that typed text actually landed, since many controls'
accessible "Name" is a static label distinct from their content.

---

## 12. Protected files

`git diff` — all empty, confirmed after this phase's changes:

- `intent_parser.py`
- `assistant_loop.py` (`handle_command()`)
- `src/jairus/application/commands/command_gateway.py`
- `src/jairus/application/tasks/task_manager.py`
- `player_action.py`
- `src/jairus/infrastructure/automation/apps.py`

## 13. Live regression check

Ran `python -u main.py` for real after this phase's changes. Reached
`[ready] listening for wake word: 'hey jairus'` — full normal
initialization, identical to every prior phase's check. Process then
terminated (a spoken wake-word command isn't practical to drive from this
non-interactive environment, same limitation documented since Phase 3).

---

## 14. Dependency: `pywinauto`

**Added.** `pywin32` (already a dependency, used by `apps.py`'s
`focus_app` and `pyttsx3`) gives raw window-handle and Win32-message-level
access — it has no concept of a semantic accessibility/control tree:
finding "the button named Seven" by name, walking named descendants, or
reading a control's enabled/value state isn't something `pywin32` exposes
at all. `pywinauto` is the standard Python wrapper around Windows' own UI
Automation API, purpose-built for exactly this (`Desktop`, `child_window`/
`descendants` by name/type, `.invoke()`/`.click_input()`/`.type_keys()`
semantic actions). This is the same kind of justification Phase 7 gave for
`psutil` (process enumeration `pywin32` also doesn't cover) — a real,
narrow capability gap, not a redundant addition. No existing dependency in
this repository provides it. Impact: one new pure-Python package,
installed into the project venv and used for real in the testing above.

---

## 15. Known limitations

- Window/control matching is a case-insensitive **substring** match on
  title/name — no exact-match mode, no disambiguation parameter (e.g. a
  process ID or window handle) when multiple windows/controls share a
  name beyond the `visible_only` filter described in §9. A future phase
  could add an optional disambiguator if this becomes a real problem.
- `apps.focus_app` (Phase 7, untouched) doesn't reliably focus UWP-hosted
  apps like Calculator, since their top-level window is owned by
  `ApplicationFrameHost.exe` rather than the app's own process name — see
  §9's cross-phase discovery. `windows.get_active_window`/`list_windows`
  are unaffected (they read whatever's actually foreground/enumerable,
  regardless of which process owns it).
- `invoke_control`'s `click_input()` fallback (for controls without an
  `Invoke` pattern) still depends on pywinauto computing a click point
  from the control's own bounding rectangle — reliable for on-screen,
  actually-rendered controls, but not guaranteed for a control that's
  technically "found" yet scrolled off-screen or occluded.
- Timeouts (`CONTROL_TIMEOUT_SECONDS = 8`) are a fixed module constant,
  not yet read from `ToolDefinition.timeout_seconds` by the executor —
  same posture already documented for `apps.*`/`browser.*` in Phases 7-8.
- `send_hotkey`'s `keys` argument uses pywinauto's own SendKeys-like
  syntax (`"^s"`, `"{ESC}"`); a caller passing plain human text (e.g.
  `"ctrl s"`) will not do what they meant — no translation layer exists
  for this yet.
