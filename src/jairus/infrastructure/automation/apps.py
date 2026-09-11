"""Windows application control — launch, close, focus, detect, list.

JAIRUS_ARCHITECTURE.md Part 14.9 (migration Phase 7), Part 19 (automation
backend hierarchy — prefer native OS APIs over anything fancier), Part 23
(capability catalog — application control), and Part 25 (permission
examples: "launch application" is Level 0, "close application" is Level 1).

Unlike the media tools (Phases 5-6), which wrapped EXISTING code in
``player_action.py``, there is no existing app-control code anywhere in
this repo — every function here is new. Per Part 19's hierarchy, each one
uses the plainest native API that does the job, nothing fancier:

- ``launch_app``: ``os.startfile`` (the same mechanism as double-clicking
  something in Explorer — resolves a bare name like ``"notepad.exe"``
  through PATH/App Paths as well as accepting a full path).
- ``close_app`` / ``detect_app`` / ``list_running_apps``: ``psutil``, for
  process enumeration and a graceful ``terminate()`` (not a hard kill).
- ``focus_app``: ``pywin32`` (already a dependency, used by ``pyttsx3``)
  to find a process's visible top-level window and bring it to the
  foreground — including the standard synthetic-key-tap workaround for
  Windows' own restriction on ``SetForegroundWindow`` from a background
  process (see ``_set_foreground``).

Deliberately NOT built here: Windows UI Automation — finding controls
inside a window, typing into fields, clicking buttons. That is Phase 9's
job (a separate, later piece of work); these functions only launch, close,
focus, and detect whole applications as black boxes.
"""

from __future__ import annotations

import os

import psutil
import win32api
import win32con
import win32gui
import win32process


def launch_app(path_or_name: str) -> bool:
    """Launches an application, by full path or by a name Windows can
    resolve (e.g. ``"notepad.exe"``). Returns ``True`` if the launch call
    itself succeeded, ``False`` if it raised."""
    print(f"[apps] launching '{path_or_name}'")
    try:
        os.startfile(path_or_name)
        return True
    except OSError as e:
        print(f"[apps] launch failed: {e}")
        return False


def _matching_processes(process_name: str) -> list[psutil.Process]:
    target = process_name.lower()
    return [
        proc
        for proc in psutil.process_iter(["pid", "name"])
        if (proc.info["name"] or "").lower() == target
    ]


def close_app(process_name: str) -> bool:
    """Gracefully terminates every running process named ``process_name``
    (e.g. ``"notepad.exe"``), via ``psutil``'s ``terminate()`` — a normal
    close request, not a forced kill. Returns ``True`` only if at least one
    matching process was found and all matches actually exited within the
    wait; ``False`` if none were running, or if one or more failed to exit
    (e.g. access denied, or it ignored the close request)."""
    print(f"[apps] closing '{process_name}'")
    matches = _matching_processes(process_name)
    if not matches:
        print(f"[apps] no running process named '{process_name}'")
        return False

    for proc in matches:
        try:
            proc.terminate()
        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied as e:
            print(f"[apps] access denied terminating pid {proc.pid}: {e}")

    _, still_alive = psutil.wait_procs(matches, timeout=5)
    if still_alive:
        print(f"[apps] {len(still_alive)} process(es) of '{process_name}' still running after close")
        return False
    return True


def detect_app(process_name: str) -> bool:
    """Returns ``True`` if any process named ``process_name`` is currently
    running."""
    return len(_matching_processes(process_name)) > 0


def list_running_apps() -> list[str]:
    """Returns the distinct process names currently running, sorted."""
    names = {
        proc.info["name"]
        for proc in psutil.process_iter(["name"])
        if proc.info["name"]
    }
    return sorted(names)


def focus_app(process_name: str) -> bool:
    """Brings a running application's window to the foreground.

    Finds the process(es) named ``process_name``, then enumerates
    top-level windows for one that is visible, has a title, and belongs to
    one of those processes. Returns ``True`` if such a window was found
    and successfully restored/foregrounded; ``False`` if the process isn't
    running or has no visible window. See ``_set_foreground`` for how the
    foreground switch itself is made reliable from a background process."""
    print(f"[apps] focusing '{process_name}'")
    target_pids = {proc.pid for proc in _matching_processes(process_name)}
    if not target_pids:
        print(f"[apps] no running process named '{process_name}'")
        return False

    found_hwnd = None

    def _visit(hwnd, _extra):
        nonlocal found_hwnd
        if found_hwnd is not None:
            return
        if not win32gui.IsWindowVisible(hwnd) or not win32gui.GetWindowText(hwnd):
            return
        _, pid = win32process.GetWindowThreadProcessId(hwnd)
        if pid in target_pids:
            found_hwnd = hwnd

    win32gui.EnumWindows(_visit, None)

    if found_hwnd is None:
        print(f"[apps] no visible window found for '{process_name}'")
        return False

    try:
        win32gui.ShowWindow(found_hwnd, win32con.SW_RESTORE)
        _set_foreground(found_hwnd)
        return True
    except Exception as e:
        print(f"[apps] focus failed: {e}")
        return False


def _set_foreground(hwnd) -> None:
    """Brings ``hwnd`` to the foreground, working around Windows' own
    restriction on ``SetForegroundWindow``: by default it silently refuses a
    foreground request from a process (like this one, run from a terminal)
    that isn't itself the current foreground process, unless that process
    can show it just received user input. The standard native-API
    workaround — still just ``win32api``/``win32gui``, no UI Automation
    involved — is to synthesize a harmless key tap (Alt, released
    immediately) first, which satisfies that check, then call
    ``SetForegroundWindow`` normally."""
    win32api.keybd_event(win32con.VK_MENU, 0, 0, 0)
    win32api.keybd_event(win32con.VK_MENU, 0, win32con.KEYEVENTF_KEYUP, 0)
    win32gui.SetForegroundWindow(hwnd)
