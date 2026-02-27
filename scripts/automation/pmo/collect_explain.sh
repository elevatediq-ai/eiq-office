#!/usr/bin/env bash
set -euo pipefail

# collect_explain.sh
# Usage: export PG_CONN="postgresql://user:pass@host:5432/dbname" && ./collect_explain.sh
# The script requires psql in PATH and read-only access to the target DB with pg_stat_statements enabled.

OUTDIR="reports/m4.1-explains"
mkdir -p "$OUTDIR"

if [[ -z "${PG_CONN:-}" ]]; then
  echo "ERROR: PG_CONN env var not set. Example: export PG_CONN=\"postgresql://user:pass@host:5432/db\""
  exit 2
fi

echo "Collecting top queries from pg_stat_statements..."

TMPSQL="/tmp/eiq_top_queries.sql"
cat > "$TMPSQL" <<'SQL'
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
WHERE query IS NOT NULL
ORDER BY total_time DESC
LIMIT 50;
SQL

psql "$PG_CONN" -t -A -F $'\t' -f "$TMPSQL" | nl -ba | while IFS=$'\t' read -r idx query calls total_time mean_time rows; do
  # sanitize idx for filename
  file="$OUTDIR/query_$(printf "%02d" "$idx").sql"
  echo "-- Query #$idx  calls=$calls total_time=$total_time mean_time=$mean_time rows=$rows" > "$file"
  echo "$query" >> "$file"
  echo "Running EXPLAIN (ANALYZE, BUFFERS) for query #$idx..."
  # Use psql here to run EXPLAIN; wrap query in parentheses to support complex statements
  psql "$PG_CONN" -v ON_ERROR_STOP=1 -c "EXPLAIN (ANALYZE, BUFFERS) ${query};" >> "$file" 2>&1 || echo "EXPLAIN failed for query #$idx (saved partial output)"
done

echo "EXPLAIN outputs saved to $OUTDIR"
