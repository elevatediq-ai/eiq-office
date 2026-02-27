"""Persistence layer for storing transcripts in PostgreSQL or other DBs."""

# simple in-memory store to simulate database persistence
_STORE: dict[str, str] = {}

def persist_transcript(meeting_id: str, text: str) -> bool:
    """Persist a transcript to the backing store.

    The current implementation writes into a module-level dictionary.  A
    real implementation would perform an INSERT/UPDATE against PostgreSQL.

    Returns:
        bool: True if persistence succeeded.
    """
    _STORE[meeting_id] = text
    return True


def get_transcript(meeting_id: str) -> str | None:
    """Retrieve a previously stored transcript (for testing)."""
    return _STORE.get(meeting_id)
