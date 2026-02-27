"""GCP Secret Manager helper for OfficeIQ

Provides a simple, production-oriented wrapper that mirrors the ElevatedIQ
pattern: primary GCP Secret Manager retrieval, in-memory caching, and an
environment-variable fallback for local/dev.

Usage:
    from libs.secrets.gcp_secret_manager import GCPSecretManager
    sm = GCPSecretManager(project_id="my-gcp-project")
    value = sm.get_secret("DATABASE_PASSWORD")
"""

from __future__ import annotations

import os
import logging
from datetime import datetime, timedelta
from typing import Optional

logger = logging.getLogger(__name__)

try:
    from google.cloud import secretmanager
    GCP_AVAILABLE = True
except Exception:
    secretmanager = None  # type: ignore
    GCP_AVAILABLE = False


class SecretAccessError(Exception):
    pass


class GCPSecretManager:
    def __init__(self, project_id: Optional[str] = None, cache_ttl_seconds: int = 300, fallback_to_env: bool = True):
        self.project_id = project_id or os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT_ID")
        self.cache_ttl = timedelta(seconds=cache_ttl_seconds)
        self.fallback_to_env = fallback_to_env
        self._cache: dict[str, tuple[str, datetime]] = {}
        self.client = None

        if GCP_AVAILABLE and self.project_id:
            try:
                self.client = secretmanager.SecretManagerServiceClient()
                logger.info("GCP Secret Manager client initialized", extra={"project": self.project_id})
            except Exception as e:
                logger.warning(f"Failed to initialize Secret Manager client: {e}")
                self.client = None

    def _cache_get(self, name: str) -> Optional[str]:
        v = self._cache.get(name)
        if not v:
            return None
        val, ts = v
        if datetime.utcnow() - ts > self.cache_ttl:
            del self._cache[name]
            return None
        return val

    def _cache_set(self, name: str, value: str) -> None:
        self._cache[name] = (value, datetime.utcnow())

    def get_secret(self, secret_id: str, version: str = "latest") -> str:
        # 1) cache
        cached = self._cache_get(secret_id)
        if cached is not None:
            return cached

        # 2) GCP Secret Manager
        if self.client and self.project_id:
            try:
                resource_name = f"projects/{self.project_id}/secrets/{secret_id}/versions/{version}"
                resp = self.client.access_secret_version(request={"name": resource_name})
                payload = resp.payload.data.decode("utf-8")
                self._cache_set(secret_id, payload)
                logger.info("Retrieved secret from GCP", extra={"secret_id": secret_id})
                return payload
            except Exception as e:
                logger.warning(f"GCP Secret Manager access failed for {secret_id}: {e}")

        # 3) fallback to env (only for dev/test)
        if self.fallback_to_env:
            env_key = secret_id.upper().replace("-", "_")
            env_val = os.environ.get(env_key)
            if env_val is not None:
                logger.warning(f"Using environment fallback for secret {secret_id}")
                self._cache_set(secret_id, env_val)
                return env_val

        raise SecretAccessError(f"Unable to retrieve secret '{secret_id}' from GCP Secret Manager or environment")
