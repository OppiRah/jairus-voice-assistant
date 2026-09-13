"""
assistant_loop.py — the always-listening voice assistant logic. Runs in a
background thread (started by main.py) while the orb UI owns the main thread.

Flow:
  [always listening] wake word detected
      -> speak "Yes?"
      -> record until you stop talking (silence detection, not a fixed timer)
      -> transcribe with whisper
      -> extract {action, title, artist, songs} — fast local match for simple
         commands, otherwise local Ollama (qwen2.5:7b) with conversation context
      -> route to local file / YouTube / system media keys, whichever applies
      -> back to idle, listening for the wake word again

Throughout, updates the shared AssistantState so the orb UI can reflect what's
happening (idle / listening / thinking / speaking) and pulse with live or
animated audio level.
"""

import threading
import time

import requests
import sounddevice as sd
import numpy as np
import openwakeword
from openwakeword.model import Model

from audio_utils import record_until_silence
from transcribe import transcribe_audio
from intent_parser import extract_intent
from player_action import (
    play_song,
    pause_music,
    resume_music,
    skip_music,
    correct_song,
    adjust_volume,
    get_now_playing,
    start_queue,
)
from tts import speak
from context import ConversationContext

# --- Jairus migration (Phase 3): make src/ importable so this loop can hand
# commands to the new application layer while all existing logic stays put. ---
import os
import sys
import uuid

_SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
if _SRC_DIR not in sys.path:
    sys.path.insert(0, _SRC_DIR)

from assistant_state import AssistantStatus
from jairus.configuration import settings
from jairus.interfaces.voice import submit_voice_command

# --- Jairus migration (Phase 11): shadow-mode Agent Core. Runs ALONGSIDE the
# real path above, in dry-run mode only -- it observes and logs what the new
# Agent Core would have done with the same transcribed text, but can never
# execute anything or affect what the user hears/sees. See
# AGENT_SHADOW_MODE.md. Registration is one-time setup (Phase 5's tools are
# data until register_media_tools() populates the registry); the allow-list
# here deliberately matches Aria's existing 9 voice actions exactly, nothing
# more -- voice capabilities are not expanding in this phase. ---
from jairus.application.agent import run_goal
from jairus.tools import register_media_tools

SHADOW_ALLOWED_TOOLS = [
    "media.play",
    "media.pause",
    "media.resume",
    "media.skip",
    "media.correct",
    "media.volume_up",
    "media.volume_down",
    "media.now_playing",
    "media.queue",
]


def _shadow_evaluate(text: str) -> None:
    """Runs the Agent Core against the same transcribed text, in dry-run
    mode, purely to observe and log what it WOULD have done. Called AFTER
    the real submit_command() above has already produced the real
    response, specifically so shadow evaluation's own latency (an extra
    Ollama round trip) can never delay what the user hears -- see
    AGENT_SHADOW_MODE.md for why this ordering was chosen.

    Deliberately swallows every exception: a shadow-evaluation failure
    (Ollama down, a malformed response, anything at all) must never reach
    the caller. The real assistant continues exactly as if shadow mode
    didn't exist.
    """
    try:
        run_goal(text, allowed_tools=SHADOW_ALLOWED_TOOLS, dry_run=True)
    except Exception as e:
        print(f"[shadow] evaluation failed: {e}")


# ---- config ----
# openWakeWord only ships a pretrained acoustic model for "hey jarvis" — there's no
# pretrained "hey jairus" model, so this stays "hey_jarvis" even though the assistant
# is now branded "Jairus". You still have to say "hey jarvis" out loud to trigger it,
# until/unless a custom wake word model gets trained for "hey jairus" down the line.
WAKE_WORD_MODEL = "hey_jairus.onnx"
SAMPLE_RATE = 16000
CHUNK_SIZE = 1280  # openwakeword expects 80ms chunks at 16kHz
# Wake-word sensitivity (Phase 6, UI): read fresh from settings on every
# loop iteration below, not cached here -- a Settings change takes effect
# on the very next audio chunk, no restart needed. Default (0.5) lives in
# jairus.configuration.settings so there's one source of truth for it.

# Phase 3 (UI): backend health check — same Ollama instance intent_parser.py
# talks to, just its lightweight root endpoint instead of /api/generate, so
# checking reachability never loads a model or costs a real inference call.
OLLAMA_HEALTH_URL = "http://localhost:11434/"
HEALTH_CHECK_INTERVAL_SECONDS = 10

# How long COMPLETED/ERROR stay visible before handle_command() returns and
# run_assistant()'s own post-command reset takes status back to idle -- see
# ASSISTANT_STATUS_MODEL.md. Without this, both states would be set and
# immediately overwritten within the same call stack unwind, too fast to
# ever be visually perceptible.
TERMINAL_STATE_DISPLAY_SECONDS = 0.6


def _wake_word_key() -> str:
    if WAKE_WORD_MODEL.endswith((".onnx", ".tflite")):
        import os
        return os.path.splitext(os.path.basename(WAKE_WORD_MODEL))[0]
    return WAKE_WORD_MODEL


def _check_ollama_reachable() -> bool:
    try:
        response = requests.get(OLLAMA_HEALTH_URL, timeout=2)
        return response.status_code == 200
    except requests.RequestException:
        return False


def _health_check_loop(state):
    """Runs on its own daemon thread so a slow/unreachable Ollama never
    blocks the UI thread or the assistant's listen loop. Makes the existing
    silent Ollama-down fallback (intent_parser.py) visible instead of only
    showing up in terminal logs.
    """
    while True:
        state.set_ollama_reachable(_check_ollama_reachable())
        time.sleep(HEALTH_CHECK_INTERVAL_SECONDS)


def handle_command(text: str, context: ConversationContext, state):
    state.set_status(AssistantStatus.THINKING)
    intent = extract_intent(text, context)
    print(f"[intent] {intent}")
    action = intent.get("action", "play")

    try:
        if action == "play" and intent.get("title"):
            query = f"{intent.get('title', '')} {intent.get('artist', '')}".strip()
            activity_text = f"Playing {query}"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
            state.set_status(AssistantStatus.EXECUTING)
            play_song(intent)
        elif action == "queue":
            songs = intent.get("songs", [])
            if songs:
                activity_text = f"Queuing up {len(songs)} songs"
                speak(activity_text, state)
                state.set_current_activity(activity_text)
                state.add_history_entry(activity_text, action_type=action)
                state.set_status(AssistantStatus.EXECUTING)
                start_queue(songs)
            else:
                activity_text = "Couldn't come up with a playlist for that"
                speak(activity_text, state)
                state.set_current_activity(activity_text)
                state.add_history_entry(activity_text, action_type=action)
        elif action == "pause":
            state.set_status(AssistantStatus.EXECUTING)
            pause_music()
            activity_text = "Paused"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        elif action == "resume":
            state.set_status(AssistantStatus.EXECUTING)
            resume_music()
            activity_text = "Resumed"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        elif action == "skip":
            state.set_status(AssistantStatus.EXECUTING)
            skip_music()
            activity_text = "Skipped"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        elif action == "correct":
            state.set_status(AssistantStatus.EXECUTING)
            switched = correct_song()
            activity_text = "How about this one" if switched else "That was the last option I found"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        elif action == "volume_up":
            state.set_status(AssistantStatus.EXECUTING)
            adjust_volume("up")
            activity_text = "Turned it up"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        elif action == "volume_down":
            state.set_status(AssistantStatus.EXECUTING)
            adjust_volume("down")
            activity_text = "Turned it down"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        elif action == "whats_playing":
            now_playing = get_now_playing()
            activity_text = f"This is {now_playing}" if now_playing else "Nothing's playing right now"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type=action)
        else:
            print("[skip] couldn't figure out a command from that")
            activity_text = "Didn't catch that"
            speak(activity_text, state)
            state.set_current_activity(activity_text)
            state.add_history_entry(activity_text, action_type="unknown")
    except Exception as e:
        print(f"[player] something went wrong ({e})")
        activity_text = "Something went wrong"
        speak(activity_text, state)
        state.set_current_activity(activity_text)
        state.add_history_entry(activity_text, action_type="error")
        state.set_status(AssistantStatus.ERROR)
        time.sleep(TERMINAL_STATE_DISPLAY_SECONDS)
        return False

    state.set_status(AssistantStatus.COMPLETED)
    time.sleep(TERMINAL_STATE_DISPLAY_SECONDS)
    context.add_turn(text, intent)
    return True


def run_assistant(state):
    threading.Thread(target=_health_check_loop, args=(state,), daemon=True).start()

    print("[init] downloading/loading openwakeword models (first run only)...")
    openwakeword.utils.download_models()
    oww_model = Model(wakeword_models=[WAKE_WORD_MODEL])
    state.set_model_loaded(True)
    wake_key = _wake_word_key()
    context = ConversationContext()
    conversation_id = str(uuid.uuid4())  # one per program run; ConversationContext also resets per run

    # Phase 11: one-time setup so the shadow Agent Core has tools to choose
    # from (Phase 5's ToolDefinitions are inert data until registered).
    register_media_tools()

    print(f"[ready] listening for wake word: '{wake_key.replace('_', ' ')}'")
    print("        say it, then say your command, e.g.:")
    print("        'hey jairus' ... 'play something chill'")
    print("        'hey jairus' ... 'queue up a workout playlist'")
    print("        'hey jairus' ... 'pause' / 'resume' / 'skip'")
    print("        'hey jairus' ... 'turn it up' / 'turn it down'")
    print("        'hey jairus' ... 'what's playing?'")

    stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="int16", blocksize=CHUNK_SIZE)
    stream.start()
    state.set_mic_active(True)
    state.set_status(AssistantStatus.IDLE)

    try:
        while True:
            audio_chunk, _ = stream.read(CHUNK_SIZE)
            audio_chunk = audio_chunk.flatten()

            # subtle ambient reactivity while idle — reuses the chunk we already read, no extra cost
            ambient_rms = float(np.sqrt(np.mean(audio_chunk.astype(np.float32) ** 2)))
            state.set_level(min(1.0, ambient_rms / 4000.0) * 0.3)

            prediction = oww_model.predict(audio_chunk)
            score = prediction.get(wake_key, 0)

            if score > settings.get("wake_word_sensitivity"):
                print(f"\n[wake] detected! (score={score:.2f})")
                stream.stop()
                state.set_status(AssistantStatus.LISTENING)
                speak("Yes?", state)
                state.set_status(AssistantStatus.LISTENING)  # speak() reverts to idle when done; re-assert

                audio, spoke = record_until_silence(
                    sample_rate=SAMPLE_RATE,
                    silence_duration=0.8,
                    min_duration=0.4,
                    on_level=state.set_level,
                )

                state.set_status(AssistantStatus.THINKING)
                text = transcribe_audio(audio, SAMPLE_RATE)
                print(f"[transcript] {text}")

                if text.strip():
                    submit_voice_command(text, context, state, conversation_id)
                    _shadow_evaluate(text)  # Phase 11: dry-run only, observes/logs, never executes
                else:
                    print("[skip] heard nothing usable, going back to sleep")

                state.set_status(AssistantStatus.IDLE)
                state.set_level(0.0)
                oww_model.reset()
                stream.start()
                print("\n[ready] listening for wake word again...")

    except KeyboardInterrupt:
        print("\n[stop] shutting down")
    finally:
        state.set_mic_active(False)
        stream.stop()
        stream.close()
