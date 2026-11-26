#!/usr/bin/env bash
# Round-trip test: all migrations up -> seed twice -> smoke test -> all down -> up again.
# Usage: DATABASE_URL=postgres://user:pass@localhost:5432/autohub_test ./backend/db/test-schema.sh
# WARNING: drops everything in the target database's public schema. Use a throwaway DB.
set -euo pipefail
cd "$(dirname "$0")"
: "${DATABASE_URL:?set DATABASE_URL to a throwaway database}"
P=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q)

up()   { for f in migrations/*.sql;       do awk '/^-- migrate:up/{f=1;next}/^-- migrate:down/{f=0}f' "$f" | "${P[@]}"; done; }
down() { for f in $(ls -r migrations/*.sql); do awk '/^-- migrate:down/{f=1;next}f' "$f" | "${P[@]}"; done; }

up                                   && echo "✓ migrations up"
"${P[@]}" -f seeds/001_reference_data.sql
"${P[@]}" -f seeds/001_reference_data.sql && echo "✓ seed is idempotent"
"${P[@]}" -f tests/schema_smoke_test.sql 2>&1 | grep -E "ok \(rejected\)|PASSED|ERROR"
down                                 && echo "✓ migrations down"
up                                   && echo "✓ migrations up again"
