"""Pin the currently installed upstream images for repeatable deployment."""
import json
from pathlib import Path
import subprocess

path = Path('.env')
lines = path.read_text().splitlines()
for key, tag in [('POSTGRES_IMAGE', 'postgres:17-bookworm'),
                 ('CADDY_IMAGE', 'caddy:2-alpine'),
                 ('METABASE_IMAGE', 'metabase/metabase:latest')]:
    details = json.loads(subprocess.check_output(['docker', 'image', 'inspect', tag]))[0]
    digest = details['RepoDigests'][0]
    lines = [line for line in lines if not line.startswith(key + '=')]
    lines.append(key + '=' + digest)
    print(f'{key}={digest}')
path.write_text('\n'.join(lines) + '\n')
