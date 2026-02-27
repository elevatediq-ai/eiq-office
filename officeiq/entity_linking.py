"""Entity linking utilities to connect text to Jira/Azure DevOps work items."""

def link_entities_to_jira(text: str) -> dict:
    """Extract entities from text and map them to Jira IDs.

    The stub uses a simple regex to capture capitalized words and returns
    a deterministic mapping for testing.  Real code would call Jira or
    Azure DevOps APIs.
    """
    import re
    entities = re.findall(r"\b[A-Z][a-zA-Z0-9_]+\b", text)
    seen = {}
    for ent in entities:
        if ent not in seen:
            seen[ent] = f"JIRA-{len(seen)+1}"
    return seen
