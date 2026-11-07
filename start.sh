#!/bin/bash
# Runs as the `capy` user. Installs Dock if missing, then keeps `capy dock`
# alive inside a tmux session so pairing can be done interactively once
# (docs: the first run must be interactive so the pairing code stays out of logs).
set -uo pipefail

export PATH="$HOME/.capy/bin:$PATH"
SESSION="dock"
CAPY_DIRS="${CAPY_DIRS:-$HOME/workspace}"

# --- 1. Install / update Dock (lives on the volume under ~/.capy) ---------
if [ ! -x "$HOME/.capy/bin/capy" ] || [ "${CAPY_AUTO_UPDATE:-false}" = "true" ]; then
  echo "[start] Installing Dock CLI..."
  until curl -fsSL https://downloads.capy.ai/stable/dock/install.sh | sh; do
    echo "[start] Install failed, retrying in 15s..."; sleep 15
  done
fi

# Make `capy` available in interactive shells (railway ssh / web shell).
grep -q '.capy/bin' "$HOME/.bashrc" 2>/dev/null || \
  echo 'export PATH="$HOME/.capy/bin:$PATH"' >> "$HOME/.bashrc"

# --- 2. Git / GitHub setup (optional) ------------------------------------
[ -n "${GIT_USER_NAME:-}" ]  && git config --global user.name  "$GIT_USER_NAME"
[ -n "${GIT_USER_EMAIL:-}" ] && git config --global user.email "$GIT_USER_EMAIL"
if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git 2>/dev/null || true   # lets git over https use the token
fi

# --- 3. Build the dock command -------------------------------------------
DIR_ARGS=()
IFS=',' read -ra _dirs <<< "$CAPY_DIRS"
for d in "${_dirs[@]}"; do
  d="$(echo "$d" | xargs)"; [ -z "$d" ] && continue
  mkdir -p "$d"; DIR_ARGS+=(--dir "$d")
done
DOCK_CMD="capy dock --verbose ${DIR_ARGS[*]@Q}"

# --- 4. Supervise: keep a tmux session running the dock -------------------
cat <<EOF
[start] Dock supervisor running.
[start] FIRST TIME ONLY: open a shell in this service (Railway > service > ... > "Open shell",
[start] or: railway ssh) and run:  tmux attach -t $SESSION   -> follow the pairing link/code.
EOF

while true; do
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[start] (re)starting dock in tmux session '$SESSION'"
    tmux new-session -d -s "$SESSION" -x 200 -y 50 \
      "while true; do $DOCK_CMD; echo '[dock exited, restarting in 5s]'; sleep 5; done"
  fi
  sleep 10
done
