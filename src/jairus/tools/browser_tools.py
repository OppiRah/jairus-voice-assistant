"""Browser tool definitions — generalizes the existing YouTube-only
Playwright/CDP integration into reusable ``browser.*`` primitives.

JAIRUS_ARCHITECTURE.md Part 14.10 (migration Phase 8), Part 21 (browser
automation), Part 23 (capability catalog), and Part 25 (permission
examples — "open website" and "search" are both explicitly Level 0).

The underlying implementation lives in
``jairus.infrastructure.automation.browser`` (new this phase), which
reuses ``player_action.py``'s EXISTING Playwright/CDP connection to an
already-running Brave instance rather than opening a second, competing
browser connection — see that module's docstring for why.

Registration is explicit, not an import-time side effect, matching
``media_tools.py`` / ``app_tools.py``. Call ``register_browser_tools()``
to populate the registry.
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

BROWSER_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="browser.navigate",
        description=(
            "Navigates the browser's dedicated tool tab to a URL (a bare "
            "host is treated as https)."
        ),
        input_schema={
            "url": {"type": "string", "description": "http(s) URL, or a bare host/domain"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="browser.search",
        description=(
            "Navigates to a deterministic search-engine results page for a "
            "query. Does not click through any results."
        ),
        input_schema={
            "query": {"type": "string", "description": "Search query text"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="browser.get_current_page",
        description="Reports the URL and title of the browser's dedicated tool tab.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="browser.back",
        description="Navigates the browser's dedicated tool tab backward in history, if possible.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="browser.forward",
        description="Navigates the browser's dedicated tool tab forward in history, if possible.",
        input_schema={},
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
]


def register_browser_tools() -> None:
    """Registers every browser tool definition above with the Tool Registry."""
    for tool in BROWSER_TOOLS:
        register_tool(tool)
