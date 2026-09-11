"""
run_gateway.py — standalone entry point for the Android WebSocket Gateway
(JAIRUS_ARCHITECTURE.md Part 13/44/45; see ANDROID_GATEWAY.md).

Deliberately independent of main.py: this phase proves the Gateway on its
own before it is ever wired into the existing pygame + assistant-thread
process. main.py has zero diff.

Run:  python run_gateway.py
Stop: Ctrl+C
"""

import asyncio
import os
import sys

_SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from jairus.configuration import settings
from jairus.interfaces.android.gateway_server import run_server


def main():
    print(f"[gateway] listening on {settings.GATEWAY_HOST}:{settings.GATEWAY_PORT}")
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        print("\n[gateway] shutting down")


if __name__ == "__main__":
    main()
