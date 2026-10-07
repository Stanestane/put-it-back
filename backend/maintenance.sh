#!/bin/bash
set -euo pipefail
cd /opt/put-it-back/backend
# 90 days of raw events; one year of first-observed cohort metadata.
docker compose exec -T db psql -U postgres -d telemetry -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM events WHERE occurred_at < now() - interval '90 days';
DELETE FROM installations i WHERE first_seen < now() - interval '365 days'
AND NOT EXISTS (SELECT 1 FROM events e WHERE e.install_id=i.install_id AND e.environment=i.environment);
VACUUM (ANALYZE) events;
VACUUM (ANALYZE) installations;
SQL
