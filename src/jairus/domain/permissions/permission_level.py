"""PermissionLevel — how risky a tool is."""

from __future__ import annotations

from enum import IntEnum


class PermissionLevel(IntEnum):
    """Risk classification for a tool, from JAIRUS_ARCHITECTURE.md Part 25.

    Integer-valued so the architecture's "Level 0..3" maps directly onto the
    enum members. The LLM never decides a tool's level — the tool's definition
    and the Policy Engine do.
    """

    HARMLESS = 0     # e.g. pause media, open a website, search, read system info
    DISRUPTIVE = 1   # e.g. close an application, terminate a process
    DESTRUCTIVE = 2  # e.g. delete a file, overwrite data, uninstall software
    DANGEROUS = 3    # e.g. administrator ops, security config, credential access
