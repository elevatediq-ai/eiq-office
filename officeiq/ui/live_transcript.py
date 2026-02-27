"""Stub implementation of a live transcript generator.

Tests in `tests/test_live_transcript.py` rely on a simple iterable returned by
:func:`start_streaming`.  In a real product this would hook into WebRTC, a
voice‑to‑text service, or a streaming audio pipeline; for now we emit a fixed
message so that the unit tests can exercise the API.
"""

from __future__ import annotations

from typing import Iterator, Dict


def start_streaming() -> Iterator[Dict[str, object]]:
    """Return a generator that yields transcript chunks.

    The returned iterator must be usable in a for‑loop and the first item is
    expected to be a dictionary containing at least the keys ``text``,
    ``speaker`` and ``confidence``.  This stub emits exactly one message and
    then terminates.
    """
    yield {"text": "(stream start)", "speaker": "system", "confidence": 1.0}
