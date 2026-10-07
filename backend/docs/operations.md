# Operations runbook

[Index](../README.md) · [Architecture](architecture.md) · [Recovery](recovery.md)

## Operator conventions and access

PowerShell examples run on the operator's Windows PC from the project root. Shell
examples run on Ubuntu. Commands needing root use sudo or an explicitly opened root
shell. The deployment path is `/opt/put-it-back/backend`; the helper scripts assume
this exact path, so relocating requires updating scripts and systemd units.

Connect the configured OpenVPN profile, then:

```powershell
ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile=verification/server_known_hosts stane@10.0.7.57
```

The ignored host-key file must be transferred/verified separately on a new PC. A
changed host key needs administrator verification, not removal of strict checking.
Do not put login passwords in command arguments, scripts or these documents.

For the dashboard use the [tunnel helper](../../tools/open-telemetry-dashboard.ps1),
or from the project root:

```powershell
ssh -N -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=verification/server_known_hosts -L 127.0.0.1:3300:127.0.0.1:3300 stane@10.0.7.57
```

Visit http://localhost:3300/dashboard/2 while that process and VPN remain connected.
If local port 3300 is occupied, use `-L 127.0.0.1:3301:127.0.0.1:3300` and browse port
3301, or close the old tunnel. The server dashboard remains bound to loopback.

## First installation on an empty server

This procedure initializes a **new** deployment. For an existing server or restored
data, follow update/recovery procedures instead of regenerating secrets.

1. Provide Ubuntu, sudo/SSH access, Docker Engine with Compose v2-compatible commands,
   host Python 3, curl, tar, and sufficient persistent storage. Follow the
   [official Docker Ubuntu installation procedure](https://docs.docker.com/engine/install/ubuntu/).
2. Arrange the [gateway/LAN route](architecture.md#network-and-tls). BIND_IP must
   exist on the host. The gateway must present a valid public certificate and forward
   the original Host header to backend port 80. Do not expose DB/dashboard ports.
3. Transfer the reviewed backend source into `/opt/put-it-back/backend`. Use a clean
   source copy excluding local `.env`, credentials.json, backups, caches and recovery
   archives. Keep the parent deployment directory root-owned, mode 0750. Source
   files mounted into containers must remain readable there; secrets use mode 0600.
4. In a root shell on the new server, initialize and start the database:

```sh
sudo -i
cd /opt/put-it-back/backend
python3 bootstrap.py
# Review only non-secret routing values in .env privately if this is a different host.
docker compose config --quiet
docker compose up -d db
docker compose ps
```

Wait until DB is healthy. Its first-volume startup runs db-init.sh and schema.sql.
If initialization fails, inspect DB logs; do not automatically delete a volume that
may contain data. On an existing volume, db-init.sh does not rerun.

5. Build/test the API, start services, and initialize the dashboard:

```sh
docker compose build api
bash test.sh
docker compose up -d --no-build
python3 setup_dashboard.py
python3 verify_dashboard.py
python3 verify_proxy.py
python3 pin_images.py
```

Dashboard setup polls readiness for approximately ten minutes. It creates an admin
account from credentials.json, adds the analytics_reader connection, and creates
nine questions. An existing dashboard with the same name causes an early exit;
partial creation must be inspected/repaired rather than assuming a rerun repairs it.
Default upstream tags are pulled during startup; pin_images.py then records the
installed digests. Review chosen versions before a production installation.

6. Install operations jobs and create the first backup before enabling health checks:

```sh
install -m 0644 put-it-back-*.service put-it-back-*.timer /etc/systemd/system/
systemctl daemon-reload
bash backup.sh
systemctl enable --now put-it-back-backup.timer put-it-back-health.timer
systemctl start put-it-back-health.service
systemctl show put-it-back-health.service -p Result
```

Leave the root shell with `exit`. Store a protected copy of configuration and backup
off this server, following [recovery](recovery.md). Record versions, deployment time,
test results and the actual dashboard URL. Do not copy secret values into the record.

## Routine checks and monitoring

```sh
cd /opt/put-it-back/backend
sudo docker compose ps
sudo docker stats --no-stream
df -h /
free -h
sudo systemctl list-timers 'put-it-back-*' --no-pager
sudo journalctl -u put-it-back-health.service -n 40 --no-pager
sudo journalctl -u put-it-back-backup.service -n 40 --no-pager
sudo docker compose logs --tail=100 api proxy
```

Public readiness requires no VPN:

```powershell
Invoke-RestMethod -Uri 'https://putitback.vdsolution.com/health/ready'
```

| Job/check | Trigger and behavior |
| --- | --- |
| Backup timer | 03:15 UTC daily, plus up to 300 seconds randomized delay; Persistent=true catches missed runs after downtime |
| Backup service | backup.sh, then maintenance.sh only after successful backup; a cleanup failure can fail the unit despite completed dumps |
| Health timer | First check five minutes after boot, then every five minutes |
| Local health | API readiness and Metabase /api/health HTTP success |
| Public health | If PUBLIC_TELEMETRY_URL exists, HTTPS readiness must parse as status=ready |
| Disk | Root filesystem fails at usage >=85% |
| Backup freshness | At least one completed dump for each DB younger than 30 hours |

Health checks do not verify dump contents, roles/config backup freshness, certificate
expiry lead time, replication, ingestion-volume anomalies or off-server copies.
Failures go to the journal; there are **no external notifications** or automatic
repair actions. Systemd oneshot services normally show inactive after success;
inspect Result and the journal instead of treating inactive as an outage.

Container health status alone does not cause Docker to restart a merely unhealthy
process. Restart policy acts when the process exits. Readiness also does not prove
public authenticated POSTs work; use the smoke test after routing changes.

## Validation commands and side effects

```sh
cd /opt/put-it-back/backend
sudo bash test.sh
sudo python3 verify_dashboard.py
sudo python3 verify_proxy.py
```

- test.sh creates `telemetry_test_<random>_<random>`, applies schema.sql, and runs
  nine tests in a disposable API container. It removes the test DB on ordinary exit.
  It uses the same PostgreSQL cluster and reapplies analytics_reader role defaults;
  it is DB-isolated, not a separate server. Abrupt process termination can leave a
  test DB requiring identification and removal.
- verify_dashboard.py logs in with saved credentials, executes nine saved questions,
  and logs out. It expects nine cards and a current dashboard URL.
- verify_proxy.py uploads one test event through public HTTPS, retries it, verifies
  401 and 413 handling, then removes only its generated installation/events in a
  finally block. Interrupted cleanup can leave harmless synthetic test data.

Tests cover schema/authentication/duplicates/conflicts, partial rejection, bounds,
clock/counter checks, throttle behavior, retryable DB failure, read-only reporting,
mature retention and known level/revenue totals. They do not replace load tests,
real-device delivery checks, production ad reconciliation or disaster exercises.

## Deploying application or schema changes

1. Record the running versions and retain the previous source, `.env`, API image and
   matching database backup. See [rollback](recovery.md#rollback).
2. Copy reviewed source changes without overwriting server secrets, credentials or
   backups. Keep executable scripts in LF line endings. Avoid introducing private
   files outside the exclusions in .dockerignore.
3. Build and test before replacing the running API:

```sh
cd /opt/put-it-back/backend
sudo bash backup.sh
sudo docker compose config --quiet
sudo docker compose build api
sudo bash test.sh
```

4. Apply only the reviewed DB migration. For compatible changes limited to the
   existing schema/view script, an operator can explicitly apply:

```sh
sudo docker compose exec -T db psql -U postgres -d telemetry -v ON_ERROR_STOP=1 < schema.sql
```

`CREATE TABLE IF NOT EXISTS` will not update existing table columns. Plan and test
column/data migrations separately, including API-version compatibility and rollback.

5. Replace only changed services and verify them:

```sh
sudo docker compose up -d --no-deps --no-build api
sudo python3 verify_proxy.py
sudo python3 verify_dashboard.py
sudo systemctl start put-it-back-health.service
```

For a Caddy change, validate and recreate proxy instead:

```sh
sudo docker compose run --no-deps --rm -T proxy caddy validate --config /etc/caddy/Caddyfile
sudo docker compose up -d --no-deps proxy
```

Changes to `.env` need container recreation; a simple restart does not inject a new
environment. `PUBLIC_TELEMETRY_URL` is read by host scripts on each execution.

## Upstream image upgrades

Do not rely on `docker compose pull` to advance an image already pinned by digest.
Select and review intended tags/digests first. Pull the approved candidates, update
the corresponding `.env` references, then recreate only affected services.
pin_images.py inspects the fixed tags postgres:17-bookworm, caddy:2-alpine and
metabase/metabase:latest: it pins what those local tags resolve to, not arbitrary
candidate tags. Do not run it blindly after a targeted upgrade.

PostgreSQL stays on major 17 until a separately planned major-version migration.
Metabase can migrate its application DB on startup; back it up before upgrades and
retain the previous application image. Downgrading the container alone may not undo
its database migration. Review logs after any DB recreation because clients can
temporarily hold stale connections.

## Credential changes

Use a private operator terminal/editor. Never use `docker compose config` without
`--quiet` in shared logs: expanded configuration contains passwords.

| Credential | Required coordinated change |
| --- | --- |
| Dashboard password | Change in Metabase, then update saved credentials.json and the protected PC copy; JSON alone does not change the login |
| Ingestion key | Generate a new >=32-character secret, update server INGEST_KEY and the saved record, recreate API, update clients/verification records |
| API DB password | Change PostgreSQL role password and API_DB_PASSWORD, then recreate API |
| Reporting DB password | Change analytics_reader password, ANALYTICS_DB_PASSWORD, and Metabase's saved analytics connection |
| Metabase DB password | Change metabase role password and METABASE_DB_PASSWORD, then recreate Metabase |
| PostgreSQL administrator password | Change postgres role password and POSTGRES_PASSWORD; retain protected recovery records |
| Metabase encryption key | Use Metabase's supported rotation procedure; preserve old key and DB backup until recovery is verified |

Changing .env initialization passwords does not alter an existing PostgreSQL role.
Interactive `\password telemetry_api` (or the relevant role) inside a private
`sudo docker compose exec db psql -U postgres` session avoids writing the password
as SQL in shell history. Synchronize dependent services during a maintenance window.
Use URL-safe secrets or correctly encode DB connection URLs.

The API accepts **one** ingestion key, with no overlap/grace-period mechanism. Rotating
it breaks old app builds until they are updated; add a planned key-transition design
before release if needed. Metabase setup skips existing connections, so rerunning it
does not rotate their passwords.

The Metabase key encrypts saved DB connection details, not raw events, full disk or
backup archives. Losing/changing it can make those connections unreadable; follow
the [official key guidance](https://github.com/metabase/metabase/blob/master/docs/databases/encrypting-details-at-rest.md).

## Removing an installation's data

There is no public deletion endpoint or player-ownership verification mechanism.
An authorized operator must first establish which installation UUID to delete. This
SQL removes that UUID across all environments. In a private administrator psql session:

```sql
\prompt 'Installation UUID to delete: ' target_install
BEGIN;
DELETE FROM events WHERE install_id = :'target_install'::uuid;
DELETE FROM installations WHERE install_id = :'target_install'::uuid;
COMMIT;
```

Stop collection/clear the device queue as part of the request; the API has no
tombstone preventing later uploads from recreating the installation. Document the
request securely so deletions can be reapplied after a restore. Existing dumps and
manual archives still contain earlier data until their retention/deletion policy is
applied. Live SQL reports reflect deletion on their next query.

## Troubleshooting

| Symptom | Checks and response |
| --- | --- |
| Public root shows API text | Expected; use the private Metabase URL for reports |
| localhost:3300 unreachable | OpenVPN, tunnel process, local port conflict, then server Metabase health |
| SSH timeout | VPN and route to 10.0.7.57; do not change public DNS to fix SSH |
| Public readiness 503 | API/DB health and logs; DB privileges/connectivity; free disk |
| Cloudflare 403/challenge | Check application User-Agent, exact route and edge rules; ask gateway administrator to allow legitimate API clients if necessary |
| Redirect loop | Backend TELEMETRY_HOST must remain http:// behind the existing TLS gateway |
| Cloudflare 521/522/525/526 | Gateway/network/certificate issue; compare local readiness and direct gateway TLS; coordinate with network administrator |
| API 401 | INGEST_KEY mismatch; saved credentials may be stale after rotation |
| API 413/415/422 | Consult API body-size, encoding and envelope requirements |
| Many rejected events | Device clocks, old queues, fields/enums, schema versions; rejection totals are not in the ingestion view |
| Empty KPI tables | No opted-in configured release clients, debug/editor collection disabled, test environment, no qualifying activity, or immature retention cohorts |
| Inflated time/revenue | Cumulative checkpoints, duplicate callbacks with new IDs, wrong test flags, currency mixing |
| Dashboard query error | Analytics role connection, view schema, migrations and 30-second query limit |
| Backup unit failed | Distinguish dump failure from ExecStartPost retention failure; check space and DB logs |
| Health says stale backup | Compare UTC dump timestamps; successful service launch alone is not a completed backup |
| OOM/restarts/slow reports | docker stats, kernel/system journal, query cost and disk I/O; limits are caps, not guaranteed capacity |

Before escalating routing issues, gather status codes, timestamps, non-secret logs
and which hop fails. Do not send `.env`, authorization headers, password-containing
configuration dumps or unredacted recovery archives as diagnostic attachments.
