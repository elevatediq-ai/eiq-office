import json


def analyze_linkage(issues_file):
    """analyze_linkage function."""
    with open(issues_file) as f:
        data = json.load(f)

    issues = data.get("issues", [])
    orphans = []
    linked_count = 0

    # Mapping of keywords to Epic Numbers
    MAPPING = {
        2103: [
            "security",
            "nist",
            "fedramp",
            "jwt",
            "cert",
            "compliance",
            "lock",
            "secret",
            "encrypt",
            "audit",
            "vuln",
            "hardening",
        ],
        2104: [
            "ai",
            "agent",
            "llm",
            "inference",
            "embedding",
            "vllm",
            "model",
            "prompt",
            "vector",
            "reasoning",
        ],
        2105: [
            "infra",
            "terraform",
            "cloud",
            "aws",
            "gcp",
            "azure",
            "region",
            "cluster",
            "multi-cloud",
            "k8s",
            "destroy",
            "state",
        ],
        2106: [
            "observability",
            "monitor",
            "metric",
            "log",
            "trace",
            "prometheus",
            "grafana",
            "alerting",
            "incident",
            "sre",
            "health",
            "uptime",
        ],
        2107: [
            "test",
            "unit",
            "integration",
            "cypress",
            "pytest",
            "coverage",
            "quality",
            "mock",
        ],
        2108: [
            "cicd",
            "pipeline",
            "deploy",
            "workflow",
            "action",
            "build",
            "automation",
        ],
        2109: [
            "pmo",
            "session",
            "issue",
            "board",
            "planning",
            "dash",
            "management",
            "kpi",
        ],
        2110: [
            "api",
            "graphql",
            "rest",
            "endpoint",
            "gateway",
            "service",
            "mesh",
            "strawberry",
            "fastapi",
            "proxy",
        ],
    }

    results = []

    for issue in issues:
        labels = [l["name"].lower() for l in issue.get("labels", [])]
        body = (issue.get("body") or "").lower()
        title = issue.get("title", "").lower()

        # Check if already linked
        is_linked = any(l.startswith("parent-epic-") for l in labels) or "ref #" in body

        if is_linked:
            linked_count += 1
            continue

        # Try to categorize
        score = {epic_id: 0 for epic_id in MAPPING}
        combined_text = f"{title} {body}"

        for epic_id, keywords in MAPPING.items():
            for kw in keywords:
                if kw in combined_text:
                    score[epic_id] += 1

        # Special Label Mapping
        if "security" in labels:
            score[2103] += 5
        if "infrastructure" in labels:
            score[2105] += 5
        if "ai-native" in labels:
            score[2104] += 5
        if "observability" in labels:
            score[2106] += 5
        if "cicd" in labels:
            score[2108] += 5
        if "api" in labels:
            score[2110] += 5
        if "pmo" in labels:
            score[2109] += 5

        best_match = max(score, key=score.get)
        if score[best_match] > 0:
            results.append(
                {
                    "number": issue["number"],
                    "title": issue["title"],
                    "proposed_epic": best_match,
                    "score": score[best_match],
                }
            )
        else:
            orphans.append({"number": issue["number"], "title": issue["title"]})

    print(
        json.dumps(
            {
                "summary": {
                    "total": len(issues),
                    "linked": linked_count,
                    "proposed": len(results),
                    "remaining_orphans": len(orphans),
                },
                "proposed_links": results,
                "orphans": orphans,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        analyze_linkage(sys.argv[1])
    else:
        print("Usage: python script.py <issues_json>")
