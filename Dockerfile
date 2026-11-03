# Orca headless server for Synology NAS (x86_64, e.g. DS225+)
# Node.js comes from the official node image; the rest is Ubuntu 24.04 (same base Orca tests headless serve on).
FROM node:22-bookworm-slim AS node

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Electron runtime libs + Xvfb (Orca serve needs a virtual display) + dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client jq procps util-linux tini \
      xvfb xauth dbus-x11 \
      libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 \
      libatk-bridge2.0-0 libuuid1 libsecret-1-0 libasound2t64 libgbm1 libdrm2 \
      libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 \
      python3 python3-gi gir1.2-atspi-2.0 at-spi2-core xdotool xclip \
      ripgrep less nano tzdata \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 + npm
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version && npm --version

# GitHub CLI (for PRs from agents)
ARG GH_VERSION=2.62.0
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /tmp && mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh && rm -rf /tmp/gh_*

# Orca: download the Linux AppImage and unpack it (Synology Docker has no FUSE)
ARG ORCA_URL=https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage
RUN cd /tmp && curl -fL -o orca.AppImage "$ORCA_URL" \
    && chmod +x orca.AppImage && ./orca.AppImage --appimage-extract >/dev/null \
    && mv squashfs-root /opt/orca && rm orca.AppImage \
    && ln -s /opt/orca/resources/bin/orca-ide /usr/local/bin/orca-ide \
    && ln -s /opt/orca/resources/bin/orca-ide /usr/local/bin/orca

# AI agent CLIs (Claude Code, Codex, Gemini). Logins are stored in the home volume.
RUN npm install -g @anthropic-ai/claude-code @openai/codex @google/gemini-cli \
    && npm cache clean --force

# Unprivileged user; UID/GID are remapped at start to match the NAS folder owner
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g 1000 orca && useradd -m -u 1000 -g orca -s /bin/bash orca \
    && mkdir -p /workspace && chown orca:orca /workspace

# AI 팀 회의실 (2D view of Orca orchestration runs), served on port 6769
COPY meeting-room /opt/meeting-room

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 6768 6769
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
