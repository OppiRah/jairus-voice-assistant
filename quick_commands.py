"""
quick_commands.py — a fast, fully local shortcut for simple short commands
(pause, resume, skip, volume, what's playing, corrections) so they don't have
to round-trip through the LLM. This is the biggest latency win for anything
that isn't a song/playlist request — no Ollama call, no GPU inference, just a
local string comparison.

Falls through to the full LLM-based intent parser for anything more complex
(song requests, playlists, ambiguous phrasing) by returning None.
"""

from difflib import SequenceMatcher

_CANONICAL_PHRASES = {
    "pause": ["pause", "stop", "stop it", "pause it", "hold on", "wait"],
    "resume": ["resume", "continue", "unpause", "keep going", "resume it", "continue playing"],
    "skip": ["skip", "next", "next song", "next one", "skip it", "skip this", "skip this one"],
    "volume_up": ["turn it up", "louder", "volume up", "turn up the volume", "make it louder"],
    "volume_down": ["turn it down", "quieter", "volume down", "turn down the volume",
                     "make it quieter", "lower the volume", "lower it"],
    "whats_playing": ["what's playing", "whats playing", "what is this", "what is playing",
                       "what song is this", "what's this song"],
    "correct": ["no not that one", "not that one", "wrong song", "wrong one", "different one",
                "that's not it", "not this one", "no not this"],
}

MATCH_THRESHOLD = 0.82
MAX_WORDS = 6  # only fast-path short utterances — longer ones probably have real content (a song title, etc.)


def _normalize(text: str) -> str:
    return text.strip().lower().rstrip(".!?,")


def match_quick_command(text: str):
    """Returns an intent dict if the text is a confident match for a simple
    command, else None (caller should fall back to the LLM parser)."""
    normalized = _normalize(text)
    if not normalized or len(normalized.split()) > MAX_WORDS:
        return None

    best_action = None
    best_score = 0.0

    for action, phrases in _CANONICAL_PHRASES.items():
        for phrase in phrases:
            score = SequenceMatcher(None, normalized, phrase).ratio()
            if score > best_score:
                best_score = score
                best_action = action

    if best_action and best_score >= MATCH_THRESHOLD:
        return {"action": best_action, "title": "", "artist": "", "songs": []}

    return None
