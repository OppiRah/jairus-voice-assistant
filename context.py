"""
context.py — lightweight in-memory conversation context.

Keeps track of recent commands and the last song played so the intent parser
can resolve references like "play that again" or "no, not that one."
Resets whenever the script restarts — nothing is saved to disk.
"""

class ConversationContext:
    def __init__(self, max_turns=4):
        self.max_turns = max_turns
        self.turns = []  # raw transcript strings, most recent last
        self.last_song = {"title": "", "artist": ""}

    def add_turn(self, text: str, intent: dict):
        self.turns.append(text)
        if len(self.turns) > self.max_turns:
            self.turns.pop(0)

        if intent.get("action") == "play" and intent.get("title"):
            self.last_song = {
                "title": intent.get("title", ""),
                "artist": intent.get("artist", ""),
            }
        elif intent.get("action") == "queue" and intent.get("songs"):
            first = intent["songs"][0]
            self.last_song = {
                "title": first.get("title", ""),
                "artist": first.get("artist", ""),
            }

    def as_prompt_block(self) -> str:
        if not self.turns and not self.last_song["title"]:
            return "(no prior context)"

        lines = []
        if self.turns:
            lines.append("Recent commands (most recent last):")
            for t in self.turns:
                lines.append(f'- "{t}"')
        if self.last_song["title"]:
            song_desc = self.last_song["title"]
            if self.last_song["artist"]:
                song_desc += f" by {self.last_song['artist']}"
            lines.append(f"Last song played: {song_desc}")

        return "\n".join(lines)
