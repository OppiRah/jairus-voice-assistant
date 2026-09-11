"""Policy Engine — decides whether a tool call may run immediately or
needs the user's explicit approval first.

JAIRUS_ARCHITECTURE.md Part 25 (permission model) and Part 26
(confirmation model), read and actually enforced for the first time in
Phase 10 (Part 14.12). ``ToolDefinition.permission_level`` and
``.requires_confirmation`` have been set correctly on every tool since
Phase 5 (media), Phase 7 (apps), and Phase 9 (windows) — this module is
the first thing that reads them for a real decision.

Deliberately narrow: ``evaluate()`` only reads the ``ToolDefinition``'s own
two fields; it does not compute, override, or second-guess a permission
level — "the LLM never decides a tool's level — the tool's definition and
the Policy Engine do" (``PermissionLevel``'s own docstring,
``domain/permissions/permission_level.py``). ``request_confirmation()`` is
a blocking TERMINAL y/n prompt for this phase; a richer confirmation UX
(voice, Android) is explicitly a later phase (Part 14.13+), not attempted
here.

**No caching, anywhere, on purpose.** Every call to
``request_confirmation()`` shows a fresh prompt and returns a fresh
decision. This module holds no state between calls — there is no way for
it to remember a prior "yes," even for the exact same tool and arguments
requested a second later. Approving one operation must never
automatically authorize a repeat of it (Part 26: "A confirmation for one
operation must not automatically authorize a different operation" — the
same rule, read the other direction, means it must not authorize *itself
again* either).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from jairus.domain.permissions.confirmation import Confirmation
from jairus.domain.tools import ToolDefinition

CONFIRMATION_WINDOW_SECONDS = 60


def evaluate(tool_definition: ToolDefinition) -> str:
    """Returns ``"allow"`` if the tool can run immediately, or
    ``"confirm"`` if the user must approve first — read straight from the
    tool's own ``requires_confirmation`` flag, not recomputed here."""
    return "confirm" if tool_definition.requires_confirmation else "allow"


def request_confirmation(tool_definition: ToolDefinition, arguments: dict[str, Any]) -> bool:
    """Blocks on a terminal y/n prompt describing exactly what is about to
    run, and returns the user's decision.

    Builds a real ``Confirmation`` record (the Phase 2 domain model, unused
    until now) bound to this exact tool and argument set (Part 26: a
    confirmation must bind to a specific command/tool/arguments, not
    authorize anything broader) — logged here, not stored or reused
    anywhere. No Command exists yet at this phase (the Agent Core is
    standalone, not wired to the Command Gateway — that integration is
    later), so ``command_id`` is a fresh placeholder id generated per
    confirmation request rather than a real Command's id.
    """
    confirmation = Confirmation(
        confirmation_id=str(uuid.uuid4()),
        command_id=str(uuid.uuid4()),
        tool_name=tool_definition.name,
        arguments=dict(arguments),
        description=f"{tool_definition.description} (arguments: {arguments})",
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=CONFIRMATION_WINDOW_SECONDS),
    )

    print(f"[policy] confirmation required for '{confirmation.tool_name}'")
    print(f"[policy] {confirmation.description}")
    answer = input("[policy] proceed? [y/n]: ").strip().lower()

    approved = answer in ("y", "yes")
    confirmation.decision = "approved" if approved else "denied"
    print(f"[policy] confirmation {confirmation.confirmation_id} -> {confirmation.decision}")
    return approved
