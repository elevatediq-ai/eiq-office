"""Entity linking utilities to connect text to Jira/Azure DevOps work items."""

def link_entities_to_jira(text: str) -> dict:
    """Extract entities from text and map them to Jira IDs.

    Returns a dict mapping entity names to fake issue keys in this stub.
    """
    # placeholder implementation
    return {word: f"JIRA-{i+1}" for i, word in enumerate(text.split())}
