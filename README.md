# Capy Host on Railway

Runs a [Capy](https://capy.ai) **Dock** host on Railway, so you can pick it under **Run on** in Capy.

## Setup: pair from the deploy logs

1. Deploy the template and open the service's **Deploy Logs**.
2. Find the `[pairing]` lines and click the link (the code is also printed). Choose your org, name the device, pick "setting up right now" and approve.
3. Done. The host shows online in Capy and stays paired across redeploys (pairing is stored on the volume).

Pairing is one-time. If the host is already paired, no link is printed.

## Security

- The pairing link is printed in the logs, so anyone who can read the project's logs could approve it into their own Capy org until you pair. Pair right after deploying. On shared projects set `PAIRING_IN_LOGS=false` and use the web terminal below.
- After pairing, the link is useless; to invalidate a host, use **Revoke device** in Capy device settings.
- Threads run with the `capy` user's permissions and can see all of the service's variables.
- Run one replica only; one user can run one Capy device. The volume must be mounted at `/home/capy`.

## Variables (all optional)

| Variable | Default | Purpose |
|---|---|---|
| `PAIRING_IN_LOGS` | `true` | Print the pairing link/code in the deploy logs. |
| `PAIRING_LOG_MINUTES` | `15` | How long after each start to watch for the pairing prompt. |
| `CAPY_DIRS` | `/home/capy/workspace` | Comma-separated folders linked to the dock (`--dir`). |
| `ENABLE_SUDO` | `false` | `true` gives the `capy` user passwordless sudo. |
| `CAPY_AUTO_UPDATE` | `false` | `true` re-runs the Dock installer on every boot. |
| `TERMINAL_PASSWORD` | – | Enables a password-protected web terminal (user `capy`, needs a public domain and `PORT=8080`). Off if unset. |

## Optional: GitHub login / shell access

Capy may not need `gh` at all; try a thread first. If you need it, use the web terminal (set `TERMINAL_PASSWORD`, `PORT=8080`, generate a domain) or `railway ssh` > `su - capy` > `tmux attach -t dock`, press `Ctrl-b c` for a new window and run:

```bash
gh auth login        # GitHub.com > HTTPS > login with a web browser
gh auth setup-git
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
capy dock doctor
```

Everything is stored on the volume. Remove the domain and `TERMINAL_PASSWORD` afterwards if you don't want a public terminal.

## Publishing as a Railway template

1. Create a project from this GitHub repo and attach a volume at `/home/capy`.
2. Project Settings > Generate Template from Project. In the editor, make sure the volume mount is `/home/capy`, and remove `TERMINAL_PASSWORD`, `PORT` and any public domain (the logs cover pairing).
3. Publish, then deploy it once yourself to confirm the `[pairing]` lines show up.
