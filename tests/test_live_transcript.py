from officeiq.ui import live_transcript


def test_start_streaming_generator():
    gen = live_transcript.start_streaming()
    assert hasattr(gen, "__iter__")
    # first item should be a dict with required keys
    item = next(gen)
    assert isinstance(item, dict)
    assert set(item.keys()) >= {"text", "speaker", "confidence"}
