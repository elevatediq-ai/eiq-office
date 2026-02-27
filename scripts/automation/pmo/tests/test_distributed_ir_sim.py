"""ElevatedIQ: Phase 7.4 Distributed Incident Response Simulation
Verifies distributed coordination, leader election, and autonomous agent routing.
"""

import asyncio
import logging
import os
import sys

# Add workspace to path
sys.path.append(os.getcwd())

from apps.control_plane.src.control_plane.agent_coordinator.coordinator import AgentCoordinator

from libs.ai_orchestrator.distributed_incident_coordinator import (
    DistributedIncidentCoordinator,
    IncidentSeverity,
    IncidentStatus,
)
from libs.ai_orchestrator.regional_coordinator import FailoverStrategy, RegionalCoordinator

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("DistributedIRSim")


async def run_simulation():
    logger.info("Starting Phase 7.4 Distributed IR Simulation")

    # 1. Setup Regional Coordinators
    regions = ["us-east1", "us-west1", "europe-west1"]
    project_id = "elevatediq-test"

    # Create regional coordinator instances for each region
    regional_coordinators = {
        region: RegionalCoordinator(
            regions=regions,
            project_id=project_id,
            failover_strategy=FailoverStrategy.AUTOMATIC,
        )
        for region in regions
    }

    # 2. Setup Agent Coordinator
    agent_coordinator = AgentCoordinator()

    # 3. Initialize Distributed Incident Coordinator for europe-west1
    primary_region = "europe-west1"
    coordinator = DistributedIncidentCoordinator(
        region=primary_region,
        regional_coordinators=regional_coordinators,
        agent_coordinator=agent_coordinator,
    )

    logger.info(f"Initializing coordination for {primary_region}")
    await coordinator.initialize_coordination()

    # 4. Verify Leader Election
    status = await coordinator.get_coordination_status()
    logger.info(f"Coordination Status: {status}")

    if status["is_leader"]:
        logger.info(f"SUCCESS: {primary_region} elected as leader (first in sorted list)")
    else:
        logger.error(f"FAILURE: {primary_region} not elected as leader")
        return

    # 5. Simulate Incident Detection in us-west1 (ML Triage will derive capability)
    logger.info("Simulating incident detection in us-west1")
    incident_data = {
        "title": "Critical Database Connection pool exhaustion",
        "description": "Prod DB cluster in us-west1 is reporting 100% pool usage. Potential outage.",
        "severity": "medium",
        "resource_id": "db-cluster-west",
    }

    incident_id = await coordinator.detect_incident("us-west1", incident_data)
    logger.info(f"Incident Created: {incident_id}")

    # 6. Verify Incident State & Triaging
    incident = coordinator.get_incident_by_id(incident_id)
    if not incident:
        logger.error("FAILURE: Incident not found in coordinator")
        return

    logger.info(f"Initial Incident Status: {incident.status}")
    logger.info(f"ML Category: {incident.metadata.get('ml_category')}")
    logger.info(f"Adjusted Severity: {incident.severity}")

    if incident.severity != IncidentSeverity.CRITICAL:
        logger.error(f"FAILURE: ML Triager failed to escalate severity. Got: {incident.severity}")
        return

    if incident.metadata.get("ml_category") != "database":
        logger.error(f"FAILURE: ML Triager failed to classify as database. Got: {incident.metadata.get('ml_category')}")
        return

    # 7. Escalate and Verify Agent Routing
    # ML Triager might have already TRIAGED it if it escalated severity
    if incident.status != IncidentStatus.TRIAGED:
        logger.info(f"Manually escalating incident {incident_id} to trigger autonomous routing")
        await coordinator.escalate_incident(incident_id, IncidentSeverity.CRITICAL)
    else:
        logger.info("Triggering routing for already triaged incident")
        await coordinator._trigger_escalation_workflows(incident)

    # Re-fetch incident
    incident = coordinator.get_incident_by_id(incident_id)
    logger.info(f"Post-Escalation Status: {incident.status}")
    logger.info(f"Assigned Team/Agent: {incident.assigned_team}")

    if incident.status == IncidentStatus.TRIAGED and incident.assigned_team == "database-optimization-agent":
        logger.info("SUCCESS: Incident correctly routed to database-optimization-agent")
    else:
        logger.error(f"FAILURE: Routing failed. Status: {incident.status}, Assigned: {incident.assigned_team}")

    # 8. Verify coordination sync (simulated)
    await coordinator._broadcast_incident_state()
    logger.info("States broadcasted to all regions")

    # 9. Clean up / Resolve
    await coordinator.resolve_incident(incident_id, "Auto-remediated by database-optimization-agent")
    logger.info("Simulation Complete")


if __name__ == "__main__":
    asyncio.run(run_simulation())
