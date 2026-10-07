# Backup, recovery and rollback

[Index](../README.md) · [Operations](operations.md)

## What exists now

backup.sh produces logical PostgreSQL backups under
`/opt/put-it-back/backend/backups` using UTC timestamps:

| File | Contents |
| --- | --- |
| telemetry-TIMESTAMP.dump | Custom-format telemetry DB dump: schema, events, installation metadata, views and grants |
| metabase-TIMESTAMP.dump | Custom-format application DB: accounts, dashboards, questions, settings, saved connections |
| roles-TIMESTAMP.sql | Cluster roles/settings/password verifiers from pg_dumpall --globals-only |

The script uses umask 077, writes temporary `.tmp` files, and renames each after that
dump succeeds. The two DB dumps are sequential, not one cross-database snapshot.
A failed run can leave one finished dump or `.tmp` files; use a complete matching
set for recovery. Retention removes matching completed files with `find -mtime +14`,
so practical deletion is after more than fourteen full 24-hour age periods, on the
next successful backup run. Temporary and other filenames are not auto-pruned.

The daily systemd service runs backup.sh first, then retention/vacuum via
maintenance.sh. Running backup.sh manually does **not** run data retention. There is
no WAL archive, continuous point-in-time recovery or automatic off-server transfer.

These dumps do not contain `.env`, credentials.json, source, installed Docker images,
systemd units outside the source copy, VPN configuration, DNS/gateway configuration,
or the gateway's TLS private key. Preserve the items you control separately.

## Recovery material to retain

Keep a protected, off-server set containing:

1. A complete timestamp-matched dump set and its checksum.
2. `.env`, especially database passwords and METABASE_ENCRYPTION_KEY, plus current
   credentials.json. These are required even when the database dump is sound.
3. The matching source/configuration and deployed image references; retain the API
   image or enough approved build inputs to reproduce it.
4. Operating/systemd units, the gateway route and ownership/contact information,
   verified SSH host key, and access to the VPN through its administrator.
5. A record of authorized deletions to reapply if an older backup is restored.

The setup saved manual recovery archives on this PC:
`verification/put-it-back-recovery-20261006.tar.gz` and
`verification/put-it-back-recovery-20261007.tar.gz`. The latter includes the working
public-host configuration. They are ignored by Git and access-restricted, but are
ordinary tar.gz archives, **not encrypted archives**. They contain secrets and are
point-in-time copies, not a continuously updated backup service.

A daily schedule implies up to roughly one day of potential data loss when healthy;
it does not establish a guaranteed RPO. Server/disk loss may require the older manual
off-server copy. There is no measured recovery-time commitment or failover host.

## Create a new backup and protected recovery archive

Run in a root shell on Ubuntu; this creates new files without replacing databases.

```sh
sudo -i
cd /opt/put-it-back/backend
bash backup.sh
stamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="/home/stane/put-it-back-recovery-${stamp}.tar.gz"
umask 077
tar -czf "$archive" -C /opt/put-it-back/backend .
chown stane:stane "$archive"
chmod 600 "$archive"
sha256sum "$archive"
```

The archive includes the deployment directory and its backups, not live Docker
volumes. Use the printed filename and checksum. From PowerShell on the VPN-connected PC:

```powershell
# Replace TIMESTAMP with the generated filename; do not copy a literal placeholder.
scp -o StrictHostKeyChecking=yes -o UserKnownHostsFile=verification/server_known_hosts stane@10.0.7.57:put-it-back-recovery-TIMESTAMP.tar.gz verification/
Get-FileHash -Algorithm SHA256 'verification/put-it-back-recovery-TIMESTAMP.tar.gz'
```

Match the checksum, restrict the local file to authorized accounts, and remove only
the exact temporary transfer archive from `/home/stane` after successful transfer.
Keep the source backups. Never place recovery archives in a public web directory.
Arrange encrypted storage, retention, failure notifications and regular restore
drills when automating off-server backup.

## Restore drill into temporary databases

This is the preferred verification method on the existing cluster. Use a trusted
complete dump set, ample disk space, and unique temporary database names. Run as root
so shell redirection can read root-only backups; `sudo pg_restore < file` alone does
not elevate the shell that opens `file`.

```sh
sudo -i
cd /opt/put-it-back/backend
backup_stamp=REPLACE_WITH_ACTUAL_DUMP_TIMESTAMP
test -f "backups/telemetry-${backup_stamp}.dump"
test -f "backups/metabase-${backup_stamp}.dump"
docker compose exec -T db createdb -U postgres telemetry_restore_check
docker compose exec -T db createdb -U postgres metabase_restore_check
docker compose exec -T db pg_restore -U postgres --exit-on-error --single-transaction --no-owner -d telemetry_restore_check < "backups/telemetry-${backup_stamp}.dump"
docker compose exec -T db pg_restore -U postgres --exit-on-error --single-transaction --no-owner -d metabase_restore_check < "backups/metabase-${backup_stamp}.dump"
docker compose exec -T db psql -U postgres -d telemetry_restore_check -c 'SELECT count(*) FROM events;'
docker compose exec -T db psql -U postgres -d telemetry_restore_check -c "SELECT count(*) FROM information_schema.views WHERE table_schema='analytics';"
docker compose exec -T db psql -U postgres -d metabase_restore_check -c 'SELECT count(*) FROM report_card;'
```

Stop on any command failure. If a temporary name already exists, investigate it
instead of deleting/reusing it automatically. Current telemetry schema has ten
analytics views. The Metabase question count can include built-in/sample questions;
it need not equal the nine Game KPIs cards.

This drill verifies dump readability/schema/data, not a complete Metabase login or
public failover. For application-level recovery assurance, restore on an isolated
staging host with matching secrets and images, then execute the dashboard/API tests.
The production dashboard must not be pointed at temporary test databases.

After verifying that these two names are the databases just created by the drill:

```sh
docker compose exec -T db dropdb -U postgres telemetry_restore_check
docker compose exec -T db dropdb -U postgres metabase_restore_check
exit
```

Custom dumps are read with pg_restore; --exit-on-error stops on errors, while
--single-transaction avoids a partially applied restore. --no-owner is used only
for this scratch drill. Production recovery below retains original owners/grants.
[PostgreSQL restore reference](https://www.postgresql.org/docs/17/app-pgrestore.html)

## Full recovery on a replacement server

Perform this on a replacement or isolated staging server, not by overwriting the
live databases. Coordinate the maintenance/cutover with the gateway administrator.
The setup verified restores into temporary databases; a complete replacement-server
cutover has not been rehearsed. Validate this procedure on staging before relying on
a recovery-time target.

1. Obtain the trusted recovery set, verify checksums, and restore the matching source
   and private configuration into `/opt/put-it-back/backend`. Install Docker/Compose,
   Python and host tools. Preserve mode 0600 for `.env` and credentials.json. Do not
   run bootstrap.py over recovered secrets.
2. Use the saved image digests and compatible PostgreSQL major 17. Keep public ingress,
   API, Metabase and timers stopped while reconstructing the DB. Set the private
   BIND_IP to an address owned by this host; coordinate any address change in the
   hardcoded health listener/scripts and the gateway route.
3. Start **only** db. Empty-volume initialization recreates the standard roles using
   the recovered `.env` and creates empty application databases. Wait for healthy:

```sh
docker compose up -d db
docker compose ps
```

4. On this isolated replacement only, replace the newly initialized empty databases
   with clean databases, preserving the expected ownership:

```sh
docker compose exec -T db dropdb -U postgres telemetry
docker compose exec -T db dropdb -U postgres metabase
docker compose exec -T db createdb -U postgres -O postgres telemetry
docker compose exec -T db createdb -U postgres -O metabase metabase
docker compose exec -T db pg_restore -U postgres --exit-on-error --single-transaction -d telemetry < "backups/telemetry-${backup_stamp}.dump"
docker compose exec -T db pg_restore -U postgres --exit-on-error --single-transaction -d metabase < "backups/metabase-${backup_stamp}.dump"
```

Set backup_stamp to the reviewed matching set first, as in the drill. These dropdb
commands are destructive and apply **only to the replacement's freshly initialized
empty databases**, with API/Metabase stopped. For recovery into an existing live
cluster, prepare a separate database/cutover plan instead of copying these commands.

5. Because the databases were recreated, reapply their connection restrictions:

```sh
docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
REVOKE ALL ON DATABASE telemetry FROM PUBLIC;
GRANT CONNECT ON DATABASE telemetry TO telemetry_api, analytics_reader;
REVOKE ALL ON DATABASE metabase FROM PUBLIC;
GRANT CONNECT ON DATABASE metabase TO metabase;
SQL
```

The normal bootstrap already created the expected roles/passwords. Do **not** replay
the entire roles SQL blindly into that initialized cluster: it includes CREATE ROLE
statements for roles that exist, including postgres. Review it privately for custom
roles/settings and restore only necessary differences. Reconcile role passwords with
recovered `.env` and retain default read-only/timeout settings for analytics_reader.

6. Restore any post-backup authorized deletions, check schema marker/row counts and
   reader grants, and ensure the recovered Metabase encryption key matches its dump.
7. Start the API and Metabase with matching images. Do not rerun setup_dashboard.py
   as a substitute for restoring the application DB. Verify dashboard queries and
   isolated API behavior before changing the public route.
8. Coordinate gateway cutover, start proxy, validate public HTTPS and run
   verify_proxy.py. Confirm the old server is not still accepting divergent writes.
9. Install/enable both timers, take a fresh backup, verify monitoring, and document
   the chosen restore point and any lost interval. Update the protected PC credentials
   and recovery copy if their values/locations changed.

A newer Metabase image can migrate its restored DB; use the version paired with the
backup first. The saved encryption key is needed to decrypt connection credentials.
See [Metabase's key documentation](https://github.com/metabase/metabase/blob/master/docs/databases/encrypting-details-at-rest.md).

## Rollback

Retain the prior source/configuration, image references, API image and DB dumps before
an update. A simple code/proxy change can usually be rolled back by restoring the
previous source/image/config and recreating the changed service. Do not run bootstrap
again or remove named volumes. Environment changes require recreation, not restart.

If a schema or Metabase upgrade changed persisted data, downgrading an image is not
enough. Use a tested reverse migration or restore the matched DB snapshot during a
maintenance window; account for events accepted after that snapshot. Keep a backup
of the failed/current state before rollback so newer data is not silently discarded.

The `backups/before-public-host.*` files are historical configuration copies, not a
current recovery set. Restoring them alone would revert public routing. The latest
recovery archive and deployment record take precedence.

## Retention, deletions and backup limits

Raw event cleanup uses occurred_at older than 90 days. Installation metadata is
deleted only when first_seen is older than 365 days **and** no retained events exist
for that installation/environment. It is not a rolling “365 days since last seen”
policy. VACUUM ANALYZE runs after deletion; it does not guarantee the filesystem
shrinks immediately.

Dumps retain pre-cleanup data until backup expiry. Manual archives have no automatic
expiration. Explicit deletion requests must include applicable backup policy and
reapplication after restore. Stale device queues can recreate deleted installations
because no deletion tombstone exists. Agree these policies before collecting real data.
