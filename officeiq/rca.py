"""Generate root cause analysis summaries from meeting transcripts."""

def generate_rca(transcript: str) -> str:
    """Produce a draft RCA text from the input transcript.

    Heuristic implementation:
    1. Split into sentences and use first one as context.
    2. Look for keywords ("error", "failed", "exception") and include
       them in the draft for signal words.

    Real code would use NLP/LLM summarization.
    """
    sentences = [s.strip() for s in transcript.split(".") if s.strip()]
    if not sentences:
        return "RCA draft: no content."
    first = sentences[0]
    keywords = [w for w in ["error", "failed", "exception"] if w in transcript.lower()]
    kw_str = f" Keywords: {', '.join(keywords)}." if keywords else ""
    return f"RCA draft: identify root cause in '{first}'.{kw_str}"
