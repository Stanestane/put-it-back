"""Exercise Caddy -> API -> PostgreSQL; remove only this script's synthetic IDs."""
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone
from uuid import uuid4
import urllib.request
import urllib.error

env = dict(line.split('=', 1) for line in Path('.env').read_text().splitlines() if '=' in line)
base = env.get('PUBLIC_TELEMETRY_URL', 'https://putitback.vdsolution.com').rstrip('/')
if not base.startswith('https://'):
    raise SystemExit('Public ingestion verification requires HTTPS')
install_id, event_id = str(uuid4()), str(uuid4())
event = {'event_id': event_id, 'schema_version': 1, 'install_id': install_id,
         'session_id': str(uuid4()), 'sequence': 0, 'occurred_at': datetime.now(timezone.utc).isoformat(),
         'build_version': 'proxy-smoke-test', 'platform': 'android', 'environment': 'test',
         'payload': {'name': 'first_open'}}


def post(body, key):
    req = urllib.request.Request(base+'/v1/events/batch', data=body,
        headers={'User-Agent': 'PutItBackTelemetry/1.0', 'Content-Type': 'application/json',
                 'Authorization': 'Bearer '+key})
    return urllib.request.urlopen(req, timeout=15)


try:
    body = json.dumps({'events': [event]}).encode()
    with post(body, env['INGEST_KEY']) as response:
        assert json.load(response)['accepted'] == [event_id]
    with post(body, env['INGEST_KEY']) as response:
        assert json.load(response)['duplicates'] == [event_id]
    for data, key, status in [(body, 'incorrect', 401), (b' '*262145, env['INGEST_KEY'], 413)]:
        try:
            post(data, key)
            raise AssertionError(f'Expected HTTP {status}')
        except urllib.error.HTTPError as error:
            assert error.code == status, error.code
    print('PASS: proxied ingestion, retry deduplication, authentication, payload limit')
finally:
    # IDs are generated UUIDs above, never supplied externally.
    sql = f"DELETE FROM events WHERE install_id='{install_id}'; DELETE FROM installations WHERE install_id='{install_id}';"
    subprocess.run(['docker','compose','exec','-T','db','psql','-U','postgres','-d','telemetry',
                    '-v','ON_ERROR_STOP=1','-c',sql], check=True, stdout=subprocess.DEVNULL)
