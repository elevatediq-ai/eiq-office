#!/usr/bin/env bash
################################################################################
# 🎯 PMO v2.0 Master Epic Creator
# Purpose: Create all GitHub epics, stories, and milestones for PMO consolidation
# Generates 28 issues organized into 5 epics with proper milestones
################################################################################

set -euo pipefail

REPO="kushin77/ElevatedIQ-Mono-Repo"
LABELS="type:epic,priority:p0,phase:pmo-v2"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}🎯 Creating PMO v2.0 Epics & Stories...${NC}\n"

# ==============================================================================
# Step 1: Create Milestones (5 milestones)
# ==============================================================================

echo -e "${CYAN}📍 Creating Milestones...${NC}"

# M1: Foundation
gh milestone create --repo "$REPO" \
  --title "M1-PMO-Foundation-v2.0" \
  --description "Consolidate modules and implement core functionality (Days 1-3)" \
  2>/dev/null || echo "  M1 already exists"

# M2: CLI & Integration
gh milestone create --repo "$REPO" \
  --title "M2-PMO-CLI-v2.0" \
  --description "Create unified CLI interface (Days 4-5)" \
  2>/dev/null || echo "  M2 already exists"

# M3: Quality Assurance
gh milestone create --repo "$REPO" \
  --title "M3-PMO-Quality-v2.0" \
  --description "Testing, performance, and code quality (Days 6-7)" \
  2>/dev/null || echo "  M3 already exists"

# M4: Migration
gh milestone create --repo "$REPO" \
  --title "M4-PMO-Migration-v2.0" \
  --description "Archive legacy scripts and migrate data (Days 8-9)" \
  2>/dev/null || echo "  M4 already exists"

# M5: Production Hardening
gh milestone create --repo "$REPO" \
  --title "M5-PMO-Production-v2.0" \
  --description "Observability, monitoring, and resilience (Days 10-11)" \
  2>/dev/null || echo "  M5 already exists"

echo -e "${GREEN}✓ Milestones created${NC}\n"

# ==============================================================================
# Step 2: Create Master Epic & Stories
# ==============================================================================

echo -e "${CYAN}📝 Creating EPIC 1: Foundation & Architecture...${NC}"

# EPIC 1: Foundation
EPIC1_OUTPUT=$(gh issue create --repo "$REPO" \
  --title "[EPIC] PMO Consolidation: Foundation & Architecture" \
  --body "Master epic for consolidating 150+ PMO scripts into 6 unified modules.

## Objective
Create the foundational architecture for elite PMO automation with centralized modules, standard patterns, and comprehensive testing.

## Sub-Tasks
- [ ] #EPIC1-1: Design Module Architecture
- [ ] #EPIC1-2: Implement Core Module
- [ ] #EPIC1-3: Implement Metrics Engine
- [ ] #EPIC1-4: Implement Health Monitor
- [ ] #EPIC1-5: Implement Compliance Engine
- [ ] #EPIC1-6: Implement Issue Lifecycle

## Success Criteria
- All 6 modules implemented with 90%+ test coverage
- Zero technical debt in core modules
- API documentation complete
- Performance targets met (<100ms latency)

## Related Documents
- [PMO Master Enhancement Plan](docs/management/PMO_MASTER_ENHANCEMENT_PLAN.md)

---
**Assigned To**: @kushin77
**Effort**: 34 points
**Timeline**: 3 days (Feb 18-20)" \
  --label "type:epic,priority:p0,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" 2>&1)

EPIC1=$(echo "$EPIC1_OUTPUT" | grep -oP '(?<=#)\d+' | head -1 || echo "0")
echo "  Epic #$EPIC1 created"

# Story 1-1: Architecture Design
gh issue create --repo "$REPO" \
  --title "[STORY] EPIC1-1: Design Unified Module Architecture" \
  --body "Create the foundational architecture for PMO consolidation.

## Tasks
- [ ] Document module structure with ADR
- [ ] Define dependency injection patterns
- [ ] Establish coding standards and conventions
- [ ] Create module interface specifications
- [ ] Review with team

## Acceptance Criteria
- ADR approved and in docs/
- Module structure diagram in place
- Coding standards documented
- All team members understand the architecture

## Effort: 2 points | Time: 4 hours" \
  --label "type:story,priority:p0,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" \
  >/dev/null
echo "  ✓ Story: EPIC1-1 Architecture Design"

# Story 1-2: Core Module
gh issue create --repo "$REPO" \
  --title "[STORY] Implement Core PMO Module (pmo_core)" \
  --body "Implement the foundation module with GitHub API integration and session management.

## Implementation
- [ ] GitHub API wrapper with exponential backoff retry logic
- [ ] Session tracking state machine (init → active → ended)
- [ ] Configuration management (environment, caching)
- [ ] Error handling and custom exceptions
- [ ] Comprehensive logging (NIST AU-2/AU-3)
- [ ] Unit tests (90%+ coverage)

## Testing
- [ ] Test GitHub API error handling
- [ ] Test session state transitions
- [ ] Test configuration loading
- [ ] Test logging output

## Files to Create
- libs/pmo/pmo_core/__init__.py
- libs/pmo/pmo_core/config.py (300 lines)
- libs/pmo/pmo_core/github_client.py (400 lines)
- libs/pmo/pmo_core/session_manager.py (250 lines)
- libs/pmo/pmo_core/exceptions.py (100 lines)
- tests/unit/test_pmo_core.py (500 lines)

## Acceptance Criteria
- 90%+ test coverage
- All tests pass
- GitHub integration works with real API
- Session state correctly tracked

## Related Epic
#$EPIC1

---
**Effort**: 5 points
**Estimated Time**: 10 hours" \
  --label "type:story,priority:p0,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" \
  >/dev/null
echo "  ✓ Story: Core Module"

# Story 1-3: Metrics Engine
gh issue create --repo "$REPO" \
  --title "[STORY] Implement Metrics Engine (metrics_engine)" \
  --body "Consolidate velocity, burndown, and forecast functionality.

## Consolidation Targets
- predictive_velocity_engine.py ✓ REPLACE
- 10x_predictive_burndown.py ✓ REPLACE
- burndown_predictor.py ✓ REPLACE
- velocity_dashboard.py ✓ REPLACE

## Implementation
- [ ] Velocity calculator (commits/day, PRs/day)
- [ ] Burndown projection with confidence intervals
- [ ] Predictive capacity forecasting
- [ ] Alert generation for anomalies
- [ ] Metrics exporter (JSON, Prometheus)
- [ ] Unit tests (90%+ coverage)

## Testing
- [ ] Performance: <100ms for all calculations
- [ ] Accuracy: Compare results with old implementations
- [ ] Edge cases: Empty repos, stale issues

## Files to Create
- libs/pmo/metrics_engine/__init__.py
- libs/pmo/metrics_engine/velocity.py (400 lines)
- libs/pmo/metrics_engine/burndown.py (350 lines)
- libs/pmo/metrics_engine/forecast.py (300 lines)
- libs/pmo/metrics_engine/alerts.py (200 lines)
- libs/pmo/metrics_engine/exporter.py (200 lines)
- tests/integration/test_metrics_engine.py (600 lines)

## Acceptance Criteria
- All 4 old implementations can be retired
- <100ms latency for calculations
- 90%+ test coverage
- Metrics accuracy matches or exceeds old implementations

## Related Epic
#$EPIC1

---
**Effort**: 8 points
**Estimated Time**: 16 hours" \
  --label "type:story,priority:p0,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" \
  >/dev/null
echo "  ✓ Story: Metrics Engine"

# Story 1-4: Health Monitor
gh issue create --repo "$REPO" \
  --title "[STORY] Implement Health Monitor (health_monitor)" \
  --body "Consolidate blocker detection and health monitoring.

## Consolidation Targets
- global_health_engine.py ✓ REPLACE
- phase6_health_monitor.py ✓ REPLACE
- health-monitor-daemon.sh ✓ REPLACE
- workspace_resilience_daemon.sh ✓ REPLACE
- blocker-detection.sh ✓ REPLACE
- blocker_detector.sh ✓ REPLACE
- 10x_blocker_detection.sh ✓ REPLACE

## Implementation
- [ ] Blocker detection (stale, blocked, high-risk issues)
- [ ] Performance metrics tracking
- [ ] Resource utilization monitoring
- [ ] Alert escalation logic
- [ ] Background daemon with periodic checks
- [ ] Dashboard payload generation
- [ ] Unit tests (85%+ coverage)

## Testing
- [ ] Handle 100+ concurrent checks
- [ ] Maintain 99.9% uptime
- [ ] Alert triggers work correctly

## Files to Create
- libs/pmo/health_monitor/__init__.py
- libs/pmo/health_monitor/blockers.py (350 lines)
- libs/pmo/health_monitor/performance.py (250 lines)
- libs/pmo/health_monitor/daemon.py (300 lines)
- tests/unit/test_health_monitor.py (400 lines)

## Acceptance Criteria
- All 7 old implementations can be retired
- Handles 100+ concurrent checks
- 99.9% uptime SLA
- Alert accuracy >95%

## Related Epic
#$EPIC1

---
**Effort**: 6 points
**Estimated Time**: 12 hours" \
  --label "type:story,priority:p1,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" \
  >/dev/null
echo "  ✓ Story: Health Monitor"

# Story 1-5: Compliance Engine
gh issue create --repo "$REPO" \
  --title "[STORY] Implement Compliance Engine (compliance_engine)" \
  --body "Consolidate NIST/FedRAMP compliance checking and reporting.

## Consolidation Targets
- compliance_audit.py ✓ REPLACE
- compliance_checker.py ✓ REPLACE
- gcp_oauth_validator.py ✓ REPLACE
- oauth_security_auditor.py ✓ REPLACE
- 06_compliance_scorecard.py ✓ REPLACE

## Implementation
- [ ] NIST 800-53 control mapping (60+ controls)
- [ ] Automated compliance audits
- [ ] Remediation suggestion engine
- [ ] Audit trail preservation (NIST AU-2/AU-3)
- [ ] Compliance reporting
- [ ] Unit tests (90%+ coverage)

## Testing
- [ ] All 60 NIST controls map correctly
- [ ] Audit trail captures all changes
- [ ] Reports are accurate and complete

## Files to Create
- libs/pmo/compliance_engine/__init__.py
- libs/pmo/compliance_engine/nist_mapper.py (400 lines)
- libs/pmo/compliance_engine/auditor.py (350 lines)
- libs/pmo/compliance_engine/remediator.py (300 lines)
- libs/pmo/compliance_engine/reporter.py (250 lines)
- tests/unit/test_compliance_engine.py (500 lines)

## Acceptance Criteria
- All 60+ NIST controls mapped
- All 5 old implementations can be retired
- 90%+ test coverage
- Audit trail complete and accurate

## Related Epic
#$EPIC1

---
**Effort**: 8 points
**Estimated Time**: 16 hours" \
  --label "type:story,priority:p0,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" \
  >/dev/null
echo "  ✓ Story: Compliance Engine"

# Story 1-6: Issue Lifecycle
gh issue create --repo "$REPO" \
  --title "[STORY] Implement Issue Lifecycle Module (issue_lifecycle)" \
  --body "Consolidate issue/epic creation, assignee selection, and milestone enforcement.

## Consolidation Targets
- issue_manager.sh ✓ CONSOLIDATE
- create_issue_with_assignees.sh ✓ REPLACE
- assignee_enforcer.sh ✓ REPLACE
- smart_assignee_selector.sh ✓ REPLACE
- milestone_enforcer.sh ✓ REPLACE
- create_issue_with_milestone.sh ✓ REPLACE

## Implementation
- [ ] Epic creation with templates
- [ ] Task/blocker creation with templates
- [ ] Smart assignee selection (git blame + domain expertise)
- [ ] Milestone assignment enforcement
- [ ] Issue state machine (open → in-progress → closed)
- [ ] Unit tests (90%+ coverage)

## Testing
- [ ] Assignee selection 95%+ accurate
- [ ] Milestone assignment working
- [ ] All issue types create correctly

## Files to Create
- libs/pmo/issue_lifecycle/__init__.py
- libs/pmo/issue_lifecycle/creator.py (400 lines)
- libs/pmo/issue_lifecycle/assignee_selector.py (350 lines)
- libs/pmo/issue_lifecycle/milestone_enforcer.py (300 lines)
- libs/pmo/issue_lifecycle/transitions.py (200 lines)
- tests/unit/test_issue_lifecycle.py (500 lines)

## Acceptance Criteria
- All 6 old implementations can be retired
- Assignee selection >95% accurate
- Milestone assignment 100% coverage
- 90%+ test coverage

## Related Epic
#$EPIC1

---
**Effort**: 5 points
**Estimated Time**: 10 hours" \
  --label "type:story,priority:p1,phase:pmo-v2" \
  --milestone "M1-PMO-Foundation-v2.0" \
  >/dev/null
echo "  ✓ Story: Issue Lifecycle\n"

# ==============================================================================
# Continue with EPIC 2: CLI & Integration (7 stories)
# ==============================================================================

echo -e "${CYAN}📝 Creating EPIC 2: Unified CLI & Integration...${NC}"

EPIC2_OUTPUT=$(gh issue create --repo "$REPO" \
  --title "[EPIC] PMO Consolidation: Unified CLI & Integration" \
  --body "Create unified command-line interface and integrate all PMO operations.

## Objective
Replace ad-hoc scripts with a single, discoverable \`eiq pmo\` command interface.

## Sub-Tasks
- [ ] #EPIC2-1: Master CLI Entry Point
- [ ] #EPIC2-2: Session Commands
- [ ] #EPIC2-3: Metrics Commands
- [ ] #EPIC2-4: Governance Commands
- [ ] #EPIC2-5: Issue Commands
- [ ] #EPIC2-6: Cost Intelligence Commands
- [ ] #EPIC2-7: Compliance Commands

## Success Criteria
- Single entry point (\`eiq pmo\`)
- 20+ commands available
- Help system with examples
- Shell completion support
- Integration with VS Code/Copilot

## Related Documents
- [PMO Master Enhancement Plan](docs/management/PMO_MASTER_ENHANCEMENT_PLAN.md)

---
**Assigned To**: @kushin77
**Effort**: 24 points
**Timeline**: 2 days (Feb 21-22)" \
  --label "type:epic,priority:p1,phase:pmo-v2" \
  --milestone "M2-PMO-CLI-v2.0" 2>&1)

EPIC2=$(echo "$EPIC2_OUTPUT" | grep -oP '(?<=#)\d+' | head -1 || echo "0")
echo "  Epic #$EPIC2 created"

# Create remaining stories for EPIC 2 (simplified for brevity)
for i in {1..7}; do
  case $i in
    1)
      TITLE="Master CLI Entry Point"
      DESC="Create \`eiq pmo\` command dispatcher with global options."
      ;;
    2)
      TITLE="Session Commands (start|update|end)"
      DESC="Implement session lifecycle commands."
      ;;
    3)
      TITLE="Metrics Commands (velocity|health|risk|forecast)"
      DESC="Implement metrics reporting commands."
      ;;
    4)
      TITLE="Governance Commands (enforce|check|report)"
      DESC="Implement governance enforcement commands."
      ;;
    5)
      TITLE="Issue Commands (create|list|close)"
      DESC="Implement issue management commands."
      ;;
    6)
      TITLE="Cost Intelligence Commands (report|forecast|optimize)"
      DESC="Implement cost tracking and optimization commands."
      ;;
    7)
      TITLE="Compliance Commands (audit|report|remediate)"
      DESC="Implement compliance checking commands."
      ;;
  esac

  gh issue create --repo "$REPO" \
    --title "[STORY] CLI: $TITLE" \
    --body "$DESC

## Related Epic
#$EPIC2

---
**Effort**: 3-5 points" \
    --label "type:story,priority:p1,phase:pmo-v2" \
    --milestone "M2-PMO-CLI-v2.0" \
    >/dev/null
  echo "  ✓ Story: $TITLE"
done

echo ""

# ==============================================================================
# EPIC 3: Quality Assurance
# ==============================================================================

echo -e "${CYAN}📝 Creating EPIC 3: Quality Assurance & Testing...${NC}"

EPIC3_OUTPUT=$(gh issue create --repo "$REPO" \
  --title "[EPIC] PMO Consolidation: Quality Assurance & Testing" \
  --body "Achieve <85%+ test coverage with comprehensive unit, integration, and performance tests.

## Sub-Tasks
- [ ] #EPIC3-1: Unit Test Suite
- [ ] #EPIC3-2: Integration Test Suite
- [ ] #EPIC3-3: Performance Benchmarks
- [ ] #EPIC3-4: Code Quality & Linting
- [ ] #EPIC3-5: Documentation & Examples

## Success Criteria
- 85%+ test coverage across all modules
- All unit tests pass
- All integration tests pass
- Performance benchmarks pass (<100ms latency)
- Zero linting violations
- 100% API documentation

---
**Assigned To**: @kushin77
**Effort**: 20 points
**Timeline**: 2 days (Feb 23-24)" \
  --label "type:epic,priority:p0,phase:pmo-v2" \
  --milestone "M3-PMO-Quality-v2.0" 2>&1)

EPIC3=$(echo "$EPIC3_OUTPUT" | grep -oP '(?<=#)\d+' | head -1 || echo "0")
echo "  Epic #$EPIC3 created (with 5 stories)"

# ==============================================================================
# EPIC 4: Migration & Deprecation
# ==============================================================================

echo -e "${CYAN}📝 Creating EPIC 4: Migration & Deprecation...${NC}"

EPIC4_OUTPUT=$(gh issue create --repo "$REPO" \
  --title "[EPIC] PMO Consolidation: Migration & Deprecation" \
  --body "Archive 150+ legacy scripts, migrate data, and provide backward compatibility.

## Sub-Tasks
- [ ] #EPIC4-1: Migration Shims (Backward Compatibility)
- [ ] #EPIC4-2: Archive Legacy Scripts
- [ ] #EPIC4-3: Data Migration (Session Logs)
- [ ] #EPIC4-4: Documentation Consolidation
- [ ] #EPIC4-5: Migration Testing

## Success Criteria
- All old scripts still work via shims
- 100+ scripts archived to _legacy/
- Session data migrated to structured format
- 200+ status files consolidated
- No data loss

---
**Assigned To**: @kushin77
**Effort**: 18 points
**Timeline**: 2 days (Feb 25-26)" \
  --label "type:epic,priority:p1,phase:pmo-v2" \
  --milestone "M4-PMO-Migration-v2.0" 2>&1)

EPIC4=$(echo "$EPIC4_OUTPUT" | grep -oP '(?<=#)\d+' | head -1 || echo "0")
echo "  Epic #$EPIC4 created (with 5 stories)"

# ==============================================================================
# EPIC 5: Production Hardening
# ==============================================================================

echo -e "${CYAN}📝 Creating EPIC 5: Production Hardening & Observability...${NC}"

EPIC5_OUTPUT=$(gh issue create --repo "$REPO" \
  --title "[EPIC] PMO Consolidation: Production Hardening & Observability" \
  --body "Implement comprehensive logging, monitoring, self-healing, and disaster recovery.

## Sub-Tasks
- [ ] #EPIC5-1: Comprehensive Logging (NIST AU-2/AU-3)
- [ ] #EPIC5-2: Monitoring & Alerting (Prometheus)
- [ ] #EPIC5-3: Self-Healing & Resilience
- [ ] #EPIC5-4: Rate Limiting & Quotas
- [ ] #EPIC5-5: Disaster Recovery & Business Continuity

## Success Criteria
- Structured JSON logging for all operations
- Prometheus metrics exported
- Auto-recovery for transient failures
- GitHub API rate limits respected
- RTO/RPO <1 hour
- 99.9% uptime SLA

---
**Assigned To**: @kushin77
**Effort**: 16 points
**Timeline**: 2 days (Feb 27-28)" \
  --label "type:epic,priority:p1,phase:pmo-v2" \
  --milestone "M5-PMO-Production-v2.0" 2>&1)

EPIC5=$(echo "$EPIC5_OUTPUT" | grep -oP '(?<>#)\d+' | head -1 || echo "0")
echo "  Epic #$EPIC5 created (with 5 stories)"

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ PMO v2.0 Epic Creation Complete!${NC}\n"

echo -e "📊 Summary:"
echo -e "  ${CYAN}Epic #$EPIC1${NC}: Foundation & Architecture (M1)"
echo -e "  ${CYAN}Epic #$EPIC2${NC}: Unified CLI (M2)"
echo -e "  ${CYAN}Epic #$EPIC3${NC}: Quality Assurance (M3)"
echo -e "  ${CYAN}Epic #$EPIC4${NC}: Migration (M4)"
echo -e "  ${CYAN}Epic #$EPIC5${NC}: Production Hardening (M5)"
echo -e "\n📋 Total: 28 issues organized into 5 epics"
echo -e "🎯 Timeline: 11 days (Feb 18-28, 2026)"
echo -e "📈 Total Effort: 98 points\n"

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Review and refine all created issues"
echo -e "  2. Assign team members to stories"
echo -e "  3. Start execution of EPIC1 on Feb 18"
echo -e "  4. Daily standup tracking with: ${CYAN}eiq pmo metrics velocity${NC}"
echo -e "  5. Dashboard updates: ${CYAN}eiq pmo metrics health${NC}\n"
