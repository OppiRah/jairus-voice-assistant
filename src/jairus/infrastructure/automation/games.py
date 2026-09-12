"""Game process control — launch, detect, focus, close, list running.

JAIRUS_ARCHITECTURE.md Part 14.17 (migration Phase 15), Part 22 (Game
Automation: "Game Registry -> Game Identity/Configuration -> Launcher
Adapter -> Generic Game Tools"), Part 23 (capability catalog), and Part
15.15's Level 1 ("Process Control": launch/detect/focus/close) scope fence
— Level 2 (launcher integration), Level 3+ (in-game state), and beyond are
explicitly later, separate roadmap steps, not built here.

A game is just a process (Part 22's own framing) — a launcher and a
close/detect/focus target, nothing more at this level. Rather than
duplicate Phase 7's process-automation logic, every function here does
exactly one thing: resolve a friendly game name through the Game Registry
(``jairus.configuration.game_registry``) into a ``GameDefinition``, then
delegate straight to the matching ``jairus.infrastructure.automation.apps``
function using that definition's ``process_name``/``launch_command``. None
of ``launch_app``/``detect_app``/``focus_app``/``close_app``/
``list_running_apps`` is reimplemented or altered.

The registry is the only source of truth for what counts as a "known
game": a name that isn't registered returns a clean ``False`` (or, for
``list_running_games``, simply can't appear) rather than falling back to
guessing a raw process name or attempting a launch with an unresolved
command.
"""

from __future__ import annotations

from jairus.configuration.game_registry import get_game, list_games

from . import apps


def launch_game(name: str) -> bool:
    """Launches a registered game by friendly name, via ``apps.launch_app``
    using its ``launch_command``. Returns ``False`` without attempting
    anything if ``name`` isn't in the Game Registry."""
    game = get_game(name)
    if game is None:
        print(f"[games] '{name}' is not a registered game")
        return False
    return apps.launch_app(game.launch_command)


def detect_game(name: str) -> bool:
    """Reports whether a registered game's process is currently running,
    via ``apps.detect_app`` using its ``process_name``. Returns ``False``
    if ``name`` isn't in the Game Registry."""
    game = get_game(name)
    if game is None:
        print(f"[games] '{name}' is not a registered game")
        return False
    return apps.detect_app(game.process_name)


def focus_game(name: str) -> bool:
    """Brings a registered game's window to the foreground, via
    ``apps.focus_app`` using its ``process_name``. Returns ``False`` if
    ``name`` isn't in the Game Registry."""
    game = get_game(name)
    if game is None:
        print(f"[games] '{name}' is not a registered game")
        return False
    return apps.focus_app(game.process_name)


def close_game(name: str) -> bool:
    """Gracefully closes a registered game's process, via
    ``apps.close_app`` using its ``process_name``. Returns ``False`` if
    ``name`` isn't in the Game Registry."""
    game = get_game(name)
    if game is None:
        print(f"[games] '{name}' is not a registered game")
        return False
    return apps.close_app(game.process_name)


def list_running_games() -> list[str]:
    """Cross-references the Game Registry against
    ``apps.list_running_apps()`` and returns the friendly names of every
    registered game currently running, sorted."""
    running = {name.lower() for name in apps.list_running_apps()}
    return sorted(game.name for game in list_games() if game.process_name.lower() in running)
