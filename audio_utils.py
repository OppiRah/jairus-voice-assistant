"""
audio_utils.py — records audio and automatically stops when you stop talking,
instead of always recording a fixed number of seconds.

Uses a simple volume (RMS) based voice activity detector: once your voice is loud
enough to count as "speech," it keeps recording until you've been quiet for
`silence_duration` seconds, then stops.
"""

import time
import numpy as np
import sounddevice as sd

# Tune this if it cuts you off too early (raise it) or never stops in a noisy
# room (lower it). Values are RMS of int16 samples — quiet room background noise
# is usually under 200-300, a normal speaking voice is usually 1000+.
SILENCE_THRESHOLD = 400


def record_until_silence(
    sample_rate=16000,
    chunk_duration=0.1,
    silence_threshold=SILENCE_THRESHOLD,
    silence_duration=1.2,
    max_duration=10,
    min_duration=0.6,
    on_level=None,
):
    """
    Records from the mic until `silence_duration` seconds of quiet follow detected
    speech (or `max_duration` is hit as a safety cap either way).

    on_level: optional callback(float 0.0-1.0) called once per chunk with the
    live normalized volume — used to drive the orb UI's reactive pulsing.

    Returns (audio_int16_array, speech_detected: bool) — speech_detected is False
    if the whole window was silence (useful for conversation-mode timeouts).
    """
    chunk_samples = int(sample_rate * chunk_duration)
    silence_chunks_needed = max(1, int(silence_duration / chunk_duration))

    frames = []
    speech_started = False
    silent_streak = 0
    start_time = time.time()

    stream = sd.InputStream(samplerate=sample_rate, channels=1, dtype="int16")
    stream.start()
    try:
        while True:
            data, _ = stream.read(chunk_samples)
            data = data.flatten()
            frames.append(data)

            rms = float(np.sqrt(np.mean(data.astype(np.float32) ** 2)))
            elapsed = time.time() - start_time

            if on_level:
                # rough normalization for visualization purposes only
                on_level(min(1.0, rms / 4000.0))

            if rms > silence_threshold:
                speech_started = True
                silent_streak = 0
            elif speech_started:
                silent_streak += 1

            if speech_started and silent_streak >= silence_chunks_needed and elapsed >= min_duration:
                break
            if elapsed >= max_duration:
                break
    finally:
        stream.stop()
        stream.close()
        if on_level:
            on_level(0.0)

    audio = np.concatenate(frames) if frames else np.array([], dtype=np.int16)
    return audio, speech_started
