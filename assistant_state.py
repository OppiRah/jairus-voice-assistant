"""
assistant_state.py — thread-safe shared state between the voice assistant
logic (runs in a background thread) and the Qt UI (runs on the main thread's
render loop). This is how the UI knows what the assistant is currently doing,
what it most recently said/did, and a bounded history of recent activity.
"""

import threading
import time
from collections import deque
from enum import StrEnum

HISTORY_MAXLEN = 20


class AssistantStatus(StrEnum):
    """The assistant's status vocabulary -- a real enum (not bare strings),
    expanded from the original 4 values toward UI_UX_CONTEXT.md's target
    model. See ASSISTANT_STATUS_MODEL.md for the full investigation this
    was built from: which states have a real trigger point in the live
    handle_command()/assistant_loop.py code path today, which don't, and
    why SPEAKING (not in the originally-requested 8) and OFFLINE (derived
    from Phase 3's health signals rather than its own trigger) are handled
    the way they are.

    Members are plain strings under the hood (StrEnum), so every existing
    caller that already passes a raw string (tts.py's
    `state.set_status("speaking")`, in particular) keeps working
    unchanged -- AssistantStatus.SPEAKING == "speaking" is True.
    """

    IDLE = "idle"
    LISTENING = "listening"
    THINKING = "thinking"
    SPEAKING = "speaking"                          # real, existing (tts.py) -- kept as its own value, see report/doc
    EXECUTING = "executing"                        # real trigger: handle_command()'s action-performing calls
    WAITING_CONFIRMATION = "waiting_confirmation"  # vocabulary only -- no real trigger exists yet (Policy Engine is shadow-only)
    COMPLETED = "completed"                        # real trigger: end of a successful handle_command() run
    ERROR = "error"                                # real trigger: handle_command()'s existing except block
    OFFLINE = "offline"                            # derived from mic_active, not its own set_status() call -- see get_snapshot()


class AssistantState:
    def __init__(self):
        self._lock = threading.Lock()
        self._status = AssistantStatus.IDLE
        self._level = 0.0       # 0.0-1.0, drives how much the orb pulses
        self._current_activity = "Idle"
        self._history = deque(maxlen=HISTORY_MAXLEN)
        self._model_loaded = False    # wake-word model finished loading
        self._mic_active = False      # mic input stream is open and running
        self._ollama_reachable = True  # optimistic until the first health check completes

    def set_status(self, status):
        with self._lock:
            self._status = status

    def set_level(self, level: float):
        with self._lock:
            self._level = max(0.0, min(1.0, level))

    def set_current_activity(self, text: str):
        with self._lock:
            self._current_activity = text

    def add_history_entry(self, text: str, action_type: str = "unknown"):
        with self._lock:
            self._history.append({
                "text": text,
                "timestamp": time.strftime("%H:%M:%S"),
                "action_type": action_type,
            })

    def get_snapshot(self):
        """Returns (status, level). OFFLINE is derived here, not set via
        set_status(): if the mic stream isn't active, the real-time loop
        genuinely isn't running (still starting up, or the assistant
        thread crashed/exited) -- OFFLINE is a more honest description of
        that than whatever `_status` happens to still hold from before,
        and it reuses the exact signal Phase 3 already tracks for this
        (`_mic_active`) instead of a second, disconnected way of saying
        the same thing.
        """
        with self._lock:
            if not self._mic_active:
                return AssistantStatus.OFFLINE, self._level
            return self._status, self._level

    def get_activity_snapshot(self):
        with self._lock:
            return self._current_activity, list(self._history)

    def set_model_loaded(self, loaded: bool):
        with self._lock:
            self._model_loaded = loaded

    def set_mic_active(self, active: bool):
        with self._lock:
            self._mic_active = active

    def set_ollama_reachable(self, reachable: bool):
        with self._lock:
            self._ollama_reachable = reachable

    def get_health_status(self) -> str:
        """One of "starting" / "ollama_unavailable" / "healthy" — a single,
        honest summary of backend health for the UI. Not a network
        connection state (this process isn't networked to anything) --
        just whether the things the assistant actually depends on
        (wake-word model, mic stream, local Ollama) are currently working.
        """
        with self._lock:
            if not (self._model_loaded and self._mic_active):
                return "starting"
            if not self._ollama_reachable:
                return "ollama_unavailable"
            return "healthy"
