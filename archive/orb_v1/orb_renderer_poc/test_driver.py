"""
test_driver.py — throwaway WebSocket state-message sender for the orb
renderer PoC (ORB_RENDERER_INVESTIGATION.md section 5).

Modeled on src/jairus/interfaces/android/gateway_server.py's minimal
`websockets.serve()` pattern, but this file is standalone: it is NOT part
of the real Jairus project's dependency chain, NOT imported by anything
in the real codebase, and does not import from assistant_loop.py,
assistant_state.py, or anything under src/jairus/. It only reuses the
`websockets` package already in requirements.txt for the real app.

Runs a bare WebSocket server on port 8766 (deliberately NOT 8765, which
is the real Android Gateway's port from Phase 13 -- kept completely
separate). Once the Godot orb_controller.gd client connects, sends a
hardcoded state message every few seconds, cycling
idle -> listening -> thinking -> speaking -> idle forever, so a person
watching the Godot window can see it visibly react to each state change.

Run:  python test_driver.py
Stop: Ctrl+C
"""

import asyncio
import json

import websockets

HOST = "localhost"
PORT = 8766

# (state, level, seconds to hold before moving to the next one)
SEQUENCE = [
    ("idle", 0.05, 3),
    ("listening", 0.6, 3),
    ("thinking", 0.2, 3),
    ("speaking", 0.8, 3),
]


async def _drive_one_client(websocket) -> None:
    print(f"[test_driver] Godot client connected from {websocket.remote_address}")
    try:
        while True:
            for state, level, hold_seconds in SEQUENCE:
                message = json.dumps({"state": state, "level": level})
                print(f"[test_driver] -> {message}")
                await websocket.send(message)
                await asyncio.sleep(hold_seconds)
    except websockets.exceptions.ConnectionClosed:
        print("[test_driver] Godot client disconnected")


async def run_server() -> None:
    print(f"[test_driver] listening on ws://{HOST}:{PORT}")
    print("[test_driver] waiting for the Godot orb_controller.gd client to connect...")
    async with websockets.serve(_drive_one_client, HOST, PORT):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        print("\n[test_driver] shutting down")
