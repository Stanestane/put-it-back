#!/bin/bash
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres \
  --set=api_password="$API_DB_PASSWORD" --set=analytics_password="$ANALYTICS_DB_PASSWORD" \
  --set=metabase_password="$METABASE_DB_PASSWORD" <<'SQL'
CREATE ROLE telemetry_api LOGIN PASSWORD :'api_password';
CREATE ROLE analytics_reader LOGIN PASSWORD :'analytics_password';
CREATE ROLE metabase LOGIN PASSWORD :'metabase_password';
CREATE DATABASE telemetry;
CREATE DATABASE metabase OWNER metabase;
REVOKE ALL ON DATABASE telemetry FROM PUBLIC;
GRANT CONNECT ON DATABASE telemetry TO telemetry_api, analytics_reader;
REVOKE ALL ON DATABASE metabase FROM PUBLIC;
GRANT CONNECT ON DATABASE metabase TO metabase;
SQL
psql -v ON_ERROR_STOP=1 --username postgres --dbname telemetry -f /schema.sql
