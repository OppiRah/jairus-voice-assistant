# Jairus — Phase 8: Browser Tools

**Migration step:** Phase 8 of `JAIRUS_ARCHITECTURE.md` (Part 14.10),
implementing the Part 21 browser automation primitives from Part 23's
capability catalog, built on the same Tool Registry (Phase 5) and Tool
Executor (Phase 6) as every prior phase.

**One-sentence summary:** the assistant can now really navigate, search,
inspect, and go back/forward in a browser tab via five new `browser.*`
tools — generalizing the existing YouTube-only Playwright/CDP connection
into reusable primitives, per Part 14.10's own framing ("Jairus can play
YouTube" → "Jairus has a browser automation capability") — but **nothing
reaches this from voice yet**.

---

## 1. What Phase 8 implemented

Five tools, wired through the existing Tool Registry/Executor pipeline,
backed by real (not stubbed) Playwright/CDP code:

```
browser.navigate           browser.search
browser.get_current_page   browser.back
browser.forward
```

## 2. Files created / modified

| File | Status | Purpose |
|---|---|---|
| `src/jairus/infrastructure/automation/browser.py` | **new** | Real implementation: `navigate`, `search`, `get_current_page`, `go_back`, `go_forward`. |
| `src/jairus/tools/browser_tools.py` | **new** | `BROWSER_TOOLS` (5 `ToolDefinition`s) + `register_browser_tools()`. |
| `src/jairus/tools/executor.py` | modified | Added 5 handler mappings (`browser.* -> jairus.infrastructure.automation.browser.*`), same try/except/`ToolResult` shape as `media.*`/`apps.*`. |
| `src/jairus/tools/__init__.py` | modified | Re-exports `BROWSER_TOOLS`, `register_browser_tools`. |

No other file was touched. `requirements.txt` is unchanged — no new
dependency (see §16 below).

## 3. Architecture integration

```
ToolDefinition (browser_tools.py)
        ↓
Tool Registry (registry.py, Phase 5 — unmodified)
        ↓
Tool Executor (executor.py, Phase 6 — extended)
        ↓
jairus.infrastructure.automation.browser  (new this phase)
        ↓
player_action._get_browser()  (EXISTING, Phase 0 — reused, not duplicated)
        ↓
Playwright  ->  CDP (localhost:9222)  ->  Brave
```

Exactly the chain `JAIRUS_ARCHITECTURE.md` Part 14.10 specifies
(`Agent → browser.navigate → Browser Tool → Browser Adapter →
Playwright/CDP → Browser`), with "Browser Adapter" being
`jairus.infrastructure.automation.browser` and "Agent" not existing yet
(nothing calls these tools but tests, per this phase's scope rule).

---

## 4. Tool Registry

`register_browser_tools()` (explicit call, not an import-time side effect —
same pattern as `register_media_tools()` / `register_app_tools()`)
registers:

| Tool name | permission_level | requires_confirmation | timeout_seconds |
|---|---|---|---|
| `browser.navigate` | `HARMLESS` | `False` | 15 |
| `browser.search` | `HARMLESS` | `False` | 15 |
| `browser.get_current_page` | `HARMLESS` | `False` | 10 |
| `browser.back` | `HARMLESS` | `False` | 15 |
| `browser.forward` | `HARMLESS` | `False` | 15 |

All `HARMLESS` per Part 25's own Level 0 examples, which explicitly list
both "open website" and "search." Permission metadata is fixed on the
`ToolDefinition` itself — callers/the executor cannot override it.

## 5. Tool Executor

`execute_tool("browser.navigate", {"url": "https://example.com"})` etc.
all route through the same `execute_tool()` used for `media.*`/`apps.*`:
look up the `ToolDefinition` (→ `NOT_FOUND` if unregistered), call the
mapped handler inside a `try/except` (→ `EXECUTION_ERROR` with the
exception's message on failure), otherwise `ToolResult(success=True,
data=...)`. `player_action`, `apps`, and `browser` are all imported lazily
inside the same `_handlers()` function, so importing `jairus.tools` never
requires Playwright/pygame/ctypes to succeed first.

## 6. Browser backend — how these connect to Playwright/CDP/Brave

`player_action.py` already has a working CDP connection: `_get_browser()`
connects Playwright's `chromium.connect_over_cdp()` to an already-running
Brave instance at `CDP_URL = "http://localhost:9222"`, caching the
`Playwright`/`Browser` handle and reconnecting only if the cached one goes
stale. **`browser.py` calls that exact function** (`player_action._get_browser()`)
rather than opening a second connection. Two reasons this isn't optional:

1. Part 19's hierarchy and this phase's scope rule both say "reuse what
   already works, don't add a second automation backend."
2. Practically, Playwright's sync API isn't meant to run two independent
   `sync_playwright().start()` calls in one process/thread — reusing the
   single cached handle sidesteps that, and avoids two independent CDP
   clients fighting over the same Brave instance.

`player_action.py` itself is **not modified** — its private `_get_browser`
is called, not duplicated or rewritten.

**Tab isolation (a deliberate safety choice):** these tools act on their
own dedicated tab (`browser.py`'s module-level `_tool_page`, opened once
via `context.new_page()` and reused across calls), never on whatever tabs
already happen to be open in Brave. In particular, never on whatever tab
`player_action.py` is using for active YouTube playback (tracked
separately there as `_last_played_page`). A generic `browser.navigate`
call must never interrupt music the user has playing — real testing
confirmed a live YouTube Music tab stayed untouched throughout.

No new browser context is created per call — the dedicated tab is opened
once and reused (`_tool_page`), same "don't recreate expensive state every
call" posture the timeout/resource-safety requirements call for.

---

## 7. Testing

**Real, not mocked** — run against the actual live Brave/CDP session
(reachable at the time of testing: `GET localhost:9222/json/version` →
200). A dedicated tab was opened for testing and closed again afterward;
existing tabs (including a live YouTube Music tab) were left untouched.

| Tool | Result | What was verified |
|---|---|---|
| `browser.navigate` | **PASS** | Navigated to `https://example.com`; `ToolResult.success=True`, resulting `data["url"] == "https://example.com/"`. |
| `browser.get_current_page` | **PASS** | Reported `url`/`title` matching the page just navigated to (`"Example Domain"`). |
| `browser.search` | **PASS** | Searched `"example domain"`; resulting `url` is a `google.com/search?q=...` URL carrying the query, `data["query"]` echoes it back — asserted at the URL level, not on fragile page content, per the task's own guidance. |
| `browser.back` | **PASS** | Navigated A (`example.com`) → B (`example.org`), then `browser.back` returned to A (`moved: True`). |
| `browser.forward` | **PASS** | From A, `browser.forward` returned to B (`moved: True`). |
| Failure path (`Brave/CDP unavailable`) | **PASS** | `player_action._get_browser` monkeypatched to raise (the tool tab was first forced to reconnect so the patched function is actually exercised); `execute_tool("browser.navigate", ...)` returned `success=False`, `failure_category=EXECUTION_ERROR`, with "Brave" in the error message — no false success. |
| (bonus) `browser.does_not_exist` | **PASS** | `NOT_FOUND`, no attempt to touch the browser. |

### A real bug found and fixed during this testing

`go_back()`/`go_forward()` initially waited on Playwright's
`wait_until="domcontentloaded"`, and reliably **timed out** on real
back/forward navigations between simple static pages: a page restored
from the browser's own back/forward cache commits its URL change without
ever re-firing `domcontentloaded` (no document is actually re-parsed), so
Playwright's wait never resolved even though the navigation had already
succeeded. Fixed by waiting on `"commit"` instead (resolves as soon as the
navigation is committed — appropriate for history navigation, unlike a
fresh `navigate()`/`search()` load, which still correctly waits on
`domcontentloaded`), with a defensive `TimeoutError` catch left in place
as a fallback. Re-verified working after the fix (see table above).

A second, non-code issue: the first back/forward test pair used
`https://www.iana.org/domains/reserved`, which turned out to
client-side-redirect mid-navigation, breaking history assumptions —
exactly the "fragile website-specific" trap the task warned about. Swapped
to `https://example.org` (an IANA-reserved test domain, alongside
`example.com` — static, no redirects) for a reliable pair.

---

## 8. Failure handling

Every `browser.py` function raises `BrowserUnavailableError` (a
`RuntimeError` subclass) or `ValueError` on anything that isn't a clean
success — never returns a success-shaped result for a failed operation:

| Scenario | How it's handled |
|---|---|
| Brave/CDP unreachable | `_connect()` catches `player_action._get_browser()`'s own exception, re-raises with a clear message. Verified live via the monkeypatch test above. |
| No open browser context | `_connect()` raises explicitly if `browser.contexts` is empty. |
| No usable page | `_get_page()` opens a fresh dedicated tab if none exists/the previous one closed; raises if even that fails. |
| Invalid URL | `_validate_url()` rejects `javascript:`, `file://`, `data:`, `chrome://`, `vbscript:`, `ftp:`, and empty input — raises `ValueError` before any navigation is attempted. A bare host/domain (`"youtube.com"`, `"localhost:9222"`) is accepted and prefixed with `https://`. |
| Navigation failure / timeout | `page.goto()`/`go_back()`/`go_forward()` exceptions are caught and re-raised as `BrowserUnavailableError` with the underlying Playwright error attached — **except** the back/forward-cache `TimeoutError` case above, which is verified via observed URL instead (see §7). |
| Browser/tab closed mid-session | `_get_page()` detects a dead tracked tab (touching `.url` raises) and transparently opens a new one. |
| Unexpected Playwright error | Falls through the same generic `except Exception` → `BrowserUnavailableError` path. |

At the Tool Executor layer, any exception raised by `browser.py` is caught
and reported as `ToolResult(success=False, failure_category=EXECUTION_ERROR,
error=str(exc))` — the same uniform mapping already used for `media.*` and
`apps.*` (Phases 6-7); this phase does not introduce a new, differentiated
failure taxonomy at the executor layer, to stay consistent with the
established pattern. Every `navigate`/`search`/`back`/`forward` result also
carries the **observed** post-action `url`/`title` (and `moved` for
back/forward) — read back from the page itself, not assumed from
"Playwright didn't throw." That observed state is what the tests above
actually assert on.

---

## 9. What is intentionally NOT implemented

- `browser.open` (listed in Part 23's catalog but not requested for this
  phase — only the five tools explicitly scoped).
- Clicking through search results, DOM extraction, typing, scrolling,
  arbitrary JavaScript execution, login/credential handling, CAPTCHA
  solving, vision-based browsing — all explicitly out of scope per the
  task and Part 21's own "potential later capabilities" list
  (`browser.click`, `browser.type`, `browser.scroll`, `browser.extract`,
  `browser.inspect`).
- A second browser connection, browser automation framework (e.g.
  Selenium), browser process, or profile — reuses `player_action.py`'s
  existing single CDP connection exclusively.
- Windows UI Automation — that's Phase 9, a separate later phase.

## 10. What is intentionally NOT wired in yet

**The browser tools are currently standalone infrastructure.**

**They are NOT yet selected by the Agent Core, NOT yet selected by the
LLM, and NOT yet part of the live voice command dispatch path.**

`intent_parser.py` has no `browser.*` concept in its `SYSTEM_PROMPT` or
JSON shape. `handle_command()`'s if/elif still does everything it did
before this phase, byte-for-byte (confirmed via `git diff` — empty).
Saying "open Google" or "go back" to Aria today does exactly what it did
before Phase 8: nothing recognizes it as a browser command. That
integration is Part 14.12 (Agent Core) and Part 14.13 (removing legacy
intent routing) — both explicitly later phases.

---

## 11. Known limitations

- No true "currently focused tab" concept is exposed by this Playwright/CDP
  connection model; these tools always act on their own dedicated tab
  (opened once, reused across calls), not whatever tab is visibly active
  in the Brave window. This is a deliberate safety trade-off (see §6), not
  an oversight — it also gives the tools a stable target instead of racing
  the user's own tab-switching.
- `browser.back`/`browser.forward`'s `moved` flag distinguishes "actually
  navigated" from "nothing to go back/forward to" (Playwright's own
  `go_back()`/`go_forward()` return `None` with no exception in that
  case) — but a call that times out on the fallback `TimeoutError` path
  with the URL genuinely unchanged (e.g. a truly stuck browser) also
  reports `moved: False`, `success: True`, since from a black-box
  URL-observation standpoint the two look the same within this phase's
  scope.
- `browser.search` always resolves to Google; no engine selection.
- Timeouts (15s navigate/search/back/forward, 10s get_current_page) are
  fixed constants, not yet read from `ToolDefinition.timeout_seconds` by
  the executor — the value is recorded correctly as metadata but not yet
  enforced from there, same posture Phase 7 already documented for
  `apps.*`.

---

## 12. Aria regression check

`git diff` on `intent_parser.py`, `assistant_loop.py` (`handle_command()`),
`command_gateway.py`, `task_manager.py`, and `player_action.py` — all
empty; none were touched.

Live-verified: killed any stray processes, then ran
`python -u main.py` for real. Output confirmed full, normal
initialization — pygame/orb init, openwakeword model load, mic stream
opened — ending in:

```
[ready] listening for wake word: 'hey jairus'
        say it, then say your command, e.g.:
        'hey jairus' ... 'play something chill'
        ...
```

identical to pre-Phase-8 behavior. The process was then terminated (this
is a background-thread, GUI + microphone application; an actual spoken
wake-word-triggered voice command isn't practical to drive from this
non-interactive environment — same limitation `COMMAND_GATEWAY.md`
already documented for Phase 3's verification). The new `browser.*` tools
were not touched by, and are not reachable from, this live run.

---

## 13. Dependencies

**None added.** `requirements.txt` is unchanged. `playwright` was already
a dependency (used by `player_action.py`); this phase's `browser.py`
imports only `playwright.sync_api.TimeoutError` and reuses the existing
`sync_playwright`-backed connection — no new package, no second
automation framework.
