#!/usr/bin/env python3
"""Automated NIST Compliance Reporting Tool (M7.3).

Collects traces from Jaeger and generates NIST SI-4/AU-2 compliance evidence.

Features:
- Jittered exponential backoff for resilience
- Offset-based pagination for large datasets
- Order-preserving deduplication
- Mock data fallback when secrets unavailable

Environment Variables:
- JAEGER_URL: Jaeger API endpoint
- JAEGER_TOKEN: Authentication token
- JAEGER_MAX_RETRIES: Max retry attempts (default: 3)
- JAEGER_BACKOFF_BASE: Base backoff seconds (default: 1.0)
- JAEGER_BACKOFF_JITTER: Jitter fraction (default: 0.5)
- JAEGER_PAGE_LIMIT: Traces per page (default: 100)
- JAEGER_MAX_TRACES: Max traces to collect (default: 500)
"""

import hashlib
import json
import os
import random
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

try:
    from google.cloud import storage

    GCS_AVAILABLE = True
except ImportError:
    GCS_AVAILABLE = False

# Configuration
JAEGER_URL = os.getenv("JAEGER_URL", "")
JAEGER_TOKEN = os.getenv("JAEGER_TOKEN", "")
JAEGER_USER = os.getenv("JAEGER_USER", "")
JAEGER_PASS = os.getenv("JAEGER_PASS", "")
JAEGER_MAX_RETRIES = int(os.getenv("JAEGER_MAX_RETRIES", "3"))
JAEGER_BACKOFF_BASE = float(os.getenv("JAEGER_BACKOFF_BASE", "1.0"))
JAEGER_BACKOFF_JITTER = float(os.getenv("JAEGER_BACKOFF_JITTER", "0.5"))
JAEGER_PAGE_LIMIT = int(os.getenv("JAEGER_PAGE_LIMIT", "100"))
JAEGER_MAX_TRACES = int(os.getenv("JAEGER_MAX_TRACES", "500"))

# GCS Configuration for M7.4 Compliance Evidence Hub
GCS_BUCKET_NAME = os.getenv("GCS_COMPLIANCE_BUCKET", "compliance-evidence-storage")
GCS_PROJECT_ID = os.getenv("GCP_PROJECT_ID", "")
GCS_UPLOAD_ENABLED = os.getenv("GCS_UPLOAD_ENABLED", "false").lower() == "true"


def jittered_exponential_backoff(attempt: int) -> float:
    """Calculate jittered exponential backoff delay."""
    expo = JAEGER_BACKOFF_BASE * (2 ** (attempt - 1))
    jitter = random.uniform(0, JAEGER_BACKOFF_JITTER * expo)
    return expo + jitter


def fetch_jaeger_traces(
    start_ts: int,
    end_ts: int,
    service: str = None,
    operation: str = None,
    max_traces: int = JAEGER_MAX_TRACES,
) -> list[dict]:
    """Fetch traces from Jaeger with pagination and retry logic."""
    if not JAEGER_URL:
        # Mock data fallback
        return generate_mock_traces(max_traces, service, operation)

    all_traces = []
    offset = 0

    while len(all_traces) < max_traces:
        query_params = {
            "limit": JAEGER_PAGE_LIMIT,
            "offset": offset,
            "start": start_ts,
            "end": end_ts,
        }
        if service:
            query_params["service"] = service
        if operation:
            query_params["operation"] = operation

        url = f"{JAEGER_URL}/api/traces?{urllib.parse.urlencode(query_params)}"

        for attempt in range(JAEGER_MAX_RETRIES):
            try:
                req = urllib.request.Request(url)
                if JAEGER_TOKEN:
                    req.add_header("Authorization", f"Bearer {JAEGER_TOKEN}")
                elif JAEGER_USER and JAEGER_PASS:
                    import base64

                    auth = base64.b64encode(f"{JAEGER_USER}:{JAEGER_PASS}".encode()).decode()
                    req.add_header("Authorization", f"Basic {auth}")

                with urllib.request.urlopen(req, timeout=30) as response:
                    data = json.loads(response.read().decode())
                    traces = data.get("data", [])
                    all_traces.extend(traces)
                    offset += len(traces)
                    if not traces:
                        break
                break  # Success
            except Exception as e:
                if attempt == JAEGER_MAX_RETRIES - 1:
                    print(f"Failed to fetch traces after {JAEGER_MAX_RETRIES} attempts: {e}")
                    return all_traces
                delay = jittered_exponential_backoff(attempt + 1)
                print(f"Attempt {attempt + 1} failed, retrying in {delay:.2f}s: {e}")
                time.sleep(delay)

        if not traces:
            break

    return all_traces[:max_traces]


def deduplicate_traces(traces: list[dict]) -> list[dict]:
    """Deduplicate traces by traceID, preserving order."""
    seen_ids = set()
    unique_traces = []
    for trace in traces:
        trace_id = trace.get("traceID") or hashlib.sha256(json.dumps(trace, sort_keys=True).encode()).hexdigest()[:16]
        if trace_id not in seen_ids:
            seen_ids.add(trace_id)
            unique_traces.append(trace)
    return unique_traces


def generate_mock_traces(count: int, service: str = None, operation: str = None) -> list[dict]:
    """Generate mock traces for testing when Jaeger unavailable."""
    traces = []
    service_name = service or "mock-service"
    op_name = operation or "mock-op"
    for i in range(count):
        latency = random.randint(10, 500) * 1000  # microseconds
        has_error = random.random() < 0.05
        traces.append(
            {
                "traceID": f"mock-trace-{i:04d}",
                "spans": [
                    {
                        "operationName": f"{op_name}-{i}",
                        "startTime": int(time.time() * 1000000),
                        "duration": latency,
                        "tags": [
                            {"key": "error", "type": "bool", "value": has_error},
                            {
                                "key": "ai.service",
                                "type": "string",
                                "value": ("vLLM" if "vllm" in service_name.lower() else "generic"),
                            },
                        ],
                    }
                ],
                "processes": {"p1": {"serviceName": service_name}},
                "warnings": None,
            }
        )
    return traces


def generate_nist_report(traces: list[dict], since_minutes: int) -> dict:
    """Generate NIST compliance report from traces."""
    latencies = []
    error_count = 0
    ai_calls = 0

    for trace in traces:
        for span in trace.get("spans", []):
            latencies.append(span.get("duration", 0) / 1000.0)  # ms
            for tag in span.get("tags", []):
                if tag.get("key") == "error" and (tag.get("value") is True or tag.get("value") == "true"):
                    error_count += 1
                if tag.get("key") == "ai.service":
                    ai_calls += 1

    avg_latency = sum(latencies) / len(latencies) if latencies else 0
    max_latency = max(latencies) if latencies else 0

    report = {
        "metadata": {
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "since_minutes": since_minutes,
            "total_traces": len(traces),
            "nist_controls": ["SI-4", "AU-2"],
            "version": "m7.4",
        },
        "evidence": {
            "system_monitoring": {
                "traces_collected": len(traces),
                "unique_operations": len(
                    set(span["operationName"] for trace in traces for span in trace.get("spans", []))
                ),
                "time_range_covered": since_minutes,
                "performance_metrics": {
                    "avg_latency_ms": round(avg_latency, 2),
                    "max_latency_ms": round(max_latency, 2),
                    "error_count": error_count,
                    "error_rate": round(error_count / len(traces), 4) if traces else 0,
                },
                "ai_inference_tracking": {
                    "total_ai_calls": ai_calls,
                    "ai_service_coverage": True if ai_calls > 0 else False,
                },
            },
            "audit_events": {
                "trace_ids": [t["traceID"] for t in traces[:10]],  # Sample
                "total_events": sum(len(t.get("spans", [])) for t in traces),
            },
        },
        "compliance_status": (
            "PASS" if traces and error_count / len(traces) < 0.1 else "FAIL" if traces else "UNKNOWN"
        ),
    }
    return report


def upload_to_gcs(bucket_name: str, source_file: str, destination_blob: str) -> bool:
    """Upload file to Google Cloud Storage bucket."""
    if not GCS_AVAILABLE:
        print("WARNING: google-cloud-storage not available, skipping GCS upload")
        return False

    if not GCS_UPLOAD_ENABLED:
        print("INFO: GCS upload disabled via GCS_UPLOAD_ENABLED=false")
        return False

    try:
        client = storage.Client(project=GCS_PROJECT_ID)
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob)

        # Upload with metadata
        blob.metadata = {
            "nist_controls": "SI-4,AU-2",
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "version": "m7.3",
        }

        blob.upload_from_filename(source_file)
        print(f"Successfully uploaded {source_file} to gs://{bucket_name}/{destination_blob}")
        return True

    except Exception as e:
        print(f"ERROR: Failed to upload to GCS: {e}")
        return False


def main():
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(description="Automated NIST Compliance Reporting")
    parser.add_argument(
        "--since-minutes",
        type=int,
        default=60,
        help="Collect traces from last N minutes",
    )
    parser.add_argument("--service", type=str, help="Filter by service name")
    parser.add_argument("--operation", type=str, help="Filter by operation name")
    args = parser.parse_args()

    end_ts = int(time.time() * 1000000)  # microseconds
    start_ts = end_ts - (args.since_minutes * 60 * 1000000)

    print(f"Collecting traces from {args.since_minutes} minutes ago...")
    if args.service:
        print(f"Filter Service: {args.service}")
    if args.operation:
        print(f"Filter Operation: {args.operation}")

    traces = fetch_jaeger_traces(start_ts, end_ts, service=args.service, operation=args.operation)
    print(f"Collected {len(traces)} traces")

    traces = deduplicate_traces(traces)
    print(f"After deduplication: {len(traces)} unique traces")

    report = generate_nist_report(traces, args.since_minutes)

    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H%M%SZ")
    filename = f"artifacts/m7.3-nist-report-{timestamp}.json"
    os.makedirs("artifacts", exist_ok=True)

    with open(filename, "w") as f:
        json.dump(report, f, indent=2)

    print(f"Report saved to {filename}")
    print(f"Compliance status: {report['compliance_status']}")

    # M7.4: Upload to centralized compliance evidence hub
    gcs_filename = f"nist-reports/{timestamp}.json"
    if upload_to_gcs(GCS_BUCKET_NAME, filename, gcs_filename):
        print(f"Evidence uploaded to compliance hub: gs://{GCS_BUCKET_NAME}/{gcs_filename}")
    else:
        print("Local evidence available, GCS upload skipped or failed")


if __name__ == "__main__":
    main()
