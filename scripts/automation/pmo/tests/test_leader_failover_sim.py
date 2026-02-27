"""ElevatedIQ: Phase 7.4 Leader Failover Simulation
Verifies leader health monitoring, re-election, and state recovery (NIST-CP-10).
"""

import asyncio
import logging
import os
import sys

# Add workspace to path
sys.path.append(os.getcwd())

from libs.ai_orchestrator.distributed_incident_coordinator import DistributedIncidentCoordinator
from libs.ai_orchestrator.regional_coordinator import FailoverStrategy, RegionalCoordinator

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("LeaderFailoverSim")


async def run_simulation():
    logger.info("Starting Phase 7.4 Leader Failover Simulation")

    # 1. Setup Regional Coordinators
    regions = ["europe-west1", "us-east1", "us-west1"]
    project_id = "elevatediq-test"

    regional_coordinators = {
        region: RegionalCoordinator(
            regions=regions,
            project_id=project_id,
            failover_strategy=FailoverStrategy.AUTOMATIC,
        )
        for region in regions
    }

    # 2. Initialize Coordinators for all regions (to simulate a distributed cluster)
    coordinators = {}
    for region in regions:
        coordinators[region] = DistributedIncidentCoordinator(
            region=region, regional_coordinators=regional_coordinators
        )
        # Mark the RegionalCoordinator objects as leader if applicable
        # (In real life this is internal state, but here we manually sync for sim)
        await coordinators[region].initialize_coordination()

    # 3. Verify europe-west1 is leader
    status_europe = await coordinators["europe-west1"].get_coordination_status()
    if not status_europe["is_leader"]:
        logger.error("FAILURE: europe-west1 not elected as leader initially")
        return

    # Manually mark the backing RegionalCoordinator as leader for others to see
    regional_coordinators["europe-west1"].is_currently_leader = True
    logger.info("europe-west1 is leader")

    # 4. Detect an incident while europe-west1 is leader
    incident_data = {
        "title": "Network Latency us-east1",
        "description": "Cross-region latency spike detected",
        "severity": "medium",
    }
    incident_id = await coordinators["europe-west1"].detect_incident("us-east1", incident_data)
    logger.info(f"Incident {incident_id} detected by leader europe-west1")

    # 5. Broadcast state to followers (to ensure they have it before failover)
    await coordinators["europe-west1"]._broadcast_incident_state()
    logger.info("Incident state broadcasted to followers")

    # Manually trigger sync on followers
    await coordinators["us-east1"]._sync_from_leader()
    await coordinators["us-west1"]._sync_from_leader()
    logger.info("Followers synced from leader")

    # Verify us-east1 has the incident
    if incident_id not in coordinators["us-east1"].active_incidents:
        logger.error("FAILURE: us-east1 follower did not receive initial incident state")
        return

    # 6. FAILOVER: Kill europe-west1 leader
    logger.info("!!! KILLING LEADER europe-west1 !!!")
    regional_coordinators["europe-west1"].is_active = False
    regional_coordinators["europe-west1"].is_currently_leader = False

    # 7. Wait for us-east1 heartbeat monitor to detect failure and trigger re-election
    logger.info("Waiting for us-east1 to detect failure and trigger re-election...")
    # In DistributedIncidentCoordinator, heartbeat check is every 30s.
    # We'll manually trigger it for the simulation to save time.

    # us-east1's monitor loop
    await coordinators["us-east1"]._heartbeat_monitor_tick()

    status_east = await coordinators["us-east1"].get_coordination_status()
    if status_east["is_leader"]:
        logger.info("SUCCESS: us-east1 elected as NEW leader")
    else:
        logger.error("FAILURE: us-east1 failed to become leader")
        return

    # 8. Verify State Recovery (NIST-CP-10)
    # The new leader should have the incident state
    incident = coordinators["us-east1"].get_incident_by_id(incident_id)
    if incident and incident.incident_id == incident_id:
        logger.info(f"SUCCESS: Incident {incident_id} recovered by new leader us-east1")
    else:
        logger.error("FAILURE: Incident state lost after failover")
        return

    logger.info("Leader Failover Simulation Complete")


# Add a hacky method to trigger a single tick of heartbeat monitor for testing
async def _heartbeat_monitor_tick(self):
    if not self.leadership_token:
        leader_healthy = await self._check_leader_health()
        if not leader_healthy:
            logger.warning("Leader appears unhealthy, triggering re-election")
            self.leadership_token = await self._elect_leader()


DistributedIncidentCoordinator._heartbeat_monitor_tick = _heartbeat_monitor_tick

if __name__ == "__main__":
    asyncio.run(run_simulation())
