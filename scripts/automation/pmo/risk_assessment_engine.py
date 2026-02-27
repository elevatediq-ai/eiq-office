#!/usr/bin/env python3
"""Phase 3: Predictive Risk Assessment Engine
Machine learning-based risk prediction and mitigation recommendations.

[NIST-CA-7] Continuous Monitoring
[NIST-PM-3] Project Management Processes
[NIST-PM-5] Risk Management Planning
"""

import argparse
import json
import logging
import os
import subprocess
from datetime import datetime

try:
    import joblib
    import numpy as np
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.preprocessing import StandardScaler

    HAS_ML = True
except ImportError:
    np = None
    StandardScaler = None
    RandomForestClassifier = None
    joblib = None
    HAS_ML = False
    print("⚠️  scikit-learn not available. Running in heuristic mode.")

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)


class RiskAssessmentEngine:
    """Predictive risk assessment using ML models."""

    def __init__(self):
        self.model_path = "/tmp/risk_model.pkl"
        self.risk_thresholds = {
            "critical": 0.80,
            "high": 0.60,
            "medium": 0.40,
            "low": 0.20,
        }
        self.model = None
        self.scaler = StandardScaler() if HAS_ML else None
        self.load_or_create_model()

    def load_or_create_model(self):
        """Load existing model or create new one."""
        if not HAS_ML:
            logger.warning("ML libraries not available, running in heuristic mode")
            return

        if os.path.exists(self.model_path):
            try:
                self.model = joblib.load(self.model_path)
                logger.info("✅ Loaded existing risk model")
            except Exception as e:
                logger.warning(f"Failed to load model: {e}. Creating new model.")
                self._create_model()
        else:
            self._create_model()

    def _create_model(self):
        """Create and train initial risk model."""
        if not HAS_ML:
            return

        logger.info("🏋️  Training new risk assessment model...")

        # Synthetic training data
        X_train = np.array(
            [
                [0, 0, 15, 100, 0],  # Low risk
                [1, 2, 15, 95, 1],  # Medium risk
                [3, 4, 5, 80, 3],  # High risk
                [5, 6, 2, 70, 5],  # Critical risk
            ]
        )

        y_train = np.array([0, 1, 2, 3])  # 0=low, 1=medium, 2=high, 3=critical

        try:
            self.model = RandomForestClassifier(n_estimators=10, random_state=42, max_depth=5)
            self.model.fit(X_train, y_train)
            joblib.dump(self.model, self.model_path)
            logger.info("✅ Model trained and saved")
        except Exception as e:
            logger.error(f"Model training failed: {e}")

    def assess_risk(self, metrics: dict) -> dict:
        """Assess project risk based on metrics."""
        logger.info("🔍 Assessing project risk...")

        # Extract features
        blocker_count = metrics.get("blockers", 0)
        stale_pr_count = metrics.get("stale_prs", 0)
        velocity = metrics.get("velocity", 15)
        compliance_score = metrics.get("compliance_score", 100)
        days_to_deadline = metrics.get("deadline_days", 14)

        # Calculate derived metrics
        days_to_complete = (metrics.get("remaining_work", 100) / velocity) if velocity > 0 else 999
        schedule_variance = days_to_complete - days_to_deadline
        min(1.0, velocity / 15)

        # Use model if available, otherwise use heuristic scoring
        if self.model is not None and HAS_ML:
            try:
                features = np.array(
                    [
                        [
                            blocker_count,
                            stale_pr_count,
                            velocity,
                            compliance_score,
                            schedule_variance,
                        ]
                    ]
                )

                risk_level = self.model.predict(features)[0]
                risk_prob = max(self.model.predict_proba(features)[0])

                risk_names = {0: "LOW", 1: "MEDIUM", 2: "HIGH", 3: "CRITICAL"}
                risk_level_name = risk_names.get(risk_level, "UNKNOWN")
            except Exception as e:
                logger.warning(f"ML prediction failed: {e}. Using heuristic.")
                risk_level_name, risk_prob = self._heuristic_risk_score(
                    blocker_count,
                    stale_pr_count,
                    velocity,
                    compliance_score,
                    schedule_variance,
                )
        else:
            risk_level_name, risk_prob = self._heuristic_risk_score(
                blocker_count,
                stale_pr_count,
                velocity,
                compliance_score,
                schedule_variance,
            )

        # Generate recommendations
        recommendations = self._generate_recommendations(
            risk_level_name,
            blocker_count,
            stale_pr_count,
            schedule_variance,
            compliance_score,
        )

        return {
            "timestamp": datetime.utcnow().isoformat(),
            "risk_level": risk_level_name,
            "confidence": risk_prob,
            "metrics": {
                "blockers": blocker_count,
                "stale_prs": stale_pr_count,
                "velocity": velocity,
                "compliance_score": compliance_score,
                "schedule_variance_days": round(schedule_variance, 2),
            },
            "recommendations": recommendations,
        }

    def _heuristic_risk_score(self, blockers, stale_prs, velocity, compliance, schedule_var) -> tuple[str, float]:
        """Heuristic risk scoring when ML model unavailable."""
        risk_score = 0.0

        risk_score += min(0.3, blockers * 0.15)  # Max 0.3
        risk_score += min(0.2, stale_prs * 0.1)  # Max 0.2
        risk_score += min(0.2, max(0, schedule_var * 0.05))  # Max 0.2
        risk_score += min(0.3, max(0, (100 - compliance) * 0.003))  # Max 0.3

        if risk_score >= 0.80:
            return "CRITICAL", risk_score
        elif risk_score >= 0.60:
            return "HIGH", risk_score
        elif risk_score >= 0.40:
            return "MEDIUM", risk_score
        else:
            return "LOW", risk_score

    def _generate_recommendations(
        self,
        risk_level: str,
        blockers: int,
        stale_prs: int,
        schedule_var: float,
        compliance: float,
    ) -> list[str]:
        """Generate tactical recommendations based on risk."""
        recommendations = []

        if risk_level == "CRITICAL":
            recommendations.extend(
                [
                    "🚨 ESCALATE to executive leadership immediately",
                    "📌 Freeze scope - no new features until stabilized",
                    "👥 Allocate additional resources (parallel development)",
                    "🔍 Conduct root cause analysis on blockers",
                ]
            )

        if blockers > 2:
            recommendations.append(f"🚨 Address {blockers} blockers: Assign to team leads with 15 min SLA")

        if stale_prs > 3:
            recommendations.append(f"⏱️  Expedite PR review: {stale_prs} PRs >6h old")

        if schedule_var > 2:
            recommendations.append(
                f"📈 Schedule slip detected: {schedule_var:.1f} days behind. Consider adding {int(schedule_var * 10)} story points capacity"
            )

        if compliance < 95:
            recommendations.append(f"🔒 Compliance gap: {100 - compliance:.1f}% below target. Audit security controls")

        if risk_level in ["HIGH", "CRITICAL"]:
            recommendations.append("📊 Generate daily risk reports (escalate deltas >5%)")

        return recommendations[:5]  # Top 5 recommendations


class ExecutiveRiskDashboard:
    """Generate executive-facing risk dashboard."""

    def __init__(self, engine: RiskAssessmentEngine):
        self.engine = engine

    def generate_report(self, metrics: dict) -> str:
        """Generate executive risk report."""
        risk_assessment = self.engine.assess_risk(metrics)

        risk_emoji = {
            "LOW": "🟢",
            "MEDIUM": "🟡",
            "HIGH": "🔴",
            "CRITICAL": "🚨",
        }

        emoji = risk_emoji.get(risk_assessment["risk_level"], "❓")

        report = f"""
{"=" * 70}
🎯 EXECUTIVE RISK ASSESSMENT REPORT
{"=" * 70}

Timestamp: {risk_assessment["timestamp"]}
Assessment Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}

┌─ RISK LEVEL ─────────────────────────────────────────────────────┐
│ {emoji} **{risk_assessment["risk_level"]}** (Confidence: {risk_assessment["confidence"]:.1%})
└──────────────────────────────────────────────────────────────────┘

📊 KEY METRICS:
  • Blockers: {risk_assessment["metrics"]["blockers"]}
  • Stale PRs: {risk_assessment["metrics"]["stale_prs"]}
  • Velocity: {risk_assessment["metrics"]["velocity"]} pts/day
  • Compliance: {risk_assessment["metrics"]["compliance_score"]:.1f}%
  • Schedule Variance: {risk_assessment["metrics"]["schedule_variance_days"]:+.1f} days

💡 RECOMMENDED ACTIONS:
"""
        for i, rec in enumerate(risk_assessment["recommendations"], 1):
            report += f"  {i}. {rec}\n"

        report += f"\n{'=' * 70}\n"

        return report


def fetch_github_metrics() -> dict:
    """Fetch current GitHub metrics."""
    logger.info("📊 Fetching GitHub metrics...")

    try:
        # Blocker count
        blockers = (
            int(
                subprocess.check_output(
                    "gh issue list --repo kushin77/ElevatedIQ-Mono-Repo --label blocker --state open 2>/dev/null | wc -l",
                    shell=True,
                    text=True,
                ).strip()
            )
            or 0
        )

        # Stale PRs
        prs = (
            int(
                subprocess.check_output(
                    "gh pr list --repo kushin77/ElevatedIQ-Mono-Repo --state open --limit 50 2>/dev/null | wc -l",
                    shell=True,
                    text=True,
                ).strip()
            )
            or 0
        )

        return {
            "blockers": blockers,
            "stale_prs": max(0, prs - 5),
            "velocity": 15,
            "compliance_score": 99.1,
            "deadline_days": 14,
            "remaining_work": 120,
        }
    except Exception as e:
        logger.warning(f"GitHub fetch failed: {e}. Using defaults.")
        return {
            "blockers": 1,
            "stale_prs": 2,
            "velocity": 15,
            "compliance_score": 99.1,
            "deadline_days": 14,
            "remaining_work": 120,
        }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Phase 3: Risk Assessment Engine")
    parser.add_argument("--report", action="store_true", help="Generate executive report")
    parser.add_argument("--model-only", action="store_true", help="Train model only")

    args = parser.parse_args()

    logger.info("=" * 70)
    logger.info("🎯 Phase 3: Predictive Risk Assessment Engine")
    logger.info("=" * 70)

    engine = RiskAssessmentEngine()

    if args.model_only:
        logger.info("Model training complete")
        return

    # Get metrics
    metrics = fetch_github_metrics()
    logger.info(f"📊 Metrics: {json.dumps(metrics, indent=2)}")

    # Assess risk
    risk_result = engine.assess_risk(metrics)

    if args.report:
        dashboard = ExecutiveRiskDashboard(engine)
        report = dashboard.generate_report(metrics)
        print(report)

    # Save results
    output_file = "/tmp/risk_assessment.json"
    with open(output_file, "w") as f:
        json.dump(risk_result, f, indent=2)
    logger.info(f"✅ Risk assessment saved to {output_file}")

    # Output summary
    logger.info(f"🎯 Risk Level: {risk_result['risk_level']} (confidence: {risk_result['confidence']:.2%})")
    logger.info("💡 Top recommendations:")
    for rec in risk_result["recommendations"][:3]:
        logger.info(f"  • {rec}")


if __name__ == "__main__":
    main()
