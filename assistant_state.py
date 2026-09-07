"""
assistant_state.py — thread-safe shared state between the voice assistant
logic (runs in a background thread) and the orb UI (runs on the main thread's
render loop). This is how the orb knows what the assistant is currently doing.
"""

import threading


class AssistantState:
    def __init__(self):
        self._lock = threading.Lock()
        self._status = "idle"   # idle | listening | thinking | speaking
        self._level = 0.0       # 0.0-1.0, drives how much the orb pulses

    def set_status(self, status: str):
        with self._lock:
            self._status = status

    def set_level(self, level: float):
        with self._lock:
            self._level = max(0.0, min(1.0, level))

    def get_snapshot(self):
        with self._lock:
            return self._status, self._level
