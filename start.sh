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

# --- 2. Git / GitHub: nothing to do here ---------------------------------
# Log in once from a shell (`gh auth login`, `gh auth setup-git`,
# `git config --global user.name/email`). It is stored in the volume.

# --- 3. Build the dock command -------------------------------------------
DIR_ARGS=()
IFS=',' read -ra _dirs <<< "$CAPY_DIRS"
for d in "${_dirs[@]}"; do
  d="$(echo "$d" | xargs)"; [ -z "$d" ] && continue
  mkdir -p "$d"; DIR_ARGS+=(--dir "$d")
done
DOCK_CMD="capy dock --verbose ${DIR_ARGS[*]@Q}"

# --- 3b. Password-protected web terminal (pairing + gh login from browser) ---
# Only starts if TERMINAL_PASSWORD is set: an exposed pairing code could be
# approved by someone else and hijack this host.
if [ -n "${TERMINAL_PASSWORD:-}" ]; then
  (
    while true; do
      # tmux attach fails until the supervisor below has created the session.
      ttyd -W -d 1 -p "${PORT:-8080}" -c "capy:${TERMINAL_PASSWORD}" \
        bash -lc 'until tmux has-session -t dock 2>/dev/null; do sleep 1; done; exec tmux attach -t dock'
      echo "[start] ttyd exited, restarting in 5s"; sleep 5
    done
  ) &
  echo "[start] Web terminal on port ${PORT:-8080} (user: capy). Open the service's public URL."
else
  echo "[start] TERMINAL_PASSWORD not set: web terminal disabled (use railway ssh)."
fi

# --- 3c. Print the pairing link/code to the deploy logs ------------------
# Default on, so deploy -> click the link in the logs -> approve -> done.
# Anyone who can read this project's logs can see the code and could approve it
# into THEIR org, so set PAIRING_IN_LOGS=false on shared projects.
# Only runs for the first PAIRING_LOG_MINUTES after each container start, and
# only prints when the dock screen mentions pairing and has changed.
if [ "${PAIRING_IN_LOGS:-true}" = "true" ]; then
  (
    end=$(( $(date +%s) + ${PAIRING_LOG_MINUTES:-15} * 60 ))
    last=""
    while [ "$(date +%s)" -lt "$end" ]; do
      sleep 3
      screen="$(tmux capture-pane -p -J -t "$SESSION" 2>/dev/null | sed -e 's/[[:space:]]*$//' | cat -s)"
      if echo "$screen" | grep -qi 'pair' && [ "$screen" != "$last" ]; then
        echo "[pairing] ======== Capy Dock pairing (open the link, approve) ========"
        echo "$screen"
        echo "[pairing] ============================================================"
        last="$screen"
      fi
    done
  ) &
fi

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
