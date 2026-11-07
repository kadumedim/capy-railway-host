# Capy host (Dock CLI) for Railway.
# Debian (glibc) is required: Dock does not support Alpine/musl.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    CAPY_USER=capy

# git + gh are used by threads and checked by `capy dock doctor`.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg openssh-client tmux gosu sudo \
      build-essential python3 python3-pip jq unzip procps less nano \
 && mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 # Node.js (most repos Capy works on need it)
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# ttyd: web terminal so pairing / gh login can be done from the browser.
RUN arch="$(uname -m)" \
 && curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.${arch}" \
 && chmod +x /usr/local/bin/ttyd

# Dock refuses to install/run as root, so use a dedicated user.
# Threads get this user's permissions (passwordless sudo is optional, see ENABLE_SUDO).
RUN useradd --create-home --shell /bin/bash --uid 1000 "$CAPY_USER"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/start.sh

# Railway volume should be mounted at /home/capy (holds ~/.capy: pairing, worktrees, install).
WORKDIR /home/capy
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
