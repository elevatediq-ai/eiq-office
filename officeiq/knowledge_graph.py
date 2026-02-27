"""Tools for constructing a knowledge graph from extracted data."""

from collections import defaultdict


def build_knowledge_graph(data: list) -> dict:
    """Construct a basic graph representation from supplied items.

    For demonstration, treat the list as a sequence of nodes and create
    directed edges between consecutive items.  Real implementation would
    perform NLP and relationship extraction.
    """
    edges = []
    for a, b in zip(data, data[1:]):
        edges.append((a, b))
    return {"nodes": data, "edges": edges}


def add_node(graph: dict, node) -> None:
    """Add a node to an existing graph."""
    if node not in graph.get("nodes", []):
        graph.setdefault("nodes", []).append(node)


def add_edge(graph: dict, src, dst) -> None:
    """Add a directed edge to an existing graph."""
    graph.setdefault("edges", []).append((src, dst))


def adjacency_list(graph: dict) -> dict:
    """Return adjacency list mapping each node to outgoing neighbours."""
    adj = defaultdict(list)
    for src, dst in graph.get("edges", []):
        adj[src].append(dst)
    return dict(adj)
