"""Command Gateway — the controlled entry point for commands.

JAIRUS_ARCHITECTURE.md Part 9 (Command Gateway) and Part 14.5 (migration
Phase 3).

Phase 3 scope, deliberately narrow: this wraps the EXISTING
``assistant_loop.handle_command()`` with a real command identity
(``command_id``) and a lifecycle status (RECEIVED -> UNDERSTANDING ->
COMPLETED / FAILED), using the ``Command`` domain model introduced in Phase 2.

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

from jairus.domain.commands import Command, CommandSource, CommandStatus


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
        today.
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

    command.status = CommandStatus.UNDERSTANDING
    print(f"[gateway] command {command.command_id} -> understanding")

    # Phase 3: handle_command() is still the thing that does the real work.
    # Imported here (not at module load) to avoid a circular import, since
    # assistant_loop imports this module at load time.
    from assistant_loop import handle_command

    try:
        handle_command(text, context, state)
    except Exception as exc:  # keep the assistant alive, same resilience as today
        command.status = CommandStatus.FAILED
        print(f"[gateway] command {command.command_id} -> failed: {exc}")
        return command

    command.status = CommandStatus.COMPLETED
    print(f"[gateway] command {command.command_id} -> completed")
    return command
