# Accessing the dashboards

[Backend index](../README.md) · [Report definitions](reporting.md)

Both dashboards run in Metabase on Ubuntu server `10.0.7.57`. Each computer opens
its own SSH tunnel, then uses a browser on that same computer. The game continues
collecting data independently of these tunnels.

| Dashboard | Browser address while the tunnel is open |
| --- | --- |
| Game KPIs — production | http://localhost:3300/dashboard/2 |
| Game QA — test data | http://localhost:3300/dashboard/3 |

## Another computer on the server's local network

OpenVPN is **not required** if that computer can already reach `10.0.7.57` on TCP
port 22. Guest Wi-Fi or a different VLAN may not have that route; in that case ask
the network administrator for SSH access to the server, or use the configured VPN.
No router port forwarding or public IP change is needed for this access method.

You need an SSH client, authorized Ubuntu login credentials (the existing operator
account is `stane`), and a Metabase email/password. The SSH and Metabase logins are
separate. Obtain the required credentials from the project owner; no credentials
are stored in this guide. The game project, Godot, and Android tools are not needed
on the viewing computer.

1. Open **PowerShell** on Windows, or **Terminal** on macOS/Linux. Check that
   `ssh -V` works. If Windows cannot find it, enable **OpenSSH Client** in Windows
   Optional Features. On Windows, you can check server connectivity with:

   ```powershell
   Test-NetConnection 10.0.7.57 -Port 22
   ```

   `TcpTestSucceeded : True` confirms that this computer can reach SSH.

2. Start the tunnel with this single command (works from any directory):

   ```sh
   ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=ask -L 127.0.0.1:3300:127.0.0.1:3300 stane@10.0.7.57
   ```

3. On the first connection, check the server's ED25519 fingerprint before typing
   `yes`. The key verified for this deployment is:

   ```text
   SHA256:k7zSB2tVA7YH8qqDkasRWvce3deVA5rx94IpMYoWvoQ
   ```

   SSH saves the accepted key in that user's normal `~/.ssh/known_hosts` file.
   If a different key is presented, have the server administrator verify it before
   continuing. Do not bypass a changed-key warning. The fingerprint is public
   identification information, not a password.

4. Enter the **Ubuntu password for `stane`** when prompted. Password entry may not
   display characters. After successful login, this command normally stays silent:
   `-N` opens the tunnel without starting a remote shell. Leave this terminal open.
   A computer with working SSH key authentication may not need a password prompt.

5. Open either dashboard address above in Chrome or another browser, and sign in
   using the **Metabase email and password**. Both dashboards use the same login.
   The QA dashboard contains test runs; production reports exclude those runs.

Press **Ctrl+C** in the tunnel terminal when finished. Closing it or suspending the
computer disconnects that computer's dashboard access; it does not stop Metabase,
ingestion, or anyone else's tunnel. Rerun the command to reconnect.

Metabase listens on the server's loopback interface only. Therefore
`http://10.0.7.57:3300` is not a dashboard address for another LAN computer.
`localhost` in the links means the computer running your browser, not the server
and not this project's development PC. The public `putitback.vdsolution.com` domain
serves the ingestion API, not Metabase. TCP 3300 remains private; only SSH port 22
needs to be reachable from the viewing computer.

## Existing development PC

Offsite, first connect its existing OpenVPN profile. On the server LAN, use the
direct route if available. Then run:

```powershell
& 'E:\Godot Projects\Put It Back\tools\open-telemetry-dashboard.ps1'
```

The helper uses the separately verified, Git-ignored
`verification/server_known_hosts` file and strict host-key checking. It resolves
the project directory itself, including paths containing spaces. A fresh Git clone
does not contain that private workstation file; use the first-connection procedure
above, or obtain the verified file from the project owner to use the helper.

On this PC, the protected `verification/put-it-back-credentials.json` record contains
the `dashboard_email` and `dashboard_password` fields. The server copy is root-only
at `/opt/put-it-back/backend/credentials.json`. Share only the required login with
an authorized viewer, not the entire credentials file, which contains other secrets.

## Troubleshooting

| What happens | What to check |
| --- | --- |
| Connection times out before any prompt | Confirm TCP 22 is reachable; check LAN/VLAN routing or connect OpenVPN when offsite. |
| `Permission denied` | Check the Ubuntu username/password or SSH key, not the Metabase password. |
| No prompt and no error; the terminal stays open | Try the dashboard URL. A successful tunnel is silent, and key authentication can skip the password prompt. |
| `Host key verification failed` | For the project helper, confirm its verified host-key file exists. The helper fixes the previous problem with spaces in the project path. For a changed key, obtain administrator verification. |
| `Address already in use` / cannot bind port 3300 | An existing tunnel may already work. Otherwise use local port 3301 as below. |
| Browser says connection refused | Keep the tunnel terminal open on the same computer as the browser; reconnect after sleep or a VPN disconnect. |
| SSH prints `channel ... connect failed: Connection refused` | SSH reached Ubuntu, but Metabase's server-side port is unavailable; ask the operator to check `docker compose ps` and Metabase health. |
| Most production reports are empty | Open the QA dashboard for test runs. Production reports need opted-in release clients; retention needs completed return days. |

If local port 3300 is occupied, use:

```sh
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=ask -L 127.0.0.1:3301:127.0.0.1:3300 stane@10.0.7.57
```

Then open `http://localhost:3301/dashboard/2` or
`http://localhost:3301/dashboard/3`. Only the local browser port changes.
