#!/usr/bin/env python3
import re
import sys

import requests

# AI-Powered Governance Classifier
# Tries to hit local Ollama for high-accuracy milestone mapping
# Fallback to heuristic rules if AI is offline

OLLAMA_HOST = "http://localhost:11434"
MODEL = "mistral"  # Default elite model

MILESTONE_MAP = {
    "3": "Project Beta: AI Intelligence",
    "4": "Project Gamma: Infrastructure",
    "5": "Project Delta: Security",
    "6": "Project Sigma: FinOps",
    "9": "Phase 6: Advanced Features",
    "20": "Project Omega: PMO Excellence",
    "27": "Project Zeta: Observability",
    "28": "Project Eta: Backlog",
    "29": "Landing page / Admin Portal",
    "31": "OpenStack Integration",
    "32": "Governance Excellence",
    "33": "Phase 6.3: Deployment & Verification",
    "119": "Infrastructure: Cloud Platforms (GCP/AWS)",
    "120": "Security: NIST/FedRAMP Compliance",
    "121": "Governance Excellence",
    "124": "Infrastructure: IaC & Terraform",
    "125": "Infrastructure: Networking & Connectivity",
    "126": "Infrastructure: Secrets & Key Management",
    "127": "Security: Audit Trail & Detection",
    "128": "Security: Identity & Access Management",
    "129": "DevOps: CI/CD & Automation",
    "44": "Phase 7.0: Next-Gen FinOps & Intelligence",
}

PROMPT_TEMPLATE = """
As a Master PMO Architect, classify the following GitHub Issue into exactly ONE of these Milestone IDs:
- 3: AI/ML, Models, Agents, Inference, Data Science, Intelligence
- 4: Infrastructure, Cloud (AWS/GCP/Azure), Terraform, K8s, Networking, Deployment
- 5: Security, Compliance, NIST, FedRAMP, Encryption, Auth, Vulnerability
- 6: FinOps, Cost Optimization, Billing, Budget
- 9: Advanced Features, Federation, Phase 6, Harmonization
- 20: PMO, Automation, Workflow, SRE, Governance, Project Omega, Elite
- 27: Observability, Monitoring, Logging, Metrics, Alerting
- 28: General Backlog / Unclassified / Triage
- 29: Frontend, Portal, Admin, UI, Landing Page
- 31: OpenStack, On-Premise Cloud
- 32: Governance, Compliance Automation
- 33: Phase 6.3, Deployment, Validation, Readiness
- 119: Multi-cloud platform management (AWS/GCP/Azure)
- 120: Regulatory Compliance, NIST 800-53, FedRAMP, SSP
- 121: Advanced Governance, Policy as Code, Risk Assessment
- 124: Infrastructure as Code, Terraform, HCL
- 125: Networking, VPC, Load Balancer, DNS, Connectivity
- 126: Secrets, Vault, KMS, Encryption, Rotation
- 127: Audit, Logging, Detection, CloudTrail, SIEM
- 128: IAM, RBAC, Identity, Access Management, Zero-trust
- 129: CI/CD, Pipelines, Automation, GitHub Actions, Jenkins
- 44: Phase 7.0, Next-Gen, FinOps Intelligence, ML for Cost

Issue Title: {title}
Issue Body: {body}
Issue Labels: {labels}

Respond only with the Milestone ID (the number).
"""


def classify_heuristically(title, body, labels):  # noqa: PLR0912,PLR0911
    """classify_heuristically function."""
    combined = f"{title} {body} {labels}".lower()

    if re.search(
        r"\b(ai|ml|embedding|inference|model|agent|intelligence|predictive|data.science|neural|llm|openai|langchain)\b",
        combined,
    ):
        return "3"
    if re.search(
        r"\b(infra|terraform|eks|vpc|aws|gcp|azure|kubernetes|k8s|deployment|provision|cluster|docker|container)\b",
        combined,
    ):
        return "4"
    if re.search(
        r"\b(security|compliance|nist|fedramp|auth|encryption|vulnerability|audit|secret|rotator|threat|exploit|cve)\b",
        combined,
    ):
        return "5"
    if re.search(
        r"\b(cost|finops|billing|optimization|budget|saving|remediation|pricing|spend)\b",
        combined,
    ):
        return "6"
    if re.search(
        r"\b(log|monitor|alert|dashboard|metrics|observability|tracing|prometheus|grafana|telemetry)\b",
        combined,
    ):
        return "27"
    if re.search(
        r"\b(phase.6|federation|harmonization|synchronization|discovery|advanced|core)\b",
        combined,
    ):
        return "9"
    if re.search(
        r"\b(pmo|governance|automation|workflow|sprint|sre|sentinel|velocity|omega|elite|10x|tracking|process)\b",
        combined,
    ):
        return "20"
    if re.search(
        r"\b(frontend|portal|admin|ui|landing|react|component|dashboard|web)\b",
        combined,
    ):
        return "29"
    if re.search(r"\b(openstack|nova|neutron|keystone|swift|horizon|on.prem|hybrid)\b", combined):
        return "31"
    if re.search(
        r"\b(phase.6\.3|deployment|validation|readiness|verification|smoke.test)\b",
        combined,
    ):
        return "33"
    if re.search(r"\b(project|organization|multi.cloud|platform|gcp|aws|azure)\b", combined):
        return "35"
    if re.search(r"\b(iac|hcl|workspace|module|state|plan|apply)\b", combined):
        return "36"
    if re.search(
        r"\b(network|subnet|lb|load.balancer|ingress|dns|routing|connectivity|vpn)\b",
        combined,
    ):
        return "37"
    if re.search(r"\b(vault|kms|decryption|rotation|manager|secret)\b", combined):
        return "38"
    if re.search(r"\b(regulatory|ssp|control|assessment)\b", combined):
        return "39"
    if re.search(r"\b(detection|siem|event|cloudtrail)\b", combined):
        return "40"
    if re.search(r"\b(iam|rbac|policy|role|user|permission|identity|cognito|okta)\b", combined):
        return "41"
    if re.search(
        r"\b(cicd|pipeline|action|automation|jenkins|github.actions|workflow)\b",
        combined,
    ):
        return "42"
    if re.search(r"\b(policy.as.code|risk|assessment|control)\b", combined):
        return "43"
    if re.search(r"\b(phase.7|phase.a|ws[1-5]|anomaly|prediction|intelligent)\b", combined):
        return "44"

    return "28"


def classify_ai(title, body, labels):
    """classify_ai function."""
    try:
        prompt = PROMPT_TEMPLATE.format(title=title, body=body, labels=labels)
        response = requests.post(
            f"{OLLAMA_HOST}/api/generate",
            json={"model": MODEL, "prompt": prompt, "stream": False},
            timeout=5,
        )
        if response.status_code == 200:
            result = response.json().get("response", "").strip()
            # Extract digits only
            match = re.search(r"\d+", result)
            if match and match.group(0) in MILESTONE_MAP:
                return match.group(0)
    except Exception:
        pass
    return None


def suggest_milestone(title, body, labels):
    """Ask the AI for a short milestone title suggestion when rules fail."""
    # Compose a concise prompt asking for a 3-6 word milestone title
    prompt = f"Suggest a concise GitHub milestone title (3-6 words) for this issue. Return only the title without punctuation.\n\nTitle: {title}\nBody: {body}\nLabels: {labels}\n"
    try:
        response = requests.post(
            f"{OLLAMA_HOST}/api/generate",
            json={"model": MODEL, "prompt": prompt, "stream": False},
            timeout=6,
        )
        if response.status_code == 200:
            title_suggestion = response.json().get("response", "").strip()
            # sanitize
            title_suggestion = re.sub(r"[^\w \-\.:]", "", title_suggestion)
            return title_suggestion
    except Exception:
        pass
    # Fallback: derive from keywords
    combined = f"{title} {body} {labels}".lower()
    words = re.findall(r"\b([a-z]{4,})\b", combined)
    common = {}
    for w in words:
        common[w] = common.get(w, 0) + 1
    if not common:
        return "Ad-hoc: Misc"
    top = sorted(common.items(), key=lambda x: x[1], reverse=True)[:3]
    suggested = " ".join([w for w, _ in top])
    return f"Ad-hoc: {suggested.title()}"


if __name__ == "__main__":
    # CLI: python ai_classifier.py <title> [body] [labels] [mode]
    if len(sys.argv) < 2:
        print("28")
        sys.exit(0)

    title = sys.argv[1]
    body = sys.argv[2] if len(sys.argv) > 2 else ""
    labels = sys.argv[3] if len(sys.argv) > 3 else ""
    mode = sys.argv[4] if len(sys.argv) > 4 else "classify"

    if mode == "suggest":
        print(suggest_milestone(title, body, labels))
        sys.exit(0)

    # Try AI first
    ai_result = classify_ai(title, body, labels)
    if ai_result:
        print(ai_result)
        sys.exit(0)

    # Fallback to heuristics
    print(classify_heuristically(title, body, labels))
