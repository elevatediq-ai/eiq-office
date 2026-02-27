"""ElevatedIQ: Phase 7.4 Leader Failover & State Recovery Simulation
Verifies NIST-CP-10 compliance for incident response state.
"""

import asyncio
import logging
import os
import sys

# Add workspace to path
sys.path.append(os.getcwd())

from apps.control_plane.src.control_plane.agent_coordinator.coordinator import AgentCoordinator

from libs.ai_orchestrator.distributed_incident_coordinator import DistributedIncidentCoordinator
from libs.ai_orchestrator.regional_coordinator import FailoverStrategy, RegionalCoordinator

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("FailoverRecoverySim")


async def run_simulation():
    logger.info("Starting NIST-CP-10 Failover & Recovery Simulation")

    # 1. Setup Environment
    regions = ["us-east1", "us-west1"]
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

    # 2. Simulation Step 1: Initialize us-east1 and us-west1 together
    logger.info("Step 1: Initialize both regions and create incident in East")
    east_coordinator = DistributedIncidentCoordinator(
        region="us-east1",
        regional_coordinators=regional_coordinators,
        agent_coordinator=agent_coordinator,
    )
    west_coordinator = DistributedIncidentCoordinator(
        region="us-west1",
        regional_coordinators=regional_coordinators,
        agent_coordinator=agent_coordinator,
    )

    await east_coordinator.initialize_coordination()
    await west_coordinator.initialize_coordination()

    incident_data = {
        "title": "Persistent Failover Test",
        "description": "This incident should survive a crash",
        "severity": "high",
    }
    incident_id = await east_coordinator.detect_incident("us-east1", incident_data)
    logger.info(f"Created incident: {incident_id}")

    # Manually trigger a broadcast from East to West
    await east_coordinator._broadcast_incident_state()

    # Followers need to pull or be notified. In this sim, we pull manually.
    await west_coordinator._sync_from_leader()

    # Verify West has it in memory and on disk
    if incident_id in west_coordinator.active_incidents:
        logger.info("SUCCESS: West received incident via sync")
    else:
        logger.error("FAILURE: West did not receive incident via sync")
        return

    west_state_file = "data/incident_state_us-west1.json"
    if os.path.exists(west_state_file):
        logger.info(f"SUCCESS: West persisted incident to {west_state_file}")
    else:
        logger.error("FAILURE: West failed to persist synced state")
        return

    # 3. Simulation Step 2: Simulate Crash & Partial Recovery
    logger.info("Step 2: Simulate crash of East and re-election of West")

    # Simulate us-east1 dying
    regional_coordinators["us-east1"].is_active = False

    # Trigger election in West
    west_coordinator.leadership_token = await west_coordinator._elect_leader()

    if west_coordinator.leadership_token:
        logger.info("us-west1 successfully elected as new leader")
    else:
        logger.error("us-west1 failed to elect itself as leader")
        return

    # Verify state is still there
    if incident_id in west_coordinator.active_incidents:
        logger.info(f"SUCCESS: Incident {incident_id} handles leader failover")
    else:
        logger.error("FAILURE: Incident lost during failover")
        return

    logger.info("Simulation Complete")

    logger.info("Simulation Complete")


if __name__ == "__main__":
    asyncio.run(run_simulation())
