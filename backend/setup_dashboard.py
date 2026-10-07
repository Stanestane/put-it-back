"""One-time private Metabase setup, with credentials kept in a mode-0600 file."""
import json
from pathlib import Path
import time
import urllib.request
import urllib.error

base = 'http://127.0.0.1:3300/api'
credentials = json.loads(Path('credentials.json').read_text())
env = dict(line.split('=', 1) for line in Path('.env').read_text().splitlines() if '=' in line)
session = None


def api(method, path, payload=None):
    headers = {'Content-Type': 'application/json'}
    if session:
        headers['X-Metabase-Session'] = session
    request = urllib.request.Request(base+path, method=method, headers=headers,
        data=json.dumps(payload).encode() if payload is not None else None)
    with urllib.request.urlopen(request, timeout=90) as response:
        data = response.read()
        return json.loads(data) if data else None


for attempt in range(120):
    try:
        if api('GET', '/health')['status'] == 'ok':
            break
    except (OSError, ValueError):
        pass
    time.sleep(5)
else:
    raise SystemExit('Metabase did not become healthy')

properties = api('GET', '/session/properties')
if properties.get('setup-token'):
    api('POST', '/setup', {
        'token': properties['setup-token'],
        'user': {'email': credentials['dashboard_email'], 'password': credentials['dashboard_password'],
                 'first_name': 'Put It Back', 'last_name': 'Admin'},
        'prefs': {'site_name': 'Put It Back Analytics', 'allow_tracking': False},
    })
session = api('POST', '/session', {'username': credentials['dashboard_email'],
                                 'password': credentials['dashboard_password']})['id']
databases = api('GET', '/database')['data']
db = next((d for d in databases if d['name'] == 'Put It Back telemetry'), None)
if db is None:
    db = api('POST', '/database', {
        'name': 'Put It Back telemetry', 'engine': 'postgres',
        'details': {'host': 'db', 'port': 5432, 'dbname': 'telemetry', 'user': 'analytics_reader',
                    'password': env['ANALYTICS_DB_PASSWORD'], 'ssl': False,
                    'schema-filters-type': 'inclusion', 'schema-filters-patterns': 'analytics'},
        'is_full_sync': True, 'is_on_demand': False,
    })
dashboards = api('GET', '/dashboard')
items = dashboards.get('data', []) if isinstance(dashboards, dict) else dashboards
if any(d['name'] == 'Game KPIs' for d in items):
    print('Dashboard already exists; retained existing configuration')
    raise SystemExit(0)
dashboard = api('POST', '/dashboard', {'name': 'Game KPIs',
    'description': 'UTC reporting. Production installations, not unique people. Empty until client telemetry is connected. Retention includes completed days only.'})
questions = [
    ('Audience: DAU / WAU / MAU', 'SELECT * FROM analytics.audience ORDER BY day DESC', 'table'),
    ('Exact-day retention', 'SELECT * FROM analytics.retention ORDER BY cohort_day DESC,day_number', 'table'),
    ('Sessions and playtime', 'SELECT * FROM analytics.engagement ORDER BY day DESC', 'table'),
    ('Level difficulty', 'SELECT * FROM analytics.levels ORDER BY level_id,mode', 'table'),
    ('Ad revenue by currency and precision', 'SELECT * FROM analytics.ad_revenue ORDER BY day DESC', 'table'),
    ('Ingestion and upload delay', 'SELECT * FROM analytics.ingestion ORDER BY received_day DESC', 'table'),
    ('First experience funnel', 'SELECT * FROM analytics.onboarding ORDER BY cohort_day DESC', 'table'),
    ('Ad delivery', 'SELECT * FROM analytics.ad_delivery ORDER BY day DESC', 'table'),
    ('ARPDAU and eCPM by currency', 'SELECT * FROM analytics.monetization ORDER BY day DESC', 'table'),
]
cards = []
for i, (title, sql, display) in enumerate(questions):
    card = api('POST', '/card', {
        'name': title, 'display': display, 'visualization_settings': {},
        'dataset_query': {'database': db['id'], 'type': 'native', 'native': {'query': sql, 'template-tags': {}}},
    })
    cards.append({'id': -(i+1), 'card_id': card['id'], 'row': (i//2)*8, 'col': (i%2)*12,
                  'size_x': 12, 'size_y': 8, 'parameter_mappings': [], 'visualization_settings': {}})
api('PUT', f"/dashboard/{dashboard['id']}", {'dashcards': cards})
credentials['dashboard_url'] = f"http://localhost:3300/dashboard/{dashboard['id']}"
Path('credentials.json').write_text(json.dumps(credentials, indent=2))
print(f"Configured Game KPIs dashboard (ID {dashboard['id']}) with {len(cards)} questions")
