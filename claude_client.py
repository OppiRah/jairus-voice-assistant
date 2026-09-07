"""
claude_client.py — calls the Claude API (Messages endpoint) as a smarter
escalation path: used when Ollama's output isn't trustworthy, or for specific
sub-tasks you've decided are worth the extra cost (see the escalation policy
at the top of intent_parser.py).

Needs an ANTHROPIC_API_KEY environment variable set — see the README for how
to set this permanently on Windows. Never hardcode your key in this file or
anywhere else you might share.

If the key isn't set, calling this raises a clear error — intent_parser.py
catches that and just falls back to Ollama-only behavior, so nothing breaks
if you haven't set up an API key yet.
"""

import os
import requests

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"
MODEL_NAME = "claude-haiku-4-5-20251001"  # cheapest current model — plenty for this kind of extraction


def call_claude(system_prompt: str, user_prompt: str, max_tokens: int = 300) -> str:
    """Sends a single-turn request to Claude and returns the raw text response.
    Raises on any failure — the caller decides how to handle/fall back."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY isn't set. See the README for how to set it as a "
            "Windows environment variable — this is expected if you haven't set "
            "up Claude yet, everything still works on Ollama alone."
        )

    response = requests.post(
        API_URL,
        headers={
            "x-api-key": api_key,
            "anthropic-version": API_VERSION,
            "content-type": "application/json",
        },
        json={
            "model": MODEL_NAME,
            "max_tokens": max_tokens,
            "system": system_prompt,
            "messages": [{"role": "user", "content": user_prompt}],
        },
        timeout=20,
    )
    response.raise_for_status()
    data = response.json()

    for block in data.get("content", []):
        if block.get("type") == "text":
            return block["text"]

    raise RuntimeError("Claude response had no text content")
