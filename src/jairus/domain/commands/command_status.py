"""CommandStatus — lifecycle state of a command."""

from __future__ import annotations

from enum import Enum


class CommandStatus(str, Enum):
    """Lifecycle state of a command (JAIRUS_ARCHITECTURE.md Part 13).

    A command moves through the "happy path" states in order and may branch into
    one of the terminal/alternative states (FAILED, RECOVERING, CANCELLED,
    INTERRUPTED) at any point.
    """

    RECEIVED = "received"
    UNDERSTANDING = "understanding"
    PLANNING = "planning"
    WAITING_CONFIRMATION = "waiting_confirmation"
    EXECUTING = "executing"
    OBSERVING = "observing"
    COMPLETED = "completed"
    FAILED = "failed"
    RECOVERING = "recovering"
    CANCELLED = "cancelled"
    INTERRUPTED = "interrupted"
