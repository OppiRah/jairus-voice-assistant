"""
tts.py — gives the assistant a voice using pyttsx3 (Windows SAPI5 under the hood).

Fully offline, no downloads, no API keys. Voice quality is the classic robotic
Windows voice, but it's instant and free.

If given an AssistantState, it also drives the orb UI: flips status to
"speaking" and feeds it a smoothed, randomized level for the duration of the
speech, so the orb visibly pulses while it talks (not literal waveform
analysis, just a convincing synced animation).
"""

import threading
import time
import random
import pyttsx3

_engine = None


def _get_engine():
    global _engine
    if _engine is None:
        _engine = pyttsx3.init()
        _engine.setProperty("rate", 175)  # slightly faster than default
    return _engine


def speak(text: str, state=None):
    if not text:
        return
    print(f"[voice] {text}")
    engine = _get_engine()

    stop_flag = threading.Event()

    def _animate():
        level = 0.0
        while not stop_flag.is_set():
            level = max(0.0, min(1.0, level + random.uniform(-0.35, 0.35)))
            if state:
                state.set_level(level)
            time.sleep(0.05)
        if state:
            state.set_level(0.0)

    animator = None
    if state:
        state.set_status("speaking")
        animator = threading.Thread(target=_animate, daemon=True)
        animator.start()

    engine.say(text)
    engine.runAndWait()

    if state:
        stop_flag.set()
        state.set_status("idle")
