"""
local_library.py — indexes a local music folder and fuzzy-matches spoken
song/artist requests against filenames, so local files play instead of
falling back to YouTube when you already have them.

Set your music folder via Settings in the app (Music Library, Phase 6 UI),
or by hand in jairus_config.json ("music_library_dir"). Leave it unset
(the default) to disable local library lookup entirely -- nothing changes
vs. YouTube-only behavior until you set this.
"""

import os
import sys
from pathlib import Path
from difflib import SequenceMatcher

_SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from jairus.configuration import settings

# Set your music folder via Settings in the app (Phase 6, UI), or by hand in
# jairus_config.json. Read once at import: changing it needs a restart,
# since the index below is only ever built once per process.
MUSIC_LIBRARY_DIR = settings.get("music_library_dir")

AUDIO_EXTENSIONS = {".mp3", ".flac", ".wav", ".m4a", ".ogg"}

_index = None  # list of Path objects, built lazily on first use


def _build_index():
    global _index
    _index = []
    if not MUSIC_LIBRARY_DIR:
        return

    root = Path(MUSIC_LIBRARY_DIR)
    if not root.exists():
        print(f"[local_library] configured folder doesn't exist: {root}")
        return

    for path in root.rglob("*"):
        if path.suffix.lower() in AUDIO_EXTENSIONS:
            _index.append(path)
    print(f"[local_library] indexed {len(_index)} local tracks")


def _similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def find_local_match(title: str, artist: str = ""):
    """Returns a matching Path if a local file looks like a good fit, else None."""
    global _index
    if _index is None:
        _build_index()
    if not _index:
        return None

    query = f"{title} {artist}".strip().lower()
    if not query:
        return None

    best_path = None
    best_score = 0.0
    for path in _index:
        score = _similarity(query, path.stem)
        if score > best_score:
            best_score = score
            best_path = path

    # Read fresh each call (Phase 6, UI): unlike MUSIC_LIBRARY_DIR above,
    # this doesn't depend on any cached index, so a Settings change applies
    # immediately, no restart needed.
    if best_path and best_score >= settings.get("music_match_threshold"):
        print(f"[local_library] matched '{query}' -> {best_path.name} (score={best_score:.2f})")
        return best_path

    return None
