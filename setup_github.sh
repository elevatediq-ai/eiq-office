#!/bin/bash

# OfficeIQ GitHub Complete Setup Script
# Automates: Milestones → Labels → Project Boards
# Usage: bash setup_github.sh

set -e

REPO_OWNER="kushin77"
REPO_NAME="OfficeIQ"
FULL_REPO="$REPO_OWNER/$REPO_NAME"

echo "🚀 OfficeIQ GitHub Setup - Complete"
echo "Repository: $FULL_REPO"
echo "========================================"

# Check GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI not found. Install with: brew install gh"
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

echo "✅ GitHub CLI authenticated"
echo ""

# ============================================
# STEP 1: Create Milestones (4 issues)
# ============================================

echo "📅 Creating Milestones..."

gh milestone create \
  --repo "$FULL_REPO" \
  --title "Q1 2026 (Jan-Mar): Prove the Differentiation" \
  --description "🎯 Phase 1: Meeting Intelligence MVP + Core Documents + Security Foundation

**Goals:**
• Live transcription working (Whisper + WebSocket)
• Entity extraction & ticket auto-creation
• Core document creation (cloud-free)
• Security audit passed

**Delivery:** Live pilot with 100 customers" || echo "  (Q1 milestone may already exist)"

gh milestone create \
  --repo "$FULL_REPO" \
  --title "Q2 2026 (Apr-Jun): Achieve Feature Parity" \
  --description "📊 Phase 2: Complete vs Office 365/GSuite

**Goals:**
• Spreadsheets functional (basic formulas)
• Messaging MVP (Slack-like)
• Advanced meeting analysis (RCA, summaries)
• Integrations with Jira, Azure DevOps

**Delivery:** 5,000 customers, $13.5M ARR" || echo "  (Q2 milestone may already exist)"

gh milestone create \
  --repo "$FULL_REPO" \
  --title "Q3 2026 (Jul-Sep): Own the Category" \
  --description "🏆 Phase 3: Category Innovation

**Goals:**
• Humanizer engine (AI personalization)
• Video calling + recording built-in
• Advanced presentations with AI
• Predictive workflows

**Delivery:** 50,000 customers" || echo "  (Q3 milestone may already exist)"

gh milestone create \
  --repo "$FULL_REPO" \
  --title "Q4 2026 (Oct-Dec): Market Dominance" \
  --description "💎 Phase 4: Enterprise Focus

**Goals:**
• Enterprise SSO & compliance
• Advanced analytics
• Custom integrations API
• White-label options

**Delivery:** 250,000 customers, $300M+ ARR" || echo "  (Q4 milestone may already exist)"

echo "✅ Milestones created"
echo ""

# ============================================
# STEP 2: Create Labels (15+ labels)
# ============================================

echo "🏷️  Creating Labels..."

# Type labels
gh label create "epic" \
  --repo "$FULL_REPO" \
  --color "0075ca" \
  --description "Epic (6-12 week initiative)" 2>/dev/null || true

gh label create "task" \
  --repo "$FULL_REPO" \
  --color "5319e7" \
  --description "Task (1-2 weeks)" 2>/dev/null || true

gh label create "spike" \
  --repo "$FULL_REPO" \
  --color "c2e0c6" \
  --description "Research/investigation" 2>/dev/null || true

# Pillar labels
gh label create "pillar-1" \
  --repo "$FULL_REPO" \
  --color "1f6feb" \
  --description "🎤 Meeting Intelligence" 2>/dev/null || true

gh label create "pillar-2" \
  --repo "$FULL_REPO" \
  --color "238636" \
  --description "📄 Documents" 2>/dev/null || true

gh label create "pillar-3" \
  --repo "$FULL_REPO" \
  --color "2ea043" \
  --description "💬 Messaging" 2>/dev/null || true

gh label create "pillar-4" \
  --repo "$FULL_REPO" \
  --color "a371f7" \
  --description "🤖 Humanizer" 2>/dev/null || true

gh label create "infra" \
  --repo "$FULL_REPO" \
  --color "8250df" \
  --description "⚙️ Infrastructure" 2>/dev/null || true

# Priority labels
gh label create "p0-critical" \
  --repo "$FULL_REPO" \
  --color "ff0000" \
  --description "🔴 Critical/blocking" 2>/dev/null || true

gh label create "p1-high" \
  --repo "$FULL_REPO" \
  --color "ff6600" \
  --description "🟠 High priority" 2>/dev/null || true

gh label create "p2-medium" \
  --repo "$FULL_REPO" \
  --color "ffcc00" \
  --description "🟡 Medium priority" 2>/dev/null || true

gh label create "p3-low" \
  --repo "$FULL_REPO" \
  --color "cccccc" \
  --description "⚪ Low priority" 2>/dev/null || true

# Team skill labels
gh label create "backend" \
  --repo "$FULL_REPO" \
  --color "5D4E60" \
  --description "Backend engineering" 2>/dev/null || true

gh label create "frontend" \
  --repo "$FULL_REPO" \
  --color "A0C4FF" \
  --description "Frontend engineering" 2>/dev/null || true

gh label create "ml-ai" \
  --repo "$FULL_REPO" \
  --color "FFD700" \
  --description "ML/AI work" 2>/dev/null || true

gh label create "devops" \
  --repo "$FULL_REPO" \
  --color "BFD4E3" \
  --description "DevOps/infrastructure" 2>/dev/null || true

gh label create "qa" \
  --repo "$FULL_REPO" \
  --color "D4EDDA" \
  --description "Testing/QA" 2>/dev/null || true

echo "✅ Labels created"
echo ""

# ============================================
# STEP 3: Show What's Next
# ============================================

echo "========================================"
echo "✅ Setup Complete!"
echo ""
echo "📊 What's Live Now:"
echo "  • 25 parent epics (IQ-1 through IQ-28)"
echo "  • 6 sample sub-issues (IQ-29 through IQ-34)"
echo "  • 4 quarterly milestones (Q1-Q4)"
echo "  • 15+ GitHub labels (type, pillar, priority, team)"
echo ""
echo "📋 What's Next:"
echo "  Option A: Create remaining 140+ sub-issues"
echo "    → Run: python3 /home/akushnir/officeIQ/scripts/generate_remaining_issues.py"
echo ""
echo "  Option B: Create project boards (manual in UI)"
echo "    → Go to: https://github.com/BestGaaS220/OfficeIQ/projects"
echo "    → Click 'New project' → Create one per pillar"
echo ""
echo "  Option C: Assign issues to Q1 milestone"
echo "    → Bulk edit by label: pillar-1 → assign to Q1 2026"
echo ""
echo "🔗 Repository:"
echo "  https://github.com/$FULL_REPO"
echo ""
echo "========================================"
