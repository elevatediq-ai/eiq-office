#!/usr/bin/env python3
import datetime
import json
import subprocess
import sys
from typing import Any


def run_command(command: list[str]) -> str:
    """run_command function."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {' '.join(command)}\n{e.stderr}", file=sys.stderr)
        sys.exit(1)


def get_issues() -> list[dict[str, Any]]:
    """get_issues function."""
    # Fetch issues with relevant fields
    cmd = [
        "gh",
        "issue",
        "list",
        "--repo",
        "kushin77/ElevatedIQ-Mono-Repo",
        "--state",
        "open",
        "--limit",
        "100",
        "--json",
        "number,title,body,labels,createdAt,comments,updatedAt,url",
    ]
    output = run_command(cmd)
    return json.loads(output)


def calculate_score(issue: dict[str, Any]) -> dict[str, Any]:
    """calculate_score function."""
    score = 0
    factors = []

    # 1. Base Priority Score
    labels = [l["name"] for l in issue["labels"]]
    priority_map = {
        "priority: P0": 1000,
        "priority: p0": 1000,
        "priority-p0": 1000,
        "priority: P1": 500,
        "priority: p1": 500,
        "priority-p1": 500,
        "priority: P2": 200,
        "priority: p2": 200,
        "priority-p2": 200,
        "priority: P3": 50,
        "priority: p3": 50,
        "priority-p3": 50,
    }

    base_score = 0
    priority_label = "None"

    for label in labels:
        if label in priority_map:
            base_score = priority_map[label]
            priority_label = label
            break  # Take highest priority found

    if base_score == 0:
        # Default if no priority label
        base_score = 50
        factors.append("Default (No Priority Label)")
    else:
        factors.append(f"Base ({priority_label})")

    score += base_score

    # 2. Type Multipliers
    type_mult = 1.0
    if any("security" in l["name"].lower() for l in issue["labels"]) or "security" in issue["title"].lower():
        type_mult *= 1.5
        factors.append("Security Boost (1.5x)")
    elif any("bug" in l["name"].lower() for l in issue["labels"]):
        type_mult *= 1.2
        factors.append("Bug Boost (1.2x)")

    # 3. Compliance & Strategic Keywords
    keywords = {
        "fedramp": 100,
        "nist": 80,
        "cve": 150,
        "compliance": 70,
        "audit": 60,
        "governance": 60,
        "architecture": 40,
    }

    keyword_score = 0
    content = (issue["title"] + " " + issue["body"]).lower()
    found_keywords = []
    for kw, points in keywords.items():
        if kw in content:
            keyword_score += points
            found_keywords.append(kw)

    if keyword_score > 0:
        factors.append(f"Keywords [{', '.join(found_keywords)}] (+{keyword_score})")
        score += keyword_score

    # 4. Age Factor (Anti-Starvation)
    created_at = datetime.datetime.fromisoformat(issue["createdAt"].replace("Z", "+00:00"))
    now = datetime.datetime.now(datetime.UTC)
    days_open = (now - created_at).days

    age_points = min(days_open * 2, 200)  # Cap at 200 points (100 days)
    if age_points > 0:
        factors.append(f"Age ({days_open} days) (+{age_points})")
        score += age_points

    # 5. Engagement
    comment_count = len(issue["comments"]) if isinstance(issue["comments"], list) else 0  # gh json sometimes varies
    # API actually returns array of comments for --json comments, but let's check structure carefully if needed.
    # Actually 'comments' field in issue list is usually a list of objects.

    engagement_points = min(comment_count * 10, 100)
    if engagement_points > 0:
        factors.append(f"Engagement ({comment_count} comments) (+{engagement_points})")
        score += engagement_points

    # Apply Multiplier
    final_score = score * type_mult

    return {
        "number": issue["number"],
        "title": issue["title"],
        "score": int(final_score),
        "factors": factors,
        "url": issue["url"],
        "labels": labels,
    }


def main():
    """Main function."""
    print("🔍 Fetching open issues from GitHub...")
    issues = get_issues()
    print(f"📋 Found {len(issues)} open issues. Calculating scores...")

    scored_issues = []
    for issue in issues:
        scored_issues.append(calculate_score(issue))

    # Sort by score descending
    scored_issues.sort(key=lambda x: x["score"], reverse=True)

    print("\n" + "=" * 80)
    print("🚀 TOP 10 PRIORITIZED ISSUES (ELITE SCORING MODEL)")
    print("=" * 80)

    for i, issue in enumerate(scored_issues[:10]):
        print(f"{i + 1}. #{issue['number']} - {issue['title']}")
        print(f"   Score: {issue['score']}")
        print(f"   Factors: {', '.join(issue['factors'])}")
        print(f"   Link: {issue['url']}")
        print("-" * 80)

    # Output recommendation for enforcement
    if scored_issues:
        top = scored_issues[0]
        print("\n💥 ENFORCEMENT RECOMMENDATION:")
        print(f"The Next Action MUST be Issue #{top['number']}: {top['title']}")
        print("Run the following command to start work:")
        print(f'./scripts/pmo/session_tracker.sh update issue "Starting work on High Priority Item #{top["number"]}"')


if __name__ == "__main__":
    main()
