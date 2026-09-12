"""Game Registry — holds GameDefinitions, queryable by friendly name.

JAIRUS_ARCHITECTURE.md Part 22 ("Game Identity / Configuration" sits
between the Game Registry and the Launcher Adapter / Generic Game Tools),
Part 14.17 (migration Phase 15), and Part 15.15's Level 1 ("Process
Control") scope fence.

This is the "friendly name -> actual process/launch info" layer Part 22
describes: it holds no automation logic itself, and no launcher-integration
logic (Level 2 — Steam/Epic/Xbox — is explicitly later). A name not
registered here is simply not a "known game" as far as the rest of the
Game subsystem is concerned — ``jairus.infrastructure.automation.games``
treats a registry miss as a clean failure rather than guessing a raw
process name.

Storage is a module-level dict, matching every other in-memory
registry/manager in this codebase (the Tool Registry, the Task Manager).
Lookup is case-insensitive on the friendly name (matching how a spoken or
typed game name might vary in case), keyed internally by the lowercased
name; ``GameDefinition.name`` itself keeps its original casing for display.
"""

from __future__ import annotations

from jairus.domain.games import GameDefinition

_GAMES: dict[str, GameDefinition] = {}


def register_game(definition: GameDefinition) -> None:
    """Registers (or replaces) a game definition, keyed by its own
    (case-insensitively matched) ``name``."""
    _GAMES[definition.name.lower()] = definition


def get_game(name: str) -> GameDefinition | None:
    """Looks up a game by friendly name, case-insensitively. Returns
    ``None`` if nothing is registered under that name."""
    return _GAMES.get(name.lower())


def list_games() -> list[GameDefinition]:
    """Returns every currently registered game definition."""
    return list(_GAMES.values())
