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


# ---------- Brave / CDP plumbing ----------

def _get_browser():
    global _playwright, _browser

    if _browser is not None:
        try:
            _ = _browser.contexts
        except Exception:
            _playwright = None
            _browser = None

    if _browser is None:
        if _playwright is None:
            _playwright = sync_playwright().start()
        try:
            _browser = _playwright.chromium.connect_over_cdp(CDP_URL)
        except Exception as e:
            raise RuntimeError(
                "Couldn't connect to Brave. Make sure Brave is running with "
                "--remote-debugging-port=9222."
            ) from e

    return _browser


def _find_active_youtube_page():
    global _last_played_page

    if _last_played_page is not None:
        try:
            if "youtube.com/watch" in _last_played_page.url:
                return _last_played_page
        except Exception:
            _last_played_page = None

    try:
        browser = _get_browser()
        context = browser.contexts[0]
        for page in context.pages:
            try:
                if "youtube.com/watch" in page.url:
                    return page
            except Exception:
                continue
    except Exception:
        pass

    return None


def _navigate_to_result(page, index: int):
    global _last_played_page
    href = _last_search_results[index]
    url = href if href.startswith("http") else f"https://www.youtube.com{href}"
    page.goto(url, wait_until="domcontentloaded")
    _last_played_page = page


def _play_youtube(song: dict):
    global _last_search_results, _last_result_index, _playback_mode

    query = f"{song.get('title', '')} {song.get('artist', '')}".strip()
    print(f"[player] searching '{query}' on YouTube...")

    browser = _get_browser()
    context = browser.contexts[0]
    page = context.new_page()
    page.goto(SEARCH_URL.format(query=quote_plus(query)), wait_until="networkidle")

    page.wait_for_selector(FIRST_RESULT_SELECTOR, timeout=15000)
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

    page = _find_active_youtube_page()
    if page is not None:
        page.bring_to_front()
        page.evaluate("() => { const v = document.querySelector('video'); if (v && !v.paused) v.pause(); }")
        print("[player] paused (YouTube)")
        return

    print("[player] nothing actively tracked, falling back to system media key")
    media_keys.play_pause()


def resume_music():
    if _playback_mode == "local":
        local_player.resume_local()
        print("[player] resumed (local)")
        return

    page = _find_active_youtube_page()
    if page is not None:
        page.bring_to_front()
        page.evaluate("() => { const v = document.querySelector('video'); if (v && v.paused) v.play(); }")
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

    page = _find_active_youtube_page()
    if page is not None:
        page.bring_to_front()
        page.keyboard.press("Shift+N")  # YouTube's own "up next" shortcut
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

    page = _find_active_youtube_page()
    if page is not None:
        page.bring_to_front()
        delta = 0.1 if direction == "up" else -0.1
        page.evaluate(
            "(delta) => { const v = document.querySelector('video'); "
            "if (v) v.volume = Math.max(0, Math.min(1, v.volume + delta)); }",
            delta,
        )
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

    page = _find_active_youtube_page()
    if page is not None:
        try:
            title = page.title()
            return title.replace(" - YouTube", "").strip()
        except Exception:
            return None

    return None
