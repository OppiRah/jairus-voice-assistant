"""Bounded developer tools — git status/diff, running tests, searching
code, opening a project. Deliberately NOT a general shell.

JAIRUS_ARCHITECTURE.md Part 14.19 (migration Phase 17), Part 15.11 ("V1
Developer Tools" — "Limited... enough to make Jairus useful during
development without handing the LLM unrestricted terminal access"), Part
23 (capability catalog), and Part 24/91's explicit V1 exclusions:
"unrestricted shell", "unrestricted PowerShell".

**The security boundary this module exists inside of, non-negotiably:**

- ``git_status``/``git_diff`` invoke ``git`` via ``subprocess`` with a
  FIXED argv list per call — never ``shell=True``, never a command built
  by concatenating/formatting caller input into a string. Caller input
  (``repo_path``, ``file_path``) is passed as its own argv element,
  exactly like ``apps.py``'s use of native APIs; a value that happens to
  start with ``-`` is defused with a ``--`` separator before it reaches
  ``git diff`` (see ``git_diff``) rather than trusted not to look like a
  flag.
- ``search_code`` does NOT shell out to ``grep``/``findstr``/``ripgrep``
  with a caller-supplied string at all. Pattern matching is implemented
  directly in Python (``pathlib`` for file discovery, ``re`` for line
  matching) — a caller supplies a search term and gets back matches; it
  never controls what program runs or how.
- ``run_tests`` invokes exactly one hardcoded command shape
  (``[sys.executable, "-m", "pytest", repo_path, ...fixed flags]``) — a
  caller supplies only ``repo_path``; there is no way to pass an
  arbitrary command, arbitrary flags, or a different program at all.
- ``open_project`` is a thin, single-purpose wrapper around
  ``["code", path]`` — nothing more, no shell, no other arguments.

Every function validates its input and returns a clean failure value
(rather than raising) for a path that doesn't exist, isn't a git repo, or
a subprocess that couldn't be started — same discipline as every prior
infrastructure module in this project.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

GIT_TIMEOUT_SECONDS = 15
TEST_TIMEOUT_SECONDS = 120
OPEN_PROJECT_TIMEOUT_SECONDS = 15

# Same spirit as Phase 16's `max_bytes` cap on `read_file` and result cap on
# `search_files`: bound tool output, don't return something unbounded.
MAX_DIFF_CHARS = 50_000
MAX_SEARCH_MATCHES = 500

_EXCLUDED_DIR_NAMES = {"venv", "__pycache__", ".git", "node_modules"}


def _resolve_existing_dir(path: str) -> Path | None:
    try:
        resolved = Path(path).resolve()
    except (OSError, ValueError):
        return None
    if not resolved.is_dir():
        return None
    return resolved


def _is_git_repo(repo_path: Path) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_path), "rev-parse", "--is-inside-work-tree"],
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_SECONDS,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and result.stdout.strip() == "true"


def git_status(repo_path: str) -> dict:
    """Returns ``{"is_git_repo": bool, "clean": bool, "staged": [...],
    "modified": [...], "untracked": [...]}`` for ``repo_path``, parsed
    from ``git status --porcelain``. If ``repo_path`` doesn't exist or
    isn't a git repository, returns the same shape with
    ``"is_git_repo": False`` and every list empty — never raises."""
    empty = {"is_git_repo": False, "clean": True, "staged": [], "modified": [], "untracked": []}

    base = _resolve_existing_dir(repo_path)
    if base is None:
        print(f"[dev] '{repo_path}' is not an existing directory")
        return empty
    if not _is_git_repo(base):
        print(f"[dev] '{base}' is not a git repository")
        return empty

    print(f"[dev] git status '{base}'")
    try:
        result = subprocess.run(
            ["git", "-C", str(base), "status", "--porcelain"],
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_SECONDS,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"[dev] git status failed: {e}")
        return empty

    staged: list[str] = []
    modified: list[str] = []
    untracked: list[str] = []
    for line in result.stdout.splitlines():
        if len(line) < 4:
            continue
        index_status, worktree_status, path = line[0], line[1], line[3:]
        if index_status == "?" and worktree_status == "?":
            untracked.append(path)
            continue
        if index_status not in (" ", "?"):
            staged.append(path)
        if worktree_status not in (" ", "?"):
            modified.append(path)

    return {
        "is_git_repo": True,
        "clean": not (staged or modified or untracked),
        "staged": staged,
        "modified": modified,
        "untracked": untracked,
    }


def git_diff(repo_path: str, file_path: str | None = None) -> str:
    """Returns the working-tree diff for ``repo_path`` (or just
    ``file_path`` within it, if given), via ``git diff``. Capped at
    ``MAX_DIFF_CHARS`` — a truncation note is appended if the real diff
    was longer.

    Returns ``""`` both when there's genuinely no diff to show AND when
    ``repo_path`` doesn't exist / isn't a git repository — the same
    "success reports the call ran, not that there was necessarily
    something to report" ambiguity APPS_TOOLS.md already accepted for
    ``apps.close`` returning ``False`` for "nothing to close." A caller
    that needs to tell the two apart can call ``git_status()`` first.
    """
    base = _resolve_existing_dir(repo_path)
    if base is None:
        print(f"[dev] '{repo_path}' is not an existing directory")
        return ""
    if not _is_git_repo(base):
        print(f"[dev] '{base}' is not a git repository")
        return ""

    # `--` separates the pathspec from options: a file_path that happens to
    # start with `-` (e.g. "--upload-pack=...") is treated as a literal path,
    # never as a flag, whether or not it was supplied with malicious intent.
    args = ["git", "-C", str(base), "diff"]
    if file_path:
        args += ["--", file_path]

    print(f"[dev] git diff '{base}'" + (f" -- {file_path}" if file_path else ""))
    try:
        result = subprocess.run(
            args, capture_output=True, text=True, timeout=GIT_TIMEOUT_SECONDS, stdin=subprocess.DEVNULL
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"[dev] git diff failed: {e}")
        return ""

    output = result.stdout
    if len(output) > MAX_DIFF_CHARS:
        output = output[:MAX_DIFF_CHARS] + f"\n... [truncated, diff exceeded {MAX_DIFF_CHARS} characters]"
    return output


def run_tests(repo_path: str) -> dict:
    """Runs ``pytest`` against ``repo_path`` with a fixed, hardcoded
    argument set — never a caller-supplied command. Returns
    ``{"ran": bool, "output": str, "passed": bool | None}``:

    - ``passed=True``/``False`` only when pytest actually collected and
      ran at least one test (exit code 0 or a genuine test-failure exit
      code).
    - ``passed=None`` for every case where there's no real test verdict to
      report: pytest collected zero tests (its own "no tests found" exit
      code), or pytest itself isn't installed/runnable in this
      environment. Both are honest, distinct-from-pass/fail outcomes, not
      failures of this tool.
    - ``ran=False`` only when the subprocess itself couldn't be invoked at
      all (bad path, pytest not importable, timeout) — not merely "found
      no tests."
    """
    base = _resolve_existing_dir(repo_path)
    if base is None:
        print(f"[dev] '{repo_path}' is not an existing directory")
        return {"ran": False, "output": f"'{repo_path}' is not an existing directory", "passed": None}

    args = [sys.executable, "-m", "pytest", str(base), "-q", "--no-header"]
    print(f"[dev] run_tests '{base}'")
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=TEST_TIMEOUT_SECONDS,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        msg = f"test run exceeded {TEST_TIMEOUT_SECONDS}s and was aborted"
        print(f"[dev] {msg}")
        return {"ran": False, "output": msg, "passed": None}
    except OSError as e:
        print(f"[dev] run_tests failed to start: {e}")
        return {"ran": False, "output": str(e), "passed": None}

    output = (result.stdout + result.stderr).strip()

    if "No module named pytest" in output or "No module named 'pytest'" in output:
        # pytest isn't installed in this interpreter -- couldn't run at all,
        # not "ran and found nothing." Honest, not a fabricated pass/fail.
        return {"ran": False, "output": output, "passed": None}

    if result.returncode == 5:
        # pytest's own exit code for "no tests were collected" -- e.g. this
        # repo, which has no pytest suite yet.
        return {"ran": True, "output": output, "passed": None}

    return {"ran": True, "output": output, "passed": result.returncode == 0}


def search_code(repo_path: str, query: str, file_pattern: str = "*.py") -> list[dict]:
    """Searches text files under ``repo_path`` matching ``file_pattern``
    (glob against the filename only, e.g. ``"*.py"``) for lines containing
    ``query``, returning up to ``MAX_SEARCH_MATCHES`` matches as
    ``{"file": ..., "line_number": ..., "line_content": ...}``.

    ``query`` is matched as a literal substring — via a compiled,
    ``re.escape()``-d pattern, so this genuinely uses ``re`` for the match
    itself without ever exposing arbitrary caller-controlled regex syntax
    (and the ReDoS risk that would come with it). ``venv/``,
    ``__pycache__/``, ``.git/``, and ``node_modules/`` directories are
    pruned automatically, wherever they appear. A file that isn't valid
    UTF-8 text is skipped, not garbled into false matches. Returns ``[]``
    for a nonexistent ``repo_path`` or an empty ``query``.
    """
    base = _resolve_existing_dir(repo_path)
    if base is None:
        print(f"[dev] '{repo_path}' is not an existing directory")
        return []
    if not query:
        return []

    pattern = re.compile(re.escape(query))
    matches: list[dict] = []

    print(f"[dev] search_code '{base}' for '{query}' ({file_pattern})")
    for root, dirnames, filenames in _walk_pruned(base):
        for filename in filenames:
            if not Path(filename).match(file_pattern):
                continue
            file_path = root / filename
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    for line_number, line in enumerate(f, start=1):
                        if pattern.search(line):
                            matches.append(
                                {
                                    "file": str(file_path),
                                    "line_number": line_number,
                                    "line_content": line.rstrip("\n"),
                                }
                            )
                            if len(matches) >= MAX_SEARCH_MATCHES:
                                print(f"[dev] search capped at {MAX_SEARCH_MATCHES} matches")
                                return matches
            except (OSError, UnicodeDecodeError):
                continue

    return matches


def _walk_pruned(base: Path):
    """Like ``os.walk``, but as a generator over ``pathlib.Path`` objects,
    pruning ``_EXCLUDED_DIR_NAMES`` in place so this never descends into
    ``venv/`` etc. at all (not just filters results after the fact)."""
    import os

    for root, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in _EXCLUDED_DIR_NAMES]
        yield Path(root), dirnames, filenames


def open_project(path: str) -> bool:
    """Opens VS Code (the ``code`` CLI) on ``path``. Returns ``False``
    cleanly if ``path`` doesn't exist or the ``code`` command isn't
    available on ``PATH`` — never raises."""
    resolved = _resolve_existing_dir(path)
    if resolved is None:
        print(f"[dev] '{path}' is not an existing directory")
        return False

    # subprocess with shell=False (used throughout this module, deliberately)
    # does not consult PATHEXT the way a shell does, and VS Code's CLI on
    # Windows is a ".cmd" shim rather than a bare ".exe" -- shutil.which()
    # resolves that ahead of time so the actual subprocess call can still be
    # a fixed argv list with no shell involved.
    code_cli = shutil.which("code")
    if code_cli is None:
        print("[dev] 'code' command not found on PATH")
        return False

    print(f"[dev] opening '{resolved}' in VS Code")
    try:
        result = subprocess.run(
            [code_cli, str(resolved)],
            timeout=OPEN_PROJECT_TIMEOUT_SECONDS,
            stdin=subprocess.DEVNULL,
            capture_output=True,
        )
    except subprocess.TimeoutExpired:
        # The `code` CLI can hang briefly while handing off to an
        # already-running VS Code instance even though the window opens
        # successfully -- treated as success rather than a false failure.
        return True
    except OSError as e:
        print(f"[dev] 'code' command not available: {e}")
        return False

    return result.returncode == 0
