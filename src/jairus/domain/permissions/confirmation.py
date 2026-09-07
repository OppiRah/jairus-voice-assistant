"""Confirmation — a specific, bound request for user approval."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any


@dataclass
class Confirmation:
    """A specific request for the user to approve one action.

    Per JAIRUS_ARCHITECTURE.md Part 26 a confirmation binds to an exact command,
    tool, and argument set, and it expires. Approving one operation must never
    authorise a different one, so every field here is part of what the user is
    agreeing to.

    Fields
    ------
    confirmation_id:  unique id for this confirmation request.
    command_id:       the Command this confirmation belongs to.
    tool_name:        the tool that will run if approved.
    arguments:        the exact arguments that will be used.
    description:      human-readable description of the specific action.
    expires_at:       after this time the confirmation is no longer valid.
    decision:         None until answered, then "approved" / "denied" /
                      "expired" (Part 13.16).
    """

    confirmation_id: str
    command_id: str
    tool_name: str
    arguments: dict[str, Any]
    description: str
    expires_at: datetime
    decision: str | None = None
