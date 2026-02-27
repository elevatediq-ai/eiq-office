# Service Configuration
SERVICE_NAME=my-service
SERVICE_PORT=8080
SERVICE_LOG_LEVEL=INFO

# Python Environment
PYTHONUNBUFFERED=1
PYTHONDONTWRITEBYTECODE=1

# Database (if applicable)
DATABASE_URL=postgresql://user:password@localhost:5432/db_name
DATABASE_POOL_SIZE=10

# AWS Configuration (if applicable)
AWS_REGION=us-gov-west-1
AWS_DEFAULT_REGION=us-gov-west-1

# Redis Cache (if applicable)
REDIS_URL=redis://localhost:6379

# Feature Flags
FEATURE_FLAG_DEBUG=false
FEATURE_FLAG_EXPERIMENTAL=false

# Security & Compliance
SECRETS_VAULT_PATH=/vault/secrets
TLS_ENABLED=true
FIPS_MODE=false

# Monitoring & Observability
JAEGER_ENABLED=false
PROMETHEUS_METRICS_PORT=9090
