"""Developer tool definitions — git status/diff, run tests, search code,
open project.

JAIRUS_ARCHITECTURE.md Part 14.19 (migration Phase 17), Part 15.11 ("V1
Developer Tools"), Part 23 (capability catalog), Part 24/91 (explicit V1
exclusions: no unrestricted shell/PowerShell), and Part 25 (permission
model).

The underlying implementation lives in
``jairus.infrastructure.developer.dev_tools`` (new this phase) — see that
module's docstring for the security boundary (fixed argv lists, no
``shell=True``, no caller-supplied command strings, pattern matching done
in Python rather than shelling out to grep). Registration is explicit,
not an import-time side effect, matching every prior phase. Call
``register_developer_tools()`` to populate the registry.

**Permission classification, reasoned per tool — genuinely re-derived
here, not copied from Phase 16's ``filesystem.read`` precedent without
engaging with it:**

- ``developer.git_status`` — returns filenames and one-letter status
  codes only, never file content. Pure metadata, same category as
  ``filesystem.list``. **HARMLESS.**
- ``developer.open_project`` — launches an editor window on a path,
  nothing more. Same reasoning as ``apps.launch``/``game.launch``:
  starting a program is Part 25's own Level 0 example. **HARMLESS.**
- ``developer.git_diff`` and ``developer.search_code`` — both expose
  actual file *content*, the same category of concern that made
  ``filesystem.read`` **DANGEROUS** last phase. The obvious question:
  does being scoped to "this repo" change that calculus? Considered and
  rejected as a real mitigant, for two concrete reasons:

  1. ``repo_path`` is still fully caller-supplied, with no enforced
     path-scoping (same gap flagged in Phase 16 — the Policy Engine
     remains shadow-only). "Scoped to a repo" doesn't mean "scoped to
     *this* project" — nothing stops ``repo_path`` from pointing at any
     other git-initialized directory on disk.
  2. The narrowing that does exist is real but partial, not
     category-changing: ``git_diff`` only shows *changed* lines of
     *tracked* files — smaller than a full file dump, but a secret
     accidentally added to a tracked file (an API key pasted into a
     config, mid-edit) shows up in a diff exactly as readily as it would
     in a raw read. ``search_code`` is arguably *less* scoped than
     ``git_diff``: it matches full content of any file under
     ``repo_path`` matching ``file_pattern`` — tracked, untracked, or
     gitignored — subject only to skipping ``venv/``/``__pycache__/``/
     ``.git/``/``node_modules/``, not to whether the file is even part of
     the project's real source.

  Both are therefore kept at the same tier as ``filesystem.read``:
  **``PermissionLevel.DANGEROUS``, ``requires_confirmation=True``.** A
  smaller blast radius *within* a given target isn't the same as a
  different risk *category*, and Part 25 doesn't define an intermediate
  tier for "somewhat narrower content exposure" — inventing one
  ungrounded in the architecture's own four-level taxonomy would be worse
  than reusing the tier that already fits.

- ``developer.run_tests`` — lands at the same **DANGEROUS** tier, but for
  a categorically different reason than the two tools above: this isn't
  content *disclosure*, it's code *execution*. ``pytest`` imports and
  runs whatever test modules/``conftest.py`` files actually exist at
  ``repo_path`` — the fixed, hardcoded invocation in ``dev_tools.py``
  constrains *how* the tool is invoked, not *what code runs* once
  ``pytest`` starts collecting. That is a strictly more powerful
  capability than any read-oriented tool in this project so far
  (execution, not just exposure), which is exactly why it's held at the
  ceiling of this project's permission taxonomy rather than defaulted
  down because "this repo doesn't even have real tests yet." The
  classification is about the capability, not today's contents of this
  particular repo.

No tool here defaults to HARMLESS "for convenience," and no tool is
pushed to DANGEROUS reflexively either — the two genuinely read-only,
metadata-only tools stay HARMLESS.
"""

from __future__ import annotations

from jairus.domain.permissions.permission_level import PermissionLevel
from jairus.domain.tools import ToolDefinition

from .registry import register_tool

DEVELOPER_TOOLS: list[ToolDefinition] = [
    ToolDefinition(
        name="developer.git_status",
        description="Reports modified/staged/untracked files for a git repository (filenames only, no content).",
        input_schema={
            "repo_path": {"type": "string", "description": "Path to a git repository's working tree"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=10,
    ),
    ToolDefinition(
        name="developer.git_diff",
        description="Returns the working-tree diff for a git repository, optionally for one file.",
        input_schema={
            "repo_path": {"type": "string", "description": "Path to a git repository's working tree"},
            "file_path": {"type": "string", "description": "Optional single file to diff, relative to repo_path"},
        },
        permission_level=PermissionLevel.DANGEROUS,
        requires_confirmation=True,
        timeout_seconds=15,
    ),
    ToolDefinition(
        name="developer.run_tests",
        description="Runs this repository's pytest suite, if it has one.",
        input_schema={
            "repo_path": {"type": "string", "description": "Path to the repository to test"},
        },
        permission_level=PermissionLevel.DANGEROUS,
        requires_confirmation=True,
        timeout_seconds=120,
    ),
    ToolDefinition(
        name="developer.search_code",
        description="Searches text files under a directory for a literal search term.",
        input_schema={
            "repo_path": {"type": "string", "description": "Directory to search"},
            "query": {"type": "string", "description": "Literal text to search for"},
            "file_pattern": {"type": "string", "description": "Filename glob to restrict the search to, default '*.py'"},
        },
        permission_level=PermissionLevel.DANGEROUS,
        requires_confirmation=True,
        timeout_seconds=30,
    ),
    ToolDefinition(
        name="developer.open_project",
        description="Opens a directory in VS Code.",
        input_schema={
            "path": {"type": "string", "description": "Directory to open"},
        },
        permission_level=PermissionLevel.HARMLESS,
        requires_confirmation=False,
        timeout_seconds=15,
    ),
]


def register_developer_tools() -> None:
    """Registers every developer tool definition above with the Tool Registry."""
    for tool in DEVELOPER_TOOLS:
        register_tool(tool)
