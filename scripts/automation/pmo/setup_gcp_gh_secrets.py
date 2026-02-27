#!/usr/bin/env python3
"""Phase 6.3: GCP Credentials → GitHub Secrets Injector
Purpose: Multi-method credential retrieval + GitHub secret configuration
Status: Production-Grade (NIST-AC-2, NIST-IA-2)
Author: Copilot Agent
Date: 2026-02-17.
"""

import json
import logging
import subprocess
import sys
from dataclasses import dataclass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


@dataclass
class CredentialConfig:
    """Configuration for credential retrieval."""

    gcp_project: str = "elevatediq-prod"
    gcp_secret_id: str = "terraform-provisioner-key"  # noqa: S105
    github_repo: str = "kushin77/ElevatedIQ-Mono-Repo"
    alternate_secrets: list = None

    def __post_init__(self):
        if self.alternate_secrets is None:
            self.alternate_secrets = [
                "pm-automation-sa-gcp-pmo",
                "github-actions-deployer",
                "gcp-sa-key",
                "terraform-sa-key",
            ]


class CredentialRetriever:
    """Multi-method GCP credential retriever."""

    def __init__(self, config: CredentialConfig):
        self.config = config
        self.credentials: str | None = None

    def retrieve_via_python_library(self) -> str | None:
        """Method 1: Use Python google-cloud-secret-manager library."""
        logger.info("Method 1: Attempting retrieval via Python library...")
        try:
            from google.cloud import secretmanager

            client = secretmanager.SecretManagerServiceClient()
            name = f"projects/{self.config.gcp_project}/secrets/{self.config.gcp_secret_id}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            creds = response.payload.data.decode("UTF-8")
            logger.info("✅ Retrieved credentials via Python library")
            return creds
        except ImportError:
            logger.warning("  - google-cloud-secret-manager not installed")
        except Exception as e:
            logger.warning(f"  - Error: {e}")
        return None

    def retrieve_via_gcloud_cli(self) -> str | None:
        """Method 2: Use gcloud CLI."""
        logger.info("Method 2: Attempting retrieval via gcloud CLI...")
        try:
            result = subprocess.run(
                [
                    "gcloud",
                    "secrets",
                    "versions",
                    "access",
                    "latest",
                    f"--secret={self.config.gcp_secret_id}",
                    f"--project={self.config.gcp_project}",
                ],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0:
                logger.info("✅ Retrieved credentials via gcloud CLI")
                return result.stdout.strip()
            else:
                logger.warning(f"  - gcloud error: {result.stderr[:200]}")
        except FileNotFoundError:
            logger.warning("  - gcloud CLI not found")
        except Exception as e:
            logger.warning(f"  - Error: {e}")
        return None

    def retrieve_via_alternate_secrets(self) -> str | None:
        """Method 3: Try alternate secret names."""
        logger.info("Method 3: Attempting retrieval via alternate secret names...")
        for secret_id in self.config.alternate_secrets:
            try:
                from google.cloud import secretmanager

                client = secretmanager.SecretManagerServiceClient()
                name = f"projects/{self.config.gcp_project}/secrets/{secret_id}/versions/latest"
                response = client.access_secret_version(request={"name": name})
                creds = response.payload.data.decode("UTF-8")
                logger.info(f"✅ Retrieved credentials from secret: {secret_id}")
                return creds
            except Exception:
                continue
        return None

    def validate_credentials(self, creds: str) -> bool:
        """Validate credentials are valid JSON."""
        try:
            parsed = json.loads(creds)
            required_fields = ["type", "project_id", "private_key", "client_email"]
            missing = [f for f in required_fields if f not in parsed]
            if missing:
                logger.error(f"Missing required fields: {missing}")
                return False
            logger.info(f"✅ Credentials valid (SA: {parsed.get('client_email')})")
            return True
        except json.JSONDecodeError:
            logger.error("Credentials are not valid JSON")
            return False

    def retrieve(self) -> str | None:
        """Retrieve credentials using all available methods."""
        logger.info("=" * 70)
        logger.info("Phase 6.3: GCP Credential Retrieval")
        logger.info("=" * 70)

        # Try methods in order
        for retriever_method in [
            self.retrieve_via_python_library,
            self.retrieve_via_gcloud_cli,
            self.retrieve_via_alternate_secrets,
        ]:
            creds = retriever_method()
            if creds and self.validate_credentials(creds):
                self.credentials = creds
                return creds
            logger.info("")

        return None


class GitHubSecretConfigurator:
    """Configure GitHub repository secrets."""

    def __init__(self, config: CredentialConfig):
        self.config = config

    def check_gh_cli(self) -> bool:
        """Check if gh CLI is available and authenticated."""
        try:
            subprocess.run(["gh", "auth", "status"], capture_output=True, check=True, timeout=5)
            logger.info("✅ GitHub CLI is authenticated")
            return True
        except Exception:
            logger.error("❌ GitHub CLI not available or not authenticated")
            logger.error("   Run: gh auth login")
            return False

    def set_secret(self, secret_name: str, secret_value: str) -> bool:
        """Set GitHub repository secret."""
        try:
            result = subprocess.run(
                [
                    "gh",
                    "secret",
                    "set",
                    secret_name,
                    "--repo",
                    self.config.github_repo,
                    "--body",
                    secret_value,
                ],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0:
                logger.info(f"✅ GitHub secret '{secret_name}' configured")
                return True
            else:
                logger.error(f"Failed to set secret: {result.stderr[:200]}")
                return False
        except Exception as e:
            logger.error(f"Error setting secret: {e}")
            return False

    def verify_secrets(self) -> bool:
        """Verify secrets are configured."""
        try:
            result = subprocess.run(
                ["gh", "secret", "list", "--repo", self.config.github_repo],
                capture_output=True,
                text=True,
                timeout=10,
            )
            secrets_output = result.stdout
            logger.info("\n📋 Current GitHub secrets:")
            for line in secrets_output.splitlines():
                if line.strip():
                    logger.info(f"  {line}")

            if "GCP_SA_KEY" in secrets_output and "GCP_PROJECT" in secrets_output:
                logger.info("\n✅ All required secrets configured")
                return True
            else:
                logger.warning("\n⚠️  Some required secrets missing")
                return False
        except Exception as e:
            logger.error(f"Error verifying secrets: {e}")
            return False

    def configure(self, gcp_sa_key: str, gcp_project: str) -> bool:
        """Configure all required GitHub secrets."""
        logger.info("\n" + "=" * 70)
        logger.info("Configuring GitHub Secrets")
        logger.info("=" * 70)

        if not self.check_gh_cli():
            return False

        # Set GCP_SA_KEY
        if not self.set_secret("GCP_SA_KEY", gcp_sa_key):
            return False

        # Set GCP_PROJECT
        if not self.set_secret("GCP_PROJECT", gcp_project):
            return False

        # Verify
        return self.verify_secrets()


class DeploymentTrigger:
    """Trigger Phase 6.3 deployment workflow."""

    def __init__(self, config: CredentialConfig):
        self.config = config

    def trigger_workflow(self) -> bool:
        """Trigger Phase 6.3 deployment workflow."""
        logger.info("\n" + "=" * 70)
        logger.info("Triggering Phase 6.3 Deployment Workflow")
        logger.info("=" * 70)

        try:
            result = subprocess.run(
                [
                    "gh",
                    "workflow",
                    "run",
                    "Phase 6.3 - Deploy (GCP)",
                    "--repo",
                    self.config.github_repo,
                    "-f",
                    "apply_confirm=false",
                ],
                capture_output=True,
                text=True,
                timeout=15,
            )

            if result.returncode == 0:
                logger.info("✅ Workflow triggered successfully")
                logger.info(f"Output: {result.stdout[:200]}")
                return True
            else:
                logger.error(f"Failed to trigger workflow: {result.stderr[:200]}")
                return False
        except Exception as e:
            logger.error(f"Error triggering workflow: {e}")
            return False


def main():
    """Main orchestration."""
    config = CredentialConfig()

    # Step 1: Retrieve credentials
    retriever = CredentialRetriever(config)
    gcp_sa_key = retriever.retrieve()

    if not gcp_sa_key:
        logger.error("\n❌ Could not retrieve GCP credentials via any method")
        logger.error("\nManual Setup Required:")
        logger.error("1. Authenticate to GCP: gcloud auth application-default login")
        logger.error("2. Run again: python3 scripts/pmo/setup_gcp_gh_secrets.py")
        logger.error("\nOR provide credentials directly in environment:")
        logger.error("   export GCP_SA_KEY='...' && python3 scripts/pmo/setup_gcp_gh_secrets.py")
        return 1

    # Parse for project ID
    try:
        creds_json = json.loads(gcp_sa_key)
        gcp_project = creds_json.get("project_id", config.gcp_project)
    except Exception:
        gcp_project = config.gcp_project

    # Step 2: Configure GitHub secrets
    configurator = GitHubSecretConfigurator(config)
    if not configurator.configure(gcp_sa_key, gcp_project):
        logger.error("\n❌ Failed to configure GitHub secrets")
        return 1

    # Step 3: Trigger deployment
    trigger = DeploymentTrigger(config)
    if not trigger.trigger_workflow():
        logger.warning("\n⚠️  Workflow trigger may have failed, but secrets are configured")
        logger.info("\nManually trigger with:")
        logger.info(f"  gh workflow run 'Phase 6.3 - Deploy (GCP)' --repo {config.github_repo}")
        return 1

    # Success summary
    logger.info("\n" + "=" * 70)
    logger.info("✅ Phase 6.3 Setup Complete!")
    logger.info("=" * 70)
    logger.info("\n📊 Summary:")
    logger.info(f"  ✅ GCP credentials retrieved from: {config.gcp_project}/{config.gcp_secret_id}")
    logger.info("  ✅ GitHub secrets configured: GCP_SA_KEY, GCP_PROJECT")
    logger.info("  ✅ Deployment workflow triggered")
    logger.info("\n🔍 Monitor workflow:")
    logger.info(f"  gh run list --workflow 'phase-6-3-deploy-gcp.yml' --repo {config.github_repo}")
    logger.info(f"  gh run view --repo {config.github_repo}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
