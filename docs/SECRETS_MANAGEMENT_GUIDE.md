# Secrets Management Guide — OfficeIQ

This document adapts the ElevatedIQ approach: use GCP Secret Manager (GSM) as
single source-of-truth, implement Workload Identity for GitHub Actions, and
provide safe fallbacks for local dev.

Key practices

- GSM = canonical: Store production secrets in Google Secret Manager.
- Semantic names: `SERVICE_RESOURCE_ENV` (e.g. `DATABASE_PASSWORD_PROD`).
- Least privilege: create dedicated service accounts with `roles/secretmanager.secretAccessor`.
- Audit & monitoring: export GSM access logs to Cloud Storage and enable alerts.
- CI: Use Workload Identity Federation (WIF) + `google-github-actions/auth@v2`.
- Local dev: allow environment-variable fallback only for non-prod.

Quick commands

- Enable Secret Manager API:

```bash
gcloud services enable secretmanager.googleapis.com --project=MY_PROJECT
```

- Create a secret:

```bash
echo -n "supersecret" | gcloud secrets create DATABASE_PASSWORD_PROD \
  --data-file=- --project=MY_PROJECT
```

- Access from code (python):

```py
from libs.secrets.gcp_secret_manager import GCPSecretManager
sm = GCPSecretManager(project_id="MY_PROJECT")
password = sm.get_secret("DATABASE_PASSWORD_PROD")
```

GitHub Actions pattern

Use Workload Identity + `google-github-actions/auth@v2` to avoid storing long-lived
PATs or service account keys in GitHub. Example workflow is in
`.github/workflows/ci-gsm-example.yml`.

Migration plan (high level)

1. Inventory current secrets (Audit): `gcloud secrets list` and `gh actions secrets list`.
2. Create secrets in GSM and tag with `managed-by=terraform` where appropriate.
3. Add WIF provider and SA with `roles/secretmanager.secretAccessor`.
4. Update workflows to authenticate using `google-github-actions/auth@v2` and fetch secrets via `gcloud secrets versions access latest`.
5. Monitor usage and revoke GitHub repo secrets after validation.

References

- Google: Workload Identity Federation for GitHub Actions
- ElevatedIQ `SECRETS_MANAGEMENT_GUIDE.md` (pattern inspiration)
