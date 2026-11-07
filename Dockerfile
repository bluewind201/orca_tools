# Paseo daemon + web UI (Docker Desktop on Windows, or a NAS) with the three agent CLIs this team uses (Gemini = PM, Claude = 개발·리뷰, Codex = 디자인)
# and the AI 팀 회의실 page. Built on the official image, which already has node, git, gosu and tini.
FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ripgrep jq less nano python3; \
    rm -rf /var/lib/apt/lists/*

# GitHub CLI (amd64 or arm64)
ARG GH_VERSION=2.62.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" | tar -xz -C /tmp; \
    mv /tmp/gh_${GH_VERSION}_linux_${arch}/bin/gh /usr/local/bin/gh; \
    rm -rf /tmp/gh_*

RUN set -eux; \
    npm install -g @anthropic-ai/claude-code @openai/codex @google/gemini-cli; \
    npm cache clean --force

COPY meeting-room /opt/meeting-room
COPY nas-entrypoint.sh /usr/local/bin/nas-entrypoint.sh
# Strip Windows line endings in case the repo was cloned with autocrlf
RUN sed -i 's/\r$//' /usr/local/bin/nas-entrypoint.sh && chmod +x /usr/local/bin/nas-entrypoint.sh

EXPOSE 6767 6769
# Stay root: nas-entrypoint maps the paseo user to the NAS uid, then the base entrypoint drops to it.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/nas-entrypoint.sh"]
