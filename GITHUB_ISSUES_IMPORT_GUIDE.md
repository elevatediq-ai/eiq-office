# OfficeIQ GitHub Issues Import Guide
## How to Implement the 150+ Issue Roadmap

**Purpose:** Script to batch-import all 150+ issues from the PMO breakdown into GitHub  
**Date:** Feb 27, 2026

---

## Quick Start

### Option 1: Manual Import (Best for First 20 Issues)

For each epic, create a GitHub issue manually:

```bash
# EPIC 1.1: Live Transcription Pipeline
gh issue create \
  --title "[EPIC-1.1] Live Transcription Pipeline - Sovereign Meeting Intelligence" \
  --body "
Business Value:
- Zero-friction meeting capture with 99.9% accuracy
- Eliminate Otter.ai dependency
- Sovereign data (on-prem only, no SaaS)

Success Metric:
- <800ms word-to-screen latency
- 250+ concurrent meetings
- 95% word error rate
- 100+ enterprise customers using by Q1 end

Timeline: Q1 (8 weeks)
Budget: $400K
Team Size: 4 FTE

Sub-Issues: 8 detailed tasks (see labels)
" \
  --label "epic,pillar-1,q1,meeting-intelligence" \
  --assignee "akushnir"
```

### Option 2: Bulk Import (Best for Full Roadmap)

Use the `issues-import.json` file (see template below):

```bash
# Prerequisites
npm install -g github-issues-import

# Create issues-import.json with all 150+ issues

gh issues-import import issues-import.json
```

---

## Full Issues Import Template

Create this file: `/home/akushnir/officeIQ/issues-import.json`

```json
{
  "issues": [
    {
      "title": "[EPIC-1.1] Live Transcription Pipeline",
      "body": "# EPIC 1.1: Live Transcription Pipeline\n\n## Business Requirements\n- Accuracy: 95% WER vs Whisper benchmark\n- Latency: <800ms from speech to UI\n- Scale: 250+ concurrent meetings\n- Cost: <$0.10/meeting hour\n\n## Success Criteria\n- 100+ enterprise customers using feature\n- <500ms end-to-end latency\n- Zero security incidents\n\n## Sub-Issues\n- IQ-1.1.1: Whisper GPU worker\n- IQ-1.1.2: WebSocket streaming\n- IQ-1.1.3: Audio queue management\n- IQ-1.1.4: Multi-language detection\n- IQ-1.1.5: OpenAI fallback\n- IQ-1.1.6: Speaker diarization\n- IQ-1.1.7: Transcript aggregation\n- IQ-1.1.8: UI streaming\n\n## Timeline\nQ1 (8 weeks, 4 FTE)\n\n## Owner\n@akushnir (AI/ML Lead)",
      "labels": ["epic", "pillar-1", "q1", "meeting-intelligence"],
      "assignee": "akushnir",
      "milestone": "Q1-2026"
    },
    {
      "title": "[TASK-1.1.1] Implement Whisper Large-V3 GPU worker",
      "body": "## User Story\nAs an Infrastructure Engineer  \nI want to deploy Whisper Large-V3 model on K8s GPU pods  \nSo that we can transcribe audio in real-time with 95% accuracy\n\n## Acceptance Criteria\n- [ ] Model loads in <30s on GPU pod startup\n- [ ] Pod processes 5 concurrent transcription jobs\n- [ ] Exports Prometheus metrics (latency, accuracy, GPU usage)\n- [ ] Fallback to OpenAI API when queue >2min latency\n- [ ] Load test: 20 pods handling 100 concurrent meetings\n- [ ] Model quantization tested (memory optimization)\n\n## Technical Details\n```\nTech Stack: Python, PyTorch, CUDA 12.1, Kubernetes\nModel: Whisper Large-V3 (13B parameters)\nGPU: NVIDIA A100 or V100\nDeployment: K8s pod with GPU requests\nMetrics: Prometheus export to monitoring stack\n```\n\n## Effort Estimate\n8 story points (1 week for 1 engineer)\n\n## Definition of Done\n- [ ] Docker image built & pushed to ECR\n- [ ] K8s deployment manifests created\n- [ ] Load test passed (20 pods, 100 concurrent jobs)\n- [ ] Monitoring alerts configured\n- [ ] Documentation complete\n- [ ] Code review approved\n\n## Dependencies\n- GPU infrastructure provisioned\n- Kubernetes cluster ready\n- ECR repository created\n\n## Related Issues\n- Depends on: IQ-1.1.3 (audio queue management)\n- Blocks: IQ-1.1.7 (transcript aggregation), IQ-1.1.8 (UI)\n\n## Notes\n- Consider model quantization (large-v3 is 13B params)\n- Fallback strategy critical for reliability\n- GPU cost: ~$5-10/month per GPU node",
      "labels": ["task", "epic-1.1", "backend", "ml-infrastructure"],
      "assignee": "backend-ml-engineer-1",
      "milestone": "Q1-2026"
    },
    {
      "title": "[TASK-1.1.2] WebSocket audio streaming from NC Talk",
      "body": "## User Story\nAs a Meeting Participant  \nI want to have a 'Record' button in NC Talk  \nSo that I can start meeting transcription with zero setup\n\n## Acceptance Criteria\n- [ ] Record button visible in NC Talk UI\n- [ ] Click Record → audio streams to transcription pipeline\n- [ ] Audio format: Opus-encoded at 48kHz\n- [ ] Word-level timestamps captured\n- [ ] <100ms latency from speaker to queue\n- [ ] Mobile PWA compatibility\n- [ ] Recording can be started/stopped by any participant\n\n## Technical Details\n```\nTech Stack: JavaScript, WebRTC API, Node.js, WebSocket\nConnection: WebRTC MediaStream → Opus Encoder → WebSocket → transcription queue\nFormat: Audio frames with timestamps\nLatency Target: <100ms from speaker to Whisper worker\n```\n\n## UI/UX\n- Record button in talk header (next to settings)\n- Visual indicator: recording ON/OFF\n- Stop + finalize flow\n- Permissions dialog (microphone access)\n\n## Effort Estimate\n5 story points (1 week for 1 backend engineer)\n\n## Definition of Done\n- [ ] NC Talk iframe bridge implemented\n- [ ] Audio streaming tested with 10+ participants\n- [ ] Timestamp sync verified across participants\n- [ ] Mobile testing complete\n- [ ] Performance profiling (<100ms latency)\n- [ ] Code review approved\n\n## Dependencies\n- Depends on: NC Talk API documentation\n- Blocks: IQ-1.1.1 (Whisper worker), IQ-1.1.3 (queue)\n\n## Notes\n- Coordinate with NC Talk team on API changes\n- Consumer browser audio API variations (Safari vs Chrome)\n- Permissions handling differs by browser",
      "labels": ["task", "epic-1.1", "backend", "frontend"],
      "assignee": "backend-engineer-1",
      "milestone": "Q1-2026"
    }
  ]
}
```

---

## Creating Issues Programmatically

### Python Script (Recommended)

Create: `/home/akushnir/officeIQ/scripts/import_issues.py`

```python
#!/usr/bin/env python3
"""
Bulk import GitHub issues from JSON configuration
Usage: python import_issues.py --org kushin77 --repo OfficeIQ --file issues.json
"""

import json
import argparse
from github import Github
from github import GithubException
import sys

def load_issues_config(filename):
    """Load issues from JSON file"""
    with open(filename, 'r') as f:
        return json.load(f)

def create_epic_issue(repo, epic_config):
    """Create an epic issue"""
    try:
        issue = repo.create_issue(
            title=epic_config['title'],
            body=epic_config['body'],
            labels=epic_config.get('labels', []),
            assignee=epic_config.get('assignee')
        )
        print(f"✅ Created: {issue.number} - {epic_config['title']}")
        return issue
    except GithubException as e:
        print(f"❌ Error creating {epic_config['title']}: {e}")
        return None

def link_sub_issue(sub_issue, epic_issue):
    """Link a sub-issue to an epic (if supported)"""
    # Note: GitHub Issues don't have explicit parent-child relationships
    # Use titles/prefixes and labels instead
    # Alternative: Use GitHub Projects for hierarchy
    pass

def main():
    parser = argparse.ArgumentParser(description='Import GitHub issues')
    parser.add_argument('--org', required=True, help='GitHub organization')
    parser.add_argument('--repo', required=True, help='GitHub repository')
    parser.add_argument('--file', default='issues-import.json', help='Issues JSON file')
    parser.add_argument('--token', help='GitHub token (or use GITHUB_TOKEN env var)')
    
    args = parser.parse_args()
    
    # Authentication
    import os
    token = args.token or os.getenv('GITHUB_TOKEN')
    if not token:
        print("Error: GitHub token required (set GITHUB_TOKEN env var)")
        sys.exit(1)
    
    # Connect to GitHub
    g = Github(token)
    repo = g.get_user(args.org).get_repo(args.repo)
    
    # Load issues config
    config = load_issues_config(args.file)
    
    print(f"\n📋 Importing {len(config['issues'])} issues into {args.org}/{args.repo}")
    print("=" * 60)
    
    created_issues = []
    for issue_config in config['issues']:
        issue = create_epic_issue(repo, issue_config)
        if issue:
            created_issues.append(issue)
            # Rate limiting: sleep between requests
            import time
            time.sleep(1)
    
    print("=" * 60)
    print(f"\n✅ Successfully created {len(created_issues)} issues")
    print("\nNext steps:")
    print("1. Review issues in GitHub UI")
    print("2. Organize into milestones (Q1, Q2, Q3, Q4)")
    print("3. Assign to team members")
    print("4. Start sprint planning")

if __name__ == '__main__':
    main()
```

**Install dependencies:**
```bash
pip install PyGithub
export GITHUB_TOKEN="your_github_token"
```

**Run import:**
```bash
cd /home/akushnir/officeIQ
python scripts/import_issues.py --org kushin77 --repo OfficeIQ --file issues-import.json
```

---

## GitHub Project Board Setup

### Create Project Boards for Each Pillar

```bash
# PILLAR 1: Meeting Intelligence
gh project create --owner kushin77 --title "Pillar 1: Meeting Intelligence" --format table

# PILLAR 2: Documents
gh project create --owner kushin77 --title "Pillar 2: Sovereign Documents" --format table

# PILLAR 3: Messaging
gh project create --owner kushin77 --title "Pillar 3: Unified Collaboration" --format table

# PILLAR 4: Humanizer
gh project create --owner kushin77 --title "Pillar 4: AI Personalization" --format table

# Infrastructure
gh project create --owner kushin77 --title "Infra: Security & Reliability" --format table
```

### Organize with Labels

```bash
# Create labels
gh label create epic --color 0075ca --description "Epics (6-12 week efforts)"
gh label create task --color 5319e7 --description "Individual tasks (1-2 week)"
gh label create bug --color d73a4a --description "Production bugs"
gh label create enhancement --color a2eeef --description "Feature enhancement"

# Pillar labels
gh label create pillar-1 --color 1f6feb --description "Meeting Intelligence"
gh label create pillar-2 --color 238636 --description "Documents"
gh label create pillar-3 --color 2ea043 --description "Messaging"
gh label create pillar-4 --color a371f7 --description "Humanizer"
gh label create infra --color 8250df --description "Infrastructure"

# Quarterly labels
gh label create q1 --color ffd60a --description "Q1 2026"
gh label create q2 --color fec614 --description "Q2 2026"
gh label create q3 --color ffb612 --description "Q3 2026"
gh label create q4 --color fb8500 --description "Q4 2026"

# Priority labels
gh label create p0 --color ff0000 --description "Critical (blocking)"
gh label create p1 --color ff6600 --description "High (required)"
gh label create p2 --color ffcc00 --description "Medium (nice-to-have)"
gh label create p3 --color cccccc --description "Low (backlog)"
```

---

## Milestone Setup

```bash
# Create milestones for each quarter
gh milestone create \
  --title "Q1 2026 (Jan-Mar)" \
  --description "Phase 1: Prove the Differentiation" \
  --due-date "2026-03-31"

gh milestone create \
  --title "Q2 2026 (Apr-Jun)" \
  --description "Phase 2: Achieve Feature Parity" \
  --due-date "2026-06-30"

gh milestone create \
  --title "Q3 2026 (Jul-Sep)" \
  --description "Phase 3: Own the Category" \
  --due-date "2026-09-30"

gh milestone create \
  --title "Q4 2026 (Oct-Dec)" \
  --description "Phase 4: Market Dominance" \
  --due-date "2026-12-31"
```

---

## Sample GitHub Issue Templates

### Create `.github/ISSUE_TEMPLATE/epic.md`:

```markdown
---
name: Epic
about: 6-12 week major initiative
title: "[EPIC] "
labels: epic
---

## Business Requirements

### Problem Statement


### Success Criteria
- [ ] Criteria 1
- [ ] Criteria 2

### OKRs
- O: [Objective]
  - KR1: [Key Result 1]
  - KR2: [Key Result 2]

## Technical Specifications

### Architecture
```
[ASCII diagram]
```

### Components

#### Component 1
- **Description:**
- **Tech Stack:**
- **AC:**

## Rollout Plan

### Phase 1: Alpha

### Phase 2: Beta

### Phase 3: GA

## Success Dashboard

| Metric | Target |
|--------|--------|
| | |

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|

## Resources Allocated

## Questions & Decisions
```

### Create `.github/ISSUE_TEMPLATE/task.md`:

```markdown
---
name: Task
about: 1-2 week individual task
title: "[TASK] "
labels: task
---

## User Story

As a [role]
I want to [action]
So that [benefit]

## Acceptance Criteria

- [ ] Criteria 1
- [ ] Criteria 2

## Technical Details

```
[Code/Architecture details]
```

## Effort Estimate

[X story points]

## Definition of Done

- [ ] Code written
- [ ] Tests pass
- [ ] Code review approved
- [ ] Deployed to staging
- [ ] Documentation complete

## Dependencies

## Related Issues

## Notes
```

---

## GitHub Actions CI/CD for Issue Automation

Create `.github/workflows/issue-management.yml`:

```yaml
name: Issue Management

on:
  issues:
    types: [opened, labeled, unlabeled, closed]

jobs:
  organize_by_epic:
    runs-on: ubuntu-latest
    if: contains(github.event.issue.labels.*.name, 'epic')
    steps:
      - name: Add to Epic Project
        uses: actions/github-script@v6
        with:
          script: |
            github.rest.projects.createCard({
              column_id: process.env.EPIC_COLUMN_ID,
              content_id: context.issue.id,
              content_type: 'Issue'
            })
```

---

## Team Workflow

### Sprint Planning (Bi-weekly)

1. **Review backlog:** Issues in milestone for next sprint
2. **Estimate:** Assign story points
3. **Assign:** Team members claim issues
4. **Standup:** Daily 15min to sync progress
5. **Retro:** End of sprint (2 weeks) to reflect

### GitHub Commits Linking to Issues

```bash
# When committing code, reference issue
git commit -m "Implement Whisper GPU worker (#IQ-1.1.1)

- Load model in <30s
- Process 5 concurrent jobs
- Export Prometheus metrics

Fixes #IQ-1.1.1"
```

### PR Review Process

- Require 2 approvals for main branch
- Require tests (90%+ coverage)
- Link PR to issue (#number in description)
- Auto-close issue on PR merge

---

## Usage Tracking & Metrics

### GitHub Actions: Track Issue Completion

```bash
# Generate weekly report
gh issue list --milestone "Q1 2026" --state closed --json number,title | jq 'length'
```

### Monitor Progress Against Plan

```bash
# Total issues in milestone
Total=$(gh issue list --milestone "Q1 2026" --json number | jq 'length')

# Completed
Completed=$(gh issue list --milestone "Q1 2026" --state closed --json number | jq 'length')

# In Progress (has assignee, open)
InProgress=$(gh issue list --milestone "Q1 2026" --state open --json number,assignee | jq '[.[] | select(.assignee != null)] | length')

# Backlog (no assignee, open)
Backlog=$(($Total - $Completed - $InProgress))

echo "Q1 Progress: $Completed/$Total complete ($((Completed*100/Total))%)"
echo "In Progress: $InProgress"
echo "Backlog: $Backlog"
```

---

## Export / Reporting

### Generate Markdown Report

```bash
# Get all closed issues in milestone
gh issue list --milestone "Q1 2026" --state closed --json number,title,assignee,labels > q1_report.json

# Convert to markdown
python -c "
import json
with open('q1_report.json') as f:
    issues = json.load(f)
    print('# Q1 2026 Completion Report\n')
    for issue in issues:
        print(f'- #{issue[\"number\"]}: {issue[\"title\"]} ({issue[\"assignee\"][\"login\"]})')
" > Q1_REPORT.md
```

---

## Next Steps

1. **Setup:** Create GitHub organization + repository
2. **Configuration:** Run issue import script
3. **Planning:** Organize by quarters and milestones
4. **Tracking:** Weekly progress reviews
5. **Execution:** Team adopts workflow

---

*Last Updated: Feb 27, 2026*
