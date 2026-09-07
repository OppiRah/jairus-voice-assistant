"""ToolCall — a concrete request to run a registered tool."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class ToolCall:
    """A concrete request to run a registered tool with specific arguments.

    Produced from a validated LLM decision (JAIRUS_ARCHITECTURE.md Part 67) and
    tied back to the command that motivated it, so execution can be audited and
    cancelled by command.

    Fields
    ------
    tool_name:   the ToolDefinition.name to invoke.
    arguments:   arguments for this call; validated against the tool's schema
                 before execution.
    command_id:  the Command this call serves.
    """

    tool_name: str
    arguments: dict[str, Any]
    command_id: str
