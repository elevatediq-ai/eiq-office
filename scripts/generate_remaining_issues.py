#!/usr/bin/env python3
"""
Generate all 140+ sub-issues for OfficeIQ GitHub repository
Pattern-based generation from the PMO breakdown

Usage:
    export GITHUB_TOKEN="ghp_xxxxx"
    python3 generate_remaining_issues.py
"""

import os
import sys
import time
import json
from typing import Dict, List, Tuple

try:
    from github import Github, GithubException
except ImportError:
    print("❌ PyGithub not installed. Install with:")
    print("   pip install PyGithub")
    sys.exit(1)

# ============================================
# EPIC SUB-ISSUE DEFINITIONS
# ============================================

EPIC_ISSUES = {
    # PILLAR 1: MEETING INTELLIGENCE
    
    # Epic 1.1: Live Transcription Pipeline (13 issues)
    1: [
        ("Whisper Large-V3 GPU Worker", 8, "ml-ai,p0-critical"),
        ("WebSocket Audio Streaming from NC Talk", 5, "backend,p0-critical"),
        ("Audio Queue Management & Buffering", 3, "backend,p0-critical"),
        ("Real-time Audio Compression (Opus)", 5, "backend,p1-high"),
        ("Speaker Detection Pre-processing", 3, "ml-ai,p1-high"),
        ("Speaker Diarization (pyannote)", 5, "ml-ai,p0-critical"),
        ("Transcript Persistence to PostgreSQL", 3, "backend,p0-critical"),
        ("Live Transcript UI Streaming (React)", 5, "frontend,p0-critical"),
        ("Confidence Scoring Per Word", 3, "ml-ai,p1-high"),
        ("Multilingual Support (EN, ES, FR, DE)", 5, "ml-ai,p2-medium"),
        ("Websocket Connection Resilience", 3, "backend,p1-high"),
        ("Transcript Versioning & Editing", 3, "backend,p1-high"),
        ("Audio Storage & Archival Strategy", 5, "devops,p1-high"),
    ],
    
    # Epic 1.2: Entity Extraction & Context Linking (12 issues)
    4: [
        ("Custom NER Model Training (IT/PMO)", 8, "ml-ai,p1-high"),
        ("CMDB Asset Database Integration", 6, "backend,p1-high"),
        ("Jira/Azure DevOps Entity Linking", 8, "backend,p1-high"),
        ("Person/Employee Recognition", 5, "ml-ai,p1-high"),
        ("Context Enrichment Pipeline", 5, "backend,p1-high"),
        ("Entity Disambiguation (ambiguous refs)", 5, "ml-ai,p2-medium"),
        ("Knowledge Graph Construction", 8, "backend,p2-medium"),
        ("OpenSearch Entity Index", 5, "devops,p1-high"),
        ("Entity Relationship Extraction", 6, "ml-ai,p2-medium"),
        ("Historical Entity Lookups", 3, "backend,p2-medium"),
        ("Bulk Entity Import Tool", 3, "backend,p3-low"),
        ("Entity Validation & QA", 3, "qa,p2-medium"),
    ],
    
    # Epic 1.3: LLM-Powered Meeting Analysis (14 issues)
    5: [
        ("Deploy Ollama Llama 3.1 70B", 8, "devops,p0-critical"),
        ("Meeting Summary Generation", 8, "ml-ai,p0-critical"),
        ("Root Cause Analysis (RCA) Draft", 8, "ml-ai,p0-critical"),
        ("Action Item Extraction", 5, "ml-ai,p0-critical"),
        ("Decision Log Generation", 5, "ml-ai,p0-critical"),
        ("Meeting Sentiment Analysis", 5, "ml-ai,p1-high"),
        ("Key Topic Extraction", 5, "ml-ai,p1-high"),
        ("Q&A Suggestions Generation", 5, "ml-ai,p2-medium"),
        ("Meeting Coaching/Advice Generation", 5, "ml-ai,p2-medium"),
        ("Follow-up Email Draft", 5, "ml-ai,p1-high"),
        ("Ollama Prompt Optimization", 5, "ml-ai,p1-high"),
        ("LLM Result Caching Strategy", 3, "backend,p2-medium"),
        ("Cost & Token Tracking", 3, "backend,p2-medium"),
        ("Prompt Versioning & A/B Testing", 5, "ml-ai,p3-low"),
    ],
    
    # Epic 1.4: Automatic Ticket & Milestone Actions (10 issues)
    3: [
        ("Jira Ticket Auto-Creation", 8, "backend,p0-critical"),
        ("Azure DevOps Work Item Creation", 8, "backend,p0-critical"),
        ("Milestone Auto-Suggestion", 5, "backend,p0-critical"),
        ("Epic Auto-Linking", 5, "backend,p1-high"),
        ("Sprint Assignment AI", 5, "ml-ai,p2-medium"),
        ("Estimate Suggestion (t-shirt → pts)", 5, "ml-ai,p2-medium"),
        ("Notification on Ticket Creation", 3, "backend,p1-high"),
        ("Audit Log of Auto-Actions", 3, "backend,p1-high"),
        ("Rollback/Undo Auto-Created Items", 3, "backend,p2-medium"),
        ("Approval Workflow for High-Value Items", 5, "backend,p2-medium"),
    ],
    
    # Epic 1.5: Cross-Meeting Semantic Search (8 issues)
    6: [
        ("OpenSearch Index of All Transcripts", 8, "devops,p0-critical"),
        ("Semantic Query Parser", 5, "backend,p0-critical"),
        ("Transcript Embedding (BGE-M3)", 8, "ml-ai,p0-critical"),
        ("Timeline-Aware Search", 5, "backend,p1-high"),
        ("Multi-language Search", 5, "backend,p2-medium"),
        ("Search Result Ranking", 5, "ml-ai,p1-high"),
        ("Search Analytics & Popular Queries", 3, "backend,p3-low"),
        ("Search Performance Optimization", 5, "backend,p2-medium"),
    ],
    
    # Epic 1.6: Meeting Intelligence UI (9 issues)
    2: [
        ("Real-time Transcript Display", 5, "frontend,p0-critical"),
        ("Entity Highlighting & Tooltips", 5, "frontend,p0-critical"),
        ("Meeting Summary Panel", 5, "frontend,p0-critical"),
        ("Action Items List View", 3, "frontend,p0-critical"),
        ("RCA & Decision Panel", 5, "frontend,p1-high"),
        ("Search Results UI", 5, "frontend,p1-high"),
        ("Meeting Timeline Scrubber", 5, "frontend,p1-high"),
        ("Speaker Timeline Swim Lanes", 5, "frontend,p2-medium"),
        ("Mobile Responsive Design", 3, "frontend,p2-medium"),
    ],
    
    # PILLAR 2: DOCUMENTS
    
    # Epic 2.1: Core Document Engine (12 issues)
    9: [
        ("Document CRUD Operations", 8, "backend,p0-critical"),
        ("Markdown Parser & Renderer", 5, "frontend,p0-critical"),
        ("Document Versioning System", 8, "backend,p0-critical"),
        ("Collaborative Editing (OT)", 13, "backend,p0-critical"),
        ("Real-time Sync via WebSocket", 8, "backend,p0-critical"),
        ("Document Permissions (RBAC)", 8, "backend,p0-critical"),
        ("Full-text Search in Documents", 5, "backend,p1-high"),
        ("Document Templates", 5, "backend,p2-medium"),
        ("Export to PDF/Word/HTML", 8, "backend,p1-high"),
        ("Document Commenting", 5, "frontend,p1-high"),
        ("Document History View", 3, "frontend,p1-high"),
        ("Offline Mode Support", 8, "frontend,p2-medium"),
    ],
    
    # Epic 2.2: Advanced Document Features (8 issues)
    7: [
        ("Tables & Advanced Formatting", 5, "frontend,p1-high"),
        ("Code Blocks with Syntax Highlight", 3, "frontend,p1-high"),
        ("Embedded Images & Media", 5, "backend,p1-high"),
        ("Mathematical Equations (LaTeX)", 5, "frontend,p2-medium"),
        ("Drawing/Whiteboard Tool", 8, "frontend,p2-medium"),
        ("Document Bookmarks & Links", 3, "backend,p2-medium"),
        ("Table of Contents Auto-Gen", 3, "backend,p2-medium"),
        ("Document Status Tracking", 3, "backend,p2-medium"),
    ],
    
    # Epic 2.3: Spreadsheet Engine (13 issues)
    12: [
        ("Cell Data Model & Rendering", 8, "frontend,p0-critical"),
        ("Formula Evaluation Engine (basic)", 13, "backend,p0-critical"),
        ("Basic Functions (SUM, AVG, COUNT)", 8, "backend,p0-critical"),
        ("IF/Conditional Functions", 5, "backend,p1-high"),
        ("Text Functions", 5, "backend,p1-high"),
        ("Date/Time Functions", 5, "backend,p1-high"),
        ("Cell Formatting (borders, colors)", 5, "frontend,p1-high"),
        ("Pivot Tables Basic", 13, "backend,p2-medium"),
        ("Charts (bar, line, pie)", 8, "frontend,p1-high"),
        ("Freeze Rows/Columns", 3, "frontend,p1-high"),
        ("Import CSV/XLSX", 5, "backend,p1-high"),
        ("Export to CSV/XLSX", 5, "backend,p1-high"),
        ("Collaboration in Sheets", 8, "backend,p2-medium"),
    ],
    
    # Epic 2.4: Presentation Engine (8 issues)
    10: [
        ("Slide Creation & Layout", 8, "frontend,p0-critical"),
        ("Slide Transitions", 5, "frontend,p1-high"),
        ("Speaker Notes", 3, "backend,p1-high"),
        ("Slide Formatting (colors, fonts)", 5, "frontend,p1-high"),
        ("Chart Insertion", 5, "frontend,p1-high"),
        ("Presentation Mode (presenter view)", 8, "frontend,p1-high"),
        ("Slide Animations", 5, "frontend,p2-medium"),
        ("Export to PDF/PPTX", 5, "backend,p1-high"),
    ],
    
    # Epic 2.5: AI-Powered Document Assistance (10 issues)
    8: [
        ("Grammar & Spell Check", 5, "ml-ai,p1-high"),
        ("Writing Style Suggestions", 5, "ml-ai,p1-high"),
        ("Document Auto-Summarization", 8, "ml-ai,p1-high"),
        ("Content Outline Suggestion", 5, "ml-ai,p2-medium"),
        ("Tone Analyzer (formal/casual/friendly)", 5, "ml-ai,p2-medium"),
        ("Citation Generator", 5, "backend,p2-medium"),
        ("Document Auto-Tagging", 5, "ml-ai,p2-medium"),
        ("Readability Score", 3, "backend,p2-medium"),
        ("Translation Assistant", 5, "ml-ai,p3-low"),
        ("Content Plagiarism Detection", 8, "ml-ai,p3-low"),
    ],
    
    # Epic 2.6: Document Integrations & Workflows (7 issues)
    11: [
        ("Google Drive Import", 8, "backend,p2-medium"),
        ("Microsoft Office Import", 8, "backend,p2-medium"),
        ("Slack Document Sharing", 5, "backend,p2-medium"),
        ("Email Document Attachment", 5, "backend,p2-medium"),
        ("Document Signing (basic e-sig)", 8, "backend,p3-low"),
        ("Workflow Automation (approval chains)", 8, "backend,p3-low"),
        ("Document Retention Policies", 8, "devops,p3-low"),
    ],
    
    # PILLAR 3: MESSAGING
    
    # Epic 3.1: Enhanced Chat Engine (11 issues)
    17: [
        ("Direct Messages (1:1)", 8, "backend,p0-critical"),
        ("Group Chat Rooms", 8, "backend,p0-critical"),
        ("Real-time Message Sync", 5, "backend,p0-critical"),
        ("Message Threading", 5, "backend,p0-critical"),
        ("Message Reactions (emoji)", 3, "backend,p1-high"),
        ("Message Editing", 3, "backend,p1-high"),
        ("Message Deletion", 3, "backend,p1-high"),
        ("Message Search", 8, "backend,p1-high"),
        ("User Typing Indicators", 3, "backend,p1-high"),
        ("Message Read Receipts", 3, "backend,p1-high"),
        ("Chat UI Component Library", 5, "frontend,p1-high"),
    ],
    
    # Epic 3.2: Advanced User Presence & Status (7 issues)
    13: [
        ("Online/Offline Status", 3, "backend,p0-critical"),
        ("Custom Status Messages", 3, "backend,p1-high"),
        ("Do Not Disturb Mode", 3, "backend,p1-high"),
        ("Activity Status (idle detection)", 5, "backend,p1-high"),
        ("Presence History", 3, "backend,p2-medium"),
        ("Status Auto-Update (calendar linked)", 5, "ml-ai,p2-medium"),
        ("Presence in Profile Card", 3, "frontend,p1-high"),
    ],
    
    # Epic 3.3: Built-in Video Calling (12 issues)
    15: [
        ("WebRTC Setup & Signaling", 13, "backend,p0-critical"),
        ("Video/Audio Codec Selection", 8, "backend,p0-critical"),
        ("Peer Connection Management", 8, "backend,p0-critical"),
        ("Call Initiation & Routing", 8, "backend,p0-critical"),
        ("Call UI (video grid)", 8, "frontend,p0-critical"),
        ("Screen Sharing", 8, "backend,p1-high"),
        ("Call Recording (on-prem)", 13, "backend,p0-critical"),
        ("Echo Cancellation & Noise Suppression", 8, "backend,p1-high"),
        ("Bandwidth Adaptation", 8, "backend,p1-high"),
        ("Group Video (up to 100)", 13, "backend,p1-high"),
        ("Call History", 3, "backend,p2-medium"),
        ("Mobile Video Support", 8, "frontend,p2-medium"),
    ],
    
    # Epic 3.4: Call Recording & Analytics (10 issues)
    14: [
        ("Recording Start/Stop", 5, "backend,p0-critical"),
        ("Recording Storage & Indexing", 8, "devops,p0-critical"),
        ("Recording Playback UI", 5, "frontend,p0-critical"),
        ("Transcript of Recording", 8, "ml-ai,p1-high"),
        ("Recording Search", 5, "backend,p1-high"),
        ("Call Duration Tracking", 3, "backend,p1-high"),
        ("Participant Join/Leave Times", 3, "backend,p1-high"),
        ("Audio Quality Metrics", 5, "backend,p2-medium"),
        ("Recording Analytics Dashboard", 5, "frontend,p2-medium"),
        ("GDPR-Compliant Recording Deletion", 5, "devops,p1-high"),
    ],
    
    # Epic 3.5: Channel Organization & Governance (8 issues)
    16: [
        ("Channel Creation & Management", 5, "backend,p1-high"),
        ("Channel Permissions (public/private)", 5, "backend,p1-high"),
        ("Pinned Messages", 3, "backend,p1-high"),
        ("Channel Description & Topic", 3, "backend,p1-high"),
        ("Member Join/Leave Notifications", 3, "backend,p1-high"),
        ("Channel Favorites/Bookmarks", 3, "backend,p2-medium"),
        ("Channel Analytics (message count)", 3, "backend,p2-medium"),
        ("Archive Old Channels", 3, "devops,p2-medium"),
    ],
    
    # Epic 3.6: Bots & Automation (9 issues)
    18: [
        ("Bot Framework & SDK", 8, "backend,p1-high"),
        ("Message Routing to Bots", 5, "backend,p1-high"),
        ("Slash Commands", 5, "backend,p1-high"),
        ("Interactive Buttons & Dropdowns", 5, "frontend,p1-high"),
        ("Scheduled Messages", 5, "backend,p2-medium"),
        ("Bot Authentication & Tokens", 5, "backend,p1-high"),
        ("Bot Marketplace (internal)", 5, "backend,p3-low"),
        ("Logging & Debugging Bots", 3, "backend,p2-medium"),
        ("Rate Limiting for Bots", 3, "backend,p1-high"),
    ],
    
    # PILLAR 4: HUMANIZER ENGINE
    
    # Epic 4.1: Employee Digital Twin (10 issues)
    20: [
        ("Digital Twin Data Model", 8, "backend,p1-high"),
        ("Collect Meeting Patterns", 5, "ml-ai,p1-high"),
        ("Collect Communication Style", 5, "ml-ai,p1-high"),
        ("Collect Work Preferences", 5, "backend,p1-high"),
        ("Historical Profile Analysis", 8, "ml-ai,p1-high"),
        ("Skills & Expertise Extraction", 8, "ml-ai,p1-high"),
        ("Team Network Graph", 8, "backend,p2-medium"),
        ("Twin Privacy Controls", 5, "backend,p1-high"),
        ("Twin Data Export", 3, "backend,p2-medium"),
        ("Twin Accuracy Metrics", 5, "ml-ai,p2-medium"),
    ],
    
    # Epic 4.2: Personalized Interface (8 issues)
    24: [
        ("Dark Mode Support", 3, "frontend,p2-medium"),
        ("Theme Customization", 3, "frontend,p2-medium"),
        ("Layout Presets (compact/comfortable)", 3, "frontend,p2-medium"),
        ("Sidebar Customization", 3, "frontend,p2-medium"),
        ("Widget Personalization", 5, "frontend,p2-medium"),
        ("Font Size & Accessibility", 3, "frontend,p1-high"),
        ("Keyboard Shortcut Customization", 3, "frontend,p3-low"),
        ("Personalization Analytics", 3, "backend,p3-low"),
    ],
    
    # Epic 4.3: Intelligent Notifications (9 issues)
    19: [
        ("Notification Priority Detection", 8, "ml-ai,p0-critical"),
        ("Smart Notification Timing", 8, "ml-ai,p0-critical"),
        ("Do Not Disturb Patterns", 5, "ml-ai,p0-critical"),
        ("Notification Deduplication", 5, "backend,p1-high"),
        ("Notification Batching", 5, "backend,p1-high"),
        ("Notification Digest Generation", 5, "ml-ai,p1-high"),
        ("Notification Preferences UI", 3, "frontend,p1-high"),
        ("Notification Templates", 5, "backend,p2-medium"),
        ("Notification A/B Testing", 5, "ml-ai,p2-medium"),
    ],
    
    # Epic 4.4: Conversational Help & Guidance (8 issues)
    23: [
        ("In-App Help Bot (Llama)", 8, "ml-ai,p1-high"),
        ("Contextual Help Tips", 5, "ml-ai,p1-high"),
        ("Onboarding Flow", 5, "backend,p1-high"),
        ("Help Article Knowledge Base", 5, "backend,p2-medium"),
        ("FAQ Auto-Categorization", 5, "ml-ai,p2-medium"),
        ("Feedback Loop from Help Usage", 3, "backend,p2-medium"),
        ("Help Translation", 5, "ml-ai,p3-low"),
        ("Help Analytics Dashboard", 3, "backend,p3-low"),
    ],
    
    # Epic 4.5: Predictive Workflows (10 issues)
    21: [
        ("Workflow Pattern Detection", 8, "ml-ai,p1-high"),
        ("Next Action Suggestions", 8, "ml-ai,p1-high"),
        ("Meeting Prep Checklist Generation", 5, "ml-ai,p1-high"),
        ("Post-Meeting Action Reminders", 5, "backend,p1-high"),
        ("Work Hours Prediction", 5, "ml-ai,p2-medium"),
        ("Priority Re-ranking (based on twin)", 8, "ml-ai,p1-high"),
        ("Workflow Automation Suggestions", 5, "ml-ai,p2-medium"),
        ("Context Switching Detection", 5, "ml-ai,p2-medium"),
        ("Focus Time Management", 3, "backend,p2-medium"),
        ("Workflow Success Metrics", 3, "backend,p3-low"),
    ],
    
    # Epic 4.6: Sentiment-Aware Interactions (7 issues)
    22: [
        ("Meeting Sentiment Analysis", 5, "ml-ai,p1-high"),
        ("User Stress Detection", 5, "ml-ai,p1-high"),
        ("Tone-Aware Message Suggestions", 5, "ml-ai,p1-high"),
        ("Emotional Intelligence Coaching", 5, "ml-ai,p2-medium"),
        ("Team Sentiment Dashboard", 5, "backend,p2-medium"),
        ("Burnout Prediction", 8, "ml-ai,p2-medium"),
        ("Wellness Recommendations", 5, "backend,p2-medium"),
    ],
    
    # PILLAR 5: INFRASTRUCTURE
    
    # Epic 5.1: Security & Compliance (12 issues)
    26: [
        ("TLS 1.3 for All Traffic", 5, "devops,p0-critical"),
        ("AES-256 Data Encryption (at rest)", 8, "devops,p0-critical"),
        ("RBAC Implementation", 8, "backend,p0-critical"),
        ("Audit Logging for All Actions", 8, "backend,p0-critical"),
        ("SOC2 Compliance Check", 13, "qa,p1-high"),
        ("GDPR Data Export Tool", 8, "backend,p1-high"),
        ("Right to Deletion Implementation", 8, "backend,p1-high"),
        ("Data Residency Options", 8, "devops,p1-high"),
        ("Security Scanning (SAST)", 5, "qa,p1-high"),
        ("Dependency Vulnerability Scanning", 5, "devops,p1-high"),
        ("Penetration Testing (3rd party)", 13, "qa,p1-high"),
        ("Incident Response Plan", 5, "devops,p2-medium"),
    ],
    
    # Epic 5.2: Performance & Reliability (10 issues)
    28: [
        ("99.99% Uptime SLA", 8, "devops,p0-critical"),
        ("Database Read Replicas", 13, "devops,p0-critical"),
        ("Redis Caching Strategy", 8, "backend,p0-critical"),
        ("CDN Integration for Static Assets", 8, "devops,p0-critical"),
        ("API Rate Limiting", 5, "backend,p0-critical"),
        ("Load Testing (10k concurrent users)", 8, "qa,p1-high"),
        ("Database Query Optimization", 13, "backend,p1-high"),
        ("Auto-scaling Kubernetes", 13, "devops,p1-high"),
        ("Monitoring & Alerting (Prometheus)", 8, "devops,p1-high"),
        ("Disaster Recovery Plan", 13, "devops,p1-high"),
    ],
    
    # Epic 5.3: Integration Ecosystem (9 issues)
    27: [
        ("Jira Cloud Integration API", 8, "backend,p1-high"),
        ("Azure DevOps Integration API", 8, "backend,p1-high"),
        ("Slack Bot Integration", 8, "backend,p1-high"),
        ("Google Workspace Integration", 8, "backend,p1-high"),
        ("Zapier Integration", 5, "backend,p2-medium"),
        ("Webhook Support", 5, "backend,p1-high"),
        ("OAuth2 Provider", 8, "backend,p1-high"),
        ("API Documentation & Portal", 5, "backend,p2-medium"),
        ("SDK Generation (TypeScript, Python)", 8, "backend,p2-medium"),
    ],
    
    # Epic 5.4: Analytics & AI Infrastructure (11 issues)
    25: [
        ("Event Streaming Pipeline (Kafka)", 13, "devops,p1-high"),
        ("Data Warehouse Setup (Snowflake)", 13, "devops,p1-high"),
        ("Aggregated Analytics Dashboard", 8, "backend,p1-high"),
        ("User Behavior Tracking", 8, "backend,p1-high"),
        ("Feature Usage Analytics", 5, "backend,p1-high"),
        ("ML Model Registry", 8, "ml-ai,p1-high"),
        ("Experiment Tracking (MLflow)", 8, "ml-ai,p1-high"),
        ("Model Inference Monitoring", 5, "devops,p2-medium"),
        ("Cost Attribution by Feature", 5, "backend,p2-medium"),
        ("Revenue Analytics", 3, "backend,p2-medium"),
        ("Churn Prediction Model", 13, "ml-ai,p2-medium"),
    ],
}

# ============================================
# HELPER FUNCTIONS
# ============================================

def get_issue_body(title: str, points: int, labels: str) -> str:
    """Generate markdown body for issue"""
    
    # Extract key info from title
    if "GPU" in title or "Whisper" in title or "Llama" in title:
        return f"""## {title}

**Effort:** {points} points  
**Skills:** {labels}

### User Story
As a developer, I need to implement this feature so that we meet Q1 timeline.

### Acceptance Criteria
- [ ] Feature implemented and tested
- [ ] Code reviewed and merged
- [ ] Documentation updated
- [ ] No performance regressions
- [ ] All test coverage maintained

### Technical Approach
{title.split('[')[0].strip()} - see epic description for context.

### Definition of Done
- Code merged to main
- Tests pass (CI/CD green)
- Documentation complete
- QA sign-off

### Related Issues
- Parent Epic in issue description
"""
    
    return f"""## {title}

**Effort:** {points} points  
**Skills:** {labels}

### User Story
As a developer, I need to implement this feature so that we meet our roadmap goals.

### Acceptance Criteria
- [ ] Feature implemented
- [ ] Tests written
- [ ] Code reviewed
- [ ] Performance verified
- [ ] Documentation updated

### Discussion
See parent epic (#) for full context and technical design.

### Definition of Done
✓ Merged  
✓ Tests passing  
✓ Docs updated  
"""

def create_issues_batch(repo, epic_num: int, issues: List[Tuple[str, int, str]]) -> Tuple[int, int]:
    """Create batch of issues for an epic"""
    
    created = 0
    failed = 0
    
    print(f"  📌 Epic #{epic_num}")
    
    for title, points, labels in issues:
        try:
            # Format: [TASK-X.Y.Z] Title (points)
            issue_title = f"[TASK] {title} ({points}pts)"
            issue_body = get_issue_body(title, points, labels)
            
            # Parse labels
            label_list = [l.strip() for l in labels.split(",")]
            label_list.append("task")
            label_list.append(f"epic-{epic_num}")
            
            issue = repo.create_issue(
                title=issue_title,
                body=issue_body,
                labels=label_list
            )
            
            print(f"    ✅ #{issue.number}: {title}")
            created += 1
            
            # Rate limit: GitHub allows ~10 requests/second for authenticated users
            # Use 0.3s between requests to stay well within limits
            time.sleep(0.3)
            
        except GithubException as e:
            print(f"    ❌ Error creating '{title}': {e.data.get('message', str(e))}")
            failed += 1
        except Exception as e:
            print(f"    ❌ Unexpected error: {str(e)}")
            failed += 1
    
    return created, failed

def main():
    """Main execution"""
    
    # Verify auth
    token = os.getenv("GITHUB_TOKEN")
    if not token:
        print("❌ GITHUB_TOKEN not set")
        print("Set with: export GITHUB_TOKEN='ghp_xxxx...'")
        sys.exit(1)
    
    # Initialize GitHub
    try:
        g = Github(token)
        user = g.get_user()
        repo = g.get_user("kushin77").get_repo("OfficeIQ")
        print(f"✅ Authenticated as: {user.login}")
        print(f"📦 Repository: {repo.full_name}\n")
    except Exception as e:
        print(f"❌ Authentication failed: {e}")
        sys.exit(1)
    
    # Create issues
    print("🚀 Creating sub-issues from PMO breakdown")
    print("=" * 60)
    
    total_created = 0
    total_failed = 0
    
    print("\n📚 PILLAR 1: Meeting Intelligence")
    for epic_id, issues in [(1, EPIC_ISSUES[1]), (4, EPIC_ISSUES[4]), (5, EPIC_ISSUES[5]), 
                             (3, EPIC_ISSUES[3]), (6, EPIC_ISSUES[6]), (2, EPIC_ISSUES[2])]:
        created, failed = create_issues_batch(repo, epic_id, issues)
        total_created += created
        total_failed += failed
    
    print("\n📄 PILLAR 2: Documents")
    for epic_id in [9, 7, 12, 10, 8, 11]:
        if epic_id in EPIC_ISSUES:
            created, failed = create_issues_batch(repo, epic_id, EPIC_ISSUES[epic_id])
            total_created += created
            total_failed += failed
    
    print("\n💬 PILLAR 3: Messaging")
    for epic_id in [17, 13, 15, 14, 16, 18]:
        if epic_id in EPIC_ISSUES:
            created, failed = create_issues_batch(repo, epic_id, EPIC_ISSUES[epic_id])
            total_created += created
            total_failed += failed
    
    print("\n🤖 PILLAR 4: Humanizer")
    for epic_id in [20, 24, 19, 23, 21, 22]:
        if epic_id in EPIC_ISSUES:
            created, failed = create_issues_batch(repo, epic_id, EPIC_ISSUES[epic_id])
            total_created += created
            total_failed += failed
    
    print("\n⚙️  PILLAR 5: Infrastructure")
    for epic_id in [26, 28, 27, 25]:
        if epic_id in EPIC_ISSUES:
            created, failed = create_issues_batch(repo, epic_id, EPIC_ISSUES[epic_id])
            total_created += created
            total_failed += failed
    
    # Summary
    print("\n" + "=" * 60)
    print(f"✅ COMPLETE!")
    print(f"   Created: {total_created} issues")
    if total_failed > 0:
        print(f"   Failed: {total_failed} issues")
    print(f"   Total: {total_created + total_failed}")
    
    print("\n📊 Next Steps:")
    print(f"  1. Review all {total_created} new issues in GitHub")
    print(f"  2. Assign issues to team members")
    print(f"  3. Assign issues to Q1/Q2/Q3/Q4 milestones")
    print(f"  4. Create project board columns")
    print(f"  5. Start sprint 0 planning")
    
    print(f"\n🔗 Repository: https://github.com/BestGaaS220/OfficeIQ")

if __name__ == "__main__":
    main()
