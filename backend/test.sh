#!/bin/bash
set -euo pipefail
cd /opt/put-it-back/backend
set -a
source .env
set +a
test_database="telemetry_test_${RANDOM}_${RANDOM}"
docker compose exec -T db createdb -U postgres "$test_database"
trap 'docker compose exec -T db dropdb -U postgres "$test_database"' EXIT
docker compose exec -T db psql -U postgres -d "$test_database" -v ON_ERROR_STOP=1 -f /schema.sql >/dev/null
export DATABASE_URL="postgresql://telemetry_api:${API_DB_PASSWORD}@db/${test_database}"
export TEST_ADMIN_DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@db/${test_database}"
export TEST_READER_DATABASE_URL="postgresql://analytics_reader:${ANALYTICS_DB_PASSWORD}@db/${test_database}"
docker compose run --no-deps --rm -T -e DATABASE_URL -e TEST_ADMIN_DATABASE_URL -e TEST_READER_DATABASE_URL api python -m pytest -q -p no:cacheprovider tests
