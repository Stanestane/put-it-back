# Android telemetry validation — 8 October 2026

[Client integration](../backend/docs/client-integration.md) · [Backend documentation](../backend/README.md)

Device: Samsung Galaxy S24+ (SM-S926B), Android 16, 1080 × 2340 display.
USB debugging was authorized by the owner. Testing used **Put It Back QA**, package
`com.vdsystem.putitback.qa`, with the embedded `--telemetry-test` argument.
The normal app and its progress were preserved. All telemetry in these checks used
`environment=test`; test events are excluded from production KPIs.

## Confirmed on the device and backend

| Scenario | Observed result |
| --- | --- |
| Offline queue and process restart | 29 persisted events survived force-stop/relaunch unchanged, with the same installation identity. |
| Reconnect over HTTPS | The queue drained with zero dropped events. PostgreSQL contained all 29 distinct IDs in the test environment. |
| Practice bottle puzzle (level 24) | A single drag swapped the misplaced bottles and produced one win: 1 action, 0 incorrect actions, 2 starting faults. The matching finish was present in PostgreSQL. |
| Pausing | A 30-second foreground checkpoint while paused recorded zero gameplay time. |
| Random play | Timeouts produced round finishes and subsequent starts; the normal ad frequency gate eventually displayed a Google test interstitial. |
| Native AdMob callbacks | The same attempt had exactly one request, load, impression, paid callback and close in PostgreSQL. Closing the ad resumed the game. |
| Test revenue | The SDK paid callback contained 0 micros, USD, unknown precision and `test_ad=true`. No real revenue was generated. |
| Opt-out with pending offline data | Both saved snapshots became disabled with empty queues. They remained disabled after relaunch/reconnect. The deliberately queued event was absent from PostgreSQL. |

Initial lifecycle, offline and ad checks used 1.5.0 (version code 12). Testing found
two issues, fixed in 1.5.1 (version code 13):

- Android Back closed the app from the level picker and usage screen. Godot's
  automatic Back-to-quit behavior is now disabled, allowing game navigation to
  handle those screens and pause gameplay. A 250 ms guard also coalesces duplicate
  Back notifications from the Android key and dispatcher paths, consistent with
  [Godot issue 123454](https://github.com/godotengine/godot/issues/123454).
  Back from the main menu still exits. Duplicate and subsequent presses have
  regression coverage.
- Active-time telemetry lost fractions of a millisecond repeatedly on the phone's
  high-refresh display. Active and foreground counters now use the same monotonic
  delta, scaled by the frame's playable fraction. A deterministic 120 Hz regression
  test covers tick rounding and paused frames.

Automated validation passed: telemetry storage/transport
and lifecycle tests, Android adapter parsing, and 28 puzzle variants with 20
randomized solves each plus timeout, input, ad-scheduling and graphics checks.
The telemetry suite was rerun after adding the duplicate-Back guard.
Windows release, ordinary Android debug and separate QA exports completed; both
APKs passed signature verification. Windows startup smoke passed.

The final 1.5.1 QA build was installed and retested:

| Retest | Observed result |
| --- | --- |
| Android Back | Level picker and Usage data return to the main menu; gameplay pauses once. A subsequent press resumes. |
| Five-second timeout | Level 11 recorded 4.983 seconds, within about one frame of the game timer. PostgreSQL confirmed the same value with build version 1.5.1. |
| Home/background return | After 12 seconds away, the same round returned paused in the same session. Explicitly leaving it recorded 0.916 active seconds, excluding background and paused time. |

The reviewed QA process log contained no Godot script errors or fatal exceptions.
Android logged a Surface disconnect message during Home navigation; the game
resumed and remained playable.

At completion, the 1.5.1 QA app was left on its main menu with **Usage data: off**.
Both queue snapshots were disabled and empty after relaunch. Original Wi-Fi and
mobile-data settings were restored. The normal game installation was not replaced.

## Evidence and reproduction

Build the QA app with `tools/build_telemetry_qa.ps1` and follow the installation
instructions in the client guide. This debug-signed package is separate from the
normal app and still requires explicit opt-in through **Usage data**.

Local evidence is under Git-ignored `verification/android-qa-*`: screenshots,
checksummed snapshot copies and app logs. The offline before/after/reconnect files,
`bottle-win`, `pending-optout`, `opted-out` and `optout-relaunch` snapshots record the
checks above. Evidence is local to this workstation; it is not a committed fixture.
Server test events remain subject to normal retention.

Backend queries were scoped to the QA installation. Useful cross-checks:

- Bottle win event: `559573ae-873d-477d-84a8-b900a81749e1`.
- Complete test-ad attempt: `d6dcb760-a24a-42bd-9477-7f63d0139721`.
- Pending event cleared by opt-out (expected count zero):
  `962fa70c-0b75-41e8-b005-f289cc8dcf84`.
- Version 1.5.1 timing retest: `cc985fa7-e716-4d13-9fb6-10eb3d998505`.
- Background-return round finish: `2ebb49b5-a19a-4fee-97c5-388188b090db`.

## Remaining release checks

This session does not certify a store-signed release, live ad revenue, provider
reconciliation, or publisher UMP consent/privacy flows. The Google demo test-ad
configuration bypasses UMP. Those checks require the owner's release signing and
registered AdMob configuration.

The 30-minute session rollover, invalid moves, receipt retries/deduplication and
first-open behavior are covered by automated tests; this device session did not
independently verify every one of those cases end to end. The initial device
first-open event was cleared by opt-out before delivery, so its server ingestion
is not claimed here. Backend ingestion was queried directly; dashboard chart
rendering was not revalidated as part of this device run.
