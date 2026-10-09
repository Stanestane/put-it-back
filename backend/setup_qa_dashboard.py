"""Create/reconcile the private test-data dashboard, or verify it without edits.

Uses the existing analytics_reader connection and never changes production cards.
Run qa-view.sql first. Credentials stay in credentials.json, never in output.
"""
import argparse
import json
from pathlib import Path
import urllib.request

TITLE = 'Game QA (test data)'
DESCRIPTION = ('Test telemetry only (environment=test), including synthetic smoke tests. '
               'UTC dates. Installation IDs are not people. Test-ad payments are not real revenue. '
               'Live queries over retained events; refresh to see new uploads.')
QUESTIONS = [
    ('QA: Received events', 'SELECT count(*) AS events FROM analytics.qa_events', 'scalar'),
    ('QA: Test installations', 'SELECT count(DISTINCT install_id) AS installations FROM analytics.qa_events', 'scalar'),
    ('QA: Finished rounds', "SELECT count(*) AS finishes FROM analytics.qa_events WHERE name='round_finished'", 'scalar'),
    ('QA: Daily activity', """
SELECT (occurred_at AT TIME ZONE 'UTC')::date AS day, platform, build_version,
 count(DISTINCT install_id) AS installations,
 count(DISTINCT (install_id,session_id)) AS observed_sessions,
 count(*) FILTER (WHERE name='round_started') AS starts,
 count(*) FILTER (WHERE name='round_finished') AS finishes,
 round(coalesce(sum((payload->>'foreground_seconds')::numeric)
   FILTER (WHERE name='activity_checkpoint'),0),3) AS foreground_seconds,
 round(coalesce(sum((payload->>'gameplay_seconds')::numeric)
   FILTER (WHERE name='activity_checkpoint'),0),3) AS gameplay_seconds
FROM analytics.qa_events
WHERE name IN ('first_open','session_started','activity_checkpoint','round_started','round_finished')
GROUP BY 1,2,3 ORDER BY 1 DESC,2,3""", 'table'),
    ('QA: Sessions and playtime', """
SELECT min(occurred_at) AS first_event_utc, build_version, platform,
 count(*) FILTER (WHERE name='session_started') AS session_starts,
 count(*) FILTER (WHERE name='round_started') AS rounds_started,
 count(*) FILTER (WHERE name='round_finished') AS rounds_finished,
 round(coalesce(sum((payload->>'foreground_seconds')::numeric)
   FILTER (WHERE name='activity_checkpoint'),0),3) AS foreground_seconds,
 round(coalesce(sum((payload->>'gameplay_seconds')::numeric)
   FILTER (WHERE name='activity_checkpoint'),0),3) AS gameplay_seconds,
 max(occurred_at) AS last_event_utc, install_id, session_id
FROM analytics.qa_events GROUP BY install_id,session_id,platform,build_version
ORDER BY last_event_utc DESC LIMIT 100""", 'table'),
    ('QA: Level results', """
WITH rounds AS (
 SELECT install_id, payload->>'round_id' AS round_id,
 (payload->>'level_id')::integer AS level_id, payload->>'mode' AS mode,
 payload->>'puzzle_revision' AS puzzle_revision, build_version, platform,
 bool_or(name='round_started') AS started, bool_or(name='round_finished') AS finished,
 bool_or(payload->>'outcome'='win') AS won,
 bool_or(payload->>'outcome'='timeout') AS timed_out,
 bool_or(payload->>'outcome'='abandoned') AS abandoned,
 max((payload->>'active_seconds')::numeric) FILTER (WHERE name='round_finished') AS active_seconds,
 max((payload->>'incorrect_actions')::integer) FILTER (WHERE name='round_finished') AS incorrect_actions
 FROM analytics.qa_events WHERE name IN ('round_started','round_finished') GROUP BY 1,2,3,4,5,6,7
)
SELECT level_id, mode, puzzle_revision, build_version, platform,
 count(*) FILTER (WHERE started) AS starts, count(*) FILTER (WHERE finished) AS finishes,
 count(*) FILTER (WHERE won) AS wins, count(*) FILTER (WHERE timed_out) AS timeouts,
 count(*) FILTER (WHERE abandoned) AS abandoned,
 count(*) FILTER (WHERE started AND NOT finished) AS incomplete,
 round(avg(active_seconds) FILTER (WHERE won),3) AS mean_win_seconds,
 round(avg(active_seconds) FILTER (WHERE timed_out),3) AS mean_timeout_seconds,
 sum(incorrect_actions) AS incorrect_actions
FROM rounds GROUP BY 1,2,3,4,5 ORDER BY level_id,mode,build_version""", 'table'),
    ('QA: Recent round results', """
SELECT occurred_at AS finished_utc, build_version, platform,
 (payload->>'level_id')::integer AS level_id, payload->>'mode' AS mode,
 payload->>'outcome' AS outcome,
 round((payload->>'active_seconds')::numeric,3) AS active_seconds,
 (payload->>'actions')::integer AS actions,
 (payload->>'incorrect_actions')::integer AS incorrect_actions,
 (payload->>'starting_faults')::integer AS starting_faults,
 payload->>'round_id' AS round_id, session_id
FROM analytics.qa_events WHERE name='round_finished'
ORDER BY occurred_at DESC,event_id DESC LIMIT 100""", 'table'),
    ('QA: Ad callbacks by attempt', """
SELECT min(occurred_at) AS first_event_utc, build_version, platform,
 count(*) FILTER (WHERE name='ad_requested') AS requests,
 count(*) FILTER (WHERE name='ad_loaded') AS loads,
 count(*) FILTER (WHERE name='ad_failed') AS failures,
 count(*) FILTER (WHERE name='ad_impression') AS impressions,
 count(*) FILTER (WHERE name='ad_revenue') AS paid_callbacks,
 count(*) FILTER (WHERE name='ad_closed') AS closes,
 payload->>'test_ad' AS test_ad, payload->>'attempt_id' AS attempt_id, install_id
FROM analytics.qa_events
WHERE name IN ('ad_requested','ad_loaded','ad_failed','ad_impression','ad_revenue','ad_closed')
GROUP BY install_id,payload->>'attempt_id',build_version,platform,payload->>'test_ad'
ORDER BY first_event_utc DESC LIMIT 100""", 'table'),
    ('QA: Paid callbacks (not real revenue)', """
SELECT occurred_at AS occurred_utc, build_version, platform,
 payload->>'attempt_id' AS attempt_id, payload->>'test_ad' AS test_ad,
 (payload->>'value_micros')::bigint AS value_micros,
 payload->>'currency' AS currency, payload->>'precision' AS precision
FROM analytics.qa_events WHERE name='ad_revenue'
ORDER BY occurred_at DESC,event_id DESC LIMIT 100""", 'table'),
    ('QA: Ingestion and upload delay', """
SELECT (received_at AT TIME ZONE 'UTC')::date AS received_day,
 build_version, platform, name, count(*) AS events,
 round(avg(extract(epoch FROM received_at-occurred_at)),1) AS mean_delay_seconds,
 max(received_at) AS last_received_utc
FROM analytics.qa_events GROUP BY 1,2,3,4 ORDER BY received_day DESC,build_version,name""", 'table'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', type=Path, default=Path('credentials.json'))
    parser.add_argument('--base-url', default='http://127.0.0.1:3300')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    credentials = json.loads(args.credentials.read_text(encoding='utf-8-sig'))
    session = None

    def api(method, path, payload=None):
        headers = {'Content-Type': 'application/json'}
        if session:
            headers['X-Metabase-Session'] = session
        request = urllib.request.Request(args.base_url.rstrip('/') + '/api' + path,
            method=method, headers=headers,
            data=json.dumps(payload).encode() if payload is not None else None)
        with urllib.request.urlopen(request, timeout=90) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    session = api('POST', '/session', {'username': credentials['dashboard_email'],
                                     'password': credentials['dashboard_password']})['id']
    try:
        dashboards = api('GET', '/dashboard')
        dashboards = dashboards.get('data', []) if isinstance(dashboards, dict) else dashboards
        dashboard = next((d for d in dashboards if d['name'] == TITLE), None)
        if dashboard is None:
            if args.verify_only:
                raise RuntimeError('QA dashboard has not been created')
            dashboard = api('POST', '/dashboard', {'name': TITLE, 'description': DESCRIPTION})
        dashboard = api('GET', f"/dashboard/{dashboard['id']}")
        placed_cards = [d for d in dashboard['dashcards'] if d.get('card_id')]
        existing = {d['card']['name']: d for d in placed_cards}
        if len(existing) != len(placed_cards):
            raise RuntimeError('Duplicate QA cards; review before reconciling')
        expected = {q[0] for q in QUESTIONS}
        if set(existing) - expected:
            raise RuntimeError('QA dashboard has custom cards; review before reconciling')
        databases = api('GET', '/database')['data']
        database = next(d for d in databases if d['name'] == 'Put It Back telemetry')
        cards = []
        for index, (name, sql, display) in enumerate(QUESTIONS):
            definition = {'name': name, 'display': display, 'description': DESCRIPTION,
                'visualization_settings': {},
                'dataset_query': {'database': database['id'], 'type': 'native',
                                  'native': {'query': sql, 'template-tags': {}}}}
            item = existing.get(name)
            if args.verify_only:
                if item is None:
                    raise RuntimeError('Missing QA card: ' + name)
                card = item['card']
                saved_query = card['dataset_query']
                # Current Metabase normalizes legacy native queries into MBQL stages.
                stages = saved_query.get('stages', [])
                saved_sql = saved_query.get('native', {}).get('query')
                if saved_query.get('lib/type') == 'mbql/query':
                    saved_sql = (stages[0].get('native') if len(stages) == 1
                                 and stages[0].get('lib/type') == 'mbql.stage/native' else None)
                if saved_query.get('database') != database['id'] or saved_sql != sql:
                    raise RuntimeError('Unexpected query for ' + name)
            elif item:
                card = api('PUT', f"/card/{item['card_id']}", definition)
            else:
                card = api('POST', '/card', definition)
            result = api('POST', f"/card/{card['id']}/query", {'parameters': []})
            if result.get('status') != 'completed':
                raise RuntimeError('Query failed: ' + name)
            print(f"PASS: {name} ({len(result['data']['rows'])} rows)", flush=True)
            # Three headline counts; detailed tables use the full width for readability.
            cards.append({'id': item['id'] if item else -(index+1), 'card_id': card['id'],
                'row': 0 if index < 3 else 4+(index-3)*8,
                'col': index*8 if index < 3 else 0,
                'size_x': 8 if index < 3 else 24, 'size_y': 4 if index < 3 else 8,
                'parameter_mappings': [], 'visualization_settings': {}})
            if not args.verify_only:
                # Attach each successful card immediately so a retry can recover partial setup.
                pending = [d for n, d in existing.items() if n not in {q[0] for q in QUESTIONS[:index+1]}]
                api('PUT', f"/dashboard/{dashboard['id']}",
                    {'description': DESCRIPTION, 'dashcards': cards + pending})
                # Metabase assigns positive dashcard IDs on save; retain them on the next update.
                saved = api('GET', f"/dashboard/{dashboard['id']}")
                saved_ids = {d['card_id']: d['id'] for d in saved['dashcards'] if d.get('card_id')}
                for placed in cards:
                    placed['id'] = saved_ids[placed['card_id']]
        print(f"QA dashboard: {args.base_url.rstrip('/')}/dashboard/{dashboard['id']}")
    finally:
        api('DELETE', '/session', {'session_id': session})


if __name__ == '__main__':
    main()
