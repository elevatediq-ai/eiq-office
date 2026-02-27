#!/bin/bash

# Generate all remaining 140+ sub-issues across 5 pillars
# Using gh CLI directly (no Python dependency)

REPO="kushin77/OfficeIQ"

echo "🚀 Generating 140+ Sub-Issues in $REPO"
echo "========================================"
echo ""

# Counter
CREATED=0

# PILLAR 1: Meeting Intelligence (Epic 1.1-1.6, ~53 issues)
echo "📌 PILLAR 1: Meeting Intelligence (53 issues)"

# Epic 1.1: Live Transcription (13 tasks)
for task in \
  "1.1.4|Real-time Audio Compression (Opus)|5|backend" \
  "1.1.5|Speaker Detection Pre-processing|3|ml-ai" \
  "1.1.7|Transcript Persistence to PostgreSQL|3|backend" \
  "1.1.9|Confidence Scoring Per Word|3|ml-ai" \
  "1.1.10|Multilingual Support (EN, ES, FR, DE)|5|ml-ai" \
  "1.1.11|Websocket Connection Resilience|3|backend" \
  "1.1.12|Transcript Versioning & Editing|3|backend" \
  "1.1.13|Audio Storage & Archival|5|devops"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 1.2: Entity Extraction (12 tasks)
for task in \
  "1.2.1|Custom NER Model Training (IT/PMO)|8|ml-ai" \
  "1.2.2|CMDB Asset Database Integration|6|backend" \
  "1.2.3|Jira/Azure DevOps Entity Linking|8|backend" \
  "1.2.4|Person/Employee Recognition|5|ml-ai" \
  "1.2.5|Context Enrichment Pipeline|5|backend" \
  "1.2.6|Entity Disambiguation|5|ml-ai" \
  "1.2.7|Knowledge Graph Construction|8|backend" \
  "1.2.8|OpenSearch Entity Index|5|devops" \
  "1.2.9|Entity Relationship Extraction|6|ml-ai" \
  "1.2.10|Historical Entity Lookups|3|backend" \
  "1.2.11|Bulk Entity Import Tool|3|backend" \
  "1.2.12|Entity Validation & QA|3|qa"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 1.3: LLM Analysis (14 tasks)
for task in \
  "1.3.1|Deploy Ollama Llama 3.1 70B|8|devops" \
  "1.3.2|Meeting Summary Generation|8|ml-ai" \
  "1.3.3|Root Cause Analysis (RCA) Draft|8|ml-ai" \
  "1.3.4|Action Item Extraction|5|ml-ai" \
  "1.3.5|Decision Log Generation|5|ml-ai" \
  "1.3.6|Meeting Sentiment Analysis|5|ml-ai" \
  "1.3.8|Key Topic Extraction|5|ml-ai" \
  "1.3.9|Q&A Suggestions Generation|5|ml-ai" \
  "1.3.10|Meeting Coaching/Advice|5|ml-ai" \
  "1.3.11|Follow-up Email Draft|5|ml-ai" \
  "1.3.12|Ollama Prompt Optimization|5|ml-ai" \
  "1.3.13|LLM Result Caching|3|backend" \
  "1.3.14|Cost & Token Tracking|3|backend" \
  "1.3.15|Prompt Versioning & A/B Testing|5|ml-ai"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 1.4: Ticket Actions (10 tasks)
for task in \
  "1.4.1|Jira Ticket Auto-Creation|8|backend" \
  "1.4.2|Azure DevOps Work Item Creation|8|backend" \
  "1.4.3|Milestone Auto-Suggestion|5|backend" \
  "1.4.4|Epic Auto-Linking|5|backend" \
  "1.4.5|Sprint Assignment AI|5|ml-ai" \
  "1.4.6|Estimate Suggestion|5|ml-ai" \
  "1.4.7|Notification on Ticket Creation|3|backend" \
  "1.4.8|Audit Log of Auto-Actions|3|backend" \
  "1.4.9|Rollback/Undo Feature|3|backend" \
  "1.4.10|Approval Workflow|5|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 1.5: Search (8 tasks)
for task in \
  "1.5.1|OpenSearch Index of Transcripts|8|devops" \
  "1.5.2|Semantic Query Parser|5|backend" \
  "1.5.3|Transcript Embedding (BGE-M3)|8|ml-ai" \
  "1.5.4|Timeline-Aware Search|5|backend" \
  "1.5.5|Multi-language Search|5|backend" \
  "1.5.6|Search Result Ranking|5|ml-ai" \
  "1.5.7|Search Analytics|3|backend" \
  "1.5.8|Search Performance Optimization|5|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 1.6: UI (9 tasks)
for task in \
  "1.6.1|Real-time Transcript Display|5|frontend" \
  "1.6.2|Entity Highlighting & Tooltips|5|frontend" \
  "1.6.3|Meeting Summary Panel|5|frontend" \
  "1.6.4|Action Items List View|3|frontend" \
  "1.6.5|RCA & Decision Panel|5|frontend" \
  "1.6.6|Search Results UI|5|frontend" \
  "1.6.7|Meeting Timeline Scrubber|5|frontend" \
  "1.6.8|Speaker Timeline Swim Lanes|5|frontend" \
  "1.6.9|Mobile Responsive Design|3|frontend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

echo "✅ Pillar 1: Created $((CREATED-0)) tasks"

# PILLAR 2: Documents (Epic 2.1-2.6, ~50 issues)
echo "📄 PILLAR 2: Documents (50 issues)"
P2_START=$CREATED

# Epic 2.1: Core Document Engine (12 tasks)
for task in \
  "2.1.1|Document CRUD Operations|8|backend" \
  "2.1.2|Markdown Parser & Renderer|5|frontend" \
  "2.1.3|Document Versioning System|8|backend" \
  "2.1.4|Collaborative Editing (OT)|13|backend" \
  "2.1.5|Real-time Sync via WebSocket|8|backend" \
  "2.1.6|Document Permissions (RBAC)|8|backend" \
  "2.1.7|Full-text Search in Documents|5|backend" \
  "2.1.8|Document Templates|5|backend" \
  "2.1.9|Export to PDF/Word/HTML|8|backend" \
  "2.1.10|Document Commenting|5|frontend" \
  "2.1.11|Document History View|3|frontend" \
  "2.1.12|Offline Mode Support|8|frontend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 2.2: Advanced Features (8 tasks)
for task in \
  "2.2.1|Tables & Advanced Formatting|5|frontend" \
  "2.2.2|Code Blocks with Syntax Highlight|3|frontend" \
  "2.2.3|Embedded Images & Media|5|backend" \
  "2.2.4|Mathematical Equations (LaTeX)|5|frontend" \
  "2.2.5|Drawing/Whiteboard Tool|8|frontend" \
  "2.2.6|Document Bookmarks & Links|3|backend" \
  "2.2.7|Table of Contents Auto-Gen|3|backend" \
  "2.2.8|Document Status Tracking|3|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 2.3: Spreadsheets (13 tasks)
for task in \
  "2.3.1|Cell Data Model & Rendering|8|frontend" \
  "2.3.2|Formula Evaluation Engine|13|backend" \
  "2.3.3|Basic Functions (SUM, AVG, COUNT)|8|backend" \
  "2.3.4|IF/Conditional Functions|5|backend" \
  "2.3.5|Text Functions|5|backend" \
  "2.3.6|Date/Time Functions|5|backend" \
  "2.3.7|Cell Formatting|5|frontend" \
  "2.3.8|Pivot Tables Basic|13|backend" \
  "2.3.9|Charts (bar, line, pie)|8|frontend" \
  "2.3.10|Freeze Rows/Columns|3|frontend" \
  "2.3.11|Import CSV/XLSX|5|backend" \
  "2.3.12|Export to CSV/XLSX|5|backend" \
  "2.3.13|Collaboration in Sheets|8|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 2.4: Presentations (8 tasks)
for task in \
  "2.4.1|Slide Creation & Layout|8|frontend" \
  "2.4.2|Slide Transitions|5|frontend" \
  "2.4.3|Speaker Notes|3|backend" \
  "2.4.4|Slide Formatting|5|frontend" \
  "2.4.5|Chart Insertion|5|frontend" \
  "2.4.6|Presentation Mode|8|frontend" \
  "2.4.7|Slide Animations|5|frontend" \
  "2.4.8|Export to PDF/PPTX|5|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 2.5: AI Assistance (10 tasks)
for task in \
  "2.5.1|Grammar & Spell Check|5|ml-ai" \
  "2.5.2|Writing Style Suggestions|5|ml-ai" \
  "2.5.3|Document Auto-Summarization|8|ml-ai" \
  "2.5.4|Content Outline Suggestion|5|ml-ai" \
  "2.5.5|Tone Analyzer|5|ml-ai" \
  "2.5.6|Citation Generator|5|backend" \
  "2.5.7|Document Auto-Tagging|5|ml-ai" \
  "2.5.8|Readability Score|3|backend" \
  "2.5.9|Translation Assistant|5|ml-ai" \
  "2.5.10|Plagiarism Detection|8|ml-ai"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 2.6: Integrations (7 tasks)
for task in \
  "2.6.1|Google Drive Import|8|backend" \
  "2.6.2|Microsoft Office Import|8|backend" \
  "2.6.3|Slack Document Sharing|5|backend" \
  "2.6.4|Email Document Attachment|5|backend" \
  "2.6.5|Document Signing|8|backend" \
  "2.6.6|Workflow Automation|8|backend" \
  "2.6.7|Document Retention Policies|8|devops"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

echo "✅ Pillar 2: Created $((CREATED-P2_START)) tasks (Total: $CREATED)"

# PILLAR 3: Messaging (Epic 3.1-3.6, ~52 issues)
echo "💬 PILLAR 3: Messaging (52 issues)"
P3_START=$CREATED

# Epic 3.1: Chat Engine (11 tasks)
for task in \
  "3.1.1|Direct Messages (1:1)|8|backend" \
  "3.1.2|Group Chat Rooms|8|backend" \
  "3.1.3|Real-time Message Sync|5|backend" \
  "3.1.4|Message Threading|5|backend" \
  "3.1.5|Message Reactions (emoji)|3|backend" \
  "3.1.6|Message Editing|3|backend" \
  "3.1.7|Message Deletion|3|backend" \
  "3.1.8|Message Search|8|backend" \
  "3.1.9|User Typing Indicators|3|backend" \
  "3.1.10|Message Read Receipts|3|backend" \
  "3.1.11|Chat UI Components|5|frontend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 3.2: Presence (7 tasks)
for task in \
  "3.2.1|Online/Offline Status|3|backend" \
  "3.2.2|Custom Status Messages|3|backend" \
  "3.2.3|Do Not Disturb Mode|3|backend" \
  "3.2.4|Activity Status (idle)|5|backend" \
  "3.2.5|Presence History|3|backend" \
  "3.2.6|Status Auto-Update|5|ml-ai" \
  "3.2.7|Presence in Profile Card|3|frontend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 3.3: Video Calling (12 tasks)
for task in \
  "3.3.1|WebRTC Setup & Signaling|13|backend" \
  "3.3.2|Video/Audio Codec Selection|8|backend" \
  "3.3.3|Peer Connection Management|8|backend" \
  "3.3.4|Call Initiation & Routing|8|backend" \
  "3.3.5|Call UI (video grid)|8|frontend" \
  "3.3.6|Screen Sharing|8|backend" \
  "3.3.7|Call Recording (on-prem)|13|backend" \
  "3.3.8|Echo Cancellation & Noise|8|backend" \
  "3.3.9|Bandwidth Adaptation|8|backend" \
  "3.3.10|Group Video (100 people)|13|backend" \
  "3.3.11|Call History|3|backend" \
  "3.3.12|Mobile Video Support|8|frontend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 3.4: Recording (10 tasks)
for task in \
  "3.4.1|Recording Start/Stop|5|backend" \
  "3.4.2|Recording Storage & Index|8|devops" \
  "3.4.3|Recording Playback UI|5|frontend" \
  "3.4.4|Transcript of Recording|8|ml-ai" \
  "3.4.5|Recording Search|5|backend" \
  "3.4.6|Call Duration Tracking|3|backend" \
  "3.4.7|Participant Join/Leave Times|3|backend" \
  "3.4.8|Audio Quality Metrics|5|backend" \
  "3.4.9|Recording Analytics|5|frontend" \
  "3.4.10|GDPR Compliant Deletion|5|devops"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 3.5: Channels (8 tasks)
for task in \
  "3.5.1|Channel Creation & Mgmt|5|backend" \
  "3.5.2|Channel Permissions|5|backend" \
  "3.5.3|Pinned Messages|3|backend" \
  "3.5.4|Channel Description|3|backend" \
  "3.5.5|Join/Leave Notifications|3|backend" \
  "3.5.6|Channel Favorites|3|backend" \
  "3.5.7|Channel Analytics|3|backend" \
  "3.5.8|Archive Old Channels|3|devops"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 3.6: Bots (9 tasks)
for task in \
  "3.6.1|Bot Framework & SDK|8|backend" \
  "3.6.2|Message Routing to Bots|5|backend" \
  "3.6.3|Slash Commands|5|backend" \
  "3.6.4|Interactive Buttons|5|frontend" \
  "3.6.5|Scheduled Messages|5|backend" \
  "3.6.6|Bot Authentication|5|backend" \
  "3.6.7|Bot Marketplace|5|backend" \
  "3.6.8|Logging & Debugging|3|backend" \
  "3.6.9|Rate Limiting for Bots|3|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

echo "✅ Pillar 3: Created $((CREATED-P3_START)) tasks (Total: $CREATED)"

# PILLAR 4: Humanizer (Epic 4.1-4.6, ~48 issues)
echo "🤖 PILLAR 4: Humanizer (48 issues)"
P4_START=$CREATED

# Epic 4.1: Digital Twin (10 tasks)
for task in \
  "4.1.1|Digital Twin Data Model|8|backend" \
  "4.1.2|Meeting Patterns Collection|5|ml-ai" \
  "4.1.3|Communication Style|5|ml-ai" \
  "4.1.4|Work Preferences Collection|5|backend" \
  "4.1.5|Historical Profile Analysis|8|ml-ai" \
  "4.1.6|Skills & Expertise Extract|8|ml-ai" \
  "4.1.7|Team Network Graph|8|backend" \
  "4.1.8|Twin Privacy Controls|5|backend" \
  "4.1.9|Twin Data Export|3|backend" \
  "4.1.10|Twin Accuracy Metrics|5|ml-ai"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 4.2: Personalization (8 tasks)
for task in \
  "4.2.1|Dark Mode Support|3|frontend" \
  "4.2.2|Theme Customization|3|frontend" \
  "4.2.3|Layout Presets|3|frontend" \
  "4.2.4|Sidebar Customization|3|frontend" \
  "4.2.5|Widget Personalization|5|frontend" \
  "4.2.6|Font Size & Accessibility|3|frontend" \
  "4.2.7|Keyboard Shortcut Custom|3|frontend" \
  "4.2.8|Personalization Analytics|3|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 4.3: Notifications (9 tasks)
for task in \
  "4.3.1|Notification Priority|8|ml-ai" \
  "4.3.2|Smart Notification Timing|8|ml-ai" \
  "4.3.3|DND Pattern Learning|5|ml-ai" \
  "4.3.4|Notification Dedup|5|backend" \
  "4.3.5|Notification Batching|5|backend" \
  "4.3.6|Notification Digest|5|ml-ai" \
  "4.3.7|Notification Prefs UI|3|frontend" \
  "4.3.8|Notification Templates|5|backend" \
  "4.3.9|Notification A/B Testing|5|ml-ai"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 4.4: Help (8 tasks)
for task in \
  "4.4.1|In-App Help Bot|8|ml-ai" \
  "4.4.2|Contextual Help Tips|5|ml-ai" \
  "4.4.3|Onboarding Flow|5|backend" \
  "4.4.4|Help Knowledge Base|5|backend" \
  "4.4.5|FAQ Auto-Categorization|5|ml-ai" \
  "4.4.6|Help Feedback Loop|3|backend" \
  "4.4.7|Help Translation|5|ml-ai" \
  "4.4.8|Help Analytics|3|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 4.5: Workflows (10 tasks)
for task in \
  "4.5.1|Workflow Pattern Detect|8|ml-ai" \
  "4.5.2|Next Action Suggestions|8|ml-ai" \
  "4.5.3|Meeting Prep Checklist|5|ml-ai" \
  "4.5.4|Post-Meeting Reminders|5|backend" \
  "4.5.5|Work Hours Prediction|5|ml-ai" \
  "4.5.6|Priority Re-ranking|8|ml-ai" \
  "4.5.7|Workflow Automation Sugg|5|ml-ai" \
  "4.5.8|Context Switch Detection|5|ml-ai" \
  "4.5.9|Focus Time Management|3|backend" \
  "4.5.10|Workflow Success Metrics|3|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 4.6: Sentiment (7 tasks)
for task in \
  "4.6.1|Meeting Sentiment Analysis|5|ml-ai" \
  "4.6.2|User Stress Detection|5|ml-ai" \
  "4.6.3|Tone-Aware Suggestions|5|ml-ai" \
  "4.6.4|Emotional Intelligence Coach|5|ml-ai" \
  "4.6.5|Team Sentiment Dashboard|5|backend" \
  "4.6.6|Burnout Prediction|8|ml-ai" \
  "4.6.7|Wellness Recommendations|5|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

echo "✅ Pillar 4: Created $((CREATED-P4_START)) tasks (Total: $CREATED)"

# PILLAR 5: Infrastructure (Epic 5.1-5.4, ~44 issues)
echo "⚙️  PILLAR 5: Infrastructure (44 issues)"
P5_START=$CREATED

# Epic 5.1: Security (12 tasks)
for task in \
  "5.1.1|TLS 1.3 for All Traffic|5|devops" \
  "5.1.2|AES-256 At-Rest Encryption|8|devops" \
  "5.1.3|RBAC Implementation|8|backend" \
  "5.1.4|Audit Logging|8|backend" \
  "5.1.5|SOC2 Compliance Check|13|qa" \
  "5.1.6|GDPR Data Export|8|backend" \
  "5.1.7|Right to Deletion|8|backend" \
  "5.1.8|Data Residency Options|8|devops" \
  "5.1.9|Security Scanning (SAST)|5|qa" \
  "5.1.10|Dependency Scanning|5|devops" \
  "5.1.11|Penetration Testing|13|qa" \
  "5.1.12|Incident Response Plan|5|devops"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 5.2: Performance (10 tasks)
for task in \
  "5.2.1|99.99% Uptime SLA|8|devops" \
  "5.2.2|Database Read Replicas|13|devops" \
  "5.2.3|Redis Caching Strategy|8|backend" \
  "5.2.4|CDN Integration|8|devops" \
  "5.2.5|API Rate Limiting|5|backend" \
  "5.2.6|Load Testing (10k users)|8|qa" \
  "5.2.7|Query Optimization|13|backend" \
  "5.2.8|Auto-scaling Kubernetes|13|devops" \
  "5.2.9|Monitoring & Alerting|8|devops" \
  "5.2.10|Disaster Recovery Plan|13|devops"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 5.3: Integrations (9 tasks)
for task in \
  "5.3.1|Jira Cloud Integration|8|backend" \
  "5.3.2|Azure DevOps Integration|8|backend" \
  "5.3.3|Slack Bot Integration|8|backend" \
  "5.3.4|Google Workspace Integration|8|backend" \
  "5.3.5|Zapier Integration|5|backend" \
  "5.3.6|Webhook Support|5|backend" \
  "5.3.7|OAuth2 Provider|8|backend" \
  "5.3.8|API Documentation|5|backend" \
  "5.3.9|SDK Generation|8|backend"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

# Epic 5.4: Analytics (11 tasks)
for task in \
  "5.4.1|Event Streaming (Kafka)|13|devops" \
  "5.4.2|Data Warehouse (Snowflake)|13|devops" \
  "5.4.3|Analytics Dashboard|8|backend" \
  "5.4.4|User Behavior Tracking|8|backend" \
  "5.4.5|Feature Usage Analytics|5|backend" \
  "5.4.6|ML Model Registry|8|ml-ai" \
  "5.4.7|Experiment Tracking (MLflow)|8|ml-ai" \
  "5.4.8|Model Inference Monitoring|5|devops" \
  "5.4.9|Cost Attribution|5|backend" \
  "5.4.10|Revenue Analytics|3|backend" \
  "5.4.11|Churn Prediction Model|13|ml-ai"
do
  IFS='|' read num title pts skill <<< "$task"
  gh issue create --repo $REPO --title "[TASK-$num] $title ($pts pts)" --body "Story points: $pts\nSkills: $skill" > /dev/null 2>&1
  ((CREATED++))
done

echo "✅ Pillar 5: Created $((CREATED-P5_START)) tasks (Total: $CREATED)"

echo ""
echo "========================================"
echo "✅ COMPLETE!"
echo "📊 Total sub-issues created: $CREATED"
echo "🔗 Repository: https://github.com/$REPO/issues"
