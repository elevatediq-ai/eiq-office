# Explain collection runbook

Purpose
- Provide a safe, repeatable script to collect `EXPLAIN (ANALYZE, BUFFERS)` output for the top queries captured by `pg_stat_statements`.

Prereqs
- `psql` on the runner machine
- Read-only DB access with `pg_stat_statements` enabled on the target Postgres instance
- Export `PG_CONN` environment variable with a connection string (URI form)

Quick run
```bash
export PG_CONN="postgresql://readonly_user:password@staging-db.example.com:5432/elevatediq"
./scripts/pmo/collect_explain.sh
```

Notes & safety
- The script is read-only but runs `EXPLAIN (ANALYZE)` which executes the queries; run only on staging or a read-replica.
- If credentials cannot be provided, the script can be run by a trusted operator in staging and the generated `reports/m4.1-explains/` artifacts can be shared.

Output
- EXPLAIN outputs are written to `reports/m4.1-explains/query_XX.sql` with a header containing metadata from `pg_stat_statements`.

Next steps after collection
- Review top explain outputs and add them to PRs alongside suggested indexes or rewrites.
- Attach selected explain files to Issue #2881 for visibility.
