"""GPU-backed Whisper transcription worker for OfficeIQ.

This module provides a simple wrapper around a Whisper model (large-v3)
that is intended to run on GPU hardware and perform real-time transcription
with stringent latency requirements (<200ms per audio chunk) and high
accuracy (>=95% on standard benchmarks).

The implementation here is a starting point; actual model loading and
inference code will depend on the library chosen (openai, transformers,
whisper, etc.).

Usage:

    worker = WhisperGPUWorker(device="cuda:0")
    text = worker.transcribe(audio_bytes)

"""
from __future__ import annotations

import time
from typing import Optional


class WhisperGPUWorker:
    def __init__(self, device: str = "cuda:0", model_name: str = "large-v3"):
        """Initialize the GPU worker.

        Args:
            device: CUDA device identifier, e.g. "cuda:0".
            model_name: name of the Whisper model to load.
        """
        self.device = device
        self.model_name = model_name
        self._model = None  # type: Optional[object]

    def _load_model(self) -> None:
        """Lazy-load the model onto the GPU if not already present."""
        if self._model is None:
            # Attempt to load a Whisper model from a supported library.
            # We try OpenAI's `whisper` package first, then `faster_whisper`.
            # If neither is installed we fall back to a stub so that the
            # rest of the system and unit tests can operate without GPU.
            try:
                import whisper  # type: ignore

                # whisper.load_model will automatically move the model to the
                # specified device; the library handles CPU/GPU selection.
                self._model = whisper.load_model(self.model_name, device=self.device)
            except ImportError:
                try:
                    from faster_whisper import WhisperModel  # type: ignore

                    # faster-whisper uses a different API; we wrap it in the
                    # same minimal interface later in transcribe().
                    self._model = WhisperModel(
                        self.model_name,
                        device=self.device,
                        compute_type="float16",
                    )
                except ImportError:
                    # no real model available, keep a stub so our tests still
                    # pass and callers can detect the placeholder output.
                    self._model = "<whisper model stub>"

    def transcribe(self, audio_bytes: bytes) -> str:
        """Run transcription on a chunk of raw audio bytes.

        Args:
            audio_bytes: raw PCM or WAV data to transcribe.

        Returns:
            The transcribed text.
        """
        start = time.time()
        self._load_model()

        # If the loaded model is still a string stub we simulate a short delay
        # and return the placeholder text; this keeps the class usable when no
        # whisper library is installed (e.g. during unit tests or dry runs).
        if isinstance(self._model, str):
            time.sleep(0.01)  # mimic a tiny GPU inference delay
            transcript = "[transcription placeholder]"
        else:
            # Real model: we need to save the incoming bytes to a temporary
            # file because both `whisper` and `faster_whisper` expect a path or
            # NumPy array.
            import tempfile
            import os

            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                tmp.write(audio_bytes)
                tmp_path = tmp.name

            try:
                if hasattr(self._model, "transcribe"):
                    # whisper model returns a dict with a "text" field
                    result = self._model.transcribe(tmp_path)
                    if isinstance(result, dict):
                        transcript = result.get("text", "")
                    else:
                        transcript = str(result)
                elif hasattr(self._model, "__call__"):
                    # faster-whisper returns a tuple (segments, info)
                    out = self._model(tmp_path)
                    if isinstance(out, tuple) and len(out) >= 1:
                        # segments is first element, join texts
                        segments = out[0]
                        transcript = " ".join(s.text for s in segments)
                    else:
                        transcript = str(out)
                else:
                    # fallback to string representation
                    transcript = str(self._model)
            finally:
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass

        elapsed = (time.time() - start) * 1000.0
        # metrics/logging could be done here if desired
        return transcript


# helper for quick CLI testing
if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python whisper_gpu.py <audio_file>")
        sys.exit(1)
    fn = sys.argv[1]
    worker = WhisperGPUWorker()
    with open(fn, "rb") as f:
        data = f.read()
    print(worker.transcribe(data))
