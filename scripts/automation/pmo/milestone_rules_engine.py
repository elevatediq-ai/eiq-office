#!/usr/bin/env python3
"""Milestone Rules Engine.

Purpose: Load and apply YAML-based milestone assignment rules
Usage: python3 milestone_rules_engine.py <issue_json>
Output: JSON with milestone ID and confidence score

NIST: PM-5 (Program Management)
Author: PMO Automation
"""

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import yaml


@dataclass
class ClassificationResult:
    """Result of milestone classification."""

    milestone_id: int
    milestone_title: str
    confidence: float
    method: str
    matched_rules: list[str]
    timestamp: str


class MilestoneRulesEngine:
    """Intelligent milestone assignment engine with confidence scoring.

    Features:
    - YAML-based rules (no code changes needed)
    - Multi-factor scoring (keywords, labels, patterns)
    - Confidence thresholds for auto-assignment
    - Audit trail for compliance
    """

    def __init__(self, rules_path: str = None):
        if rules_path is None:
            # Default to .github/milestone-rules.yml in repo root
            script_dir = Path(__file__).parent
            rules_path = script_dir.parent.parent / ".github/milestone-rules.yml"

        self.rules_path = Path(rules_path)
        self.rules = self._load_rules()
        self.settings = self.rules.get("settings", {})
        self.milestones = self.rules.get("milestones", [])
        self.exclusions = self.rules.get("exclusions", {})

    def _load_rules(self) -> dict:
        """Load milestone rules from YAML config."""
        if not self.rules_path.exists():
            raise FileNotFoundError(f"Rules file not found: {self.rules_path}")

        with open(self.rules_path) as f:
            return yaml.safe_load(f)

    def classify(self, issue_data: dict) -> ClassificationResult:
        """Classify an issue and return milestone recommendation.

        Args:
            issue_data: GitHub issue JSON (number, title, body, labels)

        Returns:
            ClassificationResult with milestone ID and confidence

        """
        # Check exclusion rules first
        if self._is_excluded(issue_data):
            return ClassificationResult(
                milestone_id=28,
                milestone_title="Project Eta: Backlog",
                confidence=0.1,
                method="excluded",
                matched_rules=["excluded_by_rules"],
                timestamp=datetime.now(UTC).isoformat() + "Z",
            )

        # Score all milestones
        scores = []
        for milestone in self.milestones:
            score, matched = self._score_milestone(issue_data, milestone)
            if score > 0:
                scores.append((milestone, score, matched))

        # Sort by score (highest first)
        scores.sort(key=lambda x: x[1], reverse=True)

        if not scores:
            # Use fallback milestone
            fallback = self.rules.get("fallback_milestones", [{}])[0]
            result = ClassificationResult(
                milestone_id=fallback.get("id", 20),
                milestone_title="Fallback (PMO)",
                confidence=0.50,
                method="fallback",
                matched_rules=["no_pattern_match"],
                timestamp=datetime.now(UTC).isoformat() + "Z",
            )

            # Try AI for fallback
            ai_milestone = self._classify_with_ai(issue_data)
            if ai_milestone:
                for ms in self.milestones:
                    if ms["id"] == int(ai_milestone):
                        result = ClassificationResult(
                            milestone_id=int(ai_milestone),
                            milestone_title=ms["title"],
                            confidence=0.85,
                            method="ai_fallback",
                            matched_rules=["ai_fallback"],
                            timestamp=datetime.now(UTC).isoformat() + "Z",
                        )
                        break

            return result

        # Return best match
        best_milestone, best_score, matched_rules = scores[0]

        result = ClassificationResult(
            milestone_id=best_milestone["id"],
            milestone_title=best_milestone["title"],
            confidence=best_score,
            method="multi_factor_scoring",
            matched_rules=matched_rules,
            timestamp=datetime.now(UTC).isoformat() + "Z",
        )

        # If confidence is low, try AI classification
        if best_score < 0.8:
            ai_milestone = self._classify_with_ai(issue_data)
            if ai_milestone:
                # Find the milestone title
                for ms in self.milestones:
                    if ms["id"] == int(ai_milestone):
                        result = ClassificationResult(
                            milestone_id=int(ai_milestone),
                            milestone_title=ms["title"],
                            confidence=0.85,  # AI confidence
                            method="ai_classification",
                            matched_rules=["ai_suggestion"],
                            timestamp=datetime.now(UTC).isoformat() + "Z",
                        )
                        break

        return result

    def _is_excluded(self, issue_data: dict) -> bool:
        """Check if issue matches exclusion rules."""
        # Robust label extraction
        issue_labels = []
        for label in issue_data.get("labels", []):
            if isinstance(label, dict):
                issue_labels.append(label.get("name", "").lower())
            elif isinstance(label, str):
                issue_labels.append(label.lower())

        excluded_labels = [l.lower() for l in self.exclusions.get("labels", [])]

        if any(label in excluded_labels for label in issue_labels):
            return True

        # Check excluded keywords
        title = issue_data.get("title", "").lower()
        body = issue_data.get("body", "").lower()
        text = f"{title} {body}"

        excluded_keywords = self.exclusions.get("keywords", [])
        if any(keyword.lower() in text for keyword in excluded_keywords):
            return True

        return False

    def _score_milestone(self, issue_data: dict, milestone: dict) -> tuple[float, list[str]]:
        """Calculate confidence score for a milestone match.

        Scoring factors:
        - Base confidence from rules config
        - Keyword matches (weighted by frequency)
        - Label matches (high weight)
        - Title pattern matches
        - Body pattern matches

        Returns:
            (confidence_score, list_of_matched_rules)

        """
        base_confidence = milestone.get("base_confidence", 0.5)
        matched_rules = []

        # Extract issue data
        title = issue_data.get("title", "").lower()
        body = issue_data.get("body", "").lower()

        # Robust label extraction (handles both string array and object array)
        issue_labels = []
        for label in issue_data.get("labels", []):
            if isinstance(label, dict):
                issue_labels.append(label.get("name", "").lower())
            elif isinstance(label, str):
                issue_labels.append(label.lower())

        ",".join(issue_labels)

        # Proceed with rules-based scoring

        # Initialize score components
        label_score = 0.0
        keyword_score = 0.0
        title_pattern_score = 0.0
        body_pattern_score = 0.0

        # Score label matches (highest weight: 0.4)
        milestone_labels = [label.lower() for label in milestone.get("labels", [])]
        label_matches = sum(1 for label in issue_labels if label in milestone_labels)
        if label_matches > 0:
            label_score = 0.4  # Fixed weight for any label match
            matched_rules.append(f"label_match({label_matches})")

        # Score keyword matches (weight: 0.5 max)
        keywords = [kw.lower() for kw in milestone.get("keywords", [])]
        text = f"{title} {body}"
        keyword_matches = sum(1 for kw in keywords if kw in text)
        if keyword_matches > 0:
            keyword_score = min(keyword_matches * 0.1, 0.5)  # Cap at 0.5
            matched_rules.append(f"keyword_match({keyword_matches})")

        # Score title pattern matches (weight: 0.3)
        title_patterns = milestone.get("title_patterns", [])
        for pattern in title_patterns:
            try:
                if re.search(pattern, title, re.IGNORECASE):
                    title_pattern_score = 0.3
                    matched_rules.append(f"title_pattern({pattern})")
                    break
            except re.error:
                # Invalid regex, skip
                continue

        # Score body pattern matches (weight: 0.2)
        body_patterns = milestone.get("body_patterns", [])
        for pattern in body_patterns:
            try:
                if re.search(pattern, body, re.IGNORECASE):
                    body_pattern_score = 0.2
                    matched_rules.append(f"body_pattern({pattern})")
                    break
            except re.error:
                # Invalid regex, skip
                continue

        # Calculate total score
        total_score = (
            base_confidence * 0.2  # 20% from base confidence
            + label_score
            + keyword_score
            + title_pattern_score
            + body_pattern_score
        )

        # Normalize to 0-1 range
        total_score = min(total_score, 1.0)

        return total_score, matched_rules

    def _classify_with_ai(self, issue_data: dict) -> str:
        """Use AI classifier for low-confidence issues."""
        try:
            title = issue_data.get("title", "")
            body = issue_data.get("body", "")

            # Robust label extraction for AI classifier call
            issue_labels = []
            for label in issue_data.get("labels", []):
                if isinstance(label, dict):
                    issue_labels.append(label.get("name", ""))
                elif isinstance(label, str):
                    issue_labels.append(label)

            labels = ",".join(issue_labels)

            # Call the AI classifier script
            script_path = self.rules_path.parent / "ai_classifier.py"
            result = subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    title,
                    body,
                    labels,
                ],
                capture_output=True,
                text=True,
                timeout=10,
            )

            if result.returncode == 0:
                milestone_id = result.stdout.strip()
                if milestone_id.isdigit():
                    # Validate that the milestone ID is known
                    if any(str(m["id"]) == milestone_id for m in self.milestones):
                        return milestone_id
                    # Also check if it's the fallback
                    if milestone_id in {"28", "20"}:
                        return milestone_id
        except Exception:
            pass
        return None

    def _get_milestone_title(self, milestone_id: int) -> str:
        """Get milestone title by ID."""
        for m in self.milestones:
            if m["id"] == milestone_id:
                return m["title"]
        return "Unknown"

    def should_auto_assign(self, confidence: float) -> bool:
        """Check if confidence is high enough for auto-assignment."""
        threshold = self.settings.get("auto_assign_threshold", 0.95)
        return confidence >= threshold

    def should_flag_for_review(self, confidence: float) -> bool:
        """Check if issue should be flagged for manual review."""
        auto_threshold = self.settings.get("auto_assign_threshold", 0.95)
        review_threshold = self.settings.get("manual_review_threshold", 0.80)
        return review_threshold <= confidence < auto_threshold

    def get_audit_log_entry(self, issue_number: int, result: ClassificationResult) -> dict:
        """Generate audit log entry for compliance."""
        return {
            "timestamp": result.timestamp,
            "issue_number": issue_number,
            "milestone_id": result.milestone_id,
            "milestone_title": result.milestone_title,
            "confidence": result.confidence,
            "method": result.method,
            "matched_rules": result.matched_rules,
            "auto_assigned": self.should_auto_assign(result.confidence),
            "nist_control": "PM-5",
            "system": "milestone_enforcement",
        }


def main():
    """CLI entry point for milestone classification."""
    if len(sys.argv) < 2:
        print("Usage: python3 milestone_rules_engine.py <issue_json>", file=sys.stderr)
        print(
            'Example: echo \'{"number":123,"title":"Security fix","labels":[{"name":"security"}]}\' | python3 milestone_rules_engine.py -',
            file=sys.stderr,
        )
        sys.exit(1)

    # Load issue data from argument or stdin
    if sys.argv[1] == "-":
        issue_data = json.load(sys.stdin)
    else:
        issue_data = json.loads(sys.argv[1])

    # Initialize rules engine
    engine = MilestoneRulesEngine()

    # Classify issue
    result = engine.classify(issue_data)

    # Generate output
    output = {
        "milestone_id": result.milestone_id,
        "milestone_title": result.milestone_title,
        "confidence": round(result.confidence, 4),
        "method": result.method,
        "matched_rules": result.matched_rules,
        "timestamp": result.timestamp,
        "actions": {
            "auto_assign": engine.should_auto_assign(result.confidence),
            "flag_for_review": engine.should_flag_for_review(result.confidence),
            "defer": result.confidence < engine.settings.get("manual_review_threshold", 0.80),
        },
    }

    # Print JSON output
    print(json.dumps(output, indent=2))

    # Log audit entry if enabled
    if engine.rules.get("audit", {}).get("enabled", True):
        audit_entry = engine.get_audit_log_entry(issue_data.get("number", 0), result)

        # Append to audit log
        log_file = Path(engine.rules.get("audit", {}).get("log_file", "logs/pmo/milestone_enforcement_decisions.jsonl"))
        log_file.parent.mkdir(parents=True, exist_ok=True)

        with open(log_file, "a") as f:
            f.write(json.dumps(audit_entry) + "\n")


if __name__ == "__main__":
    main()
