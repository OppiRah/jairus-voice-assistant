"""
transcribe.py — turns recorded audio into text using faster-whisper (local, GPU-accelerated)
"""

import os
import sysconfig


def _add_cuda_dll_dirs():
    """The pip-installed nvidia-*-cu12 packages (cublas/cudnn/etc.) ship their
    DLLs under site-packages/nvidia/<pkg>/bin, but ctranslate2's native loader
    resolves them by bare filename via the classic PATH-based search, not
    Python's os.add_dll_directory registry -- so those folders must be on
    PATH before ctranslate2 (imported via faster_whisper below) loads, or
    GPU inference fails with "Library cublas64_12.dll is not found".
    """
    if os.name != "nt":
        return
    nvidia_dir = os.path.join(sysconfig.get_paths()["purelib"], "nvidia")
    if not os.path.isdir(nvidia_dir):
        return
    bin_dirs = []
    for pkg in os.listdir(nvidia_dir):
        bin_dir = os.path.join(nvidia_dir, pkg, "bin")
        if os.path.isdir(bin_dir):
            bin_dirs.append(bin_dir)
            os.add_dll_directory(bin_dir)
    if bin_dirs:
        os.environ["PATH"] = os.pathsep.join(bin_dirs) + os.pathsep + os.environ["PATH"]


_add_cuda_dll_dirs()

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
