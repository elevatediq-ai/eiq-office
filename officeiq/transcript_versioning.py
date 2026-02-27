"""Versioning and editing logic for transcripts."""

# simple version history store
_HISTORY: dict[str, list[str]] = {}

def version_transcript(transcript: str, edits: list[str]) -> str:
    """Apply edits to a transcript and return the new version.

    For the purposes of this exercise, we simply append the edits as new
    versions.  The first call stores the original transcript as version
    zero.  Subsequent calls append a new version representing the edited text.

    Args:
        transcript: current transcript text.
        edits: list of strings representing changes (ignored in stub).

    Returns:
        The (unchanged) transcript string.
    """
    versions = _HISTORY.setdefault(transcript, [transcript])
    # append a new version (could incorporate edits)
    versions.append(transcript)
    return transcript


def get_versions(transcript: str) -> list[str]:
    """Return stored version history for a transcript."""
    return _HISTORY.get(transcript, [])
