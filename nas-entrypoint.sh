#!/usr/bin/env bash
# Wrapper around Paseo's own entrypoint (Docker Desktop on Windows, or a Synology NAS):
#  1. run the paseo user as the NAS user (PUID/PGID) so mounted folders stay editable from the host (NAS: your DSM uid; Windows: leave 1000)
#  2. register Gemini as an ACP provider (Paseo has no built-in Gemini)
#  3. start the AI 팀 회의실 page on :6769
#  4. hand over to /usr/local/bin/paseo-docker-entrypoint, which starts the daemon as paseo
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
HOME_DIR=/home/paseo
export PASEO_HOME="${PASEO_HOME:-$HOME_DIR/.paseo}"

if [[ "$(id -u)" != "0" ]]; then
  echo "[nas] must start as root (remove 'user:' from docker-compose.yml)" >&2
  exit 1
fi
if [[ "$PUID" == "0" ]]; then
  echo "[nas] PUID=0 is not supported. Use your DSM user's uid (run 'id' over SSH)." >&2
  exit 1
fi

[[ "$(id -g paseo)" == "$PGID" ]] || groupmod -o -g "$PGID" paseo
[[ "$(id -u paseo)" == "$PUID" ]] || usermod -o -u "$PUID" paseo

for d in "$HOME_DIR" /workspace; do
  mkdir -p "$d"
  # Only chown when the folder isn't writable yet. Docker Desktop's Windows folders are writable
  # but always report root as owner, so a blanket chown there would rerun (slowly) on every start.
  if [[ "$(stat -c %u "$d")" != "$PUID" ]] && ! gosu paseo test -w "$d"; then
    echo "[nas] fixing owner of $d → $PUID:$PGID"
    chown -R "$PUID:$PGID" "$d" || true
  fi
  chmod u+rwx "$d" || true
done

if ! gosu paseo test -w "$HOME_DIR" || ! gosu paseo test -w /workspace; then
  cat >&2 <<MSG
[nas] ERROR: uid $PUID cannot write to $HOME_DIR or /workspace.
[nas] Synology ACLs usually cause this. Over SSH on the NAS run (adjust the path):
[nas]   sudo synoacltool -del /volume1/docker/orca/paseo-home
[nas]   sudo synoacltool -del /volume1/docker/orca/workspace
[nas]   sudo chown -R $PUID:$PGID /volume1/docker/orca/paseo-home /volume1/docker/orca/workspace
[nas] then restart the container. Waiting so the container doesn't crash-loop.
MSG
  exec sleep infinity
fi

# Gemini via ACP. Only adds the provider when it's missing, so your own edits to config.json stay.
gosu paseo mkdir -p "$PASEO_HOME"
gosu paseo env PASEO_HOME="$PASEO_HOME" node -e '
  const fs = require("fs"), p = process.env.PASEO_HOME + "/config.json"
  let c = {}
  try { c = JSON.parse(fs.readFileSync(p, "utf8")) } catch (e) { if (e.code !== "ENOENT") { console.error("[nas] config.json unreadable, leaving it alone:", e.message); process.exit(0) } }
  c.agents ??= {}; c.agents.providers ??= {}
  if (!c.agents.providers.gemini) {
    c.agents.providers.gemini = { extends: "acp", label: "Gemini", command: ["gemini", "--acp"] }
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n")
    console.log("[nas] added Gemini (ACP) provider to " + p)
  }
'

if [[ "${MEETING_ROOM:-on}" != "off" ]]; then
  gosu paseo mkdir -p "$HOME_DIR/meeting-room"
  [[ -f "$HOME_DIR/meeting-room/roles.json" ]] || gosu paseo cp /opt/meeting-room/roles.json "$HOME_DIR/meeting-room/roles.json"
  (
    sleep 5
    while true; do
      gosu paseo env HOME="$HOME_DIR" PASEO_HOME="$PASEO_HOME" MEETING_ROOM_ROLES="$HOME_DIR/meeting-room/roles.json" \
        node /opt/meeting-room/server.mjs || true
      echo "[meeting-room] exited, restarting in 5s" >&2
      sleep 5
    done
  ) &
fi

exec /usr/local/bin/paseo-docker-entrypoint
