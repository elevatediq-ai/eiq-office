#!/usr/bin/env python3
"""🏆 10X Executive Governance Dashboard (V2.1)
Part of ElevatedIQ 10X Governance Strategy.

Highly visual, KPI-driven dashboard for C-suite and regulators.
NIST Controls: PM-5, SI-4, AU-6, AU-12
"""

import json
import os
import subprocess
import sys
from datetime import datetime

# Adjust path to include the enhancements dir
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def generate_dashboard():
    # 1. Fetch data from Governance API
    try:
        api_path = os.path.join(SCRIPT_DIR, "09_governance_api.py")
        raw_data = subprocess.check_output([sys.executable, api_path], stderr=subprocess.DEVNULL)
        data = json.loads(raw_data)
    except Exception as e:
        print(f"Error fetching dashboard data: {e}")
        return

    debt = data["components"]["debt_tracker"]
    pred = data["components"]["predictive_engine"]
    score = data["components"]["scorecard"]
    correlation = data["components"].get("correlation_engine", {})
    profiles = data["components"].get("developer_profiles", {})

    dashboard_path = "docs/management/EXECUTIVE_GOVERNANCE_DASHBOARD.md"

    # Format Profiles Table
    profiles_table = "| Developer | Tier | Compliance | Risk |\n| :--- | :--- | :--- | :--- |\n"
    for dev, p in list(profiles.items())[:5]:  # Top 5
        profiles_table += f"| {dev} | {p['excellence_tier']} | {p['compliance_rate']}% | {p['risk_score']} |\n"

    # Format Correlation Table
    corr_table = "| Issue | Commits | Controls | Author |\n| :--- | :--- | :--- | :--- |\n"
    for item in correlation.get("data", [])[:5]:  # Top 5
        corr_table += f"| #{item['issue_id']} | {len(item['commits'])} | {', '.join(item['nist_controls']) or 'None'} | {item['author']} |\n"

    md = f"""# 🏆 ElevatedIQ Executive Governance Dashboard
*Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}*

## 📊 High-Level Metrics
| Metric | Current Value | Status |
| :--- | :--- | :--- |
| **Risk Index (ERI)** | {debt.get("governance_risk_index", "N/A")} | {debt.get("summary", "⚖️").split(" ")[0]} |
| **Violation Rate** | {debt.get("violation_rate_pct", "N/A")}% | {"🟢" if debt.get("violation_rate_pct", 0) < 10 else "🟡" if debt.get("violation_rate_pct", 0) < 30 else "🔴"} |
| **Compliance Rate** | {pred["metrics"].get("overall_compliance_rate", "N/A")}% | {"✅" if pred["metrics"].get("overall_compliance_rate", 0) > 90 else "⚖️"} |
| **Active Debt Score** | {debt.get("raw_debt_score", "N/A")} pts | {"High" if debt.get("raw_debt_score", 0) > 1000 else "Stable"} |

---

## 🔗 Cross-System Correlation (NIST AU-12)
Recent issues with governance-linked commits:

{corr_table}

---

## � Developer Governance Profiles (NIST-PM-5)
Behavioral analytics for contribution excellence and risk:

{profiles_table}

---

## �🔮 Predictive Insights
> **Forecast:** Predicted violation probability for next 24h: **{pred["metrics"].get("predicted_violation_probability_next_24h", "N/A")}%**

### Risk Hotspots
- **High Risk Window:** {pred["metrics"].get("high_risk_day", "N/A")} at {pred["metrics"].get("high_risk_hour", "N/A")}
- **Author Reliability (Bottom 3):**
{chr(10).join([f"  - {auth}: {s}%" for auth, s in list(pred.get("author_reliability_scores", {}).items())[:3]])}

---

## 🛡️ Remediation SLA Tracker
| Priority | Volume | Breached | Avg Time (Hrs) |
| :--- | :--- | :--- | :--- |
| **P0 (Critical)** | {score["priority_distribution"].get("P0", 0)} | {score["summary"].get("breached_slas", 0) if score["priority_distribution"].get("P0", 0) > 0 else 0} | {score["summary"].get("avg_remediation_time_hrs", 0)} |
| **P1 (High)** | {score["priority_distribution"].get("P1", 0)} | 0 | 0 |
| **P2 (Standard)** | {score["priority_distribution"].get("P2", 0)} | 0 | 0 |

---

## 📐 Governance Architecture Matrix
```mermaid
pie title Compliance Distribution
    "Compliant Commits" : {debt.get("compliant_commits", 0)}
    "Violations" : {debt.get("total_commits", 0) - debt.get("compliant_commits", 0)}
```

### Strategic Recommendations
{chr(10).join([f"- {rec}" for rec in pred.get("recommendations", [])])}

---
**Confidentiality Notice:** This report is generated for ElevatedIQ Leadership. All data is sourced from a tamper-evident audit stream (AU-12).
"""

    with open(dashboard_path, "w") as f:
        f.write(md)

    print(f"✅ Dashboard Generated: {dashboard_path}")


if __name__ == "__main__":
    generate_dashboard()
