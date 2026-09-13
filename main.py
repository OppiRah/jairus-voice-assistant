"""
main.py — entry point. Starts the orb UI on the main thread and the voice
assistant logic on a background thread, sharing state between them.

Renderer selection (ORB_RENDERER_INVESTIGATION.md section 6): reads
jairus.configuration.settings' "renderer_mode" ("qt_orb" | "godot"). The
default, "qt_orb", requires no configuration and is byte-for-byte the
same behavior this project has always had -- the existing QPainter-based
OrbWidget never goes away and is not being replaced, only supplemented.
"godot" attempts to launch the validated Godot renderer
(src/jairus/interfaces/renderer/godot_project/) as a supervised
subprocess; if that's misconfigured, missing, or fails to actually start,
this falls back to "qt_orb" automatically rather than leaving the person
with no orb at all.

Run:  python main.py
Stop: close the orb window (or Ctrl+C in the terminal)
"""

import os
import subprocess
import sys
import threading
import time

from assistant_state import AssistantState
from assistant_loop import run_assistant
from orb_widget import run_orb

_SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from jairus.configuration import settings
from jairus.interfaces.renderer.bridge import start_bridge_thread

_GODOT_PROJECT_PATH = os.path.join(_SRC_DIR, "jairus", "interfaces", "renderer", "godot_project")

# How long to wait after launching Godot before checking whether it's
# still running. Popen() succeeding only means the OS accepted the
# request to start a process -- it says nothing about whether Godot
# itself then failed (bad project path, missing GPU driver, etc.) and
# exited immediately after. This brief pause turns "did launch actually
# work" into a real, checkable question via proc.poll().
_LAUNCH_CHECK_DELAY_SECONDS = 1.5


def _try_launch_godot():
    """Attempts to launch the Godot renderer as a subprocess. Returns the
    Popen handle if it's genuinely still running after a brief check, or
    None if renderer_mode isn't "godot", the configured executable is
    missing/invalid, or the process exited almost immediately (a real,
    checked launch failure, not just trusting Popen() not raising).
    """
    exe_path = settings.get("godot_executable_path")
    if not exe_path or not os.path.isfile(exe_path):
        print(f"[main] renderer_mode is 'godot' but godot_executable_path is unset/invalid ({exe_path!r}); "
              "falling back to the built-in orb")
        return None

    try:
        proc = subprocess.Popen([exe_path, "--path", _GODOT_PROJECT_PATH])
    except OSError as e:
        print(f"[main] failed to launch Godot ({e}); falling back to the built-in orb")
        return None

    time.sleep(_LAUNCH_CHECK_DELAY_SECONDS)
    if proc.poll() is not None:
        print(f"[main] Godot exited immediately (code {proc.returncode}); falling back to the built-in orb")
        return None

    print(f"[main] Godot renderer launched (pid {proc.pid})")
    return proc


def main():
    state = AssistantState()

    assistant_thread = threading.Thread(target=run_assistant, args=(state,), daemon=True)
    assistant_thread.start()

    godot_process = None
    if settings.get("renderer_mode") == "godot":
        godot_process = _try_launch_godot()
        if godot_process is not None:
            start_bridge_thread(state)

    run_orb(state, godot_process=godot_process)  # blocks on the main thread until the window is closed


if __name__ == "__main__":
    main()
