from officeiq.whisper_gpu import WhisperGPUWorker


def test_whisper_gpu_worker_stub():
    # The stub worker should always return a string, even if no model is
    # available on the system.  We don't require GPU hardware in CI.
    worker = WhisperGPUWorker()
    output = worker.transcribe(b"dummy audio")
    assert isinstance(output, str)
    # placeholder output from the stub contains the word "placeholder"
    assert "placeholder" in output or output == ""
