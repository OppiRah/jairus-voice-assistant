"""Tool Executor — runs a registered tool by name.

JAIRUS_ARCHITECTURE.md Part 14.8 (migration Phase 6), extended in Phase 7
(Part 14.9) with the new ``apps.*`` tools.

Phase 6 scope, deliberately narrow: given a tool name and arguments, look
the tool up in the Tool Registry (Phase 5) and run the EXISTING
``player_action.py`` function it maps to — the same functions
``handle_command()``'s if/elif has always called directly. Nothing here
rewrites ``player_action.py``'s logic; it is imported and called, the same
"wrap it, don't rewrite it" approach Phase 3 took with ``handle_command()``
itself (JAIRUS_ARCHITECTURE.md's own words: "the underlying implementation
can initially remain mostly unchanged... we're changing the architecture
around the capability, not rewriting working functionality").

Phase 7 adds the five ``apps.*`` tools, which wrap genuinely NEW code
(``jairus.infrastructure.automation.apps``) the same way, with the same
try/except/``ToolResult`` shape — there was no existing app-control code
to wrap, so Phase 7 wrote it, then exposed it here identically to how the
media tools are exposed.

Phase 8 (Part 14.10) adds the five ``browser.*`` tools, mapped to
``jairus.infrastructure.automation.browser`` the same way again. That
module reuses ``player_action.py``'s existing Playwright/CDP connection
rather than opening a second one — see its own docstring.

Phase 9 (Part 14.11) adds the six ``windows.*`` tools, mapped to
``jairus.infrastructure.automation.windows_ui`` (genuinely new — semantic
Windows UI Automation via pywinauto, no coordinate clicking). Same
try/except/``ToolResult`` shape once again.

Phase 15 (Part 14.17) adds the five ``game.*`` tools, mapped to
``jairus.infrastructure.automation.games`` — which itself resolves a
friendly game name through the Game Registry and delegates straight to
Phase 7's existing ``apps.py`` functions, duplicating none of that
automation logic. Same try/except/``ToolResult`` shape once again.

Per the architecture's own sequencing — "Introduce the Real Agent Loop" is
Part 14.12 and "Remove legacy intent routing" is Part 14.13, both AFTER
Phase 9 — there is no Agent Core wired into live voice dispatch to decide
which tool to call, and nothing here wires ``execute_tool()`` into
``handle_command()``'s legacy dispatch. It is complete and tested
standalone but unreachable from voice; see TOOL_EXECUTOR.md, APPS_TOOLS.md,
BROWSER_TOOLS.md, WINDOWS_UI_TOOLS.md, and GAME_TOOLS.md.
"""

from __future__ import annotations

from typing import Any, Callable

from jairus.domain.tools import FailureCategory, ToolResult

from .registry import get_tool


def _handlers() -> dict[str, Callable[[dict[str, Any]], dict[str, Any] | None]]:
    # Imported lazily (not at module load) so importing this module — or the
    # rest of the jairus.tools package — never requires player_action.py's
    # own imports (Playwright, pygame, ctypes) to succeed first, the same
    # reasoning command_gateway.py uses for its lazy `handle_command` import.
    import player_action
    from jairus.infrastructure.automation import apps
    from jairus.infrastructure.automation import browser as browser_automation
    from jairus.infrastructure.automation import games
    from jairus.infrastructure.automation import windows_ui

    def run_play(arguments: dict[str, Any]) -> None:
        # play_song() expects an intent-shaped dict with "title"/"artist",
        # which is exactly the media.play input_schema — passed straight through.
        player_action.play_song(arguments)
        return None

    def run_queue(arguments: dict[str, Any]) -> None:
        player_action.start_queue(arguments.get("songs", []))
        return None

    def run_pause(arguments: dict[str, Any]) -> None:
        player_action.pause_music()
        return None

    def run_resume(arguments: dict[str, Any]) -> None:
        player_action.resume_music()
        return None

    def run_skip(arguments: dict[str, Any]) -> None:
        player_action.skip_music()
        return None

    def run_correct(arguments: dict[str, Any]) -> dict[str, Any]:
        switched = player_action.correct_song()
        return {"switched": switched}

    def run_volume_up(arguments: dict[str, Any]) -> None:
        player_action.adjust_volume("up")
        return None

    def run_volume_down(arguments: dict[str, Any]) -> None:
        player_action.adjust_volume("down")
        return None

    def run_now_playing(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"now_playing": player_action.get_now_playing()}

    def run_apps_launch(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"launched": apps.launch_app(arguments.get("path_or_name", ""))}

    def run_apps_close(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"closed": apps.close_app(arguments.get("process_name", ""))}

    def run_apps_focus(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"focused": apps.focus_app(arguments.get("process_name", ""))}

    def run_apps_detect(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"running": apps.detect_app(arguments.get("process_name", ""))}

    def run_apps_list_running(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"apps": apps.list_running_apps()}

    def run_game_launch(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"launched": games.launch_game(arguments.get("name", ""))}

    def run_game_detect(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"running": games.detect_game(arguments.get("name", ""))}

    def run_game_focus(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"focused": games.focus_game(arguments.get("name", ""))}

    def run_game_close(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"closed": games.close_game(arguments.get("name", ""))}

    def run_game_list_running(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"games": games.list_running_games()}

    def run_browser_navigate(arguments: dict[str, Any]) -> dict[str, Any]:
        return browser_automation.navigate(arguments.get("url", ""))

    def run_browser_search(arguments: dict[str, Any]) -> dict[str, Any]:
        return browser_automation.search(arguments.get("query", ""))

    def run_browser_get_current_page(arguments: dict[str, Any]) -> dict[str, Any]:
        return browser_automation.get_current_page()

    def run_browser_back(arguments: dict[str, Any]) -> dict[str, Any]:
        return browser_automation.go_back()

    def run_browser_forward(arguments: dict[str, Any]) -> dict[str, Any]:
        return browser_automation.go_forward()

    def run_windows_get_active_window(arguments: dict[str, Any]) -> dict[str, Any]:
        return windows_ui.get_active_window()

    def run_windows_list_windows(arguments: dict[str, Any]) -> dict[str, Any]:
        return {"windows": windows_ui.list_windows()}

    def run_windows_find_control(arguments: dict[str, Any]) -> dict[str, Any]:
        return windows_ui.find_control(
            arguments.get("window_title", ""),
            arguments.get("control_name", ""),
            arguments.get("control_type"),
        )

    def run_windows_invoke(arguments: dict[str, Any]) -> dict[str, Any]:
        invoked = windows_ui.invoke_control(
            arguments.get("window_title", ""),
            arguments.get("control_name", ""),
            arguments.get("control_type"),
        )
        return {"invoked": invoked}

    def run_windows_type(arguments: dict[str, Any]) -> dict[str, Any]:
        typed = windows_ui.type_into_control(
            arguments.get("window_title", ""),
            arguments.get("control_name", ""),
            arguments.get("text", ""),
            arguments.get("control_type"),
        )
        return {"typed": typed}

    def run_windows_hotkey(arguments: dict[str, Any]) -> dict[str, Any]:
        sent = windows_ui.send_hotkey(arguments.get("window_title", ""), arguments.get("keys", ""))
        return {"sent": sent}

    return {
        "media.play": run_play,
        "media.queue": run_queue,
        "media.pause": run_pause,
        "media.resume": run_resume,
        "media.skip": run_skip,
        "media.correct": run_correct,
        "media.volume_up": run_volume_up,
        "media.volume_down": run_volume_down,
        "media.now_playing": run_now_playing,
        "apps.launch": run_apps_launch,
        "apps.close": run_apps_close,
        "apps.focus": run_apps_focus,
        "apps.detect": run_apps_detect,
        "apps.list_running": run_apps_list_running,
        "game.launch": run_game_launch,
        "game.detect": run_game_detect,
        "game.focus": run_game_focus,
        "game.close": run_game_close,
        "game.list_running": run_game_list_running,
        "browser.navigate": run_browser_navigate,
        "browser.search": run_browser_search,
        "browser.get_current_page": run_browser_get_current_page,
        "browser.back": run_browser_back,
        "browser.forward": run_browser_forward,
        "windows.get_active_window": run_windows_get_active_window,
        "windows.list_windows": run_windows_list_windows,
        "windows.find_control": run_windows_find_control,
        "windows.invoke": run_windows_invoke,
        "windows.type": run_windows_type,
        "windows.hotkey": run_windows_hotkey,
    }


def execute_tool(tool_name: str, arguments: dict[str, Any]) -> ToolResult:
    """Runs a registered tool by name, wrapping the matching
    ``player_action.py`` function (``media.*``),
    ``jairus.infrastructure.automation.apps`` function (``apps.*``),
    ``jairus.infrastructure.automation.browser`` function (``browser.*``),
    ``jairus.infrastructure.automation.windows_ui`` function (``windows.*``),
    or ``jairus.infrastructure.automation.games`` function (``game.*``).

    ``tool_name`` is looked up in the Tool Registry first (``get_tool()``
    from Phase 5) — a name that isn't registered there returns a
    ``ToolResult`` with ``success=False`` / ``failure_category=NOT_FOUND``
    without attempting to run anything. Note this means the registry must
    already be populated (e.g. by calling
    ``jairus.tools.register_media_tools()``,
    ``jairus.tools.register_app_tools()``,
    ``jairus.tools.register_browser_tools()``,
    ``jairus.tools.register_windows_tools()``, and/or
    ``jairus.tools.register_game_tools()``) before a call can succeed;
    nothing in this module registers tools itself.

    A tool call that raises is caught and reported as
    ``failure_category=EXECUTION_ERROR`` rather than propagating, so a
    caller can inspect ``ToolResult.error`` instead of handling exceptions.
    """
    print(f"[executor] running {tool_name}")

    if get_tool(tool_name) is None:
        return ToolResult(
            success=False,
            error=f"no tool registered as '{tool_name}'",
            failure_category=FailureCategory.NOT_FOUND,
        )

    handler = _handlers().get(tool_name)
    if handler is None:
        # Registered (has a ToolDefinition) but nothing here knows how to run
        # it yet — can't happen for the nine media.* tools Phase 5 registers,
        # but kept as a safe default for any future tool definition.
        return ToolResult(
            success=False,
            error=f"'{tool_name}' is registered but has no execution handler yet",
            failure_category=FailureCategory.NOT_FOUND,
        )

    try:
        data = handler(arguments)
    except Exception as exc:  # the executor reports failures, it doesn't crash the caller
        print(f"[executor] {tool_name} failed: {exc}")
        return ToolResult(success=False, error=str(exc), failure_category=FailureCategory.EXECUTION_ERROR)

    return ToolResult(success=True, data=data)
