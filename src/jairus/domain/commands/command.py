"""Command — a single natural-language request entering Jairus."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from .command_source import CommandSource
from .command_status import CommandStatus


@dataclass
class Command:
    """A single natural-language request entering Jairus.

    Created by the Command Gateway once a request has been authenticated and
    normalised, then carried through the lifecycle in JAIRUS_ARCHITECTURE.md
    Parts 13-14. This is a plain record: it holds no behaviour and knows nothing
    about how commands are transported, parsed, or executed.

    Fields
    ------
    command_id:       unique id for this command (e.g. "cmd_9182").
    source:           which interface the command came from.
    raw_input:        the user's request as received, before interpretation.
    timestamp:        when the command was received.
    conversation_id:  groups related commands into a conversation.
    goal:             the interpreted objective, filled in during UNDERSTANDING;
                      None until then.
    status:           current lifecycle state; starts at RECEIVED.
    """

    command_id: str
    source: CommandSource
    raw_input: str
    timestamp: datetime
    conversation_id: str
    goal: str | None = None
    status: CommandStatus = CommandStatus.RECEIVED
