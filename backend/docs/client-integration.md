# Godot client integration

[Index](../README.md) · [API contract](api.md) · [Metric definitions](reporting.md)

Current build: **game 1.5.2 / Android version code 14**, updated 9 October 2026.
The native game now records optional usage data and delivers it to
`https://putitback.vdsolution.com/v1/events/batch`. Players do not need OpenVPN.
Collection starts **off**. Source changes do not update existing installations:
distribute a configured release build to start receiving player events.

## Player controls and data scope

The main menu has **Usage data: off/on**. The explanation screen offers **Allow
usage data** or **Turn off**. Gameplay works regardless of the choice, configuration
or network availability. This setting is independent of AdMob privacy/consent.

Opt-in creates a random installation UUID and begins collection. The client sends
only API-allowlisted fields: version/platform, level/mode, aggregate actions and
timings, outcomes, ad lifecycle and SDK revenue. No name, email, advertising ID,
device identifier, pointer coordinates or raw SDK error message is sent. The ID
links events within an installation, so this is pseudonymous analytics. Network
infrastructure sees the connection IP; it is not an event payload field.

Opt-out cancels the active request, clears pending events and round counters, and
overwrites both queue snapshots. Already committed uploads cannot be recalled.
Previously received data remains subject to server retention/operator deletion.
The installation ID and first-open flag remain locally to avoid recounting the
installation after re-enabling. Late ad callbacks from an earlier opt-in period
are ignored, including after re-enabling collection.

Server defaults: raw events 90 days; inactive first-seen metadata 365 days once no
retained events remain; scheduled local backups 14 days. Manual archives are
separate. See the [operations runbook](operations.md) for deletion and retention.
There is no client deletion endpoint or server deletion tombstone. Public privacy
information/contact details and store disclosure remain release-owner work.

Only participating installations appear in KPIs. `first_open` means first telemetry
opt-in, potentially later than installation/first play. Opt-out gaps, reinstalls
and queue eviction affect retention; these are not total store-install counts.

## Source map

| File | Responsibility |
| --- | --- |
| [project.godot](../../project.godot) | Telemetry autoload and application version |
| [telemetry.gd](../../scripts/telemetry/telemetry.gd) | Gating, identity/session, event envelopes, counters, HTTPS and retries |
| [event_store.gd](../../scripts/telemetry/event_store.gd) | Checksummed persistence, caps, batches and receipt validation |
| [ad_attempt.gd](../../scripts/telemetry/ad_attempt.gd) | Ad identity, callback deduplication and revenue/error conversion |
| [game.gd](../../scripts/game.gd) | Settings UI, lifecycle, tap/round hooks and clocks |
| [puzzle_interaction.gd](../../scripts/puzzle_interaction.gd) | One drag action per owning-pointer release |
| [android_ads.gd](../../scripts/ads/android_ads.gd) | Actual AdMob load, impression, failure, close and paid callbacks |
| [configure-telemetry.ps1](../../tools/configure-telemetry.ps1) | Generates ignored client configuration |
| [build_telemetry_qa.ps1](../../tools/build_telemetry_qa.ps1) | Builds a separate Android app with the test flag embedded |
| [test_telemetry.gd](../../tools/test_telemetry.gd) | Isolated storage, transport, lifecycle, ad and gameplay checks |
| [smoke_telemetry.gd](../../tools/smoke_telemetry.gd) | Explicit live upload and persisted duplicate replay |

The existing ad scheduler still controls presentation. Live ads remain disabled by
the existing test-ad configuration. No SDK or server schema change was necessary.
The historical HTML/Capacitor version is not instrumented by this integration.

## Build configuration

`resources/telemetry_config.json` contains only `endpoint` and `ingestion_key`.
It is Git-ignored and explicitly included by both native export presets. The
[example](../../resources/telemetry_config.example.json) has a placeholder.
Missing/invalid configuration disables collection without preventing gameplay.

On this configured PC, generate it without displaying credentials:

```powershell
& './tools/configure-telemetry.ps1'
```

The script reads the protected local `verification/put-it-back-credentials.json`
and copies only its ingestion_key. Another authorized workstation can use:

```powershell
& './tools/configure-telemetry.ps1' -CredentialsPath 'C:/private/telemetry-credentials.json'
```

Alternatively copy the example to `resources/telemetry_config.json` and set the key
locally. Do not commit it or paste it into logs. The ingestion key is extractable
from a distributed game and grants ingestion access only. Never package dashboard,
database or SSH credentials, the source credentials file or backend `.env`.
Verification is export-excluded; the backend has `.gdignore`.

The destination is pinned to the exact HTTPS URL above. Domain changes require code
and configuration updates together. Godot uses normal TLS validation, no redirects,
and headers Content-Type application/json, User-Agent PutItBackTelemetry/1.0 and
bearer authorization. This actual native User-Agent passed the public HTTPS test.

| Run | Availability and environment |
| --- | --- |
| Configured native release export | Available, initially off; production after player opt-in |
| Ordinary editor, debug export or headless run | Disabled, regardless of saved preference |
| Explicit `--telemetry-test` | Available, initially off; test, separate identity and storage |
| `--self-test`, `--gallery`, `--telemetry-unit-tests` | Always disabled at startup, even with QA flag |
| Web exports / unsupported OS | Disabled; browser CORS is not implemented |

The standard build script makes a **Windows release executable** and **Android
debug APK**. The default APK therefore keeps collection disabled. A signed Android
release export enables the player-controlled production path; configure release
signing in Godot before distribution without committing signing credentials.
The QA flag overrides editor/debug/headless gating but not automated-test flags.
It does not automatically opt in.

```powershell
# Use the local Godot 4.7.2 executable if godot is not on PATH.
godot --path . -- --telemetry-test
# In the QA game, open Usage data and allow it.
```

For a physical Android device, build the dedicated QA package:

```powershell
& './tools/build_telemetry_qa.ps1'
adb install -r exports/android/PutItBack-QA.apk
adb shell am start -n com.vdsystem.putitback.qa/com.godot.game.GodotAppLauncher
```

It installs as **Put It Back QA**, package `com.vdsystem.putitback.qa`, alongside the
normal game with separate saved progress. The build embeds `-- --telemetry-test`
using Android's `command_line/extra_args`; usage collection still starts off and
must be enabled in its menu. Events use environment=test and the existing Google
test-ad settings. The helper restores the original export presets in a finally
block and verifies APK signing. Do not run concurrent exports while it is building.
If the helper process is forcibly killed, check export_presets.cfg for its temporary
QA preset before the next normal export.

Do not rely on `adb am start` intent extras to enable QA in the ordinary APK: the
installed Godot Android runtime strips command-line extras from exported launcher
activities. The embedded build flag avoids changing that protection. USB debugging
must be authorized on the phone before ADB can install or drive either build.

Build version comes from application/config/version; current puzzle_revision is
1.5.2 (October artwork update). Update both deliberately alongside export versions when releasing changes.
Queued events preserve original dimensions after upgrades.

## Event lifecycle and clocks

UUID v4 values use Godot Crypto random bytes. Event IDs, UTC timestamps ending in Z,
schema version 1 and the complete envelope are assigned when captured, before
upload. Retries preserve them. Sequence increases within a running process;
the server does not enforce ordering.

| Event | Trigger |
| --- | --- |
| first_open | First opt-in for saved installation; flag and event persisted together |
| session_started | Enabled launch/opt-in (launch), or return after at least 30 minutes in background (resume) |
| activity_checkpoint | Approximately every 30 foreground seconds, background transition and orderly tree exit |
| round_started | After generation, with round UUID, level, random/practice mode and revision |
| round_finished | Win, timeout, explicit paused-menu exit; replacing a still-tracked round also abandons it |
| ad_requested / ad_loaded / ad_failed | Interstitial preload and SDK result, or show failure |
| ad_impression / ad_closed | Actual impression and successful presentation dismissal callbacks |
| ad_revenue | SDK paid callback: integer micros, currency and precision |

Round state is memory-only. A process kill does not invent a timeout, abandonment
or crash: the backend can report an incomplete round. Backgrounding pauses gameplay
and persists a checkpoint. Long return starts a new session; an existing round's
finish keeps its original session ID. Foreground menu pauses do not split sessions.

Foreground uses monotonic ticks, capped at one second per frame to exclude long
suspension/hitch catch-up. It includes menus and pause screens, plus ad/consent
overlays only while Godot still reports foreground. Background is excluded.
Gameplay includes only unpaused active-round time, capped to the remaining timer,
and excludes ad/consent breaks. Incremental gameplay never exceeds foreground.

Checkpoints normally cover 30–31 seconds. A kill can lose the uncheckpointed
interval. UTC midnight is not split: the entire delta belongs to its timestamp's
day, with up to one checkpoint of day-boundary imprecision. Wall-clock changes
cannot inflate durations, but a wrong date can cause server timestamp rejection.

### Actions and starting faults

One gameplay tap is one action. Tapping a currently faulty interactive piece is
useful, including intermediate rotation steps. Empty/blocked/already-correct taps
are incorrect. Useful hexagon taps restore a misplaced pair. UI controls do not count.

One owning-pointer drag release is one action, including invalid/no-movement drops.
It is useful when the sum of remaining faults decreases; otherwise incorrect. This
is an operational measure, not a minimum-move solver: some intermediate reorderings
can count as incorrect. Motion, secondary pointers, canceled drags and frozen input
do not count. Fixed end books cannot be dragged and do not count as attempts.

The winning action is included before finish. Duplicate finish calls do nothing.
Starting faults sum all positive piece faults after generation: drawer depths and
composite faults can exceed the number of misplaced objects. Limits are 10,000
actions, 1,000 starting faults and 3,600 active seconds; normal rounds are much smaller.

## Ads and revenue

Every real preload gets a new attempt UUID and callback tracker. Each callback kind
is recorded at most once, including impression and revenue. Retry/expiry creates a
new attempt. Tracking starts only when collection was on at request time; opting
in does not retroactively track an already cached ad.

Placement is between_rounds and test_ad comes from ad settings. Google Android ads
domain error codes map 0/internal, 1/invalid_request, 2/network, 3/no_fill; other
errors become unknown. No raw messages, ad-unit IDs or provider metadata are sent.
Consent dialogs generate no impression/revenue; unused expired ads get no synthetic
close. Show failures record ad_failed rather than a successful close.

Paid values preserve integer micros and SDK precision (unknown, estimated,
publisher_provided, precise). Invalid currency, precision or out-of-range value
is ignored. A late paid callback can be recorded after dismissal if collection has
not changed. Actual test-ad callbacks were verified on Android on 8 October 2026.
Production provider reconciliation remains separate; neither synthetic adapter
tests nor zero-value test ads certify live paid-ad delivery.

## Persistence and delivery

Production files: user://telemetry-0.json and user://telemetry-1.json.
QA files: user://telemetry-test-0.json and user://telemetry-test-1.json.
These are Godot user-data paths, separate from progress. They are not encrypted;
they contain local pseudonymous analytics, never the bearer/dashboard credentials.

Each snapshot has versioned JSON, generation and SHA-256 checksum. Writes alternate
files and flush before close. Startup takes the newest valid snapshot, falling back
if a write tore. If both are unusable, collection defaults off. Checksums detect
corruption, not malicious modification; this is not a guarantee against disk loss.

Events are persisted before upload; first-open state is saved with its event. Disk
write failure prevents uploading and is retried, without blocking gameplay. Opt-out
changes runtime behavior immediately; a failed disk cannot guarantee that the
preference survived restart. Both snapshots are overwritten on a successful opt-out.

| Bound | Behavior |
| --- | --- |
| Count | 512 queued events |
| Encoded event bytes | 512,000; snapshot wrapping/escaping adds overhead, with two files |
| Age | Drop events older than seven days by device clock |
| Overflow | Keep newest fitting events and evict older ones |
| Batch | At most 100 events and JSON body strictly below 250,000 UTF-8 bytes |
| HTTP | One asynchronous request; 10-second timeout, 65,536-byte response limit |
| Normal cadence | First attempt after about 20 seconds; successful requests at least 20 seconds apart |

Flush checks run in foreground; background transition attempts one only if the
schedule permits. Data already persisted does not depend on background upload
completion. There is no suspended/background service or threshold upload burst.
Orderly exit persists a checkpoint without waiting for networking.

A 200 receipt is fully validated before any mutation. Accepted/duplicate IDs must
belong to the in-flight snapshot; rejection indexes must be integral/in-range with
known codes. Duplicate/conflicting receipt entries invalidate the receipt. Known
permanent rejections are dropped and counted. Missing acknowledgements remain, as
do events appended during upload. Empty/malformed receipts retry. If saving an ACK
fails, a later duplicate retry is safe. JSON numeric formatting can change on
reload, but original validated values/IDs/timestamps and server fingerprints match.

| Failure | Action |
| --- | --- |
| Network, timeout, TLS, 5xx, malformed receipt and other transient responses | Keep events; exponential backoff from 5 seconds to 300-second base plus 0–25% jitter |
| 429 | Keep events; honor numeric Retry-After, minimum 60 seconds (server uses seconds) |
| 413 | Halve batch limit; drop/count a single oversize event |
| 401, 403, 404, 405, 415, 422 | Suspend for process; correct configuration, then relaunch or toggle collection |
| invalid_event, timestamp_out_of_range, event_id_conflict | Drop only the rejected indexed event and increment local loss count |

Diagnostic fields are last_status, disk_ok, suspended, queue size and dropped count.
Runtime does not log event bodies, IDs or credentials. There is no remote client
health monitor. Queue loss can leave orphan finishes/missing starts; this is not an
accounting ledger. No crash/ANR SDK, purchase validation, experiments or browser
transport is included.

## Validation and release checks

The normal build runs the isolated telemetry tests before exports:

```powershell
godot --headless --path . --script tools/test_telemetry.gd -- --telemetry-unit-tests
& './tools/build.ps1'
```

Tests use only verification/telemetry-unit-* snapshots and clean them afterward.
The normal autoload is suppressed before injecting the test store. Coverage includes
restart/torn writes, original identities/times, malformed/partial/unknown receipts,
new events during upload, count/byte/age caps, first-open/session behavior, time
deltas, duplicate finishes and SDK callbacks, exact paid micros, long resume,
429/413/network/401, opt-out persistence in both snapshots, late callbacks across
re-enable, winning tap/drag, timeout and explicit abandonment.

The explicit live smoke requires local configuration and QA collection initially off:

```powershell
godot --headless --path . --script tools/smoke_telemetry.gd -- --telemetry-test
```

It temporarily opts in, uploads a known test sequence, reloads the original
persisted events to simulate a lost ACK, verifies duplicate receipts, then turns
QA collection off. Evidence is written to the ignored
verification/telemetry-live-result.json without the key. Test events remain under
server retention and are excluded from production KPIs; ingestion reports show them.

Verified 7 October 2026:

- Telemetry tests and Android adapter parsing passed.
- Full regression suite passed: 28 levels, 20 randomized solves each, timeouts,
  mouse/touch interaction, ad scheduling and graphics checks.
- Actual Godot HTTPS: 12 accepted and zero rejected; persisted replay returned
  12 duplicates, zero newly accepted and zero rejected.
- Windows release and Android debug exports completed; APK signing verification
  passed. Menu and usage screen were rendered and visually inspected.
- The Windows embedded resource pack and Android APK include the generated client
  configuration. Checked server `.env`/credentials and the protected operator
  credentials file are absent from the Windows pack; no such files appeared in the
  Android package inspection.

Physical Android validation followed on 8 October 2026 using a Samsung Galaxy S24+
(Android 16), a separate QA package and `environment=test`. Offline persistence,
restart/reconnect delivery, a bottle-swap win, random timeouts, queued-data opt-out,
and actual AdMob test-ad impression/paid/close callbacks were confirmed against
PostgreSQL. Device testing exposed Android Back auto-quitting and a high-refresh
timing undercount; version 1.5.1 fixes both. See the
[device validation record](../../docs/android-telemetry-validation.md) for evidence,
retest results and remaining release checks. A debug-signed QA build does not
validate production signing, UMP or live paid-ad delivery.

Scheduled encrypted off-server backups, external alerts, gateway certificate
renewal, acquisition/ROAS, long-term aggregates, provider reconciliation and
crash/performance reporting remain in the [broader roadmap](../../docs/telemetry-plan.md).
