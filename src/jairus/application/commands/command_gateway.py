"""Command Gateway — the controlled entry point for commands.

JAIRUS_ARCHITECTURE.md Part 9 (Command Gateway) and Part 14.5 (migration
Phase 3), extended in Phase 4 (Part 14.6) to also drive a linked Task via
the Task Manager.

Phase 3 scope, deliberately narrow: this wraps the EXISTING
``assistant_loop.handle_command()`` with a real command identity
(``command_id``) and a lifecycle status (RECEIVED -> UNDERSTANDING ->
COMPLETED / FAILED), using the ``Command`` domain model introduced in Phase 2.

Phase 4 adds: right after the ``Command`` is created, a ``Task`` is created
and linked to it by ``command_id`` (see ``task_manager.create_task``). The
task moves to EXECUTING right before ``handle_command()`` is called, then to
COMPLETED or FAILED mirroring the command's own final status. No
PLANNING/OBSERVING transitions are driven here — there is no real planning or
observation step until the Agent Core exists (a later phase), so those states
are not faked.

It does NOT change any decision logic. ``handle_command()`` still does all of
the actual work (intent parsing, the if/elif action dispatch, the ``speak()``
calls) exactly as before — it is imported and called, not reimplemented. The
Agent Core, Tool Registry, Policy Engine, Android transport, and persistence
described elsewhere in the architecture are all later phases and are
intentionally absent here.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from jairus.application.tasks import create_task, update_task_status
from jairus.domain.commands import Command, CommandSource, CommandStatus
from jairus.domain.tasks import TaskStatus


def submit_command(
    text: str,
    source: CommandSource,
    context,
    state,
    conversation_id: str,
) -> Command:
    """Give one user command an identity and lifecycle, then run it.

    Parameters
    ----------
    text:
        The transcribed / typed command as received.
    source:
        Which interface the command came from (``CommandSource.VOICE`` today).
    context:
        The existing ``ConversationContext`` instance, passed straight through
        to ``handle_command()``.
    state:
        The existing ``AssistantState`` instance, passed straight through to
        ``handle_command()`` so the orb keeps reflecting progress.
    conversation_id:
        Groups commands from the same program run into one conversation.

    Returns
    -------
    Command
        The command record, with ``status`` set to ``COMPLETED`` if
        ``handle_command()`` returned normally, or ``FAILED`` if it raised.
        Exceptions are swallowed here on purpose: the voice loop must stay
        alive and keep listening after a failed command, exactly as it does
        today. A ``Task`` linked to this command (by ``command_id``) is
        created and driven alongside it — see ``task_manager`` for its record.
    """
    command = Command(
        command_id=str(uuid.uuid4()),
        source=source,
        raw_input=text,
        timestamp=datetime.now(timezone.utc),
        conversation_id=conversation_id,
        status=CommandStatus.RECEIVED,
    )
    print(f"[gateway] command {command.command_id} received: '{text}'")

    task = create_task(command.command_id)

    command.status = CommandStatus.UNDERSTANDING
    print(f"[gateway] command {command.command_id} -> understanding")

    # Phase 3: handle_command() is still the thing that does the real work.
    # Imported here (not at module load) to avoid a circular import, since
    # assistant_loop imports this module at load time.
    from assistant_loop import handle_command

    update_task_status(task.task_id, TaskStatus.EXECUTING)

    try:
        handle_command(text, context, state)
    except Exception as exc:  # keep the assistant alive, same resilience as today
        command.status = CommandStatus.FAILED
        print(f"[gateway] command {command.command_id} -> failed: {exc}")
        update_task_status(task.task_id, TaskStatus.FAILED)
        return command

    command.status = CommandStatus.COMPLETED
    print(f"[gateway] command {command.command_id} -> completed")
    update_task_status(task.task_id, TaskStatus.COMPLETED)
    return command
