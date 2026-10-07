# Telemetry API reference

[Index](../README.md) · [Client integration](client-integration.md)

This describes [app.py](../app.py), schema version 1. Field names are case-sensitive.
No public Swagger, ReDoc or OpenAPI endpoint is enabled.

## Endpoints

Base URL: `https://putitback.vdsolution.com`.

| Method/path | Authentication | Success |
| --- | --- | --- |
| `GET /` | None | Plain text identifying the API |
| `GET /health/live` | None | `{"status":"ok"}`; process only |
| `GET /health/ready` | None | `{"status":"ready"}`; connects to PostgreSQL and queries events |
| `POST /v1/events/batch` | Shared bearer key | Accepted IDs, duplicate IDs and rejected indexes |

The root is not the dashboard. Unconfigured routes return 404, unsupported API
methods normally return 405, and DB readiness failures return 503. Public proxies
may produce their own errors.

## Request and limits

```http
POST /v1/events/batch
Authorization: Bearer <INGEST_KEY>
Content-Type: application/json
User-Agent: PutItBackTelemetry/1.0
```

The application identifier passed public checks; the default Python urllib agent
received Cloudflare 403. User-Agent is not authentication. Test actual mobile HTTP
clients against edge rules; browser success alone is insufficient.

| Limit | Implementation |
| --- | --- |
| Envelope | Object containing only `events`, an array of 1–100 objects |
| Size | Caddy setting `256KB`; API ceiling 262,144 bytes. Keep UTF-8 batches below 250,000 bytes to stay below both |
| Encoding | JSON; omit Content-Encoding or use `identity`; no compressed uploads |
| Media type | application/json, optionally with charset parameter |
| Global throttle | 600 authenticated requests per process in a 60-second window |
| Installation throttle | 30 batches per installation in a 60-second window |
| Event time | At most 30 days old, at most five minutes ahead of server time |
| Response caching | Public route sets Cache-Control: no-store |

Limits are in memory, capped at 10,000 bucket entries. Windows begin at first use,
not a wall-clock minute. Restart resets them; bucket eviction can reset installation
history. Multiple API workers/replicas would have independent counters. There is
no distributed/per-IP limit or durable rejection counter.

Authentication precedes the global limit; invalid authenticated requests still
consume global capacity. Installation checks happen after event validation and
charge once per distinct valid installation in a batch. If any exceeds its limit,
the whole batch returns 429 before storage.

## Common event envelope

Every field is required. Send native JSON strings/numbers/booleans as documented,
rather than relying on incidental Pydantic coercions. Extra fields are forbidden
at envelope, event and payload levels.

| Field | Type/restriction | Meaning |
| --- | --- | --- |
| `event_id` | UUID string | Stable logical event identity across retries |
| `schema_version` | Integer 1 | Only supported contract version |
| `install_id` | UUID string | Pseudonymous installation identity |
| `session_id` | UUID string | Client session, required on every event |
| `sequence` | Integer 0–2,147,483,647 | Stored; no monotonicity or uniqueness enforcement |
| `occurred_at` | Timezone-aware timestamp; send ISO 8601 with Z/offset | Event time, not upload time |
| `build_version` | 1–32 chars, `^[a-zA-Z0-9._+-]+$` | Release/build identifier |
| `platform` | android, ios, windows, web | Platform label; clients are not all implemented |
| `environment` | production, development, test | Reporting exclusion control |
| `payload` | Event object below | Discriminated by its name field |

Generate random UUIDs; the parser does not require a particular UUID version. Event
IDs are global across installations and environments. The server adds received_at
and a fingerprint; it does not synthesize missing lifecycle events or infer causality.

## Payloads

All fields below are required unless marked optional. Only fields belonging to that
event are accepted; common metadata belongs in the envelope.

### first_open

```json
{"name":"first_open"}
```

No additional payload fields. Emitting this once per installation is the client's job.

### session_started

| Field | Value |
| --- | --- |
| name | session_started |
| entry_point | launch or resume |

The proposed 30-minute inactivity boundary is not enforced on the server.

### activity_checkpoint

| Field | Value |
| --- | --- |
| name | activity_checkpoint |
| foreground_seconds | Finite number 0–300 |
| gameplay_seconds | Finite number 0–300; no greater than foreground_seconds |

Times are **increments since the preceding checkpoint**, not cumulative session
totals. There is no last_round field in this version, despite that earlier proposal.

### round_started

| Field | Value |
| --- | --- |
| name | round_started |
| round_id | UUID string |
| level_id | Integer 1–10,000 |
| mode | random or practice |
| puzzle_revision | 1–32 chars, `^[a-zA-Z0-9._-]+$` |

The numeric range is validated, not membership in the actual level catalogue.

### round_finished

Includes round_id, level_id, mode and puzzle_revision with the same restrictions,
plus:

| Field | Value |
| --- | --- |
| name | round_finished |
| outcome | win, timeout, abandoned |
| active_seconds | Finite number 0–3,600 |
| actions | Integer 0–10,000 |
| incorrect_actions | Integer 0–10,000; no greater than actions |
| starting_faults | Integer 0–1,000 |

Use identical dimensions on the start and finish. Abandoned means an explicit exit,
not an inferred crash. There is no constraint requiring a start, one finish per
round, or consistent dimensions between separate events.

### Ad lifecycle events

| Field | Value |
| --- | --- |
| name | ad_requested, ad_loaded, ad_failed, ad_impression, ad_closed |
| attempt_id | UUID shared across one attempt's lifecycle |
| placement | between_rounds |
| test_ad | Boolean |
| error_category | Optional/null, or network, no_fill, internal, invalid_request, unknown |

The model permits error_category on all these names; it is not mandatory on
ad_failed. Prefer a category for failures. Raw provider messages, ad-unit IDs and
preceding-round IDs are not version-1 fields.

### ad_revenue

| Field | Value |
| --- | --- |
| name | ad_revenue |
| attempt_id | UUID string |
| placement | between_rounds |
| test_ad | Boolean |
| value_micros | Integer 0–1,000,000,000; 1,000,000 micros = one currency unit |
| currency | Three uppercase letters, `^[A-Z]{3}$` |
| precision | unknown, estimated, publisher_provided, precise |

Currency syntax, not actual currency membership, is checked. There is no FX
conversion, provider reconciliation or negative-revenue correction in this contract.

## Complete example

Replace this illustrative timestamp with actual event time when testing; it expires
outside the 30-day acceptance window.

```json
{
  "events": [
    {
      "event_id": "a6d58543-7769-4a72-805d-09d9d1d35bf8",
      "schema_version": 1,
      "install_id": "237a2eb7-0b75-4229-a737-51dff3fc8b90",
      "session_id": "e8230aa1-f5b9-44b9-8fa2-e3ea85aa3b88",
      "sequence": 0,
      "occurred_at": "2026-10-07T06:00:00Z",
      "build_version": "1.4.0",
      "platform": "android",
      "environment": "test",
      "payload": {"name": "first_open"}
    }
  ]
}
```

## Responses and durability

**HTTP 200 does not mean every event was accepted.** This example illustrates a
two-item batch with one valid event and one invalid event:

```json
{
  "accepted": ["a6d58543-7769-4a72-805d-09d9d1d35bf8"],
  "duplicates": [],
  "rejected": [{"index": 1, "code": "invalid_event"}]
}
```

Indexes are zero-based positions in the submitted batch. Rejections need not be
sorted by index because storage conflicts are appended after validation failures.
An all-invalid batch can return 200 with empty accepted/duplicate lists.

| Code | Meaning | Client handling |
| --- | --- | --- |
| invalid_event | Missing/extra/invalid fields or inconsistent counters | Quarantine/drop under policy; fix emitter |
| timestamp_out_of_range | Outside the accepted time window | Diagnose clock/queue age; do not rewrite history as current activity |
| event_id_conflict | ID exists with different validated contents | Treat as client persistence/identity bug; do not silently mint another ID |

Accepted events share one PostgreSQL transaction. The API acknowledges after commit;
storage errors return 503 with no acknowledgement. A response can be lost after
commit, so retries must reuse the same IDs and contents. Matching existing IDs are
duplicates and do not increase reports.

Fingerprinting includes the complete validated envelope/payload, including schema
version. Persist and resend the original event; changing a timestamp, sequence or
timezone representation can cause a conflict. Deduplication is by event_id, not
round_id or attempt_id. Two IDs for the same callback can double-count it.

Validation precedes duplicate lookup. A retry older than 30 days is rejected even
if that ID was previously stored. Out-of-order and late accepted events can revise
historical reports; reports are not frozen snapshots.

## HTTP error handling

| Status | Typical source | Client response |
| --- | --- | --- |
| 200 | API | Process accepted, duplicates and rejected separately |
| 401 | API | Correct key; suspend repetitive uploads |
| 403/HTML challenge | Edge/gateway | Diagnose policy and client headers; mobile cannot solve browser challenges |
| 413 | Proxy/API | Split by encoded byte size |
| 415 | API | Fix content type or encoding |
| 422 | API | Fix malformed JSON/envelope, empty/oversize array or non-object entries |
| 429 | API/edge | Back off; API sends Retry-After: 60 |
| 500/502/503/504, timeout/network error | Service/proxy/network | Retry with backoff and original IDs; infer no acknowledgement |
| 301/308 loop | Routing | Fix scheme/termination configuration; never disable certificate validation |

API errors normally contain `{"detail":"..."}`; edge errors may be HTML/plain text.
Validate status and response shape before processing acknowledgements. Cross-origin
browser CORS/preflight is not configured; native HTTP clients are the initial target.

## Runnable PowerShell example

Run from the project directory as the Windows user allowed to read the credentials.
This creates a test event, then resends it. The event remains in raw storage until
cleanup and appears in ingestion diagnostics, but not production KPIs. No VPN needed.

```powershell
$login = Get-Content -Raw 'verification/put-it-back-credentials.json' | ConvertFrom-Json
$headers = @{ Authorization = 'Bearer ' + $login.ingestion_key }
$sampleEvent = @{
    event_id = [guid]::NewGuid().ToString()
    schema_version = 1
    install_id = [guid]::NewGuid().ToString()
    session_id = [guid]::NewGuid().ToString()
    sequence = 0
    occurred_at = [DateTimeOffset]::UtcNow.ToString('o')
    build_version = 'manual-test'
    platform = 'windows'
    environment = 'test'
    payload = @{ name = 'first_open' }
}
$body = @{ events = @($sampleEvent) } | ConvertTo-Json -Depth 5 -Compress
$request = @{
    Uri = 'https://putitback.vdsolution.com/v1/events/batch'
    Method = 'Post'
    Headers = $headers
    UserAgent = 'PutItBackTelemetry/1.0'
    ContentType = 'application/json'
    Body = $body
    TimeoutSec = 15
}
Invoke-RestMethod @request  # accepted includes the ID
Invoke-RestMethod @request  # duplicates includes the same ID
```

For a server smoke test that cleans up its generated installation afterwards, run
`sudo python3 verify_proxy.py`. It requires database administrator access for that
cleanup; ordinary clients have no deletion API.
