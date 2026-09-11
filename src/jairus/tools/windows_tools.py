"""Windows UI tool definitions — semantic control finding/interaction.

JAIRUS_ARCHITECTURE.md Part 14.11 (migration Phase 9), Part 20 (Windows
Automation), Part 23 (capability catalog), and Part 25 (permission model).

The underlying implementation lives in
``jairus.infrastructure.automation.windows_ui`` (new this phase); see that
module's docstring for the backend choice per function and the "no
coordinate clicking, no vision, no chaining" scope limits.

Registration is explicit, not an import-time side effect, matching every
prior phase. Call ``register_windows_tools()`` to populate the registry.

**Permission classification, reasoned per tool (Part 25's own examples:
Level 0 = "read system information" / "focus window"; Level 1 = "change
certain system state"; Level 2 = specific known-destructive operations
like "delete file"):**

- ``windows.get_active_window`` / ``windows.list_windows`` — pure reads,
  no interaction with anything. Directly matches Part 25's own Level 0
  example, "read system information." **HARMLESS.**
- ``windows.find_control`` — also a pure lookup/query: it reports whether
  a control exists and its properties, it does not touch it. Same
  reasoning as the two above. **HARMLESS.**
- ``windows.invoke`` — genuinely unbounded: this tool can trigger *any*
  named control in *any* window — a "Save" button, a "Delete All" button,
  an "OK" on a confirmation dialog, a menu item that launches something
  else entirely. Unlike a narrowly-scoped tool such as Phase 7's
  ``apps.close`` (which only ever does one well-understood thing —
  gracefully end one named process), this tool has no semantic
  understanding of what the control it's invoking actually does before
  doing it. That is squarely Part 25's Level 1 language, "change certain
  system state" — not a specific *known*-destructive operation (Level 2's
  own examples are all concrete: delete file, overwrite data, uninstall
  software), but a real, unpredictable state change all the same.
  **DISRUPTIVE, requires_confirmation=True.**
- ``windows.type`` — same reasoning as ``windows.invoke``: an arbitrary
  named control, in an arbitrary window, receiving arbitrary text, with
  no way for this tool to know whether that's a harmless search box or
  something more consequential. **DISRUPTIVE, requires_confirmation=True.**
- ``windows.hotkey`` — arguably the *least* bounded of the six: a
  keyboard shortcut's effect depends entirely on the focused application's
  own keybindings (save, undo, close-window, clear-data, or something
  app-specific entirely), and this tool has zero insight into which.
  Classified at the same level as ``invoke``/``type`` (not higher) because
  the actual textual operation — "send this keystroke" — is exactly the
  same kind of unbounded-but-not-specifically-destructive action as those
  two, not one of Level 2's concrete destructive examples.
  **DISRUPTIVE, requires_confirmation=True.**

No tool here defaults to HARMLESS "for convenience" — only the three that
are genuinely read-only get that classification.
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

WINDOWS_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="windows.get_active_window",
        description="Reports the title and process name of the current foreground window.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
    ToolDefinition(
        name="windows.list_windows",
        description="Lists the title and process name of every visible top-level window.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
    ToolDefinition(
        name="windows.find_control",
        description=(
            "Looks for a named control (button, text field, menu item, ...) inside "
            "a named window and reports its properties, without interacting with it."
        ),
        input_schema={
            "window_title": {"type": "string", "description": "Window title (substring match)"},
            "control_name": {"type": "string", "description": "Control's accessible name"},
            "control_type": {"type": "string", "description": "Optional UIA control type, e.g. 'Button'"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="windows.invoke",
        description=(
            "Semantically invokes (clicks/activates) a named control inside a named "
            "window — never by screen coordinate."
        ),
        input_schema={
            "window_title": {"type": "string", "description": "Window title (substring match)"},
            "control_name": {"type": "string", "description": "Control's accessible name"},
            "control_type": {"type": "string", "description": "Optional UIA control type, e.g. 'Button'"},
        },
        permission_level=PermissionLevel.DISRUPTIVE,
        requires_confirmation=True,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="windows.type",
        description="Types text into a named control inside a named window.",
        input_schema={
            "window_title": {"type": "string", "description": "Window title (substring match)"},
            "control_name": {"type": "string", "description": "Control's accessible name"},
            "text": {"type": "string", "description": "Text to type"},
            "control_type": {"type": "string", "description": "Optional UIA control type, e.g. 'Edit'"},
        },
        permission_level=PermissionLevel.DISRUPTIVE,
        requires_confirmation=True,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="windows.hotkey",
        description=(
            "Focuses a named window and sends a keyboard shortcut to it, using "
            "pywinauto's send_keys syntax (e.g. '^s' for Ctrl+S)."
        ),
        input_schema={
            "window_title": {"type": "string", "description": "Window title (substring match)"},
            "keys": {"type": "string", "description": "Key combination in pywinauto send_keys syntax"},
        },
        permission_level=PermissionLevel.DISRUPTIVE,
        requires_confirmation=True,
        timeout_seconds=10,
    ),
]


def register_windows_tools() -> None:
    """Registers every Windows UI tool definition above with the Tool Registry."""
    for tool in WINDOWS_TOOLS:
        register_tool(tool)
