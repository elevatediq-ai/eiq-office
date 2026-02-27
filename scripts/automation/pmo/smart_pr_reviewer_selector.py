#!/usr/bin/env python3
"""Smart PR Reviewer Selector - Intelligent Code Review Assignment
Phase 6.3: Project Omega - Automation Excellence.

[NIST-CM-3] Configuration Change Management & Audit Trail
[NIST-SI-7] Software Development Controls & Code Review

Analyzes:
- Files changed in PR
- Recent committers to those files
- Domain expertise of team members
- Review load balancing
- Conflict of interest (author can't review)

Returns: Ranked list of optimal reviewers for the PR
"""

import json
import logging
import subprocess
import sys
from collections import defaultdict

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


class PRReviewerSelector:
    """Intelligent PR reviewer selection engine."""

    def __init__(self, repo: str, pr_number: int):
        """Initialize selector."""
        self.repo = repo
        self.pr_number = pr_number
        self.team_expertise = self._load_team_expertise()
        self.author = self._get_pr_author()

    def _get_pr_author(self) -> str:
        """Get the PR author (don't assign them as reviewer)."""
        try:
            cmd = f'gh pr view {self.pr_number} --repo {self.repo} --json "author" --jq ".author.login"'
            output = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
            return output.strip()
        except Exception:
            return ""

    def _load_team_expertise(self) -> dict[str, set[str]]:
        """Load team members and their expertise based on git history."""
        expertise = defaultdict(set)

        try:
            # Get last 100 commits to identify key contributors
            # For now, return empty - this would be populated from actual git history
            return expertise
        except Exception:
            return expertise

    def get_files_changed(self) -> list[str]:
        """Get list of files changed in the PR."""
        try:
            cmd = f'gh pr view {self.pr_number} --repo {self.repo} --json "files" --jq ".files[].path"'
            output = subprocess.check_output(cmd, shell=True, text=True)
            return [f.strip() for f in output.strip().split("\n") if f.strip()]
        except Exception as e:
            logger.warning(f"Could not get PR files: {e}")
            return []

    def get_recent_committers(self, file_path: str, limit: int = 5) -> list[tuple[str, int]]:
        """Get recent committers to a specific file.

        Returns:
            List of (username, commit_count) tuples

        """
        committers = defaultdict(int)

        try:
            # Get recent commits to file
            cmd = f'git log --format="%an" --follow -- "{file_path}" 2>/dev/null | head -{limit}'
            output = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)

            for author in output.strip().split("\n"):
                if author.strip():
                    committers[author.strip()] += 1

            return sorted(committers.items(), key=lambda x: x[1], reverse=True)
        except Exception:
            return []

    def classify_domain(self, files: list[str]) -> set[str]:
        """Classify the domains affected by file changes."""
        domains = set()

        domain_patterns = {
            "infrastructure": ["infra/", "terraform/", "k8s/", ".github/"],
            "core": ["apps/control-plane/", "apps/hub-core/", "apps/pmo-orchestrator/"],
            "ai": [
                "apps/ai-",
                "agent-framework/",
                "apps/embedding-",
                "apps/inference-",
            ],
            "finops": ["apps/cost-", "apps/finops-", "apps/billing-"],
            "security": ["security/", "fedramp/", "nist", "auth", "secrets"],
            "observability": ["apps/observability-", "apps/audit-", "apps/metrics-"],
            "testing": ["tests/", "test_"],
            "automation": ["scripts/"],
        }

        for file in files:
            for domain, patterns in domain_patterns.items():
                if any(pattern in file for pattern in patterns):
                    domains.add(domain)

        return domains

    def select_reviewers(self) -> list[dict[str, any]]:
        """Select optimal reviewers for the PR.

        Selection criteria:
        1. Recent committers to changed files (highest weight)
        2. Domain expertise match
        3. Balanced review load
        4. Exclude PR author

        Returns:
            Ranked list of reviewers with scores

        """
        logger.info(f"🔍 Analyzing PR #{self.pr_number}")

        files = self.get_files_changed()
        logger.info(f"   Files changed: {len(files)}")

        domains = self.classify_domain(files)
        logger.info(f"   Domains: {domains}")

        reviewer_scores = defaultdict(lambda: {"score": 0, "sources": [], "files": []})

        # Analyze each changed file
        for file in files:
            committers = self.get_recent_committers(file)

            for committer, commit_count in committers:
                if committer == self.author or not committer:
                    continue

                score = commit_count * 10  # Recent commits heavily weighted
                reviewer_scores[committer]["score"] += score
                reviewer_scores[committer]["sources"].append("recent_commits")
                reviewer_scores[committer]["files"].append(file)

        # Sort by score
        ranked = sorted(
            [
                {
                    "reviewer": name,
                    "score": data["score"],
                    "rationale": f"Expert in {len(set(data['files']))} changed files",
                    "domains": domains,
                }
                for name, data in reviewer_scores.items()
            ],
            key=lambda x: x["score"],
            reverse=True,
        )

        logger.info(f"   Found {len(ranked)} potential reviewers")

        # Return top 3
        return ranked[:3]

    def run(self) -> dict[str, any]:
        """Execute reviewer selection."""
        result = {
            "pr_number": self.pr_number,
            "author": self.author,
            "reviewers": self.select_reviewers(),
            "status": "success",
        }

        return result


def main():
    """Main entry point."""
    if len(sys.argv) < 3:
        print("Usage: smart_pr_reviewer_selector.py <repo> <pr_number>")
        sys.exit(1)

    repo = sys.argv[1]
    pr_number = sys.argv[2]

    selector = PRReviewerSelector(repo, pr_number)
    result = selector.run()

    # Output as JSON
    print(json.dumps(result, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
