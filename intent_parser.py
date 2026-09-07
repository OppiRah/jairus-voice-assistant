"""
intent_parser.py — extracts {action, title, artist, songs} from a transcribed
sentence. This is where the Ollama-vs-Claude routing happens:

  1. Simple commands (pause/skip/volume/etc.) never touch either LLM —
     quick_commands.py handles those instantly and for free.
  2. Everything else goes to Ollama (qwen2.5:7b) first — free, local, and
     good enough for most requests.
  3. Claude is only called if Ollama fails (bad/missing response), or if
     ESCALATE_QUEUE_TO_CLAUDE is turned on below and this is a playlist
     request (Claude tends to suggest more accurate real songs).

This means Claude costs you nothing unless Ollama actually breaks, or you
explicitly opt into spending a little for better playlist quality. If you
haven't set up ANTHROPIC_API_KEY at all, step 3 just fails quietly and falls
back to a raw-text guess — the whole thing still works on Ollama alone.
"""

import json
import requests

from quick_commands import match_quick_command
from claude_client import call_claude

OLLAMA_URL = "http://localhost:11434/api/generate"
OLLAMA_MODEL_NAME = "qwen2.5:7b"

# ---- escalation policy — tune this yourself ----
# True = playlist/"queue" requests always get re-parsed by Claude for
# better real-song accuracy (small extra cost, a fraction of a cent each).
# False = playlists stay on Ollama like everything else (free).
ESCALATE_QUEUE_TO_CLAUDE = False

SYSTEM_PROMPT = """You extract a video/media command from a spoken sentence, using the CONTEXT below if the sentence refers back to something. This covers songs, but also TV episodes, anime, movie clips, or any other video someone might ask to watch on YouTube.

Return ONLY a JSON object, no other text, no markdown fences, in this exact shape:
{"action": "play | pause | resume | skip | correct | volume_up | volume_down | whats_playing | queue", "title": "<song/show/episode title, search phrase, or empty string>", "artist": "<artist/creator name or empty string, OPTIONAL>", "songs": [{"title": "...", "artist": "..."}]}

Rules:
- "play": ONE specific request — a song, a TV/anime episode ("Jobless Reincarnation season 3 episode 5"), a movie clip, or a mood/vibe/genre request (e.g. "play something chill"). Put the full title/search phrase — including season/episode numbers if mentioned — into "title" exactly as said. Leave "songs" as an empty list.
- "artist" is for the performer/creator ONLY if one was actually mentioned (e.g. "by The Weeknd"). For shows, episodes, or anything without a named artist, leave "artist" as "".
- "queue": the user wants MULTIPLE songs back to back — a playlist, a set, "some workout songs," etc. Generate a "songs" list of 5 to 8 real, existing songs that fit the request, each as {"title": "...", "artist": "..."}. Leave top-level "title"/"artist" empty. (Not for TV/episode requests — those are always "play".)
- If the sentence refers back to something already discussed ("play that again," "play it," "the next episode"), use CONTEXT to fill in title/artist for a "play" action.
- "pause" / "resume" / "skip": no title/artist/songs needed.
- "correct": rejecting what's currently playing or just queued (e.g. "no not that one," "wrong video"). No title/artist/songs needed.
- "volume_up" / "volume_down": user wants it louder/quieter ("turn it up," "lower the volume"). No title/artist/songs needed.
- "whats_playing": user is asking what's currently playing ("what is this," "what's playing"). No title/artist/songs needed.
- Never guess an "artist"/creator that wasn't mentioned or isn't in CONTEXT.
- Never include explanations, only the JSON object.
"""


def _parse_json_response(raw_output: str) -> dict:
    raw_output = raw_output.replace("```json", "").replace("```", "").strip()
    parsed = json.loads(raw_output)

    songs = parsed.get("songs", [])
    clean_songs = []
    if isinstance(songs, list):
        for s in songs:
            if isinstance(s, dict):
                clean_songs.append({
                    "title": str(s.get("title", "")).strip(),
                    "artist": str(s.get("artist", "")).strip(),
                })

    return {
        "action": parsed.get("action", "play").strip() or "play",
        "title": parsed.get("title", "").strip(),
        "artist": parsed.get("artist", "").strip(),
        "songs": clean_songs,
    }


def _call_ollama(full_prompt: str) -> dict:
    response = requests.post(
        OLLAMA_URL,
        json={
            "model": OLLAMA_MODEL_NAME,
            "prompt": full_prompt,
            "stream": False,
            "options": {"temperature": 0},
            "keep_alive": "30m",
        },
        timeout=60,
    )
    response.raise_for_status()
    raw_output = response.json().get("response", "").strip()
    return _parse_json_response(raw_output)


def _call_claude_intent(sentence_prompt: str) -> dict:
    raw_output = call_claude(SYSTEM_PROMPT, sentence_prompt)
    return _parse_json_response(raw_output)


def extract_intent(text: str, context=None) -> dict:
    # fast path: simple commands skip both LLMs entirely, no cost, no delay
    quick_match = match_quick_command(text)
    if quick_match is not None:
        print(f"[intent] fast-pathed '{text}' -> {quick_match['action']} (no LLM call)")
        return quick_match

    context_block = context.as_prompt_block() if context is not None else "(no prior context)"
    sentence_prompt = f"CONTEXT:\n{context_block}\n\nSentence: \"{text}\"\nJSON:"
    full_prompt = f"{SYSTEM_PROMPT}\n\n{sentence_prompt}"

    intent = None

    # 1. default: Ollama (free, local)
    try:
        intent = _call_ollama(full_prompt)
        print("[intent] parsed via Ollama (free)")
    except (requests.RequestException, json.JSONDecodeError, ValueError) as e:
        print(f"[intent] Ollama failed ({e}), escalating to Claude...")

    # 2. escalate to Claude if Ollama failed, or if this is a queue request
    #    and you've opted into better playlist quality
    should_escalate = intent is None or (
        ESCALATE_QUEUE_TO_CLAUDE and intent.get("action") == "queue"
    )

    if should_escalate:
        try:
            claude_intent = _call_claude_intent(sentence_prompt)
            print(f"[intent] parsed via Claude ({'fallback' if intent is None else 'queue upgrade'})")
            intent = claude_intent
        except Exception as e:
            print(f"[intent] Claude escalation unavailable/failed ({e})")
            if intent is None:
                print("[intent] falling back to raw text as a play request")
                intent = {"action": "play", "title": text, "artist": "", "songs": []}

    return intent
