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

from jairus.application.commands.command_gateway import submit_command
from jairus.domain.commands import CommandSource

# ---- config ----
# openWakeWord only ships a pretrained acoustic model for "hey jarvis" — there's no
# pretrained "hey jairus" model, so this stays "hey_jarvis" even though the assistant
# is now branded "Jairus". You still have to say "hey jarvis" out loud to trigger it,
# until/unless a custom wake word model gets trained for "hey jairus" down the line.
WAKE_WORD_MODEL = "hey_jairus.onnx"
SAMPLE_RATE = 16000
DETECTION_THRESHOLD = 0.5
CHUNK_SIZE = 1280  # openwakeword expects 80ms chunks at 16kHz


def _wake_word_key() -> str:
    if WAKE_WORD_MODEL.endswith((".onnx", ".tflite")):
        import os
        return os.path.splitext(os.path.basename(WAKE_WORD_MODEL))[0]
    return WAKE_WORD_MODEL


def handle_command(text: str, context: ConversationContext, state):
    state.set_status("thinking")
    intent = extract_intent(text, context)
    print(f"[intent] {intent}")
    action = intent.get("action", "play")

    try:
        if action == "play" and intent.get("title"):
            query = f"{intent.get('title', '')} {intent.get('artist', '')}".strip()
            speak(f"Playing {query}", state)
            play_song(intent)
        elif action == "queue":
            songs = intent.get("songs", [])
            if songs:
                speak(f"Queuing up {len(songs)} songs", state)
                start_queue(songs)
            else:
                speak("Couldn't come up with a playlist for that", state)
        elif action == "pause":
            pause_music()
            speak("Paused", state)
        elif action == "resume":
            resume_music()
            speak("Resumed", state)
        elif action == "skip":
            skip_music()
            speak("Skipped", state)
        elif action == "correct":
            switched = correct_song()
            speak("How about this one" if switched else "That was the last option I found", state)
        elif action == "volume_up":
            adjust_volume("up")
            speak("Turned it up", state)
        elif action == "volume_down":
            adjust_volume("down")
            speak("Turned it down", state)
        elif action == "whats_playing":
            now_playing = get_now_playing()
            speak(f"This is {now_playing}" if now_playing else "Nothing's playing right now", state)
        else:
            print("[skip] couldn't figure out a command from that")
            speak("Didn't catch that", state)
    except Exception as e:
        print(f"[player] something went wrong ({e})")
        speak("Something went wrong", state)
        return False

    context.add_turn(text, intent)
    return True


def run_assistant(state):
    print("[init] downloading/loading openwakeword models (first run only)...")
    openwakeword.utils.download_models()
    oww_model = Model(wakeword_models=[WAKE_WORD_MODEL])
    wake_key = _wake_word_key()
    context = ConversationContext()
    conversation_id = str(uuid.uuid4())  # one per program run; ConversationContext also resets per run

    print(f"[ready] listening for wake word: '{wake_key.replace('_', ' ')}'")
    print("        say it, then say your command, e.g.:")
    print("        'hey jairus' ... 'play something chill'")
    print("        'hey jairus' ... 'queue up a workout playlist'")
    print("        'hey jairus' ... 'pause' / 'resume' / 'skip'")
    print("        'hey jairus' ... 'turn it up' / 'turn it down'")
    print("        'hey jairus' ... 'what's playing?'")

    stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="int16", blocksize=CHUNK_SIZE)
    stream.start()
    state.set_status("idle")

    try:
        while True:
            audio_chunk, _ = stream.read(CHUNK_SIZE)
            audio_chunk = audio_chunk.flatten()

            # subtle ambient reactivity while idle — reuses the chunk we already read, no extra cost
            ambient_rms = float(np.sqrt(np.mean(audio_chunk.astype(np.float32) ** 2)))
            state.set_level(min(1.0, ambient_rms / 4000.0) * 0.3)

            prediction = oww_model.predict(audio_chunk)
            score = prediction.get(wake_key, 0)

            if score > DETECTION_THRESHOLD:
                print(f"\n[wake] detected! (score={score:.2f})")
                stream.stop()
                state.set_status("listening")
                speak("Yes?", state)
                state.set_status("listening")  # speak() reverts to idle when done; re-assert

                audio, spoke = record_until_silence(
                    sample_rate=SAMPLE_RATE,
                    silence_duration=0.8,
                    min_duration=0.4,
                    on_level=state.set_level,
                )

                state.set_status("thinking")
                text = transcribe_audio(audio, SAMPLE_RATE)
                print(f"[transcript] {text}")

                if text.strip():
                    submit_command(text, CommandSource.VOICE, context, state, conversation_id)
                else:
                    print("[skip] heard nothing usable, going back to sleep")

                state.set_status("idle")
                state.set_level(0.0)
                oww_model.reset()
                stream.start()
                print("\n[ready] listening for wake word again...")

    except KeyboardInterrupt:
        print("\n[stop] shutting down")
    finally:
        stream.stop()
        stream.close()
