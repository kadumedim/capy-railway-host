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
  echo "[start] Web terminal enabled on port ${PORT:-8080} (user: capy)."
fi

# --- 3c. Print the pairing link/code to the deploy logs ------------------
# Default on, so deploy -> click the link in the logs -> approve -> done.
# Dock rotates the code roughly every 10 minutes while unpaired, so keep watching;
# a paired dock shows no pairing box, so nothing is printed.
# Anyone who can read this project's logs can see the code and could approve it
# into THEIR org, so set PAIRING_IN_LOGS=false on shared projects.
# PAIRING_LOG_MINUTES=0 (default) watches forever; set N to stop after N minutes.
if [ "${PAIRING_IN_LOGS:-true}" = "true" ]; then
  (
    mins="${PAIRING_LOG_MINUTES:-0}"
    end=0; [ "$mins" -gt 0 ] && end=$(( $(date +%s) + mins * 60 ))
    last=""
    while [ "$end" -eq 0 ] || [ "$(date +%s)" -lt "$end" ]; do
      sleep 3
      # The dock draws a box with a QR next to the text; pull out just the link and code.
      pane="$(tmux capture-pane -p -J -t "$SESSION" 2>/dev/null)"
      url="$(echo "$pane" | grep -oE "https?://[A-Za-z0-9._~:/?#@!\$&'()*+,;=%-]+" | grep -i 'devices/link' | head -n1)"
      code="$(echo "$pane" | grep -oE 'Code[[:space:]]+[A-Z0-9]{3,}-[A-Z0-9]{3,}' | head -n1 | awk '{print $2}')"
      if [ -n "$url" ] && [ -n "$code" ] && [ "$url|$code" != "$last" ]; then
        echo "[pairing] Open this link to pair this host with Capy: $url (code $code)"
        last="$url|$code"
      fi
    done
  ) &
fi

# --- 4. Supervise: keep a tmux session running the dock -------------------
echo "[start] Dock supervisor running."

while true; do
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[start] (re)starting dock in tmux session '$SESSION'"
    tmux new-session -d -s "$SESSION" -x 200 -y 50 \
      "while true; do $DOCK_CMD; echo '[dock exited, restarting in 5s]'; sleep 5; done"
  fi
  sleep 10
done
