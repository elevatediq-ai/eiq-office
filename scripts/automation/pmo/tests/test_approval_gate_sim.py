"""ElevatedIQ: Phase 7.4 Executive Approval Gate Simulation
Verifies human-in-the-loop oversight for high blast-radius actions.
"""

import asyncio
import logging
import os
import sys

# Add workspace to path
sys.path.append(os.getcwd())

from apps.control_plane.src.control_plane.agent_coordinator.coordinator import AgentCoordinator

from libs.ai_orchestrator.distributed_incident_coordinator import DistributedIncidentCoordinator, IncidentStatus
from libs.ai_orchestrator.regional_coordinator import FailoverStrategy, RegionalCoordinator

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("ApprovalGateSim")


async def run_simulation():
    logger.info("Starting Phase 7.4 Executive Approval Gate Simulation")

    # 1. Setup
    regions = ["us-east1"]
    project_id = "elevatediq-test"

    regional_coordinators = {
        region: RegionalCoordinator(
            regions=regions,
            project_id=project_id,
            failover_strategy=FailoverStrategy.AUTOMATIC,
        )
        for region in regions
    }

    agent_coordinator = AgentCoordinator()

    coordinator = DistributedIncidentCoordinator(
        region="us-east1",
        regional_coordinators=regional_coordinators,
        agent_coordinator=agent_coordinator,
    )
    await coordinator.initialize_coordination()

    # 2. Simulate High Blast-Radius Incident
    # "hub-vpc" triggers score 9.5 in BlastCalculator
    incident_data = {
        "title": "Critical Hub VPC Connectivity Failure",
        "description": "The main hub-vpc is down, impacting all regions.",
        "severity": "critical",
        "resource_id": "hub-vpc-main",
    }

    incident_id = await coordinator.detect_incident("us-east1", incident_data)
    logger.info(f"Incident Created: {incident_id}")

    # 3. Verify status is PENDING (Escalated)
    incident = coordinator.get_incident_by_id(incident_id)
    logger.info(f"Routing Status: {incident.metadata.get('agent_routing_status')}")
    logger.info(f"Incident Status: {incident.status}")

    if incident.metadata.get("agent_routing_status") == "pending_approval":
        logger.info("SUCCESS: Incident correctly placed behind approval gate")
    else:
        logger.error(
            f"FAILURE: Incident failed to trigger approval gate. Status: {incident.metadata.get('agent_routing_status')}"
        )
        return

    # 4. Manually Approve Remediation
    logger.info(f"Granting executive approval for incident {incident_id}")
    success = await coordinator.approve_incident_remediation(incident_id)

    if success:
        logger.info("Executive approval processed successfully")
    else:
        logger.error("FAILURE: Approval attempt failed")
        return

    # 5. Verify final status
    incident = coordinator.get_incident_by_id(incident_id)
    logger.info(f"Post-Approval Status: {incident.status}")
    logger.info(f"Assigned Team: {incident.assigned_team}")

    if incident.status == IncidentStatus.TRIAGED and incident.assigned_team:
        logger.info("SUCCESS: Remediation proceeded after approval")
    else:
        logger.error("FAILURE: Incident did not transition to TRIAGED after approval")
        return

    logger.info("Executive Approval Gate Simulation Complete")


if __name__ == "__main__":
    asyncio.run(run_simulation())
