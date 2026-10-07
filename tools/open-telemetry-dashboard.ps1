$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$knownHosts = Join-Path $projectDirectory 'verification/server_known_hosts'
if (-not (Test-Path -LiteralPath $knownHosts)) {
    throw 'The verified server host-key file is missing. Obtain it from the server administrator before connecting.'
}
Write-Host 'Connect OpenVPN first. Enter the Ubuntu server password when SSH asks.'
Write-Host 'Keep this window open, then visit http://localhost:3300 in your browser.'
Write-Host 'Dashboard credentials are separate from your Ubuntu login; see backend/README.md.'
& ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$knownHosts" -L 3300:127.0.0.1:3300 stane@10.0.7.57
exit $LASTEXITCODE
