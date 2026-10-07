"""Generate secrets once on the server. Never print them or store them in git."""
import json
import os
from pathlib import Path
import secrets

os.umask(0o077)
env = Path('.env')
if env.exists():
    raise SystemExit('.env already exists; retaining existing secrets')
values = {name: secrets.token_hex(32) for name in (
    'POSTGRES_PASSWORD', 'API_DB_PASSWORD', 'ANALYTICS_DB_PASSWORD',
    'METABASE_DB_PASSWORD', 'METABASE_ENCRYPTION_KEY', 'INGEST_KEY')}
values.update(BIND_IP='10.0.7.57', TELEMETRY_HOST='http://putitback.vdsolution.com',
              PUBLIC_TELEMETRY_URL='https://putitback.vdsolution.com')
env.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
Path('credentials.json').write_text(json.dumps({
    'dashboard_url': 'http://localhost:3300',
    'dashboard_email': 'admin@putitback.local',
    'dashboard_password': secrets.token_urlsafe(32) + 'Aa7!',
    'ingestion_key': values['INGEST_KEY'],
}, indent=2))
print('Created .env and credentials.json with mode 0600')
