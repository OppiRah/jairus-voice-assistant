"""
assistant_state.py — thread-safe shared state between the voice assistant
logic (runs in a background thread) and the Qt UI (runs on the main thread's
render loop). This is how the UI knows what the assistant is currently doing,
what it most recently said/did, and a bounded history of recent activity.
"""

import threading
import time
from collections import deque

HISTORY_MAXLEN = 20


class AssistantState:
    def __init__(self):
        self._lock = threading.Lock()
        self._status = "idle"   # idle | listening | thinking | speaking
        self._level = 0.0       # 0.0-1.0, drives how much the orb pulses
        self._current_activity = "Idle"
        self._history = deque(maxlen=HISTORY_MAXLEN)
        self._model_loaded = False    # wake-word model finished loading
        self._mic_active = False      # mic input stream is open and running
        self._ollama_reachable = True  # optimistic until the first health check completes

    def set_status(self, status: str):
        with self._lock:
            self._status = status

    def set_level(self, level: float):
        with self._lock:
            self._level = max(0.0, min(1.0, level))

    def set_current_activity(self, text: str):
        with self._lock:
            self._current_activity = text

    def add_history_entry(self, text: str):
        with self._lock:
            self._history.append({"text": text, "timestamp": time.strftime("%H:%M:%S")})

    def get_snapshot(self):
        with self._lock:
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
