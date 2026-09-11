"""Tool Registry — holds ToolDefinitions, queryable by name.

JAIRUS_ARCHITECTURE.md Part 15 (tool properties) and Part 14.7 (migration
Phase 5).

Phase 5 scope, deliberately narrow: this is a lookup table only. Nothing in
the assistant routes through it yet — ``handle_command()``'s if/elif still
does all real dispatch, exactly as it has since Phase 3. Registering a tool
here just makes its existence and metadata queryable; wiring actual
execution through the registry (a Tool Executor) is a later phase (Part
14.7's own sequencing puts that at Phase 10).

Storage is a module-level dict, matching the existing in-memory style used
by ``task_manager.py``.
"""

from __future__ import annotations

from jairus.domain.tools import ToolDefinition

_TOOLS: dict[str, ToolDefinition] = {}


def register_tool(definition: ToolDefinition) -> None:
    """Registers (or replaces) a tool definition, keyed by its own ``name``."""
    _TOOLS[definition.name] = definition


def get_tool(name: str) -> ToolDefinition | None:
    """Looks up a tool by name. Returns ``None`` if nothing is registered
    under that name."""
    return _TOOLS.get(name)


def list_tools() -> list[ToolDefinition]:
    """Returns every currently registered tool definition."""
    return list(_TOOLS.values())
