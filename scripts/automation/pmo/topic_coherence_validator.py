#!/usr/bin/env python3
##############################################################################
# 🎯 Topic Coherence Validator - Ruthless Quality Enforcement
# Purpose: Measure how well an issue fits its current milestone (0-1 score)
# Returns coherence score: 1.0 = perfect match, 0.5 = questionable, 0.0 = wrong
# Session: 20260218-10X-MILESTONE-ENFORCER
# Issue: #3459
# FedRAMP: [NIST-PM-5] Project Management with automated governance
# Usage: echo "$ISSUE_JSON" | python3 topic_coherence_validator.py
# Input JSON: {issue_number, title, body, labels, current_milestone_id, current_milestone_title}
##############################################################################

import json
import os
import re
import sys
from typing import Any

# Add parent directory to path for lib access
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.join(SCRIPT_DIR, "..", "lib")
sys.path.insert(0, LIB_DIR)

# Load milestone rules
RULES_FILE = os.path.join(SCRIPT_DIR, "../../.github/milestone-rules.yml")
if not os.path.exists(RULES_FILE):
    RULES_FILE = os.path.join(SCRIPT_DIR, "../../.github/milestone_rules.yaml")


class TopicCoherenceValidator:
    """Measures topic coherence: how well does an issue fit its current milestone?"""

    def __init__(self, rules_file: str = RULES_FILE):
        self.rules = self._load_rules(rules_file)
        self.milestone_rules = {}
        self._index_milestones()

    def _load_rules(self, rules_file: str) -> dict[str, Any]:
        """Load milestone rules from YAML."""
        try:
            import yaml

            with open(rules_file) as f:
                return yaml.safe_load(f) or {}
        except Exception as e:
            sys.stderr.write(f"Warning: Could not load rules ({e}), using defaults\n")
            return {}

    def _index_milestones(self):
        """Build milestone ID -> rules mapping."""
        if "milestones" not in self.rules:
            return

        for milestone in self.rules.get("milestones", []):
            mid = str(milestone.get("id", ""))
            if mid:
                self.milestone_rules[mid] = milestone

    def validate_coherence(self, issue: dict[str, Any]) -> dict[str, Any]:
        """Calculate coherence score for an issue within its current milestone.

        Returns:
        {
            "coherence_score": 0.0-1.0,  # 1.0 = perfect fit, 0.5 = questionable, 0.0 = wrong
            "is_coherent": bool,          # True if score >= 0.70
            "confidence": float,          # How confident we are about misplacement
            "reason": str,                # Explanation of score
            "recommendation": {
                "action": "keep" | "review" | "reassign",
                "alternative_milestone": str or null,
                "reasoning": str
            },
            "metrics": {
                "keyword_match": 0.0-1.0,
                "label_match": 0.0-1.0,
                "title_pattern_match": 0.0-1.0,
                "body_pattern_match": 0.0-1.0
            }
        }

        """
        number = issue.get("issue_number", issue.get("number", 0))
        title = issue.get("title", "").lower()
        body = issue.get("body", "").lower() if issue.get("body") else ""
        labels = [l.lower() for l in issue.get("labels", [])]
        current_mid = str(issue.get("current_milestone_id", issue.get("current_milestone", "")))

        # Get rules for current milestone
        if not current_mid or current_mid not in self.milestone_rules:
            return {
                "coherence_score": 0.5,
                "is_coherent": False,
                "confidence": 0.6,
                "reason": "Milestone rules not found",
                "recommendation": {
                    "action": "review",
                    "alternative_milestone": None,
                    "reasoning": "Cannot validate coherence without known rules",
                },
                "metrics": {
                    "keyword_match": 0.0,
                    "label_match": 0.0,
                    "title_pattern_match": 0.0,
                    "body_pattern_match": 0.0,
                },
            }

        milestone_rule = self.milestone_rules[current_mid]

        # Score each matching dimension
        metrics = self._calculate_metrics(title, body, labels, milestone_rule)

        # Composite coherence score (weighted average)
        coherence = (
            metrics["keyword_match"] * 0.35
            + metrics["label_match"] * 0.30
            + metrics["title_pattern_match"] * 0.20
            + metrics["body_pattern_match"] * 0.15
        )

        # Determine if coherent (>= 0.70 = good fit, 0.50-0.70 = questionable, < 0.50 = bad)
        is_coherent = coherence >= 0.70
        confidence = min(1.0, coherence + 0.1)  # Add confidence boost

        # Determine recommendation
        if coherence >= 0.85:
            action = "keep"
            reason = "Excellent fit - issue is well-organized in this milestone"
        elif coherence >= 0.70:
            action = "keep"
            reason = "Good fit - issue aligns with milestone theme"
        elif coherence >= 0.50:
            action = "review"
            reason = "Questionable fit - issue may belong in different milestone, needs validation"
        else:
            action = "reassign"
            reason = "Poor fit - issue is misaligned with current milestone, should be reassigned"

        # Find better alternative if low coherence
        alternative = None
        if action in ["review", "reassign"]:
            alternative = self._find_better_fit(title, body, labels, current_mid)

        return {
            "coherence_score": round(coherence, 3),
            "is_coherent": is_coherent,
            "confidence": round(confidence, 3),
            "reason": reason,
            "recommendation": {
                "action": action,
                "alternative_milestone": alternative,
                "reasoning": f"Coherence score {round(coherence, 2)} suggests {action.upper()}",
            },
            "metrics": metrics,
            "issue_number": number,
        }

    def _calculate_metrics(
        self, title: str, body: str, labels: list[str], milestone_rule: dict[str, Any]
    ) -> dict[str, float]:
        """Calculate individual matching metrics."""
        keywords = milestone_rule.get("keywords", [])
        label_patterns = milestone_rule.get("labels", [])
        title_patterns = milestone_rule.get("title_patterns", [])
        body_patterns = milestone_rule.get("body_patterns", [])

        # Keyword matching
        keyword_match = self._match_keywords(title + " " + body, keywords)

        # Label matching
        label_match = self._match_labels(labels, label_patterns)

        # Title pattern matching
        title_patterns_match = self._match_patterns(title, title_patterns)

        # Body pattern matching
        body_patterns_match = self._match_patterns(body, body_patterns)

        return {
            "keyword_match": round(keyword_match, 3),
            "label_match": round(label_match, 3),
            "title_pattern_match": round(title_patterns_match, 3),
            "body_pattern_match": round(body_patterns_match, 3),
        }

    def _match_keywords(self, text: str, keywords: list[str]) -> float:
        """Score keyword matching (0-1)."""
        if not keywords:
            return 0.0

        text_lower = text.lower()
        matches = sum(1 for kw in keywords if kw.lower() in text_lower)
        return min(1.0, matches / len(keywords)) if keywords else 0.0

    def _match_labels(self, labels: list[str], label_patterns: list[str]) -> float:
        """Score label matching (0-1)."""
        if not label_patterns:
            return 0.0

        labels_lower = [l.lower() for l in labels]
        matches = sum(1 for lp in label_patterns if lp.lower() in labels_lower)
        return min(1.0, matches / len(label_patterns)) if label_patterns else 0.0

    def _match_patterns(self, text: str, patterns: list[str]) -> float:
        """Score regex pattern matching (0-1)."""
        if not patterns:
            return 0.0

        text_lower = text.lower()
        matches = 0
        for pattern in patterns:
            try:
                if re.search(pattern.lower(), text_lower):
                    matches += 1
            except re.error:
                # Invalid regex, skip
                pass

        return min(1.0, matches / len(patterns)) if patterns else 0.0

    def _find_better_fit(self, title: str, body: str, labels: list[str], current_mid: str) -> str:
        """Find a better-fitting milestone using rules engine."""
        try:
            # Temporarily run rules engine to find better fit
            from milestone_rules_engine import MilestoneRulesEngine

            issue_json = {
                "number": 0,
                "title": title,
                "body": body,
                "labels": [{"name": l} for l in labels],
            }

            engine = MilestoneRulesEngine(RULES_FILE)
            result = engine.classify(issue_json, threshold=0.70)

            if result and result.get("milestone_id") and result["milestone_id"] != current_mid:
                return f"#{result['milestone_id']} ({result.get('milestone_title', 'Unknown')})"

            return None
        except Exception:
            return None


def main():
    """Process stdin JSON."""
    try:
        issue_json = json.load(sys.stdin)

        validator = TopicCoherenceValidator()
        result = validator.validate_coherence(issue_json)

        print(json.dumps(result, indent=2))
        sys.exit(0)

    except json.JSONDecodeError as e:
        sys.stderr.write(f"Invalid JSON: {e}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
