# Put It Back backend documentation

Last reviewed against the implementation: **9 October 2026**.

The backend is deployed and its public HTTPS endpoint has passed ingestion checks.
Godot 1.5.1 includes optional usage collection, durable queuing and gameplay/ad
instrumentation. Collection starts off in configured release builds. Actual Godot
test uploads, duplicate replay and [Android device validation](../docs/android-telemetry-validation.md)
passed. Production release distribution remains separate.

## Documentation

| Document | Contents |
| --- | --- |
| [Dashboard access](docs/dashboard-access.md) | Step-by-step access from this PC or another LAN computer, SSH host verification, logins and troubleshooting |
| [Architecture and configuration](docs/architecture.md) | Services, network routes, ports, storage, permissions, configuration, secrets and source-file map |
| [API reference](docs/api.md) | Every event and field, validation, limits, acknowledgements, errors, retries and an upload example |
| [Dashboard and metrics](docs/reporting.md) | Production KPIs, separate QA dashboard, access, formulas, exclusions and interpretation limits |
| [Operations runbook](docs/operations.md) | Installation, updates, monitoring, credentials, deletion, testing and troubleshooting |
| [Backup and recovery](docs/recovery.md) | Backup contents, schedules, off-server copies, restore drills, disaster recovery and rollback |
| [Game integration and remaining work](docs/client-integration.md) | Client responsibilities, event lifecycle, offline delivery, release checks and unfinished features |

## Addresses and access

| Resource | Address | VPN needed? |
| --- | --- | --- |
| Public API identification | https://putitback.vdsolution.com/ | No |
| Public readiness | https://putitback.vdsolution.com/health/ready | No |
| Event ingestion | `POST https://putitback.vdsolution.com/v1/events/batch` | No; ingestion key required |
| Production dashboard | http://localhost:3300/dashboard/2 | Offsite only; always use an SSH tunnel on the browser's computer |
| QA dashboard (test data) | http://localhost:3300/dashboard/3 | Offsite only; uses the same tunnel and Metabase login |
| Ubuntu server | `stane@10.0.7.57` | Offsite only; LAN requires a route to TCP 22 |
| Local readiness | http://10.0.7.57/health/ready | Offsite only; LAN can connect directly |

To open the dashboards from this PC, connect the existing OpenVPN profile when
offsite and run this in PowerShell from the project directory:

```powershell
& './tools/open-telemetry-dashboard.ps1'
```

Keep that terminal open and visit the dashboard link. Dashboard credentials are
separate from SSH/OpenVPN. The saved record is `verification/put-it-back-credentials.json`
on this PC or root-only `/opt/put-it-back/backend/credentials.json` on the server.
Passwords and keys are intentionally absent from these documents.
Another computer on the server LAN does not need OpenVPN if it can reach SSH on
`10.0.7.57:22`. Follow the [complete access instructions](docs/dashboard-access.md),
which do not require a project checkout or Godot installation.

## Routine checks

Run inside an SSH session on Ubuntu:

```sh
cd /opt/put-it-back/backend
sudo docker compose ps
sudo systemctl list-timers 'put-it-back-*' --no-pager
sudo journalctl -u put-it-back-health.service -n 30 --no-pager
```

The hostname uses the **existing HTTPS gateway**. Ubuntu receives its HTTP traffic
on the LAN; do not add a second HTTPS redirect. See the
[network diagram](docs/architecture.md#network-and-tls) before changing routing.

## Status and records

Implemented: authenticated ingestion, event-ID deduplication, SQL reporting,
private production and QA dashboards, client opt-in/out and persistent delivery,
daily local backups and scheduled health checks. Setup checks passed: public
uploads, nine backend tests, nine production and ten QA queries, and both database
restore drills. These recorded checks are not load testing or an availability guarantee.

Still needed: configured production release distribution, production signing and
live-ad/UMP checks, agreed retention before real collection, scheduled off-server
backups and external failure alerts.

- [Deployment record](../docs/telemetry-deployment.md): server-specific setup and verification history.
- [Original telemetry plan](../docs/telemetry-plan.md): broader roadmap, including unimplemented proposals.
- [Game project README](../README.md).

Commands are for operators to run when performing the stated task. Deployment
changes and checks are recorded separately in the deployment record.
