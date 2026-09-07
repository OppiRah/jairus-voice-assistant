"""TaskStatus — lifecycle state of a task."""

from __future__ import annotations

from enum import Enum


class TaskStatus(str, Enum):
    """Lifecycle state of a task.

    A task is the unit of execution the Task Manager owns on behalf of a
    command. Its states mirror the command lifecycle and the protocol state
    machine in JAIRUS_ARCHITECTURE.md Part 13 (see also the diagram in
    Part 13.24): a linear happy path plus terminal/alternative states.
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
