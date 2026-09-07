"""
local_player.py — plays local audio files (mp3/flac/wav/etc.) using pygame's
mixer. Runs fully offline, keeps its own play/pause/volume state independent
of the browser.
"""

import pygame
from pathlib import Path

_current_track = None  # Path of the currently loaded track
_volume = 0.7


def _ensure_init():
    if not pygame.mixer.get_init():
        pygame.mixer.init()


def play_local(path):
    global _current_track
    _ensure_init()
    pygame.mixer.music.load(str(path))
    pygame.mixer.music.set_volume(_volume)
    pygame.mixer.music.play()
    _current_track = Path(path)


def pause_local():
    _ensure_init()
    pygame.mixer.music.pause()


def resume_local():
    _ensure_init()
    pygame.mixer.music.unpause()


def stop_local():
    global _current_track
    _ensure_init()
    pygame.mixer.music.stop()
    _current_track = None


def change_volume(direction: str, step: float = 0.1) -> float:
    global _volume
    _ensure_init()
    if direction == "up":
        _volume = min(1.0, _volume + step)
    else:
        _volume = max(0.0, _volume - step)
    pygame.mixer.music.set_volume(_volume)
    return _volume


def current_track_name():
    return _current_track.stem if _current_track else None
