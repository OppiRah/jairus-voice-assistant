"""Static runtime configuration.

JAIRUS_ARCHITECTURE.md Part 12 (Repository / Codebase Architecture) reserves
``src/jairus/configuration/`` for exactly this: values every layer may need
that aren't domain models or behaviour. First real content in this package
(Phase 1 left it empty on purpose).

Phase 13 (Android Gateway) is the first consumer: the WebSocket server needs
a bind address/port and a shared secret to check ``connection.auth``
against. Nothing here is meant to survive contact with a config file or
environment variables later (Part 51's "Configuration" category) — for V1
this is deliberately plain module-level constants, matching how the rest of
this codebase keeps config next to the code that uses it (``WAKE_WORD_MODEL``
etc. in ``assistant_loop.py``).
"""

from __future__ import annotations

# Bound to 0.0.0.0 so other devices on the LAN (e.g. an Android phone) can
# reach it, not just this machine. JAIRUS_ARCHITECTURE.md Part 44: local
# network only for V1 — this is a bind address, not a public listener; no
# port forwarding/NAT traversal is set up anywhere in this project.
GATEWAY_HOST = "0.0.0.0"
GATEWAY_PORT = 8765

# CHANGE THIS before pairing a real device. This is a placeholder shared
# secret (JAIRUS_ARCHITECTURE.md Part 45: authentication, "who is
# connecting?") checked verbatim against connection.auth.payload.pairing_code.
# Anyone on the LAN who knows this string can submit commands, so it should
# not be left at the default outside of local development/testing.
ANDROID_PAIRING_CODE = "changeme-pairing-code"

# JAIRUS_ARCHITECTURE.md Part 13.2 — every message envelope carries this so
# a future protocol change doesn't silently break an older client.
PROTOCOL_VERSION = "1"
