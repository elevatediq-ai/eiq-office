import asyncio
import logging
import os
from datetime import datetime

from libs.ai_orchestrator.distributed_incident_coordinator import DistributedIncidentCoordinator, IncidentStatus
from libs.ai_orchestrator.regional_coordinator import RegionalCoordinator

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("ExecutiveApprovalSim")


async def run_approval_sim():
    logger.info("Starting NIST-IR-4 Executive Approval Gate Simulation")

    # 1. Setup minimal coordinator
    region = "us-east1"
    regional_coords = {region: RegionalCoordinator([region], "elevatediq-test-project")}

    coordinator = DistributedIncidentCoordinator(
        region=region, regional_coordinators=regional_coords, state_dir="test_artifacts"
    )

    os.makedirs("test_artifacts", exist_ok=True)

    # 2. Detect a CRITICAL incident (escalated via ML)
    # ML Triager Escalation: "CRITICAL outage in database cluster" -> Severity 4
    incident_id = await coordinator.detect_incident(
        region,
        {
            "title": "CRITICAL outage in database cluster",
            "description": "Database cluster down, immediate manual intervention required.",
            "severity": "high",  # ML will escalate to CRITICAL
        },
    )

    incident = coordinator.get_incident_by_id(incident_id)

    # 3. Verify status is PENDING_APPROVAL
    if incident.status == IncidentStatus.PENDING_APPROVAL:
        logger.info(f"SUCCESS: Incident {incident_id} held at PENDING_APPROVAL gate.")
    else:
        logger.error(f"FAILURE: Incident {incident_id} status is {incident.status.value}, expected pending_approval")
        return

    # 4. Verify no team assigned yet
    if incident.assigned_team is None:
        logger.info("SUCCESS: No autonomous routing occurred while pending approval.")
    else:
        logger.error(f"FAILURE: Team {incident.assigned_team} was assigned before approval!")
        return

    # 5. Approve the incident
    logger.info(f"Step 2: Approving incident {incident_id} as 'Executive-Lead-kushin77'")
    approved = await coordinator.approve_incident(incident_id, "Executive-Lead-kushin77")

    if approved:
        logger.info("SUCCESS: approve_incident returned True")
    else:
        logger.error("FAILURE: approve_incident failed")
        return

    # 6. Verify status and routing
    if incident.status != IncidentStatus.PENDING_APPROVAL:
        logger.info(f"SUCCESS: Incident {incident_id} moved out of PENDING_APPROVAL.")
        # Note: In mock, it might stay TRIAGED or ESCALATED depending on routing result
    else:
        logger.error("FAILURE: Incident still in PENDING_APPROVAL")
        return

    # 7. Check audit logs
    audit_file = f"logs/coordination/decision_log_{datetime.utcnow().strftime('%Y%m%d')}.jsonl"
    if os.path.exists(audit_file):
        with open(audit_file) as f:
            lines = f.readlines()
            found_approval = any("executive_approval" in line and "APPROVED" in line for line in lines)
            if found_approval:
                logger.info(f"SUCCESS: Found NIH-AU-2 audit record for approval in {audit_file}")
            else:
                logger.error("FAILURE: No audit record found for approval")

    logger.info("Simulation Complete")


if __name__ == "__main__":
    asyncio.run(run_approval_sim())
