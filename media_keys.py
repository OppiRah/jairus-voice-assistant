"""
media_keys.py — fallback control via Windows' system media keys
(Play/Pause, Next Track, Volume Up/Down).

Used when there's no active YouTube tab or local track being tracked directly —
these are the same OS-level signals a keyboard's media keys send, so they
control whatever app currently holds the "now playing" session (browser,
Spotify, VLC, etc.). This is the same class of mechanism KDE Connect's phone
media controls tap into under the hood.

Windows only — uses ctypes to call the Win32 API directly, no extra installs.
"""

import ctypes

KEYEVENTF_KEYUP = 0x2
VK_MEDIA_PLAY_PAUSE = 0xB3
VK_MEDIA_NEXT_TRACK = 0xB0
VK_MEDIA_PREV_TRACK = 0xB1
VK_VOLUME_UP = 0xAF
VK_VOLUME_DOWN = 0xAE


def _press(vk_code):
    try:
        ctypes.windll.user32.keybd_event(vk_code, 0, 0, 0)
        ctypes.windll.user32.keybd_event(vk_code, 0, KEYEVENTF_KEYUP, 0)
    except AttributeError:
        print("[media_keys] not running on Windows, can't send system media keys")


def play_pause():
    _press(VK_MEDIA_PLAY_PAUSE)


def next_track():
    _press(VK_MEDIA_NEXT_TRACK)


def prev_track():
    _press(VK_MEDIA_PREV_TRACK)


def volume_up():
    _press(VK_VOLUME_UP)


def volume_down():
    _press(VK_VOLUME_DOWN)
