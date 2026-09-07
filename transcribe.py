"""
transcribe.py — turns recorded audio into text using faster-whisper (local, GPU-accelerated)
"""

import numpy as np
from faster_whisper import WhisperModel

# "small" is a good balance for a 6GB VRAM card. Bump to "medium" if accuracy
# is bad and you don't mind ~1-2s more latency; drop to "base" if VRAM is tight
# while Ollama is also loaded.
MODEL_SIZE = "small"

_model = None

def _get_model():
    global _model
    if _model is None:
        print(f"[whisper] loading '{MODEL_SIZE}' model on GPU...")
        # compute_type="int8_float16" keeps VRAM usage low while staying fast on a 3060
        _model = WhisperModel(MODEL_SIZE, device="cuda", compute_type="int8_float16")
    return _model

def transcribe_audio(audio_int16: np.ndarray, sample_rate: int) -> str:
    """
    audio_int16: 1D numpy array of int16 samples from sounddevice
    returns: transcribed text (empty string if nothing usable was heard)
    """
    model = _get_model()

    # whisper expects float32 in [-1, 1]
    audio_float32 = audio_int16.astype(np.float32) / 32768.0

    segments, _info = model.transcribe(
        audio_float32,
        language="en",
        vad_filter=True,          # trims silence, avoids hallucinating text from noise
        beam_size=5,
    )

    text = " ".join(segment.text.strip() for segment in segments)
    return text.strip()
