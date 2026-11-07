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

# --- 3c. Pairing helper: link in logs, auto-confirm, connected line --------
# Flow: deploy -> click the link printed in the logs -> approve in the browser -> done.
# - PAIRING_IN_LOGS (default true): print the pairing link/code. Dock rotates the
#   code about every 10 minutes while unpaired, so each new one is printed.
#   Anyone who can read this project's logs could approve it into THEIR org,
#   so set false on shared projects.
# - PAIRING_AUTO_CONFIRM (default true): after you approve in the browser, Dock asks
#   "Pair this machine with <workspace>?" in the terminal (default Yes). Answer it
#   with Enter so nobody needs a terminal. Set false to confirm by hand.
# - Always prints a line when Dock reports "Connected <device> in <workspace>".
# Answer Dock's "Pair this machine with <workspace>?" prompt with Yes.
# Enter alone would pick the default (No), so press "y" and verify what is selected.
confirm_pair() {
  local p tries
  tmux send-keys -t "$SESSION" y
  for tries in 1 2 3 4 5; do
    sleep 1
    p="$(tmux capture-pane -p -J -t "$SESSION" 2>/dev/null)"
    echo "$p" | grep -qi 'declined' && return 1
    echo "$p" | grep -qE 'Paired' && return 0
    # Submitted answer is printed on the line after the question.
    if echo "$p" | grep -A1 -E 'Pair this machine with .+\?' | tail -n1 | grep -qE '^[^A-Za-z]*Yes[[:space:]]*$'; then return 0; fi
    if echo "$p" | grep -A1 -E 'Pair this machine with .+\?' | tail -n1 | grep -qE '^[^A-Za-z]*No[[:space:]]*$'; then return 1; fi
    # Prompt still open: submit only if Yes is the highlighted option, else toggle.
    if echo "$p" | grep -qE '(●|\(•\)|\[x\]|>)[[:space:]]*Yes'; then
      tmux send-keys -t "$SESSION" Enter
    else
      tmux send-keys -t "$SESSION" Right
    fi
  done
  return 1
}

(
  last_pair=""; last_confirm=""; last_conn=""
  while true; do
    sleep 2
    pane="$(tmux capture-pane -p -J -t "$SESSION" 2>/dev/null)"
    [ -z "$pane" ] && continue

    if [ "${PAIRING_IN_LOGS:-true}" = "true" ]; then
      url="$(echo "$pane" | grep -oE "https?://[A-Za-z0-9._~:/?#@!\$&'()*+,;=%-]+" | grep -i 'devices/link' | head -n1)"
      code="$(echo "$pane" | grep -oE 'Code[[:space:]]+[A-Z0-9]{3,}-[A-Z0-9]{3,}' | head -n1 | awk '{print $2}')"
      if [ -n "$url" ] && [ -n "$code" ] && [ "$url|$code" != "$last_pair" ]; then
        echo "[pairing] Open this link to pair this host with Capy: $url (code $code)"
        last_pair="$url|$code"
      fi
    fi

    if [ "${PAIRING_AUTO_CONFIRM:-true}" = "true" ]; then
      q="$(echo "$pane" | grep -E 'Pair this machine with .+\?' | tail -n1 | sed -e 's/^[^A-Za-z]*//' -e 's/[[:space:]]*$//')"
      if [ -z "$q" ]; then
        last_confirm=""   # prompt gone (new pairing attempt will ask again)
      elif [ "$q" != "$last_confirm" ] && ! echo "$pane" | grep -qE 'Paired|declined'; then
        last_confirm="$q"
        echo "[pairing] Approved in browser. Confirming in the terminal: $q"
        echo "$pane" | grep -A3 -F "$q" | sed 's/^/[pairing]   | /'
        confirm_pair && echo "[pairing] Confirmed (Yes)" || echo "[pairing] Could not confirm automatically; open the web terminal or railway ssh and answer the prompt"
      fi
    fi

    conn="$(echo "$pane" | grep -E 'Connected[[:space:]]+[^[:space:]]' | tail -n1 | sed -e 's/^[^A-Za-z]*//' -e 's/[[:space:]]*$//')"
    if [ -n "$conn" ] && [ "$conn" != "$last_conn" ]; then
      echo "[pairing] $conn"
      last_conn="$conn"
    fi
  done
) &

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
