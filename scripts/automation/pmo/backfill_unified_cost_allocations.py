#!/usr/bin/env python3
"""[NIST-AU-2] Production Backfill Script for Unified Cost Allocations
Backfills unified_cost_allocations table from multi_cloud_cost_facts.
Part of Phase 9.4: Real-Time Cost Attribution.

Usage:
    python backfill_unified_cost_allocations.py [--org-id ORG_ID] [--dry-run] [--batch-size 1000]

Options:
    --org-id ORG_ID    Backfill for specific org_id (default: all)
    --dry-run         Show what would be done without executing
    --batch-size      Process in batches (default: 1000)
"""

import argparse
import asyncio
import logging
import os
import sys
from datetime import datetime

# Add workspace root to path
repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)

# Provide alias for hyphenated package path used elsewhere in repo (tests follow same pattern)
# This allows imports like `apps.intelligence_api.intelligence_api` to resolve correctly.
import importlib.util

spec = importlib.util.spec_from_file_location(
    "apps.intelligence_api",
    os.path.join(repo_root, "apps", "intelligence-api", "__init__.py"),
)
if spec and spec.loader:
    module = importlib.util.module_from_spec(spec)
    sys.modules["apps.intelligence_api"] = module
    spec.loader.exec_module(module)

spec2 = importlib.util.spec_from_file_location(
    "apps.intelligence_api.intelligence_api",
    os.path.join(repo_root, "apps", "intelligence-api", "intelligence_api", "__init__.py"),
)
if spec2 and spec2.loader:
    module2 = importlib.util.module_from_spec(spec2)
    sys.modules["apps.intelligence_api.intelligence_api"] = module2
    spec2.loader.exec_module(module2)

from apps.intelligence_api.intelligence_api.models import MultiCloudCostFact, UnifiedCostAllocation
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from libs.finops.allocation_engine import AllocationEngine

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


class BackfillManager:
    """BackfillManager class."""

    def __init__(self, db_session, dry_run: bool = False):
        self.db = db_session
        self.dry_run = dry_run

    async def get_org_ids(self) -> list[str]:
        """Get all unique org_ids from cost facts."""
        stmt = select(MultiCloudCostFact.org_id).distinct()
        result = await self.db.execute(stmt)
        return [row[0] for row in result.fetchall()]

    async def backfill_org(self, org_id: str) -> dict:
        """Backfill allocations for a single org."""
        logger.info(f"🔄 Backfilling allocations for org: {org_id}")

        if self.dry_run:
            # Count facts for this org
            stmt = select(func.count()).select_from(MultiCloudCostFact).where(MultiCloudCostFact.org_id == org_id)
            result = await self.db.execute(stmt)
            fact_count = result.scalar_one()
            logger.info(f"📊 Would process {fact_count} cost facts for {org_id}")
            return {"org_id": org_id, "status": "dry_run", "fact_count": fact_count}

        # Check if allocations already exist
        stmt = select(func.count()).select_from(UnifiedCostAllocation).where(UnifiedCostAllocation.org_id == org_id)
        result = await self.db.execute(stmt)
        existing_count = result.scalar_one()

        if existing_count > 0:
            logger.warning(f"⚠️ Allocations already exist for {org_id} ({existing_count} records). Skipping.")
            return {
                "org_id": org_id,
                "status": "skipped",
                "existing_count": existing_count,
            }

        # Run allocation
        engine = AllocationEngine(self.db)
        result = await engine.run_allocation(org_id)

        logger.info(f"✅ Backfilled {result.get('total_allocated', 0)} allocations for {org_id}")
        return {"org_id": org_id, "status": "completed", **result}

    async def run_backfill(self, org_id: str | None = None, batch_size: int = 1000) -> dict:
        """Run backfill for specified org or all orgs."""
        logger.info("🚀 Starting Unified Cost Allocations Backfill")
        logger.info(f"Mode: {'DRY RUN' if self.dry_run else 'PRODUCTION'}")

        if org_id:
            results = [await self.backfill_org(org_id)]
        else:
            org_ids = await self.get_org_ids()
            logger.info(f"📋 Found {len(org_ids)} organizations to process")

            results = []
            for i in range(0, len(org_ids), batch_size):
                batch = org_ids[i : i + batch_size]
                logger.info(f"🔄 Processing batch {i // batch_size + 1}: {len(batch)} orgs")

                batch_results = await asyncio.gather(*[self.backfill_org(oid) for oid in batch])
                results.extend(batch_results)

        summary = {
            "total_orgs": len(results),
            "completed": len([r for r in results if r["status"] == "completed"]),
            "skipped": len([r for r in results if r["status"] == "skipped"]),
            "dry_run": len([r for r in results if r["status"] == "dry_run"]),
            "total_allocations": sum(r.get("total_allocated", 0) for r in results),
            "timestamp": datetime.now().isoformat(),
        }

        logger.info("📊 Backfill Summary:")
        logger.info(f"  - Organizations processed: {summary['total_orgs']}")
        logger.info(f"  - Completed: {summary['completed']}")
        logger.info(f"  - Skipped: {summary['skipped']}")
        logger.info(f"  - Total allocations created: {summary['total_allocations']}")

        return summary


async def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Backfill Unified Cost Allocations")
    parser.add_argument("--org-id", help="Specific org_id to backfill")
    parser.add_argument("--dry-run", action="store_true", help="Dry run mode")
    parser.add_argument("--batch-size", type=int, default=1000, help="Batch size for processing")
    parser.add_argument(
        "--database-url",
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/intelligence",
        help="Database connection URL",
    )

    args = parser.parse_args()

    # Create database connection
    engine = create_async_engine(args.database_url, echo=False)
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with AsyncSessionLocal() as session:
        backfill = BackfillManager(session, dry_run=args.dry_run)
        try:
            await backfill.run_backfill(org_id=args.org_id, batch_size=args.batch_size)
            logger.info("✅ Backfill completed successfully")
            return 0
        except Exception as e:
            logger.error(f"❌ Backfill failed: {e}")
            return 1
        finally:
            await engine.dispose()


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
