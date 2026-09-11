"""Android Gateway — the WebSocket entry point for the Android client.

JAIRUS_ARCHITECTURE.md Part 13 (API & Protocol Specification), Part 44
(local-network-only for V1), Part 45 (authentication vs authorization),
and Part 11.7 ("the agent should not care where a command came from").

This is the first networked, first async code in this project. It is a
standalone server (started by ``run_gateway.py`` at the repo root) — it is
NOT wired into ``main.py``'s pygame + assistant-thread process. That
integration is an explicit follow-up phase, not this one.

What this module does, per connection:

1. Expect ``connection.hello`` then ``connection.auth`` (Part 13.5). If the
   pairing code in ``connection.auth`` doesn't match
   ``settings.ANDROID_PAIRING_CODE``, send ``connection.error`` and close
   the socket — never proceed silently (Part 45: authentication is "who is
   connecting?", checked before anything else happens).
2. Once authenticated, send ``connection.ready`` and enter a loop reading
   ``command.submit`` messages.
3. For each ``command.submit``: send ``command.acknowledged`` immediately
   (Part 13.11 — acknowledge receipt before doing the work, because the
   network can die mid-task), then hand the command text to the EXISTING,
   unmodified ``command_gateway.submit_command()`` with
   ``CommandSource.ANDROID`` — the exact same function voice already calls
   with ``CommandSource.VOICE``. That call is synchronous/blocking (it can
   reach Ollama, Whisper-adjacent code, and Playwright), so it runs via
   ``loop.run_in_executor()`` rather than blocking the event loop.
4. Once ``submit_command()`` returns, send ``task.completed`` or
   ``task.failed`` depending on the ``Command``'s final status.

Deliberately NOT implemented (see ANDROID_GATEWAY.md for the full scope
rationale): ``command.cancel``, ``command.status``, reconnection/state
reconciliation, ``confirmation.request``/``confirmation.response``,
``tool.*`` events, ``system.state``. Android reaches exactly the same 9
``media.*`` actions voice already reaches through the unmodified
``handle_command()``; no confirmation flow exists on that live path today
(the Policy Engine is still shadow-only per Phase 10/11), so there is
nothing yet for a confirmation protocol to gate.
"""

from __future__ import annotations

import asyncio
import json
import uuid

import websockets
from websockets.exceptions import ConnectionClosed

from assistant_state import AssistantState
from context import ConversationContext
from jairus.application.commands import submit_command
from jairus.application.tasks import get_task_by_command
from jairus.configuration import settings
from jairus.domain.commands import CommandSource, CommandStatus
from jairus.interfaces.android.protocol import build_message, parse_message

# A single shared ConversationContext/AssistantState for the server's
# lifetime, per this phase's explicit scope (no per-device isolation yet —
# that's later work, same as voice only ever having one context per run).
#
# Deviation from a literal `state=None`: handle_command() (assistant_loop.py,
# unmodified) calls `state.set_status("thinking")` unconditionally as its
# first line, with no None-guard, so a literal None would make every single
# Android command fail instantly (caught by submit_command()'s own
# try/except, surfaced as task.failed) before handle_command() did any real
# work at all -- defeating the entire point of this phase, which is to prove
# CommandSource.ANDROID reaches the same real execution path as
# CommandSource.VOICE. A real (but here UI-less) AssistantState() is a
# pre-existing, unmodified class built for exactly this purpose; passing a
# real instance costs nothing (no pygame/orb dependency) and is what the
# call site actually needs to behave like the real voice path, including the
# real TTS speech that goes with it (speak() calls happen inside
# handle_command() exactly as they do for voice).
_CONTEXT = ConversationContext()
_STATE = AssistantState()
_CONVERSATION_ID = str(uuid.uuid4())


async def _send(websocket, type: str, payload: dict) -> None:
    await websocket.send(json.dumps(build_message(type, payload)))


async def _send_error(websocket, code: str, message: str) -> None:
    await _send(websocket, "connection.error", {"code": code, "message": message})


async def _authenticate(websocket) -> str | None:
    """Runs the connection.hello -> connection.auth -> connection.ready
    handshake (Part 13.5). Returns the claimed device_id on success, or
    None if the handshake failed (an error has already been sent and the
    caller should close the socket).
    """
    hello_raw = await websocket.recv()
    hello = parse_message(hello_raw)
    if hello is None or hello["type"] != "connection.hello":
        await _send_error(websocket, "PROTOCOL_ERROR", "expected connection.hello")
        return None

    device_id = hello["payload"].get("device_id", "unknown")
    print(f"[gateway-android] connection.hello from device={device_id}")

    auth_raw = await websocket.recv()
    auth = parse_message(auth_raw)
    if auth is None or auth["type"] != "connection.auth":
        await _send_error(websocket, "PROTOCOL_ERROR", "expected connection.auth")
        return None

    pairing_code = auth["payload"].get("pairing_code")
    if pairing_code != settings.ANDROID_PAIRING_CODE:
        print(f"[gateway-android] auth failed for device={device_id}")
        await _send_error(websocket, "AUTHENTICATION_FAILED", "Authentication failed.")
        return None

    await _send(websocket, "connection.ready", {"server_version": "0.1.0", "agent_status": "ready"})
    print(f"[gateway-android] device={device_id} authenticated -> ready")
    return device_id


async def _handle_command_submit(websocket, payload: dict) -> None:
    text = payload.get("text", "")
    if not isinstance(text, str) or not text.strip():
        await _send_error(websocket, "VALIDATION_ERROR", "command.submit payload missing non-empty 'text'")
        return

    # Part 13.11: acknowledge receipt before doing the (potentially slow,
    # network-fragile-to-wait-on) work.
    await _send(websocket, "command.acknowledged", {"status": "accepted"})
    print(f"[gateway-android] command.submit acknowledged: '{text}'")

    # submit_command() is synchronous/blocking (Ollama, intent parsing,
    # Playwright/media control) -- must not block the event loop.
    loop = asyncio.get_running_loop()
    command = await loop.run_in_executor(
        None, submit_command, text, CommandSource.ANDROID, _CONTEXT, _STATE, _CONVERSATION_ID
    )

    task = get_task_by_command(command.command_id)
    result_payload = {
        "command_id": command.command_id,
        "task_id": task.task_id if task is not None else None,
        "status": command.status.value,
        "raw_input": command.raw_input,
    }

    if command.status == CommandStatus.COMPLETED:
        await _send(websocket, "task.completed", result_payload)
    else:
        await _send(websocket, "task.failed", result_payload)
    print(f"[gateway-android] command {command.command_id} -> {command.status.value}")


async def _handle_connection(websocket) -> None:
    device_id = None
    try:
        device_id = await _authenticate(websocket)
        if device_id is None:
            await websocket.close()
            return

        async for raw in websocket:
            message = parse_message(raw)
            if message is None:
                await _send_error(websocket, "MALFORMED_MESSAGE", "could not parse message envelope")
                continue

            if message["type"] == "command.submit":
                await _handle_command_submit(websocket, message["payload"])
            else:
                await _send_error(
                    websocket, "UNKNOWN_MESSAGE_TYPE", f"unrecognized message type: {message['type']}"
                )

    except ConnectionClosed:
        pass
    finally:
        print(f"[gateway-android] connection closed (device={device_id})")


async def run_server() -> None:
    """Binds and serves forever (until cancelled / Ctrl+C)."""
    async with websockets.serve(_handle_connection, settings.GATEWAY_HOST, settings.GATEWAY_PORT):
        await asyncio.Future()  # run until cancelled
