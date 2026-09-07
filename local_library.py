"""
local_library.py — indexes a local music folder and fuzzy-matches spoken
song/artist requests against filenames, so local files play instead of
falling back to YouTube when you already have them.

Configure MUSIC_LIBRARY_DIR below to point at your music folder. Leave it as
None (the default) to disable local library lookup entirely -- nothing
changes vs. YouTube-only behavior until you set this.
"""

from pathlib import Path
from difflib import SequenceMatcher

# Set this to your music folder to enable local library lookup, e.g.:
# MUSIC_LIBRARY_DIR = r"C:\Users\miscr\Music"
MUSIC_LIBRARY_DIR = None

AUDIO_EXTENSIONS = {".mp3", ".flac", ".wav", ".m4a", ".ogg"}
MATCH_THRESHOLD = 0.55  # how close a spoken request needs to be to a filename to count as a match

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

    if best_path and best_score >= MATCH_THRESHOLD:
        print(f"[local_library] matched '{query}' -> {best_path.name} (score={best_score:.2f})")
        return best_path

    return None
