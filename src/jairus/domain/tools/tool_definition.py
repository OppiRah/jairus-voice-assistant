"""ToolDefinition — describes one registered capability."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from ..permissions.permission_level import PermissionLevel


@dataclass
class ToolDefinition:
    """Describes one registered capability (JAIRUS_ARCHITECTURE.md Part 15).

    A tool is more than a function exposed to the LLM: it carries the metadata
    the Policy Engine and Tool Executor need to validate, gate, and time-box a
    call. This dataclass covers the subset needed now; the remaining Part 15
    properties (output schema, retry behaviour, cancellation behaviour,
    idempotency, reversibility, executor, verifier) can be added later without
    changing these fields.

    Fields
    ------
    name:                  "domain.action" identifier, e.g. "media.pause".
    description:            what the capability does, for tool selection.
    input_schema:           JSON-schema-style description of valid arguments.
    permission_level:      risk classification used by the Policy Engine.
    requires_confirmation: whether the user must approve before execution.
    timeout_seconds:       hard cap on how long a single call may run.
    """

    name: str
    description: str
    input_schema: dict[str, Any]
    permission_level: PermissionLevel
    requires_confirmation: bool
    timeout_seconds: int
