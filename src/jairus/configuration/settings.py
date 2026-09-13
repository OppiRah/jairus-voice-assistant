"""Runtime configuration, file-backed since Phase 6 (UI).

JAIRUS_ARCHITECTURE.md Part 12 (Repository / Codebase Architecture) reserves
``src/jairus/configuration/`` for exactly this: values every layer may need
that aren't domain models or behaviour. Phase 13 (Android Gateway) was the
first consumer, with three plain module-level constants (GATEWAY_HOST,
GATEWAY_PORT, ANDROID_PAIRING_CODE).

Phase 6 (UI) extends this SAME module into a small file-backed settings
system rather than creating a second, competing config mechanism — see
SETTINGS_SYSTEM.md for the full reasoning on which project-wide constants
became config-file-backed here (and which were deliberately left as plain
code constants). In short: this module is now the one place that reads/
writes ``jairus_config.json`` at the repo root (gitignored — it can hold a
personal pairing code and a personal folder path), with defaults that
exactly match every value that was hardcoded before this phase existed. A
missing or partial config file produces byte-for-byte the same behavior as
before Phase 6.

``get(key)`` / ``save(updates)`` are the primary API, used directly by
assistant_loop.py, transcribe.py, and local_library.py (top-level scripts
outside the ``jairus`` package, which already import from here via the
same ``sys.path`` bootstrap they use for other ``jairus.*`` imports).
``GATEWAY_HOST`` / ``GATEWAY_PORT`` / ``ANDROID_PAIRING_CODE`` /
``PROTOCOL_VERSION`` stay available as plain module attributes for
backward compatibility with existing Phase 13 consumers
(run_gateway.py, gateway_server.py, protocol.py) — the first three now
resolve dynamically from the loaded config on every access (see
``__getattr__`` below), so a ``save()`` call is reflected immediately to
any code in the same process that reads them, with no caching to go stale.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

# src/jairus/configuration/settings.py -> src/jairus/configuration -> src/jairus -> src -> repo root
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
_CONFIG_PATH = _REPO_ROOT / "jairus_config.json"

# Every value here is IDENTICAL to what was hardcoded across the project
# before Phase 6 introduced jairus_config.json -- this is the single
# source of truth for "what happens with no config file present."
_DEFAULTS: dict[str, Any] = {
    "gateway_host": "0.0.0.0",
    "gateway_port": 8765,
    "android_pairing_code": "changeme-pairing-code",
    "wake_word_sensitivity": 0.5,   # assistant_loop.py's old DETECTION_THRESHOLD
    "whisper_model_size": "small",  # transcribe.py's old MODEL_SIZE
    "music_library_dir": None,      # local_library.py's old MUSIC_LIBRARY_DIR
    "music_match_threshold": 0.55,  # local_library.py's old MATCH_THRESHOLD
}

# JAIRUS_ARCHITECTURE.md Part 13.2 -- every message envelope carries this so
# a future protocol change doesn't silently break an older client. Not a
# user-facing setting, so it isn't part of jairus_config.json.
PROTOCOL_VERSION = "1"


def _load_config_file() -> dict[str, Any]:
    if not _CONFIG_PATH.exists():
        return {}
    try:
        with open(_CONFIG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


_config: dict[str, Any] = {**_DEFAULTS, **_load_config_file()}


def get(key: str) -> Any:
    """Returns one setting's current value: the config-file value if
    present, otherwise the hardcoded default (identical to this project's
    pre-Phase-6 behavior)."""
    return _config.get(key, _DEFAULTS.get(key))


def all_settings() -> dict[str, Any]:
    """Returns every setting's current value, for the Settings page to
    populate its fields from."""
    return dict(_config)


def save(updates: dict[str, Any]) -> None:
    """Merges `updates` into the current settings and writes the complete
    set back to jairus_config.json. Persisting is immediate; whether a
    given setting takes effect immediately or needs a restart depends on
    how/when the consuming code reads it -- see SETTINGS_SYSTEM.md and
    SettingsPage's own per-field notes.
    """
    _config.update(updates)
    with open(_CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(_config, f, indent=2)


_GATEWAY_ATTR_KEYS = {
    "GATEWAY_HOST": "gateway_host",
    "GATEWAY_PORT": "gateway_port",
    "ANDROID_PAIRING_CODE": "android_pairing_code",
}


def __getattr__(name: str) -> Any:
    # PEP 562 module __getattr__: keeps settings.GATEWAY_HOST etc. working
    # as plain attributes for existing Phase 13 consumers, but resolved
    # fresh from _config on every access instead of frozen at import time.
    if name in _GATEWAY_ATTR_KEYS:
        return get(_GATEWAY_ATTR_KEYS[name])
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
