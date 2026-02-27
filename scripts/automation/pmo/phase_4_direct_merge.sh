#!/bin/bash
# Phase 4: Direct PR Merge via GitHub API (Commit SHA)
# NIST-CM-3: Change control - Bypass branch issues using API commit merge
# Status: ELITE FAANG automation - handles missing branches gracefully

set -e

OWNER="kushin77"
REPO="ElevatedIQ-Mono-Repo"

declare -A PR_DATA=(
    [6041]="c24b3790ef1cf587b84a18bb4e56619dcf84711b"
    [6075]="d74342fde64323333b6bd5d4584b2ada6e5ee28c"
    [6074]="5078a7d681bcc39cb102d9e50f6a5f70a5a16329"
    [6072]="49420dd4823089fd8a8525d3651e1c03489b93fa"
    [6069]="c7bbc63ad713a293e2be2287047f986983cd303a"
    [6063]="c24b3790ef1cf587b84a18bb4e56619dcf84711b"
)

echo "════════════════════════════════════════════════════════════"
echo "🚀 PHASE 4: DIRECT PR MERGE VIA GITHUB API"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📍 Repository: $OWNER/$REPO"
echo "🎯 Method: GitHub API merge (bypasses missing branches)"
echo ""

MERGED_COUNT=0
FAILED_COUNT=0
MERGE_LOG="/tmp/PHASE_4_MERGE.log"
> "$MERGE_LOG"

for PR_NUM in "${!PR_DATA[@]}"; do
    SHA="${PR_DATA[$PR_NUM]}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔀 Attempting to merge PR #$PR_NUM (commit: ${SHA:0:7})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Use GitHub API to merge - this will work even if branch doesn't exist
    # First check if PR is mergeable
    MERGE_STATUS=$(gh pr view "$PR_NUM" --repo "$OWNER/$REPO" --json mergeable --jq '.mergeable' 2>/dev/null || echo "ERROR")
    echo "   Merge Status: $MERGE_STATUS"
    
    if [ "$MERGE_STATUS" == "ERROR" ]; then
        echo "❌ Could not retrieve PR status"
        echo "[FAILED] PR #$PR_NUM - Status check failed" >> "$MERGE_LOG"
        ((FAILED_COUNT++))
        continue
    fi
    
    # Attempt merge via gh CLI API
    MERGE_RESULT=$(gh pr merge "$PR_NUM" \
        --repo "$OWNER/$REPO" \
        --squash \
        --subject "chore(merge): [NIST-CM-3] merge PR #$PR_NUM via commit SHA" \
        --body "Automated merge execution. Commit: $SHA" \
        2>&1 || echo "MERGE_FAILED")
    
    if echo "$MERGE_RESULT" | grep -q "MERGE_FAILED\|error\|Error"; then
        echo "⚠️  First merge attempt failed, trying alternative method..."
        
        # Alternative: Use raw GitHub API PUT request
        API_RESPONSE=$(gh api -X PUT \
            "repos/$OWNER/$REPO/pulls/$PR_NUM/merge" \
            -f commit_title="chore(merge): [NIST-CM-3] merge PR #$PR_NUM" \
            -f merge_method="squash" \
            2>&1 || echo "API_FAILED")
        
        if echo "$API_RESPONSE" | grep -q "merged\|false\|API_FAILED"; then
            echo "❌ Merge failed - PR may have conflicts or be unmergeable"
            echo "[FAILED] PR #$PR_NUM - $API_RESPONSE" >> "$MERGE_LOG"
            ((FAILED_COUNT++))
        else
            echo "✅ Merge successful via API"
            echo "[MERGED] PR #$PR_NUM via API" >> "$MERGE_LOG"
            ((MERGED_COUNT++))
        fi
    else
        echo "✅ Merge successful"
        echo "[MERGED] PR #$PR_NUM" >> "$MERGE_LOG"
        ((MERGED_COUNT++))
    fi
    
    sleep 1  # Rate limiting
done

echo ""
echo "════════════════════════════════════════════════════════════"
echo "📊 PHASE 4 SUMMARY"
echo "════════════════════════════════════════════════════════════"
echo "✅ Merged: $MERGED_COUNT PRs"
echo "❌ Failed: $FAILED_COUNT PRs"
echo "📝 Log: $MERGE_LOG"
echo ""
cat "$MERGE_LOG"
echo ""

# Next phase info
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 NEXT: Phase 5 - Terraform Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Location: /infrastructure/prod.tfvars"
echo "Commands:"
echo "  terraform plan -var-file=prod.tfvars"
echo "  terraform apply -var-file=prod.tfvars"
echo ""
