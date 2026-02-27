#!/usr/bin/env python3

"""🚀 ElevatedIQ: Enhancement 4 - Context Preservation Engine.

Saves and restores development session context automatically to/from git.
"""

import json
import logging
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)

logger = logging.getLogger(__name__)


@dataclass
class SessionContext:
    """Represents a development session's context."""

    session_id: str
    start_time: str
    end_time: str | None = None
    duration_minutes: int = 0

    # Current work
    current_issue: str | None = None
    current_file: str | None = None
    line_range: str | None = None
    branch: str = "main"

    # Tasks
    tasks: list[dict] = None

    # Recent commits
    recent_commits: list[dict] = None

    # Open PRs
    open_prs: list[int] = None

    # Decisions made
    decisions: list[str] = None

    # Code snippets discussed
    snippets: dict[str, list[int]] = None

    def __post_init__(self):
        if self.tasks is None:
            self.tasks = []
        if self.recent_commits is None:
            self.recent_commits = []
        if self.open_prs is None:
            self.open_prs = []
        if self.decisions is None:
            self.decisions = []
        if self.snippets is None:
            self.snippets = {}


class ContextPreserver:
    """ContextPreserver class."""

    def __init__(self, repo_root: str = None):
        self.repo_root = (
            repo_root
            or subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.strip()
        )

        self.context_dir = Path(self.repo_root) / "docs" / "management" / "chat_contexts"
        self.context_dir.mkdir(parents=True, exist_ok=True)

    def generate_session_id(self) -> str:
        """Generate unique session ID."""
        return datetime.now().strftime("%Y%m%d-%H%M%S")

    def capture_current_state(self, session_id: str) -> SessionContext:
        """Capture current development state."""
        # Get current branch
        branch = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            cwd=self.repo_root,
            check=False,
        ).stdout.strip()

        # Get recent commits
        recent_commits = (
            subprocess.run(
                ["git", "log", "-10", "--pretty=format:%h:%s"],
                capture_output=True,
                text=True,
                cwd=self.repo_root,
                check=False,
            )
            .stdout.strip()
            .split("\n")
        )

        commits_data = []
        for commit in recent_commits:
            if ":" in commit:
                hash_val, msg = commit.split(":", 1)
                commits_data.append({"hash": hash_val, "message": msg})

        # Get open PRs (if available via gh)
        open_prs = []
        try:
            prs_output = subprocess.run(
                ["gh", "pr", "list", "--state", "open", "--json", "number"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            ).stdout
            if prs_output:
                prs_data = json.loads(prs_output)
                open_prs = [pr["number"] for pr in prs_data]
        except Exception as ex:
            logger.debug("gh not available or timed out: %s", ex)

        # Create context
        context = SessionContext(
            session_id=session_id,
            start_time=datetime.now().isoformat(),
            branch=branch,
            recent_commits=commits_data,
            open_prs=open_prs,
        )

        return context

    def save_context(self, context: SessionContext) -> Path:
        """Save session context to markdown file."""
        context.duration_minutes = int(
            (
                datetime.fromisoformat(context.end_time or datetime.now().isoformat())
                - datetime.fromisoformat(context.start_time)
            ).total_seconds()
            / 60
        )

        # Generate markdown
        markdown = f"""# Session: {context.session_id}

**Date**: {context.start_time[:10]}
**Time**: {context.start_time[11:19]}
**Duration**: {context.duration_minutes} minutes

---

## Current Work

| Property | Value |
|----------|-------|
| Issue | {context.current_issue or "N/A"} |
| Branch | `{context.branch}` |
| File | {context.current_file or "N/A"} |
| Line Range | {context.line_range or "N/A"} |

---

## Tasks

"""

        if context.tasks:
            for i, task in enumerate(context.tasks, 1):
                status_icon = {
                    "completed": "✅",
                    "in-progress": "🔄",
                    "blocked": "⛔",
                    "todo": "📋",
                }.get(task.get("status"), "❓")

                markdown += f"""### {i}. {task.get("title", "Untitled")} {status_icon}

- **Status**: {task.get("status")}
- **Files**: {", ".join(task.get("files", []))}

"""
                if task.get("blocker"):
                    markdown += f"- **Blocker**: {task['blocker']}\n"
        else:
            markdown += "No tasks recorded.\n"

        markdown += "\n---\n\n## Recent Commits\n\n"

        if context.recent_commits:
            for commit in context.recent_commits[:5]:
                markdown += f"- `{commit['hash']}` {commit['message']}\n"

        markdown += "\n---\n\n## Open PRs\n\n"

        if context.open_prs:
            for pr_num in context.open_prs:
                markdown += f"- PR #{pr_num}\n"
        else:
            markdown += "No open PRs.\n"

        markdown += "\n---\n\n## Decisions Made\n\n"

        if context.decisions:
            for decision in context.decisions:
                markdown += f"- {decision}\n"
        else:
            markdown += "No decisions recorded.\n"

        markdown += "\n---\n\n## Code Snippets\n\n"

        if context.snippets:
            for filename, lines in context.snippets.items():
                markdown += f"- {filename} (lines {lines[0]}-{lines[1]})\n"
        else:
            markdown += "No snippets recorded.\n"

        markdown += "\n---\n\n*Auto-saved by PMO Context Preservation*\n"

        # Write file
        context_file = self.context_dir / f"{context.session_id}.md"
        context_file.write_text(markdown)

        print(f"✅ Context saved: {context_file}")
        return context_file

    def load_context(self, session_id: str) -> Path | None:
        """Load and display previous session context."""
        context_file = self.context_dir / f"{session_id}.md"

        if not context_file.exists():
            print(f"❌ Session not found: {session_id}")
            return None

        content = context_file.read_text()
        print(f"\n📂 Loaded Session: {session_id}\n")
        print(content)

        return context_file

    def list_sessions(self, limit: int = 10) -> list[str]:
        """List recent sessions."""
        sessions = sorted(self.context_dir.glob("*.md"), reverse=True)[:limit]

        print(f"\n📋 Recent Sessions (Last {limit})\n")
        for session_file in sessions:
            session_id = session_file.stem
            size = session_file.stat().st_size
            mtime = datetime.fromtimestamp(session_file.stat().st_mtime)

            print(f"  {session_id}  ({size:,} bytes, {mtime.strftime('%Y-%m-%d %H:%M')})")

        return [s.stem for s in sessions]

    def start_session(self) -> SessionContext:
        """Start a new session and save initial context."""
        session_id = self.generate_session_id()
        context = self.capture_current_state(session_id)
        context.end_time = datetime.now().isoformat()
        self.save_context(context)

        print(f"\n✅ Session Started: {session_id}")
        print(f"   Branch: {context.branch}")
        print(f"   Recent commits: {len(context.recent_commits)}")
        print("   Context auto-saved\n")

        return context

    def end_session(self, session_id: str) -> bool:
        """Finalize session on exit."""
        context_file = self.context_dir / f"{session_id}.md"

        if not context_file.exists():
            print(f"⚠️  Session not found: {session_id}")
            return False

        # Update with final state
        content = context_file.read_text()
        content = content.replace(
            "**Duration**:",
            f"**Duration**: (Finalized {datetime.now().strftime('%H:%M')})",
        )
        context_file.write_text(content)

        print(f"✅ Session Finalized: {session_id}")
        return True


def main():
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(description="ElevatedIQ Context Preservation")
    parser.add_argument("--repo", help="Repository root (auto-detected if not provided)")

    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("start", help="Start a new session")
    subparsers.add_parser("list", help="List recent sessions")
    subparsers.add_parser("end", help="End current session").add_argument("session_id")
    subparsers.add_parser("load", help="Load session context").add_argument("session_id")

    args = parser.parse_args()

    preserver = ContextPreserver(args.repo)

    if args.command == "start":
        preserver.start_session()
    elif args.command == "list":
        preserver.list_sessions()
    elif args.command == "end":
        preserver.end_session(args.session_id)
    elif args.command == "load":
        preserver.load_context(args.session_id)
    else:
        print("ℹ️  Context Preservation Engine")
        print("   Automatically saves/restores development session context")
        print("\nUsage:")
        print("   python context-preservation.py start       # Start session")
        print("   python context-preservation.py list        # List sessions")
        print("   python context-preservation.py load ID     # Load session")


if __name__ == "__main__":
    main()
