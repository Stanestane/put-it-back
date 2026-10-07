# Telemetry deployment — 6 October 2026

For the maintained architecture, full API contract, report definitions and operator
procedures, start with the [complete backend documentation](../backend/README.md).
This document records deployment observations and verification history.

The backend is deployed on Ubuntu `10.0.7.57`, hostname `svrstanestanepo001`, in
`/opt/put-it-back/backend`. Use the existing OpenVPN connection and SSH user `stane`.
Server login passwords are not stored in the project.

Running services: PostgreSQL 17, FastAPI ingestion, Caddy, and Metabase with its own
application database. The dashboard reporting role only reads analytics views.
Upstream container image digests are pinned in the server's private `.env`.

- Configured public API: `https://putitback.vdsolution.com/v1/events/batch`.
- Public readiness: `https://putitback.vdsolution.com/health/ready`.
- Local/VPN readiness: `http://10.0.7.57/health/ready` (still operational).
- Dashboard: `http://localhost:3300/dashboard/2`, after running
  `tools/open-telemetry-dashboard.ps1` while connected to OpenVPN.
- Dashboard credentials: server root-only `credentials.json`; a private local copy
  is stored in the Git-ignored `verification/put-it-back-credentials.json`.

The **Game KPIs** dashboard has nine reports: audience, exact-day retention,
sessions/playtime, level difficulty, revenue, ingestion delay, onboarding, ad
delivery, and ARPDAU/eCPM. Reports use UTC. Godot 1.5.0 now has a durable queue,
lifecycle/round/ad instrumentation and optional collection controls, described in
the [client guide](../backend/docs/client-integration.md). On 7 October, actual Godot
HTTPS accepted 12 test events and returned 12 duplicates after persisted replay,
with no rejected events. These test events are excluded from production KPIs.
Player collection requires a configured release build and opt-in; Android device
validation remains outstanding.

Validation completed:

- Nine automated tests against a temporary PostgreSQL database: authentication,
  retry deduplication, conflicting IDs, partial rejection, payload/batch bounds,
  time/counter validation, throttling, retryable storage failures, read-only
  reporting, mature retention cohorts, and known engagement/revenue totals.
- All nine saved dashboard queries executed successfully through Metabase.
- HTTP checks through Caddy confirmed ingestion, duplicate acknowledgement,
  authorization rejection, and the payload limit. Readiness also checked from this PC.
- Both database dumps restored successfully into temporary databases; the telemetry
  schema had ten reporting views, and the Metabase dump contained its saved reports.
  Temporary restore/test databases were removed.

Daily backup and cleanup: `put-it-back-backup.timer`, 03:15 UTC plus up to five
minutes jitter. Fourteen days of local backups; 90 days raw events; one year inactive
installation metadata. `put-it-back-health.timer` checks services, disk space, and
backup freshness every five minutes. It records failures in the server journal;
external alert delivery is not configured.

A recovery archive is copied to this PC under the ignored `verification/` directory.
It contains database dumps and private configuration; treat it as a secret. This
one-time copy does not replace scheduled off-server backups.

Public hostname update, 6 October 2026:

**Public HTTPS is operational** at `https://putitback.vdsolution.com`.
The existing gateway at `109.245.246.253:443` already terminates TLS with a valid
Let's Encrypt certificate for `*.vdsolution.com` and forwards the hostname to
`10.0.7.57:80`. Caddy on the backend is configured for this internal HTTP hop,
with the public HTTPS URL kept separately in `PUBLIC_TELEMETRY_URL`.

The public health check returns HTTP 200 and `{"status":"ready"}`, both through
Cloudflare and via a direct connection to the HTTPS gateway with certificate
validation enabled. The homepage identifies the telemetry API. Public responses
have `Cache-Control: no-store`. The IP-based HTTP listener only serves local health
checks. The API's PostgreSQL connection and private dashboard are healthy.

Authenticated synthetic uploads through the public HTTPS URL passed ingestion,
retry deduplication, invalid-key rejection, and payload-limit checks. Synthetic
events were removed afterwards. Requests identify the application as
`PutItBackTelemetry/1.0`; the default Python urllib user agent was rejected by
Cloudflare during verification. The game integration must use its application
identifier and be tested on real devices before release.

No DNS, Cloudflare account, router, or existing gateway settings were changed.
The gateway administrator owns renewal of the wildcard certificate (the inspected
certificate expires 13 November 2026). The backend health timer also checks public
HTTPS readiness. The dashboard remains private through SSH.

Still required before public collection:

1. Client integration, collection preferences, and agreed retention settings.
2. A permanent off-server backup destination and an alert recipient/channel.

See [the operating guide](../backend/README.md) for API details, limits, metric
definitions, access, deployment, and restore commands. Source changes are in the
working tree; no commit or push was requested for this setup.
