"""UI helpers for OfficeIQ.

This package contains modules related to the user‑interface layer such as
streaming transcript generators and any other presentation helpers.  It is
kept minimal for now, mostly serving as a namespace for tests.
"""

from . import live_transcript  # expose submodule for easier import

__all__ = ["live_transcript"]
