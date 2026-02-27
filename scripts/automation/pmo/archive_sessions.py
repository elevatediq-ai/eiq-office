#!/usr/bin/env python3
import json
import os
import re

# Configuration
WORKSPACE_ROOT = "/home/akushnir/ElevatedIQ-Mono-Repo"
DOCS_DIR = os.path.join(WORKSPACE_ROOT, "docs/management")
ARCHIVE_DIR = os.path.join(DOCS_DIR, "_archived/sessions")
SESSION_LOGS_FILE = os.path.join(DOCS_DIR, "SESSION_LOGS.md")
REGISTRY_FILE = os.path.join(ARCHIVE_DIR, "registry.json")


def ensure_dirs():
    """ensure_dirs function."""
    if not os.path.exists(ARCHIVE_DIR):
        os.makedirs(ARCHIVE_DIR)


def parse_sessions(content):
    """parse_sessions function."""
    # Regex to catch the session markers
    # Matches: ## [ANY STATUS] SESSION: [ID]
    pattern = r"(## .*? SESSION: ([\w\-]+).*?)(?=\n## |$)"
    matches = re.finditer(pattern, content, re.DOTALL)

    sessions = []
    for match in matches:
        full_text = match.group(1).strip()
        session_id = match.group(2).strip()

        # Extract date/status/etc (basic parsing)
        date_match = re.search(r"\*\*Date\*\*: ([\d\-]+)", full_text)
        status_match = re.search(r"\*\*Status\*\*: (.*)", full_text)

        sessions.append(
            {
                "id": session_id,
                "date": date_match.group(1) if date_match else "unknown",
                "status": status_match.group(1).strip() if status_match else "unknown",
                "content": full_text,
            }
        )
    return sessions


def archive_sessions():
    """archive_sessions function."""
    ensure_dirs()

    if not os.path.exists(SESSION_LOGS_FILE):
        print(f"Error: {SESSION_LOGS_FILE} not found.")
        return

    print(f"Reading {SESSION_LOGS_FILE}...")
    with open(SESSION_LOGS_FILE) as f:
        content = f.read()

    sessions = parse_sessions(content)
    print(f"Parsed {len(sessions)} sessions.")

    registry = []
    if os.path.exists(REGISTRY_FILE):
        with open(REGISTRY_FILE) as f:
            registry = json.load(f)

    existing_ids = {s["id"] for s in registry}

    count = 0
    for s in sessions:
        if s["id"] not in existing_ids:
            # Save individual MD file
            archive_path = os.path.join(ARCHIVE_DIR, f"{s['id']}.md")
            with open(archive_path, "w") as f:
                f.write(f"# Session Archive: {s['id']}\n\n{s['content']}")

            # Add to registry
            registry.append(
                {
                    "id": s["id"],
                    "date": s["date"],
                    "status": s["status"],
                    "path": f"docs/management/_archived/sessions/{s['id']}.md",
                }
            )
            existing_ids.add(s["id"])
            count += 1

    # Sort registry by date desc
    registry.sort(key=lambda x: x["date"], reverse=True)

    with open(REGISTRY_FILE, "w") as f:
        json.dump(registry, f, indent=2)

    print(f"Archived {count} new sessions. Total in registry: {len(registry)}")

    # Truncate SESSION_LOGS.md to keep only most recent ones (e.g., top 10)
    # But since we're in Extreme Solo execution, let's keep it very lean.
    truncated_content = "# Copilot Session Logs & Chat History\n\n"
    truncated_content += "> 📚 **Archive Note**: This file has been truncated for performance. "
    truncated_content += "Older sessions are archived in `docs/management/_archived/sessions/`.\n\n"

    # Take the first 5 sessions from the parsed list (assuming they are at the top)
    for s in sessions[:5]:
        truncated_content += s["content"] + "\n\n---\n\n"

    with open(SESSION_LOGS_FILE, "w") as f:
        f.write(truncated_content)

    print(f"Truncated {SESSION_LOGS_FILE} to top 5 sessions.")


if __name__ == "__main__":
    archive_sessions()
