"""CommandSource — where a command originated."""

from __future__ import annotations

from enum import Enum


class CommandSource(str, Enum):
    """The interface a command entered through.

    Input adapters normalise every interface down to one of these values so the
    Agent Core never has to care whether a request arrived by microphone, phone,
    or something added later (JAIRUS_ARCHITECTURE.md Part 8.1). Future adapters
    (Android voice, a desktop UI, an API client) get their own members here.
    """

    VOICE = "voice"
    ANDROID = "android"
