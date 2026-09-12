"""Game tool definitions — launch/detect/focus/close/list running games.

JAIRUS_ARCHITECTURE.md Part 14.17 (migration Phase 15), Part 22 (Game
Automation), Part 23 (capability catalog), Part 15.15's Level 1 ("Process
Control") scope fence, and Part 25 (permission model).

The underlying implementation lives in
``jairus.infrastructure.automation.games`` (new this phase), which resolves
a friendly game name through the Game Registry and delegates to Phase 7's
existing ``apps.py`` functions — no process-automation logic is duplicated
here or there.

Registration is explicit, not an import-time side effect, matching every
prior phase. Call ``register_game_tools()`` to populate the registry.

**Permission classification, reasoned per tool (Part 25's own examples:
Level 0 = "launch application"/read operations; Level 1 = "close
application"):**

- ``game.launch`` — same reasoning as Phase 7's ``apps.launch``: starting a
  program is Part 25's own Level 0 example. **HARMLESS.**
- ``game.detect`` — a pure read (is this process running?), no
  interaction with anything. **HARMLESS.**
- ``game.focus`` — same reasoning as ``apps.focus``: bringing an already-
  running window to the foreground doesn't change any application state.
  **HARMLESS.**
- ``game.list_running`` — a pure read over the Game Registry and the
  process list, nothing is touched. **HARMLESS.**
- ``game.close`` — matches Part 25's own "close application" Level 1
  example, and arguably a *stronger* case than Phase 7's ``apps.close``:
  a closed game can silently discard unsaved in-game progress (a session,
  a level, an unsaved manual save) in a way a typical desktop application
  usually does not, or at least prompts before losing. **DISRUPTIVE,
  requires_confirmation=True.**

No tool here defaults to HARMLESS "for convenience" — only ``game.close``
carries real risk of unrecoverable loss, and it alone is gated.
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

GAME_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="game.launch",
        description="Launches a registered game by its friendly name (e.g. 'Minecraft').",
        input_schema={
            "name": {"type": "string", "description": "Friendly game name, as registered in the Game Registry"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="game.detect",
        description="Reports whether a registered game is currently running.",
        input_schema={
            "name": {"type": "string", "description": "Friendly game name to check"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
    ToolDefinition(
        name="game.focus",
        description="Brings a registered, running game's window to the foreground.",
        input_schema={
            "name": {"type": "string", "description": "Friendly game name to focus"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="game.close",
        description="Gracefully closes a registered, running game.",
        input_schema={
            "name": {"type": "string", "description": "Friendly game name to close"},
        },
        permission_level=PermissionLevel.DISRUPTIVE,
        requires_confirmation=True,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="game.list_running",
        description="Lists the friendly names of every registered game currently running.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
]


def register_game_tools() -> None:
    """Registers every game tool definition above with the Tool Registry."""
    for tool in GAME_TOOLS:
        register_tool(tool)
