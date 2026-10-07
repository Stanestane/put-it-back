param([string]$CredentialsPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $CredentialsPath) { $CredentialsPath = Join-Path $projectRoot 'verification/put-it-back-credentials.json' }
# Only the ingestion credential is copied. Never print credentials or package the source file.
$credentials = Get-Content -LiteralPath $CredentialsPath -Raw | ConvertFrom-Json
if (-not $credentials.ingestion_key -or $credentials.ingestion_key.Length -lt 16) {
    throw 'An ingestion_key of at least 16 characters is required.'
}
$config = [ordered]@{
    endpoint = 'https://putitback.vdsolution.com/v1/events/batch'
    ingestion_key = $credentials.ingestion_key
}
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'resources/telemetry_config.json') -Encoding utf8NoBOM
Write-Output 'Telemetry build configuration written (ingestion key only; gitignored).'
