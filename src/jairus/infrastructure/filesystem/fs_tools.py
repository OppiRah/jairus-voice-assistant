"""Read-only filesystem access — search, list, read, exists.

JAIRUS_ARCHITECTURE.md Part 14.18 (migration Phase 16), Part 15.9 ("V1
Filesystem" — read-only: search/list/read/exists, "no deletion yet"), and
Part 23 (capability catalog).

Per Part 14.18's own sequencing — "Start read-only... Then eventually
filesystem.create/modify/move/delete with increasingly strict policy" —
this module contains ZERO functions capable of writing, deleting, moving,
or otherwise mutating anything on disk, including as unregistered/unused
helpers. That is a harder boundary than prior phases' "don't wire it up
yet": there is no code path here that could mutate the filesystem, period.
Write/delete/move belongs entirely to a later phase, "with increasingly
strict policy" applied from the start.

Every function validates its input before acting and returns a clean
failure value (``[]``, ``None``, or ``False``) for a missing/invalid path
rather than letting a ``FileNotFoundError``/``PermissionError``/etc.
propagate — same discipline ``apps.py`` uses (e.g. ``close_app`` returning
``False`` for "nothing to close" instead of raising).
"""

from __future__ import annotations

from pathlib import Path

# Bounds two different failure modes of an unrestricted glob:
# 1. A recursive ("**") pattern rooted at a filesystem root (e.g. "C:\") would
#    walk the entire drive -- rejected outright below, not just truncated.
# 2. A very broad but non-root recursive search could still legitimately
#    match huge numbers of files -- capped here so a single tool call can't
#    return an unbounded result set.
MAX_SEARCH_RESULTS = 1000


def _resolve_existing_dir(directory: str) -> Path | None:
    try:
        path = Path(directory).resolve()
    except (OSError, ValueError):
        return None
    if not path.is_dir():
        return None
    return path


def search_files(directory: str, pattern: str) -> list[str]:
    """Returns paths (as strings) under ``directory`` matching a glob-style
    ``pattern`` (e.g. ``"*.py"``, or ``"**/*.py"`` for recursive), sorted.

    Returns ``[]`` if ``directory`` doesn't exist or isn't a directory, or
    if the pattern is rejected as obviously pathological (a recursive
    pattern rooted at a filesystem root, e.g. searching ``"**/*"`` under
    ``"C:\\"``) — reflected as a printed warning, not an exception. Results
    are capped at ``MAX_SEARCH_RESULTS``.
    """
    base = _resolve_existing_dir(directory)
    if base is None:
        print(f"[fs] '{directory}' is not an existing directory")
        return []

    is_recursive = "**" in pattern
    is_drive_root = base.parent == base  # e.g. Path("C:\\").resolve().parent == itself
    if is_recursive and is_drive_root:
        print(f"[fs] refusing recursive search '{pattern}' rooted at filesystem root '{base}'")
        return []

    print(f"[fs] searching '{base}' for pattern '{pattern}'")
    try:
        matches = []
        for match in base.glob(pattern):
            matches.append(str(match))
            if len(matches) >= MAX_SEARCH_RESULTS:
                print(f"[fs] search capped at {MAX_SEARCH_RESULTS} results")
                break
        return sorted(matches)
    except (OSError, ValueError) as e:
        print(f"[fs] search failed: {e}")
        return []


def list_directory(path: str) -> list[dict]:
    """Lists the immediate (non-recursive) contents of ``path``: for each
    entry, ``{"name": ..., "is_dir": ..., "size": ...}``. A directory
    entry's own ``size`` is reported as ``0`` — this never recurses into
    subdirectories to compute a total. Returns ``[]`` if ``path`` doesn't
    exist or isn't a directory. An entry this process can't ``stat()``
    (e.g. permission denied, or removed mid-listing) is skipped rather than
    aborting the whole listing."""
    base = _resolve_existing_dir(path)
    if base is None:
        print(f"[fs] '{path}' is not an existing directory")
        return []

    print(f"[fs] listing '{base}'")
    entries = []
    try:
        children = list(base.iterdir())
    except OSError as e:
        print(f"[fs] listing failed: {e}")
        return []

    for child in children:
        try:
            is_dir = child.is_dir()
            size = 0 if is_dir else child.stat().st_size
        except OSError:
            continue
        entries.append({"name": child.name, "is_dir": is_dir, "size": size})

    return sorted(entries, key=lambda e: e["name"].lower())


def read_file(path: str, max_bytes: int = 100_000) -> str | None:
    """Reads at most ``max_bytes`` bytes of ``path`` and decodes them as
    UTF-8 text. Returns ``None`` — cleanly, never an exception — for a
    missing path, a directory, a file this process can't read, or a file
    that isn't valid UTF-8 text (the deliberate signal for "this is a
    binary file"). The ``max_bytes`` cap is enforced at the read itself:
    a large file is never loaded whole into memory just to be truncated
    afterward."""
    try:
        target = Path(path).resolve()
    except (OSError, ValueError):
        return None

    if not target.is_file():
        return None

    try:
        with open(target, "rb") as f:
            raw = f.read(max_bytes)
    except OSError as e:
        print(f"[fs] read failed: {e}")
        return None

    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        print(f"[fs] '{path}' is not UTF-8 text (binary file)")
        return None


def path_exists(path: str) -> bool:
    """Returns whether ``path`` exists (file or directory). Returns
    ``False`` — not an exception — for an unusable path string."""
    try:
        return Path(path).exists()
    except (OSError, ValueError):
        return False
