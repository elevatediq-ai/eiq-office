import pytest

from officeiq import (
    transcript_storage,
    transcript_versioning,
    entity_linking,
    knowledge_graph,
    bulk_import,
    rca,
)


def test_persist_transcript_stub():
    assert transcript_storage.persist_transcript("m1", "hello")
    assert transcript_storage.get_transcript("m1") == "hello"


def test_version_transcript_stub():
    transcript = "original"
    history1 = transcript_versioning.get_versions(transcript)
    assert history1 == []
    transcript_versioning.version_transcript(transcript, ["edit1"])
    history2 = transcript_versioning.get_versions(transcript)
    assert len(history2) == 2
    assert history2[0] == transcript

    # further versions accumulate
    transcript_versioning.version_transcript(transcript, ["edit2"])
    assert len(transcript_versioning.get_versions(transcript)) == 3


def test_entity_linking_stub():
    result = entity_linking.link_entities_to_jira("Alpha beta Gamma delta")
    assert isinstance(result, dict)
    assert result.get("Alpha") == "JIRA-1"
    assert result.get("Gamma") == "JIRA-2"
    assert "beta" not in result


def test_knowledge_graph_stub():
    result = knowledge_graph.build_knowledge_graph([1, 2])
    assert result["nodes"] == [1, 2]
    assert result["edges"] == [(1, 2)]

    # adjacency relationships should be created
    result2 = knowledge_graph.build_knowledge_graph(['A','B','C'])
    assert result2['edges'] == [('A', 'B'), ('B', 'C')]

    # utility functions
    g = {"nodes": ["x"], "edges": []}
    knowledge_graph.add_node(g, "y")
    assert "y" in g["nodes"]
    knowledge_graph.add_edge(g, "x", "y")
    assert ("x","y") in g["edges"]
    adj = knowledge_graph.adjacency_list(g)
    assert adj["x"] == ["y"]


def test_bulk_import_stub():
    assert bulk_import.import_entities_bulk("/no/such/file") == 0

    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as tf:
        tf.write("one\ntwo\nthree\n")
        fname = tf.name
    assert bulk_import.import_entities_bulk(fname) == 3

    # comma separated values counted appropriately
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as tf2:
        tf2.write("a,b,c\n")
        fname2 = tf2.name
    assert bulk_import.import_entities_bulk(fname2) == 3

    # JSON array support
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as tf3:
        tf3.write("[1,2,3,4]")
        fname3 = tf3.name
    assert bulk_import.import_entities_bulk(fname3) == 4


def test_rca_stub():
    r = rca.generate_rca("issue happened during call")
    assert r.startswith("RCA draft")
    assert "issue" in r
