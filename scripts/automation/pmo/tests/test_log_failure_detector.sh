#!/usr/bin/env bash
set -euo pipefail

# Simple test harness for log_failure_detector.sh
TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Detector scans WORKSPACE_ROOT/logs by default; create test files there
WORKSPACE_ROOT=$(cd "${TEST_ROOT}/../.." && pwd)
LOG_DIR="${WORKSPACE_ROOT}/logs"
SCRIPT="${TEST_ROOT}/log_failure_detector.sh"

rm -rf "${LOG_DIR}"
mkdir -p "${LOG_DIR}"

# Create a benign terraform-like file that should be excluded
cat > "${LOG_DIR}/example.tf" <<EOF
# Terraform plan
resource "aws_s3_bucket" "b" {}
EOF

# Create a log with a simulated panic
cat > "${LOG_DIR}/app.log" <<EOF
2026-02-06T20:00:00Z INFO starting
2026-02-06T20:01:00Z ERROR panic: Unhandled panic in runtime: nil pointer deref
2026-02-06T20:02:00Z INFO done
EOF

# Run the detector in dry-run and capture output
chmod +x "${SCRIPT}"
output=$("${SCRIPT}" --dry-run 2>&1 || true)

echo "---- DETECTOR OUTPUT ----"
echo "$output"

echo "$output" | grep -q "Would create issue" || { echo "Test failed: expected dry-run to indicate issue creation"; exit 2; }

echo "Test passed: dry-run detected expected failure and did not create an issue."

# Cleanup
rm -rf "${LOG_DIR}"
exit 0
#!/usr/bin/env bash
set -euo pipefail

# Simple test harness for log_failure_detector.sh
TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Detector scans WORKSPACE_ROOT/logs by default; create test files there
WORKSPACE_ROOT=$(cd "${TEST_ROOT}/.." && pwd)
LOG_DIR="${WORKSPACE_ROOT}/logs"
SCRIPT="${TEST_ROOT}/log_failure_detector.sh"

rm -rf "${LOG_DIR}"
mkdir -p "${LOG_DIR}"

# Create a benign terraform file that should be excluded
cat > "${LOG_DIR}/example.tf" <<EOF
# Terraform plan
resource "aws_s3_bucket" "b" {}
EOF

# Create a log with a simulated panic
cat > "${LOG_DIR}/app.log" <<EOF
2026-02-06T20:00:00Z INFO starting
2026-02-06T20:01:00Z ERROR panic: Unhandled panic in runtime: nil pointer deref
2026-02-06T20:02:00Z INFO done
EOF

# Run the detector in dry-run and capture output
output=$("${SCRIPT}" --dry-run 2>&1)

echo "---- DETECTOR OUTPUT ----"
echo "$output"

echo "$output" | grep -q "Would create issue" || { echo "Test failed: expected dry-run to indicate issue creation"; exit 2; }

echo "Test passed: dry-run detected expected failure and did not create an issue."

# Cleanup
rm -rf "${LOG_DIR}"
exit 0
