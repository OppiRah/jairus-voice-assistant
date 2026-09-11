"""Windows UI Automation — semantic control finding/interaction.

JAIRUS_ARCHITECTURE.md Part 14.11 (migration Phase 9), Part 20 (Windows
Automation — "Windows UI Automation should provide semantic interaction...
Coordinate-based raw input should not be a general-purpose LLM tool in
V1"), Part 19 (automation backend hierarchy: Native API > Windows UI
Automation > browser DOM/CDP > input simulation > vision — vision "remains
later"), and Part 23 (capability catalog).

Backend per function, per Part 19's hierarchy:

- ``get_active_window`` / ``list_windows``: plain ``win32gui`` +
  ``win32process`` + ``psutil`` — the same combination Phase 7's
  ``apps.py`` already uses for window/process introspection. These are
  just window enumeration; no semantic control interaction is needed, so
  the plainest native API does the job (Part 19's own preference order).
- ``find_control`` / ``invoke_control`` / ``type_into_control`` /
  ``send_hotkey``: ``pywinauto``'s UI Automation backend (``"uia"``) —
  genuine semantic interaction with named controls (buttons, text fields,
  menu items), identified by name/control_type, not screen position. This
  is exactly what Part 20 asks for, and what ``pywin32`` alone cannot
  provide: pywin32 gives raw window-handle/message-level access, not a
  semantic accessibility tree. See the dependency note in
  WINDOWS_UI_TOOLS.md for why ``pywinauto`` specifically.

Every control-targeting function here re-locates its target fresh from
``(window_title, control_name, control_type)`` (or just ``window_title``
for ``send_hotkey``) on every call. No live pywinauto object is ever held
between separate tool calls — tool calls are stateless, discrete actions
(this phase's own scope rule, and the architecture's ToolCall model): "act
on this named control in this named window, right now," never "reuse what
an earlier find_control call happened to return."

Deliberately NOT implemented here, on purpose, not by oversight:

- **Coordinate/pixel clicking, anywhere, not even as a fallback.** If a
  control can't be located semantically, every function below reports that
  plainly (``found: False`` / returns ``False``) — it never guesses a
  screen position instead. (``invoke_control`` can fall back from
  pywinauto's semantic ``Invoke`` pattern to pywinauto's own
  ``click_input()`` when a *found* control doesn't support ``Invoke`` —
  that still targets the specific control's own on-screen rectangle as
  reported by UI Automation, not an arbitrary/guessed coordinate; it only
  ever runs against a control this module already successfully located.)
- **Vision-based automation** (screenshots, image matching) — a later
  phase per Part 19's own hierarchy ("Vision remains later").
- **Multi-step workflows.** Each function here is one discrete action.
  There is no "open this menu, then click that item" composite behavior
  anywhere in this module.
"""

from __future__ import annotations

import re
import time
from typing import Any

import psutil
import win32gui
import win32process
from pywinauto import Desktop
from pywinauto.findwindows import ElementNotFoundError

CONTROL_TIMEOUT_SECONDS = 8
_RETRY_INTERVAL_SECONDS = 0.5


def _process_name(pid: int) -> str | None:
    try:
        return psutil.Process(pid).name()
    except psutil.Error:
        return None


def get_active_window() -> dict[str, Any]:
    """Returns ``{title, process_name}`` for the current foreground
    window, or ``{title: None, process_name: None}`` if there isn't one."""
    hwnd = win32gui.GetForegroundWindow()
    if not hwnd:
        return {"title": None, "process_name": None}
    title = win32gui.GetWindowText(hwnd) or None
    _, pid = win32process.GetWindowThreadProcessId(hwnd)
    return {"title": title, "process_name": _process_name(pid)}


def list_windows() -> list[dict[str, Any]]:
    """Returns ``{title, process_name}`` for every visible, titled
    top-level window."""
    windows: list[dict[str, Any]] = []

    def _visit(hwnd, _extra):
        if not win32gui.IsWindowVisible(hwnd):
            return
        title = win32gui.GetWindowText(hwnd)
        if not title:
            return
        _, pid = win32process.GetWindowThreadProcessId(hwnd)
        windows.append({"title": title, "process_name": _process_name(pid)})

    win32gui.EnumWindows(_visit, None)
    return windows


def _retry_until_found(attempt, timeout=CONTROL_TIMEOUT_SECONDS, interval=_RETRY_INTERVAL_SECONDS):
    """Retries ``attempt()`` (expected to return a list) until it's
    non-empty or ``timeout`` elapses — gives a freshly-launched
    application's UI Automation tree a bounded window to settle in,
    without an indefinite wait."""
    deadline = time.time() + timeout
    result = attempt()
    while not result and time.time() < deadline:
        time.sleep(interval)
        result = attempt()
    return result


def _locate_window(window_title: str):
    """Finds the first VISIBLE top-level window whose title contains
    ``window_title`` (case-insensitive substring match). Raises
    ``ElementNotFoundError`` if none match within the retry window.

    Deliberately resolves through an already-filtered, concrete
    ``visible_only=True`` list rather than a single lazy
    ``Desktop().window(title=...)`` lookup — a real flakiness surfaced
    during testing: a bare title-based lookup can intermittently fail to
    resolve when more than one window shares the same title (e.g. two
    Calculator windows, one minimized), even though the target genuinely
    exists. ``visible_only=True`` excludes the minimized/offscreen one and
    resolves this deterministically instead of racing pywinauto's own
    default disambiguation."""

    def attempt():
        return Desktop(backend="uia").windows(
            title_re=f"(?i).*{re.escape(window_title)}.*", visible_only=True
        )

    matches = _retry_until_found(attempt)
    if not matches:
        raise ElementNotFoundError({"title_re": window_title})
    return matches[0]


def _locate_control(window_title: str, control_name: str, control_type: str | None):
    """Re-locates a control fresh, by name (and optional control type)
    within a freshly-located window. Raises ``ElementNotFoundError`` if
    nothing matches within the retry window."""
    window = _locate_window(window_title)
    kwargs: dict[str, Any] = {"title": control_name}
    if control_type:
        kwargs["control_type"] = control_type

    def attempt():
        return window.descendants(**kwargs)

    matches = _retry_until_found(attempt)
    if not matches:
        raise ElementNotFoundError({"title": control_name, "control_type": control_type})
    return matches[0]


def find_control(window_title: str, control_name: str, control_type: str | None = None) -> dict[str, Any]:
    """Looks for a named control inside a named window. This is a lookup,
    not an action — "not there" is a normal, reportable outcome, not an
    error, so it returns ``{"found": False}`` rather than raising.

    ``value`` (when the control exposes UI Automation's Value pattern,
    e.g. an ``Edit`` box) is included separately from ``name``
    deliberately: for many native Windows controls the accessible "Name"
    is a static label (an ``Edit`` box named "Open:" stays named "Open:"
    no matter what's typed into it) while ``value`` is the control's
    actual current content — the only way to verify, through this
    function alone, that a ``windows.type`` call actually landed."""
    try:
        element = _locate_control(window_title, control_name, control_type)
    except ElementNotFoundError:
        return {"found": False}

    try:
        value = element.get_value() if hasattr(element, "get_value") else None
    except Exception:
        value = None

    return {
        "found": True,
        "name": element.window_text(),
        "control_type": element.element_info.control_type,
        "automation_id": element.element_info.automation_id,
        "is_enabled": element.is_enabled(),
        "is_visible": element.is_visible(),
        "value": value,
    }


def invoke_control(window_title: str, control_name: str, control_type: str | None = None) -> bool:
    """Re-locates the control fresh (same identifying params as
    ``find_control``) and invokes it semantically: pywinauto's own
    ``Invoke`` UI Automation pattern where the control supports it, its
    ``click_input()`` (still targeting that control's own on-screen
    rectangle, never an arbitrary coordinate) otherwise. Returns ``False``
    — never raises, never falls back to guessing a screen position — if
    the control can't be found or is disabled."""
    try:
        element = _locate_control(window_title, control_name, control_type)
    except ElementNotFoundError:
        print(f"[windows] control '{control_name}' not found in '{window_title}'")
        return False

    if not element.is_enabled():
        print(f"[windows] control '{control_name}' is disabled, not invoking")
        return False

    print(f"[windows] invoking '{control_name}' in '{window_title}'")
    if hasattr(element, "invoke"):
        element.invoke()
    else:
        element.click_input()
    return True


def type_into_control(
    window_title: str, control_name: str, text: str, control_type: str | None = None
) -> bool:
    """Re-locates the control fresh and types ``text`` into it via
    pywinauto's own keyboard-simulation ``type_keys()`` after focusing the
    control semantically — never simulated mouse coordinates. Returns
    ``False`` if the control can't be found or is disabled."""
    try:
        element = _locate_control(window_title, control_name, control_type)
    except ElementNotFoundError:
        print(f"[windows] control '{control_name}' not found in '{window_title}'")
        return False

    if not element.is_enabled():
        print(f"[windows] control '{control_name}' is disabled, not typing into it")
        return False

    print(f"[windows] typing into '{control_name}' in '{window_title}'")
    try:
        element.set_focus()
    except Exception:
        pass  # not every control type needs/supports an explicit focus call
    element.type_keys(text, with_spaces=True)
    return True


def send_hotkey(window_title: str, keys: str) -> bool:
    """Focuses the named window, then sends a keyboard shortcut using
    pywinauto's ``send_keys`` syntax (e.g. ``"^s"`` for Ctrl+S, ``"{ESC}"``
    for Escape). Returns ``False`` if the window can't be found."""
    try:
        window = _locate_window(window_title)
    except ElementNotFoundError:
        print(f"[windows] window '{window_title}' not found")
        return False

    print(f"[windows] sending hotkey '{keys}' to '{window_title}'")
    window.set_focus()
    window.type_keys(keys)
    return True
