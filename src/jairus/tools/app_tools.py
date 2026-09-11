"""Application tool definitions — NEW capabilities: launch/close/focus/
detect/list running applications.

JAIRUS_ARCHITECTURE.md Part 14.9 (migration Phase 7), Part 23 (capability
catalog), Part 19 (automation backend hierarchy), and Part 25 (permission
examples — "launch application" is Level 0, "close application" is Level 1).

Unlike ``media_tools.py`` (Phase 5), which described EXISTING capabilities
already reachable through ``handle_command()``, these describe genuinely
new ones: nothing in the assistant could launch, close, focus, detect, or
list applications before this phase. The underlying implementation lives
in ``jairus.infrastructure.automation.apps`` (also new this phase).

``apps.close`` is set to ``PermissionLevel.DISRUPTIVE`` with
``requires_confirmation=True`` (Part 25's own "close application" example)
even though no Policy Engine or confirmation flow exists yet to enforce
either — same as every ``media.*`` tool's ``permission_level`` was set
correctly in Phase 5 while nothing read it. It's recorded now as accurate
data, not as an active gate.

Registration is explicit, not an import-time side effect, matching
``media_tools.py``'s ``register_media_tools()`` pattern. Call
``register_app_tools()`` to populate the registry.
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

APP_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="apps.launch",
        description=(
            "Launches an application, by full path or by a name Windows "
            "can resolve (e.g. 'notepad.exe')."
        ),
        input_schema={
            "path_or_name": {
                "type": "string",
                "description": "Executable path, or a name Windows can resolve via PATH/App Paths",
            },
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="apps.close",
        description="Gracefully terminates a running application by its process name.",
        input_schema={
            "process_name": {
                "type": "string",
                "description": "Process name as shown by Task Manager, e.g. 'notepad.exe'",
            },
        },
        permission_level=PermissionLevel.DISRUPTIVE,
        requires_confirmation=True,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="apps.focus",
        description="Brings a running application's window to the foreground.",
        input_schema={
            "process_name": {"type": "string", "description": "Process name to find and focus"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="apps.detect",
        description="Reports whether an application is currently running.",
        input_schema={
            "process_name": {"type": "string", "description": "Process name to check"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
    ToolDefinition(
        name="apps.list_running",
        description="Lists the distinct process names currently running.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
]


def register_app_tools() -> None:
    """Registers every application tool definition above with the Tool Registry."""
    for tool in APP_TOOLS:
        register_tool(tool)
