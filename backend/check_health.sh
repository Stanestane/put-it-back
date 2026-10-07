#!/bin/bash
set -euo pipefail
cd /opt/put-it-back/backend
curl -fsS --max-time 10 http://10.0.7.57/health/ready >/dev/null
curl -fsS --max-time 10 http://127.0.0.1:3300/api/health >/dev/null
public_url=$(sed -n 's/^PUBLIC_TELEMETRY_URL=//p' .env)
if [[ -n "$public_url" ]]; then
  curl -fsS --max-time 15 "${public_url%/}/health/ready" | python3 -c 'import json,sys; assert json.load(sys.stdin).get("status") == "ready", "Public API not ready"'
fi
usage=$(df --output=pcent / | tail -n 1 | tr -dc '0-9')
if (( usage >= 85 )); then
  echo "Root filesystem at ${usage}%" >&2
  exit 1
fi
# Fail if the daily backup has not produced both database dumps in 30 hours.
for db in telemetry metabase; do
  if ! find backups -maxdepth 1 -type f -name "${db}-*.dump" -mmin -1800 | grep -q .; then
    echo "Missing recent ${db} backup" >&2
    exit 1
  fi
done
echo 'API, public HTTPS, dashboard, storage and backup freshness healthy'
