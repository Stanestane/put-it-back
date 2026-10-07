"""Bounded, authenticated, idempotent ingestion. No IPs or payloads in logs."""
import hashlib
import hmac
import json
import os
import time
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Annotated, Literal
from uuid import UUID

import psycopg
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, ValidationError, AwareDatetime
from psycopg.types.json import Jsonb

UTC = timezone.utc
MAX_BODY = 262144
DATABASE_URL = os.environ['DATABASE_URL']
INGEST_KEY = os.environ['INGEST_KEY']
if len(INGEST_KEY) < 32:
    raise RuntimeError('INGEST_KEY must have at least 32 characters')


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid')


class FirstOpen(Strict):
    name: Literal['first_open']


class SessionStarted(Strict):
    name: Literal['session_started']
    entry_point: Literal['launch', 'resume']


class Checkpoint(Strict):
    name: Literal['activity_checkpoint']
    # Incremental counters since the preceding checkpoint, never cumulative.
    foreground_seconds: float = Field(ge=0, le=300, allow_inf_nan=False)
    gameplay_seconds: float = Field(ge=0, le=300, allow_inf_nan=False)


class RoundStarted(Strict):
    name: Literal['round_started']
    round_id: UUID
    level_id: int = Field(ge=1, le=10000)
    mode: Literal['random', 'practice']
    puzzle_revision: str = Field(min_length=1, max_length=32, pattern=r'^[a-zA-Z0-9._-]+$')


class RoundFinished(RoundStarted):
    name: Literal['round_finished']
    outcome: Literal['win', 'timeout', 'abandoned']
    active_seconds: float = Field(ge=0, le=3600, allow_inf_nan=False)
    actions: int = Field(ge=0, le=10000)
    incorrect_actions: int = Field(ge=0, le=10000)
    starting_faults: int = Field(ge=0, le=1000)


class Ad(Strict):
    name: Literal['ad_requested', 'ad_loaded', 'ad_failed', 'ad_impression', 'ad_closed']
    attempt_id: UUID
    placement: Literal['between_rounds']
    test_ad: bool
    error_category: Literal['network', 'no_fill', 'internal', 'invalid_request', 'unknown'] | None = None


class Revenue(Strict):
    name: Literal['ad_revenue']
    attempt_id: UUID
    placement: Literal['between_rounds']
    test_ad: bool
    value_micros: int = Field(ge=0, le=1000000000)
    currency: str = Field(pattern=r'^[A-Z]{3}$')
    precision: Literal['unknown', 'estimated', 'publisher_provided', 'precise']


Payload = Annotated[FirstOpen | SessionStarted | Checkpoint | RoundStarted | RoundFinished | Ad | Revenue,
                    Field(discriminator='name')]


class Event(Strict):
    event_id: UUID
    schema_version: Literal[1]
    install_id: UUID
    session_id: UUID
    sequence: int = Field(ge=0, le=2147483647)
    occurred_at: AwareDatetime
    build_version: str = Field(min_length=1, max_length=32, pattern=r'^[a-zA-Z0-9._+-]+$')
    platform: Literal['android', 'ios', 'windows', 'web']
    environment: Literal['production', 'development', 'test']
    payload: Payload


class Batch(Strict):
    events: list[dict] = Field(min_length=1, max_length=100)


class RateLimiter:
    """Global cap plus bounded, in-memory installation buckets; one API worker."""
    def __init__(self):
        self.lock = Lock()
        self.buckets = OrderedDict()

    def allow(self, key, limit, period=60):
        now = time.monotonic()
        with self.lock:
            count, expires = self.buckets.pop(key, (0, now + period))
            if now >= expires:
                count, expires = 0, now + period
            self.buckets[key] = (count + 1, expires)
            while len(self.buckets) > 10000:
                self.buckets.popitem(last=False)
            return count < limit


limiter = RateLimiter()
app = FastAPI(title='Put It Back telemetry', docs_url=None, redoc_url=None, openapi_url=None)


@app.get('/health/live')
def live():
    return {'status': 'ok'}


@app.get('/health/ready')
def ready():
    try:
        with psycopg.connect(DATABASE_URL, connect_timeout=3) as conn:
            conn.execute('SELECT 1 FROM events LIMIT 1')
    except psycopg.Error:
        raise HTTPException(503, 'Database unavailable')
    return {'status': 'ready'}


def persist(events):
    accepted, duplicates, rejected = [], [], []
    with psycopg.connect(DATABASE_URL, connect_timeout=5, options='-c statement_timeout=5000') as conn:
        for index, event in events:
            canonical = event.model_dump(mode='json')
            fingerprint = hashlib.sha256(json.dumps(canonical, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            payload = canonical['payload']
            row = conn.execute('''INSERT INTO events
                (event_id, install_id, session_id, sequence, occurred_at, build_version, platform,
                 environment, name, payload, fingerprint)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (event_id) DO NOTHING RETURNING event_id''',
                (event.event_id, event.install_id, event.session_id, event.sequence, event.occurred_at,
                 event.build_version, event.platform, event.environment, payload['name'], Jsonb(payload), fingerprint)).fetchone()
            if row:
                conn.execute('''INSERT INTO installations (install_id, environment, first_seen)
                    VALUES (%s,%s,%s) ON CONFLICT (install_id,environment)
                    DO UPDATE SET first_seen=LEAST(installations.first_seen, EXCLUDED.first_seen)''',
                    (event.install_id, event.environment, event.occurred_at))
                accepted.append(str(event.event_id))
            else:
                existing = conn.execute('SELECT fingerprint FROM events WHERE event_id=%s', (event.event_id,)).fetchone()
                if existing and hmac.compare_digest(existing[0], fingerprint):
                    duplicates.append(str(event.event_id))
                else:
                    rejected.append({'index': index, 'code': 'event_id_conflict'})
    # Context manager commits before any IDs are acknowledged.
    return accepted, duplicates, rejected


@app.post('/v1/events/batch')
async def ingest(request: Request):
    if not hmac.compare_digest(request.headers.get('authorization', '').encode(), ('Bearer ' + INGEST_KEY).encode()):
        raise HTTPException(401, 'Invalid ingestion key')
    if not limiter.allow('global', 600):
        raise HTTPException(429, 'Request limit reached', headers={'Retry-After': '60'})
    if request.headers.get('content-type', '').split(';')[0].strip() != 'application/json':
        raise HTTPException(415, 'Use application/json')
    if request.headers.get('content-encoding', 'identity') != 'identity':
        raise HTTPException(415, 'Compressed requests are not supported')
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > MAX_BODY:
            raise HTTPException(413, 'Batch too large')
    try:
        batch = Batch.model_validate_json(bytes(body))
    except ValidationError:
        raise HTTPException(422, 'Expected 1 to 100 event objects')
    valid, rejected = [], []
    now = datetime.now(UTC)
    for index, raw in enumerate(batch.events):
        try:
            event = Event.model_validate(raw)
            if not now - timedelta(days=30) <= event.occurred_at <= now + timedelta(minutes=5):
                rejected.append({'index': index, 'code': 'timestamp_out_of_range'})
                continue
            if isinstance(event.payload, Checkpoint) and event.payload.gameplay_seconds > event.payload.foreground_seconds:
                raise ValueError('Invalid checkpoint')
            if isinstance(event.payload, RoundFinished) and event.payload.incorrect_actions > event.payload.actions:
                raise ValueError('Invalid action counters')
            valid.append((index, event))
        except (ValidationError, ValueError):
            rejected.append({'index': index, 'code': 'invalid_event'})
    for install_id in {str(event.install_id) for _, event in valid}:
        if not limiter.allow('install:' + install_id, 30):
            raise HTTPException(429, 'Installation limit reached', headers={'Retry-After': '60'})
    try:
        # Run synchronous database work off the async request loop.
        from starlette.concurrency import run_in_threadpool
        accepted, duplicates, conflicts = await run_in_threadpool(persist, valid)
    except psycopg.Error:
        raise HTTPException(503, 'Storage unavailable; retry this batch')
    return {'accepted': accepted, 'duplicates': duplicates, 'rejected': rejected + conflicts}
