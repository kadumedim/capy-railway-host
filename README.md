# Capy Host on Railway

Runs a [Capy](https://capy.ai) **Dock** host on Railway, so you can pick it under **Run on** in Capy.

## Setup (after deploying the template)

1. Open the service's public URL (Railway generates a domain; `PORT` is `8080`).
2. Log in with user `capy` and the generated `TERMINAL_PASSWORD` (see the service's Variables tab).
3. The terminal shows the Dock pairing link, QR and code. Open the link (or go to <https://capy.ai/settings/devices> > Pair a device), pick your org, name the device, choose the "setting up right now" option and approve. Only approve codes you generated.
4. Optional GitHub login: press `Ctrl-b c` for a new shell window, then
   ```bash
   gh auth login        # GitHub.com > HTTPS > login with a web browser (device code)
   gh auth setup-git
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   capy dock doctor
   ```
5. Done. The host shows online in Capy. Pairing and logins are stored on the volume, so redeploys keep them. Detach/close the tab any time (`Ctrl-b d`); Dock keeps running.

No browser? `railway ssh`, `su - capy`, `tmux attach -t dock` works too.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `TERMINAL_PASSWORD` | (template generates it) | Password for the web terminal. **If unset, the web terminal is disabled.** |
| `PORT` | `8080` | Port the web terminal listens on. |
| `CAPY_DIRS` | `/home/capy/workspace` | Comma-separated folders linked to the dock (`--dir`). |
| `ENABLE_SUDO` | `false` | `true` gives the `capy` user passwordless sudo. |
| `CAPY_AUTO_UPDATE` | `false` | `true` re-runs the Dock installer on every boot. |

## Security notes

- Anyone with the web terminal password gets a shell as `capy` and can approve pairing. Use a long random password; consider removing the public domain after setup.
- Threads run with the `capy` user's permissions and can see all service variables, including `TERMINAL_PASSWORD`.
- Run one replica only; one user can run one Capy device.
- Volume must be mounted at `/home/capy`.
- Unpair: **Revoke device** in Capy device settings.

## Publishing as a Railway template

1. Create a project from this GitHub repo, attach a volume at `/home/capy`, and generate a public domain.
2. Add variables: `PORT=8080`, `TERMINAL_PASSWORD=${{secret(32)}}` (Railway generates a random value per deploy), plus optional others.
3. Project Settings > Generate Template from Project, review, publish.
