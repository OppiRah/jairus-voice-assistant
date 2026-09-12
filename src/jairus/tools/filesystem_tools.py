"""Filesystem tool definitions — read-only search/list/read/exists.

JAIRUS_ARCHITECTURE.md Part 14.18 (migration Phase 16), Part 15.9 ("V1
Filesystem" — read-only, "no deletion yet"), Part 23 (capability catalog),
and Part 25 (permission model).

The underlying implementation lives in
``jairus.infrastructure.filesystem.fs_tools`` (new this phase), which
contains no write/delete/move capability whatsoever — not even as an
unregistered helper. Registration is explicit, not an import-time side
effect, matching every prior phase. Call ``register_filesystem_tools()``
to populate the registry.

**Permission classification, reasoned per tool — and NOT defaulted to a
single level out of convenience. Three of these four tools only ever
expose metadata; the fourth exposes file *contents*, which is a
qualitatively different kind of exposure and is classified accordingly:**

- ``filesystem.search`` — returns matching *paths* (names), nothing about
  what's inside those files. Directly comparable to Part 25's own Level 0
  example, "search." **HARMLESS.**
- ``filesystem.list`` — returns names, a directory/file flag, and sizes
  for one directory's immediate contents. Still pure metadata, nothing
  about content. Comparable to Part 25's "read system information."
  **HARMLESS.**
- ``filesystem.exists`` — returns a single boolean. The smallest possible
  information disclosure (whether *something* is at a path), and the
  architecture's own example query ("Does PROJECT_CONTEXT.md exist?",
  Part 15.9) is unambiguously benign. **HARMLESS.**
- ``filesystem.read`` — returns the actual *contents* of an arbitrary file
  this process can read, and that is a fundamentally different risk than
  the three tools above. This project has already hit this exact problem
  once for real: ``browser_profile/`` (see ``RECONNAISSANCE.md``) is a
  full Brave user-data profile that sat checked into this very repo's
  working tree — the kind of directory that holds cookies, saved-session
  tokens, and potentially saved credentials. A ``filesystem.read`` tool
  with no path scoping (and there is none yet — no allow-list, no
  sandbox; the Policy Engine remains shadow-only per Phase 11) could be
  pointed at that directory, or at a ``.env`` file, an SSH private key, a
  browser cookie database, or any other secret sitting on disk, and
  return its contents just as readily as it would return the text of a
  README. Part 25 itself names "credential-related actions" as its own
  **Level 3** example — and unscoped file-content access is exactly that
  vector once pointed at the right path, not merely a Level 1 "state
  change" (nothing is being disrupted or changed) and not a Level 2
  "destructive" op (nothing is deleted or overwritten) either. The
  disclosure is also asymmetric with every other tool built so far:
  closing an app, invoking a UI control, or deleting a file are all
  *visible, undoable-in-spirit* actions the user can observe going wrong;
  a quiet file read that exfiltrates a secret has no equivalent visible
  side effect and no do-over. That combination — real precedent in this
  codebase, an explicit textual match to Part 25's own Level 3 example,
  and the total absence of any path-scoping mechanism to constrain it —
  is why this tool, alone among the four, is set to
  **``PermissionLevel.DANGEROUS``, ``requires_confirmation=True``**: the
  first tool in this project classified at that level. Path
  scoping/sandboxing (e.g. restricting reads to an explicit allow-listed
  root) is a known, real future need flagged here deliberately rather
  than silently deferred — it does not exist yet, so confirmation is the
  only gate standing in front of this tool today.
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

FILESYSTEM_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="filesystem.search",
        description="Searches a directory for files/directories matching a glob-style pattern (e.g. '*.py').",
        input_schema={
            "directory": {"type": "string", "description": "Directory to search under"},
            "pattern": {"type": "string", "description": "Glob-style pattern, e.g. '*.py' or '**/*.py'"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="filesystem.list",
        description="Lists the immediate contents of a directory (name, is_dir, size for each entry).",
        input_schema={
            "path": {"type": "string", "description": "Directory to list"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="filesystem.read",
        description="Reads a text file's contents (up to a byte cap). Returns nothing for binary files.",
        input_schema={
            "path": {"type": "string", "description": "File to read"},
            "max_bytes": {"type": "integer", "description": "Maximum bytes to read (default 100000)"},
        },
        permission_level=PermissionLevel.DANGEROUS,
        requires_confirmation=True,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="filesystem.exists",
        description="Reports whether a file or directory exists at a given path.",
        input_schema={
            "path": {"type": "string", "description": "Path to check"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=5,
    ),
]


def register_filesystem_tools() -> None:
    """Registers every filesystem tool definition above with the Tool Registry."""
    for tool in FILESYSTEM_TOOLS:
        register_tool(tool)
