$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$knownHosts = Join-Path $projectDirectory 'verification/server_known_hosts'
if (-not (Test-Path -LiteralPath $knownHosts)) {
    throw 'The verified server host-key file is missing. Obtain it from the server administrator before connecting.'
}
Write-Host 'Connect OpenVPN when offsite; it is not needed if this PC can reach 10.0.7.57 on the LAN.'
Write-Host 'Enter the Ubuntu server password when SSH asks. A connected tunnel normally stays silent.'
Write-Host 'Keep this window open. Production: http://localhost:3300/dashboard/2'
Write-Host 'QA test data: http://localhost:3300/dashboard/3'
Write-Host 'Dashboard credentials are separate from your Ubuntu login; see backend/README.md.'
# OpenSSH parses spaces in UserKnownHostsFile as separate filenames, even when
# PowerShell passes the option as one argument. Use a relative path from the
# project directory so this also works under Windows PowerShell 5.1.
Push-Location -LiteralPath $projectDirectory
try {
    & ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=verification/server_known_hosts -L 127.0.0.1:3300:127.0.0.1:3300 stane@10.0.7.57
    $sshExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $sshExitCode
