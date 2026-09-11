"""Task Manager — tracks one Task per Command, in memory.

JAIRUS_ARCHITECTURE.md Part 9 (Task Manager) and Part 14.6 (migration
Phase 4), with storage kept intentionally simple per Part 52 ("V1 memory
should remain simple") — persistence is a later phase.

Phase 4 scope, deliberately narrow: gives each ``Command`` a linked
``Task``, using the ``Task`` domain model introduced in Phase 2. Tasks are
linked to commands by ``command_id`` only — the ``Command`` dataclass itself
(Phase 2, already completed) is not touched, and neither is
``handle_command()``. No Agent Core, Tool Registry, or Policy Engine exists
yet, so this module only offers the transitions that are actually driven
today (see ``command_gateway.py``); it does not fake PLANNING or OBSERVING.

Storage is a pair of module-level dicts, matching the existing in-memory
style already used elsewhere in the codebase (see ``player_action.py``'s
module-level state). No SQLite/database — that belongs to a later phase.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from jairus.domain.tasks import Task, TaskStatus

_TASKS: dict[str, Task] = {}
_TASK_ID_BY_COMMAND: dict[str, str] = {}

_TERMINAL_STATUSES = frozenset(
    {
        TaskStatus.COMPLETED,
        TaskStatus.FAILED,
        TaskStatus.CANCELLED,
        TaskStatus.INTERRUPTED,
    }
)


def create_task(command_id: str) -> Task:
    """Creates a new ``Task`` linked to ``command_id``, status RECEIVED.

    One command produces one task (JAIRUS_ARCHITECTURE.md Part 11.10), so a
    second call for the same ``command_id`` simply creates (and indexes)
    another task rather than raising — callers today only ever call this
    once per command, right after the ``Command`` itself is created.
    """
    task = Task(
        task_id=str(uuid.uuid4()),
        command_id=command_id,
        status=TaskStatus.RECEIVED,
        created_at=datetime.now(timezone.utc),
    )
    _TASKS[task.task_id] = task
    _TASK_ID_BY_COMMAND[command_id] = task.task_id
    print(f"[task] task {task.task_id} received (command {command_id})")
    return task


def update_task_status(task_id: str, status: TaskStatus) -> None:
    """Transitions an existing task to ``status``.

    Stamps ``completed_at`` if ``status`` is terminal (COMPLETED, FAILED,
    CANCELLED, or INTERRUPTED).
    """
    task = _TASKS.get(task_id)
    if task is None:
        raise KeyError(f"no task with id {task_id}")

    task.status = status
    if status in _TERMINAL_STATUSES:
        task.completed_at = datetime.now(timezone.utc)
    print(f"[task] task {task_id} -> {status.value}")


def get_task(task_id: str) -> Task | None:
    """Looks up a task by its own id. Returns ``None`` if unknown."""
    return _TASKS.get(task_id)


def get_task_by_command(command_id: str) -> Task | None:
    """Looks up the task linked to ``command_id``. Returns ``None`` if unknown."""
    task_id = _TASK_ID_BY_COMMAND.get(command_id)
    return _TASKS.get(task_id) if task_id is not None else None
