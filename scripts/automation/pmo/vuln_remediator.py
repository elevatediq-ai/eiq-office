#!/usr/bin/env python3
import re
from pathlib import Path

# NIST-SI-2: Flaw Remediation Automation
# Target Safe Versions (Reference: NIST 800-53 | FedRAMP High)
# NOTE: `python-ecdsa` has no upstream timing-side-channel fix; remediation
# for that advisory is handled by removal/replacement (see: #3438).
SAFE_VERSIONS = {
    "fastapi": "0.109.1",
    "uvicorn": "0.27.1",
    "cryptography": "42.0.2",
    "requests": "2.31.0",
    "urllib3": "1.26.18",
    "jinja2": "3.1.3",
    "pillow": "10.3.0",
    "pyyaml": "6.0.1",
    "aiohttp": "3.9.4",
    "idna": "3.7",
    "certifi": "2024.07.04",
    "setuptools": "70.0.0",
    "werkzeug": "3.0.3",
    "flask": "3.0.3",
    "django": "4.2.11",
    "gitpython": "3.1.41",
    "pydantic": "2.6.3",
}


def remediate_requirements(file_path):
    """remediate_requirements function."""
    print(f"[*] Remediating {file_path}...")
    with open(file_path) as f:
        lines = f.readlines()

    new_lines = []
    changes = 0
    for _line in lines:
        line = _line.strip()
        if not line or line.startswith("#"):
            new_lines.append(line + "\n")
            continue

        # Parse package name
        match = re.match(r"^([a-zA-Z0-9_\-]+)", line)
        if match:
            pkg_name = match.group(1).lower()
            if pkg_name in SAFE_VERSIONS:
                safe_ver = SAFE_VERSIONS[pkg_name]
                new_line = f"{pkg_name}>={safe_ver}\n"
                if new_line.strip() != line:
                    print(f"  [+] Updating {pkg_name}: {line} -> {new_line.strip()}")
                    new_lines.append(new_line)
                    changes += 1
                    continue

        new_lines.append(line + "\n")

    if changes > 0:
        with open(file_path, "w") as f:
            f.writelines(new_lines)
    return changes


def main():
    """Main function."""
    root_dir = Path("/home/akushnir/ElevatedIQ-Mono-Repo")
    total_changes = 0

    # Audit all requirements.txt
    for req_file in root_dir.glob("**/requirements.txt"):
        if ".venv" in str(req_file) or "node_modules" in str(req_file):
            continue
        total_changes += remediate_requirements(req_file)

    # Audit pyproject.toml
    for pyproject in root_dir.glob("**/pyproject.toml"):
        if ".venv" in str(pyproject):
            continue
        # For simplicity, we'll just log these for now or use a regex for them too
        print(f"[*] Audit check for {pyproject} (Manual update recommended if complex)")

    print(f"\n[!] Remediation Complete. Total updates: {total_changes}")
    print("[!] NIST-SI-2: Automated Flaw Remediation executed.")


if __name__ == "__main__":
    main()
