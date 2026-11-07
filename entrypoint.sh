auto #!/bin/bash
# Runs as root: fix ownership of the Railway volume (mounted root-owned),
# then drop to the unprivileged `capy` user, which Dock requires.
set -euo pipefail

CAPY_USER="${CAPY_USER:-capy}"
CAPY_HOME="$(getent passwd "$CAPY_USER" | cut -d: -f6)"

mkdir -p "$CAPY_HOME/workspace"
chown "$CAPY_USER:$CAPY_USER" "$CAPY_HOME"
# Only recurse when ownership is wrong (cheap on later boots).
if [ "$(stat -c %U "$CAPY_HOME/workspace")" != "$CAPY_USER" ] || \
   [ -d "$CAPY_HOME/.capy" -a "$(stat -c %U "$CAPY_HOME/.capy")" != "$CAPY_USER" ]; then
  chown -R "$CAPY_USER:$CAPY_USER" "$CAPY_HOME"
fi

# A fresh volume hides the image's skeleton files; restore them.
for f in .bashrc .profile .bash_logout; do
  [ -e "$CAPY_HOME/$f" ] || cp "/etc/skel/$f" "$CAPY_HOME/$f" && chown "$CAPY_USER:$CAPY_USER" "$CAPY_HOME/$f"
done

if [ "${ENABLE_SUDO:-false}" = "true" ]; then
  echo "$CAPY_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/capy
  chmod 440 /etc/sudoers.d/capy
else
  rm -f /etc/sudoers.d/capy
fi

# Pass the environment through (GH_TOKEN, CAPY_DIRS, ...) and drop privileges.
exec gosu "$CAPY_USER" env HOME="$CAPY_HOME" USER="$CAPY_USER" /usr/local/bin/start.sh "$@"
