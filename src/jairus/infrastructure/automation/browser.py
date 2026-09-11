"""Browser automation primitives — generalizes the existing YouTube-only
Playwright/CDP integration into reusable ``browser.*`` operations.

JAIRUS_ARCHITECTURE.md Part 14.10 (migration Phase 8), Part 21 (browser
automation — Playwright/CDP/DOM-level interaction, preferred over
coordinate clicking), Part 19 (automation backend hierarchy: browser
DOM/CDP/Playwright sits below native API and Windows UI Automation, above
raw input simulation), and Part 23 (capability catalog).

Where this phase's "Jairus can play YouTube" -> "Jairus has a browser
automation capability" shift (Part 14.10's own words) comes from: this
module does NOT open a second, competing browser connection. It reuses the
EXISTING connection mechanism already in ``player_action.py``
(``_get_browser()``, connecting over CDP to an already-running Brave
instance at ``CDP_URL = "http://localhost:9222"``) by calling that
function directly. Two independent reasons this matters, not just style:

1. Part 19's own hierarchy and this phase's scope rule both say "reuse
   what already works, don't introduce a second automation backend."
2. Practically, Playwright's sync API is not meant to be started twice
   (``sync_playwright().start()``) in the same process/thread — reusing
   ``player_action``'s single cached ``Playwright``/``Browser`` handle
   avoids that entirely, as well as avoiding two independent CDP
   connections fighting over the same Brave instance.

``player_action.py`` itself is NOT modified — its private ``_get_browser``
is called, not duplicated, not rewritten.

**Tab isolation, a deliberate safety choice:** these tools act on their own
dedicated browser tab (opened once, then reused across calls, tracked in
``_tool_page``), never on whatever tab(s) already exist in Brave — in
particular, never on whatever ``player_action.py`` itself is using for
active YouTube playback (tracked separately, as ``_last_played_page``,
over there). A generic ``browser.navigate`` call must never accidentally
navigate away from music the user has playing. See ``_get_page()``.
"""

from __future__ import annotations

import re
from typing import Any
from urllib.parse import quote_plus

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError

NAVIGATION_TIMEOUT_MS = 15000
SEARCH_URL = "https://www.google.com/search?q={query}"
_ALLOWED_SCHEMES = ("http://", "https://")
# Schemes that mean "run code" or "read local state" rather than "go to a web
# address" -- rejected outright, whether or not they'd otherwise look like a
# bare host:port to the naive parser below (e.g. "localhost:9222" is a valid
# host:port and must NOT be caught by this; "javascript:..." must be).
_DANGEROUS_SCHEME_RE = re.compile(
    r"^(javascript|data|file|vbscript|chrome|chrome-extension|about|ftp):",
    re.IGNORECASE,
)

_tool_page = None  # the dedicated tab browser.* operations act on, once one exists


class BrowserUnavailableError(RuntimeError):
    """Raised for anything that means the browser/tab isn't usable right
    now: Brave/CDP unreachable, no browser context, a page that closed out
    from under us, a navigation that failed or timed out, or any other
    unexpected Playwright error. Callers (the Tool Executor) catch this
    like any other exception and report it as a failed ``ToolResult`` —
    it is never swallowed into a false success."""


def _connect():
    # Lazy import, not at module load: avoids requiring player_action.py's
    # own imports (Playwright, pygame, ctypes) just to import this module —
    # the same reasoning jairus.tools.executor already uses for the same
    # import, and why that module's lazy import also covers this one.
    import player_action

    try:
        browser = player_action._get_browser()
    except Exception as e:
        raise BrowserUnavailableError(f"couldn't connect to Brave over CDP: {e}") from e

    if not browser.contexts:
        raise BrowserUnavailableError("connected to Brave, but it has no open browser context")

    return browser.contexts[0]


def _get_page():
    """Returns the dedicated tab these tools act on, opening a fresh one
    (in the existing, shared browser context) if none exists yet or the
    previous one was closed. Deliberately does NOT reuse or repurpose
    whatever tabs already happen to be open — see the module docstring."""
    global _tool_page

    context = _connect()

    if _tool_page is not None:
        try:
            _ = _tool_page.url  # touch it; raises if the tab was closed
            return _tool_page
        except Exception:
            _tool_page = None

    try:
        _tool_page = context.new_page()
    except Exception as e:
        raise BrowserUnavailableError(f"couldn't open a browser tab: {e}") from e

    return _tool_page


def _validate_url(url: str) -> str:
    """Accepts a full http(s) URL as-is, or a bare host (optionally with a
    port and/or path, e.g. ``"youtube.com"`` or ``"localhost:9222"``) —
    assumed https and prefixed accordingly. Rejects ``javascript:``,
    ``file://``, ``data:``, ``chrome://``, and similar outright: this tool
    navigates to web addresses, it does not accept arbitrary executable
    commands."""
    raw = (url or "").strip()
    if not raw:
        raise ValueError("no URL given")
    if _DANGEROUS_SCHEME_RE.match(raw):
        raise ValueError(f"unsupported/unsafe URL scheme in '{raw}'")
    if raw.lower().startswith(_ALLOWED_SCHEMES):
        return raw
    return f"https://{raw}"


def _page_info(page) -> dict[str, Any]:
    """Reads back the page's OWN current state after an action, rather
    than assuming the action worked because Playwright didn't raise — this
    is the verification step Part 30 ("tool executed != task succeeded")
    calls for, using the resulting URL/title as observable evidence."""
    try:
        return {"url": page.url, "title": page.title()}
    except Exception as e:
        raise BrowserUnavailableError(f"couldn't read the page's current state: {e}") from e


def navigate(url: str) -> dict[str, Any]:
    """Navigates the tool tab to ``url``. Returns the resulting
    ``{url, title}`` as actually observed after navigation."""
    target = _validate_url(url)
    print(f"[browser] navigating to '{target}'")
    page = _get_page()
    try:
        page.goto(target, wait_until="domcontentloaded", timeout=NAVIGATION_TIMEOUT_MS)
    except Exception as e:
        raise BrowserUnavailableError(f"navigation to '{target}' failed: {e}") from e
    return _page_info(page)


def search(query: str) -> dict[str, Any]:
    """Navigates the tool tab to a deterministic search-engine results
    page for ``query`` (Google). Does not click through any results —
    that's out of scope for this phase. Returns the resulting
    ``{url, title, query}``."""
    query = (query or "").strip()
    if not query:
        raise ValueError("no search query given")
    target = SEARCH_URL.format(query=quote_plus(query))
    print(f"[browser] searching for '{query}'")
    page = _get_page()
    try:
        page.goto(target, wait_until="domcontentloaded", timeout=NAVIGATION_TIMEOUT_MS)
    except Exception as e:
        raise BrowserUnavailableError(f"search for '{query}' failed: {e}") from e
    info = _page_info(page)
    info["query"] = query
    return info


def get_current_page() -> dict[str, Any]:
    """Returns ``{url, title}`` for the tool tab's current state."""
    return _page_info(_get_page())


def go_back() -> dict[str, Any]:
    """Navigates the tool tab backward in history, if there is any.
    Returns the resulting ``{url, title, moved}`` — ``moved`` is ``False``
    (not an error) when there was no back history to go to, since
    Playwright's own ``go_back()`` returns ``None`` rather than raising in
    that case. Waits only for the navigation to "commit" (URL updated),
    not the full "domcontentloaded" ``navigate()``/``search()`` wait on:
    a history entry restored from the browser's own back/forward cache
    commits its URL change without re-firing "domcontentloaded" at all
    (no document is actually re-parsed), so waiting on that specific event
    here would time out on most simple back/forward navigations even
    though they'd already succeeded. A stray timeout is still handled
    defensively — the actual outcome is decided by comparing the observed
    URL below either way, same as every other case here."""
    page = _get_page()
    before_url = page.url
    print(f"[browser] going back from '{before_url}'")
    try:
        page.go_back(wait_until="commit", timeout=NAVIGATION_TIMEOUT_MS)
    except PlaywrightTimeoutError:
        pass
    except Exception as e:
        raise BrowserUnavailableError(f"back navigation failed: {e}") from e
    info = _page_info(page)
    info["moved"] = info["url"] != before_url
    return info


def go_forward() -> dict[str, Any]:
    """Navigates the tool tab forward in history, if there is any. Same
    ``moved`` semantics, and same back/forward-cache handling, as
    ``go_back()``."""
    page = _get_page()
    before_url = page.url
    print(f"[browser] going forward from '{before_url}'")
    try:
        page.go_forward(wait_until="commit", timeout=NAVIGATION_TIMEOUT_MS)
    except PlaywrightTimeoutError:
        pass
    except Exception as e:
        raise BrowserUnavailableError(f"forward navigation failed: {e}") from e
    info = _page_info(page)
    info["moved"] = info["url"] != before_url
    return info
