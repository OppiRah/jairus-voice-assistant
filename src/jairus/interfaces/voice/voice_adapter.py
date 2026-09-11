"""Voice Input Adapter — the voice-specific entry point into the Command
Gateway.

JAIRUS_ARCHITECTURE.md Part 14.14 (migration Phase 12, "Migrate Voice")
and Part 11.7 ("Input Adapters" — "the agent should not care where a
command came from"; voice, Android, and any future input all become the
same shape of request into the Gateway). Adapted for where this repo
actually is: the architecture doc's own Phase 12 assumes the Agent Core
already makes real decisions by this point. It doesn't here — Phase 11
built shadow mode, not a cutover, and no cutover has happened. So this
module does exactly one thing: it moves the existing
``Wake Word -> Recorder -> Whisper -> Voice Adapter -> Gateway`` wiring
into its proper architectural layer. It does NOT change who decides what
runs. Real commands are still executed by the unmodified legacy path
(``command_gateway.submit_command()`` -> ``handle_command()``), exactly as
they were before this module existed.

``submit_voice_command()`` below does precisely what
``assistant_loop.py`` used to call ``command_gateway.submit_command()``
directly, inline, for since Phase 3 — same arguments, same
``CommandSource.VOICE``, same return value. Nothing added, nothing
reinterpreted. This is a relocation, not new capability.
"""

from __future__ import annotations

from jairus.application.commands.command_gateway import submit_command
from jairus.domain.commands import Command, CommandSource


def submit_voice_command(text: str, context, state, conversation_id: str) -> Command:
    """Hands a transcribed voice command to the Command Gateway.

    Parameters mirror ``command_gateway.submit_command()`` exactly, minus
    ``source`` — a voice command is always ``CommandSource.VOICE`` here,
    which is the one thing this adapter fixes so callers in
    ``assistant_loop.py`` don't have to import ``CommandSource`` just to
    say what every voice call already says.
    """
    return submit_command(text, CommandSource.VOICE, context, state, conversation_id)
