#!/bin/bash
set -euo pipefail
cd /opt/put-it-back/backend
umask 077
mkdir -p backups
stamp=$(date -u +%Y%m%dT%H%M%SZ)
for db in telemetry metabase; do
  docker compose exec -T db pg_dump -U postgres -Fc "$db" > "backups/${db}-${stamp}.dump.tmp"
  mv "backups/${db}-${stamp}.dump.tmp" "backups/${db}-${stamp}.dump"
done
docker compose exec -T db pg_dumpall -U postgres --globals-only > "backups/roles-${stamp}.sql.tmp"
mv "backups/roles-${stamp}.sql.tmp" "backups/roles-${stamp}.sql"
# Only completed, specifically named backup files in this fixed directory expire.
find /opt/put-it-back/backend/backups -maxdepth 1 -type f \( -name 'telemetry-*.dump' -o -name 'metabase-*.dump' -o -name 'roles-*.sql' \) -mtime +14 -delete
printf 'Backup completed: %s\n' "$stamp"
