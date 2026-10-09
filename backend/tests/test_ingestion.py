import copy
import os
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
import app

client = TestClient(app.app)
auth = {'Authorization': 'Bearer ' + os.environ['INGEST_KEY']}
created_installs = set()


@pytest.fixture(autouse=True)
def cleanup_our_events():
    yield
    with psycopg.connect(os.environ['TEST_ADMIN_DATABASE_URL']) as db:
        for install in created_installs:
            db.execute('DELETE FROM events WHERE install_id=%s', (install,))
            db.execute('DELETE FROM installations WHERE install_id=%s', (install,))
    created_installs.clear()


def event(name='first_open', environment='test', **payload):
    return dict(event_id=str(uuid4()), schema_version=1, install_id=str(uuid4()),
                session_id=str(uuid4()), sequence=0, occurred_at=datetime.now(timezone.utc).isoformat(),
                build_version='backend-test', platform='android', environment=environment,
                payload=dict(name=name, **payload))


def post(events):
    created_installs.update(e['install_id'] for e in events if 'install_id' in e)
    return client.post('/v1/events/batch', headers=auth, json={'events': events})


def test_health_and_auth():
    assert client.get('/health/ready').status_code == 200
    assert client.post('/v1/events/batch', json={'events': [event()]}).status_code == 401


def test_durable_retry_and_conflict():
    e = event()
    assert post([e]).json()['accepted'] == [e['event_id']]
    assert post([e]).json()['duplicates'] == [e['event_id']]
    e['platform'] = 'ios'
    assert post([e]).json()['rejected'] == [{'index': 0, 'code': 'event_id_conflict'}]


def test_partial_rejection_and_no_sensitive_fields():
    good, bad = event(), event()
    bad['email'] = 'should-not-be-stored@example.com'
    result = post([good, bad]).json()
    assert result['accepted'] == [good['event_id']]
    assert result['rejected'] == [{'index': 1, 'code': 'invalid_event'}]


def test_clock_and_counter_validation():
    old = event()
    old['occurred_at'] = (datetime.now(timezone.utc)-timedelta(days=31)).isoformat()
    future = copy.deepcopy(old)
    future['occurred_at'] = (datetime.now(timezone.utc)+timedelta(days=1)).isoformat()
    bad = event('activity_checkpoint', foreground_seconds=1, gameplay_seconds=2)
    result = post([old, future, bad]).json()
    assert not result['accepted']
    assert [r['code'] for r in result['rejected']] == ['timestamp_out_of_range']*2+['invalid_event']


def test_body_and_batch_bounds():
    assert post([]).status_code == 422
    assert post([event() for _ in range(101)]).status_code == 422
    assert client.post('/v1/events/batch', headers={**auth, 'Content-Type': 'application/json'},
                       content=' '*262145).status_code == 413
    assert client.post('/v1/events/batch', headers=auth, content='{}').status_code == 415


def test_rate_limiter():
    limit = app.RateLimiter()
    assert limit.allow('one', 1)
    assert not limit.allow('one', 1)
    assert limit.allow('two', 1)


def test_storage_failure_is_retryable(monkeypatch):
    def fail(_):
        raise psycopg.OperationalError('deliberate test failure')
    monkeypatch.setattr(app, 'persist', fail)
    assert post([event()]).status_code == 503


def test_read_only_reporting_and_mature_retention():
    # Administrator connection is provided ONLY to the disposable test container.
    admin = os.environ['TEST_ADMIN_DATABASE_URL']
    install = str(uuid4())
    yesterday = datetime.now(timezone.utc).replace(hour=12, minute=0, second=0)-timedelta(days=2)
    first = event(environment='production')
    first.update(install_id=install, occurred_at=yesterday.isoformat())
    returned = event('session_started', environment='production', entry_point='launch')
    returned.update(install_id=install, occurred_at=(yesterday+timedelta(days=1)).isoformat())
    try:
        assert len(post([first, returned]).json()['accepted']) == 2
        with psycopg.connect(admin) as db:
            cohort = db.execute('SELECT day_number,cohort_size,returned FROM analytics.retention WHERE cohort_day=%s',
                                (yesterday.date(),)).fetchall()
            assert any(day == 1 and size >= 1 and back >= 1 for day,size,back in cohort)
            assert not any(day in (7,30) for day,_,_ in cohort)
            # Development/test events must not create production activity.
            test_event = event()
            assert post([test_event]).status_code == 200
            assert db.execute('SELECT count(*) FROM analytics.activity WHERE install_id=%s',
                              (test_event['install_id'],)).fetchone()[0] == 0
        with psycopg.connect(os.environ['TEST_READER_DATABASE_URL']) as reader:
            reader.execute('SELECT * FROM analytics.audience LIMIT 1')
            assert reader.execute('SELECT count(*) FROM analytics.qa_events WHERE install_id=%s',
                                  (test_event['install_id'],)).fetchone()[0] == 1
            assert reader.execute('SELECT count(*) FROM analytics.qa_events WHERE install_id=%s',
                                  (install,)).fetchone()[0] == 0
            assert reader.execute("SELECT count(*) FROM analytics.qa_events WHERE environment<>'test'").fetchone()[0] == 0
            with pytest.raises(psycopg.Error):
                reader.execute('SELECT * FROM public.events LIMIT 1')
            reader.rollback()
            with pytest.raises(psycopg.Error):
                reader.execute('DELETE FROM public.events')
    finally:
        with psycopg.connect(admin) as db:
            db.execute('DELETE FROM events WHERE install_id=%s', (install,))
            db.execute('DELETE FROM installations WHERE install_id=%s', (install,))


def test_known_level_playtime_and_revenue_totals():
    install, session, round_id, attempt = map(str, (uuid4(), uuid4(), uuid4(), uuid4()))
    fields = dict(round_id=round_id, level_id=24, mode='practice', puzzle_revision='swap-v1')
    sample = [event('round_started', **fields),
              event('round_finished', **fields, outcome='win', active_seconds=2,
                    actions=2, incorrect_actions=1, starting_faults=2),
              event('round_started', **{**fields, 'round_id': str(uuid4())}),
              event('activity_checkpoint', foreground_seconds=30, gameplay_seconds=7),
              event('ad_impression', attempt_id=attempt, placement='between_rounds', test_ad=False),
              event('ad_revenue', attempt_id=attempt, placement='between_rounds', test_ad=False,
                    value_micros=10000, currency='USD', precision='precise'),
              event('ad_revenue', attempt_id=str(uuid4()), placement='between_rounds', test_ad=True,
                    value_micros=999999, currency='EUR', precision='estimated')]
    for item in sample:
        item.update(install_id=install, session_id=session, environment='production')
    assert len(post(sample).json()['accepted']) == 7
    # Duplicate delivery must not change any metric.
    assert len(post(sample).json()['duplicates']) == 7
    with psycopg.connect(os.environ['TEST_ADMIN_DATABASE_URL']) as db:
        row = db.execute("SELECT starts,finishes,wins,incomplete,mean_win_seconds FROM analytics.levels WHERE build_version='backend-test'").fetchone()
        assert tuple(map(float, row)) == (2,1,1,1,2)
        row = db.execute('SELECT observed_sessions,foreground_seconds,gameplay_seconds FROM analytics.engagement').fetchone()
        assert tuple(map(float, row)) == (1,30,7)
        row = db.execute('SELECT currency,revenue,dau,impressions,arpdau,ecpm FROM analytics.monetization').fetchall()
        assert len(row) == 1 and row[0][0] == 'USD'
        assert tuple(map(float, row[0][1:])) == (0.01,1,1,0.01,10)
