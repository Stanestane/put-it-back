"""Check authenticated dashboard queries without printing credentials or results."""
import json
from pathlib import Path
import urllib.request

base = 'http://127.0.0.1:3300/api'
credentials = json.loads(Path('credentials.json').read_text())
session = None


def api(method, path, payload=None):
    headers = {'Content-Type': 'application/json'}
    if session:
        headers['X-Metabase-Session'] = session
    req = urllib.request.Request(base+path, method=method, headers=headers,
        data=json.dumps(payload).encode() if payload is not None else None)
    with urllib.request.urlopen(req, timeout=60) as response:
        data = response.read()
        return json.loads(data) if data else None


session = api('POST', '/session', {'username': credentials['dashboard_email'],
                                 'password': credentials['dashboard_password']})['id']
dashboard_id = credentials['dashboard_url'].rsplit('/', 1)[1]
dashboard = api('GET', '/dashboard/' + dashboard_id)
cards = [c for c in dashboard['dashcards'] if c.get('card_id')]
assert len(cards) == 9, f'Expected 9 dashboard cards, found {len(cards)}'
for item in cards:
    result = api('POST', f"/card/{item['card_id']}/query", {'parameters': []})
    assert result.get('status') == 'completed', f"Card {item['card_id']} failed"
    print(f"PASS: {item['card']['name']} ({len(result['data']['rows'])} rows)")
api('DELETE', '/session', {'session_id': session})
print('All nine dashboard queries succeeded')
