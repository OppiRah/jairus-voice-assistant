# Jairus — Phase 15: Game Tools

**Migration step:** Phase 15 of `JAIRUS_ARCHITECTURE.md` Part 14.17, Part
22 ("Game Automation"), Part 23's catalog, and Part 15.15's "Game
Automation Roadmap" — specifically Level 1, **Process Control**
(launch/detect/focus/close/list). Levels 2+ (launcher integration,
in-game state, in-game automation, computer vision) are explicitly later,
separate roadmap steps and are not touched here.

**One-sentence summary:** a new Game Registry maps friendly game names
(e.g. "Sons of the Forest") to process/launch info, and five new
`game.*` tools resolve a name through that registry and delegate straight
to Phase 7's existing `apps.py` automation — a game is just a process, so
none of that automation logic is duplicated — but **nothing reaches this
from voice yet**, same as every phase since 7.

---

## What's different from Phase 7

Phase 7 (`apps.*`) wrote genuinely new process-automation code because
none existed. Phase 15 writes **no new automation code at all** — Part
22's own diagram is followed literally:

```text
Game Registry
      ↓
Game Identity / Configuration
      ↓
Launcher Adapter        <- not built yet (Level 2, later)
      ↓
Generic Game Tools
      ↓
Game-Specific Integration when necessary   <- not built yet (Level 4+, later)
```

`game.*` is a thin naming/lookup layer on top of `apps.*`: it turns "close
Sons of the Forest" into "terminate the process named
`SonsOfTheForest.exe`" and nothing more. `launch_app`, `detect_app`,
`focus_app`, `close_app`, and `list_running_apps` are called exactly as
they were before this phase — not reimplemented, not subclassed, not
wrapped in new logic beyond the name resolution itself.

---

## What was built

### New: `src/jairus/domain/games/game_definition.py`

```python
@dataclass
class GameDefinition:
    name: str            # friendly name, e.g. "Sons of the Forest"
    process_name: str    # e.g. "SonsOfTheForest.exe"
    launch_command: str  # e.g. "steam://run/1326470"
```

Stdlib only, same discipline as every `domain/` model since Phase 2.

### New: `src/jairus/configuration/game_registry.py`

```python
def register_game(definition: GameDefinition) -> None
def get_game(name: str) -> GameDefinition | None
def list_games() -> list[GameDefinition]
```

A module-level dict, same in-memory shape as the Tool Registry and Task
Manager — no persistence. Lookup is case-insensitive on the friendly
name (keyed internally by the lowercased name), since a spoken or typed
game name won't reliably match a stored name's exact casing.

This registry is the **only** source of truth for what counts as a "known
game." It holds no launcher-integration logic — that's explicitly Level 2,
later.

### New: `src/jairus/infrastructure/automation/games.py`

```python
def launch_game(name: str) -> bool
def detect_game(name: str) -> bool
def focus_game(name: str) -> bool
def close_game(name: str) -> bool
def list_running_games() -> list[str]
```

Each function (other than `list_running_games`) does exactly two things:
look `name` up in the Game Registry, then call the matching `apps.py`
function with the resolved `process_name` (or `launch_command` for
`launch_game`). If `name` isn't registered at all, the function prints a
message and returns `False` **without calling any `apps.py` function** —
it never falls back to treating the raw name as a process name or launch
target. `list_running_games()` cross-references
`apps.list_running_apps()` against the registry and returns the friendly
names of every registered game currently running, case-insensitively
matched on `process_name`.

### New: `src/jairus/tools/game_tools.py`

Defines `GAME_TOOLS: list[ToolDefinition]`:

| Tool name | permission_level | requires_confirmation |
|---|---|---|
| `game.launch` | `HARMLESS` | `False` |
| `game.detect` | `HARMLESS` | `False` |
| `game.focus` | `HARMLESS` | `False` |
| `game.close` | `DISRUPTIVE` | `True` |
| `game.list_running` | `HARMLESS` | `False` |

Reasoned per tool, not defaulted:

- `game.launch` — starting a program, Part 25's own Level 0 example, same
  as `apps.launch`. **HARMLESS.**
- `game.detect` / `game.list_running` — pure reads. **HARMLESS.**
- `game.focus` — bringing an already-running window forward changes no
  application state, same as `apps.focus`. **HARMLESS.**
- `game.close` — matches Part 25's "close application" Level 1 example,
  and arguably a **stronger** case than `apps.close`: closing a game can
  silently discard unsaved in-game progress in a way a typical desktop
  application usually doesn't (or at least prompts before losing).
  **DISRUPTIVE, `requires_confirmation=True`.**

Registration is explicit: `register_game_tools()`, same pattern as every
prior `register_*_tools()`. Importing the module registers nothing by
itself.

### Changed: `src/jairus/tools/executor.py`

Extended `_handlers()` with five new entries mapping `game.launch` /
`game.detect` / `game.focus` / `game.close` / `game.list_running` to the
matching `jairus.infrastructure.automation.games` function, same
try/except/`ToolResult` shape used by every prior phase. `data` reports
the function's own return value (e.g. `{"launched": True}`,
`{"games": [...]}`), same "tool executed != task succeeded" posture as
Phase 7 — `close_game` returning `False` because nothing matched still
comes back as `success=True, data={"closed": False}`.

`apps.*`, `media.*`, `browser.*`, and `windows.*` mappings are untouched.

### Changed: `src/jairus/tools/__init__.py`

Now also re-exports `GAME_TOOLS` and `register_game_tools`.

---

## What was explicitly NOT touched

Confirmed via empty `git diff` on all of: `intent_parser.py`,
`assistant_loop.py`, `command_gateway.py`, `task_manager.py`,
`player_action.py`, `apps.py`, `windows_ui.py`, `browser.py`,
`agent_core.py`, `policy_engine.py`, `voice_adapter.py`, `main.py`, and
everything in `interfaces/android/`.

- **`intent_parser.py`.** No `game.*` action exists in its `SYSTEM_PROMPT`
  or JSON shape. The live assistant has zero concept of "games" as a
  domain after this phase.
- **`apps.py` itself.** Zero changes — `games.py` imports and calls its
  five functions unmodified.
- **The executor's existing `media.*`/`apps.*`/`browser.*`/`windows.*`
  mappings.** Only new entries were added to `_handlers()`'s returned
  dict.
- **The user-facing behaviour.** Run `python main.py` — it behaves exactly
  as before. Nothing calls `execute_tool("game....", ...)` outside tests.

## What Phase 15 deliberately does NOT include yet

| Not in this phase | Where it belongs |
|---|---|
| Voice reachability for `game.*` (intent parsing, dispatch) | Part 14.10–14.13 (Agent Core, then legacy-routing removal) |
| Launcher integration — Steam/Epic/Xbox-specific adapters, auto-discovering installed games | Part 15.15 Level 2 |
| In-game state detection (foreground/launcher/running distinctions beyond "is the process alive") | Part 15.15 Level 3 |
| Game-specific commands, in-game automation, computer vision | Part 15.15 Levels 4-6 |
| Persistence of registered games across process restarts | later, if ever — matches every other in-memory registry so far |
| Policy Engine actually enforcing `permission_level`/confirmation | later hardening |

---

## Verification performed

`python -m compileall` is clean on the new and changed files. `git diff`
on every protected file listed above is empty.

This was run for real, not stubbed: **Sons of the Forest** (Steam App ID
1326470) was chosen as the test game because it was readily identifiable
from this machine's actual Steam library
(`libraryfolders.vdf` → `appmanifest_1326470.acf`, install dir
`D:\SteamLibrary\steamapps\common\Sons Of The Forest`, executable
`SonsOfTheForest.exe`) and force-closing it mid-session carries no
meaningful unsaved-progress risk for this test (no manual save was in
progress).

Registered as:

```python
GameDefinition(
    name="Sons of the Forest",
    process_name="SonsOfTheForest.exe",
    launch_command="steam://run/1326470",
)
```

The `steam://run/<appid>` URI form was used for `launch_command` (per
request) rather than a direct path to the executable — `apps.launch_app`
passes it straight to `os.startfile`, exactly the same mechanism used for
a bare executable name, since Windows already has the `steam://` protocol
registered to the Steam client. This means Steam resolves the actual
install location and any launch options itself; `games.py` never needs to
know where the game is installed.

Full sequence executed via `execute_tool()`, actual captured output:

```text
=== failure case: unregistered game name ===
[games] 'TotallyNotAGame' is not a registered game
ToolResult(success=True, data={'running': False}, ...)
[games] 'TotallyNotAGame' is not a registered game
ToolResult(success=True, data={'launched': False}, ...)

=== launch ===
[apps] launching 'steam://run/1326470'
ToolResult(success=True, data={'launched': True}, ...)

=== polling detect until True ===
  t+5s: ToolResult(success=True, data={'running': True}, ...)

=== list_running ===
ToolResult(success=True, data={'games': ['Sons of the Forest']}, ...)

=== focus ===
[apps] focusing 'SonsOfTheForest.exe'
ToolResult(success=True, data={'focused': True}, ...)

=== close ===
[apps] closing 'SonsOfTheForest.exe'
ToolResult(success=True, data={'closed': True}, ...)

=== detect after close ===
ToolResult(success=True, data={'running': False}, ...)
```

1. **Failure case first:** `game.detect`/`game.launch` with an
   unregistered name (`"TotallyNotAGame"`) — both returned
   `success=True, data={"running": False}` / `data={"launched": False}`
   without attempting anything, confirming the registry-miss path never
   guesses a raw process name.
2. `game.launch` on `"Sons of the Forest"` — `{"launched": True}`.
3. Polled `game.detect`; it returned `True` on the very first 5-second
   poll (the process had already been launched and shader-compiled once
   before on this machine, so this run's startup was fast).
4. `game.list_running` — `{"games": ["Sons of the Forest"]}`.
5. `game.focus` — brought the real game window to the foreground.
6. `game.close` — `{"closed": True}`.
7. `game.detect` after close — `{"running": False}`, confirming the
   process actually exited.

`python main.py` was run afterward to confirm normal startup with no
regressions from this phase's changes.
