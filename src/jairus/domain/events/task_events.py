"""Task execution events."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any


class EventType(str, Enum):
    """Event names emitted during task execution.

    Values match the wire strings in JAIRUS_ARCHITECTURE.md Parts 13.12-13.13,
    so an event can be forwarded to Android over the protocol without
    translation.
    """

    TASK_STARTED = "task.started"
    TASK_PROGRESS = "task.progress"
    TASK_WAITING_CONFIRMATION = "task.waiting_confirmation"
    TASK_COMPLETED = "task.completed"
    TASK_FAILED = "task.failed"
    TASK_CANCELLED = "task.cancelled"
    TASK_INTERRUPTED = "task.interrupted"
    TOOL_STARTED = "tool.started"
    TOOL_COMPLETED = "tool.completed"
    TOOL_FAILED = "tool.failed"


@dataclass
class TaskEvent:
    """A single structured event in a task's execution trace.

    Carries just enough for observability and for the gateway to forward
    progress to clients; heavy detail belongs in logs / audit records
    (JAIRUS_ARCHITECTURE.md Part 36).

    Fields
    ------
    event_type:  which event this is.
    task_id:     the Task the event belongs to.
    timestamp:   when the event occurred.
    payload:     event-specific detail (e.g. tool name, progress note); may be
                 empty.
    """

    event_type: EventType
    task_id: str
    timestamp: datetime
    payload: dict[str, Any] = field(default_factory=dict)
