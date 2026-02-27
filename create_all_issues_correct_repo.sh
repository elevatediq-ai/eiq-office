#!/bin/bash

# Create ALL 25 epics + 9 samples in kushin77/OfficeIQ (CORRECT REPO)
REPO="kushin77/OfficeIQ"

echo "🚀 Creating 25 epics + 9 samples in $REPO..."
echo "=================================================="
echo ""

# Remove test issues first
echo "Cleaning up test issues..."
gh issue delete --repo $REPO 6 --confirm 2>/dev/null || true
gh issue delete --repo $REPO 7 --confirm 2>/dev/null || true

echo ""
echo "📌 PILLAR 1: Meeting Intelligence (6 epics)"
gh issue create --repo $REPO --title "[EPIC-1.1] Live Transcription Pipeline" --body "Real-time speech-to-text for meetings with speaker ID and transcript storage."
gh issue create --repo $REPO --title "[EPIC-1.2] Entity Extraction & Context Linking" --body "Extract and link entities (people, assets, tickets) from meeting transcripts."
gh issue create --repo $REPO --title "[EPIC-1.3] LLM-Powered Meeting Analysis" --body "Generate summaries, action items, RCA, decisions via Ollama Llama 3.1."
gh issue create --repo $REPO --title "[EPIC-1.4] Automatic Ticket & Milestone Actions" --body "Auto-create tickets in Jira/Azure from meeting decisions."
gh issue create --repo $REPO --title "[EPIC-1.5] Cross-Meeting Semantic Search" --body "Full-text + semantic search across all meeting transcripts."
gh issue create --repo $REPO --title "[EPIC-1.6] Meeting Intelligence UI" --body "React components for live transcripts, summaries, action items."

echo "📄 PILLAR 2: Sovereign Documents (6 epics)"
gh issue create --repo $REPO --title "[EPIC-2.1] Core Document Engine" --body "Create, edit, version, share documents cloud-free with real-time collab."
gh issue create --repo $REPO --title "[EPIC-2.2] Advanced Document Features" --body "Tables, advanced formatting, embedded media, mathematical equations."
gh issue create --repo $REPO --title "[EPIC-2.3] Spreadsheet Engine" --body "Formula evaluation, pivot tables, charts (Excel-like functionality)."
gh issue create --repo $REPO --title "[EPIC-2.4] Presentation Engine" --body "Slides, transitions, animations, presenter mode, export to PPTX."
gh issue create --repo $REPO --title "[EPIC-2.5] AI-Powered Document Assistance" --body "Grammar check, writing suggestions, auto-summarization, tone analysis."
gh issue create --repo $REPO --title "[EPIC-2.6] Document Integrations & Workflows" --body "Import from Office/Google, sharing, e-signature, approval workflows."

echo "💬 PILLAR 3: Unified Messaging & Collaboration (6 epics)"
gh issue create --repo $REPO --title "[EPIC-3.1] Enhanced Chat Engine" --body "Direct messages, group chat, threads, reactions, search."
gh issue create --repo $REPO --title "[EPIC-3.2] Advanced User Presence & Status" --body "Online/offline, DND, custom status, activity tracking."
gh issue create --repo $REPO --title "[EPIC-3.3] Built-in Video Calling" --body "WebRTC, screen share, recording, group calls (100+ people)."
gh issue create --repo $REPO --title "[EPIC-3.4] Call Recording & Analytics" --body "Record, playback, transcribe, search recordings."
gh issue create --repo $REPO --title "[EPIC-3.5] Channel Organization & Governance" --body "Public/private channels, permissions, moderation, archival."
gh issue create --repo $REPO --title "[EPIC-3.6] Bots & Automation" --body "Bot SDK, slash commands, workflows, Jira/Slack integration."

echo "🤖 PILLAR 4: Humanizer Engine (6 epics)"
gh issue create --repo $REPO --title "[EPIC-4.1] Employee Digital Twin" --body "AI model of each employee's communication patterns & preferences."
gh issue create --repo $REPO --title "[EPIC-4.2] Personalized Interface" --body "Dark mode, themes, layout customization per user preference."
gh issue create --repo $REPO --title "[EPIC-4.3] Intelligent Notifications" --body "Smart timing, priority detection, do-not-disturb patterns."
gh issue create --repo $REPO --title "[EPIC-4.4] Conversational Help & Guidance" --body "In-app help bot, contextual tips, smart onboarding."
gh issue create --repo $REPO --title "[EPIC-4.5] Predictive Workflows" --body "AI suggests next actions, automates recurring patterns."
gh issue create --repo $REPO --title "[EPIC-4.6] Sentiment-Aware Interactions" --body "Detect meeting sentiment, stress, burnout. Proactive support."

echo "⚙️  PILLAR 5: Infrastructure (4 epics)"
gh issue create --repo $REPO --title "[EPIC-5.1] Security & Compliance" --body "AES-256, TLS 1.3, RBAC, audit logs, SOC2, GDPR compliance."
gh issue create --repo $REPO --title "[EPIC-5.2] Performance & Reliability" --body "99.99% uptime SLA, auto-scaling, database replication."
gh issue create --repo $REPO --title "[EPIC-5.3] Integration Ecosystem" --body "API, webhooks, OAuth, Jira/Azure/Slack/Google integrations."
gh issue create --repo $REPO --title "[EPIC-5.4] Analytics & AI Infrastructure" --body "Event streaming, data warehouse, ML model registry."

echo ""
echo "📋 Sample Sub-Issues (9 critical Q1 tasks)"
gh issue create --repo $REPO --title "[TASK-1.1.1] Implement Whisper Large-V3 GPU Worker (8pts)" --body "Deploy Whisper on GPU for real-time audio processing. Acceptance: <200ms latency, 95%+ accuracy."
gh issue create --repo $REPO --title "[TASK-1.1.2] WebSocket Audio Streaming from NC Talk (5pts)" --body "Accept binary audio from client, stream to Whisper, return transcripts real-time."
gh issue create --repo $REPO --title "[TASK-1.1.3] Audio Queue Management & Buffering (3pts)" --body "Redis queue for audio chunks, FIFO ordering, backpressure handling."
gh issue create --repo $REPO --title "[TASK-1.1.6] Speaker Diarization (pyannote) (5pts)" --body "Identify speaker changes, label speakers in transcript, 90%+ accuracy."
gh issue create --repo $REPO --title "[TASK-1.1.8] Live Transcript UI Streaming (5pts)" --body "Real-time transcript display, speaker labels, confidence scores, mobile responsive."
gh issue create --repo $REPO --title "[TASK-1.3.7] RCA Draft Generation from Meeting Calls (8pts)" --body "Analyze incident transcript, generate RCA draft, include action items."

echo ""
echo "=================================================="
echo "✅ Complete! All 34 issues created in $REPO"
echo ""
echo "📊 View at: https://github.com/$REPO/issues"
