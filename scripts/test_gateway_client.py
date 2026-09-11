"""
scripts/test_gateway_client.py — dev utility for exercising the Android
Gateway (JAIRUS_ARCHITECTURE.md Part 13; see ANDROID_GATEWAY.md).

Connects as a bare WebSocket client (no Android app needed), runs the
connection.hello -> connection.auth -> connection.ready handshake, then
submits one command.submit and prints every message received.

Usage:
    python scripts/test_gateway_client.py "pause" changeme-pairing-code
    python scripts/test_gateway_client.py "play some lo-fi beats" changeme-pairing-code
    python scripts/test_gateway_client.py "pause" wrong-code-on-purpose

Remains useful after the real Android app exists, for testing the server
in isolation without a phone.
"""

import argparse
import asyncio
import json
import uuid
from datetime import datetime, timezone

import websockets


def build_message(type_: str, payload: dict) -> dict:
    return {
        "protocol_version": "1",
        "message_id": str(uuid.uuid4()),
        "type": type_,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
    }


async def run(host: str, port: int, text: str, pairing_code: str) -> None:
    uri = f"ws://{host}:{port}"
    print(f"[client] connecting to {uri}")

    async with websockets.connect(uri) as ws:
        hello = build_message(
            "connection.hello",
            {"client_type": "test_script", "client_version": "0.1.0", "device_id": "test-client"},
        )
        print(f"[client] -> {json.dumps(hello)}")
        await ws.send(json.dumps(hello))

        auth = build_message("connection.auth", {"pairing_code": pairing_code})
        print(f"[client] -> {json.dumps(auth)}")
        await ws.send(json.dumps(auth))

        reply_raw = await ws.recv()
        print(f"[client] <- {reply_raw}")
        reply = json.loads(reply_raw)

        if reply["type"] == "connection.error":
            print("[client] authentication was rejected, stopping here.")
            return
        if reply["type"] != "connection.ready":
            print(f"[client] unexpected message during handshake: {reply['type']}")
            return

        submit = build_message("command.submit", {"text": text})
        print(f"[client] -> {json.dumps(submit)}")
        await ws.send(json.dumps(submit))

        # Expect command.acknowledged, then task.completed/task.failed.
        for _ in range(2):
            raw = await ws.recv()
            print(f"[client] <- {raw}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Test client for the Jairus Android Gateway.")
    parser.add_argument("text", help="Command text to submit, e.g. 'pause'")
    parser.add_argument("pairing_code", help="Pairing code to send in connection.auth")
    parser.add_argument("--host", default="localhost", help="Gateway host (default: localhost)")
    parser.add_argument("--port", type=int, default=8765, help="Gateway port (default: 8765)")
    args = parser.parse_args()

    asyncio.run(run(args.host, args.port, args.text, args.pairing_code))


if __name__ == "__main__":
    main()
