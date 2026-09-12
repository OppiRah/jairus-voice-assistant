"""
player_action.py — the playback brain. Routes play/pause/resume/skip/volume/
now-playing across three backends, in priority order:

  1. Local files (if a match is found in your configured music library)
  2. YouTube, via your already-open Brave tab (Chrome DevTools Protocol)
  3. System media keys, as a last resort when nothing above is actively tracked

Also handles multi-song queues (playlist mode) and multi-turn correction
("no not that one" cycles through alternate YouTube search results).

IMPORTANT ONE-TIME SETUP: Brave has to be started with remote debugging enabled
for YouTube control to work. Close all Brave windows, then launch it with:

    "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe" --remote-debugging-port=9222
"""

from urllib.parse import quote_plus
from playwright.sync_api import sync_playwright

import local_library
import local_player
import media_keys

_playwright = None
_browser = None
_last_played_page = None
_last_search_results = []
_last_result_index = -1
_playback_mode = None   # "local" | "youtube" | None

_queue = []              # list of {"title": ..., "artist": ...}
_queue_index = -1

CDP_URL = "http://localhost:9222"
SEARCH_URL = "https://www.youtube.com/results?search_query={query}"
FIRST_RESULT_SELECTOR = "ytd-video-renderer a#video-title"
MAX_RESULTS_TO_TRACK = 5

# Phase 18 hardening (JAIRUS_ARCHITECTURE.md Part 14.20, Part 33's "no blind
# retry" principle): explicit, named timeouts for every CDP operation that
# previously had none or relied on Playwright's own (much longer, 30s)
# default. Picked to fail fast against a long-running Brave session where
# the person is also actively browsing -- see the module-level notes below
# each constant's use for the specific failure mode each one guards against.
CDP_CONNECT_TIMEOUT_MS = 5000     # a plain TCP+CDP handshake to a healthy Brave should be near-instant
NAVIGATION_TIMEOUT_MS = 20000     # a real page load; more generous than the above
SEARCH_RESULT_TIMEOUT_MS = 15000  # waiting for YouTube's own results DOM to render
PAGE_ACTION_TIMEOUT_MS = 4000     # a JS round-trip against an already-open tab (pause/resume/volume)
PAGE_RESPONSIVE_CHECK_TIMEOUT_MS = 3000  # the liveness probe itself, before trusting a tracked tab
MAX_CDP_CONNECT_ATTEMPTS = 2      # one real attempt + exactly one bounded reconnect, never a loop


# ---------- Brave / CDP plumbing ----------

def _get_browser():
    """Returns a live ``Browser`` connected to Brave over CDP, reusing the
    existing connection if it still looks valid. If ``connect_over_cdp()``
    times out (bounded by ``CDP_CONNECT_TIMEOUT_MS``) or raises for any
    other reason, this makes exactly ``MAX_CDP_CONNECT_ATTEMPTS`` total
    attempts before giving up -- a single bounded retry, not an unbounded
    loop (Part 33's "no blind retry" principle), on the theory that a
    transient hiccup (Brave briefly busy, a dropped websocket) is worth one
    second try, but a genuinely dead Brave process is not worth retrying
    forever."""
    global _playwright, _browser

    if _browser is not None:
        try:
            _ = _browser.contexts
        except Exception:
            _browser = None

    if _browser is not None:
        return _browser

    if _playwright is None:
        _playwright = sync_playwright().start()

    last_error = None
    for attempt in range(1, MAX_CDP_CONNECT_ATTEMPTS + 1):
        try:
            _browser = _playwright.chromium.connect_over_cdp(CDP_URL, timeout=CDP_CONNECT_TIMEOUT_MS)
            return _browser
        except Exception as e:
            last_error = e
            print(f"[player] CDP connect attempt {attempt}/{MAX_CDP_CONNECT_ATTEMPTS} failed: {e}")

    raise RuntimeError(
        f"Couldn't connect to Brave after {MAX_CDP_CONNECT_ATTEMPTS} attempts. Make sure Brave is "
        "running with --remote-debugging-port=9222."
    ) from last_error


def _is_page_responsive(page) -> bool:
    """Checks whether ``page`` is still attached AND actually responds to a
    live round-trip, bounded by ``PAGE_RESPONSIVE_CHECK_TIMEOUT_MS``. Two
    distinct failure modes this catches, both observed in real usage over a
    long-running session where the person is also actively browsing:

    1. The tab was manually closed (or navigated away and the target torn
       down) -- ``page.is_closed()`` catches this instantly, no round trip
       needed.
    2. Brave's Memory-Saver has put the tab's renderer to sleep. The target
       still exists (``is_closed()`` says ``False``), but a real
       ``Runtime``-level round trip to it may never come back.
       ``page.evaluate()`` has no timeout parameter at all and can hang
       indefinitely against exactly this case -- ``wait_for_function()``
       does support an explicit timeout, so a trivial always-true predicate
       here gives us a bounded, catchable failure instead of a hang.
    """
    try:
        if page.is_closed():
            return False
        page.wait_for_function("() => true", timeout=PAGE_RESPONSIVE_CHECK_TIMEOUT_MS)
        return True
    except Exception:
        return False


def _find_active_youtube_page():
    """Returns a live, verified-responsive YouTube watch-page tab, preferring
    the previously-tracked one. Phase 18 hardening: a tab matching by URL is
    no longer trusted just because it exists -- it must also pass
    ``_is_page_responsive()`` first, so a closed or Memory-Saver-sleeping tab
    is discovered here (bounded by a few seconds) rather than only once some
    later action on it hangs. ``.url`` itself is a cheap, client-side-cached
    property (no round trip), so checking it first before the more expensive
    responsiveness probe keeps the common case (many unrelated tabs open)
    fast."""
    global _last_played_page

    if _last_played_page is not None:
        try:
            is_watch_page = "youtube.com/watch" in _last_played_page.url
        except Exception:
            is_watch_page = False
        if is_watch_page and _is_page_responsive(_last_played_page):
            return _last_played_page
        _last_played_page = None  # closed, navigated away, or unresponsive -- stop trusting it

    try:
        browser = _get_browser()
        context = browser.contexts[0]
        for page in context.pages:
            try:
                if "youtube.com/watch" in page.url and _is_page_responsive(page):
                    return page
            except Exception:
                continue
    except Exception:
        pass

    return None


def _with_youtube_page(action):
    """Finds the active YouTube page and calls ``action(page)`` on it.

    Phase 18 hardening: if ``action`` raises -- a ``PlaywrightTimeoutError``
    from one of the bounded calls below, or the tab having gone away between
    ``_find_active_youtube_page()``'s check and this call -- that is treated
    as a signal the tracked page was stale rather than an immediate failure:
    ``_last_played_page`` is cleared and exactly one retry is made against a
    freshly rediscovered page (which will itself re-run the responsiveness
    check). Only if that also fails, or no page was found at all, does this
    return ``None`` -- a clean, fast failure instead of a hang, which
    (unchanged from Phase 3) already correctly propagates to Command/Task
    status as FAILED.
    """
    global _last_played_page

    for _ in range(2):  # one real attempt + exactly one retry against a rediscovered page
        page = _find_active_youtube_page()
        if page is None:
            return None
        try:
            return action(page)
        except Exception as e:
            print(f"[player] action on tracked YouTube tab failed/timed out ({e}); treating it as stale")
            _last_played_page = None

    return None


def _navigate_to_result(page, index: int):
    global _last_played_page
    href = _last_search_results[index]
    url = href if href.startswith("http") else f"https://www.youtube.com{href}"
    page.goto(url, wait_until="domcontentloaded", timeout=NAVIGATION_TIMEOUT_MS)
    _last_played_page = page


def _play_youtube(song: dict):
    global _last_search_results, _last_result_index, _playback_mode

    query = f"{song.get('title', '')} {song.get('artist', '')}".strip()
    print(f"[player] searching '{query}' on YouTube...")

    browser = _get_browser()
    context = browser.contexts[0]
    page = context.new_page()
    page.goto(
        SEARCH_URL.format(query=quote_plus(query)),
        wait_until="networkidle",
        timeout=NAVIGATION_TIMEOUT_MS,
    )

    page.wait_for_selector(FIRST_RESULT_SELECTOR, timeout=SEARCH_RESULT_TIMEOUT_MS)
    results = page.locator(FIRST_RESULT_SELECTOR)
    count = min(results.count(), MAX_RESULTS_TO_TRACK)

    hrefs = []
    for i in range(count):
        href = results.nth(i).get_attribute("href")
        if href:
            hrefs.append(href)

    if not hrefs:
        raise RuntimeError(f"no results found for '{query}'")

    _last_search_results = hrefs
    _last_result_index = 0
    _navigate_to_result(page, 0)
    _playback_mode = "youtube"
    print(f"[player] playing '{query}' (YouTube)")


# ---------- unified routing ----------

def _play_resolved_song(song: dict):
    """Plays one song dict — checks the local library first, YouTube otherwise."""
    global _playback_mode

    local_path = local_library.find_local_match(song.get("title", ""), song.get("artist", ""))
    if local_path:
        local_player.play_local(local_path)
        _playback_mode = "local"
        print(f"[player] playing '{local_path.stem}' (local file)")
    else:
        _play_youtube(song)


def play_song(intent: dict):
    """Plays a single song request. Also resets the queue to just this one song,
    so skip/correct behave sensibly even outside explicit playlist mode."""
    global _queue, _queue_index

    song = {"title": intent.get("title", ""), "artist": intent.get("artist", "")}
    _queue = [song]
    _queue_index = 0
    _play_resolved_song(song)


def start_queue(songs: list):
    """Starts playing a list of songs back to back (playlist mode)."""
    global _queue, _queue_index

    if not songs:
        print("[player] no songs to queue")
        return

    _queue = songs
    _queue_index = 0
    print(f"[player] queued {len(songs)} songs, starting with the first")
    _play_resolved_song(_queue[0])


def correct_song() -> bool:
    """Switches to the next YouTube search result (e.g. after 'no not that one')."""
    global _last_result_index

    if _playback_mode != "youtube":
        print("[player] correction only works for YouTube searches right now")
        return False

    if not _last_search_results or _last_played_page is None:
        print("[player] no recent search to correct")
        return False

    if _last_result_index + 1 >= len(_last_search_results):
        print("[player] no more alternatives from that search")
        return False

    _last_result_index += 1
    _navigate_to_result(_last_played_page, _last_result_index)
    print(f"[player] switched to alternative #{_last_result_index + 1}")
    return True


def pause_music():
    if _playback_mode == "local":
        local_player.pause_local()
        print("[player] paused (local)")
        return

    def _do_pause(page):
        page.bring_to_front()
        # evaluate() has no timeout parameter and can hang indefinitely
        # against a Memory-Saver-sleeping tab -- wait_for_function() does
        # the same one-shot side effect but is bounded, per the module's
        # Phase 18 hardening notes.
        page.wait_for_function(
            "() => { const v = document.querySelector('video'); "
            "if (v && !v.paused) v.pause(); return true; }",
            timeout=PAGE_ACTION_TIMEOUT_MS,
        )
        return True

    if _with_youtube_page(_do_pause):
        print("[player] paused (YouTube)")
        return

    print("[player] nothing actively tracked, falling back to system media key")
    media_keys.play_pause()


def resume_music():
    if _playback_mode == "local":
        local_player.resume_local()
        print("[player] resumed (local)")
        return

    def _do_resume(page):
        page.bring_to_front()
        page.wait_for_function(
            "() => { const v = document.querySelector('video'); "
            "if (v && v.paused) v.play(); return true; }",
            timeout=PAGE_ACTION_TIMEOUT_MS,
        )
        return True

    if _with_youtube_page(_do_resume):
        print("[player] resumed (YouTube)")
        return

    print("[player] nothing actively tracked, falling back to system media key")
    media_keys.play_pause()  # most keyboards only have one play/pause toggle key


def skip_music():
    global _queue_index

    # prefer advancing our own queue (playlist mode) if one exists
    if _queue and _queue_index + 1 < len(_queue):
        _queue_index += 1
        print(f"[player] queue: playing next ({_queue_index + 1}/{len(_queue)})")
        _play_resolved_song(_queue[_queue_index])
        return

    # no queue left to advance — fall back to per-source skip behavior
    if _playback_mode == "local":
        print("[player] end of queue, nothing more to skip to locally")
        return

    def _do_skip(page):
        page.bring_to_front()
        page.keyboard.press("Shift+N")  # YouTube's own "up next" shortcut
        return True

    if _with_youtube_page(_do_skip):
        print("[player] skipped to next (YouTube up-next)")
        return

    print("[player] nothing actively tracked, falling back to system media key")
    media_keys.next_track()


def adjust_volume(direction: str):
    """direction: 'up' or 'down'"""
    if _playback_mode == "local":
        new_volume = local_player.change_volume(direction)
        print(f"[player] local volume now {new_volume:.0%}")
        return

    def _do_adjust(page):
        page.bring_to_front()
        delta = 0.1 if direction == "up" else -0.1
        page.wait_for_function(
            "(delta) => { const v = document.querySelector('video'); "
            "if (v) v.volume = Math.max(0, Math.min(1, v.volume + delta)); return true; }",
            arg=delta,
            timeout=PAGE_ACTION_TIMEOUT_MS,
        )
        return True

    if _with_youtube_page(_do_adjust):
        print(f"[player] YouTube volume adjusted {direction}")
        return

    print("[player] nothing actively tracked, falling back to system media key")
    if direction == "up":
        media_keys.volume_up()
    else:
        media_keys.volume_down()


def get_now_playing():
    if _playback_mode == "local":
        return local_player.current_track_name()

    def _do_get_title(page):
        return page.title()

    title = _with_youtube_page(_do_get_title)
    if title is not None:
        return title.replace(" - YouTube", "").strip()

    return None
