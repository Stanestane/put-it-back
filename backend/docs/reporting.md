# Dashboard and metric definitions

[Index](../README.md) · [API](api.md) · [Schema source](../schema.sql)

## Access and basic use

Connect OpenVPN when offsite, run `tools/open-telemetry-dashboard.ps1` from the
project, and keep its terminal open. Visit http://localhost:3300/dashboard/2 for
production or http://localhost:3300/dashboard/3 for QA on that same computer.
Use the dashboard credentials from the private credential file, not the SSH password.
On another computer, create its own tunnel; localhost always refers to the browser's
computer. Disconnecting the tunnel does not stop Metabase or collection.
On the server LAN, OpenVPN is unnecessary if SSH is reachable. The
[access guide](dashboard-access.md) covers another computer, first-time host-key
verification, passwords and port conflicts without requiring the project files.

The dashboard is named **Game KPIs**. Its ID is 2 on the current deployment; IDs can
differ after a fresh setup. The current URL is saved in credentials.json. Nine saved
SQL questions are displayed as tables. There are no configured dashboard-wide
date/build/platform filters; some tables expose those dimensions as columns.

Refresh a report to query the views. They are live SQL, not scheduled daily snapshots.
Rows change after new/offline events arrive or retention deletes old events. With no
production activity, empty tables are expected. The audience view still generates 90
calendar rows with zero activity. Sample Metabase content, if present, is not game data.

## Reports and backing views

| Dashboard report | View | Grouping/output |
| --- | --- | --- |
| Audience: DAU / WAU / MAU | analytics.audience | day, dau, wau, mau, new_installations |
| Exact-day retention | analytics.retention | cohort_day, day_number, cohort_size, returned, retention_percent |
| Sessions and playtime | analytics.engagement | day/platform/build_version, active_installations, observed_sessions, rounds_started, foreground_seconds, gameplay_seconds |
| Level difficulty | analytics.levels | level_id/mode/puzzle_revision/build_version/platform, starts, finishes, wins, timeouts, explicit_abandonments, incomplete, completed_win_percent, mean_win_seconds, incorrect_actions |
| Ad revenue by currency and precision | analytics.ad_revenue | day/currency/precision, revenue |
| Ingestion and upload delay | analytics.ingestion | received_day/environment/name, events, mean_delay_seconds |
| First experience funnel | analytics.onboarding | cohort_day, observed_installations, started_first_round, won_a_round, started_ten_rounds |
| Ad delivery | analytics.ad_delivery | day, requests, loads, failures, impressions, closes |
| ARPDAU and eCPM by currency | analytics.monetization | day/currency, revenue, dau, impressions, arpdau, ecpm |

The tenth view, `analytics.activity`, is a helper containing distinct `(day, install_id)`
pairs. It is readable by the reporting role but is not a separate dashboard card.

## QA dashboard

Open **[Game QA (test data)](http://localhost:3300/dashboard/3)** through the same
SSH tunnel (over LAN or VPN), using the same Metabase login. This separate dashboard has ten
cards over `analytics.qa_events`, a view restricted to `environment=test`:

| Card | What it shows |
| --- | --- |
| Received events | Total retained test events, including ads and synthetic smoke tests |
| Test installations | Distinct installations with retained test events; not unique people |
| Finished rounds | Received test round finishes |
| Daily activity | UTC day/platform/build, sessions, starts/finishes and checkpoint playtime |
| Sessions and playtime | Latest 100 installation/session/platform/build groups and checkpoint durations |
| Level results | Starts, finishes, wins, timeouts, abandonment, incomplete rounds, mean win/timeout time and incorrect actions by level/mode/revision/build/platform |
| Recent round results | Latest 100 finishes, including actions, faults, duration and round/session IDs |
| Ad callbacks by attempt | Latest 100 attempt groups with request/load/failure/impression/paid/close counts and test-ad flag |
| Paid callbacks (not real revenue) | Latest 100 SDK/synthetic paid events; original integer micros, currency, precision and test-ad flag |
| Ingestion and upload delay | Received UTC day/build/platform/event counts, mean delay and last receipt |

Refresh the dashboard to query newly received events. The installed QA app was
left with **Usage data: off**; allow it in that app to collect another test run.
Data normally uploads while the app is foregrounded, with a roughly 20-second
cadence and retries after network failures. Keep the app open before refreshing.

Counts include both the Android device and synthetic Godot smoke tests. Use build
and platform columns to distinguish them. All-retained-data headline counts are
not today's DAU. Session first/last event times are observation bounds, not session
duration; duration comes from checkpoints. An unfinished round can reflect a
force-stop, opt-out, or missing upload. A zero-valued paid callback confirms delivery
of a test callback, not real ad earnings. No production events are included, even
if their ad payload has `test_ad=true`; the production reports are unchanged.

The reporting role can read the QA view but cannot select the underlying raw events
table. The QA view omits fingerprints and sequence numbers. Retention is the same
as other raw events (90 days by default). There are no dashboard-wide date/build
filters; recent-detail cards have explicit limits, while aggregate cards cover all
retained test data. Dashboard ID 3 applies to this deployment; setup prints the ID
on other installations.

From `/opt/put-it-back/backend`, after the normal backend and Metabase setup:

```sh
sudo docker compose exec -T db psql -U postgres -d telemetry -v ON_ERROR_STOP=1 < qa-view.sql
sudo python3 setup_qa_dashboard.py
sudo python3 setup_qa_dashboard.py --verify-only
```

Fresh databases also receive the view from `schema.sql`. The additive migration
does not recreate production views. Setup creates or reconciles only the dashboard
named **Game QA (test data)** and its ten cards, and executes each query. Rerunning
it restores its managed queries/layout; keep custom reports on a different
dashboard. `--verify-only` checks saved SQL and executes queries without editing.
Neither mode rewrites credentials or production dashboard configuration.

## Shared definitions and exclusions

“Player” means a pseudonymous installation, not a known human. Reinstallation or a
second device can create another installation. No accounts or cross-device identity
merging exist. All calendar calculations use UTC; the DB/session timezone must stay
UTC because view boundaries also use CURRENT_DATE.

Production activity comes from these names only: first_open, session_started,
activity_checkpoint, round_started, round_finished. Ads alone do not qualify as
activity. All KPI views filter environment=production; ingestion diagnostics include
all environments. Ad/revenue reports additionally require test_ad=false.

Installation metadata is created by **any accepted event**, including ad events.
Its first_seen is the minimum client event time for the installation/environment.
Therefore “new installations” means newly observed installations, not store downloads,
and a cohort member need not have submitted first_open or qualifying gameplay.
Even a production-labelled test ad creates production installation metadata: use
environment=test for test clients, not just test_ad=true.

## Audience

For reporting date D:

- DAU: distinct active installations on D.
- WAU: distinct active installations across D−6 through D, inclusive.
- MAU: distinct active installations across D−29 through D, inclusive; a rolling
  30-day measure, not the named calendar month.
- New installations: production metadata whose first_seen UTC date is D.

These counts include practice and random play together. Today is partial; do not
compare a partial day directly to a completed day without accounting for elapsed time.
WAU/MAU are not sums of DAU. Audience reports do not currently split by build/platform.

## Exact-day retention

For each production installation cohort and N in {1,7,30}:

`retention_percent = 100 × installations active on cohort_day + N / cohort_size`.

Only cohorts from the last 89 completed dates/today are considered, and a row is
included only when `cohort_day + N < CURRENT_DATE`. The entire return day must have
finished. For an October 1 cohort, D7 concerns October 8 and is first eligible on
October 9 UTC. This is exact-day retention, not “returned on or after day N.”

Late valid uploads can move first_seen earlier or add a return, revising past cohorts.
The denominator includes observed installations even if only ad events were received.
Retention is not yet broken down by acquisition source, platform or experiment.

## Sessions and playtime

Each daily/build/platform group counts distinct `(install_id, session_id)` pairs
with qualifying activity. Session_started is not required to count a session. The
backend does **not** split a reused session after inactivity. Godot assigns a new
session on launch/opt-in or after at least 30 minutes in background; foreground
menu pauses retain their session. See the
[client timing policy](client-integration.md#event-lifecycle-and-clocks).

A session spanning midnight appears on both active dates. Summing rows across builds
or platforms can double-count an installation/session if dimensions change. The
rounds_started field counts events, not distinct round IDs.

Foreground and gameplay seconds sum incremental activity_checkpoint fields. They
are not reconstructed from wall-clock gaps or round_finished durations. Missing
checkpoints undercount time. The client should split checkpoints at midnight if
precise daily attribution matters; the whole increment currently belongs to the
event's occurred_at day. No average-session-duration metric is precomputed.

## Level difficulty

The inner query groups by installation, round_id and all reported dimensions. It
uses flags indicating whether any start, finish or each outcome occurred, then
aggregates across rounds for each dimension group.

- Starts/finishes/wins/timeouts/explicit abandonments count flagged rounds.
- Incomplete means a start exists without a finish; it does not mean a crash.
- Completed win percent is wins divided by known finishes, multiplied by 100.
- Mean win seconds averages the per-round recorded duration for won rounds, rounded
  to two decimals; it is not a median or percentile.
- Incorrect actions sum each round's recorded count; rounds without a finish
  contribute no action total.

Multiple conflicting finishes for one round can set several outcome flags; maximum
active_seconds and incorrect_actions are selected for that group. Distinct dimensions
split a round into separate groups. The API does not prevent those inconsistencies.
Clients must produce one finish and stable metadata. Missing starts do not prevent
finishes/wins from counting. A retry with the same event ID is safely deduplicated;
new IDs for duplicate logical events are not generally safe.

This view covers **all retained events**, with no day column/date filter. Comparisons
across puzzle revisions and modes are supported; day-specific difficulty needs a new
view/question. It does not report every raw pointer movement or unrecorded actions.

## Onboarding

The report groups observed production installations by first_seen date and counts
those with at least one distinct round_started round ID, any win, and at least ten
distinct started round IDs. Cohorts are limited to the last 89 dates/today.

These are cumulative milestone counts within retained history, not a strictly ordered
funnel or a fixed D1 conversion window. first_open is not required, a win without a
start can count, and time-to-milestone is not measured. Events from random/practice
play are combined. Compare cohorts of similar age rather than assuming mature and
new cohorts had equal opportunity to complete ten rounds.

## Ads and money

Ad delivery counts lifecycle events by event day. It does not join attempt timelines
or calculate load/fill rate. Loading yesterday and displaying today contributes to
different rows. A successful load is not an impression. Ad retries/callback duplicates
with different IDs can inflate counts.

Revenue is `sum(value_micros) / 1,000,000`, separated by day, currency and precision.
The monetization view then sums precision categories within each day/currency:

- ARPDAU = that currency's daily revenue / qualifying DAU.
- eCPM = 1,000 × daily revenue / impressions, only when exactly **one revenue currency**
  exists that day. Multiple currencies produce NULL eCPM; no exchange rate is invented.
- A zero/missing denominator yields NULL, not zero.

Only days with revenue events appear in monetization. The impression denominator has
no currency tag, and timing/provider differences can make these observational metrics
diverge from ad-network statements. Reconcile before using them for financial decisions.
No projected LTV, cohort revenue, purchase revenue, acquisition spend or ROAS is computed.

## Ingestion diagnostics

Counts use server received_at day, grouped by environment and event name. Mean delay
is received_at minus occurred_at in seconds, rounded. Offline uploads increase delay;
accepted future timestamps can make it negative. Only stored events appear: duplicates,
rejected requests, rate-limit responses and storage errors are not persisted as metrics.

## Retention and historical completeness

Daily maintenance removes raw events older than 90 days using occurred_at. Metadata
can remain longer, so cohort identities outlive their raw events. No durable reporting
snapshots or materialized aggregate history exist.

The audience view displays today and the preceding 89 dates. After cleanup, its
oldest 29 MAU rows and oldest six WAU rows can have incomplete lookbacks. Use the
most recent **60 completed UTC dates** for a fully retained 30-day lookback. Initial
deployment history is also necessarily incomplete before collection began.

Level/ad/engagement totals shrink when raw events expire. Long-range retention or
cohort revenue cannot be reconstructed from metadata alone. Save approved aggregates
before raw expiry if longer historical reporting becomes a requirement.

## Data dictionary

| Table | Key and important fields |
| --- | --- |
| public.events | event_id UUID primary key; install_id/session_id UUID; sequence integer; occurred_at/received_at timestamptz; build_version varchar(32); platform/environment varchar(16); name varchar(32); payload JSONB; fingerprint char(64) |
| public.installations | Composite primary key (install_id, environment); first_seen timestamptz |
| public.schema_version | Integer version primary key; current marker 1 |

Events has indexes on occurred_at, (install_id, occurred_at), and (name, occurred_at)
for production rows. There are no foreign keys requiring installation/session/round
rows. schema_version is validated and fingerprinted on ingestion but is not a separate
column in events. Reporting views and grants are defined in schema.sql.

## Extending the dashboard

Use the analytics connection, add reviewed SQL views in schema.sql, and apply schema
updates before adding questions. Keep field names and cohort definitions documented.
setup_dashboard.py creates nine table cards once; if a dashboard named Game KPIs
already exists it exits without repairing/updating cards. It is not a migration tool
for dashboard edits. Partial setup may leave a dashboard needing manual repair.

verify_dashboard.py uses the URL saved in credentials.json and expects exactly nine
cards. Update the verifier deliberately when the dashboard design changes. Do not
publish public Metabase sharing links as a substitute for the private access model.
