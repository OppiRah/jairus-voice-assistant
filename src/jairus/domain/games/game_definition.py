"""GameDefinition — one entry in the Game Registry."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class GameDefinition:
    """Describes one known game (JAIRUS_ARCHITECTURE.md Part 22's "Game
    Identity / Configuration" layer, sitting between the Game Registry and
    the generic ``apps.py`` process-automation functions a game is
    ultimately just a process to).

    Fields
    ------
    name:            friendly name used to look the game up, e.g. "Minecraft".
    process_name:    the actual OS process name used to detect/focus/close it,
                     e.g. "javaw.exe" — passed straight through to ``apps.py``.
    launch_command:  the actual path or command used to start it, e.g. a full
                     path to an executable — passed straight through to
                     ``apps.launch_app``.
    """

    name: str
    process_name: str
    launch_command: str
