"""Renderer Bridge — pushes AssistantState to an external real-time
renderer (the Godot orb) over a local WebSocket.

ORB_RENDERER_INVESTIGATION.md section 6 (migration strategy): this is a
new, additive READER of AssistantState, mirroring exactly the same
read-only relationship orb_widget.py's own OrbWidget already has --
get_snapshot()/get_activity_snapshot() only, no new writer methods, no
change to how anything currently writes to AssistantState. The Agent
Core, Tool Registry, and Policy Engine are never touched or imported
here; this module has no way to affect what Jairus does, only to report
what AssistantState already says.

Runs on its own port, deliberately distinct from every other WebSocket
server in this project:
  - 8765: the real Android Gateway (Phase 13, gateway_server.py)
  - 8766: orb_renderer_poc/test_driver.py's throwaway PoC test port
  - 8767: THIS bridge (real integration)

Message shape matches what orb_renderer_poc's Godot client already
validated ({"state": ..., "level": ...}), extended with "activity" (the
current-activity text ActivityPanel already shows) since it's already
available from the same get_activity_snapshot() call and costs nothing
extra to include.
"""

from __future__ import annotations

import asyncio
import json
import threading

import websockets

RENDERER_BRIDGE_HOST = "localhost"
RENDERER_BRIDGE_PORT = 8767

# How often to check AssistantState for a change. A message is only ever
# actually sent when the built message differs from the last one sent --
# see _stream_state()'s docstring for why polling and sending-on-change
# are two separate decisions here, not the same thing.
POLL_INTERVAL_SECONDS = 0.15

# `level` is a live mic-amplitude/animation value that jitters constantly
# (ambient RMS noise, tts.py's randomized speaking animation) -- comparing
# it at full float precision would mean "send on change" almost always
# sends anyway, defeating the point. Rounding to this many decimal places
# before comparing collapses that jitter into real, visually-meaningful
# steps (Godot's own lerp-based smoothing, same as the PoC, interpolates
# between whatever values it receives, so this granularity is still
# plenty smooth) while genuinely skipping duplicate sends during
# stretches where nothing meaningful is actually happening.
LEVEL_ROUNDING = 2


def _build_message(state) -> str:
    status, level = state.get_snapshot()
    activity, _history = state.get_activity_snapshot()
    return json.dumps({
        "state": str(status),
        "level": round(level, LEVEL_ROUNDING),
        "activity": activity,
    })


async def _stream_state(websocket, state) -> None:
    """One connected renderer client: sends the current state immediately
    on connect, then again only when it actually changes. Decided against
    sending unconditionally on every poll tick -- at a 150ms interval
    that's still under 7 messages/second even while idle, but the common
    case (nothing changing: idle, waiting for a wake word, an unchanging
    activity label) would otherwise spam identical messages to the
    renderer for no visual benefit, since nothing about the message would
    differ between sends.
    """
    last_sent = None
    try:
        while True:
            message = _build_message(state)
            if message != last_sent:
                await websocket.send(message)
                last_sent = message
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
    except websockets.exceptions.ConnectionClosed:
        pass


async def run_bridge(state) -> None:
    async with websockets.serve(
        lambda ws: _stream_state(ws, state), RENDERER_BRIDGE_HOST, RENDERER_BRIDGE_PORT
    ):
        await asyncio.Future()  # run forever


def start_bridge_thread(state) -> None:
    """Starts the bridge server on its own daemon thread with its own
    asyncio event loop. Non-blocking -- main.py calls this once, only
    when a Godot renderer subprocess actually launched successfully."""

    def _run():
        asyncio.run(run_bridge(state))

    threading.Thread(target=_run, daemon=True, name="renderer-bridge").start()
