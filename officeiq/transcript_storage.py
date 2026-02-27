"""Persistence layer for storing transcripts in a lightweight database.

By default we use SQLite to simplify deployment and testing.  The database
file path can be overridden via the ``TRANSCRIPT_DB_PATH`` environment
variable.  The schema consists of a single table named ``transcripts`` with
columns ``meeting_id`` (primary key) and ``text``.
"""

import os
import sqlite3


def _get_connection():
    db_path = os.environ.get("TRANSCRIPT_DB_PATH", "transcripts.db")
    conn = sqlite3.connect(db_path)
    return conn


def persist_transcript(meeting_id: str, text: str) -> bool:
    """Persist a transcript to the backing store.

    Args:
        meeting_id: unique identifier for the meeting.
        text: full transcript text to store.

    Returns:
        True if the operation succeeded, False otherwise.
    """
    conn = _get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "CREATE TABLE IF NOT EXISTS transcripts (meeting_id TEXT PRIMARY KEY, text TEXT)"
        )
        cur.execute(
            "INSERT OR REPLACE INTO transcripts (meeting_id, text) VALUES (?, ?)",
            (meeting_id, text),
        )
        conn.commit()
        return True
    except Exception:
        return False
    finally:
        conn.close()


def get_transcript(meeting_id: str) -> str | None:
    """Retrieve a previously stored transcript (for testing).

    Returns the text if found, or ``None`` if the meeting ID is not present.
    """
    conn = _get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "CREATE TABLE IF NOT EXISTS transcripts (meeting_id TEXT PRIMARY KEY, text TEXT)"
        )
        cur.execute(
            "SELECT text FROM transcripts WHERE meeting_id = ?", (meeting_id,)
        )
        row = cur.fetchone()
        return row[0] if row else None
    finally:
        conn.close()
