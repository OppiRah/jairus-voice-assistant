"""Message envelope helpers for the Android Gateway protocol.

JAIRUS_ARCHITECTURE.md Part 13.3 (Message Envelope) and Part 13.4
(Message ID vs Command ID). Every WebSocket message, in both directions,
uses the same envelope:

    protocol_version, message_id, type, timestamp, payload

``message_id`` identifies this one network message (Part 13.4) and is
unrelated to a ``Command``'s own ``command_id`` — one command can produce
several messages (acknowledged, then completed/failed), each with its own
fresh ``message_id``.

This module only builds and validates the envelope. It knows nothing about
what a ``type`` means or what a well-formed ``payload`` looks like for that
type — that's ``gateway_server.py``'s job.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Any

from jairus.configuration.settings import PROTOCOL_VERSION

_REQUIRED_FIELDS = ("protocol_version", "message_id", "type", "timestamp", "payload")


def build_message(type: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Builds one envelope-compliant message, ready for ``json.dumps``.

    ``message_id`` is a fresh ``uuid4`` and ``timestamp`` is the current
    time in ISO format (UTC) — this function assigns both; callers only
    supply ``type`` and ``payload``.
    """
    return {
        "protocol_version": PROTOCOL_VERSION,
        "message_id": str(uuid.uuid4()),
        "type": type,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
    }


def parse_message(raw: str) -> dict[str, Any] | None:
    """Parses and validates one incoming envelope.

    Returns the decoded message (a ``dict``) if ``raw`` is valid JSON *and*
    contains every required envelope field. Returns ``None`` otherwise —
    malformed JSON and a well-formed-but-incomplete envelope are both
    treated as "not a usable message," per Part 13.26 ("every message
    should be schema validated"): the caller is expected to respond with
    ``connection.error`` rather than assume a shape that isn't actually
    there.
    """
    try:
        message = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None

    if not isinstance(message, dict):
        return None

    if not all(field in message for field in _REQUIRED_FIELDS):
        return None

    if not isinstance(message["payload"], dict):
        return None

    return message
