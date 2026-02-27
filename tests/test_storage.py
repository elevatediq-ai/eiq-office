import os
import sqlite3
import tempfile

from officeiq import transcript_storage


def test_persist_and_get_transcript(tmp_path, monkeypatch):
    db_file = tmp_path / "test.db"
    monkeypatch.setenv("TRANSCRIPT_DB_PATH", str(db_file))

    assert transcript_storage.get_transcript("m1") is None
    success = transcript_storage.persist_transcript("m1", "hello world")
    assert success

    # ensure file was created and contains the record
    conn = sqlite3.connect(str(db_file))
    cur = conn.cursor()
    cur.execute("SELECT text FROM transcripts WHERE meeting_id = ?", ("m1",))
    row = cur.fetchone()
    conn.close()
    assert row is not None and row[0] == "hello world"

    # retrieval via helper
    assert transcript_storage.get_transcript("m1") == "hello world"
