"""Media tool definitions — the assistant's EXISTING media capabilities,
described as data for the Tool Registry.

JAIRUS_ARCHITECTURE.md Part 14.7 (migration Phase 5), Part 15 (tool
properties), Part 17 (naming convention: "domain.action"), and Part 25
(permission levels — media control is one of the Level 0 / HARMLESS
examples given there).

Every entry here mirrors one action ``handle_command()`` (assistant_loop.py)
already dispatches through its if/elif, matching the actions
``intent_parser.py``'s ``SYSTEM_PROMPT`` can produce (play, queue, pause,
resume, skip, correct, volume_up, volume_down, whats_playing). Nothing here
changes that dispatch: ``handle_command()`` is untouched, and these
definitions are not called from anywhere except tests until a later phase
(the Tool Executor) routes real execution through the registry.

Registration is explicit, not an import-time side effect — importing this
module registers nothing on its own. Call ``register_media_tools()`` to
populate the registry (see TOOL_REGISTRY.md for where that's expected to
be called from today: tests only).
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

MEDIA_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="media.play",
        description=(
            "Plays one specific request: a song, a TV/anime episode, a movie "
            "clip, or a mood/vibe/genre request. Resets the queue to just "
            "this one item."
        ),
        input_schema={
            "title": {"type": "string", "description": "Song/show/episode title or search phrase"},
            "artist": {"type": "string", "description": "Performer/creator name, optional"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=30,
    ),
    ToolDefinition(
        name="media.queue",
        description="Queues multiple songs back to back, playlist mode.",
        input_schema={
            "songs": {
                "type": "array",
                "description": "5-8 songs to queue, each {title, artist}",
                "items": {
                    "title": {"type": "string"},
                    "artist": {"type": "string"},
                },
            },
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=30,
    ),
    ToolDefinition(
        name="media.pause",
        description="Pauses whatever is currently playing.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="media.resume",
        description="Resumes playback of whatever was paused.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="media.skip",
        description=(
            "Skips to the next track — advances the local queue if one "
            "exists, otherwise falls back to the current source's own skip."
        ),
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="media.correct",
        description=(
            'Switches to the next YouTube search result after a rejection '
            '("no not that one," "wrong video").'
        ),
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="media.volume_up",
        description="Turns the volume up one step.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
    ToolDefinition(
        name="media.volume_down",
        description="Turns the volume down one step.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
    ToolDefinition(
        name="media.now_playing",
        description="Reports what is currently playing, if anything.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
]


def register_media_tools() -> None:
    """Registers every media tool definition above with the Tool Registry."""
    for tool in MEDIA_TOOLS:
        register_tool(tool)
