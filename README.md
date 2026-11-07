# Capy Host on Railway

Runs a [Capy](https://capy.ai) **Dock** host on Railway, so you can pick it under **Run on** in Capy.

## One-time pairing (required after first deploy)

Dock pairing is an interactive browser approval, so it can't be automated.

1. Deploy the template.
2. Open a shell in the service (`railway ssh`, or the service's shell in the dashboard).
3. Run `tmux attach -t dock`.
4. Open the link / scan the QR / enter the code at <https://capy.ai/settings/devices>, choose your org, name the device, and approve. Only approve codes you generated.
5. Detach with `Ctrl-b d`. Done: the host shows online in Capy.

Pairing is stored in the volume (`/home/capy/.capy`), so redeploys and restarts stay paired.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `CAPY_DIRS` | `/home/capy/workspace` | Comma-separated folders linked to the dock (`--dir`). |
| `GH_TOKEN` | – | GitHub token for `gh` and git-over-https (repo access for threads). |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | – | Git identity for commits. |
| `ENABLE_SUDO` | `false` | `true` gives the `capy` user passwordless sudo. |
| `CAPY_AUTO_UPDATE` | `false` | `true` re-runs the Dock installer on every boot. |

## Notes

- Volume must be mounted at `/home/capy`.
- Run one replica only; one user can run one Capy device.
- Threads run with the `capy` user's permissions and can see all service variables. Don't put secrets in this service you wouldn't give to Capy.
- Check health: `capy dock doctor`, `capy dock status`.
- Unpair: **Revoke device** in Capy device settings.

## Publishing as a Railway template

1. Push this folder to a GitHub repo.
2. In Railway: create a project, **+ New > GitHub Repo**, pick the repo.
3. Service **Settings > Volumes**: add a volume at `/home/capy`.
4. Add variables from the table above (leave `GH_TOKEN` blank in the template; mark it as user-supplied).
5. Workspace **Settings > Templates > Create Template** (or Project settings > "Generate Template from Project"), select the project, publish.
