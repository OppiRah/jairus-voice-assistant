"""Task — execution record for a command, owned by the Task Manager."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from .task_status import TaskStatus


@dataclass
class Task:
    """Execution record for a command.

    In V1 one command produces one task and only a single autonomous task runs
    at a time (JAIRUS_ARCHITECTURE.md Part 11.10). Kept deliberately small:
    step-by-step history and detailed traces live in the observability/audit
    layer (Part 36), not on this record.

    Fields
    ------
    task_id:       unique id for this task.
    command_id:    the Command this task executes.
    status:        current lifecycle state.
    created_at:    when the task was created.
    completed_at:  when the task reached a terminal state; None while running.
    """

    task_id: str
    command_id: str
    status: TaskStatus
    created_at: datetime
    completed_at: datetime | None = None
