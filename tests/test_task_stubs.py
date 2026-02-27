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


def test_version_transcript_stub():
    assert transcript_versioning.version_transcript("t", []) == "t"


def test_entity_linking_stub():
    result = entity_linking.link_entities_to_jira("a b")
    assert isinstance(result, dict)
    assert result.get("a") == "JIRA-1"


def test_knowledge_graph_stub():
    result = knowledge_graph.build_knowledge_graph([1, 2])
    assert result["nodes"] == [1, 2]
    assert result["edges"] == []


def test_bulk_import_stub():
    assert bulk_import.import_entities_bulk("/no/such/file") == 0


def test_rca_stub():
    assert rca.generate_rca("whatever").startswith("RCA draft")
